import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/file_widgets.dart';
import '../application/files_providers.dart';
import '../domain/file_item.dart';
import '../domain/files_logic.dart';

/// Shows files either as a list or as a grid (like Google Drive).
/// Folders (if any) are always shown first.
class FileCollectionView extends ConsumerWidget {
  const FileCollectionView({
    super.key,
    required this.files,
    this.folders = const [],
    required this.onOpenFile,
    this.onOpenFolder,
    this.onLongPressFile,
    this.bottomPadding = 96,
  });

  final List<FileItem> files;
  final List<FileItem> folders;
  final void Function(FileItem) onOpenFile;
  final void Function(FileItem)? onOpenFolder;
  final void Function(FileItem)? onLongPressFile;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(viewModeProvider);
    final all = [...folders, ...files];

    void tap(FileItem it) {
      if (it.isDir) {
        onOpenFolder?.call(it);
      } else {
        onOpenFile(it);
      }
    }

    void hold(FileItem it) {
      if (!it.isDir) onLongPressFile?.call(it);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: mode == ViewMode.list
          ? ListView.builder(
              key: const ValueKey('list'),
              padding: EdgeInsets.only(bottom: bottomPadding),
              itemCount: all.length,
              itemBuilder: (context, i) => FileListTile(
                item: all[i],
                index: i,
                onTap: () => tap(all[i]),
                onLongPress: () => hold(all[i]),
              ),
            )
          : GridView.builder(
              key: const ValueKey('grid'),
              padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPadding),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 190,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.86,
              ),
              itemCount: all.length,
              itemBuilder: (context, i) => FileGridCard(
                item: all[i],
                index: i,
                onTap: () => tap(all[i]),
                onLongPress: () => hold(all[i]),
              ),
            ),
    );
  }
}
