import 'package:flutter/material.dart';

import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import 'archive_viewer.dart';
import 'epub_viewer.dart';
import 'image_viewer.dart';
import 'office_viewer.dart';
import 'pdf_viewer.dart';
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
      case FileKind.apk:
        return ArchiveViewerScreen(item: item);
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
        return OfficeViewerScreen(item: item);
      case FileKind.audio:
      case FileKind.video:
        return UnsupportedViewerScreen(
          item: item,
          reason: 'Audio and video playback is planned for a later phase.',
        );
      case FileKind.other:
        return UnsupportedViewerScreen(item: item);
    }
  }
}
