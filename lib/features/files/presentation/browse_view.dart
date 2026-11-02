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
import 'sort_filter_widgets.dart';

/// "Browse" tab (only when features.allFilesAccess = true in the config).
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
    if (!access) {
      return EmptyState(
        icon: Icons.lock_open_rounded,
        title: 'Allow access to your files',
        message: 'Fyleon needs permission to show the files on your device. '
            'Your files never leave your phone.',
        actionLabel: 'Allow access',
        onAction: _request,
      );
    }
    final path = ref.watch(browsePathProvider);
    if (path == null) return _roots(context);
    return _folder(context, path);
  }

  Widget _roots(BuildContext context) {
    final roots = storageRoots();
    if (roots.isEmpty) {
      return const EmptyState(
        icon: Icons.folder_off_rounded,
        title: 'No storage found',
        message: 'Use "Open file" to pick a file instead.',
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: roots.length,
      itemBuilder: (context, i) {
        final r = roots[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: scheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ListTile(
            leading: Icon(r.icon, color: scheme.primary),
            title: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(r.path, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => ref.read(browsePathProvider.notifier).open(r.path),
          ),
        );
      },
    );
  }

  Widget _folder(BuildContext context, String path) {
    final listing = ref.watch(directoryListingProvider(path));
    final sort = ref.watch(sortProvider);
    final filter = ref.watch(kindFilterProvider);
    final query = ref.watch(searchQueryProvider);
    final opened = ref.watch(openedMapProvider);
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
        ),
        const FilterChipsRow(),
        Expanded(
          child: listing.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, s) => const EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Cannot read this folder',
            ),
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
                return const EmptyState(icon: Icons.folder_open_rounded, title: 'Nothing here');
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(directoryListingProvider(path)),
                child: FileCollectionView(
                  folders: shownFolders,
                  files: files,
                  onOpenFile: (FileItem f) => openFile(context, ref, f),
                  onOpenFolder: (FileItem d) => ref.read(browsePathProvider.notifier).open(d.path),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
