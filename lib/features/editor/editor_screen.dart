import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:path/path.dart' as p;

import '../../shared/widgets/animations.dart';
import '../../shared/widgets/bottom_safe.dart';
import '../files/data/file_ops.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import '../preview/preview_screen.dart';
import 'code_tools.dart';
import 'highlighting_controller.dart';

/// Code / text editor with: syntax colors, line numbers, undo/redo, save, find & replace,
/// comment toggle, indent / outdent, go to line, word + snippet suggestions, color swatches,
/// a Problems panel (live checks), symbol bar, auto indent and web preview.
class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.path});

  final String path;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  static const _maxEditBytes = 1536 * 1024;

  late final String _ext = extensionOf(p.basename(widget.path));
  late final String _unit = indentUnitFor(_ext);
  HighlightingController? _controller;
  final _undo = UndoHistoryController();
  final _focus = FocusNode();
  final _vScroll = ScrollController();
  String _saved = '';
  String _lastText = '';
  bool _loading = true;
  String? _error;
  bool _dirty = false;
  double _fontSize = 14;
  int _lineCount = 1;
  int _longest = 0;

  // tools
  Timer? _lintTimer;
  List<Problem> _problems = const [];
  bool _problemsOpen = false;
  Set<String> _words = <String>{};
  List<ColorHit> _colors = const [];
  List<Suggestion> _suggestions = const [];
  List<ColorHit> _lineColors = const [];
  String _prefix = '';
  bool _findOpen = false;
  final _findC = TextEditingController();
  final _replaceC = TextEditingController();
  List<int> _matches = const [];
  int _matchIdx = -1;
  bool _tipOpen = true;

  double get _lineH => _fontSize * 1.45;
  bool get _previewable => const {'html', 'htm', 'svg', 'md', 'markdown'}.contains(_ext);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _lintTimer?.cancel();
    _controller?.removeListener(_onChanged);
    _controller?.dispose();
    _undo.dispose();
    _focus.dispose();
    _vScroll.dispose();
    _findC.dispose();
    _replaceC.dispose();
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
      final c = HighlightingController(text: text, language: highlightLanguageFor(_ext), theme: githubTheme);
      c.addListener(_onChanged);
      _saved = text;
      _lastText = text;
      setState(() {
        _controller = c;
        _loading = false;
      });
      _recount();
      _runLint();
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
    if (c.text != _lastText) {
      _lastText = c.text;
      _recount();
      _scheduleLint();
    }
    _updateCaretTools();
    setState(() => _dirty = c.text != _saved);
  }

  /// Suggestions and color chips for the line the caret is on.
  void _updateCaretTools() {
    final c = _controller;
    if (c == null) return;
    _suggestions = const [];
    _lineColors = const [];
    _prefix = '';
    final sel = c.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final t = c.text;
    final caret = sel.baseOffset;
    if (caret < 0 || caret > t.length) return;
    final nextIsWord = caret < t.length && RegExp(r'[A-Za-z0-9_]').hasMatch(t[caret]);
    if (!nextIsWord) {
      _prefix = prefixAt(t, caret);
      _suggestions = suggest(_prefix, _words, _ext);
    }
    final ls = caret == 0 ? 0 : t.lastIndexOf('\n', caret - 1) + 1;
    var le = t.indexOf('\n', caret);
    if (le == -1) le = t.length;
    if (le - ls < 400) _lineColors = findColors(t.substring(ls, le));
  }

  void _scheduleLint() {
    _lintTimer?.cancel();
    _lintTimer = Timer(const Duration(milliseconds: 700), _runLint);
  }

  void _runLint() {
    final c = _controller;
    if (c == null || !mounted) return;
    final t = c.text;
    setState(() {
      _problems = lintText(t, _ext);
      _words = extractWords(t);
      _colors = findColors(t);
    });
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<bool> _save() async {
    final c = _controller;
    if (c == null) return false;
    try {
      await File(widget.path).writeAsString(c.text);
      _saved = c.text;
      if (mounted) {
        setState(() => _dirty = false);
        _toast('Saved');
      }
      return true;
    } catch (e) {
      _toast(friendlyError(e).message);
      return false;
    }
  }

  // ------------------------------------------------------------ editing helpers

  void _apply(EditResult r) {
    final c = _controller;
    if (c == null) return;
    c.value = c.value.copyWith(text: r.text, selection: r.selection, composing: TextRange.empty);
    _focus.requestFocus();
  }

  void _insert(String s) {
    final c = _controller;
    if (c == null) return;
    final t = c.text;
    final sel = c.selection;
    final start = sel.start < 0 ? t.length : sel.start;
    final end = sel.end < 0 ? t.length : sel.end;
    _apply(EditResult(t.replaceRange(start, end, s), TextSelection.collapsed(offset: start + s.length)));
  }

  void _toggleComment() {
    final c = _controller;
    if (c == null) return;
    final r = toggleComment(c.text, c.selection, _ext);
    if (r == null) {
      _toast('Comments are not available in .$_ext files');
    } else {
      _apply(r);
    }
  }

  void _shift({required bool indent}) {
    final c = _controller;
    if (c == null) return;
    _apply(shiftLines(c.text, c.selection, _unit, indent: indent));
  }

  void _applySuggestion(Suggestion s) {
    final c = _controller;
    if (c == null) return;
    _apply(applySuggestion(c.text, c.selection.baseOffset, _prefix, s));
  }

  int _offsetOfLine(String t, int line1) {
    var off = 0;
    for (var i = 1; i < line1; i++) {
      final nl = t.indexOf('\n', off);
      if (nl == -1) return t.length;
      off = nl + 1;
    }
    return off;
  }

  void _scrollToLine(int line0) {
    if (!_vScroll.hasClients) return;
    final target = line0 * _lineH - 90;
    _vScroll.animateTo(
      target.clamp(0.0, _vScroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _jumpToLine(int line1, int col1) {
    final c = _controller;
    if (c == null) return;
    final t = c.text;
    final off = math.min(t.length, _offsetOfLine(t, line1) + math.max(0, col1 - 1));
    c.selection = TextSelection.collapsed(offset: off);
    _focus.requestFocus();
    _scrollToLine(line1 - 1);
  }

  Future<void> _goToLine() async {
    final controller = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to line'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - $_lineCount'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Go')),
        ],
      ),
    );
    controller.dispose();
    final n = int.tryParse((r ?? '').trim());
    if (n != null) _jumpToLine(n.clamp(1, _lineCount), 1);
  }

  // ------------------------------------------------------------ find & replace

  void _runFind() {
    final c = _controller;
    if (c == null) return;
    final q = _findC.text;
    final m = <int>[];
    if (q.isNotEmpty) {
      final t = c.text.toLowerCase();
      final ql = q.toLowerCase();
      var i = t.indexOf(ql);
      while (i != -1 && m.length < 5000) {
        m.add(i);
        i = t.indexOf(ql, i + ql.length);
      }
    }
    setState(() {
      _matches = m;
      _matchIdx = m.isEmpty ? -1 : 0;
    });
    if (m.isNotEmpty) _selectMatch(0, focusEditor: false);
  }

  void _selectMatch(int idx, {bool focusEditor = true}) {
    final c = _controller;
    if (c == null || idx < 0 || idx >= _matches.length) return;
    final start = _matches[idx];
    c.selection = TextSelection(baseOffset: start, extentOffset: start + _findC.text.length);
    final line = '\n'.allMatches(c.text.substring(0, start)).length;
    _scrollToLine(line);
    if (focusEditor) _focus.requestFocus();
    setState(() => _matchIdx = idx);
  }

  void _stepMatch(int d) {
    if (_matches.isEmpty) return;
    _selectMatch((_matchIdx + d + _matches.length) % _matches.length);
  }

  void _replaceOne() {
    final c = _controller;
    if (c == null || _matchIdx < 0 || _matchIdx >= _matches.length) return;
    final s = _matches[_matchIdx];
    final r = _replaceC.text;
    c.value = c.value.copyWith(
      text: c.text.replaceRange(s, s + _findC.text.length, r),
      selection: TextSelection.collapsed(offset: s + r.length),
      composing: TextRange.empty,
    );
    _runFind();
  }

  void _replaceAll() {
    final c = _controller;
    if (c == null || _findC.text.isEmpty) return;
    final re = RegExp(RegExp.escape(_findC.text), caseSensitive: false);
    final n = re.allMatches(c.text).length;
    final r = _replaceC.text;
    c.value = c.value.copyWith(
      text: c.text.replaceAllMapped(re, (_) => r),
      selection: const TextSelection.collapsed(offset: 0),
      composing: TextRange.empty,
    );
    _runFind();
    _toast('Replaced $n');
  }

  // ------------------------------------------------------------ navigation

  Future<void> _preview() async {
    final c = _controller;
    if (c == null || !mounted) return;
    await Navigator.of(context).push(fadeSlideRoute(PreviewScreen(path: widget.path, liveText: c.text)));
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

  // ------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hlTheme = dark ? atomOneDarkTheme : githubTheme;
    _controller?.theme = hlTheme;
    final bg = hlTheme['root']?.backgroundColor ?? Theme.of(context).colorScheme.surface;
    final fg = hlTheme['root']?.color ?? Theme.of(context).colorScheme.onSurface;
    final scheme = Theme.of(context).colorScheme;
    final errors = _problems.where((e) => e.error).length;

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
          title: Text('${p.basename(widget.path)}${_dirty ? ' *' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (_controller != null) ...[
              ValueListenableBuilder<UndoHistoryValue>(
                valueListenable: _undo,
                builder: (context, v, _) => IconButton(tooltip: 'Undo', icon: const Icon(Icons.undo_rounded), onPressed: v.canUndo ? _undo.undo : null),
              ),
              ValueListenableBuilder<UndoHistoryValue>(
                valueListenable: _undo,
                builder: (context, v, _) => IconButton(tooltip: 'Redo', icon: const Icon(Icons.redo_rounded), onPressed: v.canRedo ? _undo.redo : null),
              ),
              if (_previewable) IconButton(tooltip: 'Preview', icon: const Icon(Icons.play_circle_outline_rounded), onPressed: _preview),
              IconButton(
                tooltip: 'Problems',
                icon: Badge(
                  isLabelVisible: _problems.isNotEmpty,
                  backgroundColor: errors > 0 ? scheme.error : Colors.orange,
                  label: Text('${_problems.length}'),
                  child: const Icon(Icons.bug_report_outlined),
                ),
                onPressed: () => setState(() => _problemsOpen = !_problemsOpen),
              ),
              IconButton(
                tooltip: 'Save',
                icon: Icon(Icons.save_rounded, color: _dirty ? scheme.primary : null),
                onPressed: _dirty ? _save : null,
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'find':
                      setState(() => _findOpen = true);
                      break;
                    case 'comment':
                      _toggleComment();
                      break;
                    case 'goto':
                      _goToLine();
                      break;
                    case 'indent':
                      _shift(indent: true);
                      break;
                    case 'outdent':
                      _shift(indent: false);
                      break;
                    case 'plus':
                      setState(() => _fontSize = math.min(26, _fontSize + 1));
                      break;
                    case 'minus':
                      setState(() => _fontSize = math.max(9, _fontSize - 1));
                      break;
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'find', child: Text('Find & replace')),
                  PopupMenuItem(value: 'comment', child: Text('Comment / uncomment line')),
                  PopupMenuItem(value: 'goto', child: Text('Go to line')),
                  PopupMenuItem(value: 'indent', child: Text('Indent')),
                  PopupMenuItem(value: 'outdent', child: Text('Outdent')),
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
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)));
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
    final gutterW = digits * charW + 26;
    final gutter = List.generate(_lineCount, (i) => '${i + 1}').join('\n');
    final swatches = _colors.length > 300 ? _colors.sublist(0, 300) : _colors;
    final seenLines = <int>{};

    return Column(
      children: [
        if (_ext == 'py' && _tipOpen) _tip('Python tip: code inside if / for / while / def / class must be indented with 4 spaces. Fyleon adds the spaces for you after ":" and the Problems panel warns about wrong indentation.'),
        if (_findOpen) _findBar(),
        Expanded(
          child: Container(
            color: bg,
            child: LayoutBuilder(
              builder: (context, box) {
                final textW = math.max(box.maxWidth - gutterW, _longest * charW + 60);
                return SingleChildScrollView(
                  controller: _vScroll,
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: gutterW,
                        padding: const EdgeInsets.fromLTRB(4, 12, 8, 0),
                        child: Stack(
                          children: [
                            Text(gutter, textAlign: TextAlign.right, style: mono.copyWith(color: fg.withValues(alpha: 0.4))),
                            for (final h in swatches)
                              if (seenLines.add(h.line))
                                Positioned(
                                  top: h.line * _lineH + (_lineH - 10) / 2,
                                  left: 0,
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: h.color,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: fg.withValues(alpha: 0.4), width: 0.6),
                                    ),
                                  ),
                                ),
                          ],
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
                              inputFormatters: [AutoIndentFormatter(unit: _unit, colon: colonOpensBlock(_ext))],
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
        if (_problemsOpen) _problemsPanel(),
        if (_suggestions.isNotEmpty || _lineColors.isNotEmpty) _suggestionBar(),
        BottomSafe(child: _symbolBar()),
      ],
    );
  }

  Widget _tip(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.tertiaryContainer.withValues(alpha: 0.7),
      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
          IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() => _tipOpen = false)),
        ],
      ),
    );
  }

  Widget _findBar() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _findC,
                    autofocus: true,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Find',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixText: _matches.isEmpty ? (_findC.text.isEmpty ? '' : 'none') : '${_matchIdx + 1}/${_matches.length}',
                    ),
                    onChanged: (_) => _runFind(),
                    onSubmitted: (_) => _stepMatch(1),
                  ),
                ),
                IconButton(tooltip: 'Previous', icon: const Icon(Icons.keyboard_arrow_up_rounded), onPressed: () => _stepMatch(-1)),
                IconButton(tooltip: 'Next', icon: const Icon(Icons.keyboard_arrow_down_rounded), onPressed: () => _stepMatch(1)),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _findOpen = false;
                    _matches = const [];
                    _matchIdx = -1;
                  }),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: TextField(controller: _replaceC, decoration: const InputDecoration(isDense: true, hintText: 'Replace with', prefixIcon: Icon(Icons.find_replace_rounded, size: 20)))),
                TextButton(onPressed: _replaceOne, child: const Text('Replace')),
                TextButton(onPressed: _replaceAll, child: const Text('All')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _problemsPanel() {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 190,
      child: Material(
        color: scheme.surfaceContainerHigh,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 4, 0),
              child: Row(
                children: [
                  Text('Problems (${_problems.length})', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _problemsOpen = false)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _problems.isEmpty
                  ? const Center(child: Text('No problems found'))
                  : ListView.builder(
                      itemCount: _problems.length,
                      itemBuilder: (context, i) {
                        final pr = _problems[i];
                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Icon(pr.error ? Icons.error_rounded : Icons.warning_amber_rounded, color: pr.error ? scheme.error : Colors.orange, size: 20),
                          title: Text(pr.message, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('Line ${pr.line}, column ${pr.col}', style: const TextStyle(fontSize: 11.5)),
                          onTap: () => _jumpToLine(pr.line, pr.col),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionBar() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          children: [
            for (final h in _lineColors)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Container(width: 18, height: 18, decoration: BoxDecoration(color: h.color, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black26, width: 0.6))),
                  label: Text(h.code, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                ),
              ),
            for (final s in _suggestions)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: s.snippet ? const Icon(Icons.bolt_rounded, size: 16) : null,
                  label: Text(s.label, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                  onPressed: () => _applySuggestion(s),
                ),
              ),
          ],
        ),
      ),
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
            _symbolButton('Tab', _unit),
            _iconButton(Icons.format_indent_decrease_rounded, 'Outdent', () => _shift(indent: false)),
            _iconButton(Icons.format_indent_increase_rounded, 'Indent', () => _shift(indent: true)),
            _iconButton(Icons.comment_outlined, 'Comment', _toggleComment),
            _iconButton(Icons.search_rounded, 'Find', () => setState(() => _findOpen = true)),
            for (final s in symbols) _symbolButton(s, s),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tip, VoidCallback onTap) {
    return IconButton(tooltip: tip, visualDensity: VisualDensity.compact, icon: Icon(icon, size: 21), onPressed: onTap);
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
