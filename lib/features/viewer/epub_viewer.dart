import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../files/domain/file_item.dart';
import 'epub_layout.dart';
import 'epub_paginator.dart';
import 'epub_parser.dart';
import 'flip_book.dart';

enum _ReadTheme { paper, sepia, night }

/// EPUB reader: the book is split into real pages that fit the screen
/// (nothing to scroll), with a page-turn animation.
class EpubViewerScreen extends StatefulWidget {
  const EpubViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<EpubViewerScreen> createState() => _EpubViewerScreenState();
}

class _EpubViewerScreenState extends State<EpubViewerScreen> {
  static const _hPad = 26.0;
  static const _topPad = 20.0;
  static const _bottomPad = 12.0;

  late final Future<EpubData> _future = compute(parseEpub, widget.item.path);
  final _flip = FlipBookController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  Pagination? _pag;
  String? _layoutKey;
  bool _paginating = false;
  double _progress = 0;
  int _page = 0;
  int _token = 0;

  double _fontSize = 18;
  double _lineHeight = 1.6;
  _ReadTheme _theme = _ReadTheme.paper;

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

  @override
  void dispose() {
    _token++; // cancels a running pagination
    super.dispose();
  }

  Future<void> _repaginate(Size size, EpubData data) async {
    final token = ++_token;
    final old = _pag;
    int? chapter;
    double anchor = 0;
    if (old != null && old.pages.isNotEmpty) {
      final cur = old.pages[_page.clamp(0, old.pages.length - 1)];
      chapter = cur.chapter;
      final first = old.chapterFirstPage[chapter];
      final count = math.max(1, old.chapterEnd(chapter) - first);
      anchor = (_page - first) / count;
    }
    if (mounted) {
      setState(() {
        _paginating = true;
        _progress = 0;
      });
    }
    final style = ReaderStyle(fontSize: _fontSize, lineHeight: _lineHeight, color: _colors.$2);
    final result = await paginateBook(
      data: data,
      width: size.width,
      height: size.height - 6,
      style: style,
      cancelled: () => token != _token || !mounted,
      onProgress: (v) {
        if (mounted && token == _token) setState(() => _progress = v);
      },
    );
    if (!mounted || result == null || token != _token) return;
    var newPage = 0;
    if (chapter != null && chapter < result.chapterFirstPage.length) {
      final first = result.chapterFirstPage[chapter];
      final count = math.max(1, result.chapterEnd(chapter) - first);
      newPage = (first + (anchor * count).round()).clamp(0, result.pages.length - 1);
    }
    setState(() {
      _pag = result;
      _page = newPage;
      _paginating = false;
    });
  }

  void _openSettings() {
    var fs = _fontSize;
    var lh = _lineHeight;
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
              Text('Text size: ${fs.round()}'),
              Slider(
                min: 12,
                max: 32,
                divisions: 20,
                value: fs,
                onChanged: (v) => setSheet(() => fs = v),
                onChangeEnd: (v) => setState(() => _fontSize = v),
              ),
              Text('Line spacing: ${lh.toStringAsFixed(1)}'),
              Slider(
                min: 1.2,
                max: 2.2,
                divisions: 10,
                value: lh,
                onChanged: (v) => setSheet(() => lh = v),
                onChangeEnd: (v) => setState(() => _lineHeight = v),
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
          endDrawer: (data == null || _pag == null) ? null : _tocDrawer(data, _pag!),
          body: _body(snap, bg, fg),
          bottomNavigationBar: (data == null || _pag == null) ? null : _bottomBar(data, _pag!, fg),
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
    return LayoutBuilder(
      builder: (context, box) {
        final w = math.max(100.0, box.maxWidth - _hPad * 2);
        final h = math.max(100.0, box.maxHeight - _topPad - _bottomPad);
        final key = '${w.round()}x${h.round()}-$_fontSize-$_lineHeight';
        if (key != _layoutKey) {
          _layoutKey = key;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _repaginate(Size(w, h), data);
          });
        }
        final pag = _pag;
        if (pag == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: fg, value: _progress > 0 ? _progress : null),
                const SizedBox(height: 14),
                Text('Preparing pages...', style: TextStyle(color: fg.withValues(alpha: 0.7))),
              ],
            ),
          );
        }
        final style = ReaderStyle(fontSize: _fontSize, lineHeight: _lineHeight, color: fg);
        return Stack(
          children: [
            Positioned.fill(
              child: FlipBook(
                key: ObjectKey(pag),
                controller: _flip,
                pageCount: pag.pages.length,
                initialPage: _page,
                pageColor: bg,
                onPageChanged: (i) => setState(() => _page = i),
                pageBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.fromLTRB(_hPad, _topPad, _hPad, _bottomPad),
                  child: _PageContent(page: pag.pages[i], style: style),
                ),
              ),
            ),
            if (_paginating)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 3),
              ),
          ],
        );
      },
    );
  }

  Widget _bottomBar(EpubData data, Pagination pag, Color fg) {
    final total = pag.pages.length;
    final page = _page.clamp(0, total - 1);
    final chapter = data.chapters[pag.pages[page].chapter.clamp(0, data.chapters.length - 1)].title;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (total > 1)
              SizedBox(
                height: 28,
                child: Slider(
                  min: 0,
                  max: (total - 1).toDouble(),
                  value: page.toDouble(),
                  onChanged: (v) {
                    setState(() => _page = v.round());
                    _flip.jumpTo(v.round());
                  },
                ),
              ),
            Text(
              '${page + 1} / $total  -  $chapter',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: fg.withValues(alpha: 0.65), fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tocDrawer(EpubData data, Pagination pag) {
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
              Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Text(data.author)),
            const Divider(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: data.chapters.length,
                itemBuilder: (context, i) {
                  final current = pag.pages[_page.clamp(0, pag.pages.length - 1)].chapter == i;
                  return ListTile(
                    selected: current,
                    title: Text(data.chapters[i].title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.of(context).pop();
                      final target = pag.chapterFirstPage[i].clamp(0, pag.pages.length - 1);
                      setState(() => _page = target);
                      _flip.jumpTo(target);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draws one page. Uses the SAME styles/widths as the paginator, so it fits exactly.
class _PageContent extends StatelessWidget {
  const _PageContent({required this.page, required this.style});

  final BookPage page;
  final ReaderStyle style;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox.expand(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in page.items)
              Padding(
                padding: EdgeInsets.only(top: item.topGap),
                child: _item(item),
              ),
          ],
        ),
      ),
    );
  }

  Widget _item(PageItem item) {
    final b = item.block;
    if (b.kind == BlockKind.image && b.image != null) {
      return SizedBox(
        height: item.imageHeight,
        child: Image.memory(b.image!, fit: BoxFit.contain, errorBuilder: (c, e, s) => const SizedBox.shrink()),
      );
    }
    if (b.kind == BlockKind.rule) {
      return Divider(height: item.imageHeight, color: style.color.withValues(alpha: 0.3));
    }
    final text = Text.rich(
      spanFor(item.runs, blockStyle(b, style)),
      textAlign: blockAlign(b),
      textScaler: TextScaler.noScaling,
    );
    if (b.kind == BlockKind.quote) {
      return Container(
        padding: const EdgeInsets.only(left: 13),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: style.color.withValues(alpha: 0.35), width: 3)),
        ),
        child: text,
      );
    }
    return text;
  }
}
