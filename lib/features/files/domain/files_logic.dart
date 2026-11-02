import 'package:flutter/material.dart';

import 'file_item.dart';
import 'file_kind.dart';

enum SortOption {
  lastOpened,
  nameAsc,
  nameDesc,
  newestModified,
  oldestModified,
  recentlyAdded,
  sizeLargest,
  sizeSmallest,
  type,
}

extension SortOptionX on SortOption {
  String get label {
    switch (this) {
      case SortOption.lastOpened:
        return 'Last opened';
      case SortOption.nameAsc:
        return 'Name (A to Z)';
      case SortOption.nameDesc:
        return 'Name (Z to A)';
      case SortOption.newestModified:
        return 'Recently modified';
      case SortOption.oldestModified:
        return 'Oldest modified';
      case SortOption.recentlyAdded:
        return 'Recently added';
      case SortOption.sizeLargest:
        return 'Size (largest first)';
      case SortOption.sizeSmallest:
        return 'Size (smallest first)';
      case SortOption.type:
        return 'Type';
    }
  }

  IconData get icon {
    switch (this) {
      case SortOption.lastOpened:
        return Icons.history_rounded;
      case SortOption.nameAsc:
        return Icons.sort_by_alpha_rounded;
      case SortOption.nameDesc:
        return Icons.sort_by_alpha_rounded;
      case SortOption.newestModified:
        return Icons.update_rounded;
      case SortOption.oldestModified:
        return Icons.event_rounded;
      case SortOption.recentlyAdded:
        return Icons.fiber_new_rounded;
      case SortOption.sizeLargest:
        return Icons.arrow_downward_rounded;
      case SortOption.sizeSmallest:
        return Icons.arrow_upward_rounded;
      case SortOption.type:
        return Icons.category_rounded;
    }
  }
}

enum ViewMode { list, grid }

int _byName(FileItem a, FileItem b) =>
    a.name.toLowerCase().compareTo(b.name.toLowerCase());

/// Pure function: filter + search + sort. `opened` maps path -> last opened.
List<FileItem> applySortFilter(
  List<FileItem> items, {
  required SortOption sort,
  required KindFilter filter,
  required String query,
  required Map<String, DateTime> opened,
}) {
  final q = query.trim().toLowerCase();
  final list = items
      .where((f) =>
          filter.matches(f.kind) &&
          (q.isEmpty || f.name.toLowerCase().contains(q)))
      .toList();

  int compare(FileItem a, FileItem b) {
    switch (sort) {
      case SortOption.lastOpened:
        final oa = opened[a.path];
        final ob = opened[b.path];
        if (oa != null && ob != null) return ob.compareTo(oa);
        if (oa != null) return -1;
        if (ob != null) return 1;
        return b.modified.compareTo(a.modified);
      case SortOption.nameAsc:
        return _byName(a, b);
      case SortOption.nameDesc:
        return _byName(b, a);
      case SortOption.newestModified:
        return b.modified.compareTo(a.modified);
      case SortOption.oldestModified:
        return a.modified.compareTo(b.modified);
      case SortOption.recentlyAdded:
        return b.added.compareTo(a.added);
      case SortOption.sizeLargest:
        return b.size.compareTo(a.size);
      case SortOption.sizeSmallest:
        return a.size.compareTo(b.size);
      case SortOption.type:
        final c = a.kind.label.compareTo(b.kind.label);
        if (c != 0) return c;
        final e = a.ext.compareTo(b.ext);
        return e != 0 ? e : _byName(a, b);
    }
  }

  list.sort(compare);
  return list;
}
