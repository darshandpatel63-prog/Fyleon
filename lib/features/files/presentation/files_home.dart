import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/native/native_bridge.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/animations.dart';
import '../application/browse_controller.dart';
import '../application/collections_providers.dart';
import '../domain/file_category.dart';
import '../domain/file_item.dart';
import '../domain/file_kind.dart';
import 'category_screen.dart';
import 'collection_screen.dart';
import 'file_manager_actions.dart';
import 'safe_folder_screen.dart';
import 'trash_screen.dart';

/// Home of the Files tab (like Google Files): recent files, categories,
/// collections (starred, favorites, safe folder, trash) and storages.
class FilesHome extends ConsumerWidget {
  const FilesHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(storageScanProvider);
    final roots = storageRoots();
    final internal = roots.isEmpty ? null : roots.first.path;
    final scheme = Theme.of(context).colorScheme;

    String sizeText(FileCategory c) => scan.when(
          data: (r) => r == null ? '' : '${formatSize(r.bytes[c] ?? 0)} - ${r.count(c)} files',
          loading: () => 'Scanning...',
          error: (e, s) => '',
        );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(storageScanProvider);
        await ref.read(storageScanProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          _title(context, 'Recent'),
          SizedBox(
            height: 150,
            child: scan.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, s) => const SizedBox.shrink(),
              data: (r) {
                final list = r?.recent ?? const <FileItem>[];
                if (list.isEmpty) {
                  return Center(child: Text('No recent files yet', style: TextStyle(color: scheme.onSurfaceVariant)));
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (context, i) => const SizedBox(width: 10),
                  itemBuilder: (context, i) => _RecentCard(
                    item: list[i],
                    onTap: () => openFromBrowse(context, ref, list[i]),
                    onLongPress: () => showItemMenu(context, ref, list[i], p.dirname(list[i].path)),
                  ),
                );
              },
            ),
          ),
          _title(context, 'Categories'),
          _grid(context, [
            _BigCard(
              icon: Icons.download_rounded,
              color: const Color(0xFF16A34A),
              title: 'Downloads',
              subtitle: scan.when(
                data: (r) => r == null ? '' : formatSize(r.downloadsBytes),
                loading: () => 'Scanning...',
                error: (e, s) => '',
              ),
              onTap: () {
                if (internal != null) ref.read(browsePathProvider.notifier).open(p.join(internal, 'Download'));
              },
            ),
            for (final c in FileCategory.values)
              _BigCard(
                icon: c.icon,
                color: c.color,
                title: c.label,
                subtitle: sizeText(c),
                onTap: () => Navigator.of(context).push(fadeSlideRoute(CategoryScreen(category: c))),
              ),
          ]),
          _title(context, 'Collections'),
          _grid(context, [
            _BigCard(
              icon: Icons.star_rounded,
              color: const Color(0xFFF59E0B),
              title: 'Starred',
              subtitle: '${ref.watch(starredProvider).length} items',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const CollectionScreen(starred: true))),
            ),
            _BigCard(
              icon: Icons.favorite_rounded,
              color: const Color(0xFFE11D48),
              title: 'Favorites',
              subtitle: '${ref.watch(favoritesProvider).length} items',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const CollectionScreen(starred: false))),
            ),
            _BigCard(
              icon: Icons.lock_rounded,
              color: const Color(0xFF4F46E5),
              title: 'Safe folder',
              subtitle: 'PIN protected',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const SafeFolderScreen())),
            ),
            _BigCard(
              icon: Icons.delete_rounded,
              color: const Color(0xFF64748B),
              title: 'Trash',
              subtitle: 'Kept for ${TrashNotifier.keepDays} days',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const TrashScreen())),
            ),
          ]),
          _title(context, 'All storage'),
          for (final r in roots.where((r) => r.label.startsWith('Internal') || r.label.startsWith('SD card') || r.label == 'Home'))
            _StorageCard(
              root: r,
              onTap: () => ref.read(browsePathProvider.notifier).open(r.path),
            ),
          const SizedBox(height: 4),
          Text(
            'Other apps\' data folders (Android/data) are blocked by Android itself, so no file manager can open them on Android 11 and newer.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _title(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      );

  Widget _grid(BuildContext context, List<Widget> children) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.15,
      children: children,
    );
  }
}

class _BigCard extends StatelessWidget {
  const _BigCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
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

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.item, required this.onTap, required this.onLongPress});

  final FileItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final color = item.kind.color;
    Widget bg;
    if (item.kind == FileKind.image) {
      bg = Image.file(
        File(item.path),
        fit: BoxFit.cover,
        cacheWidth: 360,
        errorBuilder: (c, e, s) => Container(color: color.withValues(alpha: 0.15), child: Icon(item.kind.icon, color: color, size: 40)),
      );
    } else {
      bg = Container(color: color.withValues(alpha: 0.16), child: Center(child: Icon(item.kind.icon, color: color, size: 44)));
    }
    return SizedBox(
      width: 130,
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Stack(
            fit: StackFit.expand,
            children: [
              bg,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(10, 22, 10, 8),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xB3000000)]),
                  ),
                  child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorageCard extends StatefulWidget {
  const _StorageCard({required this.root, required this.onTap});

  final StorageRoot root;
  final VoidCallback onTap;

  @override
  State<_StorageCard> createState() => _StorageCardState();
}

class _StorageCardState extends State<_StorageCard> {
  late final Future<StorageInfo?> _info = NativeBridge.instance.storageInfo(widget.root.path);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: FutureBuilder<StorageInfo?>(
              future: _info,
              builder: (context, snap) {
                final info = snap.data;
                return Row(
                  children: [
                    Icon(widget.root.icon, color: scheme.primary, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.root.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            info == null ? widget.root.path : '${formatSize(info.free)} free of ${formatSize(info.total)}',
                            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                          ),
                          if (info != null && info.total > 0) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(value: 1 - info.free / info.total, minHeight: 6),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
