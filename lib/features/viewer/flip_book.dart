import 'dart:math' as math;

import 'package:flutter/material.dart';

class FlipBookController {
  _FlipBookState? _state;
  void next() => _state?._go(1);
  void prev() => _state?._go(-1);
  void jumpTo(int page) => _state?._jump(page);
  int get page => _state?._page ?? 0;
}

/// A single-page book with a page-turn animation (3D flip around the spine).
/// Drag left/right, or tap the left/right edge of the screen.
class FlipBook extends StatefulWidget {
  const FlipBook({
    super.key,
    required this.pageCount,
    required this.pageBuilder,
    required this.controller,
    this.initialPage = 0,
    this.onPageChanged,
    this.onTapCenter,
    this.pageColor = Colors.white,
  });

  final int pageCount;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final FlipBookController controller;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final VoidCallback? onTapCenter;
  final Color pageColor;

  @override
  State<FlipBook> createState() => _FlipBookState();
}

class _FlipBookState extends State<FlipBook> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  late int _page = widget.initialPage.clamp(0, math.max(0, widget.pageCount - 1));
  int _dir = 0; // +1 turning forward, -1 turning back
  double _drag = 0;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void dispose() {
    if (widget.controller._state == this) widget.controller._state = null;
    _c.dispose();
    super.dispose();
  }

  void _jump(int page) {
    if (widget.pageCount == 0) return;
    setState(() {
      _page = page.clamp(0, widget.pageCount - 1);
      _dir = 0;
      _animating = false;
      _c.value = 0;
    });
    widget.onPageChanged?.call(_page);
  }

  void _go(int dir) {
    if (_animating) return;
    final target = _page + dir;
    if (target < 0 || target >= widget.pageCount) return;
    setState(() => _dir = dir);
    _c.value = 0;
    _finish(true);
  }

  Future<void> _finish(bool commit) async {
    _animating = true;
    final from = _c.value;
    final span = commit ? (1 - from) : from;
    await _c.animateTo(
      commit ? 1.0 : 0.0,
      duration: Duration(milliseconds: (380 * span + 120).round()),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    setState(() {
      if (commit) _page += _dir;
      _dir = 0;
      _animating = false;
      _c.value = 0;
    });
    if (commit) widget.onPageChanged?.call(_page);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final w = context.size?.width ?? 1;
        if (d.localPosition.dx < w * 0.3) {
          _go(-1);
        } else if (d.localPosition.dx > w * 0.7) {
          _go(1);
        } else {
          widget.onTapCenter?.call();
        }
      },
      onHorizontalDragStart: (d) {
        if (_animating) return;
        _drag = 0;
      },
      onHorizontalDragUpdate: (d) {
        if (_animating) return;
        _drag += d.delta.dx;
        final dir = _drag < 0 ? 1 : -1;
        if ((dir == 1 && _page >= widget.pageCount - 1) || (dir == -1 && _page <= 0)) return;
        if (_dir != dir) setState(() => _dir = dir);
        final w = context.size?.width ?? 1;
        _c.value = (_drag.abs() / w).clamp(0.0, 1.0);
      },
      onHorizontalDragEnd: (d) {
        if (_animating || _dir == 0) return;
        final v = d.primaryVelocity ?? 0;
        final fast = (_dir == 1 && v < -500) || (_dir == -1 && v > 500);
        _finish(fast || _c.value > 0.35);
      },
      onHorizontalDragCancel: () {
        if (_animating || _dir == 0) return;
        _finish(false);
      },
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => _content(context),
        ),
      ),
    );
  }

  Widget _flat(BuildContext context, int i) {
    return RepaintBoundary(
      child: SizedBox.expand(
        child: ColoredBox(color: widget.pageColor, child: widget.pageBuilder(context, i)),
      ),
    );
  }

  Widget _shaded(Widget child, double alpha) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: alpha.clamp(0.0, 1.0)))),
      ],
    );
  }

  /// `a` = 0: page lies flat. `a` = 1: page stands edge-on (turned away).
  Widget _turning(BuildContext context, int index, double a) {
    final angle = a * math.pi / 2;
    return Transform(
      alignment: Alignment.centerLeft,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0009)
        ..rotateY(angle),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _flat(context, index),
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.black.withValues(alpha: 0.0),
                    Colors.black.withValues(alpha: 0.38 * a),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (widget.pageCount == 0) return const SizedBox.shrink();
    final t = _c.value;
    if (_dir > 0 && _page + 1 < widget.pageCount) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _shaded(_flat(context, _page + 1), 0.3 * (1 - t)),
          _turning(context, _page, t),
        ],
      );
    }
    if (_dir < 0 && _page - 1 >= 0) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _shaded(_flat(context, _page), 0.3 * t),
          _turning(context, _page - 1, 1 - t),
        ],
      );
    }
    return _flat(context, _page.clamp(0, widget.pageCount - 1));
  }
}
