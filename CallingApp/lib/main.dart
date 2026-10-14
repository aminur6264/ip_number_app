import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/sip_config.dart';
import 'screens/call_screen.dart';
import 'screens/dialpad_screen.dart';
import 'screens/login_screen.dart';
import 'services/sip_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  SipService().restoreConfig(SipConfig.load(prefs));
  runApp(const CallingApp());
}

class CallingApp extends StatelessWidget {
  const CallingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IP Call BD',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF129E8F),
      ),
      home: const HomeRouter(),
    );
  }
}

/// Chooses between the login and dialpad screens, and overlays the call
/// screen on top whenever there is an active call.
class HomeRouter extends StatefulWidget {
  const HomeRouter({super.key});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  final SipService _sip = SipService();
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    _sip.addListener(_onSipChanged);
    _lifecycle = AppLifecycleListener(
      // Window/tab close: hang up and drop the SIP session before letting
      // the app exit, so the remote party receives a BYE.
      onExitRequested: _onExitRequested,
      // Shutdown paths that bypass onExitRequested (e.g. OS tearing the
      // engine down on mobile).
      onStateChange: _onAppStateChanged,
    );
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _sip.removeListener(_onSipChanged);
    super.dispose();
  }

  Future<AppExitResponse> _onExitRequested() async {
    await _sip.handleAppClosed();
    return AppExitResponse.exit;
  }

  void _onAppStateChanged(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _sip.handleAppClosed();
    }
  }

  void _onSipChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _saveConfig() async {
    final config = _sip.config;
    if (config != null) {
      await config.save(await SharedPreferences.getInstance());
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget base;
    if (!_sip.signedIn) {
      base = LoginScreen(
        initialConfig: _sip.config,
        onSignedIn: _saveConfig,
      );
    } else {
      base = const DialpadScreen();
    }

    return Stack(
      children: [
        base,
        // Offscreen sink for remote audio: WebRTC needs the stream attached
        // to a renderer for it to play, regardless of which screen is up.
        if (_sip.inCall)
          const Positioned.fill(child: CallScreen())
        else
          const Positioned(
            left: 0,
            top: 0,
            width: 0,
            height: 0,
            child: RtcAudioSink(),
          ),
      ],
    );
  }
}

/// Invisible widget that owns the remote audio renderer for the whole app
/// lifetime, so incoming audio plays no matter which screen is visible.
class RtcAudioSink extends StatefulWidget {
  const RtcAudioSink({super.key});

  @override
  State<RtcAudioSink> createState() => _RtcAudioSinkState();
}

class _RtcAudioSinkState extends State<RtcAudioSink> {
  RTCVideoRenderer? _renderer;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  Future<void> _attach() async {
    final renderer = SipService().remoteRenderer;
    await renderer.initialize();
    if (mounted) {
      setState(() => _renderer = renderer);
    }
  }

  @override
  void dispose() {
    // The renderer is owned by SipService and reused across calls; do not
    // dispose it here.
    _renderer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = _renderer;
    if (renderer == null) {
      return const SizedBox.shrink();
    }
    return RTCVideoView(renderer, mirror: false);
  }
}
