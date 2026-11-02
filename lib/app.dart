import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_themes.dart';
import 'core/theme/theme_controller.dart';
import 'features/splash/splash_screen.dart';

class FyleonApp extends ConsumerWidget {
  const FyleonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeControllerProvider);
    final id = themeState.selectedId;

    ThemeData light;
    ThemeData dark;
    ThemeMode mode;
    if (id == AppThemes.systemId || !themeState.isUnlocked(id)) {
      light = AppThemes.fyleonLight.build();
      dark = AppThemes.fyleonDark.build();
      mode = ThemeMode.system;
    } else {
      final built = AppThemes.byId(id).build();
      light = built;
      dark = built;
      mode = ThemeMode.light;
    }

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      home: const SplashScreen(),
    );
  }
}
