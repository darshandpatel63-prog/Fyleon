import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import 'epub_parser.dart';

const _blockTags = {
  'p', 'div', 'section', 'article', 'blockquote', 'li', 'ul', 'ol', 'h1', 'h2',
  'h3', 'h4', 'h5', 'h6', 'pre', 'figure', 'figcaption', 'body', 'header',
  'footer', 'aside', 'nav', 'table', 'tr', 'td', 'th', 'tbody', 'thead', 'dl',
  'dt', 'dd', 'main',
};

/// Turns one EPUB chapter (HTML) into simple, selectable reading widgets.
class EpubChapterView extends StatelessWidget {
  const EpubChapterView({
    super.key,
    required this.chapter,
    required this.images,
    required this.fontSize,
    required this.lineHeight,
    required this.textColor,
  });

  final EpubChapter chapter;
  final Map<String, Uint8List> images;
  final double fontSize;
  final double lineHeight;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final doc = html_parser.parse(chapter.html);
    final body = doc.body;
    final widgets = <Widget>[];
    if (body != null) {
      _blocks(body, widgets);
    }
    if (widgets.isEmpty) {
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Text('(empty page)', style: TextStyle(color: textColor.withValues(alpha: 0.5))),
      ));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 80),
      children: widgets,
    );
  }

  TextStyle get _base => TextStyle(
        fontSize: fontSize,
        height: lineHeight,
        color: textColor,
      );

  TextStyle _styleFor(String tag) {
    switch (tag) {
      case 'h1':
        return _base.copyWith(fontSize: fontSize * 1.7, fontWeight: FontWeight.w800, height: 1.25);
      case 'h2':
        return _base.copyWith(fontSize: fontSize * 1.45, fontWeight: FontWeight.w800, height: 1.25);
      case 'h3':
        return _base.copyWith(fontSize: fontSize * 1.25, fontWeight: FontWeight.w700, height: 1.3);
      case 'h4':
      case 'h5':
      case 'h6':
        return _base.copyWith(fontSize: fontSize * 1.1, fontWeight: FontWeight.w700);
      case 'pre':
        return _base.copyWith(fontFamily: 'monospace', fontSize: fontSize * 0.9);
      case 'blockquote':
        return _base.copyWith(fontStyle: FontStyle.italic);
      default:
        return _base;
    }
  }

  bool _hasBlockChild(dom.Element e) =>
      e.children.any((c) => _blockTags.contains(c.localName) || c.localName == 'img');

  void _blocks(dom.Element e, List<Widget> out) {
    final tag = e.localName ?? '';
    if (tag == 'script' || tag == 'style' || tag == 'head') return;
    if (tag == 'img') {
      final w = _image(e);
      if (w != null) out.add(w);
      return;
    }
    if (_hasBlockChild(e) || tag == 'body') {
      var buffer = <dom.Node>[];
      void flush() {
        if (buffer.isEmpty) return;
        final span = TextSpan(children: _spans(buffer, _styleFor(tag)));
        final plain = span.toPlainText().trim();
        if (plain.isNotEmpty) out.add(_paragraph(span, tag));
        buffer = <dom.Node>[];
      }

      for (final n in e.nodes) {
        if (n is dom.Element && (_blockTags.contains(n.localName) || n.localName == 'img')) {
          flush();
          _blocks(n, out);
        } else {
          buffer.add(n);
        }
      }
      flush();
      return;
    }
    final prefix = tag == 'li' ? '\u2022  ' : '';
    final span = TextSpan(
      style: _styleFor(tag),
      children: [if (prefix.isNotEmpty) TextSpan(text: prefix), ..._spans(e.nodes, _styleFor(tag))],
    );
    if (span.toPlainText().trim().isEmpty) return;
    out.add(_paragraph(span, tag));
  }

  Widget _paragraph(TextSpan span, String tag) {
    final isHeading = tag.length == 2 && tag.startsWith('h');
    final text = SelectableText.rich(
      TextSpan(style: _styleFor(tag), children: [span]),
      textAlign: isHeading ? TextAlign.start : TextAlign.justify,
    );
    Widget w = Padding(
      padding: EdgeInsets.only(top: isHeading ? fontSize * 1.2 : 0, bottom: fontSize * (isHeading ? 0.6 : 0.7)),
      child: text,
    );
    if (tag == 'blockquote') {
      w = Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: textColor.withValues(alpha: 0.35), width: 3)),
        ),
        child: w,
      );
    }
    return w;
  }

  List<InlineSpan> _spans(Iterable<dom.Node> nodes, TextStyle style) {
    final out = <InlineSpan>[];
    for (final n in nodes) {
      if (n is dom.Text) {
        final t = n.text.replaceAll(RegExp(r'\s+'), ' ');
        if (t.isNotEmpty) out.add(TextSpan(text: t));
      } else if (n is dom.Element) {
        final tag = n.localName ?? '';
        switch (tag) {
          case 'script':
          case 'style':
          case 'img':
          case 'image':
            break;
          case 'br':
            out.add(const TextSpan(text: '\n'));
            break;
          case 'b':
          case 'strong':
            out.add(TextSpan(style: const TextStyle(fontWeight: FontWeight.w700), children: _spans(n.nodes, style)));
            break;
          case 'i':
          case 'em':
          case 'cite':
            out.add(TextSpan(style: const TextStyle(fontStyle: FontStyle.italic), children: _spans(n.nodes, style)));
            break;
          case 'u':
            out.add(TextSpan(style: const TextStyle(decoration: TextDecoration.underline), children: _spans(n.nodes, style)));
            break;
          case 'a':
            out.add(TextSpan(
              style: const TextStyle(decoration: TextDecoration.underline),
              children: _spans(n.nodes, style),
            ));
            break;
          case 'sup':
          case 'sub':
            out.add(TextSpan(style: TextStyle(fontSize: fontSize * 0.75), children: _spans(n.nodes, style)));
            break;
          default:
            out.addAll(_spans(n.nodes, style));
        }
      }
    }
    return out;
  }

  Widget? _image(dom.Element e) {
    final src = e.attributes['src'];
    if (src == null) return null;
    var clean = src.split('#').first;
    try {
      clean = Uri.decodeComponent(clean);
    } catch (_) {}
    final dir = p.posix.dirname(chapter.path);
    final full = p.posix.normalize(dir == '.' ? clean : '$dir/$clean');
    final bytes = images[full];
    if (bytes == null) return null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 520),
          child: Image.memory(bytes, fit: BoxFit.contain, errorBuilder: (c, e, s) => const SizedBox.shrink()),
        ),
      ),
    );
  }
}
