import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/prefs.dart';
import '../utils/platform_utils.dart';
import 'app_themes.dart';

class ThemeState {
  const ThemeState({required this.selectedId, required this.unlockedUntil});

  final String selectedId;

  /// theme id -> unlock expiry (ms since epoch)
  final Map<String, int> unlockedUntil;

  bool isUnlocked(String id, {int? nowMs}) {
    final spec = AppThemes.byIdOrNull(id);
    if (spec == null || !spec.premium) return true;
    // Platforms without ads (desktop) get all themes for now.
    if (!adsSupported) return true;
    final exp = unlockedUntil[id];
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return exp != null && exp > now;
  }

  int? remainingMs(String id) {
    final exp = unlockedUntil[id];
    if (exp == null) return null;
    final left = exp - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? left : null;
  }

  ThemeState copyWith({String? selectedId, Map<String, int>? unlockedUntil}) =>
      ThemeState(
        selectedId: selectedId ?? this.selectedId,
        unlockedUntil: unlockedUntil ?? this.unlockedUntil,
      );
}

class ThemeController extends Notifier<ThemeState> {
  static const _kSelected = 'theme_selected';
  static const _kUnlocks = 'theme_unlocks';

  @override
  ThemeState build() {
    final prefs = ref.read(sharedPrefsProvider);
    final unlocks = <String, int>{};
    try {
      final raw = prefs.getString(_kUnlocks);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        m.forEach((k, v) {
          if (v is num) unlocks[k] = v.toInt();
        });
      }
    } catch (_) {}
    return ThemeState(
      selectedId: prefs.getString(_kSelected) ?? AppThemes.systemId,
      unlockedUntil: unlocks,
    );
  }

  Future<void> select(String id) async {
    state = state.copyWith(selectedId: id);
    await ref.read(sharedPrefsProvider).setString(_kSelected, id);
  }

  Future<void> unlock(String id, Duration duration) async {
    final until = DateTime.now().add(duration).millisecondsSinceEpoch;
    final next = Map<String, int>.from(state.unlockedUntil)..[id] = until;
    state = state.copyWith(unlockedUntil: next);
    await ref.read(sharedPrefsProvider).setString(_kUnlocks, jsonEncode(next));
  }
}

final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeState>(ThemeController.new);
