import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/prefs.dart';

/// Things the owner can put on the viewer toolbar (image, PDF, PPTX, Word, text...).
enum ViewerAction { star, favorite, share, edit, info, openWith, neighbors }

/// Where an action lives. `top` = icon on the top bar, `menu` = inside the three-dots menu,
/// `pill` = floating pill at the bottom (images only; other viewers show it in the menu),
/// `off` = hidden everywhere.
enum ActionPlace { top, menu, pill, off }

ActionPlace defaultPlaceOf(ViewerAction a) {
  switch (a) {
    case ViewerAction.star:
    case ViewerAction.share:
      return ActionPlace.top;
    case ViewerAction.edit:
    case ViewerAction.info:
      return ActionPlace.pill;
    case ViewerAction.favorite:
    case ViewerAction.openWith:
    case ViewerAction.neighbors:
      return ActionPlace.menu;
  }
}

/// Pure data (easy to unit test).
class ViewerToolbarSettings {
  const ViewerToolbarSettings({this.places = const {}, this.maxTop = 3, this.maxPill = 3});

  final Map<ViewerAction, ActionPlace> places;

  /// Icons allowed on the top bar before the rest moves into the menu.
  final int maxTop;
  final int maxPill;

  ActionPlace placeOf(ViewerAction a) => places[a] ?? defaultPlaceOf(a);

  ViewerToolbarSettings withPlace(ViewerAction a, ActionPlace p) =>
      ViewerToolbarSettings(places: {...places, a: p}, maxTop: maxTop, maxPill: maxPill);

  ViewerToolbarSettings withMaxTop(int n) =>
      ViewerToolbarSettings(places: places, maxTop: n.clamp(1, 5), maxPill: maxPill);

  /// Splits the available actions into the three visible groups.
  /// - top: at most [maxTop] icons (extra ones fall into the menu)
  /// - pill: only when [allowPill] (image viewer); otherwise pill actions take a free spot on the top bar,
  ///   or go to the menu when the top bar is full
  ToolbarLayout layout(Iterable<ViewerAction> available, {required bool allowPill}) {
    final avail = ViewerAction.values.where(available.toSet().contains).toList();
    final top = <ViewerAction>[];
    final menu = <ViewerAction>[];
    final pill = <ViewerAction>[];
    for (final a in avail) {
      switch (placeOf(a)) {
        case ActionPlace.top:
          if (top.length < maxTop) {
            top.add(a);
          } else {
            menu.add(a);
          }
        case ActionPlace.menu:
          menu.add(a);
        case ActionPlace.pill:
          if (allowPill && pill.length < maxPill) {
            pill.add(a);
          } else if (!allowPill && top.length < maxTop) {
            top.add(a); // no pill in this viewer: use a free spot on the top bar
          } else {
            menu.add(a);
          }
        case ActionPlace.off:
          break;
      }
    }
    return ToolbarLayout(top: top, menu: menu, pill: pill);
  }

  Map<String, Object?> toJson() => {
        'maxTop': maxTop,
        'places': {for (final e in places.entries) e.key.name: e.value.name},
      };

  static ViewerToolbarSettings fromJson(Object? raw) {
    if (raw is! Map) return const ViewerToolbarSettings();
    final places = <ViewerAction, ActionPlace>{};
    final p = raw['places'];
    if (p is Map) {
      for (final a in ViewerAction.values) {
        final v = p[a.name];
        for (final pl in ActionPlace.values) {
          if (pl.name == v) places[a] = pl;
        }
      }
    }
    final mt = raw['maxTop'];
    return ViewerToolbarSettings(places: places, maxTop: mt is num ? mt.toInt().clamp(1, 5) : 3);
  }
}

class ToolbarLayout {
  const ToolbarLayout({required this.top, required this.menu, required this.pill});
  final List<ViewerAction> top;
  final List<ViewerAction> menu;
  final List<ViewerAction> pill;
}

class ViewerToolbarNotifier extends Notifier<ViewerToolbarSettings> {
  static const _key = 'viewer_toolbar_v1';

  @override
  ViewerToolbarSettings build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw != null) {
      try {
        return ViewerToolbarSettings.fromJson(jsonDecode(raw));
      } catch (_) {}
    }
    return const ViewerToolbarSettings();
  }

  Future<void> setPlace(ViewerAction a, ActionPlace p) => _save(state.withPlace(a, p));

  Future<void> setMaxTop(int n) => _save(state.withMaxTop(n));

  Future<void> reset() => _save(const ViewerToolbarSettings());

  Future<void> _save(ViewerToolbarSettings next) async {
    state = next;
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(next.toJson()));
  }
}

final viewerToolbarProvider =
    NotifierProvider<ViewerToolbarNotifier, ViewerToolbarSettings>(ViewerToolbarNotifier.new);

// ---------------------------------------------------------------- media prefs

/// Keep audio playing when the app is minimised or the screen is locked (audio and video).
class BackgroundPlayNotifier extends Notifier<bool> {
  static const _key = 'media_background_play_v1';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_key) ?? true;

  Future<void> set(bool v) async {
    state = v;
    await ref.read(sharedPrefsProvider).setBool(_key, v);
  }
}

final backgroundPlayProvider = NotifierProvider<BackgroundPlayNotifier, bool>(BackgroundPlayNotifier.new);
