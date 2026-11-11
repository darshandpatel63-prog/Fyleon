import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../shared/widgets/animations.dart';
import '../files/application/files_providers.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import '../files/domain/files_logic.dart';
import 'viewer_screen.dart';

/// What to look for next to an open file.
class SiblingQuery {
  const SiblingQuery(this.path, this.kindIndex);

  final String path;
  final int kindIndex;
}

/// Top-level so it can run in an isolate: every file of the same kind in the same folder.
List<FileItem> listSameKind(SiblingQuery q) {
  final dir = p.dirname(q.path);
  final out = <FileItem>[];
  for (final it in listDirectory(dir)) {
    if (!it.isDir && it.kind.index == q.kindIndex) out.add(it);
  }
  return out;
}

/// Files of the same kind that sit next to [item], in the order the owner chose with "Sort".
Future<List<FileItem>> loadSiblings(WidgetRef ref, FileItem item) async {
  final list = await compute(listSameKind, SiblingQuery(item.path, item.kind.index));
  final sorted = applySortFilter(
    list,
    sort: ref.read(sortProvider),
    filter: KindFilter.all,
    query: '',
    opened: ref.read(openedMapProvider),
  );
  // the file may have been picked from the cache: make sure it is part of the list
  if (!sorted.any((f) => f.path == item.path)) sorted.insert(0, item);
  return sorted;
}

/// Opens the previous (-1) or next (+1) file in place of the current viewer.
Future<void> openNeighbor(BuildContext context, WidgetRef ref, FileItem current, int delta) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final list = await loadSiblings(ref, current);
  final i = list.indexWhere((f) => f.path == current.path);
  final j = i + delta;
  if (i < 0 || j < 0 || j >= list.length) {
    messenger.showSnackBar(SnackBar(content: Text(delta < 0 ? 'This is the first file.' : 'This is the last file.')));
    return;
  }
  final next = list[j];
  ref.read(recentsProvider.notifier).add(next);
  navigator.pushReplacement(fadeSlideRoute(ViewerScreen(item: next)));
}
