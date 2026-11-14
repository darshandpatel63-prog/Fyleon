import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../utils/platform_utils.dart';

class StorageInfo {
  const StorageInfo(this.total, this.free);
  final int total;
  final int free;
}


/// One installed app as reported by MainActivity.kt.
class InstalledApp {
  const InstalledApp({
    required this.pkg,
    required this.label,
    required this.system,
    required this.game,
    required this.apkSize,
    required this.installed,
    required this.updated,
    required this.version,
    required this.launchable,
  });

  final String pkg;
  final String label;
  final bool system;
  final bool game;
  final int apkSize;
  final DateTime installed;
  final DateTime updated;
  final String version;
  final bool launchable;

  static InstalledApp? fromMap(Map<Object?, Object?> m) {
    final pkg = m['pkg'];
    if (pkg is! String) return null;
    int n(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
    return InstalledApp(
      pkg: pkg,
      label: (m['label'] as String?) ?? pkg,
      system: m['system'] == true,
      game: m['game'] == true,
      apkSize: n(m['apkSize']),
      installed: DateTime.fromMillisecondsSinceEpoch(n(m['installed'])),
      updated: DateTime.fromMillisecondsSinceEpoch(n(m['updated'])),
      version: (m['version'] as String?) ?? '',
      launchable: m['launchable'] == true,
    );
  }
}

/// Sizes of one app (needs "Usage access"). All values are bytes; [lastUsed] is null if unknown.
class AppStats {
  const AppStats({required this.app, required this.data, required this.cache, required this.lastUsed});

  final int app;
  final int data;
  final int cache;
  final DateTime? lastUsed;

  int get total => app + data + cache;
}


/// One stream inside a media file (from MediaExtractor).
class MediaTrackInfo {
  const MediaTrackInfo({required this.type, required this.mime, this.lang, this.channels, this.sampleRate, this.width, this.height, this.fps, this.bitrate});

  final String type; // video | audio | text | other
  final String mime;
  final String? lang;
  final int? channels;
  final int? sampleRate;
  final int? width;
  final int? height;
  final double? fps;
  final int? bitrate;

  static MediaTrackInfo? fromMap(Map<Object?, Object?> m) {
    final mime = m['mime'];
    if (mime is! String) return null;
    int? i(Object? v) => v is num ? v.toInt() : null;
    return MediaTrackInfo(
      type: (m['type'] as String?) ?? 'other',
      mime: mime,
      lang: m['lang'] as String?,
      channels: i(m['channels']),
      sampleRate: i(m['sampleRate']),
      width: i(m['width']),
      height: i(m['height']),
      fps: m['fps'] is num ? (m['fps'] as num).toDouble() : null,
      bitrate: i(m['bitrate']),
    );
  }
}

/// Container details of a video file (from MediaMetadataRetriever + MediaExtractor).
class VideoInfo {
  const VideoInfo({this.durationMs = 0, this.width = 0, this.height = 0, this.rotation = 0, this.bitrate = 0, this.mime, this.fps, this.tracks = const []});

  final int durationMs;
  final int width;
  final int height;
  final int rotation;
  final int bitrate;
  final String? mime;
  final double? fps;
  final List<MediaTrackInfo> tracks;

  Duration get duration => Duration(milliseconds: durationMs);
  Iterable<MediaTrackInfo> get video => tracks.where((t) => t.type == 'video');
  Iterable<MediaTrackInfo> get audio => tracks.where((t) => t.type == 'audio');
  Iterable<MediaTrackInfo> get text => tracks.where((t) => t.type == 'text');

  static VideoInfo fromMap(Map<Object?, Object?> m) {
    int i(Object? v) => v is num ? v.toInt() : 0;
    final tracks = <MediaTrackInfo>[];
    final raw = m['tracks'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final t = MediaTrackInfo.fromMap(e.cast<Object?, Object?>());
          if (t != null) tracks.add(t);
        }
      }
    }
    return VideoInfo(
      durationMs: i(m['durationMs']),
      width: i(m['width']),
      height: i(m['height']),
      rotation: i(m['rotation']),
      bitrate: i(m['bitrate']),
      mime: m['mime'] as String?,
      fps: m['fps'] is num ? (m['fps'] as num).toDouble() : null,
      tracks: tracks,
    );
  }
}

/// Talks to MainActivity.kt (Android): files received from "Open with / Share",
/// and free storage space.
class NativeBridge {
  NativeBridge._() {
    _channel.setMethodCallHandler(_onCall);
  }

  static final NativeBridge instance = NativeBridge._();
  static const _channel = MethodChannel('fyleon/native');

  final _filesReady = StreamController<void>.broadcast();

  /// Fires when new incoming files were copied and are ready to be taken.
  Stream<void> get onFilesReady => _filesReady.stream;

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'filesReady') _filesReady.add(null);
    return null;
  }

  Future<List<String>> takeFiles() async {
    if (!isAndroid) return const [];
    try {
      final r = await _channel.invokeMethod<List<Object?>>('takeFiles');
      return r?.whereType<String>().toList() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Opens the system installer for an APK. Returns started / need_permission / error...
  Future<String> installApk(String path) async {
    if (!isAndroid) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('installApk', {'path': path}) ?? 'error';
    } catch (e) {
      return 'error: $e';
    }
  }

  Future<bool> openPlayProtect() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openPlayProtect') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<StorageInfo?> storageInfo(String path) async {
    if (!isAndroid) return null;
    try {
      final r = await _channel.invokeMethod<Map<Object?, Object?>>('storageInfo', {'path': path});
      if (r == null) return null;
      final total = r['total'];
      final free = r['free'];
      if (total is int && free is int) return StorageInfo(total, free);
    } catch (_) {}
    return null;
  }

  // ------------------------------------------------------------ share / open with
  Future<bool> shareFiles(List<String> paths) async {
    if (!isAndroid || paths.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('shareFiles', {'paths': paths}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openWith(String path) async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openWith', {'path': path}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> deviceName() async {
    if (!isAndroid) return '';
    try {
      return await _channel.invokeMethod<String>('deviceName') ?? '';
    } catch (_) {
      return '';
    }
  }

  // ------------------------------------------------------------ apps
  Future<List<InstalledApp>> listApps({bool includeSystem = true}) async {
    if (!isAndroid) return const [];
    try {
      final r = await _channel.invokeMethod<List<Object?>>('listApps', {'includeSystem': includeSystem});
      final out = <InstalledApp>[];
      for (final e in r ?? const <Object?>[]) {
        if (e is Map) {
          final a = InstalledApp.fromMap(e.cast<Object?, Object?>());
          if (a != null) out.add(a);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<Uint8List?> appIcon(String pkg, {int size = 96}) async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('appIcon', {'pkg': pkg, 'size': size});
    } catch (_) {
      return null;
    }
  }

  Future<bool> hasUsageAccess() async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('hasUsageAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openUsageAccess() => _bool('openUsageAccess');

  /// Sizes of all apps, or only of [pkgs] (much faster). Empty without "Usage access".
  Future<Map<String, AppStats>> appStats({List<String>? pkgs}) async {
    if (!isAndroid) return const {};
    try {
      final r = await _channel.invokeMethod<Map<Object?, Object?>>('appStats', {'pkgs': pkgs});
      final out = <String, AppStats>{};
      r?.forEach((k, v) {
        if (k is String && v is Map) {
          int n(Object? x) => x is int ? x : (x is num ? x.toInt() : 0);
          final last = n(v['last']);
          out[k] = AppStats(
            app: n(v['app']),
            data: n(v['data']),
            cache: n(v['cache']),
            lastUsed: last > 0 ? DateTime.fromMillisecondsSinceEpoch(last) : null,
          );
        }
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  Future<bool> openAppInfo(String pkg) => _bool('openAppInfo', {'pkg': pkg});

  Future<bool> uninstallApp(String pkg) => _bool('uninstallApp', {'pkg': pkg});

  Future<bool> launchApp(String pkg) => _bool('launchApp', {'pkg': pkg});

  /// Copies the app's base APK to the cache folder and returns the path (null on error).
  Future<String?> extractApk(String pkg) async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('extractApk', {'pkg': pkg});
    } catch (_) {
      return null;
    }
  }

  /// Android's own dialog "clear all apps' cache" (external cache folders only).
  /// Returns cleared / cancelled / unsupported / error...
  Future<String> clearAllCacheDialog() async {
    if (!isAndroid) return 'unsupported';
    try {
      return await _channel.invokeMethod<String>('clearAllCache') ?? 'error';
    } catch (e) {
      return 'error: $e';
    }
  }

  // ------------------------------------------------------------ Dash helpers
  Future<bool> openHotspotSettings() => _bool('openHotspotSettings');

  Future<bool> openWifiSettings() => _bool('openWifiSettings');

  Future<bool> multicastLock(bool on) => _bool('multicastLock', {'on': on});

  // ------------------------------------------------------------ video player
  Future<VideoInfo?> videoInfo(String path) async {
    if (!isAndroid) return null;
    try {
      final r = await _channel.invokeMethod<Map<Object?, Object?>>('videoInfo', {'path': path});
      return r == null ? null : VideoInfo.fromMap(r);
    } catch (_) {
      return null;
    }
  }

  /// JPEG bytes of a frame of the video, or null.
  Future<Uint8List?> videoThumb(String path, {int width = 320}) async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<Uint8List>('videoThumb', {'path': path, 'width': width});
    } catch (_) {
      return null;
    }
  }

  /// Window brightness 0..1 (value < 0 = give control back to the system).
  Future<bool> setBrightness(double value) => _bool('setBrightness', {'value': value});

  Future<double> getBrightness() async {
    if (!isAndroid) return 0.5;
    try {
      return await _channel.invokeMethod<double>('getBrightness') ?? 0.5;
    } catch (_) {
      return 0.5;
    }
  }

  /// Media volume as 0..1 (null when unknown).
  Future<double?> getVolume() async {
    if (!isAndroid) return null;
    try {
      final r = await _channel.invokeMethod<Map<Object?, Object?>>('getVolume');
      if (r == null) return null;
      final cur = (r['cur'] as num?)?.toDouble() ?? 0;
      final max = (r['max'] as num?)?.toDouble() ?? 1;
      _volumeMax = max.toInt();
      return max <= 0 ? null : (cur / max).clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  int? _volumeMax;

  /// Sets the media volume from a 0..1 fraction (no system volume popup).
  Future<bool> setVolume(double fraction) async {
    if (!isAndroid) return false;
    try {
      if (_volumeMax == null) await getVolume();
      final max = _volumeMax ?? 15;
      return await _channel.invokeMethod<bool>('setVolume', {'index': (fraction.clamp(0.0, 1.0) * max).round()}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> keepScreenOn(bool on) => _bool('keepScreenOn', {'on': on});

  Future<bool> _bool(String method, [Map<String, Object?>? args]) async {
    if (!isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (_) {
      return false;
    }
  }
}
