import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/storage/prefs.dart';
import '../data/safe_service.dart';
import '../data/storage_scan.dart';
import '../data/trash_service.dart';
import 'browse_controller.dart';

// ---------------- starred + favorites (sets of paths) ----------------
abstract class PathSetNotifier extends Notifier<Set<String>> {
  String get prefsKey;

  @override
  Set<String> build() {
    final raw = ref.read(sharedPrefsProvider).getStringList(prefsKey);
    return {...?raw};
  }

  bool contains(String path) => state.contains(path);

  Future<void> toggle(String path) async {
    final next = {...state};
    if (!next.add(path)) next.remove(path);
    await _save(next);
  }

  Future<void> remove(String path) async {
    if (!state.contains(path)) return;
    await _save({...state}..remove(path));
  }

  Future<void> rename(String from, String to) async {
    if (!state.contains(from)) return;
    await _save({...state}..remove(from)..add(to));
  }

  Future<void> _save(Set<String> next) async {
    state = next;
    await ref.read(sharedPrefsProvider).setStringList(prefsKey, next.toList());
  }
}

class StarredNotifier extends PathSetNotifier {
  @override
  String get prefsKey => 'starred_v1';
}

class FavoritesNotifier extends PathSetNotifier {
  @override
  String get prefsKey => 'favorites_v1';
}

final starredProvider = NotifierProvider<StarredNotifier, Set<String>>(StarredNotifier.new);
final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<String>>(FavoritesNotifier.new);

// ---------------- trash ----------------
List<String> trashVolumes() => storageRoots()
    .where((r) => r.label.startsWith('Internal') || r.label.startsWith('SD card') || r.label == 'Home')
    .map((r) => r.path)
    .toList();

class TrashNotifier extends Notifier<List<TrashEntry>> {
  static const keepDays = 30;

  @override
  List<TrashEntry> build() => const [];

  void refresh() => state = listTrash(trashVolumes());

  Future<void> purgeOld() async {
    await purgeOlderThan(trashVolumes(), const Duration(days: keepDays));
    refresh();
  }

  Future<void> restore(TrashEntry e) async {
    await restoreEntry(e);
    refresh();
  }

  Future<void> deleteOne(TrashEntry e) async {
    await deleteForever(e);
    refresh();
  }

  Future<void> emptyAll() async {
    for (final e in state) {
      try {
        await deleteForever(e);
      } catch (_) {}
    }
    refresh();
  }
}

final trashProvider = NotifierProvider<TrashNotifier, List<TrashEntry>>(TrashNotifier.new);

// ---------------- safe folder ----------------
final safeServiceProvider = Provider<SafeService>((ref) => SafeService(ref.read(sharedPrefsProvider)));

// ---------------- storage scan (categories) ----------------
final storageScanProvider = FutureProvider<ScanResult?>((ref) async {
  final roots = storageRoots();
  if (roots.isEmpty) return null;
  final internal = roots.firstWhere((r) => r.label.startsWith('Internal') || r.label == 'Home', orElse: () => roots.first);
  return compute(scanStorage, internal.path);
});

String parentFolderName(String path) => p.basename(p.dirname(path));
