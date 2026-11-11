import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/native_bridge.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/bottom_safe.dart';
import 'apps_model.dart';
import 'apps_providers.dart';

enum QueueMode { cache, uninstall }

enum _Status { waiting, active, done, skipped }

/// Android does not let ANY normal app clear another app's cache or uninstall it silently.
/// So Fyleon walks through the chosen apps: it opens each one's Android page, the owner taps
/// "Storage > Clear cache" (or confirms the uninstall) and presses Back, and Fyleon opens the next app by itself.
class AppQueueScreen extends ConsumerStatefulWidget {
  const AppQueueScreen({super.key, required this.entries, required this.mode});

  final List<AppEntry> entries;
  final QueueMode mode;

  @override
  ConsumerState<AppQueueScreen> createState() => _AppQueueScreenState();
}

class _AppQueueScreenState extends ConsumerState<AppQueueScreen> with WidgetsBindingObserver {
  late final List<AppEntry> _items;
  final Map<String, _Status> _status = {};
  int _index = -1;
  bool _running = false;
  bool _finished = false;
  bool _awaitingReturn = false;
  int _freed = 0;

  bool get _cacheMode => widget.mode == QueueMode.cache;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    var list = widget.entries.toList();
    if (_cacheMode) {
      // when sizes are known, apps without cache are skipped and the biggest cache comes first
      if (list.any((e) => e.hasStats)) list = list.where((e) => e.cache > 4096).toList();
      list.sort((a, b) => b.cache.compareTo(a.cache));
    }
    _items = list;
    for (final e in _items) {
      _status[e.app.pkg] = _Status.waiting;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _running && _awaitingReturn) {
      _awaitingReturn = false;
      _afterReturn();
    }
  }

  int get _doneCount => _status.values.where((s) => s == _Status.done || s == _Status.skipped).length;

  Future<void> _start() async {
    setState(() {
      _running = true;
      _finished = false;
    });
    await _next();
  }

  Future<void> _next() async {
    if (!mounted || !_running) return;
    _index++;
    if (_index >= _items.length) {
      await _finish();
      return;
    }
    final e = _items[_index];
    setState(() => _status[e.app.pkg] = _Status.active);
    _awaitingReturn = true;
    final ok = _cacheMode ? await NativeBridge.instance.openAppInfo(e.app.pkg) : await NativeBridge.instance.uninstallApp(e.app.pkg);
    if (!ok && mounted) {
      _awaitingReturn = false;
      setState(() => _status[e.app.pkg] = _Status.skipped);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _next();
    }
  }

  Future<void> _afterReturn() async {
    if (_index < 0 || _index >= _items.length) return;
    final e = _items[_index];
    var result = _Status.skipped;
    if (_cacheMode) {
      final stats = await NativeBridge.instance.appStats(pkgs: [e.app.pkg]);
      final s = stats[e.app.pkg];
      if (s == null) {
        // sizes unknown (no Usage access): we cannot check, so we trust the owner
        result = _Status.done;
      } else if (s.cache < 4096 || s.cache < e.cache * 0.1) {
        result = _Status.done;
        _freed += e.cache - s.cache;
      }
    } else {
      final apps = await NativeBridge.instance.listApps(includeSystem: true);
      result = apps.any((a) => a.pkg == e.app.pkg) ? _Status.skipped : _Status.done;
    }
    if (!mounted) return;
    setState(() => _status[e.app.pkg] = result);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _next();
  }

  Future<void> _skip() async {
    if (_index < 0 || _index >= _items.length) return;
    _awaitingReturn = false;
    setState(() => _status[_items[_index].app.pkg] = _Status.skipped);
    await _next();
  }

  Future<void> _finish() async {
    _running = false;
    _awaitingReturn = false;
    if (mounted) setState(() => _finished = true);
    await ref.read(appsProvider.notifier).load();
  }

  void _stop() {
    _awaitingReturn = false;
    // the app we were waiting for is tried again when the owner presses Continue
    if (_index >= 0 && _index < _items.length && _status[_items[_index].app.pkg] == _Status.active) {
      _status[_items[_index].app.pkg] = _Status.waiting;
      _index--;
    }
    setState(() => _running = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _items.length;
    final progress = total == 0 ? 0.0 : _doneCount / total;
    final title = _cacheMode ? 'Clear cache' : 'Uninstall apps';

    return PopScope(
      canPop: !_running,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _stop();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: BottomSafe(
          child: total == 0
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 64, color: scheme.primary),
                        const SizedBox(height: 12),
                        const Text('Nothing to clear', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        const Text('None of these apps has cache right now.', textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: scheme.tertiaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(18)),
                      child: Text(
                        _cacheMode
                            ? 'Android does not allow any app to clear another app\'s cache silently. '
                                'Fyleon opens each app\'s page: tap Storage, then Clear cache, then press Back. '
                                'The next app opens by itself.'
                            : 'Android asks you to confirm each uninstall. After each one, Fyleon opens the next.',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress, minHeight: 8)),
                          const SizedBox(height: 6),
                          Text(
                            _finished
                                ? 'Finished: $_doneCount of $total${_cacheMode && _freed > 0 ? ' - freed ${formatSize(_freed)}' : ''}'
                                : '$_doneCount of $total${_cacheMode && _freed > 0 ? ' - freed ${formatSize(_freed)}' : ''}',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _items.length,
                        itemBuilder: (context, i) {
                          final e = _items[i];
                          final s = _status[e.app.pkg] ?? _Status.waiting;
                          return ListTile(
                            dense: true,
                            leading: AppIcon(pkg: e.app.pkg, size: 40),
                            title: Text(e.app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(_cacheMode && e.hasStats ? 'Cache ${formatSize(e.cache)}' : formatSize(e.size)),
                            trailing: _statusIcon(s, scheme),
                            selected: s == _Status.active,
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: Row(
                        children: [
                          if (!_running && !_finished)
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _start,
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: Text(_index < 0 ? 'Start' : 'Continue'),
                              ),
                            ),
                          if (_running) ...[
                            Expanded(child: OutlinedButton(onPressed: _skip, child: const Text('Skip this app'))),
                            const SizedBox(width: 10),
                            Expanded(child: FilledButton.tonal(onPressed: _stop, child: const Text('Stop'))),
                          ],
                          if (_finished) Expanded(child: FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _statusIcon(_Status s, ColorScheme scheme) {
    switch (s) {
      case _Status.waiting:
        return Icon(Icons.radio_button_unchecked_rounded, color: scheme.outline);
      case _Status.active:
        return const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5));
      case _Status.done:
        return const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A));
      case _Status.skipped:
        return Icon(Icons.remove_circle_outline_rounded, color: scheme.outline);
    }
  }
}
