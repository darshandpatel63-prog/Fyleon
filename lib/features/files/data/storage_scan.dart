import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/file_category.dart';
import '../domain/file_item.dart';
import '../domain/file_kind.dart';

class ScanResult {
  const ScanResult({
    required this.byCategory,
    required this.bytes,
    required this.downloadsBytes,
    required this.recent,
  });

  final Map<FileCategory, List<FileItem>> byCategory;
  final Map<FileCategory, int> bytes;
  final int downloadsBytes;
  final List<FileItem> recent;

  int count(FileCategory c) => byCategory[c]?.length ?? 0;
}

const _maxEntries = 400000;

/// Walks the whole storage once and sorts files into categories.
/// Runs in an isolate via compute(). Skips hidden folders and the Android/ folder.
ScanResult scanStorage(String root) {
  final byCat = <FileCategory, List<FileItem>>{for (final c in FileCategory.values) c: <FileItem>[]};
  final bytes = <FileCategory, int>{for (final c in FileCategory.values) c: 0};
  var downloads = 0;
  final downloadDir = p.join(root, 'Download');
  var seen = 0;

  final stack = <String>[root];
  while (stack.isNotEmpty && seen < _maxEntries) {
    final dir = stack.removeLast();
    final inDownloads = dir == downloadDir || p.isWithin(downloadDir, dir);
    List<FileSystemEntity> entries;
    try {
      entries = Directory(dir).listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in entries) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        if (dir == root && name == 'Android') continue;
        stack.add(e.path);
      } else if (e is File) {
        seen++;
        final ext = extensionOf(name);
        final cat = categoryOfExtension(ext);
        if (cat == null && !inDownloads) continue;
        FileStat st;
        try {
          st = e.statSync();
        } catch (_) {
          continue;
        }
        if (inDownloads) downloads += st.size;
        if (cat == null) continue;
        byCat[cat]!.add(FileItem(
          path: e.path,
          name: name,
          size: st.size,
          modified: st.modified,
          added: st.changed,
          kind: kindForExtension(ext),
        ));
        bytes[cat] = bytes[cat]! + st.size;
      }
    }
  }

  final recentSource = <FileItem>[
    ...byCat[FileCategory.images]!,
    ...byCat[FileCategory.videos]!,
    ...byCat[FileCategory.audio]!,
    ...byCat[FileCategory.documents]!,
  ]..sort((a, b) => b.modified.compareTo(a.modified));

  return ScanResult(
    byCategory: byCat,
    bytes: bytes,
    downloadsBytes: downloads,
    recent: recentSource.take(14).toList(),
  );
}
