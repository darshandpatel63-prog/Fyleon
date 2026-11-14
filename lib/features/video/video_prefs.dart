import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs.dart';
import 'video_models.dart';

class VideoSettingsNotifier extends Notifier<VideoSettings> {
  static const _key = 'video_settings_v1';

  @override
  VideoSettings build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw != null) {
      try {
        return VideoSettings.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    return const VideoSettings();
  }

  Future<void> update(VideoSettings Function(VideoSettings) change) async {
    state = change(state);
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(state.toJson()));
  }

  Future<void> reset() => update((_) => const VideoSettings());
}

final videoSettingsProvider = NotifierProvider<VideoSettingsNotifier, VideoSettings>(VideoSettingsNotifier.new);

/// Resume points + what was watched (also the "Recently played" list).
class VideoHistoryNotifier extends Notifier<Map<String, VideoRecord>> {
  static const _key = 'video_history_v1';

  @override
  Map<String, VideoRecord> build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw != null) {
      try {
        final j = jsonDecode(raw);
        if (j is Map) {
          final out = <String, VideoRecord>{};
          j.forEach((k, v) {
            final r = VideoRecord.fromJson(v);
            if (k is String && r != null) out[k] = r;
          });
          return out;
        }
      } catch (_) {}
    }
    return {};
  }

  VideoRecord? of(String path) => state[path];

  Future<void> record(String path, {required Duration position, required Duration duration, String? subtitle, int subDelayMs = 0}) async {
    final next = {
      ...state,
      path: VideoRecord(
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        lastPlayed: DateTime.now(),
        subtitle: subtitle,
        subDelayMs: subDelayMs,
      ),
    };
    state = trimHistory(next);
    await _save();
  }

  Future<void> remove(String path) async {
    if (!state.containsKey(path)) return;
    state = {...state}..remove(path);
    await _save();
  }

  Future<void> clear() async {
    state = {};
    await _save();
  }

  Future<void> _save() async {
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode({for (final e in state.entries) e.key: e.value.toJson()}));
  }
}

final videoHistoryProvider = NotifierProvider<VideoHistoryNotifier, Map<String, VideoRecord>>(VideoHistoryNotifier.new);
