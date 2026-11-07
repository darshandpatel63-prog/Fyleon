import 'package:flutter/material.dart';

/// Fade + slight slide for list items (staggered by index).
class FadeSlideIn extends StatelessWidget {
  const FadeSlideIn({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final delay = index.clamp(0, 8) * 40;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, 14 * (1 - v)), child: child),
      ),
      child: child,
    );
  }
}

Route<T> fadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutQuart, reverseCurve: Curves.easeInCubic);
      final away = CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeOutCubic);
      // when ANOTHER page opens on top of this one, this page shrinks back slightly
      return ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.94).animate(away),
        child: FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.6).animate(away),
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.0, 0.06), end: Offset.zero).animate(curved),
              child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved), child: child),
            ),
          ),
        ),
      );
    },
  );
}
