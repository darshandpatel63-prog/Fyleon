import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/native/native_bridge.dart';
import '../files/domain/file_item.dart';

/// Video thumbnails: memory (small) + disk (size limited) + the phone's own frame extractor.
class VideoThumbCache {
  VideoThumbCache._();

  static final VideoThumbCache instance = VideoThumbCache._();

  /// Disk limit. The oldest thumbnails are deleted first.
  static const maxDiskBytes = 64 * 1024 * 1024;

  final LinkedHashMap<String, Uint8List> _mem = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _pending = {};
  int _writesSinceTrim = 0;

  String _key(FileItem f) => sha1.convert('${f.path}|${f.size}|${f.modified.millisecondsSinceEpoch}'.codeUnits).toString();

  Future<Directory> _folder() async {
    final base = await getTemporaryDirectory();
    final d = Directory(p.join(base.path, 'vthumbs'));
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<Uint8List?> thumb(FileItem item, {int width = 320}) {
    final key = _key(item);
    final cached = _mem.remove(key);
    if (cached != null) {
      _mem[key] = cached; // most recently used goes last
      return Future.value(cached);
    }
    return _pending[key] ??= _load(item, key, width).whenComplete(() => _pending.remove(key));
  }

  Future<Uint8List?> _load(FileItem item, String key, int width) async {
    try {
      final dir = await _folder();
      final file = File(p.join(dir.path, '$key.jpg'));
      Uint8List? bytes;
      if (file.existsSync()) {
        bytes = await file.readAsBytes();
      } else {
        bytes = await NativeBridge.instance.videoThumb(item.path, width: width);
        if (bytes != null) {
          await file.writeAsBytes(bytes, flush: false);
          if (++_writesSinceTrim >= 40) {
            _writesSinceTrim = 0;
            _trim(dir);
          }
        }
      }
      if (bytes != null) {
        _mem[key] = bytes;
        while (_mem.length > 60) {
          _mem.remove(_mem.keys.first);
        }
      }
      return bytes;
    } catch (_) {
      return null;
    }
  }

  void _trim(Directory dir) {
    try {
      final files = dir.listSync().whereType<File>().toList();
      var total = 0;
      final stats = <File, FileStat>{};
      for (final f in files) {
        final s = f.statSync();
        stats[f] = s;
        total += s.size;
      }
      if (total <= maxDiskBytes) return;
      files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
      for (final f in files) {
        if (total <= maxDiskBytes * 0.8) break;
        total -= stats[f]!.size;
        f.deleteSync();
      }
    } catch (_) {}
  }

  Future<int> diskBytes() async {
    try {
      final dir = await _folder();
      return dir.listSync().whereType<File>().fold<int>(0, (a, f) => a + f.lengthSync());
    } catch (_) {
      return 0;
    }
  }

  Future<void> clear() async {
    _mem.clear();
    try {
      final dir = await _folder();
      for (final f in dir.listSync()) {
        f.deleteSync(recursive: true);
      }
    } catch (_) {}
  }
}

/// Duration / resolution of videos for the library (asked once, remembered in memory).
class VideoInfoCache {
  VideoInfoCache._();

  static final VideoInfoCache instance = VideoInfoCache._();

  final LinkedHashMap<String, VideoInfo?> _mem = LinkedHashMap();
  final Map<String, Future<VideoInfo?>> _pending = {};

  VideoInfo? peek(String path) => _mem[path];

  Future<VideoInfo?> info(String path) {
    if (_mem.containsKey(path)) return Future.value(_mem[path]);
    return _pending[path] ??= NativeBridge.instance.videoInfo(path).then((v) {
      _mem[path] = v;
      while (_mem.length > 600) {
        _mem.remove(_mem.keys.first);
      }
      return v;
    }).whenComplete(() => _pending.remove(path));
  }
}

/// Thumbnail with a neutral placeholder; the picture appears when it is ready.
class VideoThumb extends StatefulWidget {
  const VideoThumb({super.key, required this.item, this.width, this.height, this.radius = 12, this.fit = BoxFit.cover});

  final FileItem item;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;

  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  Future<Uint8List?>? _future;

  @override
  void initState() {
    super.initState();
    _future = VideoThumbCache.instance.thumb(widget.item);
  }

  @override
  void didUpdateWidget(VideoThumb old) {
    super.didUpdateWidget(old);
    if (old.item.path != widget.item.path) _future = VideoThumbCache.instance.thumb(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: FutureBuilder<Uint8List?>(
          future: _future,
          builder: (context, snap) {
            final bytes = snap.data;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: bytes == null
                  ? ColoredBox(
                      key: const ValueKey('ph'),
                      color: scheme.surfaceContainerHighest,
                      child: Center(child: Icon(Icons.movie_rounded, color: scheme.onSurfaceVariant.withValues(alpha: 0.6))),
                    )
                  : Image.memory(bytes, key: const ValueKey('img'), fit: widget.fit, width: double.infinity, height: double.infinity, gaplessPlayback: true),
            );
          },
        ),
      ),
    );
  }
}
