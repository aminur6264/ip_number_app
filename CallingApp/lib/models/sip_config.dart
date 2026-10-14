import 'package:shared_preferences/shared_preferences.dart';

/// SIP account settings. The extension and password are the ones issued by
/// the IP Call BD PBX; the server is the WSS endpoint of the PBX.
class SipConfig {
  SipConfig({
    required this.server,
    required this.extension,
    required this.password,
  });

  /// PBX host, e.g. `talk.ipcall.bd`.
  final String server;

  /// SIP extension / username, e.g. `55500`.
  final String extension;

  /// SIP password for the extension.
  final String password;

  /// Signaling endpoint derived from the server host, same scheme the
  /// web demo uses (`wss://<host>/ws`).
  String get webSocketUrl => 'wss://$server/ws';

  /// SIP identity for the extension.
  String get sipUri => 'sip:$extension@$server';

  bool get isValid =>
      server.isNotEmpty && extension.isNotEmpty && password.isNotEmpty;

  static SipConfig? load(SharedPreferences prefs) {
    final server = prefs.getString(_kServer);
    final extension = prefs.getString(_kExtension);
    final password = prefs.getString(_kPassword);
    if (server == null || extension == null || password == null) {
      return null;
    }
    return SipConfig(
      server: server,
      extension: extension,
      password: password,
    );
  }

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setString(_kServer, server);
    await prefs.setString(_kExtension, extension);
    await prefs.setString(_kPassword, password);
  }

  static const _kServer = 'sip.server';
  static const _kExtension = 'sip.extension';
  static const _kPassword = 'sip.password';
}
