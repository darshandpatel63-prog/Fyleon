import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../shared/widgets/empty_state.dart';
import '../application/browse_controller.dart';
import '../application/files_providers.dart';
import '../domain/file_item.dart';
import '../domain/files_logic.dart';
import 'file_actions.dart';
import 'file_collection_view.dart';
import 'file_manager_actions.dart';
import 'files_home.dart';
import 'sort_filter_widgets.dart';

/// "Files" tab: a real file manager (needs the optional "all files access").
class BrowseView extends ConsumerStatefulWidget {
  const BrowseView({super.key});

  @override
  ConsumerState<BrowseView> createState() => _BrowseViewState();
}

class _BrowseViewState extends ConsumerState<BrowseView> with WidgetsBindingObserver {
  bool? _access;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await hasAllFilesAccess();
    if (mounted) setState(() => _access = ok);
  }

  Future<void> _request() async {
    final ok = await requestAllFilesAccess();
    if (mounted) setState(() => _access = ok);
  }

  @override
  Widget build(BuildContext context) {
    final access = _access;
    if (access == null) return const Center(child: CircularProgressIndicator());
    if (!access) return _permissionCard(context);
    final path = ref.watch(browsePathProvider);
    if (path == null) return const FilesHome();
    return _folder(context, path);
  }

  Widget _permissionCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.6), shape: BoxShape.circle),
              child: Icon(Icons.folder_open_rounded, size: 46, color: scheme.primary),
            ),
            const SizedBox(height: 20),
            Text('See and manage all your files',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'Allow "all files access" to browse every folder, create files and folders, '
              'and write code. This is optional. Your files never leave your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _request,
              icon: const Icon(Icons.lock_open_rounded),
              label: const Text('Allow access'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => pickAndOpenFile(context, ref),
              child: const Text('Not now - pick one file instead'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folder(BuildContext context, String path) {
    final listing = ref.watch(directoryListingProvider(path));
    final sort = ref.watch(sortProvider);
    final filter = ref.watch(kindFilterProvider);
    final query = ref.watch(searchQueryProvider);
    final opened = ref.watch(openedMapProvider);
    final clip = ref.watch(clipboardProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        ListTile(
          dense: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => ref.read(browsePathProvider.notifier).up(),
          ),
          title: Text(p.basename(path), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(path, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant)),
          trailing: clip == null
              ? null
              : FilledButton.tonalIcon(
                  onPressed: () => pasteInto(context, ref, path),
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: Text(clip.cut ? 'Move here' : 'Paste'),
                ),
        ),
        const FilterChipsRow(),
        Expanded(
          child: listing.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => const EmptyState(icon: Icons.error_outline_rounded, title: 'Cannot read this folder'),
            data: (items) {
              final folders = items.where((i) => i.isDir).toList()
                ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
              final files = applySortFilter(
                items.where((i) => !i.isDir).toList(),
                sort: sort,
                filter: filter,
                query: query,
                opened: opened,
              );
              final shownFolders = query.isEmpty
                  ? folders
                  : folders.where((f) => f.name.toLowerCase().contains(query.toLowerCase())).toList();
              if (shownFolders.isEmpty && files.isEmpty) {
                return EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'This folder is empty',
                  message: 'Tap + to create a file, folder or web project.',
                  actionLabel: 'Create',
                  onAction: () => showCreateSheet(context, ref, path),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(directoryListingProvider(path)),
                child: FileCollectionView(
                  folders: shownFolders,
                  files: files,
                  onOpenFile: (FileItem f) => openFromBrowse(context, ref, f),
                  onOpenFolder: (FileItem d) => ref.read(browsePathProvider.notifier).open(d.path),
                  onLongPressFile: (FileItem f) => showItemMenu(context, ref, f, path),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
