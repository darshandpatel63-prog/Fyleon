import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyleon/features/editor/code_tools.dart';
import 'package:fyleon/features/files/presentation/file_collection_view.dart';

void main() {
  group('comments', () {
    test('toggle // on and off', () {
      const text = 'a();\nb();\nc();';
      final on = toggleComment(text, const TextSelection(baseOffset: 0, extentOffset: 9), 'dart')!;
      expect(on.text, '// a();\n// b();\nc();');
      final off = toggleComment(on.text, TextSelection(baseOffset: 0, extentOffset: on.selection.end), 'dart')!;
      expect(off.text, text);
    });
    test('python uses # and keeps indentation', () {
      final r = toggleComment('def f():\n    pass', const TextSelection.collapsed(offset: 12), 'py')!;
      expect(r.text, 'def f():\n    # pass');
    });
    test('html uses block comments, json has none', () {
      final r = toggleComment('<p>x</p>', const TextSelection.collapsed(offset: 2), 'html')!;
      expect(r.text, '<!-- <p>x</p> -->');
      expect(toggleComment('{}', const TextSelection.collapsed(offset: 0), 'json'), isNull);
    });
  });

  test('indent and outdent', () {
    final a = shiftLines('x\ny', const TextSelection(baseOffset: 0, extentOffset: 3), '  ', indent: true);
    expect(a.text, '  x\n  y');
    final b = shiftLines(a.text, const TextSelection(baseOffset: 0, extentOffset: 7), '  ', indent: false);
    expect(b.text, 'x\ny');
  });

  test('colors are found with their line', () {
    final hits = findColors('a { color: #ff0000; }\nb { background: rgb(0, 128, 255); }');
    expect(hits.length, 2);
    expect(hits[0].line, 0);
    expect(hits[0].color, const Color(0xFFFF0000));
    expect(hits[1].line, 1);
    expect(hits[1].color, const Color.fromRGBO(0, 128, 255, 1));
  });

  test('suggestions: words, snippets, apply', () {
    final words = extractWords('counter total counterValue');
    final s = suggest('cou', words, 'dart');
    expect(s.map((e) => e.label), containsAll(['counter', 'counterValue']));
    final sn = suggest('def', const {}, 'py');
    expect(sn.first.snippet, isTrue);
    final r = applySuggestion('    def', 7, 'def', sn.first);
    expect(r.text, startsWith('    def name(args):\n        '));
    expect(prefixAt('foo.bar', 7), 'bar');
  });

  group('lint', () {
    test('json', () {
      expect(lintText('{"a": 1}', 'json'), isEmpty);
      expect(lintText('{"a": }', 'json'), isNotEmpty);
    });
    test('brackets', () {
      expect(lintText('void main() { print(1); }', 'dart'), isEmpty);
      final p = lintText('void main() {\n  print(1;\n}', 'dart');
      expect(p.length, 2);
      expect(p.any((e) => e.message.contains("Expected ')'")), isTrue);
      expect(p.any((e) => e.message.contains('never closed')), isTrue);
    });
    test('comments and strings do not confuse the bracket check', () {
      expect(lintText("// (\nvar s = '(';\nvar t = \"{\";\n", 'dart'), isEmpty);
    });
    test('html tags', () {
      expect(lintText('<div><p>hi</p></div>', 'html'), isEmpty);
      final p = lintText('<div>\n<p>hi\n</div>', 'html');
      expect(p.any((e) => e.message.contains('<p>')), isTrue);
    });
    test('python indentation', () {
      expect(lintText('def f():\n    return 1\n', 'py'), isEmpty);
      final missing = lintText('def f():\nreturn 1\n', 'py');
      expect(missing.any((e) => e.message.contains('indented block')), isTrue);
      final unexpected = lintText('x = 1\n    y = 2\n', 'py');
      expect(unexpected.any((e) => e.message.contains('Unexpected indent')), isTrue);
    });
  });

  test('ad slots', () {
    final s = AdSlots(10, every: 4, max: 6);
    expect(s.ads, 2);
    expect(s.total, 12);
    expect([for (var i = 0; i < s.total; i++) s.isAd(i)].where((e) => e).length, 2);
    final items = [for (var i = 0; i < s.total; i++) if (!s.isAd(i)) s.itemIndex(i)];
    expect(items, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(AdSlots(10, every: 4, max: 0).total, 10);
  });
}
