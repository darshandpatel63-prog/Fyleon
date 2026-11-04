import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import 'epub_parser.dart';

enum BlockKind { paragraph, heading, quote, listItem, image, rule }

class Run {
  const Run(this.text, {this.bold = false, this.italic = false, this.underline = false, this.scale = 1.0});
  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final double scale;

  Run withText(String t) => Run(t, bold: bold, italic: italic, underline: underline, scale: scale);
  bool sameStyle(Run o) => bold == o.bold && italic == o.italic && underline == o.underline && scale == o.scale;
}

class Block {
  const Block(this.kind, {this.level = 0, this.runs = const [], this.image});
  final BlockKind kind;
  final int level;
  final List<Run> runs;
  final Uint8List? image;
}

class ReaderStyle {
  const ReaderStyle({required this.fontSize, required this.lineHeight, required this.color});
  final double fontSize;
  final double lineHeight;
  final Color color;
}

// ------------------------------------------------------------------ styles

TextStyle blockStyle(Block b, ReaderStyle s) {
  final base = TextStyle(fontSize: s.fontSize, height: s.lineHeight, color: s.color);
  switch (b.kind) {
    case BlockKind.heading:
      const scales = {1: 1.7, 2: 1.45, 3: 1.25};
      return base.copyWith(
        fontSize: s.fontSize * (scales[b.level] ?? 1.1),
        fontWeight: FontWeight.w800,
        height: 1.3,
      );
    case BlockKind.quote:
      return base.copyWith(fontStyle: FontStyle.italic);
    default:
      return base;
  }
}

TextAlign blockAlign(Block b) => b.kind == BlockKind.heading ? TextAlign.start : TextAlign.justify;

/// Left space used by quotes (border + padding).
double blockInset(Block b) => b.kind == BlockKind.quote ? 16 : 0;

double spaceBefore(Block b, ReaderStyle s) => b.kind == BlockKind.heading ? s.fontSize * 1.1 : 0;

double spaceAfter(Block b, ReaderStyle s) => b.kind == BlockKind.heading ? s.fontSize * 0.6 : s.fontSize * 0.55;

TextSpan spanFor(List<Run> runs, TextStyle base) {
  return TextSpan(
    style: base,
    children: [
      for (final r in runs)
        TextSpan(
          text: r.text,
          style: TextStyle(
            fontWeight: r.bold ? FontWeight.w700 : null,
            fontStyle: r.italic ? FontStyle.italic : null,
            decoration: r.underline ? TextDecoration.underline : null,
            fontSize: r.scale == 1.0 ? null : (base.fontSize ?? 16) * r.scale,
          ),
        ),
    ],
  );
}

// ------------------------------------------------------------------ runs helpers

String runsText(List<Run> runs) => runs.map((r) => r.text).join();

List<Run> sliceRuns(List<Run> runs, int start, [int? end]) {
  final out = <Run>[];
  var pos = 0;
  for (final r in runs) {
    final rs = pos;
    final re = pos + r.text.length;
    pos = re;
    final a = math.max(start, rs);
    final b = end == null ? re : math.min(end, re);
    if (a < b) out.add(r.withText(r.text.substring(a - rs, b - rs)));
  }
  return out;
}

List<Run> trimLeftRuns(List<Run> runs) {
  final out = <Run>[];
  var trimming = true;
  for (final r in runs) {
    if (trimming) {
      final t = r.text.trimLeft();
      if (t.isEmpty) continue;
      trimming = false;
      out.add(r.withText(t));
    } else {
      out.add(r);
    }
  }
  return out;
}

List<Run> _tidy(List<Run> raw) {
  final merged = <Run>[];
  for (final r in raw) {
    if (r.text.isEmpty) continue;
    if (merged.isNotEmpty && merged.last.sameStyle(r)) {
      merged[merged.length - 1] = merged.last.withText(merged.last.text + r.text);
    } else {
      merged.add(r);
    }
  }
  // no double spaces across run borders
  for (var i = 1; i < merged.length; i++) {
    if (merged[i - 1].text.endsWith(' ') && merged[i].text.startsWith(' ')) {
      merged[i] = merged[i].withText(merged[i].text.substring(1));
    }
  }
  var out = trimLeftRuns(merged);
  // trim the end
  while (out.isNotEmpty) {
    final t = out.last.text.trimRight();
    if (t.isEmpty) {
      out = out.sublist(0, out.length - 1);
    } else {
      out[out.length - 1] = out.last.withText(t);
      break;
    }
  }
  return out;
}

// ------------------------------------------------------------------ HTML -> blocks

const _blockTags = {
  'p', 'div', 'section', 'article', 'blockquote', 'li', 'ul', 'ol', 'h1', 'h2', 'h3',
  'h4', 'h5', 'h6', 'pre', 'figure', 'figcaption', 'body', 'header', 'footer', 'aside',
  'nav', 'table', 'tr', 'td', 'th', 'tbody', 'thead', 'dl', 'dt', 'dd', 'main',
};

bool _isBlockLike(dom.Element e) {
  final t = e.localName;
  return _blockTags.contains(t) || t == 'img' || t == 'hr';
}

List<Block> parseBlocks(EpubChapter chapter, Map<String, Uint8List> images) {
  final body = html_parser.parse(chapter.html).body;
  final out = <Block>[];
  if (body != null) _walk(body, out, chapter.path, images, false);
  return out;
}

void _walk(dom.Element e, List<Block> out, String chapterPath, Map<String, Uint8List> images, bool inQuote) {
  final tag = e.localName ?? '';
  if (tag == 'script' || tag == 'style' || tag == 'head') return;
  if (tag == 'img') {
    final b = _imageBlock(e, chapterPath, images);
    if (b != null) out.add(b);
    return;
  }
  if (tag == 'hr') {
    out.add(const Block(BlockKind.rule));
    return;
  }
  final quote = inQuote || tag == 'blockquote';
  final hasBlockChild = e.children.any(_isBlockLike);
  if (hasBlockChild || tag == 'body') {
    var buffer = <dom.Node>[];
    void flush() {
      if (buffer.isEmpty) return;
      final runs = _runs(buffer);
      if (runs.isNotEmpty) out.add(_textBlock(tag, runs, quote));
      buffer = <dom.Node>[];
    }

    for (final n in e.nodes) {
      if (n is dom.Element && _isBlockLike(n)) {
        flush();
        _walk(n, out, chapterPath, images, quote);
      } else {
        buffer.add(n);
      }
    }
    flush();
    return;
  }
  final runs = _runs(e.nodes);
  if (runs.isNotEmpty) out.add(_textBlock(tag, runs, quote));
}

Block _textBlock(String tag, List<Run> runs, bool quote) {
  if (tag.length == 2 && tag.startsWith('h') && '123456'.contains(tag[1])) {
    return Block(BlockKind.heading, level: int.parse(tag[1]), runs: runs);
  }
  if (tag == 'li') {
    return Block(BlockKind.listItem, runs: [const Run('\u2022  '), ...runs]);
  }
  if (quote) return Block(BlockKind.quote, runs: runs);
  return Block(BlockKind.paragraph, runs: runs);
}

List<Run> _runs(Iterable<dom.Node> nodes) {
  final out = <Run>[];
  void visit(dom.Node n, bool b, bool i, bool u, double scale) {
    if (n is dom.Text) {
      final t = n.text.replaceAll(RegExp(r'\s+'), ' ');
      if (t.isNotEmpty) out.add(Run(t, bold: b, italic: i, underline: u, scale: scale));
    } else if (n is dom.Element) {
      final tag = n.localName ?? '';
      if (tag == 'script' || tag == 'style' || tag == 'img' || tag == 'image') return;
      if (tag == 'br') {
        out.add(Run('\n', bold: b, italic: i, underline: u, scale: scale));
        return;
      }
      final nb = b || tag == 'b' || tag == 'strong';
      final ni = i || tag == 'i' || tag == 'em' || tag == 'cite';
      final nu = u || tag == 'u' || tag == 'a';
      final ns = (tag == 'sup' || tag == 'sub') ? 0.75 : scale;
      for (final c in n.nodes) {
        visit(c, nb, ni, nu, ns);
      }
    }
  }

  for (final n in nodes) {
    visit(n, false, false, false, 1.0);
  }
  return _tidy(out);
}

Block? _imageBlock(dom.Element e, String chapterPath, Map<String, Uint8List> images) {
  final src = e.attributes['src'];
  if (src == null) return null;
  var clean = src.split('#').first;
  try {
    clean = Uri.decodeComponent(clean);
  } catch (_) {}
  final dir = p.posix.dirname(chapterPath);
  final full = p.posix.normalize(dir == '.' ? clean : '$dir/$clean');
  final bytes = images[full];
  if (bytes == null) return null;
  return Block(BlockKind.image, image: bytes);
}
