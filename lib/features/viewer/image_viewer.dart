import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/utils/format.dart';
import '../files/domain/file_item.dart';

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                formatSize(item.size),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 8,
        child: Center(
          child: Image.file(
            File(item.path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'This image could not be decoded.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
