import 'package:flutter/material.dart';

/// Keeps content above the Android navigation buttons / gesture bar.
class BottomSafe extends StatelessWidget {
  const BottomSafe({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(top: false, left: false, right: false, child: child);
}

/// Extra space a scrolling list needs at its end so the last item is not hidden.
double bottomInset(BuildContext context) => MediaQuery.viewPaddingOf(context).bottom;
