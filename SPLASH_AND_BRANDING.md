# SPLASH AND BRANDING

- Name: Fyleon. Tagline: "Open anything."
- Icon: white rounded "F" with a folded top-right corner (a page) and a small 4-point spark, on the brand gradient.
  Source: `assets/icon/icon.svg` (approx.), PNGs made by `python3 tool/make_icons.py`.
  Files: `icon.png` (legacy), `icon_foreground.png` + `icon_background.png` (adaptive), `icon_mono.png` (Android 13 themed icon).
- Native splash: `flutter_native_splash` (flat #4F46E5 + foreground logo; Android 12 splash configured) generated in CI on first run.
- In-app splash: `features/splash/splash_screen.dart` - gradient, logo scale-in with overshoot, name + tagline fade, 1.7 s,
  then fade-slide to Home. Ads init and remote settings load in the background and never block it.
- NOTE: flutter_launcher_icons / flutter_native_splash are not in pubspec dependencies (they broke the release build). To regenerate locally: `flutter pub add --dev flutter_launcher_icons flutter_native_splash`, run both tools, then `flutter pub remove` them.
- To change the icon: edit `tool/make_icons.py`, run it, commit PNGs, delete the generated `mipmap-*` folders (or run
  `dart run flutter_launcher_icons` locally), and re-run `dart run flutter_native_splash:create`.
- Before release: check name availability (Play, App Store, trademark) and prepare store graphics (feature graphic 1024x500, screenshots).
