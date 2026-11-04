import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight, Node;

/// TextEditingController that colors the text while you type (syntax highlight).
/// The produced spans always contain exactly the same characters as `text`.
class HighlightingController extends TextEditingController {
  HighlightingController({
    super.text,
    required this.language,
    required this.theme,
  });

  String? language;
  Map<String, TextStyle> theme;

  static const maxHighlightChars = 150000;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final lang = language;
    final t = text;
    if (lang == null || t.isEmpty || t.length > maxHighlightChars) {
      return TextSpan(style: style, text: t);
    }
    try {
      final result = highlight.parse(t, language: lang);
      final nodes = result.nodes;
      if (nodes == null) return TextSpan(style: style, text: t);
      final children = _convert(nodes);
      final span = TextSpan(style: style, children: children);
      // Safety: if the characters differ, cursor positions would break.
      if (span.toPlainText() != t) return TextSpan(style: style, text: t);
      return span;
    } catch (_) {
      return TextSpan(style: style, text: t);
    }
  }

  List<InlineSpan> _convert(List<Node> nodes) {
    final out = <InlineSpan>[];
    for (final n in nodes) {
      final cls = n.className;
      final st = cls == null ? null : theme[cls];
      final v = n.value;
      if (v != null) {
        out.add(TextSpan(text: v, style: st));
      } else {
        final kids = n.children;
        if (kids != null) {
          out.add(TextSpan(style: st, children: _convert(kids)));
        }
      }
    }
    return out;
  }
}

/// Keeps the indentation of the previous line when you press Enter.
class AutoIndentFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final sel = newValue.selection;
    if (newValue.text.length == oldValue.text.length + 1 &&
        sel.isCollapsed &&
        sel.baseOffset > 0 &&
        newValue.text[sel.baseOffset - 1] == '\n') {
      final caret = sel.baseOffset;
      final before = newValue.text.substring(0, caret - 1);
      final lineStart = before.lastIndexOf('\n') + 1;
      final prev = before.substring(lineStart);
      final indent = RegExp(r'^[ \t]*').stringMatch(prev) ?? '';
      final trimmed = prev.trimRight();
      final extra = (trimmed.endsWith('{') || trimmed.endsWith('(') || trimmed.endsWith('[') || trimmed.endsWith(':')) ? '  ' : '';
      final insert = indent + extra;
      if (insert.isEmpty) return newValue;
      final text = newValue.text.replaceRange(caret, caret, insert);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: caret + insert.length),
      );
    }
    return newValue;
  }
}
