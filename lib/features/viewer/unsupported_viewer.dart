import 'package:flutter/material.dart';

import '../../core/utils/format.dart';
import '../../shared/widgets/animations.dart';
import '../../shared/widgets/file_widgets.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import 'text_viewer.dart';

class UnsupportedViewerScreen extends StatelessWidget {
  const UnsupportedViewerScreen({super.key, required this.item, this.reason});

  final FileItem item;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FileThumb(item: item, size: 96, radius: 28),
              const SizedBox(height: 20),
              Text(
                item.name,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '${item.kind.label} - ${formatSize(item.size)}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Text(
                reason ?? 'Fyleon cannot preview this file type yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  fadeSlideRoute(TextViewerScreen(item: item, forceText: true)),
                ),
                icon: const Icon(Icons.article_rounded),
                label: const Text('Try as text'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
