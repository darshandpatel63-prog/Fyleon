import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class DocPara {
  const DocPara(this.text, this.level);
  final String text;

  /// 0 = normal paragraph, 1..6 = heading level
  final int level;
}

class SheetData {
  const SheetData(this.name, this.rows, this.truncated);
  final String name;
  final List<List<String>> rows;
  final bool truncated;
}

class SlideData {
  const SlideData(this.number, this.lines);
  final int number;
  final List<String> lines;
}

class OfficeResult {
  const OfficeResult({
    this.paragraphs = const [],
    this.sheets = const [],
    this.slides = const [],
  });
  final List<DocPara> paragraphs;
  final List<SheetData> sheets;
  final List<SlideData> slides;
}

Iterable<XmlElement> _els(XmlNode n, String local) =>
    n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

const _maxRows = 300;
const _maxCols = 40;

/// Runs in an isolate (top-level). Basic text/table extraction only.
OfficeResult parseOffice(String path) {
  final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  final files = <String, ArchiveFile>{
    for (final f in archive.files)
      if (f.isFile) f.name: f,
  };

  String? read(String name) {
    final f = files[name];
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final ext = p.extension(path).toLowerCase();
  if (ext == '.docx') return _docx(read);
  if (ext == '.xlsx') return _xlsx(read);
  if (ext == '.pptx') return _pptx(read, files.keys);
  throw const FormatException('Unsupported Office format.');
}

OfficeResult _docx(String? Function(String) read) {
  final xml = read('word/document.xml');
  if (xml == null) throw const FormatException('Not a valid DOCX file.');
  final doc = XmlDocument.parse(xml);
  final out = <DocPara>[];
  for (final para in _els(doc, 'p')) {
    final buf = StringBuffer();
    for (final n in para.descendants.whereType<XmlElement>()) {
      switch (n.name.local) {
        case 't':
          buf.write(n.innerText);
          break;
        case 'tab':
          buf.write('\t');
          break;
        case 'br':
          buf.write('\n');
          break;
      }
    }
    var level = 0;
    final style = _els(para, 'pStyle').firstOrNull?.getAttribute('w:val') ?? '';
    final m = RegExp(r'^Heading(\d)$', caseSensitive: false).firstMatch(style);
    if (m != null) {
      level = int.parse(m.group(1)!).clamp(1, 6);
    } else if (style.toLowerCase() == 'title') {
      level = 1;
    }
    final text = buf.toString();
    if (text.trim().isEmpty && out.isNotEmpty && out.last.text.isEmpty) continue;
    out.add(DocPara(text, level));
  }
  return OfficeResult(paragraphs: out);
}

int _colIndex(String ref) {
  var n = 0;
  for (final c in ref.codeUnits) {
    if (c >= 65 && c <= 90) {
      n = n * 26 + (c - 64);
    } else if (c >= 97 && c <= 122) {
      n = n * 26 + (c - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

OfficeResult _xlsx(String? Function(String) read) {
  final workbookXml = read('xl/workbook.xml');
  if (workbookXml == null) throw const FormatException('Not a valid XLSX file.');

  final shared = <String>[];
  final ssXml = read('xl/sharedStrings.xml');
  if (ssXml != null) {
    for (final si in _els(XmlDocument.parse(ssXml), 'si')) {
      shared.add(_els(si, 't').map((t) => t.innerText).join());
    }
  }

  final rels = <String, String>{};
  final relsXml = read('xl/_rels/workbook.xml.rels');
  if (relsXml != null) {
    for (final r in _els(XmlDocument.parse(relsXml), 'Relationship')) {
      final id = r.getAttribute('Id');
      final target = r.getAttribute('Target');
      if (id != null && target != null) rels[id] = target;
    }
  }

  final sheets = <SheetData>[];
  var index = 0;
  for (final s in _els(XmlDocument.parse(workbookXml), 'sheet')) {
    index++;
    final name = s.getAttribute('name') ?? 'Sheet $index';
    final rid = s.getAttribute('r:id');
    var target = rid != null ? rels[rid] : null;
    target ??= 'worksheets/sheet$index.xml';
    final path = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    final sheetXml = read(p.posix.normalize(path));
    if (sheetXml == null) continue;
    sheets.add(_sheet(name, sheetXml, shared));
  }
  if (sheets.isEmpty) throw const FormatException('This workbook has no readable sheets.');
  return OfficeResult(sheets: sheets);
}

SheetData _sheet(String name, String xml, List<String> shared) {
  final rows = <List<String>>[];
  var truncated = false;
  for (final row in _els(XmlDocument.parse(xml), 'row')) {
    if (rows.length >= _maxRows) {
      truncated = true;
      break;
    }
    final r = int.tryParse(row.getAttribute('r') ?? '') ?? (rows.length + 1);
    while (rows.length < r - 1 && rows.length < _maxRows) {
      rows.add(const []);
    }
    final cells = <String>[];
    for (final c in row.children.whereType<XmlElement>().where((e) => e.name.local == 'c')) {
      final col = _colIndex(c.getAttribute('r') ?? '');
      if (col < 0 || col >= _maxCols) continue;
      while (cells.length < col) {
        cells.add('');
      }
      final type = c.getAttribute('t');
      String value = '';
      if (type == 'inlineStr') {
        value = _els(c, 't').map((t) => t.innerText).join();
      } else {
        final v = _els(c, 'v').firstOrNull?.innerText ?? '';
        if (type == 's') {
          final i = int.tryParse(v);
          value = (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
        } else if (type == 'b') {
          value = v == '1' ? 'TRUE' : 'FALSE';
        } else {
          value = v;
        }
      }
      if (col < cells.length) {
        cells[col] = value;
      } else {
        cells.add(value);
      }
    }
    rows.add(cells);
  }
  return SheetData(name, rows, truncated);
}

OfficeResult _pptx(String? Function(String) read, Iterable<String> names) {
  final slideNames = names
      .where((n) => RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(n))
      .toList()
    ..sort((a, b) => _num(a).compareTo(_num(b)));
  if (slideNames.isEmpty) throw const FormatException('Not a valid PPTX file.');
  final slides = <SlideData>[];
  for (final n in slideNames) {
    final xml = read(n);
    if (xml == null) continue;
    final lines = <String>[];
    for (final para in _els(XmlDocument.parse(xml), 'p')) {
      final text = _els(para, 't').map((t) => t.innerText).join();
      if (text.trim().isNotEmpty) lines.add(text.trim());
    }
    slides.add(SlideData(_num(n), lines));
  }
  return OfficeResult(slides: slides);
}

int _num(String name) =>
    int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(name)?.group(1) ?? '') ?? 0;
