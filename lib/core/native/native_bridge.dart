import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/platform_utils.dart';

class StorageInfo {
  const StorageInfo(this.total, this.free);
  final int total;
  final int free;
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
}
