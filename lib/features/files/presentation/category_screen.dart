import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../shared/widgets/empty_state.dart';
import '../application/collections_providers.dart';
import '../application/files_providers.dart';
import '../domain/file_category.dart';
import '../domain/file_kind.dart';
import '../domain/files_logic.dart';
import 'file_collection_view.dart';
import 'file_manager_actions.dart';
import 'sort_filter_widgets.dart';

/// All files of one kind (Images, Videos, Audio, Documents, APKs & archives).
class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.category});

  final FileCategory category;

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
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

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search', border: InputBorder.none),
                onChanged: (_) => setState(() {}),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Hero(tag: 'cat-${widget.category.name}', child: Icon(widget.category.icon, color: widget.category.color)),
                  const SizedBox(width: 10),
                  Text(widget.category.label),
                ],
              ),
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
          final all = (r?.byCategory[widget.category] ?? const []).where((f) => !_gone.contains(f.path)).toList();
          final files = applySortFilter(all, sort: sort, filter: KindFilter.all, query: _search.text, opened: opened);
          if (files.isEmpty) {
            return EmptyState(icon: widget.category.icon, title: 'Nothing here', message: 'No ${widget.category.label.toLowerCase()} found on this device.');
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
