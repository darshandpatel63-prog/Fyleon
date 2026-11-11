import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/platform_utils.dart';

/// One shared audio player for the whole app. With `just_audio_background` it keeps playing when
/// the app is minimised or the screen is locked, and shows a notification with play / pause.
/// Videos use it too, when the owner switches a video to "audio only" or leaves the app.
class AudioEngine {
  AudioEngine._();

  static final AudioEngine instance = AudioEngine._();

  bool _backgroundReady = false;
  bool _askedNotification = false;
  AudioPlayer? _player;

  bool get backgroundReady => _backgroundReady;

  /// Called once from main(). Never throws: if it fails, audio still plays in the foreground.
  static Future<void> initBackground() async {
    if (!isAndroid && !isIOS) return;
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.fyleon.app.playback',
        androidNotificationChannelName: 'Fyleon playback',
        androidNotificationOngoing: true,
      );
      instance._backgroundReady = true;
    } catch (e) {
      debugPrint('Background audio init failed: $e');
    }
  }

  AudioPlayer get player => _player ??= AudioPlayer();

  /// Android 13+ needs this to show the playback notification (playback itself works without it).
  Future<void> ensureNotificationPermission() async {
    if (!isAndroid || _askedNotification) return;
    _askedNotification = true;
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  Future<void> load(String path, String title, {Duration? start}) async {
    await ensureNotificationPermission();
    await player.setAudioSource(
      AudioSource.uri(
        Uri.file(path),
        tag: MediaItem(id: path, title: title, album: 'Fyleon'),
      ),
      initialPosition: start,
    );
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
