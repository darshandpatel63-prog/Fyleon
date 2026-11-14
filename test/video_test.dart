// Video player v1: subtitles, gesture math, settings, history, queue, sidecars, library grouping.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyleon/core/native/native_bridge.dart';
import 'package:fyleon/features/files/domain/file_item.dart';
import 'package:fyleon/features/files/domain/file_kind.dart';
import 'package:fyleon/features/video/subtitle_parser.dart';
import 'package:fyleon/features/video/video_library_screen.dart';
import 'package:fyleon/features/video/video_models.dart';
import 'package:fyleon/features/video/video_player_screen.dart';

FileItem _video(String path, int size) => FileItem(
      path: path,
      name: path.split('/').last,
      size: size,
      modified: DateTime(2026, 1, 1),
      added: DateTime(2026, 1, 1),
      kind: FileKind.video,
    );

void main() {
  group('subtitles', () {
    const srt = r'''1
00:00:01,000 --> 00:00:03,500
Hello <i>world</i>
second line

2
00:00:05,000 --> 00:00:06,000
{\an8}Top text
''';

    test('SRT with tags and two lines', () {
      final c = parseSubtitles(srt);
      expect(c.length, 2);
      expect(c[0].start, const Duration(seconds: 1));
      expect(c[0].end, const Duration(milliseconds: 3500));
      expect(c[0].text, 'Hello world\nsecond line');
      expect(c[1].text, 'Top text');
    });

    test('SRT with Windows line endings gives the same result', () {
      final c = parseSubtitles(srt.replaceAll('\n', '\r\n'));
      expect(c.length, 2);
      expect(c[0].text, 'Hello world\nsecond line');
    });

    test('WebVTT with header, note, short times and voice tags', () {
      const vtt = '''WEBVTT

NOTE this is a comment

00:01.000 --> 00:02.500 align:start
<v Anna>Hi there</v>

1
01:00:01.000 --> 01:00:02.000
Long
''';
      final c = parseSubtitles(vtt);
      expect(c.length, 2);
      expect(c[0].start, const Duration(seconds: 1));
      expect(c[0].end, const Duration(milliseconds: 2500));
      expect(c[0].text, 'Hi there');
      expect(c[1].start, const Duration(hours: 1, seconds: 1));
    });

    test('ASS dialogue with override tags, comma and line break', () {
      const ass = r'''[Script Info]
Title: x

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.50,0:00:03.00,Default,,0,0,0,,{\i1}Hello{\i0}\Nworld, with comma
''';
      final c = parseSubtitles(ass);
      expect(c.length, 1);
      expect(c[0].start, const Duration(milliseconds: 1500));
      expect(c[0].end, const Duration(seconds: 3));
      expect(c[0].text, 'Hello\nworld, with comma');
    });

    test('format detection', () {
      expect(detectSubFormat('WEBVTT\n\n'), SubFormat.vtt);
      expect(detectSubFormat('[Script Info]\n'), SubFormat.ass);
      expect(detectSubFormat('hello', ext: 'vtt'), SubFormat.vtt);
      expect(detectSubFormat('hello'), SubFormat.srt);
    });

    test('time parsing', () {
      expect(parseSubTime('01:02:03,500'), const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500));
      expect(parseSubTime('00:03.5'), const Duration(seconds: 3, milliseconds: 500));
      expect(parseSubTime('abc'), isNull);
    });

    test('active cues, overlap and delay', () {
      const a = SubCue(Duration(seconds: 1), Duration(seconds: 3), 'A');
      const b = SubCue(Duration(seconds: 2), Duration(seconds: 5), 'B');
      const c = SubCue(Duration(seconds: 10), Duration(seconds: 12), 'C');
      final list = [a, b, c];
      expect(cuesAt(list, const Duration(milliseconds: 2500)).map((e) => e.text), ['A', 'B']);
      expect(cuesAt(list, const Duration(seconds: 7)), isEmpty);
      expect(cuesAt(list, const Duration(milliseconds: 10500)).map((e) => e.text), ['C']);
      // delay +2 s: the subtitles come 2 seconds later
      expect(cuesAt(list, const Duration(seconds: 12), delay: const Duration(seconds: 2)).map((e) => e.text), ['C']);
      expect(cuesAt(list, Duration.zero), isEmpty);
    });

    test('text decoding', () {
      expect(decodeSubtitleBytes(Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x48, 0x69])), 'Hi');
      expect(decodeSubtitleBytes(Uint8List.fromList([0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00])), 'Hi');
      expect(decodeSubtitleBytes(Uint8List.fromList([0x63, 0x61, 0x66, 0xE9])), 'caf\u00e9');
      expect(decodeSubtitleBytes(Uint8List.fromList([0xC3, 0xA9]), encoding: 'latin1'), '\u00c3\u00a9');
    });
  });

  group('gesture and display math', () {
    test('seek distance', () {
      expect(seekDeltaMs(540, 1080, 3600000, 1.0), 90000);
      expect(seekDeltaMs(540, 1080, 60000, 1.0), 15000); // short video: 30 s span
      expect(seekDeltaMs(-540, 1080, 3600000, 2.0), -180000);
      expect(seekDeltaMs(100, 0, 1000, 1), 0);
    });

    test('brightness / volume fraction', () {
      expect(adjustFraction(0.5, -100, 1000, 1.0), closeTo(0.61, 0.0001));
      expect(adjustFraction(0.9, -1000, 1000, 1.0), 1.0);
      expect(adjustFraction(0.1, 1000, 1000, 1.0), 0.0);
    });

    test('aspect modes', () {
      (double, double) size(AspectMode m, {double w = 1000, double h = 1000, double dpr = 1}) =>
          displaySizeFor(m, videoW: 1920, videoH: 1080, boxW: w, boxH: h, devicePixelRatio: dpr);
      expect(size(AspectMode.fit).$1, closeTo(1000, 0.01));
      expect(size(AspectMode.fit).$2, closeTo(562.5, 0.01));
      expect(size(AspectMode.fill).$2, closeTo(1000, 0.01));
      expect(size(AspectMode.fill).$1, closeTo(1777.78, 0.01));
      expect(size(AspectMode.stretch), (1000.0, 1000.0));
      expect(size(AspectMode.original, dpr: 2), (960.0, 540.0));
      expect(size(AspectMode.r16x9).$2, closeTo(562.5, 0.01));
      expect(size(AspectMode.r4x3, h: 500).$1, closeTo(666.67, 0.01));
    });

    test('pan can never show an empty edge', () {
      final z = clampPan(800, -800, contentW: 1000, contentH: 500, boxW: 1000, boxH: 500, scale: 2);
      expect(z.$1, 500);
      expect(z.$2, -250);
      final one = clampPan(50, 50, contentW: 1000, contentH: 500, boxW: 1000, boxH: 500, scale: 1);
      expect(one, (0.0, 0.0));
    });
  });

  group('settings, history, resume', () {
    test('settings survive JSON and are clamped', () {
      final s = const VideoSettings().copyWith(skipSeconds: 30, resumeMode: ResumeMode.ask, leftHanded: true, defaultAspect: AspectMode.fill, subSize: 30);
      final back = VideoSettings.fromJson(s.toJson());
      expect(back.skipSeconds, 30);
      expect(back.resumeMode, ResumeMode.ask);
      expect(back.leftHanded, isTrue);
      expect(back.defaultAspect, AspectMode.fill);
      expect(back.subSize, 30);
      expect(VideoSettings.fromJson({'skip': 999}).skipSeconds, 120);
      expect(VideoSettings.fromJson({'sens': 0}).sensitivity, 0.4);
      expect(VideoSettings.fromJson({'aspect': 'zzz'}).defaultAspect, AspectMode.fit);
      expect(VideoSettings.fromJson('nonsense').skipSeconds, 10);
    });

    test('resume point', () {
      const d = Duration(seconds: 100);
      expect(resumePoint(const Duration(seconds: 5), d), isNull);
      expect(resumePoint(const Duration(seconds: 50), d), const Duration(seconds: 50));
      expect(resumePoint(const Duration(seconds: 95), d), isNull);
      expect(resumePoint(const Duration(seconds: 50), Duration.zero), isNull);
    });

    test('record JSON and history trimming keep the newest', () {
      final r = VideoRecord(positionMs: 5000, durationMs: 20000, lastPlayed: DateTime.fromMillisecondsSinceEpoch(1000), subtitle: '/a/b.srt', subDelayMs: -300);
      final back = VideoRecord.fromJson(r.toJson())!;
      expect(back.positionMs, 5000);
      expect(back.subtitle, '/a/b.srt');
      expect(back.subDelayMs, -300);
      expect(back.progress, 0.25);
      final all = {for (var i = 0; i < 5; i++) 'v$i': VideoRecord(lastPlayed: DateTime.fromMillisecondsSinceEpoch(i * 1000))};
      expect(trimHistory(all, max: 3).keys.toSet(), {'v4', 'v3', 'v2'});
    });
  });

  group('queue', () {
    test('plain and shuffled order', () {
      expect(buildOrder(4, shuffle: false, first: 2), [0, 1, 2, 3]);
      final o = buildOrder(5, shuffle: true, first: 2, seed: 7);
      expect(o.first, 2);
      expect(List.of(o)..sort(), [0, 1, 2, 3, 4]);
    });

    test('next and previous with and without wrap', () {
      const order = [0, 1, 2];
      expect(nextInOrder(order, 1, wrap: false), 2);
      expect(nextInOrder(order, 2, wrap: false), isNull);
      expect(nextInOrder(order, 2, wrap: true), 0);
      expect(previousInOrder(order, 0, wrap: false), isNull);
      expect(previousInOrder(order, 0, wrap: true), 2);
      expect(previousInOrder(order, 1, wrap: false), 0);
    });
  });

  group('subtitle files next to a video', () {
    test('finding and naming', () {
      final found = findSidecarNames('Movie.mp4', ['Movie.mp4', 'movie.srt', 'Movie.en.srt', 'movie.gu.vtt', 'other.srt', 'movie.txt', 'Movie.Final.srt']);
      expect(found.first, 'movie.srt');
      expect(found.toSet(), {'movie.srt', 'Movie.en.srt', 'movie.gu.vtt', 'Movie.Final.srt'});
      expect(sidecarLabel('movie.srt', 'Movie.mp4'), 'Default');
      expect(sidecarLabel('Movie.en.srt', 'Movie.mp4'), 'English');
      expect(sidecarLabel('movie.gu.vtt', 'Movie.mp4'), 'Gujarati');
      expect(sidecarLabel('movie.en.forced.srt', 'Movie.mp4'), 'English (forced)');
    });
  });

  group('labels and messages', () {
    test('codec names and clock', () {
      expect(codecLabel('video/hevc'), 'H.265 (HEVC)');
      expect(codecLabel('audio/mp4a-latm'), 'AAC');
      expect(codecLabel('video/x-unknown'), 'x-unknown');
      expect(formatClock(const Duration(seconds: 83)), '1:23');
      expect(formatClock(const Duration(seconds: 3725)), '1:02:05');
      expect(formatClock(const Duration(seconds: -90)), '-1:30');
    });

    test('error text is plain language', () {
      expect(explainPlaybackError(null), contains('could not be read'));
      final info = VideoInfo.fromMap({
        'durationMs': 5000,
        'tracks': [
          {'type': 'video', 'mime': 'video/hevc'},
          {'type': 'audio', 'mime': 'audio/ac3'},
        ],
      });
      final text = explainPlaybackError(info);
      expect(text, contains('H.265 (HEVC)'));
      expect(text, contains('Dolby Digital (AC-3)'));
      expect(text, contains('another player'));
    });

    test('video info from the platform map', () {
      final i = VideoInfo.fromMap({
        'durationMs': 90000,
        'width': 1920,
        'height': 1080,
        'rotation': 90,
        'bitrate': 4000000,
        'mime': 'video/mp4',
        'fps': 29.97,
        'tracks': [
          {'type': 'video', 'mime': 'video/avc', 'width': 1920, 'height': 1080},
          {'type': 'audio', 'mime': 'audio/mp4a-latm', 'lang': 'gu', 'channels': 2, 'sampleRate': 48000},
          {'type': 'text', 'mime': 'text/vtt'},
        ],
      });
      expect(i.video.length, 1);
      expect(i.audio.single.lang, 'gu');
      expect(i.text.length, 1);
      expect(i.duration, const Duration(seconds: 90));
    });
  });

  group('library', () {
    test('videos are grouped by folder, biggest folder first', () {
      final folders = groupVideoFolders([
        _video('/s/Movies/a.mp4', 100),
        _video('/s/Movies/b.mp4', 200),
        _video('/s/DCIM/c.mp4', 50),
        _video('/s/Download/d.mp4', 10),
        _video('/s/Download/e.mp4', 10),
        _video('/s/Download/f.mp4', 10),
      ]);
      expect(folders.map((f) => f.path), ['/s/Download', '/s/Movies', '/s/DCIM']);
      expect(folders[1].count, 2);
      expect(folders[1].bytes, 300);
    });
  });
}
