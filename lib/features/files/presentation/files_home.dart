import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/native/native_bridge.dart';
import '../../../core/utils/format.dart';
import '../../../shared/widgets/animations.dart';
import '../../ads/native_ad_tile.dart';
import '../application/browse_controller.dart';
import '../application/collections_providers.dart';
import '../domain/file_category.dart';
import '../domain/file_item.dart';
import '../domain/file_kind.dart';
import '../../apps/apps_screen.dart';
import '../../video/video_library_screen.dart';
import '../../dash/dash_screens.dart';
import 'category_screen.dart';
import 'collection_screen.dart';
import 'recent_all_screen.dart';
import 'file_manager_actions.dart';
import 'safe_folder_screen.dart';
import 'trash_screen.dart';

/// Home of the Files tab: a storage "ring" hero, recent files, colorful category tiles,
/// collections (starred, favorites, safe folder, trash) and all storages.
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

    var tileIndex = 0;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(storageScanProvider);
        await ref.read(storageScanProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
        children: [
          if (internal != null) _StorageHero(path: internal, onTap: () => ref.read(browsePathProvider.notifier).open(internal)),
          const SizedBox(height: 12),
          const _DashCard(),
          _titleAction(context, 'Recent', 'See all', () => Navigator.of(context).push(fadeSlideRoute(const RecentAllScreen()))),
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
                  itemBuilder: (context, i) => FadeSlideIn(
                    index: i,
                    child: _RecentCard(
                      item: list[i],
                      onTap: () => openFromBrowse(context, ref, list[i]),
                      onLongPress: () => showItemMenu(context, ref, list[i], p.dirname(list[i].path)),
                    ),
                  ),
                );
              },
            ),
          ),
          _title(context, 'Categories'),
          _grid([
            _BigCard(
              index: tileIndex++,
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
                index: tileIndex++,
                icon: c.icon,
                color: c.color,
                title: c.label,
                subtitle: sizeText(c),
                heroTag: 'cat-${c.name}',
                onTap: () => Navigator.of(context).push(fadeSlideRoute(c == FileCategory.videos ? const VideoLibraryScreen() : CategoryScreen(category: c))),
              ),
            _BigCard(
              index: tileIndex++,
              icon: Icons.apps_rounded,
              color: const Color(0xFF0F766E),
              title: 'Apps',
              subtitle: 'Sizes, cache, unused',
              heroTag: 'cat-apps',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const AppsScreen())),
            ),
          ]),
          const NativeAdTile(),
          _title(context, 'Collections'),
          _grid([
            _BigCard(
              index: tileIndex++,
              icon: Icons.star_rounded,
              color: const Color(0xFFF59E0B),
              title: 'Starred',
              subtitle: '${ref.watch(starredProvider).length} items',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const CollectionScreen(starred: true))),
            ),
            _BigCard(
              index: tileIndex++,
              icon: Icons.favorite_rounded,
              color: const Color(0xFFE11D48),
              title: 'Favorites',
              subtitle: '${ref.watch(favoritesProvider).length} items',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const CollectionScreen(starred: false))),
            ),
            _BigCard(
              index: tileIndex++,
              icon: Icons.lock_rounded,
              color: const Color(0xFF4F46E5),
              title: 'Safe folder',
              subtitle: 'PIN protected',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const SafeFolderScreen())),
            ),
            _BigCard(
              index: tileIndex++,
              icon: Icons.delete_rounded,
              color: const Color(0xFF64748B),
              title: 'Trash',
              subtitle: 'Kept for ${TrashNotifier.keepDays} days',
              onTap: () => Navigator.of(context).push(fadeSlideRoute(const TrashScreen())),
            ),
          ]),
          _title(context, 'All storage'),
          for (final r in roots.where((r) => r.label.startsWith('Internal') || r.label.startsWith('SD card') || r.label == 'Home'))
            _StorageCard(root: r, onTap: () => ref.read(browsePathProvider.notifier).open(r.path)),
          const SizedBox(height: 4),
          Text(
            'Other apps\' data folders (Android/data) are blocked by Android itself, so no file manager can open them on Android 11 and newer.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _titleAction(BuildContext context, String t, String action, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 0, 2),
        child: Row(
          children: [
            Expanded(child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
            TextButton(
              onPressed: onTap,
              child: Row(mainAxisSize: MainAxisSize.min, children: [Text(action), const Icon(Icons.chevron_right_rounded, size: 20)]),
            ),
          ],
        ),
      );

  Widget _title(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      );

  Widget _grid(List<Widget> children) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.15,
      ),
      children: children,
    );
  }
}

// ---------------------------------------------------------------- Dash entry

class _DashCard extends StatelessWidget {
  const _DashCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FadeSlideIn(
      index: 1,
      child: Material(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        color: scheme.surfaceContainerHigh,
        child: InkWell(
          onTap: () => Navigator.of(context).push(fadeSlideRoute(const DashHomeScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
                  ),
                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fyleon Dash', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      Text('Send files to nearby phones and PCs, no internet needed', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- hero ring

class _StorageHero extends StatefulWidget {
  const _StorageHero({required this.path, required this.onTap});

  final String path;
  final VoidCallback onTap;

  @override
  State<_StorageHero> createState() => _StorageHeroState();
}

class _StorageHeroState extends State<_StorageHero> {
  late final Future<StorageInfo?> _info = NativeBridge.instance.storageInfo(widget.path);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FutureBuilder<StorageInfo?>(
      future: _info,
      builder: (context, snap) {
        final info = snap.data;
        final used = (info == null || info.total == 0) ? 0.0 : 1 - info.free / info.total;
        return Material(
          borderRadius: BorderRadius.circular(28),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: 92,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: used),
                      duration: const Duration(milliseconds: 1100),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => CustomPaint(
                        painter: _RingPainter(v, Colors.white.withValues(alpha: 0.28), Colors.white),
                        child: Center(
                          child: Text(
                            info == null ? '' : '${(v * 100).round()}%',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Internal storage', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          info == null ? 'Tap to browse' : '${formatSize(info.total - info.free)} used - ${formatSize(info.free)} free',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                        ),
                        if (info != null)
                          Text('of ${formatSize(info.total)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.track, this.color);

  final double value;
  final Color track;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final rect = Offset.zero & size;
    final arc = rect.deflate(stroke / 2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track;
    canvas.drawArc(arc, 0, math.pi * 2, false, base);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(arc, -math.pi / 2, math.pi * 2 * value.clamp(0.0, 1.0), false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color || old.track != track;
}

// ---------------------------------------------------------------- tiles

class _BigCard extends StatelessWidget {
  const _BigCard({
    required this.index,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.heroTag,
  });

  final int index;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget iconW = Icon(icon, color: color, size: 24);
    if (heroTag != null) iconW = Hero(tag: heroTag!, child: iconW);
    return FadeSlideIn(
      index: index,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.05)],
            ),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: [
                Positioned(
                  right: -10,
                  bottom: -14,
                  child: Icon(icon, size: 74, color: color.withValues(alpha: 0.10)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(14)),
                        child: iconW,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                            if (subtitle.isNotEmpty)
                              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
        borderRadius: BorderRadius.circular(22),
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
