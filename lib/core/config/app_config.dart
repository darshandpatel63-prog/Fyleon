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
    required this.rewardedInterstitial,
    required this.appOpen,
  });

  final String banner;
  final String interstitial;
  final String rewarded;
  final String native;

  /// Ready for later phases (the ids are in the config; the code does not show these formats yet).
  final String rewardedInterstitial;
  final String appOpen;
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
    rewardedInterstitial: 'ca-app-pub-3940256099942544/5354046379',
    appOpen: 'ca-app-pub-3940256099942544/9257395921',
  );
  static const iosTestIds = AdUnitIds(
    banner: 'ca-app-pub-3940256099942544/2934735716',
    interstitial: 'ca-app-pub-3940256099942544/4411468910',
    rewarded: 'ca-app-pub-3940256099942544/1712485313',
    native: 'ca-app-pub-3940256099942544/3986624511',
    rewardedInterstitial: 'ca-app-pub-3940256099942544/6978759866',
    appOpen: 'ca-app-pub-3940256099942544/5575463023',
  );

  static AdUnitIds get testIds => isIOS ? iosTestIds : androidTestIds;

  static AppConfig defaults() => AppConfig(
        useTestAds: true,
        adUnits: testIds,
        remoteConfigUrl: '',
        allFilesAccess: false,
      );

  /// Which ads this build shows. Set by the build workflow (`--dart-define=FYLEON_ADS=live|test`):
  /// - `live`  = release build: REAL ad units from config/fyleon_config.json (the file's useTestAds is ignored)
  /// - `test`  = debug build: Google TEST ads only
  /// - `auto`  = anything else (flutter run on a computer): follows `admob.useTestAds` of the config file
  static const adsMode = String.fromEnvironment('FYLEON_ADS', defaultValue: 'auto');

  /// Pure function (unit tested): decides test / live and the ad unit ids.
  static AppConfig fromJson(Map<String, dynamic> json, {String mode = 'auto', bool ios = false}) {
    final admob = (json['admob'] as Map?)?.cast<String, dynamic>() ?? {};
    final useTest = mode == 'live'
        ? false
        : mode == 'test'
            ? true
            : admob['useTestAds'] != false;
    final platform = (admob[ios ? 'ios' : 'android'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final test = ios ? iosTestIds : androidTestIds;

    String pick(String key, String fallback) {
      final v = ((platform[key] as String?) ?? '').trim();
      return (useTest || v.isEmpty) ? fallback : v;
    }

    final features = (json['features'] as Map?)?.cast<String, dynamic>() ?? {};
    final remote = (json['remoteConfig'] as Map?)?.cast<String, dynamic>() ?? {};

    return AppConfig(
      useTestAds: useTest,
      adUnits: AdUnitIds(
        banner: pick('banner', test.banner),
        interstitial: pick('interstitial', test.interstitial),
        rewarded: pick('rewarded', test.rewarded),
        native: pick('native', test.native),
        rewardedInterstitial: pick('rewardedInterstitial', test.rewardedInterstitial),
        appOpen: pick('appOpen', test.appOpen),
      ),
      remoteConfigUrl: ((remote['githubJsonUrl'] as String?) ?? '').trim(),
      allFilesAccess: features['allFilesAccess'] == true,
    );
  }

  static Future<AppConfig> load() async {
    try {
      final raw = await rootBundle.loadString('config/fyleon_config.json');
      return fromJson(jsonDecode(raw) as Map<String, dynamic>, mode: adsMode, ios: isIOS);
    } catch (_) {
      return defaults();
    }
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.defaults());
