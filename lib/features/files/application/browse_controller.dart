import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../../core/utils/platform_utils.dart';
import '../domain/file_item.dart';

class StorageRoot {
  const StorageRoot(this.label, this.path, this.icon);
  final String label;
  final String path;
  final IconData icon;
}

List<StorageRoot> storageRoots() {
  final out = <StorageRoot>[];
  if (isAndroid) {
    const internal = '/storage/emulated/0';
    out.add(const StorageRoot('Internal storage', internal, Icons.smartphone_rounded));
    const shortcuts = <(String, String, IconData)>[
      ('Download', 'Download', Icons.download_rounded),
      ('Documents', 'Documents', Icons.description_rounded),
      ('DCIM', 'DCIM', Icons.photo_camera_rounded),
      ('Pictures', 'Pictures', Icons.image_rounded),
      ('Music', 'Music', Icons.library_music_rounded),
      ('Movies', 'Movies', Icons.movie_rounded),
    ];
    for (final s in shortcuts) {
      final path = '$internal/${s.$2}';
      if (Directory(path).existsSync()) out.add(StorageRoot(s.$1, path, s.$3));
    }
    try {
      for (final e in Directory('/storage').listSync(followLinks: false)) {
        final n = p.basename(e.path);
        if (n == 'emulated' || n == 'self') continue;
        if (e is Directory) out.add(StorageRoot('SD card ($n)', e.path, Icons.sd_card_rounded));
      }
    } catch (_) {}
  } else if (isDesktop) {
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && Directory(home).existsSync()) {
      out.add(StorageRoot('Home', home, Icons.home_rounded));
      for (final n in ['Downloads', 'Documents', 'Desktop', 'Pictures']) {
        final path = p.join(home, n);
        if (Directory(path).existsSync()) out.add(StorageRoot(n, path, Icons.folder_rounded));
      }
    }
  }
  return out;
}

Future<bool> hasAllFilesAccess() async {
  if (!isAndroid) return true;
  if (await Permission.manageExternalStorage.isGranted) return true;
  return Permission.storage.isGranted;
}

Future<bool> requestAllFilesAccess() async {
  if (!isAndroid) return true;
  final st = await Permission.manageExternalStorage.request();
  if (st.isGranted) return true;
  final legacy = await Permission.storage.request();
  return legacy.isGranted;
}

/// Current folder in the Browse tab. null = the storage list.
class BrowsePathNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String path) => state = path;

  /// Returns false when already at the top (storage list).
  bool up() {
    final cur = state;
    if (cur == null) return false;
    final rootPaths = storageRoots().map((r) => r.path).toSet();
    state = rootPaths.contains(cur) ? null : p.dirname(cur);
    return true;
  }
}

final browsePathProvider =
    NotifierProvider<BrowsePathNotifier, String?>(BrowsePathNotifier.new);

final directoryListingProvider =
    FutureProvider.autoDispose.family<List<FileItem>, String>(
  (ref, path) => compute(listDirectory, path),
);
