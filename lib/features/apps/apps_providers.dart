import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/native/native_bridge.dart';
import 'apps_model.dart';

class AppsState {
  const AppsState({this.entries = const [], this.usageAccess = false, this.loading = true});

  final List<AppEntry> entries;
  final bool usageAccess;
  final bool loading;
}

class AppsNotifier extends Notifier<AppsState> {
  @override
  AppsState build() => const AppsState();

  /// Reads the installed apps (and their sizes when "Usage access" is on).
  Future<void> load() async {
    if (state.entries.isEmpty) state = const AppsState(loading: true);
    final apps = await NativeBridge.instance.listApps(includeSystem: true);
    final usage = await NativeBridge.instance.hasUsageAccess();
    final stats = usage ? await NativeBridge.instance.appStats() : const <String, AppStats>{};
    state = AppsState(
      entries: [for (final a in apps) AppEntry(a, stats[a.pkg])],
      usageAccess: usage,
      loading: false,
    );
  }

  /// Measures sizes again (after a cache clean-up) without re-reading the app list.
  Future<void> refreshStats() async {
    if (state.entries.isEmpty) return load();
    final usage = await NativeBridge.instance.hasUsageAccess();
    final stats = usage ? await NativeBridge.instance.appStats() : const <String, AppStats>{};
    state = AppsState(
      entries: [for (final e in state.entries) AppEntry(e.app, stats[e.app.pkg])],
      usageAccess: usage,
      loading: false,
    );
  }
}

final appsProvider = NotifierProvider<AppsNotifier, AppsState>(AppsNotifier.new);

/// Deletes Fyleon's own cache folder content. Returns the bytes that were freed.
Future<int> clearOwnCache() async {
  var freed = 0;
  try {
    final dir = await getTemporaryDirectory();
    if (!dir.existsSync()) return 0;
    for (final e in dir.listSync(followLinks: false)) {
      try {
        if (e is File) {
          freed += e.lengthSync();
          e.deleteSync();
        } else if (e is Directory) {
          for (final f in e.listSync(recursive: true, followLinks: false)) {
            if (f is File) freed += f.lengthSync();
          }
          e.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  } catch (_) {}
  PaintingBinding.instance.imageCache.clear();
  return freed;
}

final Map<String, Uint8List?> _iconCache = {};

/// Round-cornered app icon (loaded from the system on demand, cached in memory).
class AppIcon extends StatefulWidget {
  const AppIcon({super.key, required this.pkg, this.size = 44});

  final String pkg;
  final double size;

  @override
  State<AppIcon> createState() => _AppIconState();
}

class _AppIconState extends State<AppIcon> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AppIcon old) {
    super.didUpdateWidget(old);
    if (old.pkg != widget.pkg) _load();
  }

  Future<void> _load() async {
    if (_iconCache.containsKey(widget.pkg)) {
      _bytes = _iconCache[widget.pkg];
      return;
    }
    final b = await NativeBridge.instance.appIcon(widget.pkg, size: 96);
    _iconCache[widget.pkg] = b;
    if (mounted) setState(() => _bytes = b);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = _bytes;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * 0.24),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: b == null
            ? ColoredBox(color: scheme.surfaceContainerHighest, child: Icon(Icons.android_rounded, color: scheme.onSurfaceVariant, size: widget.size * 0.55))
            : Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}
