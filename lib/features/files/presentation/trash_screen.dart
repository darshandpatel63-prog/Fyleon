import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/utils/format.dart';
import '../../../shared/widgets/bottom_safe.dart';
import '../../../shared/widgets/empty_state.dart';
import '../application/browse_controller.dart';
import '../application/collections_providers.dart';
import '../data/file_ops.dart';
import '../data/trash_service.dart';
import '../domain/file_item.dart';
import '../domain/file_kind.dart';

/// Recycle bin: restore or delete forever.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(trashProvider.notifier).refresh();
    });
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<bool> _confirm(String title, String body, String action) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return r == true;
  }

  Future<void> _restore(TrashEntry e) async {
    try {
      await ref.read(trashProvider.notifier).restore(e);
      ref.invalidate(directoryListingProvider);
      _toast('"${e.name}" restored');
    } catch (err) {
      _toast(friendlyError(err).message);
    }
  }

  Future<void> _deleteForever(TrashEntry e) async {
    final ok = await _confirm('Delete forever?', '"${e.name}" will be deleted permanently. This cannot be undone.', 'Delete forever');
    if (!ok) return;
    try {
      await ref.read(trashProvider.notifier).deleteOne(e);
    } catch (err) {
      _toast(friendlyError(err).message);
    }
  }

  Future<void> _empty() async {
    final ok = await _confirm('Empty Trash?', 'Everything in the Trash will be deleted permanently. This cannot be undone.', 'Empty Trash');
    if (ok) await ref.read(trashProvider.notifier).emptyAll();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(trashProvider);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (items.isNotEmpty)
            TextButton(onPressed: _empty, child: const Text('Empty')),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Trash is empty',
              message: 'Deleted files stay here for 30 days, then they are removed for good.',
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: scheme.tertiaryContainer.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14)),
                  child: Text('Items are deleted forever after ${TrashNotifier.keepDays} days.', style: const TextStyle(fontSize: 12.5)),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.only(bottom: bottomInset(context) + 16),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      final kind = e.isDir ? null : kindForExtension(extensionOf(e.name));
                      return ListTile(
                        leading: Icon(e.isDir ? Icons.folder_rounded : kind!.icon, color: e.isDir ? scheme.primary : kind!.color),
                        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          'From ${p.basename(p.dirname(e.originalPath))} - ${formatDate(e.deletedAt)}${e.isDir ? '' : ' - ${formatSize(e.size)}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) => v == 'restore' ? _restore(e) : _deleteForever(e),
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'restore', child: Text('Restore')),
                            PopupMenuItem(value: 'delete', child: Text('Delete forever')),
                          ],
                        ),
                        onTap: () => _restore(e),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
