// Pure logic tests (no plugins needed). File is named widget_test.dart so that
// `flutter create` never generates its own default test over it.
import 'package:flutter_test/flutter_test.dart';
import 'package:fyleon/core/remote/remote_settings.dart';
import 'package:fyleon/core/utils/format.dart';
import 'package:fyleon/features/files/domain/file_item.dart';
import 'package:fyleon/features/files/domain/file_kind.dart';
import 'package:fyleon/features/files/domain/files_logic.dart';

FileItem _f(String name, int size, DateTime modified, {DateTime? added}) => FileItem(
      path: '/x/$name',
      name: name,
      size: size,
      modified: modified,
      added: added ?? modified,
      kind: kindForExtension(extensionOf(name)),
    );

void main() {
  group('file kinds', () {
    test('detects common types', () {
      expect(kindForExtension('PDF'), FileKind.pdf);
      expect(kindForExtension('epub'), FileKind.epub);
      expect(kindForExtension('dart'), FileKind.code);
      expect(kindForExtension('docx'), FileKind.word);
      expect(kindForExtension('zip'), FileKind.archive);
      expect(kindForExtension('apk'), FileKind.apk);
      expect(kindForExtension('xyz'), FileKind.other);
    });
    test('extension helper', () {
      expect(extensionOf('Main.DART'), 'dart');
      expect(extensionOf('Dockerfile'), 'dockerfile');
      expect(extensionOf('noext'), '');
    });
  });

  group('sort and filter', () {
    final a = _f('b.pdf', 300, DateTime(2026, 1, 3));
    final b = _f('A.txt', 100, DateTime(2026, 1, 1));
    final c = _f('c.dart', 200, DateTime(2026, 1, 2));
    final items = [a, b, c];

    List<String> names(SortOption s, {KindFilter f = KindFilter.all, String q = '', Map<String, DateTime>? o}) =>
        applySortFilter(items, sort: s, filter: f, query: q, opened: o ?? {}).map((e) => e.name).toList();

    test('name A-Z and Z-A', () {
      expect(names(SortOption.nameAsc), ['A.txt', 'b.pdf', 'c.dart']);
      expect(names(SortOption.nameDesc), ['c.dart', 'b.pdf', 'A.txt']);
    });
    test('size and modified', () {
      expect(names(SortOption.sizeLargest), ['b.pdf', 'c.dart', 'A.txt']);
      expect(names(SortOption.sizeSmallest), ['A.txt', 'c.dart', 'b.pdf']);
      expect(names(SortOption.newestModified), ['b.pdf', 'c.dart', 'A.txt']);
      expect(names(SortOption.oldestModified), ['A.txt', 'c.dart', 'b.pdf']);
    });
    test('last opened puts opened files first', () {
      final opened = {c.path: DateTime(2026, 2, 1), a.path: DateTime(2026, 3, 1)};
      expect(names(SortOption.lastOpened, o: opened), ['b.pdf', 'c.dart', 'A.txt']);
    });
    test('filter and search', () {
      expect(names(SortOption.nameAsc, f: KindFilter.pdf), ['b.pdf']);
      expect(names(SortOption.nameAsc, f: KindFilter.code), ['c.dart']);
      expect(names(SortOption.nameAsc, q: 'A.T'), ['A.txt']);
    });
  });

  group('format', () {
    test('sizes', () {
      expect(formatSize(512), '512 B');
      expect(formatSize(2048), '2.0 KB');
      expect(formatSize(5 * 1024 * 1024), '5.0 MB');
    });
    test('dates', () {
      final now = DateTime(2026, 11, 1, 12);
      expect(formatDate(DateTime(2026, 11, 1, 3), now: now), 'Today');
      expect(formatDate(DateTime(2026, 10, 31), now: now), 'Yesterday');
      expect(formatDate(DateTime(2026, 3, 5), now: now), '5 Mar');
      expect(formatDate(DateTime(2025, 3, 5), now: now), '5 Mar 2025');
    });
  });

  group('remote settings', () {
    test('defaults when json is empty', () {
      final s = RemoteSettings.fromJson({});
      expect(s.interstitialEveryNFileCloses, 4);
      expect(s.premiumThemeUnlockHours, 24);
      expect(s.bannerEnabled, true);
    });
    test('values are clamped to safe limits', () {
      final s = RemoteSettings.fromJson({
        'ads': {'interstitialEveryNFileCloses': 1, 'interstitialMinGapSeconds': 5},
      });
      expect(s.interstitialEveryNFileCloses, 2);
      expect(s.interstitialMinGapSeconds, 60);
    });
  });
}
