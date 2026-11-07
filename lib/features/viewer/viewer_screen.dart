import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import 'apk_screen.dart';
import 'archive_viewer.dart';
import 'epub_viewer.dart';
import 'image_viewer.dart';
import 'media_player_screen.dart';
import 'office_viewer.dart';
import 'pdf_viewer.dart';
import 'sniff.dart';
import 'pptx_viewer.dart';
import 'text_viewer.dart';
import 'unsupported_viewer.dart';

/// Picks the right viewer for a file. Add new viewers here.
class ViewerScreen extends StatelessWidget {
  const ViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case FileKind.pdf:
        return PdfViewerScreen(item: item);
      case FileKind.epub:
        return EpubViewerScreen(item: item);
      case FileKind.code:
      case FileKind.text:
        return TextViewerScreen(item: item);
      case FileKind.image:
        return ImageViewerScreen(item: item);
      case FileKind.archive:
        return ArchiveViewerScreen(item: item);
      case FileKind.apk:
        return ApkScreen(item: item);
      case FileKind.word:
      case FileKind.excel:
      case FileKind.powerpoint:
        final ext = item.ext;
        if (ext == 'doc' || ext == 'xls' || ext == 'ppt' || ext == 'odt' || ext == 'ods' || ext == 'odp') {
          return UnsupportedViewerScreen(
            item: item,
            reason: 'Old/OpenDocument formats (.$ext) are not supported yet. '
                'DOCX, XLSX and PPTX open with a basic preview.',
          );
        }
        if (item.kind == FileKind.powerpoint) return PptxViewerScreen(item: item);
        return OfficeViewerScreen(item: item);
      case FileKind.audio:
      case FileKind.video:
        return MediaPlayerScreen(item: item);
      case FileKind.other:
        return _SniffingViewer(item: item);
    }
  }
}


/// For files with no/unknown extension: reads the first bytes to find out what the file really is.
class _SniffingViewer extends StatefulWidget {
  const _SniffingViewer({required this.item});

  final FileItem item;

  @override
  State<_SniffingViewer> createState() => _SniffingViewerState();
}

class _SniffingViewerState extends State<_SniffingViewer> {
  late final Future<int> _future = compute(sniffKindIndex, widget.item.path);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final idx = snap.data ?? -1;
        if (idx >= 0 && idx < FileKind.values.length && FileKind.values[idx] != FileKind.other) {
          return ViewerScreen(item: widget.item.withKind(FileKind.values[idx]));
        }
        return UnsupportedViewerScreen(item: widget.item);
      },
    );
  }
}
