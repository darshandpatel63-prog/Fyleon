import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/prefs.dart';

/// Values that can be changed remotely (GitHub-hosted JSON now,
/// Firebase Remote Config later) without a store update.
class RemoteSettings {
  const RemoteSettings({
    this.bannerEnabled = true,
    this.interstitialEnabled = true,
    this.rewardedEnabled = true,
    this.nativeEnabled = true,
    this.nativeEveryNItems = 4,
    this.nativeMaxPerList = 6,
    this.dashNativeEveryNItems = 3,
    this.interstitialEveryNFileCloses = 4,
    this.interstitialMinGapSeconds = 180,
    this.premiumThemeUnlockHours = 24,
  });

  final bool bannerEnabled;
  final bool interstitialEnabled;
  final bool rewardedEnabled;
  final bool nativeEnabled;
  final int nativeEveryNItems;
  final int nativeMaxPerList;

  /// Dash (file sharing) screens: a native ad after every N files.
  final int dashNativeEveryNItems;
  final int interstitialEveryNFileCloses;
  final int interstitialMinGapSeconds;
  final int premiumThemeUnlockHours;

  factory RemoteSettings.fromJson(Map<String, dynamic> j) {
    final ads = (j['ads'] as Map?)?.cast<String, dynamic>() ?? {};
    final themes = (j['themes'] as Map?)?.cast<String, dynamic>() ?? {};
    bool b(Object? v, bool d) => v is bool ? v : d;
    int i(Object? v, int d, int min) =>
        v is num ? v.toInt().clamp(min, 100000) : d;
    return RemoteSettings(
      bannerEnabled: b(ads['banner'], true),
      interstitialEnabled: b(ads['interstitial'], true),
      rewardedEnabled: b(ads['rewarded'], true),
      nativeEnabled: b(ads['native'], true),
      nativeEveryNItems: i(ads['nativeEvery'], 4, 3),
      nativeMaxPerList: i(ads['nativeMax'], 6, 1),
      dashNativeEveryNItems: i(ads['dashNativeEvery'], 3, 2),
      interstitialEveryNFileCloses:
          i(ads['interstitialEveryNFileCloses'], 4, 2),
      interstitialMinGapSeconds: i(ads['interstitialMinGapSeconds'], 180, 60),
      premiumThemeUnlockHours: i(themes['premiumUnlockHours'], 24, 1),
    );
  }

  Map<String, dynamic> toJson() => {
        'ads': {
          'banner': bannerEnabled,
          'interstitial': interstitialEnabled,
          'rewarded': rewardedEnabled,
          'native': nativeEnabled,
          'nativeEvery': nativeEveryNItems,
          'nativeMax': nativeMaxPerList,
          'dashNativeEvery': dashNativeEveryNItems,
          'interstitialEveryNFileCloses': interstitialEveryNFileCloses,
          'interstitialMinGapSeconds': interstitialMinGapSeconds,
        },
        'themes': {'premiumUnlockHours': premiumThemeUnlockHours},
      };
}

class RemoteSettingsNotifier extends Notifier<RemoteSettings> {
  static const _key = 'remote_settings_v1';

  @override
  RemoteSettings build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw != null) {
      try {
        return RemoteSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {}
    }
    return const RemoteSettings();
  }

  /// Never throws. Uses cached/default values when offline.
  Future<void> refresh() async {
    final url = ref.read(appConfigProvider).remoteConfigUrl;
    if (url.isEmpty) return;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return;
      final body = await res.transform(utf8.decoder).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      final next = RemoteSettings.fromJson(map);
      state = next;
      await ref
          .read(sharedPrefsProvider)
          .setString(_key, jsonEncode(next.toJson()));
    } catch (_) {
      // keep cached values
    } finally {
      client.close();
    }
  }
}

final remoteSettingsProvider =
    NotifierProvider<RemoteSettingsNotifier, RemoteSettings>(
  RemoteSettingsNotifier.new,
);
