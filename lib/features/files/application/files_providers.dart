import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/storage/prefs.dart';
import '../domain/file_item.dart';
import '../domain/file_kind.dart';
import '../domain/files_logic.dart';

// ---------- view mode (list / grid) ----------
class ViewModeNotifier extends Notifier<ViewMode> {
  static const _key = 'view_mode';

  @override
  ViewMode build() {
    final v = ref.read(sharedPrefsProvider).getString(_key);
    return v == 'grid' ? ViewMode.grid : ViewMode.list;
  }

  Future<void> toggle() async {
    state = state == ViewMode.list ? ViewMode.grid : ViewMode.list;
    await ref.read(sharedPrefsProvider).setString(_key, state.name);
  }
}

final viewModeProvider =
    NotifierProvider<ViewModeNotifier, ViewMode>(ViewModeNotifier.new);

// ---------- sort ----------
class SortNotifier extends Notifier<SortOption> {
  static const _key = 'sort_option';

  @override
  SortOption build() {
    final v = ref.read(sharedPrefsProvider).getString(_key);
    for (final o in SortOption.values) {
      if (o.name == v) return o;
    }
    return SortOption.lastOpened;
  }

  Future<void> set(SortOption o) async {
    state = o;
    await ref.read(sharedPrefsProvider).setString(_key, o.name);
  }
}

final sortProvider =
    NotifierProvider<SortNotifier, SortOption>(SortNotifier.new);

// ---------- filter chips + search ----------
class KindFilterNotifier extends Notifier<KindFilter> {
  @override
  KindFilter build() => KindFilter.all;
  void set(KindFilter f) => state = f;
}

final kindFilterProvider =
    NotifierProvider<KindFilterNotifier, KindFilter>(KindFilterNotifier.new);

class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void set(String q) => state = q;
}

final searchQueryProvider =
    NotifierProvider<SearchQueryNotifier, String>(SearchQueryNotifier.new);

// ---------- recents ----------
class RecentFile {
  const RecentFile(this.item, this.openedAt);
  final FileItem item;
  final DateTime openedAt;
}

class RecentsNotifier extends Notifier<List<RecentFile>> {
  static const _key = 'recents_v1';

  @override
  List<RecentFile> build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <RecentFile>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        final item = FileItem.tryFromPath(m['p'] as String);
        if (item == null || item.isDir) continue; // file was deleted
        out.add(RecentFile(
          item,
          DateTime.fromMillisecondsSinceEpoch((m['t'] as num).toInt()),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> add(FileItem item) async {
    final next = <RecentFile>[
      RecentFile(item, DateTime.now()),
      ...state.where((r) => r.item.path != item.path),
    ];
    state = next.take(AppConstants.maxRecents).toList();
    await _save();
  }

  Future<void> remove(String path) async {
    state = state.where((r) => r.item.path != path).toList();
    await _save();
  }

  Future<void> clear() async {
    state = const [];
    await _save();
  }

  Future<void> _save() async {
    final data = state
        .map((r) => {'p': r.item.path, 't': r.openedAt.millisecondsSinceEpoch})
        .toList();
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(data));
  }
}

final recentsProvider =
    NotifierProvider<RecentsNotifier, List<RecentFile>>(RecentsNotifier.new);

/// path -> last opened time (used by the "Last opened" sort everywhere).
final openedMapProvider = Provider<Map<String, DateTime>>((ref) {
  final recents = ref.watch(recentsProvider);
  return {for (final r in recents) r.item.path: r.openedAt};
});
