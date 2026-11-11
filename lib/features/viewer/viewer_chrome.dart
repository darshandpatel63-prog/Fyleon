import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/native/native_bridge.dart';
import '../../shared/widgets/animations.dart';
import '../editor/editor_screen.dart';
import '../files/application/collections_providers.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import '../files/presentation/file_manager_actions.dart';
import 'file_neighbors.dart';
import 'image_editor_screen.dart';
import 'viewer_prefs.dart';

extension ViewerActionMeta on ViewerAction {
  String get label {
    switch (this) {
      case ViewerAction.star:
        return 'Star';
      case ViewerAction.favorite:
        return 'Favorite (heart)';
      case ViewerAction.share:
        return 'Share';
      case ViewerAction.edit:
        return 'Edit';
      case ViewerAction.info:
        return 'Details';
      case ViewerAction.openWith:
        return 'Open with another app';
      case ViewerAction.neighbors:
        return 'Previous / next file';
    }
  }

  IconData get icon {
    switch (this) {
      case ViewerAction.star:
        return Icons.star_border_rounded;
      case ViewerAction.favorite:
        return Icons.favorite_border_rounded;
      case ViewerAction.share:
        return Icons.share_rounded;
      case ViewerAction.edit:
        return Icons.edit_rounded;
      case ViewerAction.info:
        return Icons.info_outline_rounded;
      case ViewerAction.openWith:
        return Icons.open_in_new_rounded;
      case ViewerAction.neighbors:
        return Icons.swap_horiz_rounded;
    }
  }
}

/// Actions that make sense for this file.
Set<ViewerAction> availableActions(FileItem item) => {
      ViewerAction.star,
      ViewerAction.favorite,
      ViewerAction.share,
      ViewerAction.info,
      ViewerAction.openWith,
      ViewerAction.neighbors,
      if (item.kind == FileKind.image || item.kind == FileKind.code || item.kind == FileKind.text) ViewerAction.edit,
    };

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Runs one action. [onEdit] lets a viewer do its own "edit" (the image viewer reloads the picture).
Future<void> runViewerAction(
  BuildContext context,
  WidgetRef ref,
  ViewerAction action,
  FileItem item, {
  VoidCallback? onEdit,
}) async {
  switch (action) {
    case ViewerAction.star:
      await ref.read(starredProvider.notifier).toggle(item.path);
    case ViewerAction.favorite:
      await ref.read(favoritesProvider.notifier).toggle(item.path);
    case ViewerAction.share:
      {
        final ok = await NativeBridge.instance.shareFiles([item.path]);
        if (!ok && context.mounted) _toast(context, 'Sharing is not available on this device yet.');
      }
    case ViewerAction.edit:
      if (onEdit != null) {
        onEdit();
      } else if (item.kind == FileKind.image) {
        await Navigator.of(context).push(fadeSlideRoute(ImageEditorScreen(path: item.path)));
      } else {
        await Navigator.of(context).pushReplacement(fadeSlideRoute(EditorScreen(path: item.path)));
      }
    case ViewerAction.info:
      showFileDetails(context, item);
    case ViewerAction.openWith:
      {
        final ok = await NativeBridge.instance.openWith(item.path);
        if (!ok && context.mounted) _toast(context, 'No app found to open this file.');
      }
    case ViewerAction.neighbors:
      break;
  }
}

/// Icons for the top bar of a viewer: what the owner chose in Settings > Viewer toolbar.
/// Put it inside `AppBar(actions: [ViewerActions(...)])`.
class ViewerActions extends ConsumerWidget {
  const ViewerActions({
    super.key,
    required this.item,
    this.color,
    this.hide = const {},
    this.onEdit,
    this.leading = const [],
  });

  final FileItem item;
  final Color? color;

  /// Actions this viewer already offers in another way (the image viewer swipes instead of "next file").
  final Set<ViewerAction> hide;
  final VoidCallback? onEdit;

  /// Viewer-specific icons shown first (text size, word wrap...).
  final List<Widget> leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(viewerToolbarProvider);
    final starred = ref.watch(starredProvider).contains(item.path);
    final favorite = ref.watch(favoritesProvider).contains(item.path);
    final layout = settings.layout(availableActions(item).difference(hide), allowPill: false);

    Widget iconBtn(String tip, IconData icon, VoidCallback onTap, {Color? tint, Object? key}) {
      return IconButton(
        tooltip: tip,
        color: tint ?? color,
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
          child: Icon(icon, key: ValueKey(key ?? icon)),
        ),
        onPressed: onTap,
      );
    }

    final top = <Widget>[];
    for (final a in layout.top) {
      switch (a) {
        case ViewerAction.star:
          top.add(iconBtn(
            starred ? 'Remove from Starred' : 'Add to Starred',
            starred ? Icons.star_rounded : Icons.star_border_rounded,
            () => runViewerAction(context, ref, a, item),
            tint: starred ? const Color(0xFFF59E0B) : null,
          ));
        case ViewerAction.favorite:
          top.add(iconBtn(
            favorite ? 'Remove from Favorites' : 'Add to Favorites',
            favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            () => runViewerAction(context, ref, a, item),
            tint: favorite ? const Color(0xFFE11D48) : null,
          ));
        case ViewerAction.neighbors:
          top.add(iconBtn('Previous file', Icons.chevron_left_rounded, () => openNeighbor(context, ref, item, -1), key: 'prev'));
          top.add(iconBtn('Next file', Icons.chevron_right_rounded, () => openNeighbor(context, ref, item, 1), key: 'next'));
        default:
          top.add(iconBtn(a.label, a.icon, () => runViewerAction(context, ref, a, item, onEdit: onEdit)));
      }
    }

    final menuEntries = <PopupMenuEntry<String>>[];
    for (final a in layout.menu) {
      switch (a) {
        case ViewerAction.star:
          menuEntries.add(_item('star', starred ? Icons.star_rounded : Icons.star_border_rounded, starred ? 'Remove from Starred' : 'Add to Starred'));
        case ViewerAction.favorite:
          menuEntries.add(_item('favorite', favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, favorite ? 'Remove from Favorites' : 'Add to Favorites'));
        case ViewerAction.neighbors:
          menuEntries.add(_item('prev', Icons.chevron_left_rounded, 'Previous file'));
          menuEntries.add(_item('next', Icons.chevron_right_rounded, 'Next file'));
        default:
          menuEntries.add(_item(a.name, a.icon, a.label));
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...leading,
        ...top,
        if (menuEntries.isNotEmpty)
          PopupMenuButton<String>(
            tooltip: 'More',
            iconColor: color,
            icon: const Icon(Icons.more_vert_rounded),
            itemBuilder: (context) => menuEntries,
            onSelected: (v) {
              if (v == 'prev') {
                openNeighbor(context, ref, item, -1);
              } else if (v == 'next') {
                openNeighbor(context, ref, item, 1);
              } else {
                final a = ViewerAction.values.firstWhere((e) => e.name == v);
                runViewerAction(context, ref, a, item, onEdit: onEdit);
              }
            },
          ),
      ],
    );
  }

  PopupMenuItem<String> _item(String value, IconData icon, String label) => PopupMenuItem<String>(
        value: value,
        child: Row(children: [Icon(icon, size: 20), const SizedBox(width: 12), Flexible(child: Text(label))]),
      );
}

/// Floating pill at the bottom of the image viewer (default: Edit + Details).
class ViewerPill extends ConsumerWidget {
  const ViewerPill({super.key, required this.item, this.hide = const {}, this.onEdit});

  final FileItem item;
  final Set<ViewerAction> hide;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(viewerToolbarProvider);
    final starred = ref.watch(starredProvider).contains(item.path);
    final favorite = ref.watch(favoritesProvider).contains(item.path);
    final layout = settings.layout(availableActions(item).difference(hide), allowPill: true);
    final actions = layout.pill.where((a) => a != ViewerAction.neighbors).toList();
    if (actions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    IconData iconOf(ViewerAction a) {
      if (a == ViewerAction.star) return starred ? Icons.star_rounded : Icons.star_border_rounded;
      if (a == ViewerAction.favorite) return favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded;
      return a.icon;
    }

    return Material(
      color: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final a in actions)
              IconButton(
                tooltip: a.label,
                iconSize: 26,
                color: Colors.white,
                icon: Icon(iconOf(a)),
                onPressed: () => runViewerAction(context, ref, a, item, onEdit: onEdit),
              ),
          ],
        ),
      ),
    );
  }
}
