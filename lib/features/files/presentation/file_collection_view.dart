import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/remote/remote_settings.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/bottom_safe.dart';
import '../../../shared/widgets/file_widgets.dart';
import '../../ads/native_ad_tile.dart';
import '../application/files_providers.dart';
import '../domain/file_item.dart';
import '../domain/files_logic.dart';

/// Where native ads go in a list: after every [every] items, at most [max] ads.
class AdSlots {
  AdSlots(this.items, {required this.every, required int max})
      : ads = every <= 0 ? 0 : math.min(items ~/ every, max);

  final int items;
  final int every;
  final int ads;

  int get total => items + ads;

  bool isAd(int i) => ads > 0 && (i + 1) % (every + 1) == 0 && (i + 1) ~/ (every + 1) <= ads;

  int itemIndex(int i) => i - (ads == 0 ? 0 : math.min(i ~/ (every + 1), ads));
}

/// Shows files either as a list or as a grid. Folders (if any) come first.
/// Every item has a three-dots button (same menu as long-press). Native ads are
/// mixed in after every few items.
class FileCollectionView extends ConsumerWidget {
  const FileCollectionView({
    super.key,
    required this.files,
    this.folders = const [],
    required this.onOpenFile,
    this.onOpenFolder,
    this.onLongPressFile,
    this.bottomPadding = 96,
    this.showAds = true,
  });

  final List<FileItem> files;
  final List<FileItem> folders;
  final void Function(FileItem) onOpenFile;
  final void Function(FileItem)? onOpenFolder;
  final void Function(FileItem)? onLongPressFile;
  final double bottomPadding;
  final bool showAds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(viewModeProvider);
    final remote = ref.watch(remoteSettingsProvider);
    final all = [...folders, ...files];
    final adsOn = showAds && adsSupported && remote.nativeEnabled;
    final inset = bottomInset(context);

    void tap(FileItem it) {
      if (it.isDir) {
        onOpenFolder?.call(it);
      } else {
        onOpenFile(it);
      }
    }

    VoidCallback? menuFor(FileItem it) => onLongPressFile == null ? null : () => onLongPressFile!(it);

    Widget child;
    if (mode == ViewMode.list) {
      final slots = AdSlots(all.length, every: remote.nativeEveryNItems, max: adsOn ? remote.nativeMaxPerList : 0);
      child = ListView.builder(
        key: const ValueKey('list'),
        padding: EdgeInsets.only(bottom: bottomPadding + inset),
        itemCount: slots.total,
        itemBuilder: (context, i) {
          if (slots.isAd(i)) return const NativeAdTile();
          final item = all[slots.itemIndex(i)];
          return FileListTile(
            item: item,
            index: i,
            onTap: () => tap(item),
            onLongPress: menuFor(item),
            onMore: menuFor(item),
          );
        },
      );
    } else {
      child = LayoutBuilder(
        key: const ValueKey('grid'),
        builder: (context, box) {
          final extent = gridExtents[ref.watch(gridSizeProvider)];
          final cols = math.max(2, ((box.maxWidth - 32) / extent).floor());
          final perChunk = ((remote.nativeEveryNItems / cols).ceil()) * cols;
          final slivers = <Widget>[
            SliverToBoxAdapter(child: _GridHeader(count: all.length)),
          ];
          var adCount = 0;
          for (var start = 0; start < all.length; start += perChunk) {
            final end = math.min(start + perChunk, all.length);
            slivers.add(SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.86,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final idx = start + i;
                    final item = all[idx];
                    return FileGridCard(
                      item: item,
                      index: idx,
                      onTap: () => tap(item),
                      onLongPress: menuFor(item),
                      onMore: menuFor(item),
                    );
                  },
                  childCount: end - start,
                ),
              ),
            ));
            if (adsOn && adCount < remote.nativeMaxPerList && end < all.length) {
              slivers.add(const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.only(top: 6), child: NativeAdTile())));
              adCount++;
            }
          }
          slivers.add(SliverToBoxAdapter(child: SizedBox(height: bottomPadding + inset)));
          return CustomScrollView(slivers: slivers);
        },
      );
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 240), child: child);
  }
}

/// Options shown above the grid: item count and tile size (small / medium / large).
class _GridHeader extends ConsumerWidget {
  const _GridHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = ref.watch(gridSizeProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
      child: Row(
        children: [
          Text('$count items', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5)),
          const Spacer(),
          SegmentedButton<int>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: 0, icon: Icon(Icons.grid_view_rounded, size: 15)),
              ButtonSegment(value: 1, icon: Icon(Icons.apps_rounded, size: 18)),
              ButtonSegment(value: 2, icon: Icon(Icons.crop_square_rounded, size: 20)),
            ],
            selected: {size},
            onSelectionChanged: (s) => ref.read(gridSizeProvider.notifier).set(s.first),
          ),
        ],
      ),
    );
  }
}
