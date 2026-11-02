import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/empty_state.dart';
import '../application/files_providers.dart';
import 'file_actions.dart';
import 'file_collection_view.dart';
import 'sort_filter_widgets.dart';
import '../domain/files_logic.dart';

/// "Files" tab: everything the user opened with Fyleon.
class RecentView extends ConsumerWidget {
  const RecentView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recents = ref.watch(recentsProvider);
    final sort = ref.watch(sortProvider);
    final filter = ref.watch(kindFilterProvider);
    final query = ref.watch(searchQueryProvider);
    final opened = ref.watch(openedMapProvider);

    final files = applySortFilter(
      recents.map((r) => r.item).toList(),
      sort: sort,
      filter: filter,
      query: query,
      opened: opened,
    );

    return Column(
      children: [
        const FilterChipsRow(),
        Expanded(
          child: recents.isEmpty
              ? EmptyState(
                  icon: Icons.folder_open_rounded,
                  title: 'Open anything',
                  message: 'PDF, EPUB, code, text, images, ZIP and Office files. '
                      'Tap the button to pick a file. Files you open appear here.',
                  actionLabel: 'Open a file',
                  onAction: () => pickAndOpenFile(context, ref),
                )
              : files.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No files match',
                      message: 'Try another filter or search.',
                    )
                  : FileCollectionView(
                      files: files,
                      onOpenFile: (f) => openFile(context, ref, f),
                      onLongPressFile: (f) => _confirmRemove(context, ref, f.path, f.name),
                    ),
        ),
      ],
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref, String path, String name) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              leading: const Icon(Icons.history_toggle_off_rounded),
              title: const Text('Remove from recent'),
              subtitle: const Text('The file itself is not deleted.'),
              onTap: () {
                ref.read(recentsProvider.notifier).remove(path);
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
