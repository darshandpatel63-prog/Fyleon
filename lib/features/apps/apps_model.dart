import '../../core/native/native_bridge.dart';

enum AppTab { installed, system, apks }

enum AppChipFilter { large, unused, games }

enum AppSort { size, name, lastUsed, cache }

extension AppSortX on AppSort {
  String get label {
    switch (this) {
      case AppSort.size:
        return 'Size (largest first)';
      case AppSort.name:
        return 'Name A-Z';
      case AppSort.lastUsed:
        return 'Last used';
      case AppSort.cache:
        return 'Cache size';
    }
  }
}

const largeAppBytes = 100 * 1024 * 1024;
const unusedAfter = Duration(days: 30);

/// An installed app + its sizes (sizes exist only when the owner allowed "Usage access").
class AppEntry {
  const AppEntry(this.app, this.stats);

  final InstalledApp app;
  final AppStats? stats;

  /// App + data + cache when known, otherwise just the size of the APK file(s).
  int get size => stats?.total ?? app.apkSize;
  int get cache => stats?.cache ?? 0;
  DateTime? get lastUsed => stats?.lastUsed;
  bool get hasStats => stats != null;
}

/// Pure function: tab + chips + search + sort. Easy to unit test.
List<AppEntry> filterApps(
  List<AppEntry> all, {
  required AppTab tab,
  Set<AppChipFilter> chips = const {},
  String query = '',
  AppSort sort = AppSort.size,
  DateTime? now,
}) {
  final t = now ?? DateTime.now();
  final q = query.trim().toLowerCase();
  final out = all.where((e) {
    if (tab == AppTab.installed && e.app.system) return false;
    if (tab == AppTab.system && !e.app.system) return false;
    if (q.isNotEmpty && !e.app.label.toLowerCase().contains(q) && !e.app.pkg.toLowerCase().contains(q)) return false;
    if (chips.contains(AppChipFilter.large) && e.size < largeAppBytes) return false;
    if (chips.contains(AppChipFilter.games) && !e.app.game) return false;
    if (chips.contains(AppChipFilter.unused)) {
      // "unused" needs Usage access; without it nothing is called unused (we would only guess)
      if (!e.hasStats || !e.app.launchable) return false;
      final last = e.lastUsed;
      if (last != null && t.difference(last) < unusedAfter) return false;
    }
    return true;
  }).toList();

  int byName(AppEntry a, AppEntry b) => a.app.label.toLowerCase().compareTo(b.app.label.toLowerCase());
  out.sort((a, b) {
    switch (sort) {
      case AppSort.size:
        final c = b.size.compareTo(a.size);
        return c != 0 ? c : byName(a, b);
      case AppSort.name:
        return byName(a, b);
      case AppSort.lastUsed:
        final la = a.lastUsed;
        final lb = b.lastUsed;
        if (la == null && lb == null) return byName(a, b);
        if (la == null) return 1;
        if (lb == null) return -1;
        return lb.compareTo(la);
      case AppSort.cache:
        final c = b.cache.compareTo(a.cache);
        return c != 0 ? c : byName(a, b);
    }
  });
  return out;
}

int totalCacheOf(Iterable<AppEntry> list) => list.fold(0, (sum, e) => sum + e.cache);

int totalSizeOf(Iterable<AppEntry> list) => list.fold(0, (sum, e) => sum + e.size);
