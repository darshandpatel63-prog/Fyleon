import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

class EpubChapter {
  const EpubChapter({required this.title, required this.html, required this.path});
  final String title;
  final String html;
  final String path;
}

class EpubData {
  const EpubData({
    required this.title,
    required this.author,
    required this.chapters,
    required this.images,
  });
  final String title;
  final String author;
  final List<EpubChapter> chapters;
  final Map<String, Uint8List> images;
}

Iterable<XmlElement> _els(XmlNode n, String local) =>
    n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

String _join(String dir, String href) {
  var h = href.split('#').first;
  try {
    h = Uri.decodeComponent(h);
  } catch (_) {}
  final joined = (dir == '.' || dir.isEmpty) ? h : '$dir/$h';
  return p.posix.normalize(joined);
}

/// Runs in an isolate (top-level). Throws FormatException for broken files.
EpubData parseEpub(String path) {
  final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  final files = <String, ArchiveFile>{
    for (final f in archive.files)
      if (f.isFile) f.name: f,
  };

  String? readText(String name) {
    final f = files[name];
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final containerXml = readText('META-INF/container.xml');
  if (containerXml == null) {
    throw const FormatException('Not a valid EPUB (container.xml is missing).');
  }
  final rootfile = _els(XmlDocument.parse(containerXml), 'rootfile').firstOrNull;
  final opfPath = rootfile?.getAttribute('full-path');
  if (opfPath == null) {
    throw const FormatException('Not a valid EPUB (no package file).');
  }
  final opfText = readText(opfPath);
  if (opfText == null) {
    throw const FormatException('Not a valid EPUB (package file is missing).');
  }
  final opf = XmlDocument.parse(opfText);
  final opfDir = p.posix.dirname(opfPath);

  final manifest = <String, Map<String, String>>{};
  for (final it in _els(opf, 'item')) {
    final id = it.getAttribute('id');
    final href = it.getAttribute('href');
    if (id == null || href == null) continue;
    manifest[id] = {
      'href': href,
      'type': it.getAttribute('media-type') ?? '',
      'props': it.getAttribute('properties') ?? '',
    };
  }

  final spineIds = <String>[];
  for (final r in _els(opf, 'itemref')) {
    final id = r.getAttribute('idref');
    if (id != null) spineIds.add(id);
  }

  // ---- chapter titles from NCX (EPUB2) and nav (EPUB3) ----
  final titles = <String, String>{};
  try {
    for (final m in manifest.values) {
      if (m['type'] == 'application/x-dtbncx+xml') {
        final ncxPath = _join(opfDir, m['href']!);
        final ncxText = readText(ncxPath);
        if (ncxText == null) continue;
        final ncxDir = p.posix.dirname(ncxPath);
        for (final nav in _els(XmlDocument.parse(ncxText), 'navPoint')) {
          final label = _els(nav, 'text').firstOrNull?.innerText.trim();
          final src = _els(nav, 'content').firstOrNull?.getAttribute('src');
          if (label != null && label.isNotEmpty && src != null) {
            titles.putIfAbsent(_join(ncxDir, src), () => label);
          }
        }
      }
      if (m['props']!.split(' ').contains('nav')) {
        final navPath = _join(opfDir, m['href']!);
        final navText = readText(navPath);
        if (navText == null) continue;
        final navDir = p.posix.dirname(navPath);
        final doc = html_parser.parse(navText);
        for (final a in doc.querySelectorAll('nav a')) {
          final href = a.attributes['href'];
          final label = a.text.trim();
          if (href != null && label.isNotEmpty) {
            titles.putIfAbsent(_join(navDir, href), () => label);
          }
        }
      }
    }
  } catch (_) {
    // titles are optional
  }

  final chapters = <EpubChapter>[];
  for (final id in spineIds) {
    final m = manifest[id];
    if (m == null) continue;
    final full = _join(opfDir, m['href']!);
    final text = readText(full);
    if (text == null) continue;
    chapters.add(EpubChapter(
      title: titles[full] ?? 'Section ${chapters.length + 1}',
      html: text,
      path: full,
    ));
  }
  if (chapters.isEmpty) {
    throw const FormatException('This EPUB has no readable chapters.');
  }

  // ---- images (capped so memory stays safe) ----
  const imageExt = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};
  final images = <String, Uint8List>{};
  var imageBytes = 0;
  for (final e in files.entries) {
    if (!imageExt.contains(p.posix.extension(e.key).toLowerCase())) continue;
    final c = e.value.content as List<int>;
    if (c.length > 6 * 1024 * 1024 || imageBytes + c.length > 80 * 1024 * 1024) continue;
    imageBytes += c.length;
    images[e.key] = c is Uint8List ? c : Uint8List.fromList(c);
  }

  final title = _els(opf, 'title').firstOrNull?.innerText.trim();
  final author = _els(opf, 'creator').firstOrNull?.innerText.trim();
  return EpubData(
    title: (title == null || title.isEmpty) ? p.basenameWithoutExtension(path) : title,
    author: author ?? '',
    chapters: chapters,
    images: images,
  );
}
