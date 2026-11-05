import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../shared/widgets/empty_state.dart';
import '../application/browse_controller.dart';
import '../application/collections_providers.dart';
import '../domain/file_item.dart';
import 'file_collection_view.dart';
import 'file_manager_actions.dart';

/// Starred or Favorites.
class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key, required this.starred});

  final bool starred;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Set<String> paths = starred ? ref.watch(starredProvider) : ref.watch(favoritesProvider);
    final items = paths.map(FileItem.tryFromPath).whereType<FileItem>().toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final folders = items.where((i) => i.isDir).toList();
    final files = items.where((i) => !i.isDir).toList();
    final title = starred ? 'Starred' : 'Favorites';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: items.isEmpty
          ? EmptyState(
              icon: starred ? Icons.star_border_rounded : Icons.favorite_border_rounded,
              title: 'Nothing in $title yet',
              message: 'Long-press any file or folder and choose "Add to $title".',
            )
          : FileCollectionView(
              folders: folders,
              files: files,
              onOpenFile: (f) => openFromBrowse(context, ref, f),
              onOpenFolder: (d) {
                ref.read(browsePathProvider.notifier).open(d.path);
                Navigator.of(context).pop();
              },
              onLongPressFile: (f) => showItemMenu(context, ref, f, p.dirname(f.path)),
            ),
    );
  }
}
