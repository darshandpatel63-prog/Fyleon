import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyleon/features/files/data/storage_scan.dart';
import 'package:fyleon/features/files/data/trash_service.dart';
import 'package:fyleon/features/files/domain/file_category.dart';

void main() {
  late Directory vol;

  setUp(() => vol = Directory.systemTemp.createTempSync('fyleon_vol_'));
  tearDown(() {
    if (vol.existsSync()) vol.deleteSync(recursive: true);
  });

  test('trash: delete, list, restore', () async {
    final f = File('${vol.path}/docs/a.txt')..createSync(recursive: true);
    f.writeAsStringSync('hello');
    final root = '${vol.path}/$trashFolderName';

    final entry = await moveToTrash(f.path, trashRoot: root);
    expect(f.existsSync(), isFalse);
    expect(File(entry.storedPath).existsSync(), isTrue);

    final listed = listTrash([vol.path]);
    expect(listed.length, 1);
    expect(listed.first.name, 'a.txt');
    expect(listed.first.originalPath, f.path);

    final back = await restoreEntry(listed.first);
    expect(File(back).readAsStringSync(), 'hello');
    expect(listTrash([vol.path]), isEmpty);
  });

  test('trash: delete forever and purge old', () async {
    final f = File('${vol.path}/b.txt')..writeAsStringSync('x');
    final root = '${vol.path}/$trashFolderName';
    final entry = await moveToTrash(f.path, trashRoot: root);
    await deleteForever(entry);
    expect(listTrash([vol.path]), isEmpty);

    final g = File('${vol.path}/c.txt')..writeAsStringSync('y');
    await moveToTrash(g.path, trashRoot: root);
    expect(await purgeOlderThan([vol.path], const Duration(days: 30)), 0);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(await purgeOlderThan([vol.path], Duration.zero), 1);
  });

  test('trash: folders keep their content', () async {
    final d = Directory('${vol.path}/proj')..createSync();
    File('${d.path}/index.html').writeAsStringSync('<p>');
    final root = '${vol.path}/$trashFolderName';
    final e = await moveToTrash(d.path, trashRoot: root);
    expect(e.isDir, isTrue);
    expect(File('${e.storedPath}/index.html').existsSync(), isTrue);
    await restoreEntry(listTrash([vol.path]).first);
    expect(File('${d.path}/index.html').existsSync(), isTrue);
  });

  test('storage scan sorts files into categories and skips hidden/Android', () {
    void make(String rel, [String data = 'abc']) => File('${vol.path}/$rel')
      ..createSync(recursive: true)
      ..writeAsStringSync(data);
    make('DCIM/a.jpg');
    make('Movies/b.mp4');
    make('Music/c.mp3');
    make('Documents/d.pdf');
    make('Download/e.zip', '12345');
    make('Download/readme.xyz', '123456789');
    make('.hidden/f.jpg');
    make('Android/data/g.jpg');
    make('stuff/h.unknown');

    final r = scanStorage(vol.path);
    expect(r.count(FileCategory.images), 1);
    expect(r.count(FileCategory.videos), 1);
    expect(r.count(FileCategory.audio), 1);
    expect(r.count(FileCategory.documents), 1);
    expect(r.count(FileCategory.packages), 1);
    expect(r.downloadsBytes, 14); // e.zip (5) + readme.xyz (9)
    expect(r.recent.length, 4);
  });

  test('category by extension', () {
    expect(categoryOfExtension('JPG'), FileCategory.images);
    expect(categoryOfExtension('mkv'), FileCategory.videos);
    expect(categoryOfExtension('flac'), FileCategory.audio);
    expect(categoryOfExtension('docx'), FileCategory.documents);
    expect(categoryOfExtension('apk'), FileCategory.packages);
    expect(categoryOfExtension('dart'), isNull);
  });
}
