import 'package:flutter/material.dart';

import 'bottom_safe.dart';

/// "3/52" pill with up / down arrows (jump to the previous / next page). Tap the number to type a page.
class PageIndicatorPill extends StatelessWidget {
  const PageIndicatorPill({
    super.key,
    required this.current,
    required this.total,
    required this.onPrev,
    required this.onNext,
    this.onJump,
  });

  /// 1-based
  final int current;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<int>? onJump;

  Future<void> _ask(BuildContext context) async {
    final controller = TextEditingController(text: '$current');
    controller.selection = TextSelection(baseOffset: 0, extentOffset: controller.text.length);
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 - $total'),
          onSubmitted: (s) => Navigator.pop(ctx, int.tryParse(s.trim())),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(controller.text.trim())), child: const Text('Go')),
        ],
      ),
    );
    if (v != null) onJump?.call(v.clamp(1, total));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = scheme.inverseSurface.withValues(alpha: 0.92);
    final fg = scheme.onInverseSurface;
    return Material(
      color: Colors.transparent,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onJump == null ? null : () => _ask(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
              child: Text('$current/$total', style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(22)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Previous page',
                  icon: Icon(Icons.keyboard_arrow_up_rounded, color: fg),
                  onPressed: current > 1 ? onPrev : null,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Next page',
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: fg),
                  onPressed: current < total ? onNext : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Places [child] at the bottom-right of a Stack. Set [addInset] when the Stack is NOT already
/// inside a SafeArea (then the Android navigation buttons are cleared too).
class BottomRightOverlay extends StatelessWidget {
  const BottomRightOverlay({super.key, required this.child, this.addInset = false});

  final Widget child;
  final bool addInset;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 14 + (addInset ? bottomInset(context) : 0),
      child: child,
    );
  }
}
