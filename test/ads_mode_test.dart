// The release build must show the REAL ads, the debug build must show TEST ads.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyleon/core/config/app_config.dart';

const _json = {
  'admob': {
    'useTestAds': true,
    'android': {
      'appId': 'ca-app-pub-1~1',
      'banner': 'ca-app-pub-1/banner',
      'interstitial': 'ca-app-pub-1/inter',
      'rewarded': 'ca-app-pub-1/rew',
      'native': 'ca-app-pub-1/native',
      'rewardedInterstitial': 'ca-app-pub-1/rewinter',
      'appOpen': 'ca-app-pub-1/appopen',
    },
  },
};

void main() {
  test('live mode (release build) uses the real ids, even if useTestAds is true in the file', () {
    final c = AppConfig.fromJson(_json, mode: 'live');
    expect(c.useTestAds, isFalse);
    expect(c.adUnits.banner, 'ca-app-pub-1/banner');
    expect(c.adUnits.interstitial, 'ca-app-pub-1/inter');
    expect(c.adUnits.rewarded, 'ca-app-pub-1/rew');
    expect(c.adUnits.native, 'ca-app-pub-1/native');
    expect(c.adUnits.rewardedInterstitial, 'ca-app-pub-1/rewinter');
    expect(c.adUnits.appOpen, 'ca-app-pub-1/appopen');
  });

  test('test mode (debug build) always uses Google test ids', () {
    final c = AppConfig.fromJson({
      'admob': {'useTestAds': false, 'android': (_json['admob']! as Map)['android']},
    }, mode: 'test');
    expect(c.useTestAds, isTrue);
    expect(c.adUnits.banner, AppConfig.androidTestIds.banner);
    expect(c.adUnits.appOpen, AppConfig.androidTestIds.appOpen);
  });

  test('auto mode follows the file', () {
    expect(AppConfig.fromJson(_json).useTestAds, isTrue);
    final off = AppConfig.fromJson({
      'admob': {'useTestAds': false, 'android': (_json['admob']! as Map)['android']},
    });
    expect(off.useTestAds, isFalse);
    expect(off.adUnits.banner, 'ca-app-pub-1/banner');
  });

  test('empty ids fall back to test ids; iOS uses the iOS test ids', () {
    final c = AppConfig.fromJson({'admob': {'useTestAds': false}}, mode: 'live');
    expect(c.adUnits.banner, AppConfig.androidTestIds.banner);
    final ios = AppConfig.fromJson({'admob': {'useTestAds': true}}, ios: true);
    expect(ios.adUnits.banner, AppConfig.iosTestIds.banner);
  });

  test('config/fyleon_config.json has real Android ids for every format (guards against an overwritten blank config)', () {
    final json = jsonDecode(File('config/fyleon_config.json').readAsStringSync()) as Map<String, dynamic>;
    final android = ((json['admob'] as Map)['android'] as Map).cast<String, dynamic>();
    expect(RegExp(r'^ca-app-pub-\d+~\d+$').hasMatch(android['appId'] as String), isTrue, reason: 'appId');
    for (final k in ['banner', 'interstitial', 'rewarded', 'native', 'rewardedInterstitial', 'appOpen']) {
      final v = android[k] as String;
      expect(RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(v), isTrue, reason: k);
      expect(v.contains('3940256099942544'), isFalse, reason: '$k must not be a Google test id');
    }
  });
}
