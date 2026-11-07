import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/platform_utils.dart';

class AdUnitIds {
  const AdUnitIds({
    required this.banner,
    required this.interstitial,
    required this.rewarded,
    required this.native,
  });

  final String banner;
  final String interstitial;
  final String rewarded;
  final String native;
}

/// Reads config/fyleon_config.json (the file YOU fill in).
class AppConfig {
  const AppConfig({
    required this.useTestAds,
    required this.adUnits,
    required this.remoteConfigUrl,
    required this.allFilesAccess,
  });

  final bool useTestAds;
  final AdUnitIds adUnits;
  final String remoteConfigUrl;
  final bool allFilesAccess;

  // Google's public TEST ad unit ids. Safe to click.
  static const androidTestIds = AdUnitIds(
    banner: 'ca-app-pub-3940256099942544/6300978111',
    interstitial: 'ca-app-pub-3940256099942544/1033173712',
    rewarded: 'ca-app-pub-3940256099942544/5224354917',
    native: 'ca-app-pub-3940256099942544/2247696110',
  );
  static const iosTestIds = AdUnitIds(
    banner: 'ca-app-pub-3940256099942544/2934735716',
    interstitial: 'ca-app-pub-3940256099942544/4411468910',
    rewarded: 'ca-app-pub-3940256099942544/1712485313',
    native: 'ca-app-pub-3940256099942544/3986624511',
  );

  static AdUnitIds get testIds => isIOS ? iosTestIds : androidTestIds;

  static AppConfig defaults() => AppConfig(
        useTestAds: true,
        adUnits: testIds,
        remoteConfigUrl: '',
        allFilesAccess: false,
      );

  static Future<AppConfig> load() async {
    try {
      final raw = await rootBundle.loadString('config/fyleon_config.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final admob = (json['admob'] as Map?)?.cast<String, dynamic>() ?? {};
      final useTest = admob['useTestAds'] != false;
      final platform = (admob[isIOS ? 'ios' : 'android'] as Map?)
              ?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final test = testIds;

      String pick(String key, String fallback) {
        final v = ((platform[key] as String?) ?? '').trim();
        return (useTest || v.isEmpty) ? fallback : v;
      }

      final features =
          (json['features'] as Map?)?.cast<String, dynamic>() ?? {};
      final remote =
          (json['remoteConfig'] as Map?)?.cast<String, dynamic>() ?? {};

      return AppConfig(
        useTestAds: useTest,
        adUnits: AdUnitIds(
          banner: pick('banner', test.banner),
          interstitial: pick('interstitial', test.interstitial),
          rewarded: pick('rewarded', test.rewarded),
          native: pick('native', test.native),
        ),
        remoteConfigUrl: ((remote['githubJsonUrl'] as String?) ?? '').trim(),
        allFilesAccess: features['allFilesAccess'] == true,
      );
    } catch (_) {
      return defaults();
    }
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.defaults());
