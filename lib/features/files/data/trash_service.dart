import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_ops.dart';

/// Recycle bin. Deleted items are MOVED into a hidden ".FyleonTrash" folder on the same
/// storage (fast, no copy), together with a small meta.json, so they can be restored.
class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.name,
    required this.originalPath,
    required this.storedPath,
    required this.trashDir,
    required this.isDir,
    required this.size,
    required this.deletedAt,
  });

  final String id;
  final String name;
  final String originalPath;
  final String storedPath;
  final String trashDir;
  final bool isDir;
  final int size;
  final DateTime deletedAt;
}

const trashFolderName = '.FyleonTrash';

/// The storage volume (internal / SD card) that a path lives on.
String volumeRootOf(String path) {
  const internal = '/storage/emulated/0';
  if (path == internal || path.startsWith('$internal/')) return internal;
  final m = RegExp(r'^/storage/[^/]+').firstMatch(path);
  if (m != null) return m.group(0)!;
  return Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? p.dirname(path);
}

String trashRootOf(String path) => p.join(volumeRootOf(path), trashFolderName);

Future<TrashEntry> moveToTrash(String path, {String? trashRoot}) async {
  final root = trashRoot ?? trashRootOf(path);
  final id = DateTime.now().microsecondsSinceEpoch.toString();
  final dir = p.join(root, id);
  try {
    await Directory(dir).create(recursive: true);
    final nomedia = File(p.join(root, '.nomedia'));
    if (!nomedia.existsSync()) await nomedia.writeAsString('');
  } catch (e) {
    throw friendlyError(e);
  }
  final isDir = FileSystemEntity.isDirectorySync(path);
  var size = 0;
  if (!isDir) {
    try {
      size = File(path).lengthSync();
    } catch (_) {}
  }
  final stored = await moveEntity(path, dir);
  if (stored == null) throw const FileOpException('Could not move to trash');
  final now = DateTime.now();
  await File(p.join(dir, 'meta.json')).writeAsString(jsonEncode({
    'name': p.basename(path),
    'original': path,
    'deletedAt': now.millisecondsSinceEpoch,
    'isDir': isDir,
    'size': size,
  }));
  return TrashEntry(
    id: id,
    name: p.basename(path),
    originalPath: path,
    storedPath: stored,
    trashDir: dir,
    isDir: isDir,
    size: size,
    deletedAt: now,
  );
}

/// Reads every trash folder under the given storage volumes (newest first).
List<TrashEntry> listTrash(Iterable<String> volumeRoots) {
  final out = <TrashEntry>[];
  for (final v in volumeRoots) {
    final root = Directory(p.join(v, trashFolderName));
    if (!root.existsSync()) continue;
    List<FileSystemEntity> items;
    try {
      items = root.listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final d in items) {
      if (d is! Directory) continue;
      final metaFile = File(p.join(d.path, 'meta.json'));
      if (!metaFile.existsSync()) continue;
      try {
        final m = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        final name = m['name'] as String;
        final stored = p.join(d.path, name);
        if (FileSystemEntity.typeSync(stored) == FileSystemEntityType.notFound) continue;
        out.add(TrashEntry(
          id: p.basename(d.path),
          name: name,
          originalPath: m['original'] as String,
          storedPath: stored,
          trashDir: d.path,
          isDir: m['isDir'] == true,
          size: (m['size'] as num?)?.toInt() ?? 0,
          deletedAt: DateTime.fromMillisecondsSinceEpoch((m['deletedAt'] as num).toInt()),
        ));
      } catch (_) {}
    }
  }
  out.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  return out;
}

/// Puts the item back where it came from (a new name is used if that name is taken now).
Future<String> restoreEntry(TrashEntry e) async {
  final target = p.dirname(e.originalPath);
  try {
    await Directory(target).create(recursive: true);
  } catch (err) {
    throw friendlyError(err);
  }
  final restored = await moveEntity(e.storedPath, target);
  await deleteEntity(e.trashDir);
  return restored ?? e.originalPath;
}

Future<void> deleteForever(TrashEntry e) => deleteEntity(e.trashDir);

/// Removes trash items older than [age]. Returns how many were removed.
Future<int> purgeOlderThan(Iterable<String> volumeRoots, Duration age) async {
  final limit = DateTime.now().subtract(age);
  var n = 0;
  for (final e in listTrash(volumeRoots)) {
    if (e.deletedAt.isBefore(limit)) {
      try {
        await deleteEntity(e.trashDir);
        n++;
      } catch (_) {}
    }
  }
  return n;
}
