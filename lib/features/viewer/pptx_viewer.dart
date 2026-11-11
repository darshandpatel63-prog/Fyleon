import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../shared/widgets/bottom_safe.dart';
import '../../shared/widgets/page_indicator_pill.dart';
import '../files/domain/file_item.dart';
import 'pptx_parser.dart';
import 'viewer_chrome.dart';

/// PowerPoint viewer: draws every slide with its shapes, colors, text and pictures.
/// (Approximate: animations, charts, SmartArt and some fonts/effects are not shown.)
class PptxViewerScreen extends StatefulWidget {
  const PptxViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<PptxViewerScreen> createState() => _PptxViewerScreenState();
}

class _PptxViewerScreenState extends State<PptxViewerScreen> {
  late final Future<PptxDeck> _future = compute(parsePptx, widget.item.path);
  final _controller = PageController();
  final _scroll = ScrollController();
  int _page = 0;

  /// true = all slides one below the other (default, like a PDF); false = one slide at a time.
  bool _grid = true;
  double _extent = 300;
  int _count = 1;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_grid || !_scroll.hasClients) return;
      final i = ((_scroll.offset + _extent * 0.3) / _extent).floor().clamp(0, _count - 1);
      if (i != _page && mounted) setState(() => _page = i);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _goTo(int slide) {
    final i = slide.clamp(1, _count) - 1;
    if (_scroll.hasClients) {
      _scroll.animateTo(i * _extent, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          ViewerActions(
            item: widget.item,
            leading: [
              IconButton(
                tooltip: _grid ? 'One slide at a time' : 'All slides',
                icon: Icon(_grid ? Icons.slideshow_rounded : Icons.view_agenda_rounded),
                onPressed: () => setState(() => _grid = !_grid),
              ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<PptxDeck>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final e = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(e is FormatException ? e.message : 'Could not open this presentation.', textAlign: TextAlign.center),
              ),
            );
          }
          final deck = snap.data!;
          _count = deck.slides.length;
          if (!_grid) return _show(deck);
          return Stack(
            children: [
              _list(deck),
              BottomRightOverlay(
                addInset: true,
                child: PageIndicatorPill(
                  current: _page + 1,
                  total: _count,
                  onPrev: () => _goTo(_page),
                  onNext: () => _goTo(_page + 2),
                  onJump: _goTo,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _show(PptxDeck deck) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: deck.slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: PptxSlideView(deck: deck, slide: deck.slides[i]),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 12 + bottomInset(context), top: 6),
          child: Text('Slide ${_page + 1} of ${deck.slides.length}', style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }

  Widget _list(PptxDeck deck) {
    final width = MediaQuery.sizeOf(context).width;
    final column = math.min(width, 900.0);
    final slideW = column - 24;
    final slideH = slideW * deck.cy / deck.cx;
    const labelH = 20.0;
    const gap = 14.0;
    _extent = labelH + slideH + gap;
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(0, 4, 0, 90 + bottomInset(context)),
      itemExtent: _extent,
      itemCount: deck.slides.length,
      itemBuilder: (context, i) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: column,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, gap),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: labelH,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 3),
                      child: Text(
                        'Slide ${i + 1}',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                  ),
                ),
                PptxSlideView(deck: deck, slide: deck.slides[i]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PptxSlideView extends StatelessWidget {
  const PptxSlideView({super.key, required this.deck, required this.slide});

  final PptxDeck deck;
  final PptxSlide slide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        var w = box.maxWidth.isFinite ? box.maxWidth : 360.0;
        var h = w * deck.cy / deck.cx;
        if (box.maxHeight.isFinite && h > box.maxHeight) {
          h = box.maxHeight;
          w = h * deck.cx / deck.cy;
        }
        final k = w / deck.cx; // pixels per EMU
        return Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: Color(slide.background),
            boxShadow: const [BoxShadow(blurRadius: 8, color: Color(0x33000000))],
          ),
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [for (final s in slide.shapes) _shape(s, k)],
            ),
          ),
        );
      },
    );
  }

  Widget _shape(PptxShape s, double k) {
    var width = math.max(s.w * k, 0.0);
    var height = math.max(s.h * k, 0.0);
    final lineW = s.lineW * k;

    Widget content;
    if (s.image != null) {
      content = Image.memory(s.image!, fit: BoxFit.fill, errorBuilder: (c, e, st) => const SizedBox.shrink());
    } else if (s.table != null) {
      content = _table(s.table!, k);
    } else if (s.geom == 'line') {
      final horizontal = width >= height;
      final thick = math.max(1.0, lineW);
      if (horizontal) {
        height = thick;
      } else {
        width = thick;
      }
      content = ColoredBox(color: Color(s.lineColor ?? 0xFF000000));
    } else {
      content = _box(s, k, width, height);
    }

    var child = content;
    if (s.rot != 0) {
      child = Transform.rotate(angle: s.rot * math.pi / 180, child: child);
    }
    return Positioned(left: s.x * k, top: s.y * k, width: width, height: height, child: child);
  }

  Widget _box(PptxShape s, double k, double width, double height) {
    final lineW = s.lineW * k;
    final hasBorder = s.lineColor != null && s.lineW > 0;
    final radius = s.geom == 'roundRect' ? BorderRadius.circular(math.min(width, height) * 0.16) : null;
    final decoration = BoxDecoration(
      color: s.fill == null ? null : Color(s.fill!),
      borderRadius: radius,
      shape: s.geom == 'ellipse' && (width - height).abs() < 1 ? BoxShape.circle : BoxShape.rectangle,
      border: hasBorder ? Border.all(color: Color(s.lineColor!), width: math.max(0.5, lineW)) : null,
    );
    Widget inner = s.paras.isEmpty ? const SizedBox.expand() : _text(s, k);
    if (s.geom == 'ellipse' && (width - height).abs() >= 1) {
      inner = ClipOval(child: ColoredBox(color: s.fill == null ? Colors.transparent : Color(s.fill!), child: inner));
      return inner;
    }
    return DecoratedBox(decoration: decoration, child: inner);
  }

  Widget _text(PptxShape s, double k) {
    final align = s.anchor == 'ctr' ? Alignment.center : (s.anchor == 'b' ? Alignment.bottomCenter : Alignment.topCenter);
    final pad = EdgeInsets.fromLTRB(s.insets[0] * k, s.insets[1] * k, s.insets[2] * k, s.insets[3] * k);
    return ClipRect(
      child: Padding(
        padding: pad,
        child: Align(
          alignment: align,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final para in s.paras) _para(para, k)],
          ),
        ),
      ),
    );
  }

  Widget _para(PptxPara para, double k) {
    final spans = <InlineSpan>[];
    final first = para.runs.first;
    if (para.bullet) {
      spans.add(TextSpan(
        text: '\u2022  ',
        style: TextStyle(fontSize: first.sizePt * 12700 * k, color: Color(first.color), height: 1.15),
      ));
    }
    for (final r in para.runs) {
      spans.add(TextSpan(
        text: r.text,
        style: TextStyle(
          fontSize: math.max(1.0, r.sizePt * 12700 * k),
          color: Color(r.color),
          fontWeight: r.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: r.italic ? FontStyle.italic : FontStyle.normal,
          decoration: r.underline ? TextDecoration.underline : TextDecoration.none,
          height: 1.15,
        ),
      ));
    }
    TextAlign a;
    switch (para.align) {
      case 'ctr':
        a = TextAlign.center;
        break;
      case 'r':
        a = TextAlign.right;
        break;
      case 'just':
        a = TextAlign.justify;
        break;
      default:
        a = TextAlign.left;
    }
    return Padding(
      padding: EdgeInsets.only(left: para.level * first.sizePt * 12700 * k * 1.2),
      child: Text.rich(TextSpan(children: spans), textAlign: a, textScaler: TextScaler.noScaling),
    );
  }

  Widget _table(List<List<String>> rows, double k) {
    final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final size = math.max(7.0, 16 * 12700 * k);
    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.85), border: Border.all(color: const Color(0x55000000))),
      child: Column(
        children: [
          for (final r in rows)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < cols; c++)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0x33000000)), bottom: BorderSide(color: Color(0x33000000)))),
                        child: Text(
                          c < r.length ? r[c] : '',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: size, color: Colors.black87),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
