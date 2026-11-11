import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/native/native_bridge.dart';
import '../../core/remote/remote_settings.dart';
import '../../core/utils/format.dart';
import '../../core/utils/platform_utils.dart';
import '../../shared/widgets/animations.dart';
import '../../shared/widgets/empty_state.dart';
import '../ads/banner_ad_widget.dart';
import '../ads/native_ad_tile.dart';
import '../files/application/browse_controller.dart';
import '../files/application/collections_providers.dart';
import '../files/application/files_providers.dart';
import '../files/data/file_ops.dart';
import '../files/domain/file_category.dart';
import '../files/domain/file_kind.dart';
import '../files/domain/files_logic.dart';
import '../files/presentation/file_collection_view.dart';
import '../files/presentation/file_manager_actions.dart';
import 'app_queue_screen.dart';
import 'apps_model.dart';
import 'apps_providers.dart';

/// All installed apps (like a "manage apps" page): sizes, last used, cache, uninstall.
/// Own design; works with and without "Usage access" (without it only the APK size is known).
class AppsScreen extends ConsumerStatefulWidget {
  const AppsScreen({super.key});

  @override
  ConsumerState<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends ConsumerState<AppsScreen> with WidgetsBindingObserver {
  AppTab _tab = AppTab.installed;
  final Set<AppChipFilter> _chips = {};
  AppSort _sort = AppSort.size;
  String _query = '';
  bool _searching = false;
  final _search = TextEditingController();
  final Set<String> _selected = {};

  /// true after we sent the owner to an Android settings page (usage access, uninstall dialog)
  bool _externalPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(appsProvider.notifier).load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back from the "Usage access" page or an uninstall dialog -> read everything again
    if (state == AppLifecycleState.resumed && _externalPending) {
      _externalPending = false;
      ref.read(appsProvider.notifier).load();
    }
  }

  Future<void> _openUsage() async {
    _externalPending = true;
    final ok = await NativeBridge.instance.openUsageAccess();
    if (!ok) {
      _externalPending = false;
      _toast('Open Android Settings > Apps > Special access > Usage access and allow Fyleon.');
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  List<AppEntry> _visible(AppsState st) =>
      filterApps(st.entries, tab: _tab, chips: _chips, query: _query, sort: _sort);

  List<AppEntry> _selectedEntries(AppsState st) => st.entries.where((e) => _selected.contains(e.app.pkg)).toList();

  // ------------------------------------------------------------------ cache actions

  Future<void> _cacheMenuAction(String v) async {
    final st = ref.read(appsProvider);
    if (!isAndroid) {
      _toast('This works on Android only.');
      return;
    }
    switch (v) {
      case 'selected':
        final sel = _selectedEntries(st);
        if (sel.isEmpty) {
          _toast('Select some apps first (long-press an app).');
          return;
        }
        await _runQueue(sel, QueueMode.cache);
      case 'user':
        await _runQueue(st.entries.where((e) => !e.app.system).toList(), QueueMode.cache);
      case 'all':
        await _runQueue(st.entries.toList(), QueueMode.cache);
      case 'dialog':
        await _systemClear(st);
      case 'own':
        final freed = await clearOwnCache();
        _toast('Fyleon cache cleared (${formatSize(freed)}).');
    }
  }

  Future<void> _runQueue(List<AppEntry> entries, QueueMode mode) async {
    if (entries.isEmpty) {
      _toast('No apps to clean.');
      return;
    }
    await Navigator.of(context).push(fadeSlideRoute(AppQueueScreen(entries: entries, mode: mode)));
    if (!mounted) return;
    await ref.read(appsProvider.notifier).load();
    if (mounted) setState(_selected.clear);
  }

  /// Android's own "clear all apps' cache" dialog. It needs "All files access" and only removes the
  /// EXTERNAL cache folders of the apps (not their internal cache).
  Future<void> _systemClear(AppsState st) async {
    if (!await hasAllFilesAccess()) {
      final ok = await requestAllFilesAccess();
      if (!ok) {
        _toast('Android needs "All files access" for this dialog.');
        return;
      }
    }
    final before = totalCacheOf(st.entries);
    final r = await NativeBridge.instance.clearAllCacheDialog();
    if (!mounted) return;
    if (r == 'cleared') {
      await ref.read(appsProvider.notifier).refreshStats();
      final after = totalCacheOf(ref.read(appsProvider).entries);
      final freed = before - after;
      _toast(st.usageAccess && freed > 0 ? 'Cache cleared. Freed ${formatSize(freed)}.' : 'Cache cleared.');
    } else if (r == 'unsupported') {
      _toast('This needs Android 11 or newer. Use "Selected apps" or "All my apps" instead.');
    } else if (r != 'cancelled') {
      _toast('Could not open the Android dialog. Use "Selected apps" or "All my apps" instead.');
    }
  }

  Future<void> _uninstallSelected(AppsState st) async {
    final sel = _selectedEntries(st).where((e) => !e.app.system).toList();
    if (sel.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Uninstall ${sel.length} app${sel.length == 1 ? '' : 's'}?'),
        content: const Text('Android will ask you to confirm each app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok == true) await _runQueue(sel, QueueMode.uninstall);
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(appsProvider);
    final scheme = Theme.of(context).colorScheme;
    final selecting = _selected.isNotEmpty;
    final list = _tab == AppTab.apks ? const <AppEntry>[] : _visible(st);
    final selEntries = _selectedEntries(st);

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: selecting ? _selectionBar(st, list, selEntries) : _normalBar(scheme),
        body: Column(
          children: [
            _tabs(scheme),
            if (_tab != AppTab.apks) _chipRow(),
            if (isAndroid && !st.usageAccess && !st.loading && _tab != AppTab.apks) _usageBanner(scheme),
            if (_tab != AppTab.apks) _summary(st, list, scheme),
            Expanded(child: _tab == AppTab.apks ? const _ApkFilesList() : _appList(st, list)),
          ],
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selecting) _selectionActions(st, selEntries, scheme),
              const BannerAdWidget(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _normalBar(ColorScheme scheme) {
    return AppBar(
      title: _searching
          ? TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Search apps', border: InputBorder.none),
              onChanged: (v) => setState(() => _query = v),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Hero(tag: 'cat-apps', child: Icon(Icons.apps_rounded, color: Color(0xFF0F766E))),
                const SizedBox(width: 10),
                const Text('Apps'),
              ],
            ),
      actions: [
        IconButton(
          icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
          onPressed: () => setState(() {
            _searching = !_searching;
            if (!_searching) {
              _search.clear();
              _query = '';
            }
          }),
        ),
        PopupMenuButton<AppSort>(
          tooltip: 'Sort',
          icon: const Icon(Icons.sort_rounded),
          initialValue: _sort,
          onSelected: (s) => setState(() => _sort = s),
          itemBuilder: (context) => [for (final s in AppSort.values) PopupMenuItem(value: s, child: Text(s.label))],
        ),
      ],
    );
  }

  PreferredSizeWidget _selectionBar(AppsState st, List<AppEntry> list, List<AppEntry> sel) {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_selected.clear)),
      title: Text('${sel.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Select all',
          icon: const Icon(Icons.select_all_rounded),
          onPressed: () => setState(() => _selected.addAll(list.map((e) => e.app.pkg))),
        ),
      ],
    );
  }

  Widget _selectionActions(AppsState st, List<AppEntry> sel, ColorScheme scheme) {
    final cache = totalCacheOf(sel);
    final size = totalSizeOf(sel);
    final canUninstall = sel.any((e) => !e.app.system);
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(st.usageAccess ? 'Cache: ${formatSize(cache)}' : 'Cache size: allow Usage access', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('Total size: ${formatSize(size)}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: () => _cacheMenuAction('selected'),
              icon: const Icon(Icons.cleaning_services_rounded, size: 18),
              label: const Text('Clear cache'),
            ),
            if (canUninstall)
              IconButton(
                tooltip: 'Uninstall',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => _uninstallSelected(st),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabs(ColorScheme scheme) {
    const labels = {AppTab.installed: 'Installed apps', AppTab.system: 'System apps', AppTab.apks: 'Install files'};
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(26)),
        child: Row(
          children: [
            for (final t in AppTab.values)
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _tab = t;
                    _selected.clear();
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: _tab == t ? LinearGradient(colors: [scheme.primaryContainer, scheme.tertiaryContainer]) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[t]!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: _tab == t ? FontWeight.w800 : FontWeight.w500,
                        color: _tab == t ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chipRow() {
    const items = [
      (AppChipFilter.large, Icons.data_usage_rounded, 'Large apps'),
      (AppChipFilter.unused, Icons.hourglass_empty_rounded, 'Unused apps'),
      (AppChipFilter.games, Icons.sports_esports_rounded, 'Games'),
    ];
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          for (final it in items)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                avatar: Icon(it.$2, size: 18),
                label: Text(it.$3),
                selected: _chips.contains(it.$1),
                onSelected: (on) => setState(() => on ? _chips.add(it.$1) : _chips.remove(it.$1)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _usageBanner(ColorScheme scheme) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(color: scheme.tertiaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(18)),
      child: Row(
        children: [
          const Icon(Icons.insights_rounded),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Allow "Usage access" to see real app sizes, cache sizes and when an app was last used.', style: TextStyle(fontSize: 12.5)),
          ),
          TextButton(onPressed: _openUsage, child: const Text('Allow')),
        ],
      ),
    );
  }

  Widget _summary(AppsState st, List<AppEntry> list, ColorScheme scheme) {
    final cache = totalCacheOf(list);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 10, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              st.loading
                  ? 'Reading apps...'
                  : '${list.length} apps - ${formatSize(totalSizeOf(list))}${st.usageAccess ? ' - cache ${formatSize(cache)}' : ''}',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Clear cache',
            onSelected: _cacheMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'selected', child: _MenuRow(Icons.checklist_rounded, 'Selected apps')),
              PopupMenuItem(value: 'user', child: _MenuRow(Icons.apps_rounded, 'All my apps (no system apps)')),
              PopupMenuItem(value: 'all', child: _MenuRow(Icons.phone_android_rounded, 'All apps with system apps')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'dialog', child: _MenuRow(Icons.flash_on_rounded, 'All at once (Android dialog)')),
              PopupMenuItem(value: 'own', child: _MenuRow(Icons.cleaning_services_rounded, 'Fyleon\'s own cache')),
            ],
            child: Chip(
              avatar: const Icon(Icons.cleaning_services_rounded, size: 18),
              label: const Text('Clear cache'),
              backgroundColor: scheme.primaryContainer,
              side: BorderSide.none,
            ),
          ),
        ],
      ),
    );
  }

  Widget _appList(AppsState st, List<AppEntry> list) {
    if (st.loading) return const Center(child: CircularProgressIndicator());
    if (!isAndroid) {
      return const EmptyState(icon: Icons.apps_rounded, title: 'Apps list is for Android', message: 'On this device only Android apps can be listed.');
    }
    if (list.isEmpty) {
      return EmptyState(
        icon: Icons.apps_rounded,
        title: 'No apps here',
        message: _chips.contains(AppChipFilter.unused) && !st.usageAccess
            ? 'Allow "Usage access" so Fyleon can tell which apps you did not use.'
            : 'Try another filter.',
      );
    }
    final remote = ref.watch(remoteSettingsProvider);
    final adsOn = adsSupported && remote.nativeEnabled;
    final slots = AdSlots(list.length, every: remote.nativeEveryNItems, max: adsOn ? remote.nativeMaxPerList : 0);
    return RefreshIndicator(
      onRefresh: () => ref.read(appsProvider.notifier).load(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: slots.total,
        itemBuilder: (context, i) {
          if (slots.isAd(i)) return const NativeAdTile();
          final e = list[slots.itemIndex(i)];
          return _AppTile(
            entry: e,
            index: i,
            usage: st.usageAccess,
            selecting: _selected.isNotEmpty,
            selected: _selected.contains(e.app.pkg),
            onTap: () {
              if (_selected.isNotEmpty) {
                setState(() => _toggle(e.app.pkg));
              } else {
                _showAppSheet(e, st.usageAccess);
              }
            },
            onLongPress: () => setState(() => _toggle(e.app.pkg)),
            onMore: () => _showAppSheet(e, st.usageAccess),
          );
        },
      ),
    );
  }

  void _toggle(String pkg) {
    if (!_selected.add(pkg)) _selected.remove(pkg);
  }

  // ------------------------------------------------------------------ one app

  void _showAppSheet(AppEntry e, bool usage) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: AppIcon(pkg: e.app.pkg, size: 48),
                title: Text(e.app.label, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${e.app.pkg}${e.app.version.isEmpty ? '' : '\nVersion ${e.app.version}'}'),
                isThreeLine: e.app.version.isNotEmpty,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: usage && e.stats != null
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _statChip('App', e.stats!.app, scheme),
                          _statChip('Data', e.stats!.data, scheme),
                          _statChip('Cache', e.stats!.cache, scheme),
                          _statChip('Total', e.stats!.total, scheme),
                        ],
                      )
                    : Text('APK size: ${formatSize(e.app.apkSize)}  (allow Usage access for data + cache sizes)', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
              ),
              if (e.app.launchable)
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Open app'),
                  onTap: () {
                    Navigator.pop(ctx);
                    NativeBridge.instance.launchApp(e.app.pkg);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('App info (Android settings)'),
                subtitle: const Text('Storage > Clear cache / Clear data'),
                onTap: () {
                  Navigator.pop(ctx);
                  NativeBridge.instance.openAppInfo(e.app.pkg);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cleaning_services_rounded),
                title: const Text('Clear cache of this app'),
                subtitle: const Text('Opens its info page; tap Storage > Clear cache'),
                onTap: () {
                  Navigator.pop(ctx);
                  _runQueue([e], QueueMode.cache);
                },
              ),
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: const Text('Save APK backup'),
                subtitle: const Text('Copies the app file to Download/Fyleon/Apps'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveApk(e);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded),
                title: const Text('Share APK'),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareApk(e);
                },
              ),
              if (!e.app.system)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
                  title: Text('Uninstall', style: TextStyle(color: scheme.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _externalPending = true;
                    NativeBridge.instance.uninstallApp(e.app.pkg);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, int bytes, ColorScheme scheme) {
    return Chip(
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
      backgroundColor: scheme.surfaceContainerHighest,
      label: Text('$label ${formatSize(bytes)}', style: const TextStyle(fontSize: 12)),
    );
  }

  Future<void> _saveApk(AppEntry e) async {
    final src = await NativeBridge.instance.extractApk(e.app.pkg);
    if (src == null) {
      _toast('Could not read this app file.');
      return;
    }
    try {
      final roots = storageRoots();
      final base = roots.isEmpty ? p.dirname(src) : p.join(roots.first.path, 'Download');
      final dir = Directory(p.join(base, 'Fyleon', 'Apps'))..createSync(recursive: true);
      final safe = e.app.label.replaceAll(_badNameChars, '_');
      final ver = e.app.version.isEmpty ? '' : '_${e.app.version}';
      final target = uniquePath(dir.path, '$safe$ver.apk');
      await File(src).copy(target);
      _toast('Saved: $target');
    } catch (err) {
      _toast(friendlyError(err).message);
    }
  }

  Future<void> _shareApk(AppEntry e) async {
    final src = await NativeBridge.instance.extractApk(e.app.pkg);
    if (src == null) {
      _toast('Could not read this app file.');
      return;
    }
    // the cache copy is named after the package; give it a readable name for the receiver
    final readable = p.join(p.dirname(src), '${e.app.label.replaceAll(_badNameChars, '_')}.apk');
    try {
      await File(src).copy(readable);
      await NativeBridge.instance.shareFiles([readable]);
    } catch (_) {
      await NativeBridge.instance.shareFiles([src]);
    }
  }
}

final _badNameChars = RegExp(r'[\\/:*?"<>|]');

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(text))]);
}

class _AppTile extends StatelessWidget {
  const _AppTile({
    required this.entry,
    required this.index,
    required this.usage,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  final AppEntry entry;
  final int index;
  final bool usage;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = entry;
    final parts = <String>[formatSize(e.size)];
    if (usage && e.cache > 0) parts.add('cache ${formatSize(e.cache)}');
    final last = e.lastUsed;
    parts.add(last != null ? formatAgo(last) : (usage ? 'not used' : 'updated ${formatAgo(e.app.updated)}'));
    return FadeSlideIn(
      index: index,
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.55) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppIcon(pkg: e.app.pkg, size: 46),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: AnimatedScale(
                        scale: selected ? 1 : 0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutBack,
                        child: CircleAvatar(radius: 10, backgroundColor: scheme.primary, child: Icon(Icons.check_rounded, size: 14, color: scheme.onPrimary)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.app.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(parts.join('  -  '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
                    ],
                  ),
                ),
                if (!selecting) IconButton(icon: const Icon(Icons.more_vert_rounded), onPressed: onMore),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Install files" tab: every .apk found on the storage (tap = Install / scan / browse).
class _ApkFilesList extends ConsumerWidget {
  const _ApkFilesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(storageScanProvider);
    final sort = ref.watch(sortProvider);
    final opened = ref.watch(openedMapProvider);
    return scan.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, s) => const EmptyState(icon: Icons.error_outline_rounded, title: 'Could not scan the storage'),
      data: (r) {
        final apks = (r?.byCategory[FileCategory.packages] ?? const []).where((f) => f.ext == 'apk').toList();
        final files = applySortFilter(apks, sort: sort, filter: KindFilter.all, query: '', opened: opened);
        if (files.isEmpty) {
          return const EmptyState(icon: Icons.android_rounded, title: 'No install files', message: 'No .apk files were found on this device.');
        }
        return FileCollectionView(
          files: files,
          onOpenFile: (f) => openFromBrowse(context, ref, f),
          onLongPressFile: (f) => showItemMenu(context, ref, f, p.dirname(f.path)),
        );
      },
    );
  }
}
