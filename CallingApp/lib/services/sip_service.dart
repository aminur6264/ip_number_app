import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:sip_ua/sip_ua.dart';

import '../models/sip_config.dart';

/// App-wide SIP state machine. Wraps [SIPUAHelper] and re-emits its events as
/// a [ChangeNotifier] so the screens can rebuild on registration and call
/// state changes.
class SipService extends ChangeNotifier implements SipUaHelperListener {
  SipService._internal() {
    _helper.addSipUaHelperListener(this);
  }

  static final SipService instance = SipService._internal();

  factory SipService() => instance;

  final SIPUAHelper _helper = SIPUAHelper();

  SipConfig? _config;
  RegistrationStateEnum _registrationState = RegistrationStateEnum.NONE;
  String? _registrationError;
  Call? _activeCall;
  bool _signedIn = false;
  bool _connecting = false;
  bool _muted = false;
  bool _onHold = false;
  bool _speakerOn = true;
  DateTime? _connectedAt;
  String? _lastEndReason;
  bool _closing = false;

  RTCVideoRenderer? _remoteRenderer;

  SipConfig? get config => _config;
  RegistrationStateEnum get registrationState => _registrationState;
  String? get registrationError => _registrationError;
  Call? get activeCall => _activeCall;
  bool get signedIn => _signedIn;
  bool get connecting => _connecting;
  bool get muted => _muted;
  bool get onHold => _onHold;
  bool get speakerOn => _speakerOn;
  String? get lastEndReason => _lastEndReason;
  bool get registered => _registrationState == RegistrationStateEnum.REGISTERED;

  /// True when there is a live call that is ringing or established.
  bool get inCall => _activeCall != null;

  /// True when the active call is an incoming call not yet answered.
  bool get incomingCallPending =>
      _activeCall != null &&
      _activeCall!.session.direction == Direction.incoming &&
      (_activeCall!.state == CallStateEnum.CALL_INITIATION ||
          _activeCall!.state == CallStateEnum.PROGRESS);

  /// Remote identity (extension number) of the active call, if any.
  String? get remoteIdentity => _activeCall?.remote_identity;

  String? get remoteDisplayName => _activeCall?.remote_display_name;

  /// Elapsed time since the call was established, for the call timer.
  Duration? get callDuration =>
      _connectedAt == null ? null : DateTime.now().difference(_connectedAt!);

  /// Remote audio is routed through a renderer so it plays on every platform
  /// (on web a media element is required, on mobile this is harmless).
  RTCVideoRenderer get remoteRenderer {
    _remoteRenderer ??= RTCVideoRenderer();
    return _remoteRenderer!;
  }

  /// Load a previously saved config (shown pre-filled on the login screen).
  void restoreConfig(SipConfig? config) {
    if (config != null) {
      _config = config;
    }
  }

  /// Register with the PBX. Reports progress through [registrationState] /
  /// [registrationError]; watch this service for updates.
  Future<void> connect(SipConfig config) async {
    _config = config;
    _registrationError = null;
    _registrationState = RegistrationStateEnum.NONE;
    _connecting = true;
    notifyListeners();

    final settings = UaSettings()
      ..webSocketUrl = config.webSocketUrl
      ..uri = config.sipUri
      ..authorizationUser = config.extension
      ..password = config.password
      ..displayName = config.extension
      ..userAgent = 'CallingApp/1.0 (Flutter)'
      ..transportType = TransportType.WS
      ..register = true
      ..register_expires = 300
      // Matches the web demo, which sends DTMF as named telephone events.
      ..dtmfMode = DtmfMode.RFC2833;

    await _helper.start(settings);
  }

  /// Unregister and drop the WebSocket connection, then forget credentials.
  Future<void> signOut() async {
    try {
      if (_helper.registered) {
        await _helper.unregister();
      }
      _helper.stop();
    } finally {
      _signedIn = false;
      _connecting = false;
      _registrationState = RegistrationStateEnum.NONE;
      _activeCall = null;
      _resetCallUiState();
      notifyListeners();
    }
  }

  /// Tear down the SIP session because the app is being closed: send BYE for
  /// any live call (CANCEL / reject if it has not been answered yet) so the
  /// far end is not left hanging until its timeout, then drop the transport.
  /// Best-effort; never throws.
  Future<void> handleAppClosed() async {
    if (_closing) return;
    _closing = true;
    try {
      final call = _activeCall;
      if (call != null) {
        try {
          call.hangup();
        } catch (e) {
          if (kDebugMode) debugPrint('hangup on app close failed: $e');
        }
        // Give the BYE/CANCEL a moment to leave the socket before it closes.
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      _helper.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('teardown on app close failed: $e');
    } finally {
      _activeCall = null;
      _resetCallUiState();
      _closing = false;
    }
  }

  /// Place an audio call to [number] on the configured PBX domain.
  Future<bool> call(String number) async {
    final config = _config;
    if (config == null || number.isEmpty) return false;
    return _helper.call('sip:$number@${config.server}', voiceOnly: true);
  }

  void answer() {
    final call = _activeCall;
    if (call == null) return;
    call.answer(_helper.buildCallOptions(true));
  }

  /// Hang up, cancel or reject the active call depending on its state
  /// (mirrors the web demo behaviour).
  void hangup() {
    _activeCall?.hangup();
  }

  void toggleMute() {
    final call = _activeCall;
    if (call == null) return;
    if (_muted) {
      call.unmute(true);
    } else {
      call.mute(true);
    }
    // Optimistic; confirmed by MUTED/UNMUTED call events.
    _muted = !_muted;
    notifyListeners();
  }

  void toggleHold() {
    final call = _activeCall;
    if (call == null) return;
    if (_onHold) {
      call.unhold();
    } else {
      call.hold();
    }
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    try {
      await Helper.setSpeakerphoneOn(_speakerOn);
    } catch (e) {
      // Not supported on this platform (e.g. web); keep the flag for UI.
      if (kDebugMode) debugPrint('setSpeakerphoneOn failed: $e');
    }
    notifyListeners();
  }

  void sendDTMF(String digit) {
    if (digit.isEmpty) return;
    _activeCall?.sendDTMF(digit);
  }

  void _resetCallUiState() {
    _muted = false;
    _onHold = false;
    _connectedAt = null;
  }

  /// Translates the raw SIP failure cause (e.g. `Code: [403], Cause:
  /// Rejected, Reason: Forbidden`) into an actionable message, keeping the
  /// raw cause appended for support requests.
  String _describeRegistrationFailure(String? cause) {
    final code = RegExp(r'\[(\d{3})\]').firstMatch(cause ?? '')?.group(1);
    final suffix =
        cause == null || cause.isEmpty ? '' : '\nServer said: $cause';
    switch (code) {
      case '401':
      case '407':
        return 'Authentication failed (SIP $code): the server rejected this '
            'extension or password. Check your credentials.$suffix';
      case '403':
        return 'Registration rejected (SIP 403 Forbidden): the server refused '
            'this account. The password may be wrong for this extension, or '
            'the extension is already registered on another device or app — '
            'sign out elsewhere and try again.$suffix';
      case '404':
        return 'Extension not found (SIP 404): check the SIP server and '
            'extension number.$suffix';
      default:
        return 'Registration failed'
            '${code == null ? '' : ' (SIP $code)'}.$suffix';
    }
  }

  // --- SipUaHelperListener -------------------------------------------------

  @override
  void transportStateChanged(TransportState state) {
    if (state.state == TransportStateEnum.DISCONNECTED) {
      // The helper retries on its own; surface the drop in the UI.
      _registrationState = RegistrationStateEnum.UNREGISTERED;
    }
    notifyListeners();
  }

  @override
  void registrationStateChanged(RegistrationState state) {
    _registrationState = state.state ?? RegistrationStateEnum.NONE;
    if (_registrationState == RegistrationStateEnum.REGISTERED) {
      _signedIn = true;
      _connecting = false;
      _registrationError = null;
    } else if (_registrationState == RegistrationStateEnum.REGISTRATION_FAILED) {
      _signedIn = false;
      _connecting = false;
      _registrationError = _describeRegistrationFailure(state.cause?.toString());
    }
    notifyListeners();
  }

  @override
  void callStateChanged(Call call, CallState state) {
    switch (state.state) {
      case CallStateEnum.CALL_INITIATION:
      case CallStateEnum.CONNECTING:
      case CallStateEnum.PROGRESS:
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        final isNew = _activeCall == null || _activeCall!.id != call.id;
        if (isNew) {
          _resetCallUiState();
          _activeCall = call;
        }
        if (state.state == CallStateEnum.ACCEPTED ||
            state.state == CallStateEnum.CONFIRMED) {
          _connectedAt ??= DateTime.now();
        }
        break;

      case CallStateEnum.STREAM:
        // Attach the remote stream so the incoming audio actually plays.
        if (state.originator == Originator.remote &&
            state.stream != null &&
            _activeCall?.id == call.id) {
          remoteRenderer.srcObject = state.stream;
        }
        break;

      case CallStateEnum.HOLD:
        _onHold = true;
        break;

      case CallStateEnum.UNHOLD:
        _onHold = false;
        break;

      case CallStateEnum.MUTED:
        _muted = true;
        break;

      case CallStateEnum.UNMUTED:
        _muted = false;
        break;

      case CallStateEnum.ENDED:
      case CallStateEnum.FAILED:
      case CallStateEnum.REFER:
      case CallStateEnum.NONE:
        if (_activeCall?.id == call.id || _activeCall == null) {
          _lastEndReason = state.cause?.toString() ??
              (state.state == CallStateEnum.FAILED ? 'Call failed' : 'Call ended');
          _activeCall = null;
          _resetCallUiState();
        }
        break;
    }
    notifyListeners();
  }

  @override
  void onNewMessage(SIPMessageRequest msg) {
    // SIP messages are not used by this app.
  }

  @override
  void onNewNotify(Notify ntf) {
    // SUBSCRIBE/NOTIFY is not used by this app.
  }

  @override
  void onNewReinvite(ReInvite event) {
    // Re-INVITEs (e.g. hold from the far end) are accepted by default.
  }
}
