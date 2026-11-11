// Session 8 tests: viewer toolbar layout, photo crop math, apps filter, Dash protocol.
// Pure logic + a loopback transfer (no phone needed).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyleon/core/native/native_bridge.dart';
import 'package:fyleon/core/utils/format.dart';
import 'package:fyleon/features/apps/apps_model.dart';
import 'package:fyleon/features/dash/dash_transport.dart';
import 'package:fyleon/features/viewer/image_editor_screen.dart';
import 'package:fyleon/features/viewer/viewer_prefs.dart';
import 'package:image/image.dart' as img;

InstalledApp _app(String pkg, String label, {bool system = false, bool game = false, int apk = 1000, bool launchable = true}) => InstalledApp(
      pkg: pkg,
      label: label,
      system: system,
      game: game,
      apkSize: apk,
      installed: DateTime(2026, 1, 1),
      updated: DateTime(2026, 1, 1),
      version: '1.0',
      launchable: launchable,
    );

AppStats _stats(int app, int data, int cache, DateTime? last) => AppStats(app: app, data: data, cache: cache, lastUsed: last);

void main() {
  // NativeBridge (used by Dash) registers a platform channel handler
  TestWidgetsFlutterBinding.ensureInitialized();

  group('viewer toolbar layout', () {
    const all = ViewerAction.values;

    test('default, viewer without a pill', () {
      final l = const ViewerToolbarSettings().layout(all, allowPill: false);
      expect(l.top, [ViewerAction.star, ViewerAction.share, ViewerAction.edit]);
      expect(l.menu, [ViewerAction.favorite, ViewerAction.info, ViewerAction.openWith, ViewerAction.neighbors]);
      expect(l.pill, isEmpty);
    });

    test('default, image viewer with a pill', () {
      final l = const ViewerToolbarSettings().layout(all, allowPill: true);
      expect(l.top, [ViewerAction.star, ViewerAction.share]);
      expect(l.pill, [ViewerAction.edit, ViewerAction.info]);
      expect(l.menu, [ViewerAction.favorite, ViewerAction.openWith, ViewerAction.neighbors]);
    });

    test('hidden actions are nowhere, extra top icons move to the menu', () {
      var s = const ViewerToolbarSettings(maxTop: 1).withPlace(ViewerAction.favorite, ActionPlace.off);
      final l = s.layout(all, allowPill: false);
      expect(l.top, [ViewerAction.star]);
      expect(l.menu.contains(ViewerAction.favorite), isFalse);
      expect(l.menu.contains(ViewerAction.share), isTrue);
      s = s.withPlace(ViewerAction.favorite, ActionPlace.top);
      expect(s.layout(all, allowPill: false).top, [ViewerAction.star]);
    });

    test('unavailable actions are skipped', () {
      final l = const ViewerToolbarSettings().layout([ViewerAction.star, ViewerAction.share], allowPill: true);
      expect(l.top, [ViewerAction.star, ViewerAction.share]);
      expect(l.pill, isEmpty);
      expect(l.menu, isEmpty);
    });

    test('settings survive JSON', () {
      final s = const ViewerToolbarSettings(maxTop: 4).withPlace(ViewerAction.edit, ActionPlace.top).withPlace(ViewerAction.star, ActionPlace.off);
      final back = ViewerToolbarSettings.fromJson(s.toJson());
      expect(back.maxTop, 4);
      expect(back.placeOf(ViewerAction.edit), ActionPlace.top);
      expect(back.placeOf(ViewerAction.star), ActionPlace.off);
      expect(back.placeOf(ViewerAction.share), ActionPlace.top);
    });
  });

  group('photo editor', () {
    test('crop rectangles', () {
      expect(cropRect(4000, 3000, 1, 1, 0, 0), [500, 0, 3000, 3000]);
      expect(cropRect(4000, 3000, 4, 1, 0, 0), [0, 375, 4000, 2250]);
      expect(cropRect(4000, 3000, 0, 2, 0, 0), [1000, 750, 2000, 1500]);
      expect(cropRect(4000, 3000, 0, 2, -1, 0), [0, 750, 2000, 1500]);
    });

    test('identity detection', () {
      expect(const EditParams().isIdentity, isTrue);
      expect(const EditParams(turns: 4).isIdentity, isTrue);
      expect(const EditParams(turns: 1).isIdentity, isFalse);
      expect(const EditParams(filter: 2).isIdentity, isFalse);
    });

    test('rotate and crop really change the picture', () {
      final src = Uint8List.fromList(img.encodePng(img.Image(width: 40, height: 20)));
      final rotated = applyEdits(EditJob(bytes: src, path: '', params: const EditParams(turns: 1), png: true));
      final r = img.decodeImage(rotated!)!;
      expect([r.width, r.height], [20, 40]);
      final cropped = applyEdits(EditJob(bytes: src, path: '', params: const EditParams(crop: 1), png: true));
      final c = img.decodeImage(cropped!)!;
      expect([c.width, c.height], [20, 20]);
    });
  });

  group('apps filter', () {
    final now = DateTime(2026, 11, 10);
    final list = [
      AppEntry(_app('a.big', 'Big', apk: 10), _stats(200 * 1024 * 1024, 0, 5000, now.subtract(const Duration(days: 2)))),
      AppEntry(_app('b.old', 'Old', apk: 10), _stats(1000, 1000, 9000000, now.subtract(const Duration(days: 90)))),
      AppEntry(_app('c.game', 'Game', game: true, apk: 10), _stats(5000, 0, 100, null)),
      AppEntry(_app('d.sys', 'System thing', system: true, apk: 10), _stats(100, 0, 100, now)),
      AppEntry(_app('e.nostats', 'NoStats', apk: 77), null),
    ];

    test('tabs', () {
      final user = filterApps(list, tab: AppTab.installed, now: now);
      expect(user.map((e) => e.app.pkg), isNot(contains('d.sys')));
      final sys = filterApps(list, tab: AppTab.system, now: now);
      expect(sys.map((e) => e.app.pkg), ['d.sys']);
    });

    test('chips', () {
      expect(filterApps(list, tab: AppTab.installed, chips: {AppChipFilter.large}, now: now).map((e) => e.app.pkg), ['a.big']);
      expect(filterApps(list, tab: AppTab.installed, chips: {AppChipFilter.games}, now: now).map((e) => e.app.pkg), ['c.game']);
      final unused = filterApps(list, tab: AppTab.installed, chips: {AppChipFilter.unused}, now: now).map((e) => e.app.pkg).toList();
      expect(unused.toSet(), {'b.old', 'c.game'}); // never used or 30+ days; apps without sizes are not guessed
    });

    test('sorting and search', () {
      expect(filterApps(list, tab: AppTab.installed, now: now).first.app.pkg, 'a.big');
      expect(filterApps(list, tab: AppTab.installed, sort: AppSort.cache, now: now).first.app.pkg, 'b.old');
      expect(filterApps(list, tab: AppTab.installed, sort: AppSort.name, now: now).first.app.label, 'Big');
      expect(filterApps(list, tab: AppTab.installed, sort: AppSort.lastUsed, now: now).first.app.pkg, 'a.big');
      expect(filterApps(list, tab: AppTab.installed, query: 'nostat', now: now).length, 1);
    });

    test('totals', () {
      expect(totalCacheOf(list), 5000 + 9000000 + 100 + 100);
      expect(list.last.size, 77); // no stats: APK size
    });
  });

  group('Dash helpers', () {
    test('codes', () {
      final c = randomCode();
      expect(c.length, 6);
      expect(RegExp(r'^[1-9]\d{5}$').hasMatch(c), isTrue);
      expect(codeTag('123456'), codeTag('123456'));
      expect(codeTag('123456'), isNot(codeTag('123457')));
      expect(randomCode(digits: 7).length, 7);
    });

    test('file names from other devices are made safe', () {
      expect(safeFileName('../../etc/passwd'), 'passwd');
      expect(safeFileName('a:b?.txt'), 'a_b_.txt');
      expect(safeFileName('..'), 'file');
      expect(safeFileName('...hidden'), 'hidden');
    });

    test('QR link round trip', () {
      final raw = buildDashLink(hosts: ['192.168.1.5', '10.0.0.2'], port: 5000, code: '123456', name: 'My Phone');
      final l = DashLink.parse(raw)!;
      expect(l.hosts, ['192.168.1.5', '10.0.0.2']);
      expect(l.port, 5000);
      expect(l.code, '123456');
      expect(l.name, 'My Phone');
      expect(DashLink.parse('https://example.com'), isNull);
      expect(DashLink.parse('fyleon://dash?h=&p=1'), isNull);
    });

    test('time ago text', () {
      final now = DateTime(2026, 11, 10, 12);
      expect(formatAgo(DateTime(2026, 11, 7, 12), now: now), '3 days ago');
      expect(formatAgo(DateTime(2026, 11, 10, 9), now: now), '3 h ago');
    });
  });

  group('Dash transfer over loopback', () {
    late Directory dir;
    late File src;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('fyleon_dash_test');
      src = File('${dir.path}/photo.bin')..writeAsBytesSync(List<int>.generate(700000, (i) => (i * 7) % 251));
    });

    tearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('sender and receiver exchange a file with the code', () async {
      final sender = DashSender(deviceId: 'A', deviceName: 'Sender', files: [SendItem(src.path, 'photo.bin', src.lengthSync())]);
      await sender.start();
      final dl = DashDownloader(myId: 'B', myName: 'Receiver');
      try {
        await dl.connect(['127.0.0.1'], sender.port, code: sender.code);
        expect(dl.files.length, 1);
        expect(dl.files.first.name, 'photo.bin');
        final saved = await dl.download('${dir.path}/out', (_) {});
        expect(File(saved[0]!).readAsBytesSync(), src.readAsBytesSync());
      } finally {
        await dl.close();
        await sender.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('wrong code is refused', () async {
      final sender = DashSender(deviceId: 'A', deviceName: 'Sender', files: [SendItem(src.path, 'photo.bin', src.lengthSync())], code: '482913');
      await sender.start();
      final dl = DashDownloader(myId: 'B', myName: 'Receiver');
      try {
        await expectLater(dl.connect(['127.0.0.1'], sender.port, code: '000000'), throwsA(isA<DashRefused>()));
      } finally {
        await dl.close();
        await sender.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('without a code the sender must accept', () async {
      final sender = DashSender(deviceId: 'A', deviceName: 'Sender', files: [SendItem(src.path, 'photo.bin', src.lengthSync())]);
      await sender.start();
      final dl = DashDownloader(myId: 'B', myName: 'Receiver');
      try {
        final connecting = dl.connect(['127.0.0.1'], sender.port);
        // the receiver shows up as "pending" on the sender
        for (var i = 0; i < 50 && sender.clients.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(sender.clients.single.status, ClientStatus.pending);
        sender.approve('B');
        await connecting;
        expect(dl.files.length, 1);
      } finally {
        await dl.close();
        await sender.stop();
      }
    }, timeout: const Timeout(Duration(seconds: 40)));
  });
}
