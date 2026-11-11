import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../shared/widgets/empty_state.dart';
import '../application/collections_providers.dart';
import '../application/files_providers.dart';
import '../domain/files_logic.dart';
import '../domain/file_kind.dart';
import 'file_collection_view.dart';
import 'file_manager_actions.dart';
import 'sort_filter_widgets.dart';

/// "See all" of the Recent row on the Files home: the newest pictures, videos, audio and documents.
class RecentAllScreen extends ConsumerStatefulWidget {
  const RecentAllScreen({super.key});

  @override
  ConsumerState<RecentAllScreen> createState() => _RecentAllScreenState();
}

class _RecentAllScreenState extends ConsumerState<RecentAllScreen> {
  final Set<String> _gone = {};
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(storageScanProvider);
    final sort = ref.watch(sortProvider);
    final mode = ref.watch(viewModeProvider);
    final opened = ref.watch(openedMapProvider);
    // the default sort of this screen is "newest first" unless the owner picked another one
    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search', border: InputBorder.none),
                onChanged: (_) => setState(() {}),
              )
            : const Text('Recent'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search.clear();
            }),
          ),
          IconButton(
            icon: Icon(mode == ViewMode.list ? Icons.grid_view_rounded : Icons.view_list_rounded),
            onPressed: () => ref.read(viewModeProvider.notifier).toggle(),
          ),
          IconButton(icon: const Icon(Icons.sort_rounded), onPressed: () => showSortSheet(context, ref)),
        ],
      ),
      body: scan.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => const EmptyState(icon: Icons.error_outline_rounded, title: 'Could not scan the storage'),
        data: (r) {
          final all = (r?.recentAll ?? const []).where((f) => !_gone.contains(f.path)).toList();
          final files = applySortFilter(all, sort: sort, filter: KindFilter.all, query: _search.text, opened: opened);
          if (files.isEmpty) {
            return const EmptyState(icon: Icons.history_rounded, title: 'Nothing here yet', message: 'New pictures, videos, audio and documents appear here.');
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(storageScanProvider);
              await ref.read(storageScanProvider.future);
            },
            child: FileCollectionView(
              files: files,
              onOpenFile: (f) => openFromBrowse(context, ref, f),
              onLongPressFile: (f) => showItemMenu(context, ref, f, p.dirname(f.path), onGone: (path) => setState(() => _gone.add(path))),
            ),
          );
        },
      ),
    );
  }
}
