import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_service.dart';

/// A small native ad (clearly labelled "Ad" by AdMob) shown between files.
/// It stays invisible until it is loaded, so it never leaves an empty gap.
class NativeAdTile extends ConsumerStatefulWidget {
  const NativeAdTile({super.key});

  @override
  ConsumerState<NativeAdTile> createState() => _NativeAdTileState();
}

class _NativeAdTileState extends ConsumerState<NativeAdTile> with AutomaticKeepAliveClientMixin {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final ads = ref.read(adServiceProvider);
    if (!ads.supported) return;
    await ads.init();
    if (!mounted || !ads.initialized || !ads.nativeAllowed) return;
    final ad = NativeAd(
      adUnitId: ads.ids.native,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(templateType: TemplateType.small),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 90, maxHeight: 130),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
