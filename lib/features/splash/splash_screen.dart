import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/remote/remote_settings.dart';
import '../../shared/widgets/animations.dart';
import '../ads/ad_service.dart';
import '../files/presentation/home_screen.dart';

/// Animated splash. Starts ads init + remote settings in the background and
/// never waits for them (ads must not delay the app).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  late final Animation<double> _logoScale = Tween<double>(begin: 0.6, end: 1).animate(
    CurvedAnimation(parent: _c, curve: const Interval(0, 0.6, curve: Curves.easeOutBack)),
  );
  late final Animation<double> _logoFade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, 0.4, curve: Curves.easeOut),
  );
  late final Animation<double> _textFade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.45, 1, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _c.forward();
    unawaited(ref.read(remoteSettingsProvider.notifier).refresh());
    unawaited(ref.read(adServiceProvider).init());
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(fadeSlideRoute(const HomeScreen()));
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFF06B6D4)],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FadeTransition(
                opacity: _logoFade,
                child: ScaleTransition(
                  scale: _logoScale,
                  child: Image.asset('assets/icon/icon_foreground.png', width: 190, height: 190),
                ),
              ),
              FadeTransition(
                opacity: _textFade,
                child: const Column(
                  children: [
                    Text(
                      AppConstants.appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      AppConstants.tagline,
                      style: TextStyle(color: Colors.white70, fontSize: 16, letterSpacing: 0.6),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
