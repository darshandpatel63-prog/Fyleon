import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/native/native_bridge.dart';

// =====================================================================================
// Fyleon Dash: send files to nearby devices over Wi-Fi / hotspot (no internet needed).
//
//  - Sender runs a tiny TCP server and shouts "I am here" with a UDP broadcast every second.
//  - Receivers hear the broadcast (list of nearby senders), OR scan the QR code, OR type the
//    5-7 digit code. With the QR / code the sender lets them in automatically; otherwise the
//    sender taps "Accept".
//  - Plain TCP sockets (not HTTP) on purpose: Android blocks plain HTTP to unknown hosts.
//  - HONEST LIMIT: the data is NOT encrypted yet (planned: key from the QR code). Use it on
//    your own Wi-Fi / hotspot, not on public networks.
// =====================================================================================

const dashBeaconPort = 41414;
const dashAppId = 'fyleon-dash';
const dashProtocol = 1;

/// A file offered by a sender.
class DashFile {
  const DashFile(this.index, this.name, this.size);

  final int index;
  final String name;
  final int size;

  Map<String, Object?> toJson() => {'i': index, 'name': name, 'size': size};

  static DashFile? fromJson(Object? j) {
    if (j is! Map) return null;
    final i = j['i'];
    final n = j['name'];
    final s = j['size'];
    if (i is! int || n is! String || s is! int || s < 0) return null;
    return DashFile(i, n, s);
  }
}

/// A sender found on the network (from its UDP beacon).
class DashPeer {
  const DashPeer({required this.id, required this.name, required this.host, required this.port, required this.files, required this.bytes, required this.tag, required this.seen});

  final String id;
  final String name;
  final String host;
  final int port;
  final int files;
  final int bytes;
  final String tag; // hash of the code, lets a typed code find the right sender
  final DateTime seen;
}

String codeTag(String code) => sha256.convert(utf8.encode('$dashAppId:$code')).toString().substring(0, 8);

String randomCode({int digits = 6}) {
  final r = math.Random.secure();
  final b = StringBuffer();
  for (var i = 0; i < digits; i++) {
    b.write(i == 0 ? 1 + r.nextInt(9) : r.nextInt(10));
  }
  return b.toString();
}

String randomToken() {
  final r = math.Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// File names coming from another device are never trusted: no folders, no odd characters.
String safeFileName(String raw) {
  var n = p.basename(raw.replaceAll('\\', '/')).replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  while (n.startsWith('.')) {
    n = n.substring(1);
  }
  return n.isEmpty ? 'file' : (n.length > 180 ? n.substring(n.length - 180) : n);
}

/// IPv4 addresses of this device (Wi-Fi, hotspot, ethernet), without loopback / link-local.
Future<List<String>> localIps() async {
  final out = <String>[];
  try {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false)) {
      for (final a in i.addresses) {
        if (a.isLoopback || a.address.startsWith('169.254.')) continue;
        out.add(a.address);
      }
    }
  } catch (_) {}
  return out;
}

/// Link used in the QR code: fyleon://dash?h=ip1,ip2&p=port&c=code&n=name
String buildDashLink({required List<String> hosts, required int port, required String code, required String name}) {
  return Uri(scheme: 'fyleon', host: 'dash', queryParameters: {'h': hosts.join(','), 'p': '$port', 'c': code, 'n': name}).toString();
}

class DashLink {
  const DashLink(this.hosts, this.port, this.code, this.name);

  final List<String> hosts;
  final int port;
  final String code;
  final String name;

  static DashLink? parse(String raw) {
    try {
      final u = Uri.parse(raw.trim());
      if (u.scheme != 'fyleon' || u.host != 'dash') return null;
      final h = (u.queryParameters['h'] ?? '').split(',').where((e) => e.isNotEmpty).toList();
      final port = int.tryParse(u.queryParameters['p'] ?? '');
      final code = u.queryParameters['c'] ?? '';
      if (h.isEmpty || port == null || port < 1 || port > 65535) return null;
      return DashLink(h, port, code, u.queryParameters['n'] ?? 'Device');
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------- socket reader

/// Reads lines and raw bytes from one socket. Pauses the network when the consumer is slower.
class SocketReader {
  SocketReader(Socket socket) {
    _sub = socket.listen(
      (data) {
        _chunks.add(data);
        _buffered += data.length;
        if (_buffered > _highWater && !_sub.isPaused) _sub.pause();
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      onError: (Object _) {
        _done = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  static const _highWater = 4 * 1024 * 1024;
  static const _lowWater = 1024 * 1024;

  late final StreamSubscription<Uint8List> _sub;
  final _chunks = ListQueue<Uint8List>();
  int _offset = 0;
  int _buffered = 0;
  bool _done = false;
  Completer<void>? _waiter;

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _wait() {
    _waiter ??= Completer<void>();
    return _waiter!.future;
  }

  void _consumed(int n) {
    _buffered -= n;
    if (_sub.isPaused && _buffered < _lowWater) _sub.resume();
  }

  /// One text line (without the newline), or null when the connection closed first.
  Future<String?> readLine({int maxLength = 1 << 20}) async {
    final bytes = BytesBuilder(copy: false);
    while (true) {
      while (_chunks.isNotEmpty) {
        final c = _chunks.first;
        var i = _offset;
        while (i < c.length && c[i] != 10) {
          i++;
        }
        if (i < c.length) {
          bytes.add(Uint8List.sublistView(c, _offset, i));
          _consumed(i + 1 - _offset);
          _offset = i + 1;
          if (_offset >= c.length) {
            _chunks.removeFirst();
            _offset = 0;
          }
          return utf8.decode(bytes.takeBytes(), allowMalformed: true);
        }
        bytes.add(Uint8List.sublistView(c, _offset));
        _consumed(c.length - _offset);
        _chunks.removeFirst();
        _offset = 0;
        if (bytes.length > maxLength) throw const FormatException('line too long');
      }
      if (_done) return null;
      await _wait();
    }
  }

  /// Hands exactly [n] bytes to [onData]. Returns false when the connection closed too early.
  Future<bool> readBytes(int n, Future<void> Function(Uint8List chunk) onData) async {
    var left = n;
    while (left > 0) {
      if (_chunks.isEmpty) {
        if (_done) return false;
        await _wait();
        continue;
      }
      final c = _chunks.first;
      final avail = c.length - _offset;
      final take = avail < left ? avail : left;
      await onData(Uint8List.sublistView(c, _offset, _offset + take));
      _consumed(take);
      _offset += take;
      left -= take;
      if (_offset >= c.length) {
        _chunks.removeFirst();
        _offset = 0;
      }
    }
    return true;
  }

  Future<void> close() async {
    try {
      await _sub.cancel();
    } catch (_) {}
  }
}

void _sendJson(Socket s, Map<String, Object?> m) => s.add(utf8.encode('${jsonEncode(m)}\n'));

// ---------------------------------------------------------------------------- sender

enum ClientStatus { pending, connected, denied, done, failed }

/// One receiver as seen by the sender (progress shown on the sender screen).
class DashClient {
  DashClient(this.id, this.name, this.ip);

  final String id;
  String name;
  String ip;
  ClientStatus status = ClientStatus.pending;
  int sentBytes = 0;
  int currentIndex = -1;
  int currentBytes = 0;
  int currentSize = 0;
  int filesDone = 0;
  Completer<bool>? waiter;
}

class SendItem {
  const SendItem(this.path, this.name, this.size);

  final String path;
  final String name;
  final int size;
}

class DashSender {
  DashSender({required this.deviceId, required this.deviceName, required List<SendItem> files, String? code})
      : code = code ?? randomCode(),
        _files = [...files];

  final String deviceId;
  final String deviceName;
  final String code;
  final List<SendItem> _files;

  ServerSocket? _server;
  RawDatagramSocket? _udp;
  Timer? _beacon;
  List<String> _targets = const ['255.255.255.255'];
  int _tick = 0;
  final Map<String, DashClient> _clients = {};
  final Map<String, String> _tokenToClient = {};
  final Map<String, List<DateTime>> _bad = {};
  final Set<Socket> _sockets = {};
  final _changes = StreamController<void>.broadcast();
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  bool _stopped = false;

  int get port => _server?.port ?? 0;
  List<SendItem> get files => List.unmodifiable(_files);
  List<DashClient> get clients => _clients.values.toList();
  Stream<void> get changes => _changes.stream;
  int get totalBytes => _files.fold(0, (a, f) => a + f.size);

  void _notify({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastNotify).inMilliseconds < 120) return;
    _lastNotify = now;
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> start() async {
    await NativeBridge.instance.multicastLock(true);
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0, shared: false);
    _server = server;
    server.listen(_handle, onError: (Object _) {}, cancelOnError: false);
    try {
      final udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      udp.broadcastEnabled = true;
      _udp = udp;
      await _refreshTargets();
      _sendBeacon();
      _beacon = Timer.periodic(const Duration(milliseconds: 1200), (_) {
        if (++_tick % 5 == 0) _refreshTargets();
        _sendBeacon();
      });
    } catch (e) {
      debugPrint('Dash beacon unavailable: $e');
    }
  }

  void addFiles(List<SendItem> more) {
    _files.addAll(more);
    _notify(force: true);
  }

  Future<void> _refreshTargets() async {
    final t = <String>{'255.255.255.255'};
    for (final ip in await localIps()) {
      final parts = ip.split('.');
      if (parts.length == 4) t.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
    }
    _targets = t.toList();
  }

  void _sendBeacon() {
    final udp = _udp;
    if (udp == null || _stopped) return;
    final data = utf8.encode(jsonEncode({
      'app': dashAppId,
      'v': dashProtocol,
      'id': deviceId,
      'name': deviceName,
      'port': port,
      'n': _files.length,
      'bytes': totalBytes,
      'tag': codeTag(code),
    }));
    for (final t in _targets) {
      try {
        udp.send(data, InternetAddress(t), dashBeaconPort);
      } catch (_) {}
    }
  }

  bool _blocked(String ip) {
    final list = _bad[ip];
    if (list == null) return false;
    final cutoff = DateTime.now().subtract(const Duration(seconds: 60));
    list.removeWhere((d) => d.isBefore(cutoff));
    return list.length >= 5;
  }

  void _noteBad(String ip) => (_bad[ip] ??= []).add(DateTime.now());

  void approve(String clientId) => _clients[clientId]?.waiter?.complete(true);

  void deny(String clientId) => _clients[clientId]?.waiter?.complete(false);

  Future<void> _handle(Socket socket) async {
    _sockets.add(socket);
    final reader = SocketReader(socket);
    final ip = socket.remoteAddress.address;
    DashClient? client;
    String? token;
    try {
      while (!_stopped) {
        final line = await reader.readLine();
        if (line == null) break;
        final Object? decoded = jsonDecode(line);
        if (decoded is! Map) break;
        final op = decoded['op'];

        if (op == 'hello') {
          if (_blocked(ip)) {
            _sendJson(socket, {'ok': false, 'reason': 'blocked'});
            break;
          }
          final cid = (decoded['id'] is String && (decoded['id'] as String).isNotEmpty) ? decoded['id'] as String : ip;
          final name = (decoded['name'] is String && (decoded['name'] as String).trim().isNotEmpty) ? (decoded['name'] as String).trim() : 'Device';
          final given = decoded['code'];
          var approved = false;
          if (given is String && given.isNotEmpty) {
            if (given != code) {
              _noteBad(ip);
              _sendJson(socket, {'ok': false, 'reason': 'badcode'});
              break;
            }
            approved = true;
          }
          final c = _clients[cid] ??= DashClient(cid, name, ip);
          c
            ..name = name
            ..ip = ip
            ..status = approved ? ClientStatus.connected : ClientStatus.pending;
          client = c;
          _notify(force: true);
          if (!approved) {
            c.waiter = Completer<bool>();
            approved = await c.waiter!.future.timeout(const Duration(seconds: 90), onTimeout: () => false);
            c.waiter = null;
          }
          if (!approved) {
            c.status = ClientStatus.denied;
            _notify(force: true);
            _sendJson(socket, {'ok': false, 'reason': 'denied'});
            break;
          }
          token = randomToken();
          _tokenToClient[token] = cid;
          c.status = ClientStatus.connected;
          _notify(force: true);
          _sendJson(socket, {
            'ok': true,
            'token': token,
            'sender': deviceName,
            'files': [for (var i = 0; i < _files.length; i++) DashFile(i, _files[i].name, _files[i].size).toJson()],
          });
        } else if (op == 'get') {
          final c = client;
          if (c == null || token == null || decoded['token'] != token) {
            _sendJson(socket, {'ok': false, 'reason': 'auth'});
            break;
          }
          final i = decoded['i'];
          if (i is! int || i < 0 || i >= _files.length) {
            _sendJson(socket, {'ok': false, 'reason': 'nofile'});
            continue;
          }
          final item = _files[i];
          final file = File(item.path);
          int len;
          try {
            len = await file.length();
          } catch (_) {
            _sendJson(socket, {'ok': false, 'reason': 'unreadable'});
            continue;
          }
          final off = decoded['offset'] is int ? (decoded['offset'] as int).clamp(0, len) : 0;
          _sendJson(socket, {'ok': true, 'size': len, 'offset': off});
          c
            ..currentIndex = i
            ..currentSize = len
            ..currentBytes = off;
          await socket.addStream(file.openRead(off).map((chunk) {
            c.currentBytes += chunk.length;
            c.sentBytes += chunk.length;
            _notify();
            return chunk;
          }));
          c.filesDone++;
          _notify(force: true);
        } else if (op == 'bye') {
          if (client != null) client.status = ClientStatus.done;
          _notify(force: true);
          break;
        } else {
          _sendJson(socket, {'ok': false, 'reason': 'unknown'});
        }
      }
    } catch (_) {
      final c = client;
      if (c != null && c.status == ClientStatus.connected && c.filesDone < _files.length) {
        c.status = ClientStatus.failed;
        _notify(force: true);
      }
    } finally {
      await reader.close();
      // let the last answer ("denied", "wrong code"...) leave before the connection is closed
      try {
        await socket.flush().timeout(const Duration(seconds: 2));
      } catch (_) {}
      _sockets.remove(socket);
      try {
        socket.destroy();
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    for (final s in _sockets.toList()) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _sockets.clear();
    _beacon?.cancel();
    _udp?.close();
    for (final c in _clients.values) {
      c.waiter?.complete(false);
    }
    try {
      await _server?.close();
    } catch (_) {}
    await NativeBridge.instance.multicastLock(false);
    await _changes.close();
  }
}

// ---------------------------------------------------------------------------- discovery

/// Listens for sender beacons and keeps a list of nearby senders (refreshed every second).
class DashDiscovery {
  DashDiscovery({required this.myId});

  final String myId;
  RawDatagramSocket? _socket;
  Timer? _timer;
  final Map<String, DashPeer> _peers = {};
  final _controller = StreamController<List<DashPeer>>.broadcast();

  Stream<List<DashPeer>> get peers => _controller.stream;
  List<DashPeer> get current => _peers.values.toList();

  Future<bool> start() async {
    await NativeBridge.instance.multicastLock(true);
    try {
      final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, dashBeaconPort, reuseAddress: true, reusePort: !Platform.isWindows);
      _socket = s;
      s.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = s.receive()) != null) {
          _onDatagram(d!);
        }
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _expire());
      return true;
    } catch (e) {
      debugPrint('Dash discovery unavailable: $e');
      return false;
    }
  }

  void _onDatagram(Datagram d) {
    try {
      final j = jsonDecode(utf8.decode(d.data, allowMalformed: true));
      if (j is! Map || j['app'] != dashAppId) return;
      final id = j['id'];
      final port = j['port'];
      if (id is! String || id == myId || port is! int || port < 1) return;
      final peer = DashPeer(
        id: id,
        name: (j['name'] as String?) ?? 'Device',
        host: d.address.address,
        port: port,
        files: (j['n'] as int?) ?? 0,
        bytes: (j['bytes'] as int?) ?? 0,
        tag: (j['tag'] as String?) ?? '',
        seen: DateTime.now(),
      );
      final isNew = !_peers.containsKey(id);
      _peers[id] = peer;
      if (isNew) _controller.add(current);
    } catch (_) {}
  }

  void _expire() {
    final cutoff = DateTime.now().subtract(const Duration(seconds: 5));
    final before = _peers.length;
    _peers.removeWhere((_, v) => v.seen.isBefore(cutoff));
    if (_peers.length != before) _controller.add(current);
  }

  DashPeer? findByCode(String code) {
    final tag = codeTag(code);
    for (final peer in _peers.values) {
      if (peer.tag == tag) return peer;
    }
    return null;
  }

  Future<void> stop() async {
    _timer?.cancel();
    _socket?.close();
    await NativeBridge.instance.multicastLock(false);
    await _controller.close();
  }
}

// ---------------------------------------------------------------------------- receiver

class DashRefused implements Exception {
  const DashRefused(this.reason);

  final String reason;

  String get message {
    switch (reason) {
      case 'denied':
        return 'The sender did not accept.';
      case 'badcode':
        return 'Wrong code.';
      case 'blocked':
        return 'Too many wrong codes. Try again in a minute.';
      default:
        return 'The sender refused the connection.';
    }
  }

  @override
  String toString() => message;
}

class DashProgress {
  const DashProgress({this.fileIndex = -1, this.fileBytes = 0, this.fileSize = 0, this.doneBytes = 0, this.totalBytes = 0, this.finished = false, this.error});

  final int fileIndex;
  final int fileBytes;
  final int fileSize;
  final int doneBytes;
  final int totalBytes;
  final bool finished;
  final String? error;
}

/// Receiver side: connects to a sender, asks for the file list and downloads the files.
class DashDownloader {
  DashDownloader({required this.myId, required this.myName});

  final String myId;
  final String myName;

  Socket? _socket;
  SocketReader? _reader;
  String? _token;
  bool _cancelled = false;
  List<DashFile> files = const [];
  String senderName = '';

  /// Tries every host until one answers. Waits for the sender's "Accept" when no code is given.
  Future<void> connect(List<String> hosts, int port, {String? code}) async {
    Object? last;
    for (final h in hosts) {
      try {
        _socket = await Socket.connect(h, port, timeout: const Duration(seconds: 4));
        last = null;
        break;
      } catch (e) {
        last = e;
      }
    }
    final s = _socket;
    if (s == null) throw last ?? const SocketException('No connection');
    s.setOption(SocketOption.tcpNoDelay, true);
    final r = SocketReader(s);
    _reader = r;
    _sendJson(s, {'op': 'hello', 'v': dashProtocol, 'id': myId, 'name': myName, 'code': code});
    final line = await r.readLine().timeout(const Duration(seconds: 100), onTimeout: () => null);
    if (line == null) {
      await close();
      throw const DashRefused('timeout');
    }
    final Object? j = jsonDecode(line);
    if (j is! Map || j['ok'] != true || j['token'] is! String) {
      await close();
      throw DashRefused(j is Map ? '${j['reason']}' : 'error');
    }
    _token = j['token'] as String;
    senderName = (j['sender'] as String?) ?? '';
    files = (j['files'] as List? ?? const []).map(DashFile.fromJson).whereType<DashFile>().toList();
  }

  void cancel() {
    _cancelled = true;
    _socket?.destroy();
  }

  /// Downloads [indexes] (all by default) into [dir]. Returns file index -> saved path.
  Future<Map<int, String>> download(String dir, void Function(DashProgress) onProgress, {List<int>? indexes}) async {
    final s = _socket;
    final r = _reader;
    final token = _token;
    if (s == null || r == null || token == null) throw StateError('Not connected');
    final chosen = indexes ?? [for (final f in files) f.index];
    final total = files.where((f) => chosen.contains(f.index)).fold<int>(0, (a, f) => a + f.size);
    var done = 0;
    var lastReport = DateTime.fromMillisecondsSinceEpoch(0);
    final saved = <int, String>{};
    Directory(dir).createSync(recursive: true);

    for (final f in files.where((f) => chosen.contains(f.index))) {
      if (_cancelled) throw const DashRefused('cancelled');
      _sendJson(s, {'op': 'get', 'token': token, 'i': f.index, 'offset': 0});
      final line = await r.readLine();
      if (line == null) throw const SocketException('Connection closed');
      final Object? j = jsonDecode(line);
      if (j is! Map || j['ok'] != true || j['size'] is! int) {
        onProgress(DashProgress(fileIndex: f.index, error: 'Could not get ${f.name}', doneBytes: done, totalBytes: total));
        continue;
      }
      final size = j['size'] as int;
      final target = _uniquePath(dir, safeFileName(f.name));
      final part = '$target.part';
      final raf = await File(part).open(mode: FileMode.write);
      var got = 0;
      try {
        final ok = await r.readBytes(size, (chunk) async {
          await raf.writeFrom(chunk);
          got += chunk.length;
          done += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastReport).inMilliseconds > 100) {
            lastReport = now;
            onProgress(DashProgress(fileIndex: f.index, fileBytes: got, fileSize: size, doneBytes: done, totalBytes: total));
          }
        });
        if (!ok) throw const SocketException('Connection closed');
      } finally {
        await raf.close();
      }
      await File(part).rename(target);
      saved[f.index] = target;
      onProgress(DashProgress(fileIndex: f.index, fileBytes: size, fileSize: size, doneBytes: done, totalBytes: total));
    }
    try {
      _sendJson(s, {'op': 'bye'});
    } catch (_) {}
    onProgress(DashProgress(doneBytes: done, totalBytes: total, finished: true));
    return saved;
  }

  String _uniquePath(String dir, String name) {
    var path = p.join(dir, name);
    if (!File(path).existsSync()) return path;
    final base = p.basenameWithoutExtension(name);
    final ext = p.extension(name);
    for (var i = 1; i < 10000; i++) {
      path = p.join(dir, '$base ($i)$ext');
      if (!File(path).existsSync()) return path;
    }
    return p.join(dir, '$base-${DateTime.now().millisecondsSinceEpoch}$ext');
  }

  Future<void> close() async {
    await _reader?.close();
    try {
      _socket?.destroy();
    } catch (_) {}
  }
}
