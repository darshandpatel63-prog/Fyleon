import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../core/utils/archive_utils.dart';

// ---------------------------------------------------------------- data model
// Only plain data (numbers, strings, lists, bytes) so it can cross isolates.

class PptxRun {
  const PptxRun(this.text, this.sizePt, this.color, {this.bold = false, this.italic = false, this.underline = false});
  final String text;
  final double sizePt;
  final int color; // 0xAARRGGBB
  final bool bold;
  final bool italic;
  final bool underline;
}

class PptxPara {
  const PptxPara(this.runs, this.align, this.bullet, this.level);
  final List<PptxRun> runs;
  final String align; // l, ctr, r, just
  final bool bullet;
  final int level;
}

class PptxShape {
  const PptxShape({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rot = 0,
    this.fill,
    this.lineColor,
    this.lineW = 0,
    this.geom = 'rect',
    this.paras = const [],
    this.anchor = 't',
    this.insets = const [91440, 45720, 91440, 45720],
    this.image,
    this.table,
  });
  final double x, y, w, h; // EMU
  final double rot; // degrees
  final int? fill;
  final int? lineColor;
  final double lineW; // EMU
  final String geom;
  final List<PptxPara> paras;
  final String anchor; // t, ctr, b
  final List<double> insets; // l, t, r, b in EMU
  final Uint8List? image;
  final List<List<String>>? table;
}

class PptxSlide {
  const PptxSlide(this.background, this.shapes);
  final int background;
  final List<PptxShape> shapes;
}

class PptxDeck {
  const PptxDeck(this.cx, this.cy, this.slides);
  final double cx, cy; // slide size in EMU
  final List<PptxSlide> slides;
}

// ---------------------------------------------------------------- xml helpers

Iterable<XmlElement> _kids(XmlElement e, String local) =>
    e.children.whereType<XmlElement>().where((c) => c.name.local == local);

XmlElement? _kid(XmlElement? e, String local) => e == null ? null : _kids(e, local).firstOrNull;

XmlElement? _path(XmlElement? e, List<String> locals) {
  var cur = e;
  for (final l in locals) {
    cur = _kid(cur, l);
    if (cur == null) return null;
  }
  return cur;
}

Iterable<XmlElement> _desc(XmlNode n, String local) =>
    n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

double? _num(String? s) => s == null ? null : double.tryParse(s);

// ---------------------------------------------------------------- colors

class _Theme {
  final Map<String, int> scheme = {}; // dk1, lt1, accent1...
  final Map<String, String> clrMap = {'bg1': 'lt1', 'tx1': 'dk1', 'bg2': 'lt2', 'tx2': 'dk2'};
  double titlePt = 40;
  double bodyPt = 24;

  int named(String n) {
    final mapped = clrMap[n] ?? n;
    return scheme[mapped] ?? (mapped == 'lt1' ? 0xFFFFFFFF : 0xFF000000);
  }
}

int _rgb(int r, int g, int b) => 0xFF000000 | (r.clamp(0, 255) << 16) | (g.clamp(0, 255) << 8) | b.clamp(0, 255);

int _applyLum(int c, double mod, double off) {
  final r = ((c >> 16) & 255) / 255, g = ((c >> 8) & 255) / 255, b = (c & 255) / 255;
  final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
  var l = (mx + mn) / 2;
  double h = 0, s = 0;
  if (mx != mn) {
    final d = mx - mn;
    s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    if (mx == r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h /= 6;
  }
  l = (l * mod + off).clamp(0.0, 1.0);
  double f(double p0, double q, double t0) {
    var t = t0;
    if (t < 0) t += 1;
    if (t > 1) t -= 1;
    if (t < 1 / 6) return p0 + (q - p0) * 6 * t;
    if (t < 1 / 2) return q;
    if (t < 2 / 3) return p0 + (q - p0) * (2 / 3 - t) * 6;
    return p0;
  }

  double rr, gg, bb;
  if (s == 0) {
    rr = gg = bb = l;
  } else {
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p0 = 2 * l - q;
    rr = f(p0, q, h + 1 / 3);
    gg = f(p0, q, h);
    bb = f(p0, q, h - 1 / 3);
  }
  return _rgb((rr * 255).round(), (gg * 255).round(), (bb * 255).round());
}

/// Reads a solidFill-like parent element: finds the srgbClr, schemeClr or sysClr child.
int? _colorOf(XmlElement? parent, _Theme theme, {int? phColor}) {
  if (parent == null) return null;
  XmlElement? c;
  for (final k in parent.children.whereType<XmlElement>()) {
    final n = k.name.local;
    if (n == 'srgbClr' || n == 'schemeClr' || n == 'sysClr' || n == 'prstClr') {
      c = k;
      break;
    }
  }
  if (c == null) return null;
  int base;
  switch (c.name.local) {
    case 'srgbClr':
      base = 0xFF000000 | (int.tryParse(c.getAttribute('val') ?? '000000', radix: 16) ?? 0);
      break;
    case 'sysClr':
      base = 0xFF000000 | (int.tryParse(c.getAttribute('lastClr') ?? '000000', radix: 16) ?? 0);
      break;
    case 'prstClr':
      base = (c.getAttribute('val') ?? '') == 'white' ? 0xFFFFFFFF : 0xFF000000;
      break;
    default:
      final v = c.getAttribute('val') ?? 'tx1';
      base = (v == 'phClr' && phColor != null) ? phColor : theme.named(v);
  }
  var mod = 1.0, off = 0.0;
  for (final m in c.children.whereType<XmlElement>()) {
    final v = (_num(m.getAttribute('val')) ?? 100000) / 100000;
    switch (m.name.local) {
      case 'lumMod':
        mod = v;
        break;
      case 'lumOff':
        off = v;
        break;
      case 'shade':
        base = _rgb((((base >> 16) & 255) * v).round(), (((base >> 8) & 255) * v).round(), ((base & 255) * v).round());
        break;
      case 'tint':
        int t(int x) => (x + (255 - x) * (1 - v)).round();
        base = _rgb(t((base >> 16) & 255), t((base >> 8) & 255), t(base & 255));
        break;
    }
  }
  if (mod != 1.0 || off != 0.0) base = _applyLum(base, mod, off);
  return base;
}

/// solidFill / gradFill(first stop) / noFill inside a shape-properties element.
/// Returns (hasFillElement, color).
(bool, int?) _fillOf(XmlElement? spPr, _Theme theme, {int? phColor}) {
  if (spPr == null) return (false, null);
  for (final k in spPr.children.whereType<XmlElement>()) {
    switch (k.name.local) {
      case 'noFill':
        return (true, null);
      case 'solidFill':
        return (true, _colorOf(k, theme, phColor: phColor));
      case 'gradFill':
        final gs = _desc(k, 'gs').firstOrNull;
        return (true, _colorOf(gs, theme, phColor: phColor));
      case 'blipFill':
      case 'pattFill':
        return (true, null);
    }
  }
  return (false, null);
}

// ---------------------------------------------------------------- context

class _Xf {
  const _Xf(this.sx, this.sy, this.tx, this.ty);
  final double sx, sy, tx, ty;
  static const identity = _Xf(1, 1, 0, 0);
}

class _Ctx {
  _Ctx(this.theme, this.rels, this.sourcePath, this.files, this.media, this.isSlide, this.layoutDoc, this.masterDoc, this.slideW, this.slideH);
  final _Theme theme;
  final Map<String, String> rels; // rId -> resolved path
  final String sourcePath;
  final Map<String, ArchiveFile> files;
  final Map<String, Uint8List> media;
  final bool isSlide;
  final XmlDocument? layoutDoc;
  final XmlDocument? masterDoc;
  final double slideW, slideH;
}

// ---------------------------------------------------------------- main entry

/// Runs in an isolate (top-level). Draws slides approximately (shapes, colors, text, pictures).
PptxDeck parsePptx(String path) {
  final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  final files = <String, ArchiveFile>{
    for (final f in archive.files)
      if (f.isFile) f.name: f,
  };
  String? read(String n) {
    final f = files[n];
    return f == null ? null : utf8.decode(archiveFileBytes(f), allowMalformed: true);
  }

  XmlDocument? doc(String n) {
    final t = read(n);
    if (t == null) return null;
    try {
      return XmlDocument.parse(t);
    } catch (_) {
      return null;
    }
  }

  final presentation = doc('ppt/presentation.xml');
  if (presentation == null) throw const FormatException('Not a valid PPTX file.');

  final sz = _desc(presentation, 'sldSz').firstOrNull;
  final cx = _num(sz?.getAttribute('cx')) ?? 9144000;
  final cy = _num(sz?.getAttribute('cy')) ?? 5143500;

  // ---- theme + master defaults
  final theme = _Theme();
  final themeDoc = doc('ppt/theme/theme1.xml');
  if (themeDoc != null) {
    final scheme = _desc(themeDoc, 'clrScheme').firstOrNull;
    if (scheme != null) {
      for (final c in scheme.children.whereType<XmlElement>()) {
        final inner = c.children.whereType<XmlElement>().firstOrNull;
        if (inner == null) continue;
        final hex = inner.getAttribute('val') ?? inner.getAttribute('lastClr');
        final v = int.tryParse(hex ?? '', radix: 16);
        if (v != null && hex!.length == 6) theme.scheme[c.name.local] = 0xFF000000 | v;
      }
    }
  }
  final masterPath = files.keys.where((n) => RegExp(r'^ppt/slideMasters/slideMaster\d+\.xml$').hasMatch(n)).toList()..sort();
  final defaultMaster = masterPath.isEmpty ? null : doc(masterPath.first);
  if (defaultMaster != null) {
    final cm = _desc(defaultMaster, 'clrMap').firstOrNull;
    if (cm != null) {
      for (final a in cm.attributes) {
        theme.clrMap[a.name.local] = a.value;
      }
    }
    double? szOf(String style) {
      final st = _desc(defaultMaster, style).firstOrNull;
      final def = _path(_kid(st, 'lvl1pPr'), ['defRPr']);
      final v = _num(def?.getAttribute('sz'));
      return v == null ? null : v / 100;
    }

    theme.titlePt = szOf('titleStyle') ?? 40;
    theme.bodyPt = szOf('bodyStyle') ?? 24;
  }

  // ---- slide order
  final rels = _readRels(read('ppt/_rels/presentation.xml.rels'), 'ppt/presentation.xml');
  var slidePaths = <String>[];
  for (final id in _desc(presentation, 'sldId')) {
    final rid = id.getAttribute('r:id');
    final target = rid == null ? null : rels[rid];
    if (target != null && files.containsKey(target)) slidePaths.add(target);
  }
  if (slidePaths.isEmpty) {
    slidePaths = files.keys.where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n)).toList()
      ..sort((a, b) => _slideNo(a).compareTo(_slideNo(b)));
  }
  if (slidePaths.isEmpty) throw const FormatException('This presentation has no slides.');

  final media = <String, Uint8List>{};
  final slides = <PptxSlide>[];
  for (final sp in slidePaths) {
    final sdoc = doc(sp);
    if (sdoc == null) continue;
    final srels = _readRels(read(_relsPath(sp)), sp);
    final layoutPath = _relOfType(read(_relsPath(sp)), sp, 'slideLayout');
    final layoutDoc = layoutPath == null ? null : doc(layoutPath);
    final lrels = layoutPath == null ? <String, String>{} : _readRels(read(_relsPath(layoutPath)), layoutPath);
    final mp = layoutPath == null ? null : _relOfType(read(_relsPath(layoutPath)), layoutPath, 'slideMaster');
    final masterDoc = (mp == null ? null : doc(mp)) ?? defaultMaster;
    final mrels = mp == null ? <String, String>{} : _readRels(read(_relsPath(mp)), mp);

    // background: slide -> layout -> master -> theme bg1
    int bg = _bgOf(sdoc, theme) ?? (layoutDoc == null ? null : _bgOf(layoutDoc, theme)) ?? (masterDoc == null ? null : _bgOf(masterDoc, theme)) ?? theme.named('bg1');

    final shapes = <PptxShape>[];
    if (masterDoc != null) {
      final tree = _desc(masterDoc, 'spTree').firstOrNull;
      if (tree != null) {
        shapes.addAll(_collect(tree, _Ctx(theme, mrels, mp ?? '', files, media, false, null, null, cx, cy), _Xf.identity));
      }
    }
    if (layoutDoc != null) {
      final tree = _desc(layoutDoc, 'spTree').firstOrNull;
      if (tree != null) {
        shapes.addAll(_collect(tree, _Ctx(theme, lrels, layoutPath ?? '', files, media, false, null, null, cx, cy), _Xf.identity));
      }
    }
    final stree = _desc(sdoc, 'spTree').firstOrNull;
    if (stree != null) {
      shapes.addAll(_collect(stree, _Ctx(theme, srels, sp, files, media, true, layoutDoc, masterDoc, cx, cy), _Xf.identity));
    }
    slides.add(PptxSlide(bg, shapes));
  }
  return PptxDeck(cx, cy, slides);
}

int _slideNo(String n) => int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(n)?.group(1) ?? '') ?? 0;

String _relsPath(String part) => '${p.posix.dirname(part)}/_rels/${p.posix.basename(part)}.rels';

String _resolve(String sourcePart, String target) {
  if (target.startsWith('/')) return target.substring(1);
  return p.posix.normalize(p.posix.join(p.posix.dirname(sourcePart), target));
}

Map<String, String> _readRels(String? xml, String sourcePart) {
  final out = <String, String>{};
  if (xml == null) return out;
  try {
    for (final r in _desc(XmlDocument.parse(xml), 'Relationship')) {
      final id = r.getAttribute('Id');
      final t = r.getAttribute('Target');
      if (id != null && t != null && r.getAttribute('TargetMode') != 'External') out[id] = _resolve(sourcePart, t);
    }
  } catch (_) {}
  return out;
}

String? _relOfType(String? xml, String sourcePart, String typeEnd) {
  if (xml == null) return null;
  try {
    for (final r in _desc(XmlDocument.parse(xml), 'Relationship')) {
      final type = r.getAttribute('Type') ?? '';
      final t = r.getAttribute('Target');
      if (t != null && type.endsWith('/$typeEnd')) return _resolve(sourcePart, t);
    }
  } catch (_) {}
  return null;
}

int? _bgOf(XmlDocument d, _Theme theme) {
  final bg = _desc(d, 'bg').firstOrNull;
  if (bg == null) return null;
  final props = _kid(bg, 'bgPr');
  if (props != null) {
    final (has, c) = _fillOf(props, theme);
    if (has) return c;
  }
  final ref = _kid(bg, 'bgRef');
  if (ref != null) return _colorOf(ref, theme);
  return null;
}

// ---------------------------------------------------------------- shapes

class _Rect {
  const _Rect(this.x, this.y, this.w, this.h, this.rot);
  final double x, y, w, h, rot;
}

_Rect? _xfrmOf(XmlElement? xfrm, _Xf t) {
  if (xfrm == null) return null;
  final off = _kid(xfrm, 'off');
  final ext = _kid(xfrm, 'ext');
  if (off == null || ext == null) return null;
  final x = _num(off.getAttribute('x')) ?? 0, y = _num(off.getAttribute('y')) ?? 0;
  final w = _num(ext.getAttribute('cx')) ?? 0, h = _num(ext.getAttribute('cy')) ?? 0;
  final rot = (_num(xfrm.getAttribute('rot')) ?? 0) / 60000;
  return _Rect(x * t.sx + t.tx, y * t.sy + t.ty, w * t.sx, h * t.sy, rot);
}

List<PptxShape> _collect(XmlElement tree, _Ctx ctx, _Xf t) {
  final out = <PptxShape>[];
  for (final e in tree.children.whereType<XmlElement>()) {
    switch (e.name.local) {
      case 'sp':
        final s = _sp(e, ctx, t);
        if (s != null) out.add(s);
        break;
      case 'cxnSp':
        final s = _cxn(e, ctx, t);
        if (s != null) out.add(s);
        break;
      case 'pic':
        final s = _pic(e, ctx, t);
        if (s != null) out.add(s);
        break;
      case 'graphicFrame':
        final s = _frame(e, ctx, t);
        if (s != null) out.add(s);
        break;
      case 'grpSp':
        final gx = _path(e, ['grpSpPr', 'xfrm']);
        final off = _kid(gx, 'off'), ext = _kid(gx, 'ext'), choff = _kid(gx, 'chOff'), chext = _kid(gx, 'chExt');
        if (off == null || ext == null || choff == null || chext == null) {
          out.addAll(_collect(e, ctx, t));
          break;
        }
        final cw = _num(chext.getAttribute('cx')) ?? 1, ch = _num(chext.getAttribute('cy')) ?? 1;
        final gw = _num(ext.getAttribute('cx')) ?? cw, gh = _num(ext.getAttribute('cy')) ?? ch;
        final fx = cw == 0 ? 1.0 : gw / cw, fy = ch == 0 ? 1.0 : gh / ch;
        final ox = _num(off.getAttribute('x')) ?? 0, oy = _num(off.getAttribute('y')) ?? 0;
        final cx0 = _num(choff.getAttribute('x')) ?? 0, cy0 = _num(choff.getAttribute('y')) ?? 0;
        final nt = _Xf(fx * t.sx, fy * t.sy, t.sx * (ox - cx0 * fx) + t.tx, t.sy * (oy - cy0 * fy) + t.ty);
        out.addAll(_collect(e, ctx, nt));
        break;
    }
  }
  return out;
}

class _Ph {
  const _Ph(this.type, this.idx);
  final String? type;
  final String? idx;
}

_Ph? _phOf(XmlElement sp) {
  final ph = _path(sp, ['nvSpPr', 'nvPr', 'ph']);
  if (ph == null) return null;
  return _Ph(ph.getAttribute('type'), ph.getAttribute('idx'));
}

XmlElement? _findPlaceholder(XmlDocument? d, _Ph ph) {
  if (d == null) return null;
  XmlElement? byType;
  for (final sp in _desc(d, 'sp')) {
    final c = _phOf(sp);
    if (c == null) continue;
    if (ph.idx != null && c.idx == ph.idx) return sp;
    if (ph.type != null && c.type == ph.type) byType ??= sp;
  }
  if (byType != null) return byType;
  // slide "ctrTitle" <-> layout/master "title"; "subTitle"/others <-> "body"
  final alt = (ph.type == 'ctrTitle') ? 'title' : ((ph.type == 'subTitle' || ph.type == null || ph.type == 'obj') ? 'body' : null);
  if (alt != null) {
    for (final sp in _desc(d, 'sp')) {
      final c = _phOf(sp);
      if (c != null && c.type == alt) return sp;
    }
  }
  return null;
}

_Rect? _inheritedRect(_Ph ph, _Ctx ctx) {
  for (final d in [ctx.layoutDoc, ctx.masterDoc]) {
    final sp = _findPlaceholder(d, ph);
    final r = _xfrmOf(_path(sp, ['spPr', 'xfrm']), _Xf.identity);
    if (r != null) return r;
  }
  final w = ctx.slideW, h = ctx.slideH;
  if (ph.type == 'title' || ph.type == 'ctrTitle') return _Rect(w * 0.08, h * 0.06, w * 0.84, h * 0.2, 0);
  if (ph.type == 'subTitle') return _Rect(w * 0.12, h * 0.45, w * 0.76, h * 0.2, 0);
  return _Rect(w * 0.08, h * 0.28, w * 0.84, h * 0.62, 0);
}

PptxShape? _sp(XmlElement sp, _Ctx ctx, _Xf t) {
  final ph = _phOf(sp);
  if (ph != null && !ctx.isSlide) return null; // layout/master prompt text is not drawn
  final spPr = _kid(sp, 'spPr');
  var rect = _xfrmOf(_kid(spPr, 'xfrm'), t);
  if (rect == null && ph != null) {
    final r = _inheritedRect(ph, ctx);
    if (r != null) rect = _Rect(r.x * t.sx + t.tx, r.y * t.sy + t.ty, r.w * t.sx, r.h * t.sy, 0);
  }
  if (rect == null) return null;

  final style = _kid(sp, 'style');
  final fillRef = _kid(style, 'fillRef');
  final lnRef = _kid(style, 'lnRef');
  final fontRef = _kid(style, 'fontRef');
  final styleFill = (fillRef != null && (fillRef.getAttribute('idx') ?? '0') != '0') ? _colorOf(fillRef, ctx.theme) : null;
  final styleLine = (lnRef != null && (lnRef.getAttribute('idx') ?? '0') != '0') ? _colorOf(lnRef, ctx.theme) : null;
  final fontRefColor = _colorOf(fontRef, ctx.theme);

  final (hasFill, fillColor) = _fillOf(spPr, ctx.theme, phColor: styleFill);
  final fill = hasFill ? fillColor : styleFill;

  final ln = _kid(spPr, 'ln');
  int? lineColor = styleLine;
  double lineW = styleLine != null ? 12700 : 0;
  if (ln != null) {
    final (hasLn, lc) = _fillOf(ln, ctx.theme, phColor: styleLine);
    if (hasLn) lineColor = lc;
    final w = _num(ln.getAttribute('w'));
    if (w != null) lineW = w;
    if (lineColor == null) lineW = 0;
  }

  final geom = _kid(spPr, 'prstGeom')?.getAttribute('prst') ?? 'rect';
  final txBody = _kid(sp, 'txBody');
  final bodyPr = _kid(txBody, 'bodyPr');
  final fontScale = (_num(_kid(bodyPr, 'normAutofit')?.getAttribute('fontScale')) ?? 100000) / 100000;
  double ins(String a, double d) => _num(bodyPr?.getAttribute(a)) ?? d;

  final paras = txBody == null ? <PptxPara>[] : _paragraphs(txBody, ctx, ph, fontScale, fontRefColor);

  if (fill == null && lineW == 0 && paras.isEmpty) return null;
  return PptxShape(
    x: rect.x,
    y: rect.y,
    w: rect.w,
    h: rect.h,
    rot: rect.rot,
    fill: fill,
    lineColor: lineColor,
    lineW: lineW,
    geom: geom,
    paras: paras,
    anchor: bodyPr?.getAttribute('anchor') ?? ((ph?.type == 'ctrTitle' || ph?.type == 'title') ? 'ctr' : 't'),
    insets: [ins('lIns', 91440), ins('tIns', 45720), ins('rIns', 91440), ins('bIns', 45720)],
  );
}

PptxShape? _cxn(XmlElement e, _Ctx ctx, _Xf t) {
  final spPr = _kid(e, 'spPr');
  final rect = _xfrmOf(_kid(spPr, 'xfrm'), t);
  if (rect == null) return null;
  final style = _kid(e, 'style');
  final styleLine = _colorOf(_kid(style, 'lnRef'), ctx.theme);
  final ln = _kid(spPr, 'ln');
  var color = styleLine;
  final (has, c) = _fillOf(ln, ctx.theme, phColor: styleLine);
  if (has) color = c;
  final w = _num(ln?.getAttribute('w')) ?? 12700;
  if (color == null) return null;
  return PptxShape(x: rect.x, y: rect.y, w: rect.w, h: rect.h, rot: rect.rot, lineColor: color, lineW: w, geom: 'line');
}

PptxShape? _pic(XmlElement e, _Ctx ctx, _Xf t) {
  final rect = _xfrmOf(_path(e, ['spPr', 'xfrm']), t);
  if (rect == null) return null;
  final blip = _desc(e, 'blip').firstOrNull;
  final rid = blip?.getAttribute('r:embed');
  final target = rid == null ? null : ctx.rels[rid];
  if (target == null) return null;
  final ext = p.posix.extension(target).toLowerCase();
  if (!const {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'}.contains(ext)) return null;
  var bytes = ctx.media[target];
  if (bytes == null) {
    final f = ctx.files[target];
    if (f == null) return null;
    final raw = archiveFileBytes(f);
    if (raw.length > 8 * 1024 * 1024) return null;
    bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
    ctx.media[target] = bytes;
  }
  return PptxShape(x: rect.x, y: rect.y, w: rect.w, h: rect.h, rot: rect.rot, image: bytes);
}

PptxShape? _frame(XmlElement e, _Ctx ctx, _Xf t) {
  final rect = _xfrmOf(_kid(e, 'xfrm'), t);
  if (rect == null) return null;
  final tbl = _desc(e, 'tbl').firstOrNull;
  if (tbl == null) return null;
  final rows = <List<String>>[];
  for (final tr in _kids(tbl, 'tr')) {
    final cells = <String>[];
    for (final tc in _kids(tr, 'tc')) {
      cells.add(_desc(tc, 'p').map((pp) => _desc(pp, 't').map((x) => x.innerText).join()).where((s) => s.isNotEmpty).join('\n'));
    }
    rows.add(cells);
  }
  if (rows.isEmpty) return null;
  return PptxShape(x: rect.x, y: rect.y, w: rect.w, h: rect.h, table: rows);
}

List<PptxPara> _paragraphs(XmlElement txBody, _Ctx ctx, _Ph? ph, double fontScale, int? fontRefColor) {
  final theme = ctx.theme;
  final isTitle = ph?.type == 'title' || ph?.type == 'ctrTitle';
  final isSubtitle = ph?.type == 'subTitle';
  final isBody = ph != null && !isTitle && !isSubtitle;
  final defaultColor = fontRefColor ?? theme.named('tx1');

  final out = <PptxPara>[];
  for (final para in _kids(txBody, 'p')) {
    final pPr = _kid(para, 'pPr');
    final level = int.tryParse(pPr?.getAttribute('lvl') ?? '0') ?? 0;
    final algn = pPr?.getAttribute('algn') ?? ((ph?.type == 'ctrTitle' || isSubtitle) ? 'ctr' : 'l');
    var bullet = isBody;
    if (_kid(pPr, 'buNone') != null) bullet = false;
    if (_kid(pPr, 'buChar') != null || _kid(pPr, 'buAutoNum') != null) bullet = true;

    double baseSize;
    if (isTitle) {
      baseSize = theme.titlePt;
    } else if (isSubtitle) {
      baseSize = math.min(theme.bodyPt, 28);
    } else if (ph != null) {
      baseSize = theme.bodyPt * math.pow(0.85, level).toDouble();
    } else {
      baseSize = 18;
    }

    final runs = <PptxRun>[];
    for (final r in para.children.whereType<XmlElement>()) {
      final n = r.name.local;
      if (n == 'r' || n == 'fld') {
        final text = _kids(r, 't').map((x) => x.innerText).join();
        if (text.isEmpty) continue;
        runs.add(_run(text, _kid(r, 'rPr'), baseSize, fontScale, defaultColor, theme));
      } else if (n == 'br') {
        runs.add(PptxRun('\n', baseSize * fontScale, defaultColor));
      }
    }
    if (runs.isEmpty) {
      final end = _kid(para, 'endParaRPr');
      final sz = (_num(end?.getAttribute('sz')) ?? baseSize * 100) / 100 * fontScale;
      runs.add(PptxRun(' ', sz, defaultColor));
      bullet = false;
    }
    out.add(PptxPara(runs, algn, bullet, level));
  }
  return out;
}

PptxRun _run(String text, XmlElement? rPr, double baseSize, double fontScale, int defaultColor, _Theme theme) {
  final sz = _num(rPr?.getAttribute('sz'));
  final (has, c) = _fillOf(rPr, theme);
  return PptxRun(
    text,
    (sz != null ? sz / 100 : baseSize) * fontScale,
    (has ? c : null) ?? defaultColor,
    bold: rPr?.getAttribute('b') == '1' || rPr?.getAttribute('b') == 'true',
    italic: rPr?.getAttribute('i') == '1' || rPr?.getAttribute('i') == 'true',
    underline: (rPr?.getAttribute('u') ?? 'none') != 'none',
  );
}
