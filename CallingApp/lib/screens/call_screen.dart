import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sip_ua/sip_ua.dart';

import '../services/sip_service.dart';

/// Full-screen in-call UI. Shows Answer/Reject for incoming calls, call
/// status and timer for outgoing, and mute / speaker / hold / DTMF / hangup
/// controls once connected.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final SipService _sip = SipService();
  Timer? _ticker;
  bool _dtmfPadVisible = false;

  @override
  void initState() {
    super.initState();
    _sip.addListener(_onSipChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _established) setState(() {});
    });
  }

  @override
  void dispose() {
    _sip.removeListener(_onSipChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onSipChanged() {
    if (mounted) setState(() {});
  }

  bool get _incomingPending => _sip.incomingCallPending;

  bool get _established {
    final state = _sip.activeCall?.state;
    return state == CallStateEnum.ACCEPTED ||
        state == CallStateEnum.CONFIRMED;
  }

  String get _statusText {
    final call = _sip.activeCall;
    if (call == null) return _sip.lastEndReason ?? 'Call ended';
    switch (call.state) {
      case CallStateEnum.CALL_INITIATION:
        return call.session.direction == Direction.incoming
            ? 'Incoming call'
            : 'Calling…';
      case CallStateEnum.CONNECTING:
        return 'Connecting…';
      case CallStateEnum.PROGRESS:
        return call.session.direction == Direction.incoming
            ? 'Incoming call'
            : 'Ringing…';
      case CallStateEnum.ACCEPTED:
      case CallStateEnum.CONFIRMED:
        return _formatDuration(_sip.callDuration ?? Duration.zero);
      case CallStateEnum.HOLD:
        return 'On hold';
      case CallStateEnum.FAILED:
        return 'Call failed';
      case CallStateEnum.ENDED:
        return 'Call ended';
      default:
        return '…';
    }
  }

  static String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peer = _sip.remoteDisplayName?.isNotEmpty == true
        ? _sip.remoteDisplayName!
        : (_sip.remoteIdentity ?? 'Unknown');

    return Scaffold(
      backgroundColor: const Color(0xFF101418),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            CircleAvatar(
              radius: 48,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                peer.isNotEmpty ? peer[0] : '?',
                style: theme.textTheme.headlineLarge
                    ?.copyWith(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              peer,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              _statusText,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            // DTMF pad (in-call keypad)
            if (_dtmfPadVisible && _established)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: _DtmfPad(onDigit: _sip.sendDTMF),
              ),
            const Spacer(),
            // Controls
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: _incomingPending
                  ? _buildIncomingControls()
                  : _buildInCallControls(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomingControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            FloatingActionButton.large(
              heroTag: 'reject',
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              onPressed: _sip.hangup,
              child: const Icon(Icons.call_end_rounded, size: 36),
            ),
            const SizedBox(height: 8),
            const Text('Reject'),
          ],
        ),
        Column(
          children: [
            FloatingActionButton.large(
              heroTag: 'answer',
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              onPressed: _sip.answer,
              child: const Icon(Icons.call_rounded, size: 36),
            ),
            const SizedBox(height: 8),
            const Text('Answer'),
          ],
        ),
      ],
    );
  }

  Widget _buildInCallControls(ThemeData theme) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ControlButton(
              icon: _sip.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: _sip.muted ? 'Unmute' : 'Mute',
              active: _sip.muted,
              onPressed: _established ? _sip.toggleMute : null,
            ),
            _ControlButton(
              icon: _sip.speakerOn
                  ? Icons.volume_up_rounded
                  : Icons.hearing_disabled_rounded,
              label: _sip.speakerOn ? 'Speaker' : 'Earpiece',
              active: _sip.speakerOn,
              onPressed: _sip.toggleSpeaker,
            ),
            _ControlButton(
              icon: _sip.onHold
                  ? Icons.play_circle_outline_rounded
                  : Icons.pause_circle_outline_rounded,
              label: _sip.onHold ? 'Resume' : 'Hold',
              active: _sip.onHold,
              onPressed: _established ? _sip.toggleHold : null,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ControlButton(
              icon: Icons.dialpad_rounded,
              label: 'Keypad',
              active: _dtmfPadVisible,
              onPressed: _established
                  ? () => setState(() => _dtmfPadVisible = !_dtmfPadVisible)
                  : null,
            ),
            FloatingActionButton.large(
              heroTag: 'hangup',
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              onPressed: _sip.hangup,
              child: const Icon(Icons.call_end_rounded, size: 36),
            ),
            // Placeholder to keep the layout symmetric with the keypad button.
            const SizedBox(width: 64, height: 64),
          ],
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        IconButton.filledTonal(
          iconSize: 28,
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor:
                active ? theme.colorScheme.primaryContainer : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _DtmfPad extends StatelessWidget {
  const _DtmfPad({required this.onDigit});

  final ValueChanged<String> onDigit;

  static const List<List<String>> _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final row in _keys)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final key in row)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: OutlinedButton(
                    onPressed: () => onDigit(key),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(64, 44),
                    ),
                    child: Text(
                      key,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}
