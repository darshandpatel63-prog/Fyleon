import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/native/native_bridge.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../ads/banner_ad_widget.dart';
import '../../settings/settings_screen.dart';
import '../application/browse_controller.dart';
import '../application/collections_providers.dart';
import '../application/files_providers.dart';
import '../domain/file_item.dart';
import '../domain/files_logic.dart';
import 'browse_view.dart';
import 'file_actions.dart';
import 'file_manager_actions.dart';
import 'recent_view.dart';
import 'sort_filter_widgets.dart';

/// Tabs: Files (file manager) - Recent (opened with Fyleon) - Settings.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0; // 0 Files, 1 Recent, 2 Settings
  bool _searching = false;
  final _searchController = TextEditingController();
  StreamSubscription<void>? _incomingSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _incomingSub = NativeBridge.instance.onFilesReady.listen((_) => _checkIncoming());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkIncoming();
      ref.read(trashProvider.notifier).purgeOld();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _incomingSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkIncoming();
  }

  /// Files sent to Fyleon from "Open with", "Share" or "Send to" in other apps.
  Future<void> _checkIncoming() async {
    final paths = await NativeBridge.instance.takeFiles();
    if (paths.isEmpty || !mounted) return;
    final items = paths.map(FileItem.tryFromPath).whereType<FileItem>().where((i) => !i.isDir).toList();
    if (items.isEmpty) return;
    for (final it in items.skip(1)) {
      await ref.read(recentsProvider.notifier).add(it);
    }
    if (!mounted) return;
    await openFile(context, ref, items.first);
  }

  void _stopSearch() {
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).set('');
    setState(() => _searching = false);
  }

  void _onBack() {
    if (_searching) {
      _stopSearch();
      return;
    }
    if (_tab == 0 && ref.read(browsePathProvider.notifier).up()) return;
    setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    final browsePath = ref.watch(browsePathProvider);
    final mode = ref.watch(viewModeProvider);
    final scheme = Theme.of(context).colorScheme;
    final filesEnabled = ref.read(appConfigProvider).allFilesAccess;

    final onFilesRoot = _tab == 0 && browsePath == null;
    final canExit = onFilesRoot && !_searching;
    final showListTools = _tab == 1 || (_tab == 0 && browsePath != null);

    return PopScope(
      canPop: canExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: _tab == 2
            ? null
            : AppBar(
                title: _searching
                    ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'Search files', border: InputBorder.none),
                        onChanged: (v) => ref.read(searchQueryProvider.notifier).set(v),
                      )
                    : ShaderMask(
                        shaderCallback: (rect) => LinearGradient(colors: [scheme.primary, scheme.tertiary]).createShader(rect),
                        child: const Text(
                          AppConstants.appName,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.white),
                        ),
                      ),
                leading: _searching ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _stopSearch) : null,
                actions: showListTools
                    ? [
                        if (!_searching)
                          IconButton(tooltip: 'Search', icon: const Icon(Icons.search_rounded), onPressed: () => setState(() => _searching = true)),
                        IconButton(
                          tooltip: mode == ViewMode.list ? 'Grid view' : 'List view',
                          icon: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(mode == ViewMode.list ? Icons.grid_view_rounded : Icons.view_list_rounded, key: ValueKey(mode)),
                          ),
                          onPressed: () => ref.read(viewModeProvider.notifier).toggle(),
                        ),
                        IconButton(tooltip: 'Sort', icon: const Icon(Icons.sort_rounded), onPressed: () => showSortSheet(context, ref)),
                      ]
                    : [
                        IconButton(
                          tooltip: 'Open a file',
                          icon: const Icon(Icons.file_open_rounded),
                          onPressed: () => pickAndOpenFile(context, ref),
                        ),
                      ],
              ),
        body: IndexedStack(
          index: _tab,
          children: [
            filesEnabled
                ? const BrowseView()
                : EmptyState(
                    icon: Icons.folder_open_rounded,
                    title: 'File manager is turned off',
                    message: 'Pick a file to open it, or turn on "allFilesAccess" in config/fyleon_config.json.',
                    actionLabel: 'Open a file',
                    onAction: () => pickAndOpenFile(context, ref),
                  ),
            const RecentView(),
            const SettingsScreen(),
          ],
        ),
        floatingActionButton: _tab == 1
            ? FloatingActionButton.extended(
                onPressed: () => pickAndOpenFile(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Open file'),
              )
            : (filesEnabled && _tab == 0 && browsePath != null)
                ? FloatingActionButton.extended(
                    onPressed: () => showCreateSheet(context, ref, browsePath),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('New'),
                  )
                : null,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BannerAdWidget(),
            NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                if (_searching) _stopSearch();
                setState(() => _tab = i);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder_rounded),
                  label: 'Files',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  selectedIcon: Icon(Icons.history_toggle_off_rounded),
                  label: 'Recent',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
