import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_kind.dart';

String extensionOf(String name) {
  final e = p.extension(name);
  if (e.isEmpty) {
    // "Dockerfile" style names
    final lower = name.toLowerCase();
    return lower == 'dockerfile' ? 'dockerfile' : '';
  }
  return e.substring(1).toLowerCase();
}

class FileItem {
  const FileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
    required this.added,
    required this.kind,
    this.isDir = false,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;

  /// Best available "added" time (inode change time on Android/Linux).
  final DateTime added;
  final FileKind kind;
  final bool isDir;

  String get ext => extensionOf(name);

  static FileItem? tryFromPath(String path) {
    try {
      final stat = FileStat.statSync(path);
      if (stat.type == FileSystemEntityType.notFound) return null;
      final name = p.basename(path);
      final isDir = stat.type == FileSystemEntityType.directory;
      return FileItem(
        path: path,
        name: name,
        size: isDir ? 0 : stat.size,
        modified: stat.modified,
        added: stat.changed,
        kind: isDir ? FileKind.other : kindForExtension(extensionOf(name)),
        isDir: isDir,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Top-level so it can run in an isolate via compute().
List<FileItem> listDirectory(String path) {
  final out = <FileItem>[];
  try {
    for (final e in Directory(path).listSync(followLinks: false)) {
      if (p.basename(e.path).startsWith('.')) continue;
      final item = FileItem.tryFromPath(e.path);
      if (item != null) out.add(item);
    }
  } catch (_) {}
  return out;
}
