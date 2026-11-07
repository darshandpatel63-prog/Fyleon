import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../files/domain/file_kind.dart';

/// Recognises a file by its CONTENT (magic bytes), not by its name. Used for files without
/// an extension or with an unknown one (for example a PDF saved as "1 to 50").
/// Top-level, so it can run in an isolate. Returns FileKind.index or -1.
int sniffKindIndex(String path) {
  try {
    final f = File(path);
    final raf = f.openSync();
    Uint8List head;
    try {
      head = raf.readSync(4096);
    } finally {
      raf.closeSync();
    }
    final k = _sniff(head, f);
    return k?.index ?? -1;
  } catch (_) {
    return -1;
  }
}

bool _starts(Uint8List h, List<int> sig, [int off = 0]) {
  if (h.length < off + sig.length) return false;
  for (var i = 0; i < sig.length; i++) {
    if (h[off + i] != sig[i]) return false;
  }
  return true;
}

List<int> _a(String s) => s.codeUnits;

FileKind? _sniff(Uint8List h, File f) {
  if (_starts(h, _a('%PDF'))) return FileKind.pdf;
  if (_starts(h, [0x89, 0x50, 0x4E, 0x47]) || _starts(h, [0xFF, 0xD8, 0xFF]) || _starts(h, _a('GIF8'))) return FileKind.image;
  if (_starts(h, _a('RIFF'))) {
    if (_starts(h, _a('WEBP'), 8)) return FileKind.image;
    if (_starts(h, _a('WAVE'), 8)) return FileKind.audio;
    if (_starts(h, _a('AVI '), 8)) return FileKind.video;
  }
  if (_starts(h, _a('ID3')) || _starts(h, _a('fLaC')) || _starts(h, _a('OggS'))) return FileKind.audio;
  if (h.length > 2 && h[0] == 0xFF && (h[1] == 0xFB || h[1] == 0xF3 || h[1] == 0xF2)) return FileKind.audio;
  if (_starts(h, _a('ftyp'), 4)) return _starts(h, _a('M4A '), 8) ? FileKind.audio : FileKind.video;
  if (_starts(h, [0x1A, 0x45, 0xDF, 0xA3])) return FileKind.video;
  if (_starts(h, _a('Rar!')) || _starts(h, [0x37, 0x7A, 0xBC, 0xAF]) || _starts(h, [0x1F, 0x8B])) return FileKind.archive;

  if (_starts(h, [0x50, 0x4B, 0x03, 0x04])) return _zipKind(f);

  // plain text: no NUL bytes and almost only printable characters
  if (h.isNotEmpty) {
    var odd = 0;
    for (final b in h) {
      if (b == 0) return null;
      if (b < 9 || (b > 13 && b < 32)) odd++;
    }
    if (odd * 20 < h.length) return FileKind.text;
  }
  return null;
}

FileKind _zipKind(File f) {
  try {
    if (f.lengthSync() > 80 * 1024 * 1024) return FileKind.archive;
    final names = ZipDecoder().decodeBytes(f.readAsBytesSync()).files.map((e) => e.name).toSet();
    if (names.contains('word/document.xml')) return FileKind.word;
    if (names.contains('xl/workbook.xml')) return FileKind.excel;
    if (names.contains('ppt/presentation.xml')) return FileKind.powerpoint;
    if (names.contains('META-INF/container.xml') && names.contains('mimetype')) return FileKind.epub;
    if (names.contains('AndroidManifest.xml') && names.any((n) => n.endsWith('.dex'))) return FileKind.apk;
  } catch (_) {}
  return FileKind.archive;
}
