import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

// =====================================================================
// Creates real example files in every supported format so every viewer
// can be tested without having such files on the phone.
// =====================================================================

final _crcTable = () {
  final t = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    t[n] = c;
  }
  return t;
}();

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Minimal ZIP writer (stored, no compression) - valid for every unzip tool and for Fyleon.
Uint8List buildZip(Map<String, List<int>> files) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var count = 0;

  void u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  files.forEach((name, data) {
    final nameBytes = utf8.encode(name);
    final crc = data.isEmpty ? 0 : crc32(data);
    final offset = out.length;
    u32(out, 0x04034b50);
    u16(out, 20);
    u16(out, 0x0800);
    u16(out, 0);
    u16(out, 0);
    u16(out, 33);
    u32(out, crc);
    u32(out, data.length);
    u32(out, data.length);
    u16(out, nameBytes.length);
    u16(out, 0);
    out.add(nameBytes);
    out.add(data);

    u32(central, 0x02014b50);
    u16(central, 20);
    u16(central, 20);
    u16(central, 0x0800);
    u16(central, 0);
    u16(central, 0);
    u16(central, 33);
    u32(central, crc);
    u32(central, data.length);
    u32(central, data.length);
    u16(central, nameBytes.length);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u16(central, 0);
    u32(central, name.endsWith('/') ? 0x10 : 0);
    u32(central, offset);
    central.add(nameBytes);
    count++;
  });

  final cdOffset = out.length;
  final cd = central.toBytes();
  out.add(cd);
  u32(out, 0x06054b50);
  u16(out, 0);
  u16(out, 0);
  u16(out, count);
  u16(out, count);
  u32(out, cd.length);
  u32(out, cdOffset);
  u16(out, 0);
  return out.toBytes();
}

List<int> _b(String s) => utf8.encode(s);

String _xmlEscape(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

// ------------------------------------------------------------------ PDF

Uint8List buildPdf(List<List<String>> pages) {
  final sb = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  void obj(int n, String body) {
    offsets.add(sb.length);
    sb.write('$n 0 obj\n$body\nendobj\n');
  }

  String esc(String t) => t.replaceAll('\\', '\\\\').replaceAll('(', '\\(').replaceAll(')', '\\)');
  final firstPageObj = 4;
  final kids = [for (var i = 0; i < pages.length; i++) '${firstPageObj + 2 * i} 0 R'].join(' ');
  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  obj(2, '<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>');
  obj(3, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  for (var i = 0; i < pages.length; i++) {
    final pageNo = firstPageObj + 2 * i;
    final contentNo = pageNo + 1;
    final content = StringBuffer('BT /F1 26 Tf 72 740 Td (${esc(pages[i].first)}) Tj ET\n');
    var y = 700.0;
    for (final line in pages[i].skip(1)) {
      content.write('BT /F1 13 Tf 72 $y Td (${esc(line)}) Tj ET\n');
      y -= 20;
    }
    content.write('72 120 450 3 re f\n');
    obj(pageNo, '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents $contentNo 0 R >>');
    final c = content.toString();
    obj(contentNo, '<< /Length ${c.length} >>\nstream\n$c\nendstream');
  }
  final xref = sb.length;
  final total = offsets.length + 1;
  sb.write('xref\n0 $total\n0000000000 65535 f \n');
  for (final o in offsets) {
    sb.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  sb.write('trailer\n<< /Size $total /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(sb.toString()));
}

// ------------------------------------------------------------------ audio / image

Uint8List buildWav({int seconds = 3, int rate = 16000}) {
  final samples = seconds * rate;
  final data = ByteData(44 + samples * 2);
  void s(int off, String t) {
    for (var i = 0; i < t.length; i++) {
      data.setUint8(off + i, t.codeUnitAt(i));
    }
  }

  s(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  s(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final t = i / rate;
    final freq = t < 1 ? 440.0 : (t < 2 ? 554.37 : 659.25);
    final fade = math.min(1.0, math.min(t % 1 * 12, (1 - t % 1) * 12));
    data.setInt16(44 + i * 2, (math.sin(2 * math.pi * freq * t) * 9000 * fade).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

Future<Uint8List> buildPng() async {
  const w = 640.0;
  const h = 360.0;
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, w, h));
  final bg = ui.Paint()
    ..shader = ui.Gradient.linear(
      const ui.Offset(0, 0),
      const ui.Offset(w, h),
      const [ui.Color(0xFF4F46E5), ui.Color(0xFF7C3AED), ui.Color(0xFF06B6D4)],
      const [0.0, 0.55, 1.0],
    );
  canvas.drawRect(const ui.Rect.fromLTWH(0, 0, w, h), bg);
  canvas.drawCircle(const ui.Offset(w / 2, h / 2), 80, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(const ui.Rect.fromLTWH(60, 50, 140, 90), const ui.Radius.circular(18)),
    ui.Paint()..color = const ui.Color(0x99FFFFFF),
  );
  canvas.drawCircle(const ui.Offset(520, 270), 42, ui.Paint()..color = const ui.Color(0xFFF59E0B));
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// ------------------------------------------------------------------ Office + EPUB

const _ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

Uint8List buildDocx() {
  const w = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"';
  String para(String text, {int heading = 0}) =>
      '<w:p>${heading > 0 ? '<w:pPr><w:pStyle w:val="Heading$heading"/></w:pPr>' : ''}<w:r><w:t xml:space="preserve">${_xmlEscape(text)}</w:t></w:r></w:p>';
  final body = StringBuffer()
    ..write(para('Fyleon sample document', heading: 1))
    ..write(para('This DOCX file was created by Fyleon so that you can test the Word viewer.'))
    ..write(para('Headings', heading: 2))
    ..write(para('Headings, paragraphs and long text are shown. Tables, images and styles come in a later version.'))
    ..write(para('A longer paragraph', heading: 2));
  for (var i = 1; i <= 6; i++) {
    body.write(para('Paragraph $i. The quick brown fox jumps over the lazy dog. Fyleon opens PDF, EPUB, Word, Excel, PowerPoint, code, images, audio, video and archives.'));
  }
  return buildZip({
    '[Content_Types].xml': _b('$_ct<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'),
    '_rels/.rels': _b('$_ct<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'),
    'word/document.xml': _b('$_ct<w:document $w><w:body>$body</w:body></w:document>'),
  });
}

Uint8List buildXlsx() {
  String cell(String ref, Object v) => v is num ? '<c r="$ref"><v>$v</v></c>' : '<c r="$ref" t="inlineStr"><is><t>${_xmlEscape('$v')}</t></is></c>';
  final sheet1 = StringBuffer('<row r="1">${cell('A1', 'Number')}${cell('B1', 'Square')}${cell('C1', 'Cube')}${cell('D1', 'Note')}</row>');
  for (var i = 1; i <= 25; i++) {
    sheet1.write('<row r="${i + 1}">${cell('A${i + 1}', i)}${cell('B${i + 1}', i * i)}${cell('C${i + 1}', i * i * i)}${cell('D${i + 1}', i.isEven ? 'even' : 'odd')}</row>');
  }
  final sheet2 = StringBuffer('<row r="1">${cell('A1', 'Item')}${cell('B1', 'Price')}</row>');
  const items = ['Notebook', 'Pen', 'Bag', 'Bottle', 'Lamp'];
  for (var i = 0; i < items.length; i++) {
    sheet2.write('<row r="${i + 2}">${cell('A${i + 2}', items[i])}${cell('B${i + 2}', (i + 1) * 49.5)}</row>');
  }
  const ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"';
  return buildZip({
    '[Content_Types].xml': _b('$_ct<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'),
    '_rels/.rels': _b('$_ct<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
    'xl/workbook.xml': _b('$_ct<workbook $ns xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Numbers" sheetId="1" r:id="rId1"/><sheet name="Shop" sheetId="2" r:id="rId2"/></sheets></workbook>'),
    'xl/_rels/workbook.xml.rels': _b('$_ct<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>'),
    'xl/worksheets/sheet1.xml': _b('$_ct<worksheet $ns><sheetData>$sheet1</sheetData></worksheet>'),
    'xl/worksheets/sheet2.xml': _b('$_ct<worksheet $ns><sheetData>$sheet2</sheetData></worksheet>'),
  });
}

Uint8List buildPptx() {
  const ns = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"';
  String shape(int id, String geom, int x, int y, int w, int h, {String? fill, String? line, List<(String, int, bool, String)> paras = const [], String anchor = 'ctr'}) {
    final fillXml = fill == null ? '<a:noFill/>' : '<a:solidFill><a:srgbClr val="$fill"/></a:solidFill>';
    final lineXml = line == null ? '' : '<a:ln w="25400"><a:solidFill><a:srgbClr val="$line"/></a:solidFill></a:ln>';
    final text = paras.map((e) => '<a:p><a:pPr algn="l"/><a:r><a:rPr lang="en-US" sz="${e.$2}" b="${e.$3 ? 1 : 0}"><a:solidFill><a:srgbClr val="${e.$4}"/></a:solidFill></a:rPr><a:t>${_xmlEscape(e.$1)}</a:t></a:r></a:p>').join();
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Shape $id"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$w" cy="$h"/></a:xfrm><a:prstGeom prst="$geom"><a:avLst/></a:prstGeom>$fillXml$lineXml</p:spPr><p:txBody><a:bodyPr anchor="$anchor"/><a:lstStyle/>${text.isEmpty ? '<a:p><a:endParaRPr lang="en-US"/></a:p>' : text}</p:txBody></p:sp>';
  }

  String slide(String bg, String shapes) =>
      '$_ct<p:sld $ns><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="$bg"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>$shapes</p:spTree></p:cSld></p:sld>';

  final s1 = slide(
    '4F46E5',
    shape(2, 'rect', 0, 4200000, 12192000, 120000, fill: '06B6D4') +
        shape(3, 'rect', 900000, 1700000, 10400000, 1500000, paras: [('Fyleon sample slides', 5400, true, 'FFFFFF')]) +
        shape(4, 'rect', 900000, 3200000, 10400000, 800000, paras: [('Open anything.', 2800, false, 'E0E7FF')], anchor: 't'),
  );
  final s2 = slide(
    'FFFFFF',
    shape(2, 'rect', 600000, 400000, 11000000, 1100000, paras: [('What Fyleon can open', 4000, true, '1E1B4B')]) +
        shape(3, 'rect', 600000, 1700000, 11000000, 4200000, anchor: 't', paras: [
          ('PDF and EPUB books', 2600, false, '111827'),
          ('Word, Excel and PowerPoint files', 2600, false, '111827'),
          ('Code with colors, and a full editor', 2600, false, '111827'),
          ('Images, audio and video', 2600, false, '111827'),
          ('ZIP, APK and other archives', 2600, false, '111827'),
        ]),
  );
  final s3 = slide(
    'F8FAFC',
    shape(2, 'ellipse', 800000, 1200000, 3200000, 3200000, fill: 'F59E0B', paras: [('Circle', 2400, true, 'FFFFFF')]) +
        shape(3, 'roundRect', 4700000, 1200000, 3200000, 3200000, fill: '10B981', line: '047857', paras: [('Rounded', 2400, true, 'FFFFFF')]) +
        shape(4, 'rect', 8600000, 1200000, 3000000, 3200000, fill: 'EF4444', paras: [('Rectangle', 2400, true, 'FFFFFF')]) +
        shape(5, 'rect', 800000, 4900000, 10800000, 900000, paras: [('Shapes, colors and text are drawn like on a slide.', 2400, false, '334155')], anchor: 't'),
  );
  return buildZip({
    '[Content_Types].xml': _b('$_ct<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/slides/slide2.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/slides/slide3.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>'),
    '_rels/.rels': _b('$_ct<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>'),
    'ppt/presentation.xml': _b('$_ct<p:presentation $ns><p:sldIdLst><p:sldId id="256" r:id="rId1"/><p:sldId id="257" r:id="rId2"/><p:sldId id="258" r:id="rId3"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>'),
    'ppt/_rels/presentation.xml.rels': _b('$_ct<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide3.xml"/></Relationships>'),
    'ppt/slides/slide1.xml': _b(s1),
    'ppt/slides/slide2.xml': _b(s2),
    'ppt/slides/slide3.xml': _b(s3),
  });
}

Uint8List buildEpub() {
  const words = 'the quiet river carries small boats past old stone bridges while children count the stars and the wind reads aloud from a book that never ends';
  String chapter(int n, String title) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n<html xmlns="http://www.w3.org/1999/xhtml"><head><title>$title</title></head><body><h1>$title</h1>');
    for (var i = 1; i <= 26; i++) {
      final text = List.generate(9 + (i * 3) % 7, (k) => words.split(' ')[(i + k * 5) % words.split(' ').length]).join(' ');
      b.write('<p>Paragraph $i of chapter $n: $text. <em>Italic words</em> and <strong>bold words</strong> are kept. $text, again and again, so that this chapter fills several pages on your screen.</p>');
      if (i == 8) b.write('<h2>A smaller heading</h2>');
      if (i == 14) b.write('<blockquote><p>"A quote stands out from the text around it."</p></blockquote>');
      if (i == 20) b.write('<ul><li>First list item</li><li>Second list item</li><li>Third list item</li></ul>');
    }
    b.write('</body></html>');
    return b.toString();
  }

  const titles = ['The beginning', 'The middle', 'The end'];
  final nav = [for (var i = 0; i < 3; i++) '<navPoint id="n${i + 1}" playOrder="${i + 1}"><navLabel><text>${titles[i]}</text></navLabel><content src="chapter${i + 1}.xhtml"/></navPoint>'].join();
  return buildZip({
    'mimetype': _b('application/epub+zip'),
    'META-INF/container.xml': _b('<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>'),
    'OEBPS/content.opf': _b('<?xml version="1.0" encoding="UTF-8"?><package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Fyleon Sample Book</dc:title><dc:creator>Fyleon</dc:creator><dc:identifier id="id">fyleon-sample-book</dc:identifier><dc:language>en</dc:language></metadata><manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/><item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/><item id="c2" href="chapter2.xhtml" media-type="application/xhtml+xml"/><item id="c3" href="chapter3.xhtml" media-type="application/xhtml+xml"/></manifest><spine toc="ncx"><itemref idref="c1"/><itemref idref="c2"/><itemref idref="c3"/></spine></package>'),
    'OEBPS/toc.ncx': _b('<?xml version="1.0" encoding="UTF-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head/><docTitle><text>Fyleon Sample Book</text></docTitle><navMap>$nav</navMap></ncx>'),
    'OEBPS/chapter1.xhtml': _b(chapter(1, titles[0])),
    'OEBPS/chapter2.xhtml': _b(chapter(2, titles[1])),
    'OEBPS/chapter3.xhtml': _b(chapter(3, titles[2])),
  });
}

// ------------------------------------------------------------------ the sample set

const _html = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Fyleon sample page</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <h1>Hello from Fyleon</h1>
  <p>Open this file and tap Preview. Try Phone, Tablet and Desktop views.</p>
  <button id="btn">Tap me</button>
  <p id="out"></p>
  <script src="script.js"></script>
</body>
</html>
''';

const _css = '''/* Colors show as small squares next to the line number in the editor */
:root { color-scheme: light dark; }
body { font-family: system-ui, sans-serif; margin: 0; padding: 24px; line-height: 1.5; }
h1 { color: #4f46e5; }
button { background: rgb(124, 58, 237); color: #fff; border: 0; padding: 10px 18px; border-radius: 10px; font-size: 16px; }
@media (min-width: 900px) { body { max-width: 760px; margin: 0 auto; } }
''';

const _js = '''document.getElementById('btn').addEventListener('click', () => {
  const out = document.getElementById('out');
  out.textContent = 'Clicked at ' + new Date().toLocaleTimeString();
  console.log('button clicked');
});
''';

const _py = '''# Python sample. Inside def / if / for the code is indented with 4 spaces.
def greet(name):
    if name:
        print("Hello, " + name)
    else:
        print("Hello, world")


for i in range(3):
    greet("Fyleon " + str(i))
''';

const _brokenPy = '''def broken(x):
print(x)

value = 1
    other = 2
''';

const _dart = '''import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('Hello, Fyleon!')))));
}

const brand = Color(0xFF4F46E5);
''';

const _java = '''public class Main {
    public static void main(String[] args) {
        for (int i = 1; i <= 3; i++) {
            System.out.println("Hello " + i);
        }
    }
}
''';

const _svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" width="200" height="200">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#4F46E5"/><stop offset="1" stop-color="#06B6D4"/></linearGradient></defs>
  <rect width="200" height="200" rx="40" fill="url(#g)"/>
  <circle cx="100" cy="100" r="46" fill="#fff"/>
</svg>
''';

const _md = '''# Fyleon sample notes

Markdown is **bold**, *italic* and `code`.

- First item
- Second item

> A quote

| Format | Works |
|--------|-------|
| PDF    | yes   |
| EPUB   | yes   |

```python
print("code block")
```
''';

/// Writes the files into `<root>/Fyleon Samples` and returns that folder's path.
Future<String> generateSampleFiles(String root) async {
  final dir = Directory(p.join(root, 'Fyleon Samples'));
  await dir.create(recursive: true);

  Future<void> w(String name, List<int> bytes) async {
    final f = File(p.join(dir.path, name));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  Future<void> t(String name, String text) => w(name, _b(text));

  final pdf = buildPdf([
    ['Fyleon sample PDF', 'This PDF has three pages.', 'It was created by Fyleon so you can test the PDF viewer.', 'Zoom with two fingers, scroll down for the next page.'],
    ['Page two', 'Lines of text are drawn with the Helvetica font.', 'PDF files from scanners or cameras are pictures and work too.'],
    ['Page three', 'The end of the sample document.'],
  ]);

  await t('01_notes.txt', 'Plain text file.\nOpen it and try the text size buttons.\nSecond line.\n');
  await t('02_readme.md', _md);
  await t('03_data.csv', 'name,age,city\nAsha,24,Surat\nRavi,31,Pune\nMeena,28,Delhi\n');
  await t('04_config.json', '{\n  "app": "Fyleon",\n  "version": 1,\n  "features": ["viewer", "editor", "preview"]\n}\n');
  await t('05_page.html', _html);
  await t('style.css', _css);
  await t('script.js', _js);
  await t('06_hello.py', _py);
  await t('07_app.dart', _dart);
  await t('08_Main.java', _java);
  await t('09_logo.svg', _svg);
  await t('10_broken.py', _brokenPy);
  await t('11_broken.json', '{"a": 1,}\n');
  await t('12_broken.html', '<div>\n  <p>Not closed\n</div>\n');
  await w('13_picture.png', await buildPng());
  await w('14_tone.wav', buildWav());
  await w('15_document.docx', buildDocx());
  await w('16_sheet.xlsx', buildXlsx());
  await w('17_slides.pptx', buildPptx());
  await w('18_book.epub', buildEpub());
  await w('19_report.pdf', pdf);
  await w('20_scan_without_extension', pdf); // opens by content, not by name
  await w(
    '21_project.zip',
    buildZip({
      'src/': <int>[],
      'src/main.py': _b(_py),
      'src/utils/': <int>[],
      'src/utils/helper.js': _b(_js),
      'docs/': <int>[],
      'docs/readme.md': _b(_md),
      'assets/logo.svg': _b(_svg),
      'config.json': _b('{"name": "sample-project"}\n'),
    }),
  );
  await t('web-project/index.html', _html);
  await t('web-project/style.css', _css);
  await t('web-project/script.js', _js);
  return dir.path;
}
