import 'package:flutter/widgets.dart';

/// A [Stack] that ALWAYS fills the space it is given.
///
/// A plain `Stack` shrinks to its non-positioned children. A single zero-size one (for example
/// `SizedBox.shrink()` used as "nothing to show") makes the whole Stack 0 x 0 inside a Scaffold body,
/// and then everything in it (video, controls, gestures) is invisible and cannot be touched.
/// This is exactly what produced the black video screen. Use this widget for full-screen layers.
class FullScreenStack extends StatelessWidget {
  const FullScreenStack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(fit: StackFit.expand, children: children),
    );
  }
}
