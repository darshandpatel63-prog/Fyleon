import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/format.dart';
import '../../../shared/widgets/animations.dart';
import '../../editor/editor_screen.dart';
import '../../preview/preview_screen.dart';
import '../application/browse_controller.dart';
import '../application/files_providers.dart';
import '../data/file_ops.dart';
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

/// Long-press menu for a file or folder.
Future<void> showItemMenu(BuildContext context, WidgetRef ref, FileItem item, String dir) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
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
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _renameFlow(context, ref, item, dir);
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
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(ctx);
                _deleteFlow(context, ref, item, dir);
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

Future<void> _renameFlow(BuildContext context, WidgetRef ref, FileItem item, String dir) async {
  final name = await promptText(context, title: 'Rename', initial: item.name, confirm: 'Rename');
  if (name == null || name.trim() == item.name || !context.mounted) return;
  try {
    await renameEntity(item.path, name);
    await ref.read(recentsProvider.notifier).remove(item.path);
    ref.invalidate(directoryListingProvider(dir));
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e).message);
  }
}

Future<void> _deleteFlow(BuildContext context, WidgetRef ref, FileItem item, String dir) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(item.isDir ? 'Delete folder?' : 'Delete file?'),
      content: Text(item.isDir
          ? '"${item.name}" and everything inside it will be deleted. This cannot be undone.'
          : '"${item.name}" will be deleted. This cannot be undone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await deleteEntity(item.path);
    await ref.read(recentsProvider.notifier).remove(item.path);
    ref.invalidate(directoryListingProvider(dir));
  } catch (e) {
    if (context.mounted) _toast(context, friendlyError(e).message);
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
