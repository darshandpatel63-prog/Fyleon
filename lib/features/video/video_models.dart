import 'dart:math' as math;

import 'package:path/path.dart' as p;

// Pure data + logic of the video player (no Flutter widgets): easy to unit test.

enum ResumeMode { ask, auto, never }

enum OrientationMode { auto, sensor, landscape, portrait }

enum AspectMode { fit, fill, stretch, original, r16x9, r4x3 }

extension AspectModeX on AspectMode {
  String get label {
    switch (this) {
      case AspectMode.fit:
        return 'Fit';
      case AspectMode.fill:
        return 'Fill';
      case AspectMode.stretch:
        return 'Stretch';
      case AspectMode.original:
        return 'Original';
      case AspectMode.r16x9:
        return '16:9';
      case AspectMode.r4x3:
        return '4:3';
    }
  }
}

enum VideoRepeat { off, one, all }

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

/// Subtitle colours (ARGB).
const subtitleColors = <int>[0xFFFFFFFF, 0xFFFFEB3B, 0xFF80DEEA, 0xFFA5D6A7];

class VideoSettings {
  const VideoSettings({
    this.skipSeconds = 10,
    this.resumeMode = ResumeMode.auto,
    this.doubleTapSkip = true,
    this.gestures = true,
    this.seekGesture = true,
    this.brightnessGesture = true,
    this.volumeGesture = true,
    this.pinchZoom = true,
    this.longPressSpeed = true,
    this.longPressRate = 2.0,
    this.leftHanded = false,
    this.sensitivity = 1.0,
    this.defaultAspect = AspectMode.fit,
    this.orientation = OrientationMode.auto,
    this.autoNext = true,
    this.keepScreenOn = true,
    this.controlsHideSeconds = 4,
    this.subSize = 20,
    this.subColor = 0,
    this.subOutline = true,
    this.subBackground = false,
    this.subBottom = 40,
    this.subAuto = true,
  });

  final int skipSeconds;
  final ResumeMode resumeMode;
  final bool doubleTapSkip;
  final bool gestures;
  final bool seekGesture;
  final bool brightnessGesture;
  final bool volumeGesture;
  final bool pinchZoom;
  final bool longPressSpeed;
  final double longPressRate;
  final bool leftHanded;
  final double sensitivity;
  final AspectMode defaultAspect;
  final OrientationMode orientation;
  final bool autoNext;
  final bool keepScreenOn;
  final int controlsHideSeconds;
  final int subSize;
  final int subColor;
  final bool subOutline;
  final bool subBackground;
  final int subBottom;
  final bool subAuto;

  VideoSettings copyWith({
    int? skipSeconds,
    ResumeMode? resumeMode,
    bool? doubleTapSkip,
    bool? gestures,
    bool? seekGesture,
    bool? brightnessGesture,
    bool? volumeGesture,
    bool? pinchZoom,
    bool? longPressSpeed,
    double? longPressRate,
    bool? leftHanded,
    double? sensitivity,
    AspectMode? defaultAspect,
    OrientationMode? orientation,
    bool? autoNext,
    bool? keepScreenOn,
    int? controlsHideSeconds,
    int? subSize,
    int? subColor,
    bool? subOutline,
    bool? subBackground,
    int? subBottom,
    bool? subAuto,
  }) =>
      VideoSettings(
        skipSeconds: skipSeconds ?? this.skipSeconds,
        resumeMode: resumeMode ?? this.resumeMode,
        doubleTapSkip: doubleTapSkip ?? this.doubleTapSkip,
        gestures: gestures ?? this.gestures,
        seekGesture: seekGesture ?? this.seekGesture,
        brightnessGesture: brightnessGesture ?? this.brightnessGesture,
        volumeGesture: volumeGesture ?? this.volumeGesture,
        pinchZoom: pinchZoom ?? this.pinchZoom,
        longPressSpeed: longPressSpeed ?? this.longPressSpeed,
        longPressRate: longPressRate ?? this.longPressRate,
        leftHanded: leftHanded ?? this.leftHanded,
        sensitivity: sensitivity ?? this.sensitivity,
        defaultAspect: defaultAspect ?? this.defaultAspect,
        orientation: orientation ?? this.orientation,
        autoNext: autoNext ?? this.autoNext,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        controlsHideSeconds: controlsHideSeconds ?? this.controlsHideSeconds,
        subSize: subSize ?? this.subSize,
        subColor: subColor ?? this.subColor,
        subOutline: subOutline ?? this.subOutline,
        subBackground: subBackground ?? this.subBackground,
        subBottom: subBottom ?? this.subBottom,
        subAuto: subAuto ?? this.subAuto,
      );

  Map<String, Object?> toJson() => {
        'skip': skipSeconds,
        'resume': resumeMode.name,
        'dtSkip': doubleTapSkip,
        'gest': gestures,
        'gSeek': seekGesture,
        'gBright': brightnessGesture,
        'gVol': volumeGesture,
        'pinch': pinchZoom,
        'lpSpeed': longPressSpeed,
        'lpRate': longPressRate,
        'left': leftHanded,
        'sens': sensitivity,
        'aspect': defaultAspect.name,
        'orient': orientation.name,
        'next': autoNext,
        'awake': keepScreenOn,
        'hide': controlsHideSeconds,
        'sSize': subSize,
        'sColor': subColor,
        'sOutline': subOutline,
        'sBg': subBackground,
        'sBottom': subBottom,
        'sAuto': subAuto,
      };

  static VideoSettings fromJson(Object? raw) {
    if (raw is! Map) return const VideoSettings();
    const d = VideoSettings();
    int i(String k, int def, int lo, int hi) {
      final v = raw[k];
      return v is num ? v.toInt().clamp(lo, hi) : def;
    }

    double dbl(String k, double def, double lo, double hi) {
      final v = raw[k];
      return v is num ? v.toDouble().clamp(lo, hi) : def;
    }

    bool b(String k, bool def) => raw[k] is bool ? raw[k] as bool : def;
    return VideoSettings(
      skipSeconds: i('skip', d.skipSeconds, 3, 120),
      resumeMode: _enumByName(ResumeMode.values, raw['resume'], d.resumeMode),
      doubleTapSkip: b('dtSkip', d.doubleTapSkip),
      gestures: b('gest', d.gestures),
      seekGesture: b('gSeek', d.seekGesture),
      brightnessGesture: b('gBright', d.brightnessGesture),
      volumeGesture: b('gVol', d.volumeGesture),
      pinchZoom: b('pinch', d.pinchZoom),
      longPressSpeed: b('lpSpeed', d.longPressSpeed),
      longPressRate: dbl('lpRate', d.longPressRate, 1.25, 4.0),
      leftHanded: b('left', d.leftHanded),
      sensitivity: dbl('sens', d.sensitivity, 0.4, 2.5),
      defaultAspect: _enumByName(AspectMode.values, raw['aspect'], d.defaultAspect),
      orientation: _enumByName(OrientationMode.values, raw['orient'], d.orientation),
      autoNext: b('next', d.autoNext),
      keepScreenOn: b('awake', d.keepScreenOn),
      controlsHideSeconds: i('hide', d.controlsHideSeconds, 2, 15),
      subSize: i('sSize', d.subSize, 12, 48),
      subColor: i('sColor', d.subColor, 0, subtitleColors.length - 1),
      subOutline: b('sOutline', d.subOutline),
      subBackground: b('sBg', d.subBackground),
      subBottom: i('sBottom', d.subBottom, 0, 200),
      subAuto: b('sAuto', d.subAuto),
    );
  }
}

/// What we remember about one video (resume point, subtitle choice).
class VideoRecord {
  const VideoRecord({this.positionMs = 0, this.durationMs = 0, required this.lastPlayed, this.subtitle, this.subDelayMs = 0});

  final int positionMs;
  final int durationMs;
  final DateTime lastPlayed;
  final String? subtitle;
  final int subDelayMs;

  double get progress => durationMs <= 0 ? 0 : (positionMs / durationMs).clamp(0.0, 1.0);

  Map<String, Object?> toJson() => {
        'p': positionMs,
        'd': durationMs,
        'l': lastPlayed.millisecondsSinceEpoch,
        if (subtitle != null) 's': subtitle,
        if (subDelayMs != 0) 'sd': subDelayMs,
      };

  static VideoRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final l = raw['l'];
    if (l is! num) return null;
    int n(Object? v) => v is num ? v.toInt() : 0;
    return VideoRecord(
      positionMs: n(raw['p']),
      durationMs: n(raw['d']),
      lastPlayed: DateTime.fromMillisecondsSinceEpoch(l.toInt()),
      subtitle: raw['s'] as String?,
      subDelayMs: n(raw['sd']),
    );
  }
}

/// Keeps the [max] most recently played records.
Map<String, VideoRecord> trimHistory(Map<String, VideoRecord> all, {int max = 300}) {
  if (all.length <= max) return all;
  final entries = all.entries.toList()..sort((a, b) => b.value.lastPlayed.compareTo(a.value.lastPlayed));
  return {for (final e in entries.take(max)) e.key: e.value};
}

/// Where to continue: null = start from the beginning (too early, or already (almost) finished).
Duration? resumePoint(Duration position, Duration duration) {
  if (duration <= Duration.zero) return null;
  if (position < const Duration(seconds: 10)) return null;
  if (position > duration - const Duration(seconds: 10)) return null;
  return position;
}

// ------------------------------------------------------------------ gestures + display math

/// Horizontal swipe -> seek distance. A swipe over the whole width covers 30 to 180 seconds
/// (a quarter of the video, at most 3 minutes), scaled by [sensitivity].
int seekDeltaMs(double dx, double width, int durationMs, double sensitivity) {
  if (width <= 0 || durationMs <= 0) return 0;
  final span = (durationMs * 0.25).clamp(30000.0, 180000.0);
  return (dx / width * span * sensitivity).round();
}

/// Vertical swipe -> new brightness/volume (0..1). Swipe up = more.
double adjustFraction(double start, double dy, double height, double sensitivity) {
  if (height <= 0) return start;
  return (start - dy / height * 1.1 * sensitivity).clamp(0.0, 1.0);
}

/// Size of the video picture for an aspect mode, before zoom.
(double, double) displaySizeFor(
  AspectMode mode, {
  required double videoW,
  required double videoH,
  required double boxW,
  required double boxH,
  double devicePixelRatio = 1,
}) {
  if (videoW <= 0 || videoH <= 0 || boxW <= 0 || boxH <= 0) return (boxW, boxH);
  (double, double) fitRatio(double r) => boxW / boxH > r ? (boxH * r, boxH) : (boxW, boxW / r);
  switch (mode) {
    case AspectMode.fit:
      final s = math.min(boxW / videoW, boxH / videoH);
      return (videoW * s, videoH * s);
    case AspectMode.fill:
      final s = math.max(boxW / videoW, boxH / videoH);
      return (videoW * s, videoH * s);
    case AspectMode.stretch:
      return (boxW, boxH);
    case AspectMode.original:
      return (videoW / devicePixelRatio, videoH / devicePixelRatio);
    case AspectMode.r16x9:
      return fitRatio(16 / 9);
    case AspectMode.r4x3:
      return fitRatio(4 / 3);
  }
}

/// Keeps a zoomed picture covering the screen: pan can never show an empty edge.
(double, double) clampPan(
  double dx,
  double dy, {
  required double contentW,
  required double contentH,
  required double boxW,
  required double boxH,
  required double scale,
}) {
  final maxX = math.max(0.0, (contentW * scale - boxW) / 2);
  final maxY = math.max(0.0, (contentH * scale - boxH) / 2);
  return (dx.clamp(-maxX, maxX), dy.clamp(-maxY, maxY));
}

// ------------------------------------------------------------------ queue

/// Play order of a folder queue. Not shuffled = 0..n-1.
List<int> buildOrder(int length, {required bool shuffle, required int first, int seed = 0}) {
  final order = List<int>.generate(length, (i) => i);
  if (!shuffle || length < 2) return order;
  final rest = order.where((i) => i != first).toList()..shuffle(math.Random(seed));
  return [first, ...rest];
}

/// Next index in [order] after [current]; wraps when [wrap]; null at the end.
int? nextInOrder(List<int> order, int current, {required bool wrap}) {
  final pos = order.indexOf(current);
  if (pos < 0 || order.isEmpty) return null;
  if (pos + 1 < order.length) return order[pos + 1];
  return wrap ? order.first : null;
}

int? previousInOrder(List<int> order, int current, {required bool wrap}) {
  final pos = order.indexOf(current);
  if (pos < 0 || order.isEmpty) return null;
  if (pos > 0) return order[pos - 1];
  return wrap ? order.last : null;
}

// ------------------------------------------------------------------ sidecar subtitles

const _subExts = {'srt', 'vtt', 'ass', 'ssa'};

/// Subtitle files next to a video: `movie.srt`, `movie.en.srt`, `movie.gu.vtt` ... (exact name first).
List<String> findSidecarNames(String videoFileName, Iterable<String> siblingNames) {
  final base = p.basenameWithoutExtension(videoFileName).toLowerCase();
  final exact = <String>[];
  final tagged = <String>[];
  for (final n in siblingNames) {
    final lower = n.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot <= 0) continue;
    if (!_subExts.contains(lower.substring(dot + 1))) continue;
    final stem = lower.substring(0, dot);
    if (stem == base) {
      exact.add(n);
    } else if (stem.startsWith('$base.')) {
      tagged.add(n);
    }
  }
  exact.sort();
  tagged.sort();
  return [...exact, ...tagged];
}

const _languageNames = {
  'en': 'English',
  'gu': 'Gujarati',
  'hi': 'Hindi',
  'mr': 'Marathi',
  'ta': 'Tamil',
  'te': 'Telugu',
  'bn': 'Bengali',
  'ur': 'Urdu',
  'es': 'Spanish',
  'fr': 'French',
  'de': 'German',
  'it': 'Italian',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'ar': 'Arabic',
  'ja': 'Japanese',
  'ko': 'Korean',
  'zh': 'Chinese',
};

/// "Gujarati" for `movie.gu.srt`, "Default" for `movie.srt`.
String sidecarLabel(String subtitleFileName, String videoFileName) {
  final base = p.basenameWithoutExtension(videoFileName).toLowerCase();
  final lower = subtitleFileName.toLowerCase();
  final dot = lower.lastIndexOf('.');
  final stem = dot > 0 ? lower.substring(0, dot) : lower;
  if (stem == base) return 'Default';
  final tag = stem.startsWith('$base.') ? stem.substring(base.length + 1) : stem;
  final first = tag.split('.').first;
  final name = _languageNames[first];
  final extra = tag.contains('.') ? ' (${tag.substring(first.length + 1)})' : '';
  return name != null ? '$name$extra' : tag.toUpperCase();
}

// ------------------------------------------------------------------ labels

/// "video/hevc" -> "HEVC (H.265)". Unknown types are shown as they are.
String codecLabel(String mime) {
  switch (mime.toLowerCase()) {
    case 'video/avc':
      return 'H.264 (AVC)';
    case 'video/hevc':
      return 'H.265 (HEVC)';
    case 'video/x-vnd.on2.vp9':
      return 'VP9';
    case 'video/x-vnd.on2.vp8':
      return 'VP8';
    case 'video/av01':
      return 'AV1';
    case 'video/mp4v-es':
      return 'MPEG-4';
    case 'video/mpeg2':
      return 'MPEG-2';
    case 'video/3gpp':
      return 'H.263';
    case 'video/dolby-vision':
      return 'Dolby Vision';
    case 'audio/mp4a-latm':
      return 'AAC';
    case 'audio/mpeg':
      return 'MP3';
    case 'audio/opus':
      return 'Opus';
    case 'audio/vorbis':
      return 'Vorbis';
    case 'audio/flac':
      return 'FLAC';
    case 'audio/ac3':
      return 'Dolby Digital (AC-3)';
    case 'audio/eac3':
      return 'Dolby Digital Plus (E-AC-3)';
    case 'audio/raw':
      return 'PCM';
    case 'audio/3gpp':
      return 'AMR-NB';
    case 'audio/amr-wb':
      return 'AMR-WB';
    case 'audio/vnd.dts':
    case 'audio/vnd.dts.hd':
      return 'DTS';
  }
  final i = mime.indexOf('/');
  return i >= 0 ? mime.substring(i + 1) : mime;
}

/// 83 -> "1:23", 3725 -> "1:02:05"
String formatClock(Duration d) {
  final neg = d.isNegative;
  final x = neg ? -d : d;
  final h = x.inHours;
  final m = x.inMinutes.remainder(60);
  final s = x.inSeconds.remainder(60);
  final body = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '${x.inMinutes}:${s.toString().padLeft(2, '0')}';
  return neg ? '-$body' : body;
}
