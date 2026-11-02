import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../files/domain/file_item.dart';

class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: PdfViewer.file(item.path),
    );
  }
}
