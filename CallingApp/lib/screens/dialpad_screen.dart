import 'package:flutter/material.dart';
import 'package:sip_ua/sip_ua.dart';

import '../services/sip_service.dart';

/// Registered home screen: shows registration status, a number display and
/// the dialpad, mirroring the web demo.
class DialpadScreen extends StatefulWidget {
  const DialpadScreen({super.key});

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  final SipService _sip = SipService();
  final TextEditingController _number = TextEditingController();

  static const List<List<String>> _keys = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['*', '0', '#'],
  ];

  @override
  void initState() {
    super.initState();
    _sip.addListener(_onSipChanged);
  }

  @override
  void dispose() {
    _sip.removeListener(_onSipChanged);
    _number.dispose();
    super.dispose();
  }

  void _onSipChanged() {
    if (mounted) setState(() {});
  }

  // The number display is a plain Text, not a TextField, so it does not
  // observe the controller — rebuild explicitly whenever the text changes.
  void _append(String digit) {
    setState(() => _number.text += digit);
  }

  void _backspace() {
    if (_number.text.isNotEmpty) {
      setState(
        () => _number.text =
            _number.text.substring(0, _number.text.length - 1),
      );
    }
  }

  Future<void> _call() async {
    if (_number.text.isEmpty) return;
    final ok = await SipService().call(_number.text);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not connected — check registration')),
      );
    }
  }

  Future<void> _reconnect() async {
    final config = SipService().config;
    if (config != null) {
      await SipService().connect(config);
    }
  }

  Future<void> _signOut() async {
    await SipService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canCall = _sip.registered && _number.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Ext ${_sip.config?.extension ?? ''}'),
        actions: [
          _StatusChip(sip: _sip, onReconnect: _reconnect),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Number display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _number.text.isEmpty ? 'Enter number' : _number.text,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: _number.text.isEmpty
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Backspace',
                    icon: const Icon(Icons.backspace_outlined),
                    onPressed: _number.text.isEmpty ? null : _backspace,
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Dialpad
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  for (final row in _keys)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        for (final key in row)
                          _DialKey(label: key, onTap: () => _append(key)),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Call button
            FilledButton.icon(
              onPressed: canCall ? _call : null,
              icon: const Icon(Icons.call_rounded, size: 28),
              label: const Text('Call', style: TextStyle(fontSize: 18)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

/// Small pill showing the current registration state; tap to retry when offline.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.sip, required this.onReconnect});

  final SipService sip;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final (label, color, canRetry) = switch (sip.registrationState) {
      RegistrationStateEnum.REGISTERED => ('Online', Colors.greenAccent, false),
      RegistrationStateEnum.REGISTRATION_FAILED => ('Failed', Colors.redAccent, true),
      RegistrationStateEnum.UNREGISTERED => ('Offline', Colors.orangeAccent, true),
      RegistrationStateEnum.NONE => sip.connecting
          ? ('Connecting…', Colors.amberAccent, false)
          : ('Offline', Colors.orangeAccent, true),
    };

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ActionChip(
        avatar: Icon(Icons.circle, size: 10, color: color),
        label: Text(label),
        onPressed: canRetry ? onReconnect : null,
      ),
    );
  }
}

class _DialKey extends StatelessWidget {
  const _DialKey({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onTap,
          child: SizedBox(
            width: 72,
            height: 72,
            child: Center(
              child: Text(
                label,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
