import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Expanding rings around an icon: "searching / waiting for devices".
class RadarPulse extends StatefulWidget {
  const RadarPulse({super.key, this.size = 170, this.icon = Icons.bolt_rounded, this.active = true});

  final double size;
  final IconData icon;
  final bool active;

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat();
  }

  @override
  void didUpdateWidget(RadarPulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) _c.repeat();
    if (!widget.active && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(size: Size(s, s), painter: _RingsPainter(_c.value, scheme.primary)),
          ),
          Container(
            width: s * 0.42,
            height: s * 0.42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary], begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: scheme.primary.withValues(alpha: 0.4), blurRadius: 18, spreadRadius: 1)],
            ),
            child: Icon(widget.icon, color: Colors.white, size: s * 0.22),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;
    for (var k = 0; k < 3; k++) {
      final phase = (t + k / 3) % 1.0;
      final r = maxR * (0.3 + 0.7 * phase);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = color.withValues(alpha: math.max(0, 0.45 * (1 - phase)));
      canvas.drawCircle(center, r, paint);
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.color != color;
}

/// Round icon for a device in lists.
class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar({super.key, this.size = 44, this.icon = Icons.smartphone_rounded});

  final double size;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      child: Icon(icon, color: scheme.onPrimaryContainer, size: size * 0.52),
    );
  }
}
