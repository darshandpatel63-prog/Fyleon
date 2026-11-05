import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../shared/widgets/animations.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../viewer/viewer_screen.dart';
import '../application/browse_controller.dart';
import '../application/collections_providers.dart';
import '../data/file_ops.dart';
import '../domain/file_item.dart';
import 'file_collection_view.dart';

/// PIN protected folder kept inside Fyleon's private storage.
class SafeFolderScreen extends ConsumerStatefulWidget {
  const SafeFolderScreen({super.key});

  @override
  ConsumerState<SafeFolderScreen> createState() => _SafeFolderScreenState();
}

class _SafeFolderScreenState extends ConsumerState<SafeFolderScreen> {
  bool _unlocked = false;
  String _dir = '';
  List<FileItem> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _start() async {
    final svc = ref.read(safeServiceProvider);
    if (!svc.hasPin) {
      final pin = await _createPin();
      if (pin == null) return _leave();
      await svc.setPin(pin);
    } else {
      var tries = 0;
      while (true) {
        final pin = await _askPin(tries == 0 ? null : 'Wrong PIN. Try again.');
        if (!mounted) return;
        if (pin == null) return _leave();
        if (pin == '__forgot__') {
          final erase = await _confirmErase();
          if (erase) {
            await svc.resetAndErase();
            _toast('Safe folder erased and PIN removed');
          }
          return _leave();
        }
        if (svc.verify(pin)) break;
        tries++;
        if (tries >= 5) {
          _toast('Too many wrong PINs');
          return _leave();
        }
      }
    }
    final dir = await svc.directory();
    if (!mounted) return;
    _dir = dir.path;
    _reload();
    setState(() => _unlocked = true);
  }

  void _leave() {
    if (mounted) Navigator.of(context).pop();
  }

  void _reload() {
    setState(() => _items = listDirectory(_dir)..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  }

  bool _validPin(String s) => RegExp(r'^\d{4,8}$').hasMatch(s);

  Future<String?> _createPin() async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? error;
    final r = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          icon: const Icon(Icons.lock_rounded),
          title: const Text('Create a PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('4 to 8 digits. If you forget it, the only way back in is to erase the Safe folder.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(controller: a, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: const InputDecoration(labelText: 'New PIN', counterText: '')),
              TextField(controller: b, obscureText: true, keyboardType: TextInputType.number, maxLength: 8, decoration: InputDecoration(labelText: 'Repeat PIN', counterText: '', errorText: error)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!_validPin(a.text)) {
                  setD(() => error = 'Use 4 to 8 digits');
                } else if (a.text != b.text) {
                  setD(() => error = 'PINs do not match');
                } else {
                  Navigator.pop(ctx, a.text);
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    a.dispose();
    b.dispose();
    return r;
  }

  Future<String?> _askPin(String? error) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_rounded),
        title: const Text('Safe folder'),
        content: TextField(
          controller: c,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: InputDecoration(labelText: 'Enter PIN', counterText: '', errorText: error),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, '__forgot__'), child: const Text('Forgot PIN')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Open')),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<bool> _confirmErase() async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase the Safe folder?'),
        content: const Text('Everything inside the Safe folder will be deleted forever and the PIN will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Erase')),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _menu(FileItem item) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            if (!item.isDir) ListTile(leading: const Icon(Icons.open_in_new_rounded), title: const Text('Open'), onTap: () => Navigator.pop(ctx, 'open')),
            ListTile(leading: const Icon(Icons.output_rounded), title: const Text('Move out to Download'), onTap: () => Navigator.pop(ctx, 'out')),
            ListTile(leading: const Icon(Icons.delete_forever_rounded), title: const Text('Delete forever'), onTap: () => Navigator.pop(ctx, 'delete')),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'open') {
      await Navigator.of(context).push(fadeSlideRoute(ViewerScreen(item: item)));
    } else if (choice == 'out') {
      try {
        final roots = storageRoots();
        final target = roots.isEmpty ? p.dirname(_dir) : p.join(roots.first.path, 'Download');
        await Directory(target).create(recursive: true);
        await moveEntity(item.path, target);
        _toast('Moved to $target');
        ref.invalidate(directoryListingProvider);
      } catch (e) {
        _toast(friendlyError(e).message);
      }
      _reload();
    } else if (choice == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete forever?'),
          content: Text('"${item.name}" will be deleted permanently. This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) {
        try {
          await deleteEntity(item.path);
        } catch (e) {
          _toast(friendlyError(e).message);
        }
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Safe folder')),
      body: !_unlocked
          ? const Center(child: Icon(Icons.lock_rounded, size: 56))
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.tertiaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                  child: const Text(
                    'Files here are kept inside Fyleon and are deleted if you uninstall the app. Move them out first. '
                    'Add files from the Files tab: long-press a file and choose "Move to Safe folder".',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? const EmptyState(icon: Icons.lock_outline_rounded, title: 'The Safe folder is empty')
                      : FileCollectionView(
                          folders: _items.where((i) => i.isDir).toList(),
                          files: _items.where((i) => !i.isDir).toList(),
                          onOpenFile: (f) => Navigator.of(context).push(fadeSlideRoute(ViewerScreen(item: f))),
                          onOpenFolder: (_) {},
                          onLongPressFile: _menu,
                        ),
                ),
              ],
            ),
    );
  }
}
