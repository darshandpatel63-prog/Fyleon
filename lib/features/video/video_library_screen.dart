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
import '../dash/dash_screens.dart';
import '../files/application/collections_providers.dart';
import '../files/application/files_providers.dart';
import '../files/data/trash_service.dart';
import '../files/domain/file_category.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import '../files/domain/files_logic.dart';
import '../files/presentation/file_collection_view.dart';
import '../files/presentation/file_manager_actions.dart';
import '../files/presentation/sort_filter_widgets.dart';
import 'video_models.dart';
import 'video_prefs.dart';
import 'video_settings_screen.dart';
import 'video_thumbs.dart';

const _largeVideoBytes = 500 * 1024 * 1024;

/// A folder that contains videos (for the Folders tab).
class VideoFolder {
  const VideoFolder(this.path, this.count, this.bytes);

  final String path;
  final int count;
  final int bytes;
}

/// Pure grouping (unit tested): videos -> folders, biggest folder first.
List<VideoFolder> groupVideoFolders(Iterable<FileItem> videos) {
  final count = <String, int>{};
  final bytes = <String, int>{};
  for (final v in videos) {
    final d = p.dirname(v.path);
    count[d] = (count[d] ?? 0) + 1;
    bytes[d] = (bytes[d] ?? 0) + v.size;
  }
  final out = [for (final d in count.keys) VideoFolder(d, count[d]!, bytes[d]!)];
  out.sort((a, b) {
    final c = b.count.compareTo(a.count);
    return c != 0 ? c : p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
  });
  return out;
}

/// Videos of the phone: All, Folders, Recently played, Favorites.
class VideoLibraryScreen extends ConsumerStatefulWidget {
  const VideoLibraryScreen({super.key});

  @override
  ConsumerState<VideoLibraryScreen> createState() => _VideoLibraryScreenState();
}

class _VideoLibraryScreenState extends ConsumerState<VideoLibraryScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this)..addListener(() => setState(() {}));
  final _search = TextEditingController();
  bool _searching = false;
  bool _large = false;
  String? _folder;
  final Set<String> _selected = {};
  final Set<String> _gone = {};

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  void _toggle(String path) => setState(() {
        if (!_selected.add(path)) _selected.remove(path);
      });

  // ------------------------------------------------------------------ selection actions

  Future<void> _favorite(List<FileItem> all) async {
    final favs = ref.read(favoritesProvider);
    final chosen = all.where((f) => _selected.contains(f.path)).toList();
    final allFav = chosen.isNotEmpty && chosen.every((f) => favs.contains(f.path));
    for (final f in chosen) {
      final isFav = favs.contains(f.path);
      if (allFav == isFav) await ref.read(favoritesProvider.notifier).toggle(f.path);
    }
    _toast(allFav ? 'Removed from Favorites' : 'Added to Favorites');
    setState(_selected.clear);
  }

  Future<void> _delete() async {
    final paths = _selected.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline_rounded),
        title: Text('Move ${paths.length} video${paths.length == 1 ? '' : 's'} to Trash?'),
        content: const Text('You can restore them from the Trash within 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move to Trash')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    var moved = 0;
    for (final path in paths) {
      try {
        await moveToTrash(path);
        _gone.add(path);
        moved++;
      } catch (_) {}
    }
    ref.invalidate(storageScanProvider);
    if (!mounted) return;
    setState(_selected.clear);
    _toast(moved == paths.length ? '$moved moved to Trash' : '$moved of ${paths.length} moved to Trash');
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(storageScanProvider);
    final sort = ref.watch(sortProvider);
    final opened = ref.watch(openedMapProvider);
    final mode = ref.watch(viewModeProvider);
    final history = ref.watch(videoHistoryProvider);
    final favs = ref.watch(favoritesProvider);
    final scheme = Theme.of(context).colorScheme;
    final selecting = _selected.isNotEmpty;

    final all = (scan.valueOrNull?.byCategory[FileCategory.videos] ?? const <FileItem>[]).where((f) => !_gone.contains(f.path)).toList();
    final byPath = {for (final f in all) f.path: f};
    final query = _search.text;

    bool keep(FileItem f) => (!_large || f.size >= _largeVideoBytes) && (_folder == null || p.dirname(f.path) == _folder);

    final allList = applySortFilter(all.where(keep).toList(), sort: sort, filter: KindFilter.all, query: query, opened: opened);

    final recentEntries = history.entries.toList()..sort((a, b) => b.value.lastPlayed.compareTo(a.value.lastPlayed));
    final recentList = <FileItem>[];
    for (final e in recentEntries) {
      final f = byPath[e.key];
      if (f != null && (query.isEmpty || f.name.toLowerCase().contains(query.trim().toLowerCase()))) recentList.add(f);
    }

    final favList = applySortFilter(all.where((f) => favs.contains(f.path)).toList(), sort: sort, filter: KindFilter.all, query: query, opened: opened);
    final folders = groupVideoFolders(all).where((f) => query.isEmpty || p.basename(f.path).toLowerCase().contains(query.trim().toLowerCase())).toList();

    return PopScope(
      canPop: !selecting,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) setState(_selected.clear);
      },
      child: Scaffold(
        appBar: selecting
            ? AppBar(
                leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(_selected.clear)),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    tooltip: 'Select all',
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: () => setState(() => _selected.addAll((_tabs.index == 3 ? favList : (_tabs.index == 2 ? recentList : allList)).map((f) => f.path))),
                  ),
                ],
              )
            : AppBar(
                title: _searching
                    ? TextField(
                        controller: _search,
                        autofocus: true,
                        decoration: const InputDecoration(hintText: 'Search videos', border: InputBorder.none),
                        onChanged: (_) => setState(() {}),
                      )
                    : const Text('Videos'),
                actions: [
                  IconButton(
                    icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _search.clear();
                    }),
                  ),
                  IconButton(
                    tooltip: mode == ViewMode.list ? 'Grid' : 'List',
                    icon: Icon(mode == ViewMode.list ? Icons.grid_view_rounded : Icons.view_list_rounded),
                    onPressed: () => ref.read(viewModeProvider.notifier).toggle(),
                  ),
                  IconButton(tooltip: 'Sort', icon: const Icon(Icons.sort_rounded), onPressed: () => showSortSheet(context, ref)),
                  IconButton(
                    tooltip: 'Player settings',
                    icon: const Icon(Icons.settings_rounded),
                    onPressed: () => Navigator.of(context).push(fadeSlideRoute(const VideoSettingsScreen())),
                  ),
                ],
                bottom: TabBar(
                  controller: _tabs,
                  tabs: const [Tab(text: 'All'), Tab(text: 'Folders'), Tab(text: 'Recent'), Tab(text: 'Favorites')],
                ),
              ),
        body: scan.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, s) => const EmptyState(icon: Icons.error_outline_rounded, title: 'Could not scan the storage'),
          data: (_) => Column(
            children: [
              if (_tabs.index == 0)
                SizedBox(
                  height: 46,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      FilterChip(
                        avatar: const Icon(Icons.data_usage_rounded, size: 18),
                        label: const Text('Large (500 MB+)'),
                        selected: _large,
                        onSelected: (v) => setState(() => _large = v),
                      ),
                      if (_folder != null) ...[
                        const SizedBox(width: 8),
                        InputChip(
                          avatar: const Icon(Icons.folder_rounded, size: 18),
                          label: Text(p.basename(_folder!)),
                          onDeleted: () => setState(() => _folder = null),
                        ),
                      ],
                    ],
                  ),
                ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [
                    _videoList(allList, mode, empty: 'No videos found', hint: 'Videos on this phone appear here.'),
                    _folderList(folders),
                    _videoList(recentList, mode, empty: 'Nothing played yet', hint: 'Videos you watch show up here.', progress: true),
                    _videoList(favList, mode, empty: 'No favorite videos', hint: 'Long-press a video and tap the heart.'),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selecting)
                Material(
                  color: scheme.surfaceContainerHigh,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      IconButton(tooltip: 'Favorite', icon: const Icon(Icons.favorite_border_rounded), onPressed: () => _favorite(all)),
                      IconButton(
                        tooltip: 'Share',
                        icon: const Icon(Icons.share_rounded),
                        onPressed: () async {
                          final ok = await NativeBridge.instance.shareFiles(_selected.toList());
                          if (!ok) _toast('Sharing is not available on this device yet.');
                        },
                      ),
                      IconButton(
                        tooltip: 'Send with Dash',
                        icon: const Icon(Icons.bolt_rounded),
                        onPressed: () {
                          final paths = _selected.toList();
                          setState(_selected.clear);
                          sendWithDash(context, paths);
                        },
                      ),
                      if (_tabs.index == 2)
                        IconButton(
                          tooltip: 'Remove from history',
                          icon: const Icon(Icons.history_toggle_off_rounded),
                          onPressed: () async {
                            for (final path in _selected.toList()) {
                              await ref.read(videoHistoryProvider.notifier).remove(path);
                            }
                            if (mounted) setState(_selected.clear);
                          },
                        ),
                      IconButton(tooltip: 'Move to Trash', icon: Icon(Icons.delete_outline_rounded, color: scheme.error), onPressed: _delete),
                    ],
                  ),
                ),
              const BannerAdWidget(),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ lists

  Widget _videoList(List<FileItem> files, ViewMode mode, {required String empty, required String hint, bool progress = false}) {
    final favs = ref.watch(favoritesProvider);
    if (files.isEmpty) return EmptyState(icon: Icons.movie_rounded, title: empty, message: hint);
    final history = ref.watch(videoHistoryProvider);
    Future<void> refresh() async {
      ref.invalidate(storageScanProvider);
      await ref.read(storageScanProvider.future);
    }

    if (mode == ViewMode.grid) {
      return RefreshIndicator(
        onRefresh: refresh,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.95),
          itemCount: files.length,
          itemBuilder: (context, i) => _gridTile(files[i], history),
        ),
      );
    }

    final remote = ref.watch(remoteSettingsProvider);
    final adsOn = adsSupported && remote.nativeEnabled;
    final slots = AdSlots(files.length, every: remote.nativeEveryNItems, max: adsOn ? remote.nativeMaxPerList : 0);
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: slots.total,
        itemBuilder: (context, i) {
          if (slots.isAd(i)) return const NativeAdTile();
          return _listTile(files[slots.itemIndex(i)], history, favs, i);
        },
      ),
    );
  }

  double? _progressOf(FileItem f, Map<String, VideoRecord> history) {
    final r = history[f.path];
    if (r == null || r.durationMs <= 0) return null;
    final v = r.progress;
    return v > 0.02 && v < 0.98 ? v : null;
  }

  Widget _listTile(FileItem f, Map<String, VideoRecord> history, Set<String> favs, int index) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected.contains(f.path);
    final progress = _progressOf(f, history);
    final favorite = favs.contains(f.path);
    return FadeSlideIn(
      index: index,
      child: Material(
        color: selected ? scheme.primaryContainer.withValues(alpha: 0.55) : Colors.transparent,
        child: InkWell(
          onTap: () => _selected.isNotEmpty ? _toggle(f.path) : openFromBrowse(context, ref, f),
          onLongPress: () => _toggle(f.path),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 118,
                  height: 68,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoThumb(item: f, radius: 12),
                      Positioned(right: 4, bottom: 4, child: _DurationBadge(path: f.path)),
                      if (progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                            child: LinearProgressIndicator(value: progress, minHeight: 4),
                          ),
                        ),
                      if (selected)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: CircleAvatar(radius: 11, backgroundColor: scheme.primary, child: Icon(Icons.check_rounded, size: 15, color: scheme.onPrimary)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      const SizedBox(height: 3),
                      _MetaLine(item: f),
                    ],
                  ),
                ),
                if (favorite) Icon(Icons.favorite_rounded, size: 16, color: scheme.error),
                if (_selected.isEmpty)
                  IconButton(
                    icon: const Icon(Icons.more_vert_rounded),
                    onPressed: () => showItemMenu(context, ref, f, p.dirname(f.path), onGone: (path) => setState(() => _gone.add(path))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gridTile(FileItem f, Map<String, VideoRecord> history) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected.contains(f.path);
    final progress = _progressOf(f, history);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _selected.isNotEmpty ? _toggle(f.path) : openFromBrowse(context, ref, f),
      onLongPress: () => _toggle(f.path),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: selected ? Border.all(color: scheme.primary, width: 2.5) : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoThumb(item: f, radius: 14),
                  Positioned(right: 6, bottom: 6, child: _DurationBadge(path: f.path)),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ClipRRect(borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)), child: LinearProgressIndicator(value: progress, minHeight: 4)),
                    ),
                  if (selected) Positioned(left: 6, top: 6, child: CircleAvatar(radius: 12, backgroundColor: scheme.primary, child: Icon(Icons.check_rounded, size: 16, color: scheme.onPrimary))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
              child: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
              child: Text(formatSize(f.size), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderList(List<VideoFolder> folders) {
    if (folders.isEmpty) return const EmptyState(icon: Icons.folder_open_rounded, title: 'No video folders', message: 'Folders with videos appear here.');
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: folders.length,
      itemBuilder: (context, i) {
        final f = folders[i];
        return ListTile(
          leading: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.folder_rounded, color: scheme.onPrimaryContainer),
          ),
          title: Text(p.basename(f.path), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${f.count} video${f.count == 1 ? '' : 's'}  -  ${formatSize(f.bytes)}', maxLines: 1),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            setState(() => _folder = f.path);
            _tabs.animateTo(0);
          },
        );
      },
    );
  }
}

class _DurationBadge extends StatelessWidget {
  const _DurationBadge({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VideoInfo?>(
      future: VideoInfoCache.instance.info(path),
      builder: (context, snap) {
        final i = snap.data;
        if (i == null || i.durationMs <= 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.72), borderRadius: BorderRadius.circular(6)),
          child: Text(formatClock(i.duration), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
        );
      },
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.item});

  final FileItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<VideoInfo?>(
      future: VideoInfoCache.instance.info(item.path),
      builder: (context, snap) {
        final i = snap.data;
        final parts = <String>[formatSize(item.size)];
        if (i != null && i.width > 0) {
          final h = i.rotation == 90 || i.rotation == 270 ? i.width : i.height;
          parts.add('${h}p');
        }
        return Text(parts.join('  -  '), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5));
      },
    );
  }
}
