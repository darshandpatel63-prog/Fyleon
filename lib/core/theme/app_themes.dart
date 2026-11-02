import 'package:flutter/material.dart';

class FyleonThemeSpec {
  const FyleonThemeSpec({
    required this.id,
    required this.name,
    required this.seed,
    required this.brightness,
    required this.gradient,
    this.premium = false,
    this.amoled = false,
  });

  final String id;
  final String name;
  final Color seed;
  final Brightness brightness;
  final List<Color> gradient;
  final bool premium;
  final bool amoled;

  ThemeData build() {
    var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    if (amoled) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF171717),
        surfaceContainerHighest: const Color(0xFF1E1E1E),
      );
    }
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: brightness,
    );
    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.primaryContainer,
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}

class AppThemes {
  AppThemes._();

  static const systemId = 'system';

  // ---- Free themes ----
  static const fyleonLight = FyleonThemeSpec(
    id: 'fyleon_light',
    name: 'Fyleon Light',
    seed: Color(0xFF5B4BE8),
    brightness: Brightness.light,
    gradient: [Color(0xFFEEF0FF), Color(0xFFD9DCFF)],
  );
  static const fyleonDark = FyleonThemeSpec(
    id: 'fyleon_dark',
    name: 'Fyleon Dark',
    seed: Color(0xFF7C6CFF),
    brightness: Brightness.dark,
    gradient: [Color(0xFF1B1840), Color(0xFF0E0C24)],
  );
  static const amoled = FyleonThemeSpec(
    id: 'amoled',
    name: 'AMOLED Black',
    seed: Color(0xFF8B7CFF),
    brightness: Brightness.dark,
    gradient: [Color(0xFF111111), Color(0xFF000000)],
    amoled: true,
  );

  // ---- Premium themes (rewarded ad) ----
  static const ocean = FyleonThemeSpec(
    id: 'ocean',
    name: 'Ocean',
    seed: Color(0xFF0A84FF),
    brightness: Brightness.light,
    gradient: [Color(0xFFCFE8FF), Color(0xFF7DB8FF)],
    premium: true,
  );
  static const forest = FyleonThemeSpec(
    id: 'forest',
    name: 'Emerald Forest',
    seed: Color(0xFF1B9E6B),
    brightness: Brightness.dark,
    gradient: [Color(0xFF0F3D2E), Color(0xFF07201A)],
    premium: true,
  );
  static const sunset = FyleonThemeSpec(
    id: 'sunset',
    name: 'Sunset',
    seed: Color(0xFFFF7A3D),
    brightness: Brightness.light,
    gradient: [Color(0xFFFFE0C7), Color(0xFFFFA67A)],
    premium: true,
  );
  static const royal = FyleonThemeSpec(
    id: 'royal',
    name: 'Royal Purple',
    seed: Color(0xFF9B51E0),
    brightness: Brightness.dark,
    gradient: [Color(0xFF2E1A52), Color(0xFF150C2B)],
    premium: true,
  );
  static const rose = FyleonThemeSpec(
    id: 'rose',
    name: 'Rose Gold',
    seed: Color(0xFFE0778F),
    brightness: Brightness.light,
    gradient: [Color(0xFFFFE3EA), Color(0xFFF4B6C5)],
    premium: true,
  );
  static const cyber = FyleonThemeSpec(
    id: 'cyber',
    name: 'Neon Cyber',
    seed: Color(0xFF00E5C7),
    brightness: Brightness.dark,
    gradient: [Color(0xFF062B33), Color(0xFF020E12)],
    premium: true,
  );

  static const all = <FyleonThemeSpec>[
    fyleonLight,
    fyleonDark,
    amoled,
    ocean,
    forest,
    sunset,
    royal,
    rose,
    cyber,
  ];

  static FyleonThemeSpec? byIdOrNull(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  static FyleonThemeSpec byId(String id) => byIdOrNull(id) ?? fyleonLight;
}
