import 'dart:convert';

import 'package:flutter/material.dart';

// =====================================================================
// Pure helpers for the code editor (comments, indent, colors, lint,
// suggestions). No widgets, so they are easy to unit test.
// =====================================================================

String indentUnitFor(String ext) => ext == 'py' ? '    ' : '  ';

/// Languages where a line ending with ':' starts an indented block.
bool colonOpensBlock(String ext) => ext == 'py' || ext == 'yaml' || ext == 'yml';

// ---------------------------------------------------------------- comments

class CommentStyle {
  const CommentStyle.line(this.line)
      : open = null,
        close = null;
  const CommentStyle.block(this.open, this.close) : line = null;
  final String? line;
  final String? open;
  final String? close;
}

const _slashSlash = {
  'dart', 'java', 'kt', 'kts', 'js', 'mjs', 'cjs', 'jsx', 'ts', 'tsx', 'c', 'h', 'cpp',
  'cc', 'hpp', 'cs', 'go', 'rs', 'swift', 'scala', 'php', 'gradle', 'groovy', 'proto',
};
const _hash = {
  'py', 'sh', 'bash', 'zsh', 'yaml', 'yml', 'toml', 'rb', 'r', 'dockerfile', 'ps1',
  'properties', 'conf', 'cfg', 'ini', 'pl',
};

CommentStyle? commentStyleFor(String ext) {
  final e = ext.toLowerCase();
  if (_slashSlash.contains(e)) return const CommentStyle.line('//');
  if (_hash.contains(e)) return const CommentStyle.line('#');
  if (e == 'sql' || e == 'lua') return const CommentStyle.line('--');
  if (const {'html', 'htm', 'xml', 'svg', 'vue', 'md', 'markdown'}.contains(e)) return const CommentStyle.block('<!--', '-->');
  if (const {'css', 'scss', 'less'}.contains(e)) return const CommentStyle.block('/*', '*/');
  return null;
}

class EditResult {
  const EditResult(this.text, this.selection);
  final String text;
  final TextSelection selection;
}

({int start, int end}) _lineRange(String text, TextSelection sel) {
  var a = sel.start < 0 ? 0 : sel.start;
  var b = sel.end < 0 ? 0 : sel.end;
  if (a > text.length) a = text.length;
  if (b > text.length) b = text.length;
  final ls = a == 0 ? 0 : text.lastIndexOf('\n', a - 1) + 1;
  final effEnd = (b > a && text[b - 1] == '\n') ? b - 1 : b;
  final le0 = text.indexOf('\n', effEnd);
  return (start: ls, end: le0 == -1 ? text.length : le0);
}

String _leading(String s) => RegExp(r'^[ \t]*').stringMatch(s) ?? '';

EditResult _replaceBlock(String text, TextSelection sel, int ls, int le, String newBlock) {
  final newText = text.replaceRange(ls, le, newBlock);
  final selection = sel.isCollapsed
      ? TextSelection.collapsed(offset: ls + newBlock.length)
      : TextSelection(baseOffset: ls, extentOffset: ls + newBlock.length);
  return EditResult(newText, selection);
}

/// Comments / uncomments the selected lines (or the caret line). Null if the language has no comments.
EditResult? toggleComment(String text, TextSelection sel, String ext) {
  final style = commentStyleFor(ext);
  if (style == null) return null;
  final r = _lineRange(text, sel);
  final lines = text.substring(r.start, r.end).split('\n');
  final nonEmpty = lines.where((l) => l.trim().isNotEmpty).toList();

  if (nonEmpty.isEmpty) {
    final marker = style.line != null ? '${style.line} ' : '${style.open}  ${style.close}';
    final res = _replaceBlock(text, sel, r.start, r.end, marker);
    return EditResult(res.text, TextSelection.collapsed(offset: r.start + (style.line != null ? marker.length : style.open!.length + 1)));
  }

  final all = style.line != null
      ? nonEmpty.every((l) => l.trimLeft().startsWith(style.line!))
      : nonEmpty.every((l) {
          final t = l.trim();
          return t.startsWith(style.open!) && t.endsWith(style.close!);
        });

  final out = <String>[];
  if (all) {
    for (final l in lines) {
      if (l.trim().isEmpty) {
        out.add(l);
      } else if (style.line != null) {
        final i = l.indexOf(style.line!);
        var rest = l.substring(i + style.line!.length);
        if (rest.startsWith(' ')) rest = rest.substring(1);
        out.add(l.substring(0, i) + rest);
      } else {
        final ind = _leading(l);
        var body = l.trim();
        body = body.substring(style.open!.length, body.length - style.close!.length);
        if (body.startsWith(' ')) body = body.substring(1);
        if (body.endsWith(' ')) body = body.substring(0, body.length - 1);
        out.add('$ind$body');
      }
    }
  } else {
    var minIndent = 1 << 30;
    for (final l in nonEmpty) {
      final n = _leading(l).length;
      if (n < minIndent) minIndent = n;
    }
    for (final l in lines) {
      if (l.trim().isEmpty) {
        out.add(l);
      } else if (style.line != null) {
        out.add('${l.substring(0, minIndent)}${style.line} ${l.substring(minIndent)}');
      } else {
        final ind = _leading(l);
        out.add('$ind${style.open} ${l.substring(ind.length)} ${style.close}');
      }
    }
  }
  return _replaceBlock(text, sel, r.start, r.end, out.join('\n'));
}

/// Indents / outdents the selected lines (or the caret line).
EditResult shiftLines(String text, TextSelection sel, String unit, {required bool indent}) {
  final r = _lineRange(text, sel);
  final lines = text.substring(r.start, r.end).split('\n');
  final out = <String>[];
  for (final l in lines) {
    if (indent) {
      out.add(l.isEmpty ? l : '$unit$l');
    } else if (l.startsWith(unit)) {
      out.add(l.substring(unit.length));
    } else if (l.startsWith('\t')) {
      out.add(l.substring(1));
    } else {
      out.add(l.replaceFirst(RegExp(r'^ {1,8}'), ''));
    }
  }
  return _replaceBlock(text, sel, r.start, r.end, out.join('\n'));
}

// ---------------------------------------------------------------- colors

class ColorHit {
  const ColorHit(this.line, this.color, this.code);
  final int line; // 0-based
  final Color color;
  final String code;
}

final _hexRe = RegExp(r'#([0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b');
final _rgbRe = RegExp(r'rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})(?:\s*[,/]\s*([\d.]+%?))?\s*\)');
final _flutterRe = RegExp(r'Color\(\s*0x([0-9a-fA-F]{8})\s*\)');

List<ColorHit> findColors(String text, {int maxHits = 300, int startLine = 0}) {
  final hits = <_Raw>[];
  for (final m in _hexRe.allMatches(text)) {
    final h = m.group(1)!;
    int? v;
    if (h.length == 3) {
      v = int.tryParse('FF${h[0]}${h[0]}${h[1]}${h[1]}${h[2]}${h[2]}', radix: 16);
    } else if (h.length == 6) {
      v = int.tryParse('FF$h', radix: 16);
    } else {
      final rgb = h.substring(0, 6);
      final a = h.substring(6);
      v = int.tryParse('$a$rgb', radix: 16); // CSS #RRGGBBAA
    }
    if (v != null) hits.add(_Raw(m.start, Color(v), m.group(0)!));
    if (hits.length >= maxHits) break;
  }
  for (final m in _rgbRe.allMatches(text)) {
    final r = int.parse(m.group(1)!), g = int.parse(m.group(2)!), b = int.parse(m.group(3)!);
    if (r > 255 || g > 255 || b > 255) continue;
    var alpha = 1.0;
    final a = m.group(4);
    if (a != null) {
      alpha = a.endsWith('%') ? (double.tryParse(a.substring(0, a.length - 1)) ?? 100) / 100 : (double.tryParse(a) ?? 1);
    }
    hits.add(_Raw(m.start, Color.fromRGBO(r, g, b, alpha.clamp(0.0, 1.0)), m.group(0)!));
    if (hits.length >= maxHits) break;
  }
  for (final m in _flutterRe.allMatches(text)) {
    final v = int.tryParse(m.group(1)!, radix: 16);
    if (v != null) hits.add(_Raw(m.start, Color(v), m.group(0)!));
    if (hits.length >= maxHits) break;
  }
  hits.sort((a, b) => a.offset.compareTo(b.offset));

  // offset -> line number
  final out = <ColorHit>[];
  var line = startLine;
  var pos = 0;
  for (final h in hits) {
    for (var i = pos; i < h.offset && i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) line++;
    }
    pos = h.offset;
    out.add(ColorHit(line, h.color, h.code));
  }
  return out;
}

class _Raw {
  const _Raw(this.offset, this.color, this.code);
  final int offset;
  final Color color;
  final String code;
}

// ---------------------------------------------------------------- suggestions

class Suggestion {
  const Suggestion(this.label, this.insert, {this.snippet = false});
  final String label;

  /// Text that replaces what the user typed. `$0` marks where the caret goes.
  final String insert;
  final bool snippet;
}

const _snippets = <String, Map<String, String>>{
  'py': {
    'def': 'def name(args):\n    \$0',
    'for': 'for item in items:\n    \$0',
    'if': 'if condition:\n    \$0',
    'elif': 'elif condition:\n    \$0',
    'else': 'else:\n    \$0',
    'class': 'class Name:\n    def __init__(self):\n        \$0',
    'try': 'try:\n    \$0\nexcept Exception as e:\n    print(e)',
    'main': 'if __name__ == "__main__":\n    \$0',
    'while': 'while condition:\n    \$0',
  },
  'js': {
    'fn': 'function name() {\n  \$0\n}',
    'log': 'console.log(\$0);',
    'for': 'for (let i = 0; i < n; i++) {\n  \$0\n}',
    'if': 'if (condition) {\n  \$0\n}',
    'arrow': 'const name = () => {\n  \$0\n};',
    'fetch': 'fetch(url)\n  .then((r) => r.json())\n  .then((data) => {\n    \$0\n  });',
  },
  'dart': {
    'main': 'void main() {\n  \$0\n}',
    'for': 'for (var i = 0; i < n; i++) {\n  \$0\n}',
    'if': 'if (condition) {\n  \$0\n}',
    'print': "print('\$0');",
    'stless': 'class Name extends StatelessWidget {\n  const Name({super.key});\n\n  @override\n  Widget build(BuildContext context) {\n    return \$0;\n  }\n}',
  },
  'java': {
    'main': 'public static void main(String[] args) {\n    \$0\n}',
    'sout': 'System.out.println(\$0);',
    'for': 'for (int i = 0; i < n; i++) {\n    \$0\n}',
    'if': 'if (condition) {\n    \$0\n}',
  },
  'html': {
    'html5': '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <meta charset="utf-8">\n  <meta name="viewport" content="width=device-width, initial-scale=1">\n  <title>Title</title>\n</head>\n<body>\n  \$0\n</body>\n</html>',
    'div': '<div>\n  \$0\n</div>',
    'ul': '<ul>\n  <li>\$0</li>\n</ul>',
    'link': '<link rel="stylesheet" href="style.css">',
    'script': '<script src="script.js"></script>',
    'button': '<button type="button">\$0</button>',
  },
  'css': {
    'flex': 'display: flex;\n  align-items: center;\n  justify-content: center;',
    'grid': 'display: grid;\n  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));\n  gap: 12px;',
    'media': '@media (max-width: 600px) {\n  \$0\n}',
  },
};

const _keywords = <String, List<String>>{
  'py': ['import', 'from', 'return', 'class', 'def', 'lambda', 'while', 'continue', 'break', 'pass', 'raise', 'except', 'finally', 'yield', 'global', 'True', 'False', 'None', 'print', 'range', 'len', 'self'],
  'js': ['function', 'const', 'let', 'return', 'await', 'async', 'import', 'export', 'default', 'document', 'window', 'console', 'addEventListener', 'querySelector', 'getElementById', 'undefined', 'null', 'true', 'false'],
  'dart': ['import', 'class', 'extends', 'implements', 'final', 'const', 'return', 'await', 'async', 'Future', 'Widget', 'BuildContext', 'StatelessWidget', 'StatefulWidget', 'setState', 'String', 'bool', 'double', 'List', 'Map', 'void'],
  'java': ['public', 'private', 'protected', 'static', 'final', 'class', 'interface', 'extends', 'implements', 'return', 'import', 'package', 'String', 'void', 'boolean', 'System', 'throws', 'new', 'null'],
  'css': ['display', 'background', 'color', 'margin', 'padding', 'border', 'font-size', 'font-weight', 'width', 'height', 'position', 'absolute', 'relative', 'flex', 'grid', 'center', 'transition', 'transform', 'opacity', 'overflow'],
  'html': ['div', 'span', 'section', 'header', 'footer', 'button', 'input', 'form', 'label', 'class', 'href', 'src', 'style', 'script', 'table', 'img', 'nav'],
};

String _langGroup(String ext) {
  switch (ext) {
    case 'py':
      return 'py';
    case 'js':
    case 'jsx':
    case 'ts':
    case 'tsx':
    case 'mjs':
      return 'js';
    case 'dart':
      return 'dart';
    case 'java':
    case 'kt':
    case 'cs':
      return 'java';
    case 'css':
    case 'scss':
    case 'less':
      return 'css';
    case 'html':
    case 'htm':
    case 'xml':
    case 'svg':
      return 'html';
    default:
      return '';
  }
}

final _wordRe = RegExp(r'[A-Za-z_][A-Za-z0-9_]{2,}');

Set<String> extractWords(String text) {
  if (text.length > 250000) return <String>{};
  return {for (final m in _wordRe.allMatches(text)) m.group(0)!};
}

/// The word being typed right before the caret ('' if none).
String prefixAt(String text, int caret) {
  if (caret <= 0 || caret > text.length) return '';
  var i = caret;
  while (i > 0) {
    final c = text.codeUnitAt(i - 1);
    final ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
    if (!ok) break;
    i--;
  }
  return text.substring(i, caret);
}

List<Suggestion> suggest(String prefix, Set<String> words, String ext) {
  if (prefix.isEmpty) return const [];
  final group = _langGroup(ext);
  final lp = prefix.toLowerCase();
  final out = <Suggestion>[];
  final seen = <String>{};

  final snippets = _snippets[group];
  if (snippets != null) {
    for (final e in snippets.entries) {
      if (e.key.startsWith(lp)) {
        out.add(Suggestion(e.key, e.value, snippet: true));
        seen.add(e.key);
      }
    }
  }
  if (prefix.length >= 2) {
    final fromWords = words.where((w) => w != prefix && w.toLowerCase().startsWith(lp)).toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    for (final w in fromWords) {
      if (seen.add(w)) out.add(Suggestion(w, w));
      if (out.length >= 8) break;
    }
    for (final k in _keywords[group] ?? const <String>[]) {
      if (k != prefix && k.toLowerCase().startsWith(lp) && seen.add(k)) out.add(Suggestion(k, k));
      if (out.length >= 8) break;
    }
  }
  return out.take(8).toList();
}

/// Applies a suggestion: replaces the typed prefix and keeps the line's indentation inside multi-line snippets.
EditResult applySuggestion(String text, int caret, String prefix, Suggestion s) {
  final start = caret - prefix.length;
  final lineStart = start == 0 ? 0 : text.lastIndexOf('\n', start - 1) + 1;
  final indent = _leading(text.substring(lineStart, start));
  var body = s.insert;
  if (s.snippet) body = body.split('\n').asMap().entries.map((e) => e.key == 0 ? e.value : '$indent${e.value}').join('\n');
  final marker = body.indexOf('\$0');
  final clean = body.replaceFirst('\$0', '');
  final newText = text.replaceRange(start, caret, clean);
  final caretAt = start + (marker == -1 ? clean.length : marker);
  return EditResult(newText, TextSelection.collapsed(offset: caretAt));
}

// ---------------------------------------------------------------- lint

class Problem {
  const Problem(this.line, this.col, this.message, {this.error = true});
  final int line; // 1-based
  final int col; // 1-based
  final String message;
  final bool error;
}

List<Problem> lintText(String text, String ext) {
  if (text.isEmpty || text.length > 400000) return const [];
  final e = ext.toLowerCase();
  List<Problem> out;
  if (e == 'json') {
    out = _lintJson(text);
  } else if (const {'html', 'htm', 'xml', 'svg', 'vue'}.contains(e)) {
    out = _lintMarkup(text, xml: e != 'html' && e != 'htm' && e != 'vue');
  } else if (const {'md', 'markdown', 'txt', 'csv', 'log', 'yaml', 'yml', 'toml', 'ini', 'properties', 'conf', 'cfg'}.contains(e)) {
    out = const [];
  } else {
    out = _lintBrackets(text, e);
    if (e == 'py') out = [...out, ..._lintPython(text)];
  }
  out = [...out]..sort((a, b) => a.line != b.line ? a.line.compareTo(b.line) : a.col.compareTo(b.col));
  return out.take(60).toList();
}

(int, int) _lineCol(String text, int offset) {
  var line = 1;
  var last = -1;
  final end = offset.clamp(0, text.length);
  for (var i = 0; i < end; i++) {
    if (text.codeUnitAt(i) == 10) {
      line++;
      last = i;
    }
  }
  return (line, end - last);
}

List<Problem> _lintJson(String text) {
  try {
    jsonDecode(text);
    return const [];
  } on FormatException catch (e) {
    final (l, c) = _lineCol(text, e.offset ?? 0);
    return [Problem(l, c, 'Invalid JSON: ${e.message}')];
  }
}

const _voidTags = {'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr'};
final _tagRe = RegExp(r'<!--.*?-->|<!\[CDATA\[.*?\]\]>|<[!?][^>]*>|<(/?)([a-zA-Z][a-zA-Z0-9:_-]*)((?:"[^"]*"|\x27[^\x27]*\x27|[^>"\x27])*)>', dotAll: true);

List<Problem> _lintMarkup(String text, {required bool xml}) {
  final problems = <Problem>[];
  final stack = <(String, int)>[];
  var skipUntil = -1;
  for (final m in _tagRe.allMatches(text)) {
    if (m.start < skipUntil) continue;
    final name = m.group(2);
    if (name == null) continue;
    final closing = m.group(1) == '/';
    final tag = xml ? name : name.toLowerCase();
    final selfClose = (m.group(3) ?? '').trimRight().endsWith('/');
    if (!closing) {
      if (!xml && (tag == 'script' || tag == 'style')) {
        final endIdx = text.toLowerCase().indexOf('</$tag', m.end);
        if (endIdx != -1) skipUntil = endIdx;
      }
      if (selfClose || (!xml && _voidTags.contains(tag))) continue;
      stack.add((tag, m.start));
    } else {
      if (!xml && _voidTags.contains(tag)) continue;
      final idx = stack.lastIndexWhere((s) => s.$1 == tag);
      if (idx == -1) {
        final (l, c) = _lineCol(text, m.start);
        problems.add(Problem(l, c, 'Unexpected closing tag </$name>'));
      } else {
        for (var i = stack.length - 1; i > idx; i--) {
          final (l, c) = _lineCol(text, stack[i].$2);
          problems.add(Problem(l, c, '<${stack[i].$1}> is not closed'));
        }
        stack.removeRange(idx, stack.length);
      }
    }
  }
  for (final s in stack) {
    final (l, c) = _lineCol(text, s.$2);
    problems.add(Problem(l, c, '<${s.$1}> is never closed'));
  }
  return problems;
}

List<Problem> _lintBrackets(String text, String ext) {
  const pairs = {')': '(', ']': '[', '}': '{'};
  const openers = '([{';
  final lineComment = _commentMarker(ext);
  final checkStrings = const {'py', 'js', 'jsx', 'ts', 'tsx', 'java', 'kt', 'dart', 'cs', 'mjs'}.contains(ext);
  final problems = <Problem>[];
  final stack = <(String, int)>[];
  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text[i];
    // comments
    if (lineComment != null && text.startsWith(lineComment, i)) {
      while (i < n && text[i] != '\n') {
        i++;
      }
      continue;
    }
    if (lineComment != '#' && lineComment != '--' && text.startsWith('/*', i)) {
      final end = text.indexOf('*/', i + 2);
      i = end == -1 ? n : end + 2;
      continue;
    }
    // strings
    if (c == '"' || c == "'" || (c == '`' && (ext == 'js' || ext == 'jsx' || ext == 'ts' || ext == 'tsx'))) {
      final triple = (ext == 'py' || ext == 'dart' || ext == 'kt') && text.startsWith(c * 3, i);
      if (triple) {
        final end = text.indexOf(c * 3, i + 3);
        i = end == -1 ? n : end + 3;
        continue;
      }
      final start = i;
      i++;
      var closed = false;
      while (i < n) {
        final d = text[i];
        if (d == '\\') {
          i += 2;
          continue;
        }
        if (d == c) {
          closed = true;
          i++;
          break;
        }
        if (d == '\n' && c != '`') break;
        i++;
      }
      if (!closed && checkStrings) {
        final (l, col) = _lineCol(text, start);
        problems.add(Problem(l, col, 'String is not closed'));
      }
      continue;
    }
    if (openers.contains(c)) {
      stack.add((c, i));
    } else if (pairs.containsKey(c)) {
      if (stack.isEmpty) {
        final (l, col) = _lineCol(text, i);
        problems.add(Problem(l, col, "Unexpected '$c' (nothing was opened)"));
      } else if (stack.last.$1 == pairs[c]) {
        stack.removeLast();
      } else {
        final (l, col) = _lineCol(text, i);
        final top = stack.last.$1;
        final want = top == '(' ? ')' : (top == '[' ? ']' : '}');
        problems.add(Problem(l, col, "Expected '$want' but found '$c'"));
        stack.removeLast();
      }
    }
    i++;
  }
  for (final s in stack) {
    final (l, col) = _lineCol(text, s.$2);
    problems.add(Problem(l, col, "'${s.$1}' is never closed"));
  }
  return problems;
}

String? _commentMarker(String ext) {
  final s = commentStyleFor(ext);
  return s?.line;
}

List<Problem> _lintPython(String text) {
  final problems = <Problem>[];
  final lines = text.split('\n');
  final stack = <int>[0];
  var prevColon = false;
  var depth = 0; // open brackets
  var inTriple = false;
  var sawTab = false;
  var sawSpace = false;
  var reportedMix = false;
  for (var n = 0; n < lines.length; n++) {
    final raw = lines[n];
    final tripleCount = RegExp(r'"""|' "'''").allMatches(raw).length;
    final wasInTriple = inTriple;
    if (tripleCount.isOdd) inTriple = !inTriple;
    if (wasInTriple) continue;

    final stripped = raw.trim();
    if (stripped.isEmpty || stripped.startsWith('#')) continue;
    final ind = _leading(raw);
    if (depth == 0) {
      if (ind.contains('\t')) sawTab = true;
      if (ind.contains(' ')) sawSpace = true;
      if (sawTab && sawSpace && !reportedMix) {
        problems.add(Problem(n + 1, 1, 'Mixed tabs and spaces. Use 4 spaces for every indent.', error: false));
        reportedMix = true;
      }
      final width = ind.replaceAll('\t', '    ').length;
      if (width % 4 != 0 && !ind.contains('\t')) {
        problems.add(Problem(n + 1, 1, 'Indent should be a multiple of 4 spaces (this line has $width).', error: false));
      }
      if (prevColon) {
        if (width <= stack.last) {
          problems.add(Problem(n + 1, 1, "Expected an indented block (the line above ends with ':'). Add 4 spaces."));
        } else {
          stack.add(width);
        }
      } else if (width > stack.last) {
        problems.add(Problem(n + 1, 1, 'Unexpected indent. This line is indented more than the code above it.'));
        stack.add(width);
      } else if (width < stack.last) {
        while (stack.length > 1 && stack.last > width) {
          stack.removeLast();
        }
        if (stack.last != width) {
          problems.add(Problem(n + 1, 1, 'Unindent does not match any outer indentation level.'));
        }
      }
    }
    // update bracket depth and colon state using the code part of the line
    var code = stripped.replaceAll(RegExp(r'"([^"\\]|\\.)*"|' "'([^'\\\\]|\\\\.)*'"), '""');
    final hashIdx = code.indexOf('#');
    if (hashIdx != -1) code = code.substring(0, hashIdx);
    code = code.trimRight();
    for (final ch in code.split('')) {
      if (ch == '(' || ch == '[' || ch == '{') depth++;
      if (ch == ')' || ch == ']' || ch == '}') depth = depth > 0 ? depth - 1 : 0;
    }
    prevColon = depth == 0 && code.endsWith(':');
  }
  return problems;
}
