import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/config/app_config.dart';
import '../../core/remote/remote_settings.dart';
import '../../core/utils/platform_utils.dart';

/// All AdMob logic lives here. Rules:
///  - ads NEVER delay opening a file
///  - interstitial only AFTER the user closes a file (frequency capped)
///  - rewarded only when the user taps "watch ad" (premium themes)
class AdService {
  AdService(this._ref);

  final Ref _ref;

  bool get supported => adsSupported;
  bool _initialized = false;
  Future<void>? _initFuture;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  Completer<void>? _rewardedLoading;
  DateTime? _lastInterstitial;
  int _fileCloses = 0;

  bool get initialized => _initialized;
  AdUnitIds get ids => _ref.read(appConfigProvider).adUnits;
  RemoteSettings get _remote => _ref.read(remoteSettingsProvider);

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    if (!supported) return;
    try {
      await _gatherConsent();
      final canRequest = await ConsentInformation.instance.canRequestAds();
      if (!canRequest) return;
      await MobileAds.instance.initialize();
      _initialized = true;
      _loadInterstitial();
      _loadRewarded();
    } catch (e) {
      debugPrint('Ads init failed: $e');
    }
  }

  /// EU/UK consent (UMP). Shows a form only if AdMob says it is required.
  Future<void> _gatherConsent() {
    final c = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
          if (!c.isCompleted) c.complete();
        });
      },
      (FormError error) {
        if (!c.isCompleted) c.complete();
      },
    );
    return c.future.timeout(const Duration(seconds: 45), onTimeout: () {});
  }

  // ---------------- banner ----------------
  bool get bannerAllowed => supported && _remote.bannerEnabled;

  bool get nativeAllowed => supported && _remote.nativeEnabled;

  // ---------------- interstitial ----------------
  void _loadInterstitial() {
    if (!_initialized) return;
    InterstitialAd.load(
      adUnitId: ids.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (error) => _interstitial = null,
      ),
    );
  }

  /// Call when the user has CLOSED a file viewer (never before opening).
  void onFileClosed() {
    if (!_initialized || !_remote.interstitialEnabled) return;
    _fileCloses++;
    if (_fileCloses % _remote.interstitialEveryNFileCloses != 0) return;
    final last = _lastInterstitial;
    if (last != null &&
        DateTime.now().difference(last).inSeconds <
            _remote.interstitialMinGapSeconds) {
      return;
    }
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        _loadInterstitial();
      },
    );
    _lastInterstitial = DateTime.now();
    ad.show();
  }

  // ---------------- rewarded ----------------
  bool get rewardedAllowed => _remote.rewardedEnabled;

  Future<void> _loadRewarded() {
    if (!_initialized) return Future.value();
    final running = _rewardedLoading;
    if (running != null) return running.future;
    final c = Completer<void>();
    _rewardedLoading = c;
    RewardedAd.load(
      adUnitId: ids.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          _rewardedLoading = null;
          c.complete();
        },
        onAdFailedToLoad: (error) {
          _rewarded = null;
          _rewardedLoading = null;
          c.complete();
        },
      ),
    );
    return c.future;
  }

  /// Returns true only if the user earned the reward.
  Future<bool> showRewarded() async {
    if (!_initialized) await init();
    if (!_initialized) return false;
    if (_rewarded == null) {
      await _loadRewarded().timeout(const Duration(seconds: 6), onTimeout: () {});
    }
    final ad = _rewarded;
    if (ad == null) return false;
    _rewarded = null;

    final result = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (a, error) {
        a.dispose();
        _loadRewarded();
        if (!result.isCompleted) result.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (view, reward) => earned = true);
    return result.future;
  }
}

final adServiceProvider = Provider<AdService>((ref) => AdService(ref));
