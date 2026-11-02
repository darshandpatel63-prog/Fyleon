import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/utils/format.dart';
import '../../features/files/domain/file_item.dart';
import '../../features/files/domain/file_kind.dart';
import 'animations.dart';

/// Rounded colored tile with the icon of the file type (or an image thumbnail).
class FileThumb extends StatelessWidget {
  const FileThumb({super.key, required this.item, this.size = 48, this.radius = 14});

  final FileItem item;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = item.isDir ? Theme.of(context).colorScheme.primary : item.kind.color;
    final icon = item.isDir ? Icons.folder_rounded : item.kind.icon;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
    if (item.kind != FileKind.image || item.isDir) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.file(
          File(item.path),
          fit: BoxFit.cover,
          cacheWidth: (size * 3).round(),
          errorBuilder: (context, error, stack) => fallback,
        ),
      ),
    );
  }
}

String fileSubtitle(FileItem item) {
  if (item.isDir) return 'Folder';
  return '${item.kind.label} - ${formatSize(item.size)} - ${formatDate(item.modified)}';
}

class FileListTile extends StatelessWidget {
  const FileListTile({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final FileItem item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeSlideIn(
      index: index,
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: FileThumb(item: item),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          fileSubtitle(item),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
        ),
        trailing: trailing,
      ),
    );
  }
}

class FileGridCard extends StatelessWidget {
  const FileGridCard({
    super.key,
    required this.item,
    required this.index,
    required this.onTap,
    this.onLongPress,
  });

  final FileItem item;
  final int index;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeSlideIn(
      index: index,
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                  child: LayoutBuilder(
                    builder: (context, c) => Center(
                      child: FileThumb(
                        item: item,
                        size: c.maxHeight.clamp(40, 140).toDouble(),
                        radius: 16,
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.isDir
                          ? 'Folder'
                          : '${formatSize(item.size)} - ${formatDate(item.modified)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
