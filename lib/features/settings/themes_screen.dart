import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/remote/remote_settings.dart';
import '../../core/theme/app_themes.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/platform_utils.dart';
import '../ads/ad_service.dart';

class ThemesScreen extends ConsumerWidget {
  const ThemesScreen({super.key});

  Future<void> _tap(BuildContext context, WidgetRef ref, FyleonThemeSpec spec) async {
    final ctrl = ref.read(themeControllerProvider.notifier);
    final state = ref.read(themeControllerProvider);
    if (state.isUnlocked(spec.id)) {
      await ctrl.select(spec.id);
      return;
    }
    final hours = ref.read(remoteSettingsProvider).premiumThemeUnlockHours;
    final ads = ref.read(adServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    if (!ads.rewardedAllowed) {
      messenger.showSnackBar(const SnackBar(content: Text('Premium themes are not available right now.')));
      return;
    }
    final watch = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_open_rounded),
        title: Text('Unlock ${spec.name}'),
        content: Text('Watch a short ad to use this premium theme for $hours hours.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.play_circle_rounded),
            label: const Text('Watch ad'),
          ),
        ],
      ),
    );
    if (watch != true) return;
    final earned = await ads.showRewarded();
    if (earned) {
      await ctrl.unlock(spec.id, Duration(hours: hours));
      await ctrl.select(spec.id);
      messenger.showSnackBar(SnackBar(content: Text('${spec.name} unlocked for $hours hours.')));
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('The ad is not ready. Check your internet and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(themeControllerProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Themes')),
      body: GridView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 1.05,
        ),
        children: [
          _card(
            context,
            name: 'Auto (system)',
            colors: const [Color(0xFFEEF0FF), Color(0xFF1B1840)],
            selected: state.selectedId == AppThemes.systemId,
            locked: false,
            badge: 'Free',
            onTap: () => ref.read(themeControllerProvider.notifier).select(AppThemes.systemId),
            scheme: scheme,
          ),
          for (final t in AppThemes.all)
            _card(
              context,
              name: t.name,
              colors: t.gradient,
              accent: t.seed,
              selected: state.selectedId == t.id,
              locked: !state.isUnlocked(t.id),
              badge: t.premium ? (adsSupported ? 'Watch ad' : 'Premium') : 'Free',
              onTap: () => _tap(context, ref, t),
              scheme: scheme,
            ),
        ],
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String name,
    required List<Color> colors,
    Color? accent,
    required bool selected,
    required bool locked,
    required String badge,
    required VoidCallback onTap,
    required ColorScheme scheme,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selected ? scheme.primary : Colors.transparent,
          width: 3,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(color: accent ?? Colors.white, shape: BoxShape.circle),
                    ),
                    if (locked)
                      const Icon(Icons.lock_rounded, color: Colors.white70, size: 20)
                    else if (selected)
                      const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                  ],
                ),
                const Spacer(),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black38)],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
