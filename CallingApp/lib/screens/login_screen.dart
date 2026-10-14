import 'package:flutter/material.dart';

import '../models/sip_config.dart';
import '../services/sip_service.dart';

/// Sign-in form for the PBX account. Ships with the IP Call BD demo server
/// pre-filled; enter the extension and password you were issued.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialConfig,
    this.onSignedIn,
  });

  final SipConfig? initialConfig;
  final VoidCallback? onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final SipService _sip = SipService();
  late final TextEditingController _server;
  late final TextEditingController _extension;
  late final TextEditingController _password;
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig;
    _server = TextEditingController(text: initial?.server ?? 'talk.ipcall.bd');
    _extension = TextEditingController(text: initial?.extension ?? '');
    _password = TextEditingController(text: initial?.password ?? '');
    _sip.addListener(_onSipChanged);
  }

  @override
  void dispose() {
    _sip.removeListener(_onSipChanged);
    _server.dispose();
    _extension.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onSipChanged() {
    if (!mounted) return;
    if (_sip.signedIn) {
      widget.onSignedIn?.call();
    }
    setState(() {});
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final config = SipConfig(
      server: _server.text.trim(),
      extension: _extension.text.trim(),
      password: _password.text,
    );
    await SipService().connect(config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connecting = _sip.connecting;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      Icons.phone_in_talk_rounded,
                      size: 72,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'IP Call BD',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Sign in with your SIP extension',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 36),
                    TextFormField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'SIP server',
                        hintText: 'talk.ipcall.bd',
                        prefixIcon: Icon(Icons.dns_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Enter server' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _extension,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Extension',
                        hintText: '55500',
                        prefixIcon: Icon(Icons.account_circle_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Enter extension' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Enter password' : null,
                    ),
                    const SizedBox(height: 24),
                    if (_sip.registrationError != null) ...[
                      Text(
                        _sip.registrationError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: 16),
                    ],
                    FilledButton.icon(
                      onPressed: connecting ? null : _signIn,
                      icon: connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: Text(connecting ? 'Connecting…' : 'Sign in'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
