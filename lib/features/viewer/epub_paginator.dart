import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'epub_layout.dart';
import 'epub_parser.dart';

class PageItem {
  const PageItem(this.block, this.runs, this.topGap, {this.imageHeight = 0});
  final Block block;
  final List<Run> runs;
  final double topGap;
  final double imageHeight;
}

class BookPage {
  const BookPage(this.items, this.chapter);
  final List<PageItem> items;
  final int chapter;
}

class Pagination {
  const Pagination(this.pages, this.chapterFirstPage);
  final List<BookPage> pages;
  final List<int> chapterFirstPage;

  int chapterEnd(int chapter) =>
      chapter + 1 < chapterFirstPage.length ? chapterFirstPage[chapter + 1] : pages.length;
}

/// Splits the whole book into screen-sized pages (no scrolling needed).
/// Each chapter starts on a new page. Returns null if cancelled.
Future<Pagination?> paginateBook({
  required EpubData data,
  required double width,
  required double height,
  required ReaderStyle style,
  required bool Function() cancelled,
  void Function(double progress)? onProgress,
}) async {
  final pages = <BookPage>[];
  final firsts = <int>[];

  for (var ci = 0; ci < data.chapters.length; ci++) {
    if (cancelled()) return null;
    firsts.add(pages.length);
    final blocks = parseBlocks(data.chapters[ci], data.images);

    var cur = <PageItem>[];
    var y = 0.0;
    var lastAfter = 0.0; // space owed after the previous block

    void newPage() {
      if (cur.isNotEmpty) {
        pages.add(BookPage(cur, ci));
        cur = <PageItem>[];
      }
      y = 0;
      lastAfter = 0;
    }

    var counter = 0;
    for (final block in blocks) {
      if (++counter % 25 == 0) {
        await Future<void>.delayed(Duration.zero);
        if (cancelled()) return null;
      }

      if (block.kind == BlockKind.image) {
        final h = math.min(height * 0.6, 440.0);
        var gap = cur.isEmpty ? 0.0 : lastAfter + 6;
        if (y + gap + h > height) {
          newPage();
          gap = 0.0;
        }
        cur.add(PageItem(block, const [], gap, imageHeight: h));
        y += gap + h;
        lastAfter = style.fontSize * 0.6;
        continue;
      }
      if (block.kind == BlockKind.rule) {
        final gap = cur.isEmpty ? 0.0 : lastAfter + 4;
        if (cur.isNotEmpty && y + gap + 12 < height) {
          cur.add(PageItem(block, const [], gap, imageHeight: 12));
          y += gap + 12;
          lastAfter = style.fontSize * 0.4;
        }
        continue;
      }

      final textStyle = blockStyle(block, style);
      final textWidth = math.max(60.0, width - blockInset(block));
      final after = spaceAfter(block, style);
      var runs = block.runs;
      var guard = 0;

      while (runs.isNotEmpty && guard++ < 400) {
        final topGap = cur.isEmpty ? 0.0 : lastAfter + spaceBefore(block, style);
        final span = spanFor(runs, textStyle);
        final tp = TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
          textAlign: blockAlign(block),
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: textWidth);
        final full = tp.height;
        final remaining = height - y - topGap;

        if (full <= remaining) {
          cur.add(PageItem(block, runs, topGap));
          y += topGap + full;
          lastAfter = after;
          tp.dispose();
          break;
        }

        final lines = tp.computeLineMetrics();
        var acc = 0.0;
        var k = 0;
        for (final l in lines) {
          if (acc + l.height <= remaining + 0.5) {
            acc += l.height;
            k++;
          } else {
            break;
          }
        }
        if (k == 0) {
          tp.dispose();
          if (cur.isNotEmpty) {
            newPage();
            continue; // try again on an empty page
          }
          // a single line taller than a page: show it anyway
          cur.add(PageItem(block, runs, 0));
          y += full;
          lastAfter = after;
          break;
        }

        final total = runsText(runs).length;
        final offset = tp.getPositionForOffset(Offset(1, acc + 1)).offset;
        tp.dispose();
        if (offset <= 0 || offset >= total) {
          cur.add(PageItem(block, runs, topGap));
          y += topGap + full;
          lastAfter = after;
          break;
        }
        cur.add(PageItem(block, sliceRuns(runs, 0, offset), topGap));
        newPage();
        runs = trimLeftRuns(sliceRuns(runs, offset));
      }
    }
    newPage();
    onProgress?.call((ci + 1) / data.chapters.length);
    await Future<void>.delayed(Duration.zero);
  }

  if (pages.isEmpty) {
    pages.add(const BookPage([], 0));
  }
  return Pagination(pages, firsts);
}
