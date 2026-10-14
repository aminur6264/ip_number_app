// Diagnostic probe: performs a SIP REGISTER (with digest auth) over
// WebSocket (what the app/sip_ua does) or plain UDP (what 3rd-party SIP
// clients like Zoiper/Linphone do by default), and prints every raw SIP
// message so server-side behaviour per extension and transport can be
// compared.
//
// Usage:
//   dart run bin/sip_probe.dart <extension> [password] [--udp] [--port=N] [server]
//
// Examples:
//   dart run bin/sip_probe.dart 44004 abcd1234           (WSS, like the app)
//   dart run bin/sip_probe.dart 44004 abcd1234 --udp     (UDP:5060, like Zoiper)
//   dart run bin/sip_probe.dart 44000                    (challenge-only)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

/// Minimal bidirectional pipe for SIP messages.
abstract class SipConnection {
  Stream<String> get incoming;
  Future<void> send(String msg);
  Future<void> close();
}

class WsConnection implements SipConnection {
  WsConnection(this._channel);
  final WebSocket _channel;

  static Future<WsConnection> connect(String url) async {
    // Perform the upgrade by hand, exactly like sip_ua's
    // websocket_dart_impl.dart does: hardcoded `sip` subprotocol and
    // badCertificateCallback => true.
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    final parsed = Uri.parse(url);
    final uri = parsed.replace(
        scheme: parsed.scheme == 'wss' ? 'https' : 'http');
    final key = base64
        .encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    final request = await client.getUrl(uri);
    request.headers.add('Connection', 'Upgrade', preserveHeaderCase: true);
    request.headers.add('Upgrade', 'websocket', preserveHeaderCase: true);
    request.headers.add('Sec-WebSocket-Version', '13',
        preserveHeaderCase: true);
    request.headers.add('Sec-WebSocket-Key', key.toLowerCase(),
        preserveHeaderCase: true);
    request.headers.add('Sec-WebSocket-Protocol', 'sip',
        preserveHeaderCase: true);
    final response = await request.close();
    if (response.statusCode != HttpStatus.switchingProtocols) {
      final body = await response.transform(utf8.decoder).join();
      throw WebSocketException(
          'not upgraded, HTTP ${response.statusCode}${body.isEmpty ? '' : ': ${body.trim().substring(0, body.length.clamp(0, 200))}'}');
    }
    final socket = await response.detachSocket();
    return WsConnection(
      WebSocket.fromUpgradedSocket(socket, protocol: 'sip', serverSide: false),
    );
  }

  @override
  Stream<String> get incoming => _channel.map((data) =>
      data is String ? data : utf8.decode(data as List<int>, allowMalformed: true));

  @override
  Future<void> send(String msg) async {
    _channel.add(msg);
  }

  @override
  Future<void> close() => _channel.close();
}

class UdpConnection implements SipConnection {
  UdpConnection._(this._socket, this._remote, this._port);
  final RawDatagramSocket _socket;
  final InternetAddress _remote;
  final int _port;
  final _controller = StreamController<String>.broadcast();

  static Future<UdpConnection> connect(String host, int port) async {
    final addr = (await InternetAddress.lookup(host)).first;
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final conn = UdpConnection._(socket, addr, port);
    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = socket.receive();
        if (dg != null) {
          conn._controller
              .add(utf8.decode(dg.data, allowMalformed: true));
        }
      }
    });
    return conn;
  }

  @override
  Stream<String> get incoming => _controller.stream;

  @override
  Future<void> send(String msg) async {
    _socket.send(utf8.encode(msg), _remote, _port);
  }

  @override
  Future<void> close() async {
    await _controller.close();
    _socket.close();
  }
}

class TcpConnection implements SipConnection {
  TcpConnection._(this._socket);
  final Socket _socket;
  final _controller = StreamController<String>.broadcast();

  static Future<TcpConnection> connect(String host, int port) async {
    final socket = await Socket.connect(host, port);
    final conn = TcpConnection._(socket);
    socket.listen(
      (data) => conn._controller.add(utf8.decode(data, allowMalformed: true)),
      onError: (Object e) => conn._controller.addError(e),
      onDone: conn._controller.close,
    );
    return conn;
  }

  @override
  Stream<String> get incoming => _controller.stream;

  @override
  Future<void> send(String msg) async {
    _socket.add(utf8.encode(msg));
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    await _controller.close();
    _socket.destroy();
  }
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'usage: dart run bin/sip_probe.dart <extension> [password] [--udp] [--port=N] [server]');
    exitCode = 2;
    return;
  }
  final positional = <String>[];
  var mode = 'wss'; // wss | ws | tcp | udp
  var port = -1;
  var viaOverride = '';
  for (final a in args.skip(1)) {
    if (a == '--udp') {
      mode = 'udp';
    } else if (a == '--tcp') {
      mode = 'tcp';
    } else if (a == '--ws') {
      mode = 'ws';
    } else if (a.startsWith('--port=')) {
      port = int.tryParse(a.substring(7)) ?? -1;
    } else if (a.startsWith('--via=')) {
      viaOverride = a.substring(6);
    } else {
      positional.add(a);
    }
  }
  final extension = args[0];
  final password = positional.isNotEmpty ? positional[0] : '';
  final server = positional.length > 1 ? positional[1] : 'talk.ipcall.bd';

  final SipConnection conn;
  switch (mode) {
    case 'udp':
      final p = port > 0 ? port : 5060;
      stdout.writeln('=== connecting via UDP to $server:$p');
      conn = await UdpConnection.connect(server, p);
      break;
    case 'tcp':
      final p = port > 0 ? port : 5060;
      stdout.writeln('=== connecting via TCP to $server:$p');
      conn = await TcpConnection.connect(server, p);
      break;
    case 'ws':
      final p = port > 0 ? port : 8088;
      final url = 'ws://$server:$p/ws';
      stdout.writeln('=== connecting via WS to $url');
      conn = await WsConnection.connect(url);
      break;
    default:
      final p = port > 0 ? port : 443;
      final url =
          p == 443 ? 'wss://$server/ws' : 'wss://$server:$p/ws';
      stdout.writeln('=== connecting via WSS to $url');
      conn = await WsConnection.connect(url);
  }
  stdout.writeln('=== connected');

  final rnd = Random.secure();
  final callId =
      '${DateTime.now().millisecondsSinceEpoch}-${_randHex(rnd, 6)}@probe.invalid';
  final fromTag = _randHex(rnd, 8);
  final viaTransport = switch (mode) {
    'udp' => 'UDP',
    'tcp' => 'TCP',
    _ => 'WSS',
  };
  final viaHost = viaOverride.isNotEmpty
      ? viaOverride
      : mode == 'udp' || mode == 'tcp'
          ? 'probe.invalid'
          : server;
  final contactTransport = switch (mode) {
    'udp' => '',
    'tcp' => ';transport=tcp',
    _ => ';transport=ws',
  };

  int cseq = 0;
  // 0 = waiting for the 401 challenge, 1 = waiting for the auth result.
  int phase = 0;
  final challenge = Completer<String>();
  final authResult = Completer<String>();

  late final StreamSubscription sub;
  sub = conn.incoming.listen(
    (text) {
      stdout.writeln('\n<<< ${'-' * 60}');
      stdout.write(text.trimRight());
      stdout.writeln('\n<<< ${'-' * 60}');
      final status = _statusOf(text);
      if (status == null ||
          !(status.startsWith('2') || status.startsWith('4'))) {
        return;
      }
      if (phase == 0 && !challenge.isCompleted) {
        challenge.complete(text);
      } else if (phase == 1 && !authResult.isCompleted) {
        authResult.complete(text);
      }
    },
    onError: (Object e) {
      stdout.writeln('!! socket error: $e');
      if (!challenge.isCompleted) challenge.complete('');
      if (!authResult.isCompleted) authResult.complete('');
    },
    onDone: () {
      stdout.writeln('!! socket closed');
      if (!challenge.isCompleted) challenge.complete('');
      if (!authResult.isCompleted) authResult.complete('');
    },
  );

  void send(String msg) {
    stdout.writeln('\n>>> ${'-' * 60}');
    stdout.write(msg.trimRight());
    stdout.writeln('\n>>> ${'-' * 60}');
    conn.send(msg);
  }

  String register(String? authHeader) {
    cseq++;
    final branch = 'z9hG4bK${_randHex(rnd, 12)}';
    final buf = StringBuffer()
      ..writeln('REGISTER sip:$server SIP/2.0')
      ..writeln('Via: SIP/2.0/$viaTransport $viaHost;branch=$branch'
          '${(mode == 'udp' || mode == 'tcp') ? ";rport" : ""}')
      ..writeln('Max-Forwards: 70')
      ..writeln('From: <sip:$extension@$server>;tag=$fromTag')
      ..writeln('To: <sip:$extension@$server>')
      ..writeln('Call-ID: $callId')
      ..writeln('CSeq: $cseq REGISTER')
      ..writeln('Contact: <sip:$extension@$server$contactTransport>;expires=300')
      ..writeln('User-Agent: sip-probe/1.0');
    if (authHeader != null) {
      buf.writeln('Authorization: $authHeader');
    }
    buf.writeln('Content-Length: 0');
    buf.writeln();
    return buf.toString();
  }

  try {
    send(register(null));
    final first = await challenge.future
        .timeout(const Duration(seconds: 10), onTimeout: () => '');
    if (first.isEmpty) {
      stdout.writeln('\n=== no SIP response received (timeout); stopping.');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final wwwAuth = _headersOf(first)
        .where((h) => h.toLowerCase().startsWith('www-authenticate:'))
        .toList();
    if (wwwAuth.isEmpty) {
      stdout.writeln('\n=== no WWW-Authenticate challenge; stopping.');
      return;
    }
    final params = _digestParams(wwwAuth.first);
    final realm = params['realm'] ?? '';
    final nonce = params['nonce'] ?? '';
    final algorithm = (params['algorithm'] ?? 'MD5').toUpperCase();
    final qopRaw = params['qop'] ?? '';
    final uri = 'sip:$server';
    stdout.writeln(
        '\n=== challenge: realm="$realm" algorithm=$algorithm qop="$qopRaw" nonce=${nonce.isEmpty ? '<none>' : '<present>'}');

    if (password.isEmpty || nonce.isEmpty) {
      stdout.writeln('\n=== challenge-only mode (no password given); stopping.');
      return;
    }

    String h(String s) {
      final bytes = utf8.encode(s);
      switch (algorithm) {
        case 'SHA-256':
        case 'SHA-256-SESS':
          return crypto.sha256.convert(bytes).toString();
        case 'MD5':
        case 'MD5-SESS':
        default:
          return crypto.md5.convert(bytes).toString();
      }
    }

    final ha1 = h('$extension:$realm:$password');
    final ha2 = h('REGISTER:$uri');
    final authParts = <String>[
      'Digest username="$extension"',
      'realm="$realm"',
      'nonce="$nonce"',
      'uri="$uri"',
    ];
    if (qopRaw.toLowerCase().contains('auth')) {
      const nc = '00000001';
      final cnonce = _randHex(rnd, 12);
      final response = h('$ha1:$nonce:$nc:$cnonce:auth:$ha2');
      authParts
        ..add('response="$response"')
        ..add('algorithm=$algorithm')
        ..add('cnonce="$cnonce"')
        ..add('qop=auth')
        ..add('nc=$nc');
    } else {
      final response = h('$ha1:$nonce:$ha2');
      authParts
        ..add('response="$response"')
        ..add('algorithm=$algorithm');
    }

    phase = 1;
    send(register(authParts.join(', ')));
    final second = await authResult.future
        .timeout(const Duration(seconds: 10), onTimeout: () => '');
    if (second.isEmpty) {
      stdout.writeln('\n=== no response to authenticated REGISTER.');
      return;
    }
    final status = _statusOf(second)!;
    stdout.writeln('\n=== RESULT for $extension over ${mode.toUpperCase()}: '
        'SIP $status '
        '(${status.startsWith("2") ? "AUTH OK" : "AUTH FAILED"})');
  } finally {
    await sub.cancel();
    try {
      await conn.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}

String? _statusOf(String msg) {
  final m = RegExp(r'^SIP/2\.0 (\d{3})', multiLine: true).firstMatch(msg);
  return m?.group(1);
}

List<String> _headersOf(String msg) {
  final idx = msg.indexOf('\r\n\r\n');
  final headerBlock = idx >= 0 ? msg.substring(0, idx) : msg;
  return headerBlock
      .split(RegExp(r'\r?\n'))
      .skip(1)
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
}

Map<String, String> _digestParams(String headerLine) {
  final value = headerLine.substring(headerLine.indexOf(':') + 1).trim();
  final params = <String, String>{};
  final re = RegExp(r'(\w+)=(?:"((?:[^"\\]|\\.)*)"|([^\s,]+))');
  for (final m in re.allMatches(value)) {
    params[m.group(1)!.toLowerCase()] = (m.group(2) ?? m.group(3) ?? '').trim();
  }
  return params;
}

String _randHex(Random rnd, int bytes) =>
    List.generate(bytes, (_) => rnd.nextInt(16).toRadixString(16)).join();
