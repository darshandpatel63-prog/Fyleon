import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/storage/prefs.dart';

void main() {
  // Any startup problem must show a message instead of silently closing the app.
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('FlutterError: ${details.exceptionAsString()}');
    };
    try {
      try {
        pdfrxFlutterInitialize();
      } catch (e) {
        // PDF viewing may fail later, but the rest of the app must still start.
        debugPrint('pdfrx init failed: $e');
      }
      final prefs = await SharedPreferences.getInstance();
      final config = await AppConfig.load();
      runApp(
        ProviderScope(
          overrides: [
            sharedPrefsProvider.overrideWithValue(prefs),
            appConfigProvider.overrideWithValue(config),
          ],
          child: const FyleonApp(),
        ),
      );
    } catch (e, st) {
      runApp(StartupErrorApp(error: e, stack: st));
    }
  }, (error, stack) {
    debugPrint('Uncaught error: $error\n$stack');
  });
}

/// Shown only if the app cannot start. Lets the user copy the error text.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error, required this.stack});

  final Object error;
  final StackTrace stack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SelectionArea(
              child: ListView(
                children: [
                  const Text(
                    'Fyleon could not start',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text('Please send a screenshot of this screen to the developer.'),
                  const SizedBox(height: 16),
                  Text('$error', style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 12),
                  Text(
                    '$stack',
                    maxLines: 25,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
