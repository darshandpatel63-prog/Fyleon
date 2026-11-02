import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../ads/banner_ad_widget.dart';
import '../../settings/settings_screen.dart';
import '../application/browse_controller.dart';
import '../application/files_providers.dart';
import '../domain/files_logic.dart';
import 'browse_view.dart';
import 'file_actions.dart';
import 'recent_view.dart';
import 'sort_filter_widgets.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;
  bool _searching = false;
  final _searchController = TextEditingController();

  bool get _hasBrowse => ref.read(appConfigProvider).allFilesAccess;
  int get _settingsIndex => _hasBrowse ? 2 : 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    if (_hasBrowse && _tab == 1 && ref.read(browsePathProvider.notifier).up()) return;
    setState(() => _tab = 0);
  }

  @override
  Widget build(BuildContext context) {
    final hasBrowse = _hasBrowse;
    final browsePath = ref.watch(browsePathProvider);
    final mode = ref.watch(viewModeProvider);
    final scheme = Theme.of(context).colorScheme;

    final canExit = _tab == 0 && !_searching;

    return PopScope(
      canPop: canExit,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: _tab == _settingsIndex
            ? null
            : AppBar(
                title: _searching
                    ? TextField(
                        controller: _searchController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search files',
                          border: InputBorder.none,
                        ),
                        onChanged: (v) => ref.read(searchQueryProvider.notifier).set(v),
                      )
                    : ShaderMask(
                        shaderCallback: (rect) => LinearGradient(
                          colors: [scheme.primary, scheme.tertiary],
                        ).createShader(rect),
                        child: const Text(
                          AppConstants.appName,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.white),
                        ),
                      ),
                leading: _searching
                    ? IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: _stopSearch)
                    : null,
                actions: [
                  if (!_searching)
                    IconButton(
                      tooltip: 'Search',
                      icon: const Icon(Icons.search_rounded),
                      onPressed: () => setState(() => _searching = true),
                    ),
                  IconButton(
                    tooltip: mode == ViewMode.list ? 'Grid view' : 'List view',
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Icon(
                        mode == ViewMode.list ? Icons.grid_view_rounded : Icons.view_list_rounded,
                        key: ValueKey(mode),
                      ),
                    ),
                    onPressed: () => ref.read(viewModeProvider.notifier).toggle(),
                  ),
                  IconButton(
                    tooltip: 'Sort',
                    icon: const Icon(Icons.sort_rounded),
                    onPressed: () => showSortSheet(context, ref),
                  ),
                ],
              ),
        body: IndexedStack(
          index: _tab,
          children: [
            const RecentView(),
            if (hasBrowse) const BrowseView(),
            const SettingsScreen(),
          ],
        ),
        floatingActionButton: (_tab == 0 || (hasBrowse && _tab == 1 && browsePath == null))
            ? FloatingActionButton.extended(
                onPressed: () => pickAndOpenFile(context, ref),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Open file'),
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
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  selectedIcon: Icon(Icons.history_toggle_off_rounded),
                  label: 'Files',
                ),
                if (hasBrowse)
                  const NavigationDestination(
                    icon: Icon(Icons.folder_outlined),
                    selectedIcon: Icon(Icons.folder_rounded),
                    label: 'Browse',
                  ),
                const NavigationDestination(
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
