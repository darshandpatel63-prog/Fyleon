import 'package:archive/archive.dart';

/// Works with archive 3.x (`content`) and 4.x (`readBytes()`).
List<int> archiveFileBytes(ArchiveFile file) {
  final dynamic f = file;
  try {
    final r = f.readBytes();
    if (r is List<int>) return r;
  } catch (_) {
    // archive 3.x has no readBytes(); fall through to content
  }
  return f.content as List<int>;
}
