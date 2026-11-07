import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/animations.dart';
import '../../shared/widgets/bottom_safe.dart';
import '../editor/editor_screen.dart';
import '../files/domain/file_item.dart';
import '../preview/preview_screen.dart';
import '../files/domain/file_kind.dart';

class _TextData {
  const _TextData(this.text, this.truncated, this.binary, this.totalBytes);
  final String text;
  final bool truncated;
  final bool binary;
  final int totalBytes;
}

/// Viewer for text and code files (syntax highlighting for known languages).
class TextViewerScreen extends StatefulWidget {
  const TextViewerScreen({super.key, required this.item, this.forceText = false});

  final FileItem item;
  final bool forceText;

  @override
  State<TextViewerScreen> createState() => _TextViewerScreenState();
}

class _TextViewerScreenState extends State<TextViewerScreen> {
  late final Future<_TextData> _future = _load();
  double _fontSize = 13;
  bool _wrap = true;

  Future<_TextData> _load() async {
    final file = File(widget.item.path);
    final length = await file.length();
    final toRead = math.min(length, AppConstants.maxTextBytes);
    final raf = await file.open();
    try {
      final bytes = await raf.read(toRead);
      final sample = bytes.length > 8000 ? bytes.sublist(0, 8000) : bytes;
      final binary = !widget.forceText && sample.contains(0);
      if (binary) return _TextData('', false, true, length);
      return _TextData(
        utf8.decode(bytes, allowMalformed: true),
        length > toRead,
        false,
        length,
      );
    } finally {
      await raf.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isCode = item.kind == FileKind.code;
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => Navigator.of(context).pushReplacement(
              fadeSlideRoute(EditorScreen(path: item.path)),
            ),
          ),
          if (const {'html', 'htm', 'svg', 'md', 'markdown'}.contains(item.ext))
            IconButton(
              tooltip: 'Preview',
              icon: const Icon(Icons.play_circle_outline_rounded),
              onPressed: () => Navigator.of(context).push(
                fadeSlideRoute(PreviewScreen(path: item.path)),
              ),
            ),
          IconButton(
            tooltip: 'Smaller text',
            icon: const Icon(Icons.text_decrease_rounded),
            onPressed: () => setState(() => _fontSize = math.max(9, _fontSize - 1)),
          ),
          IconButton(
            tooltip: 'Bigger text',
            icon: const Icon(Icons.text_increase_rounded),
            onPressed: () => setState(() => _fontSize = math.min(30, _fontSize + 1)),
          ),
          if (!isCode)
            IconButton(
              tooltip: 'Word wrap',
              icon: Icon(_wrap ? Icons.wrap_text_rounded : Icons.notes_rounded),
              onPressed: () => setState(() => _wrap = !_wrap),
            ),
        ],
      ),
      body: FutureBuilder<_TextData>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not read this file.\n${snap.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final data = snap.data!;
          if (data.binary) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This looks like a binary file, so it cannot be shown as text.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              if (data.truncated)
                MaterialBanner(
                  content: Text(
                    'Large file: showing the first ${formatSize(AppConstants.maxTextBytes)} of ${formatSize(data.totalBytes)}.',
                  ),
                  actions: const [SizedBox.shrink()],
                ),
              Expanded(child: _body(context, data, isCode)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, _TextData data, bool isCode) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: _fontSize,
      height: 1.45,
    );
    final lang = highlightLanguageFor(widget.item.ext);
    final lines = '\n'.allMatches(data.text).length + 1;
    final canHighlight = isCode &&
        lang != null &&
        data.text.length <= AppConstants.maxHighlightBytes &&
        lines <= AppConstants.maxHighlightLines;

    if (canHighlight) {
      final theme = dark ? atomOneDarkTheme : githubTheme;
      final bg = theme['root']?.backgroundColor;
      return Container(
        color: bg,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: HighlightView(
              data.text,
              language: lang,
              theme: theme,
              padding: const EdgeInsets.all(16),
              textStyle: mono,
            ),
          ),
        ),
      );
    }

    final text = SelectableText(data.text, style: mono);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset(context)),
      child: (_wrap && !isCode)
          ? text
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: text),
    );
  }
}
