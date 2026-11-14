import 'dart:convert';
import 'dart:typed_data';

/// One subtitle line (or two) that is visible between [start] and [end].
class SubCue {
  const SubCue(this.start, this.end, this.text);

  final Duration start;
  final Duration end;
  final String text;
}

enum SubFormat { srt, vtt, ass }

const subtitleExtensions = {'srt', 'vtt', 'ass', 'ssa'};

/// Decides the format from the content first, then from the file extension.
SubFormat detectSubFormat(String content, {String? ext}) {
  final c = content.trimLeft();
  if (c.startsWith('WEBVTT')) return SubFormat.vtt;
  if (c.contains('[Script Info]') || RegExp(r'^Dialogue:', multiLine: true).hasMatch(c)) return SubFormat.ass;
  switch ((ext ?? '').toLowerCase()) {
    case 'vtt':
      return SubFormat.vtt;
    case 'ass':
    case 'ssa':
      return SubFormat.ass;
  }
  return SubFormat.srt;
}

/// Text file bytes -> String. Handles UTF-8 (with or without BOM) and UTF-16 with BOM; falls back to Latin-1.
/// [encoding] can force `latin1` for old files.
String decodeSubtitleBytes(Uint8List b, {String encoding = 'auto'}) {
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(b.sublist(3), allowMalformed: true);
  }
  if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
    final little = b[0] == 0xFF;
    final units = <int>[];
    for (var i = 2; i + 1 < b.length; i += 2) {
      units.add(little ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]));
    }
    return String.fromCharCodes(units);
  }
  if (encoding == 'latin1') return latin1.decode(b);
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b);
  }
}

/// "01:02:03,500", "00:03.5", "0:00:01.50" -> Duration (null when it is not a time).
Duration? parseSubTime(String s) {
  final m = RegExp(r'^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?$').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1) ?? '0');
  final mm = int.parse(m.group(2)!);
  final ss = int.parse(m.group(3)!);
  final ms = int.parse((m.group(4) ?? '0').padRight(3, '0'));
  return Duration(hours: h, minutes: mm, seconds: ss, milliseconds: ms);
}

String _clean(String t) {
  var s = t
      .replaceAll(RegExp(r'\{[^}]*\}'), '') // ASS / SRT style overrides like {\an8}
      .replaceAll(RegExp(r'<[^>]*>'), '') // <i> <b> <font ...> <c.yellow> <v Name>
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\h', ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
  s = s.split('\n').map((l) => l.trimRight()).join('\n').trim();
  return s;
}

List<String> _blocks(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n[ \t]*\n'));

List<SubCue> parseSrt(String text) {
  final timeRe = RegExp(r'(\d+:\d{1,2}:\d{1,2}(?:[.,]\d{1,3})?)\s*-->\s*(\d+:\d{1,2}:\d{1,2}(?:[.,]\d{1,3})?)');
  final out = <SubCue>[];
  for (final block in _blocks(text)) {
    final lines = block.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = timeRe.firstMatch(lines[i]);
      if (m == null) continue;
      final a = parseSubTime(m.group(1)!);
      final b = parseSubTime(m.group(2)!);
      final body = _clean(lines.sublist(i + 1).join('\n'));
      if (a != null && b != null && body.isNotEmpty) out.add(SubCue(a, b, body));
      break;
    }
  }
  return out;
}

List<SubCue> parseVtt(String text) {
  final timeRe = RegExp(r'((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})\s*-->\s*((?:\d+:)?\d{1,2}:\d{2}[.,]\d{1,3})');
  final out = <SubCue>[];
  for (final block in _blocks(text)) {
    final first = block.trimLeft();
    if (first.startsWith('WEBVTT') || first.startsWith('NOTE') || first.startsWith('STYLE') || first.startsWith('REGION')) continue;
    final lines = block.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = timeRe.firstMatch(lines[i]);
      if (m == null) continue;
      final a = parseSubTime(m.group(1)!);
      final b = parseSubTime(m.group(2)!);
      final body = _clean(lines.sublist(i + 1).join('\n'));
      if (a != null && b != null && body.isNotEmpty) out.add(SubCue(a, b, body));
      break;
    }
  }
  return out;
}

List<SubCue> parseAss(String text) {
  final out = <SubCue>[];
  var inEvents = false;
  var cols = <String>[];
  for (final raw in text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n')) {
    final line = raw.trim();
    if (line.startsWith('[')) {
      inEvents = line.toLowerCase() == '[events]';
      continue;
    }
    if (!inEvents) continue;
    if (line.startsWith('Format:')) {
      cols = line.substring(7).split(',').map((c) => c.trim().toLowerCase()).toList();
      continue;
    }
    if (!line.startsWith('Dialogue:')) continue;
    final n = cols.isEmpty ? 10 : cols.length;
    final parts = <String>[];
    var rest = line.substring(9).trimLeft();
    for (var i = 0; i < n - 1; i++) {
      final idx = rest.indexOf(',');
      if (idx < 0) break;
      parts.add(rest.substring(0, idx));
      rest = rest.substring(idx + 1);
    }
    parts.add(rest);
    int col(String name, int fallback) {
      final i = cols.indexOf(name);
      return i >= 0 ? i : fallback;
    }

    final si = col('start', 1);
    final ei = col('end', 2);
    final ti = col('text', n - 1);
    if (si >= parts.length || ei >= parts.length || ti >= parts.length) continue;
    final a = parseSubTime(parts[si]);
    final b = parseSubTime(parts[ei]);
    final body = _clean(parts[ti]);
    if (a != null && b != null && body.isNotEmpty) out.add(SubCue(a, b, body));
  }
  return out;
}

/// Parses any supported subtitle text. The result is sorted by start time.
List<SubCue> parseSubtitles(String content, {String? ext}) {
  final text = content.startsWith('\uFEFF') ? content.substring(1) : content;
  final List<SubCue> cues;
  switch (detectSubFormat(text, ext: ext)) {
    case SubFormat.vtt:
      cues = parseVtt(text);
    case SubFormat.ass:
      cues = parseAss(text);
    case SubFormat.srt:
      cues = parseSrt(text);
  }
  final fixed = [
    for (final c in cues) c.end > c.start ? c : SubCue(c.start, c.start + const Duration(seconds: 2), c.text),
  ];
  fixed.sort((a, b) => a.start.compareTo(b.start));
  return fixed;
}

/// Cues visible at [position]. [delay] > 0 shows the subtitles later, < 0 earlier.
List<SubCue> cuesAt(List<SubCue> cues, Duration position, {Duration delay = Duration.zero}) {
  if (cues.isEmpty) return const [];
  final t = position - delay;
  var lo = 0;
  var hi = cues.length - 1;
  var idx = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cues[mid].start <= t) {
      idx = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  final out = <SubCue>[];
  for (var i = idx; i >= 0 && i > idx - 6; i--) {
    if (cues[i].end > t) out.add(cues[i]);
  }
  return out.reversed.toList();
}
