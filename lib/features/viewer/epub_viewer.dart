import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../files/domain/file_item.dart';
import 'epub_parser.dart';
import 'epub_renderer.dart';

enum _ReadTheme { paper, sepia, night }

/// Basic EPUB reader: one chapter per page, table of contents, font size,
/// line spacing and reading themes. (Kindle-level features come in Phase 3.)
class EpubViewerScreen extends StatefulWidget {
  const EpubViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<EpubViewerScreen> createState() => _EpubViewerScreenState();
}

class _EpubViewerScreenState extends State<EpubViewerScreen> {
  late final Future<EpubData> _future = compute(parseEpub, widget.item.path);
  final _controller = PageController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _page = 0;
  double _fontSize = 18;
  double _lineHeight = 1.6;
  _ReadTheme _theme = _ReadTheme.paper;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  (Color, Color) get _colors {
    switch (_theme) {
      case _ReadTheme.paper:
        return (const Color(0xFFFFFFFF), const Color(0xFF1A1A1A));
      case _ReadTheme.sepia:
        return (const Color(0xFFF4ECD8), const Color(0xFF5B4636));
      case _ReadTheme.night:
        return (const Color(0xFF121212), const Color(0xFFD8D8D8));
    }
  }

  void _go(int page, int total) {
    final target = page.clamp(0, total - 1);
    _controller.animateToPage(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Reading settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              Text('Text size: ${_fontSize.round()}'),
              Slider(
                min: 12,
                max: 32,
                divisions: 20,
                value: _fontSize,
                onChanged: (v) {
                  setState(() => _fontSize = v);
                  setSheet(() {});
                },
              ),
              Text('Line spacing: ${_lineHeight.toStringAsFixed(1)}'),
              Slider(
                min: 1.2,
                max: 2.2,
                divisions: 10,
                value: _lineHeight,
                onChanged: (v) {
                  setState(() => _lineHeight = v);
                  setSheet(() {});
                },
              ),
              const SizedBox(height: 8),
              SegmentedButton<_ReadTheme>(
                segments: const [
                  ButtonSegment(value: _ReadTheme.paper, label: Text('Paper'), icon: Icon(Icons.wb_sunny_outlined)),
                  ButtonSegment(value: _ReadTheme.sepia, label: Text('Sepia'), icon: Icon(Icons.coffee_outlined)),
                  ButtonSegment(value: _ReadTheme.night, label: Text('Night'), icon: Icon(Icons.nightlight_outlined)),
                ],
                selected: {_theme},
                onSelectionChanged: (s) {
                  setState(() => _theme = s.first);
                  setSheet(() {});
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return FutureBuilder<EpubData>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            foregroundColor: fg,
            title: Text(
              data?.title ?? widget.item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 18),
            ),
            actions: [
              if (data != null) ...[
                IconButton(
                  tooltip: 'Reading settings',
                  icon: const Icon(Icons.text_fields_rounded),
                  onPressed: _openSettings,
                ),
                IconButton(
                  tooltip: 'Contents',
                  icon: const Icon(Icons.list_rounded),
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ],
            ],
          ),
          endDrawer: data == null ? null : _tocDrawer(data),
          body: _body(snap, bg, fg),
          bottomNavigationBar: data == null ? null : _pager(data, fg),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<EpubData> snap, Color bg, Color fg) {
    if (snap.connectionState != ConnectionState.done) {
      return Center(child: CircularProgressIndicator(color: fg));
    }
    if (snap.hasError) {
      final e = snap.error;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            e is FormatException ? e.message : 'Could not open this EPUB.',
            textAlign: TextAlign.center,
            style: TextStyle(color: fg),
          ),
        ),
      );
    }
    final data = snap.data!;
    return PageView.builder(
      controller: _controller,
      itemCount: data.chapters.length,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (context, i) => EpubChapterView(
        key: ValueKey('ch$i-${_fontSize.round()}-${_lineHeight.toStringAsFixed(1)}-${_theme.name}'),
        chapter: data.chapters[i],
        images: data.images,
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        textColor: fg,
      ),
    );
  }

  Widget _pager(EpubData data, Color fg) {
    final total = data.chapters.length;
    return SafeArea(
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            IconButton(
              color: fg,
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: _page > 0 ? () => _go(_page - 1, total) : null,
            ),
            Expanded(
              child: Text(
                'Chapter ${math.min(_page + 1, total)} of $total',
                textAlign: TextAlign.center,
                style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 13),
              ),
            ),
            IconButton(
              color: fg,
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _page < total - 1 ? () => _go(_page + 1, total) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tocDrawer(EpubData data) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                data.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
            if (data.author.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(data.author),
              ),
            const Divider(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: data.chapters.length,
                itemBuilder: (context, i) => ListTile(
                  selected: i == _page,
                  title: Text(data.chapters[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () {
                    Navigator.of(context).pop();
                    _controller.jumpToPage(i);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
