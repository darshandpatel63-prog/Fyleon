import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:path/path.dart' as p;

import '../../shared/widgets/animations.dart';
import '../files/data/file_ops.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import '../preview/preview_screen.dart';
import 'highlighting_controller.dart';

/// Code / text editor: syntax colors, line numbers, undo/redo, save,
/// symbol bar, auto indent, and preview for web files.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.path});

  final String path;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const _maxEditBytes = 1536 * 1024;

  late final String _ext = extensionOf(p.basename(widget.path));
  HighlightingController? _controller;
  final _undo = UndoHistoryController();
  final _focus = FocusNode();
  String _saved = '';
  bool _loading = true;
  String? _error;
  bool _dirty = false;
  double _fontSize = 14;
  int _lineCount = 1;
  int _longest = 0;

  bool get _previewable => const {'html', 'htm', 'svg', 'md', 'markdown'}.contains(_ext);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    _undo.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final file = File(widget.path);
      final length = await file.length();
      if (length > _maxEditBytes) {
        setState(() {
          _loading = false;
          _error = 'This file is too large to edit on a phone (limit 1.5 MB).';
        });
        return;
      }
      final bytes = await file.readAsBytes();
      final sample = bytes.length > 8000 ? bytes.sublist(0, 8000) : bytes;
      if (sample.contains(0)) {
        setState(() {
          _loading = false;
          _error = 'This looks like a binary file, so it cannot be edited as text.';
        });
        return;
      }
      final text = utf8.decode(bytes, allowMalformed: true);
      final c = HighlightingController(
        text: text,
        language: highlightLanguageFor(_ext),
        theme: githubTheme,
      );
      c.addListener(_onChanged);
      _saved = text;
      setState(() {
        _controller = c;
        _loading = false;
      });
      _recount();
    } catch (e) {
      setState(() {
        _loading = false;
        _error = friendlyError(e).message;
      });
    }
  }

  void _recount() {
    final t = _controller?.text ?? '';
    var lines = 1;
    var longest = 0;
    var cur = 0;
    for (var i = 0; i < t.length; i++) {
      if (t.codeUnitAt(i) == 10) {
        lines++;
        if (cur > longest) longest = cur;
        cur = 0;
      } else {
        cur++;
      }
    }
    if (cur > longest) longest = cur;
    _lineCount = lines;
    _longest = longest;
  }

  void _onChanged() {
    final c = _controller;
    if (c == null) return;
    _recount();
    setState(() => _dirty = c.text != _saved);
  }

  Future<bool> _save() async {
    final c = _controller;
    if (c == null) return false;
    try {
      await File(widget.path).writeAsString(c.text);
      _saved = c.text;
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e).message)));
      }
      return false;
    }
  }

  void _insert(String s) {
    final c = _controller;
    if (c == null) return;
    final t = c.text;
    final sel = c.selection;
    final start = sel.start < 0 ? t.length : sel.start;
    final end = sel.end < 0 ? t.length : sel.end;
    c.value = c.value.copyWith(
      text: t.replaceRange(start, end, s),
      selection: TextSelection.collapsed(offset: start + s.length),
      composing: TextRange.empty,
    );
    _focus.requestFocus();
  }

  Future<void> _preview() async {
    final c = _controller;
    if (c == null) return;
    if (!mounted) return;
    await Navigator.of(context).push(
      fadeSlideRoute(PreviewScreen(path: widget.path, liveText: c.text)),
    );
  }

  Future<bool> _confirmLeave() async {
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save changes?'),
        content: const Text('You have unsaved changes.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (r == 'save') return _save();
    return r == 'discard';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hlTheme = dark ? atomOneDarkTheme : githubTheme;
    _controller?.theme = hlTheme;
    final bg = hlTheme['root']?.backgroundColor ?? Theme.of(context).colorScheme.surface;
    final fg = hlTheme['root']?.color ?? Theme.of(context).colorScheme.onSurface;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final leave = await _confirmLeave();
        if (leave && mounted) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            '${p.basename(widget.path)}${_dirty ? ' *' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_controller != null) ...[
              ValueListenableBuilder<UndoHistoryValue>(
                valueListenable: _undo,
                builder: (context, v, _) => IconButton(
                  tooltip: 'Undo',
                  icon: const Icon(Icons.undo_rounded),
                  onPressed: v.canUndo ? _undo.undo : null,
                ),
              ),
              ValueListenableBuilder<UndoHistoryValue>(
                valueListenable: _undo,
                builder: (context, v, _) => IconButton(
                  tooltip: 'Redo',
                  icon: const Icon(Icons.redo_rounded),
                  onPressed: v.canRedo ? _undo.redo : null,
                ),
              ),
              if (_previewable)
                IconButton(
                  tooltip: 'Preview',
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  onPressed: _preview,
                ),
              IconButton(
                tooltip: 'Save',
                icon: Icon(Icons.save_rounded, color: _dirty ? Theme.of(context).colorScheme.primary : null),
                onPressed: _dirty ? _save : null,
              ),
              PopupMenuButton<String>(
                onSelected: (v) => setState(() {
                  _fontSize = v == 'plus' ? math.min(26, _fontSize + 1) : math.max(9, _fontSize - 1);
                }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'plus', child: Text('Bigger text')),
                  PopupMenuItem(value: 'minus', child: Text('Smaller text')),
                ],
              ),
            ],
          ],
        ),
        body: _body(bg, fg),
      ),
    );
  }

  Widget _body(Color bg, Color fg) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)),
      );
    }
    final c = _controller!;
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
      fontSize: _fontSize,
      height: 1.45,
      color: fg,
    );
    final charW = _fontSize * 0.62;
    final digits = '$_lineCount'.length;
    final gutterW = digits * charW + 18;
    final gutter = List.generate(_lineCount, (i) => '${i + 1}').join('\n');

    return Column(
      children: [
        Expanded(
          child: Container(
            color: bg,
            child: LayoutBuilder(
              builder: (context, box) {
                final textW = math.max(box.maxWidth - gutterW, _longest * charW + 60);
                return SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: gutterW,
                        padding: const EdgeInsets.fromLTRB(4, 12, 8, 0),
                        child: Text(
                          gutter,
                          textAlign: TextAlign.right,
                          style: mono.copyWith(color: fg.withValues(alpha: 0.4)),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: textW,
                            child: TextField(
                              controller: c,
                              focusNode: _focus,
                              undoController: _undo,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              style: mono,
                              cursorColor: Theme.of(context).colorScheme.primary,
                              autocorrect: false,
                              enableSuggestions: false,
                              smartDashesType: SmartDashesType.disabled,
                              smartQuotesType: SmartQuotesType.disabled,
                              inputFormatters: [AutoIndentFormatter()],
                              scrollPhysics: const NeverScrollableScrollPhysics(),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.fromLTRB(4, 12, 12, 12),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        _symbolBar(),
      ],
    );
  }

  Widget _symbolBar() {
    const symbols = ['{', '}', '(', ')', '[', ']', '<', '>', ';', ':', '"', "'", '=', '/', '\\', '_', '-', '+', '*', '#', '!', '&', '|', r'$'];
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          children: [
            _symbolButton('Tab', '  '),
            for (final s in symbols) _symbolButton(s, s),
          ],
        ),
      ),
    );
  }

  Widget _symbolButton(String label, String insert) {
    return InkWell(
      onTap: () => _insert(insert),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        alignment: Alignment.center,
        constraints: const BoxConstraints(minWidth: 40),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, fontFamily: 'monospace')),
      ),
    );
  }
}
