import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyleon/features/files/data/file_ops.dart';
import 'package:fyleon/features/viewer/epub_layout.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('fyleon_test_');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('name validation', () {
    expect(validateName('ok.txt'), isNull);
    expect(validateName(''), isNotNull);
    expect(validateName('a/b'), isNotNull);
    expect(validateName('..'), isNotNull);
  });

  test('create, rename, copy, move, delete', () async {
    final folder = await createFolder(tmp.path, 'proj');
    expect(Directory(folder).existsSync(), isTrue);

    final file = await createFile(folder, 'a.txt', content: 'hello');
    expect(File(file).readAsStringSync(), 'hello');

    expect(() => createFile(folder, 'a.txt'), throwsA(isA<FileOpException>()));

    final renamed = await renameEntity(file, 'b.txt');
    expect(File(renamed).existsSync(), isTrue);
    expect(File(file).existsSync(), isFalse);

    final other = await createFolder(tmp.path, 'other');
    await copyEntity(renamed, other);
    expect(File('$other/b.txt').existsSync(), isTrue);
    // copying again creates "b (1).txt"
    await copyEntity(renamed, other);
    expect(File('$other/b (1).txt').existsSync(), isTrue);

    await moveEntity(renamed, other);
    expect(File(renamed).existsSync(), isFalse);

    await deleteEntity(folder);
    expect(Directory(folder).existsSync(), isFalse);
  });

  test('cannot copy a folder into itself', () async {
    final folder = await createFolder(tmp.path, 'x');
    final inner = await createFolder(folder, 'inner');
    expect(() => copyEntity(folder, inner), throwsA(isA<FileOpException>()));
  });

  test('web project template', () async {
    final index = await createWebProject(tmp.path, 'site');
    expect(File(index).readAsStringSync(), contains('<!DOCTYPE html>'));
    expect(File('${tmp.path}/site/style.css').existsSync(), isTrue);
    expect(File('${tmp.path}/site/script.js').existsSync(), isTrue);
  });

  test('templates by extension', () {
    expect(templateFor('x.html'), contains('<html'));
    expect(templateFor('Main.java'), contains('class Main'));
    expect(templateFor('data.json'), contains('{'));
    expect(templateFor('plain'), '');
  });

  test('epub runs slicing', () {
    const runs = [Run('Hello '), Run('bold world', bold: true)];
    expect(runsText(runs), 'Hello bold world');
    final a = sliceRuns(runs, 0, 8);
    expect(runsText(a), 'Hello bo');
    final b = sliceRuns(runs, 8);
    expect(runsText(b), 'ld world');
    expect(b.first.bold, isTrue);
    expect(runsText(trimLeftRuns(const [Run('  x')])), 'x');
  });
}
