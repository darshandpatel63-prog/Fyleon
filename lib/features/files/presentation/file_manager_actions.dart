import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/native/native_bridge.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/animations.dart';
import '../../dash/dash_screens.dart';
import '../../editor/editor_screen.dart';
import '../../preview/preview_screen.dart';
import '../../viewer/archive_viewer.dart';
import '../application/browse_controller.dart';
import '../application/files_providers.dart';
import '../application/collections_providers.dart';
import '../data/file_ops.dart';
import '../data/trash_service.dart';
import '../domain/file_item.dart';
import '../domain/file_kind.dart';
import 'file_actions.dart';

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirm = 'OK',
  List<String> quickExtensions = const [],
}) {
  final controller = TextEditingController(text: initial);
  if (initial.isNotEmpty) {
    final dot = initial.lastIndexOf('.');
    controller.selection = TextSelection(baseOffset: 0, extentOffset: dot > 0 ? dot : initial.length);
  }
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          if (quickExtensions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 0,
              children: [
                for (final e in quickExtensions)
                  ActionChip(
                    label: Text(e),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final base = p.basenameWithoutExtension(controller.text.trim());
                      final name = base.isEmpty ? 'untitled' : base;
                      controller.text = '$name$e';
                      controller.selection = TextSelection.collapsed(offset: controller.text.length);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(confirm)),
      ],
    ),
  );
}

Future<void> openEditor(BuildContext context, String path) {
  return Navigator.of(context).push(fadeSlideRoute(EditorScreen(path: path)));
}

void openPreview(BuildContext context, String path) {
  Navigator.of(context).push(fadeSlideRoute(PreviewScreen(path: path)));
}

bool isPreviewablePath(String path) =>
    const {'html', 'htm', 'svg', 'md', 'markdown'}.contains(extensionOf(p.basename(path)));

bool isEditableItem(FileItem item) =>
    !item.isDir &&
    (item.kind == FileKind.code ||
        item.kind == FileKind.text ||
        item.kind == FileKind.other);

/// "+" menu inside a folder: new folder / new file / new web project.
Future<void> showCreateSheet(BuildContext context, WidgetRef ref, String dir) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.create_new_folder_rounded),
            title: const Text('New folder'),
            onTap: () {
              Navigator.pop(ctx);
              _createFolderFlow(context, ref, dir);
            },
          ),
          ListTile(
            leading: const Icon(Icons.note_add_rounded),
            title: const Text('New file'),
            subtitle: const Text('Text, Markdown, HTML, CSS, JS, Dart, Python...'),
            onTap: () {
              Navigator.pop(ctx);
              _createFileFlow(context, ref, dir);
            },
          ),
          ListTile(
            leading: const Icon(Icons.web_rounded),
            title: const Text('New web project'),
            subtitle: const Text('index.html + style.css + script.js, with live preview'),
            onTap: () {
              Navigator.pop(ctx);
              _createWebProjectFlow(context, ref, dir);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Future<void> _createFolderFlow(BuildContext context, WidgetRef ref, String dir) async {
  final name = await promptText(context, title: 'New folder', hint: 'Folder name', confirm: 'Create');
  if (name == null || !context.mounted) return;
  try {
    await createFolder(dir, name);
    ref.invalidate(directoryListingProvider(dir));
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e).message);
  }
}

Future<void> _createFileFlow(BuildContext context, WidgetRef ref, String dir) async {
  final name = await promptText(
    context,
    title: 'New file',
    hint: 'name.ext (example: index.html)',
    confirm: 'Create',
    quickExtensions: quickExtensions,
  );
  if (name == null || !context.mounted) return;
  try {
    final path = await createFile(dir, name, content: templateFor(name));
    ref.invalidate(directoryListingProvider(dir));
    if (context.mounted) await openEditor(context, path);
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e).message);
  }
}

Future<void> _createWebProjectFlow(BuildContext context, WidgetRef ref, String dir) async {
  final name = await promptText(context, title: 'New web project', initial: 'my-website', confirm: 'Create');
  if (name == null || !context.mounted) return;
  try {
    final index = await createWebProject(dir, name);
    ref.invalidate(directoryListingProvider(dir));
    if (context.mounted) await openEditor(context, index);
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e).message);
  }
}

/// Long-press menu for a file or folder. [onGone] is called when the item left its folder
/// (trashed, moved, renamed) so that lists can hide it right away.
Future<void> showItemMenu(
  BuildContext context,
  WidgetRef ref,
  FileItem item,
  String dir, {
  void Function(String path)? onGone,
}) {
  final starred = ref.read(starredProvider).contains(item.path);
  final favorite = ref.read(favoritesProvider).contains(item.path);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            const SizedBox(height: 4),
            if (!item.isDir)
              ListTile(
                leading: const Icon(Icons.open_in_new_rounded),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(ctx);
                  openFromBrowse(context, ref, item);
                },
              ),
            if (!item.isDir)
              ListTile(
                leading: const Icon(Icons.bolt_rounded),
                title: const Text('Send with Dash'),
                subtitle: const Text('To a nearby device, no internet needed'),
                onTap: () {
                  Navigator.pop(ctx);
                  sendWithDash(context, [item.path]);
                },
              ),
            if (item.kind == FileKind.apk)
              ListTile(
                leading: const Icon(Icons.install_mobile_rounded),
                title: const Text('Install'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final r = await NativeBridge.instance.installApk(item.path);
                  if (context.mounted) {
                    _toast(context, r == 'started' ? 'Installer opened' : (r == 'need_permission' ? 'Allow Fyleon to install apps, then try again' : 'Could not start the installer'));
                  }
                },
              ),
            if (!item.isDir && (item.kind == FileKind.apk || item.kind == FileKind.archive))
              ListTile(
                leading: const Icon(Icons.folder_zip_rounded),
                title: const Text('Unpack / browse contents'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(fadeSlideRoute(ArchiveViewerScreen(item: item)));
                },
              ),
            if (isEditableItem(item))
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(ctx);
                  openEditor(context, item.path);
                },
              ),
            if (!item.isDir && isPreviewablePath(item.path))
              ListTile(
                leading: const Icon(Icons.play_circle_outline_rounded),
                title: const Text('Preview'),
                onTap: () {
                  Navigator.pop(ctx);
                  openPreview(context, item.path);
                },
              ),
            ListTile(
              leading: Icon(starred ? Icons.star_rounded : Icons.star_border_rounded),
              title: Text(starred ? 'Remove from Starred' : 'Add to Starred'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(starredProvider.notifier).toggle(item.path);
              },
            ),
            ListTile(
              leading: Icon(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded),
              title: Text(favorite ? 'Remove from Favorites' : 'Add to Favorites'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(favoritesProvider.notifier).toggle(item.path);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _renameFlow(context, ref, item, dir, onGone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Copy'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(clipboardProvider.notifier).set(FileClipboard([item.path], cut: false));
                _toast(context, 'Copied. Open a folder and tap Paste.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_cut_rounded),
              title: const Text('Move (cut)'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(clipboardProvider.notifier).set(FileClipboard([item.path], cut: true));
                _toast(context, 'Ready to move. Open a folder and tap Paste.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline_rounded),
              title: const Text('Move to Safe folder'),
              onTap: () {
                Navigator.pop(ctx);
                _toSafeFlow(context, ref, item, dir, onGone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Move to Trash'),
              onTap: () {
                Navigator.pop(ctx);
                _trashFlow(context, ref, item, dir, onGone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Details'),
              onTap: () {
                Navigator.pop(ctx);
                _detailsDialog(context, item);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

Future<void> _forget(WidgetRef ref, String path) async {
  await ref.read(recentsProvider.notifier).remove(path);
  await ref.read(starredProvider.notifier).remove(path);
  await ref.read(favoritesProvider.notifier).remove(path);
}

Future<void> _renameFlow(BuildContext context, WidgetRef ref, FileItem item, String dir, void Function(String)? onGone) async {
  final name = await promptText(context, title: 'Rename', initial: item.name, confirm: 'Rename');
  if (name == null || name.trim() == item.name || !context.mounted) return;
  try {
    final target = await renameEntity(item.path, name);
    await ref.read(recentsProvider.notifier).remove(item.path);
    await ref.read(starredProvider.notifier).rename(item.path, target);
    await ref.read(favoritesProvider.notifier).rename(item.path, target);
    ref.invalidate(directoryListingProvider(dir));
    onGone?.call(item.path);
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e).message);
  }
}

Future<void> _trashFlow(BuildContext context, WidgetRef ref, FileItem item, String dir, void Function(String)? onGone) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.delete_outline_rounded),
      title: Text(item.isDir ? 'Move folder to Trash?' : 'Move file to Trash?'),
      content: Text(
        item.isDir
            ? '"${item.name}" and everything inside it will go to the Trash. You can restore it within 30 days.'
            : '"${item.name}" will go to the Trash. You can restore it within 30 days.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move to Trash')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final entry = await moveToTrash(item.path);
    await _forget(ref, item.path);
    ref.invalidate(directoryListingProvider(dir));
    onGone?.call(item.path);
    messenger.showSnackBar(SnackBar(
      content: Text('"${item.name}" moved to Trash'),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          try {
            await restoreEntry(entry);
            ref.invalidate(directoryListingProvider);
          } catch (_) {}
        },
      ),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e).message)));
  }
}

Future<void> _toSafeFlow(BuildContext context, WidgetRef ref, FileItem item, String dir, void Function(String)? onGone) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final safe = await ref.read(safeServiceProvider).directory();
    await moveEntity(item.path, safe.path);
    await _forget(ref, item.path);
    ref.invalidate(directoryListingProvider(dir));
    onGone?.call(item.path);
    messenger.showSnackBar(SnackBar(content: Text('"${item.name}" moved to the Safe folder')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(friendlyError(e).message)));
  }
}

void _detailsDialog(BuildContext context, FileItem item) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Details'),
      content: SelectionArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Name: ${item.name}'),
            const SizedBox(height: 6),
            Text('Type: ${item.isDir ? 'Folder' : item.kind.label}'),
            if (!item.isDir) ...[
              const SizedBox(height: 6),
              Text('Size: ${formatSize(item.size)}'),
            ],
            const SizedBox(height: 6),
            Text('Modified: ${item.modified.toString().split('.').first}'),
            const SizedBox(height: 6),
            Text('Path: ${item.path}'),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}

/// Details dialog (also used by the viewer toolbar).
void showFileDetails(BuildContext context, FileItem item) => _detailsDialog(context, item);

/// Paste whatever is in the clipboard into [dir].
Future<void> pasteInto(BuildContext context, WidgetRef ref, String dir) async {
  final clip = ref.read(clipboardProvider);
  if (clip == null) return;
  try {
    for (final path in clip.paths) {
      if (clip.cut) {
        await moveEntity(path, dir);
        await ref.read(recentsProvider.notifier).remove(path);
      } else {
        await copyEntity(path, dir);
      }
    }
    if (clip.cut) ref.read(clipboardProvider.notifier).set(null);
    ref.invalidate(directoryListingProvider(dir));
    if (context.mounted) _toast(context, clip.cut ? 'Moved' : 'Pasted');
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e).message);
  }
}

/// Opens a file from the file manager (viewer chosen by type).
Future<void> openFromBrowse(BuildContext context, WidgetRef ref, FileItem item) =>
    openFile(context, ref, item);
