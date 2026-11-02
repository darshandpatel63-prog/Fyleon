import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/animations.dart';
import '../../ads/ad_service.dart';
import '../../viewer/viewer_screen.dart';
import '../application/files_providers.dart';
import '../domain/file_item.dart';

/// Opens a file. Ads never run before this: the file opens immediately.
/// An interstitial may appear only AFTER the user closes the viewer.
Future<void> openFile(BuildContext context, WidgetRef ref, FileItem item) async {
  final navigator = Navigator.of(context);
  final ads = ref.read(adServiceProvider);
  final recents = ref.read(recentsProvider.notifier);
  recents.add(item); // fire and forget
  await navigator.push(fadeSlideRoute(ViewerScreen(item: item)));
  ads.onFileClosed();
}

/// System file picker (works without any storage permission).
Future<void> pickAndOpenFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  PlatformFile? picked;
  try {
    picked = await FilePicker.pickFile();
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not open the file picker.')));
    return;
  }
  if (picked == null) return;
  final path = picked.path;
  if (path == null) {
    messenger.showSnackBar(const SnackBar(content: Text('This file cannot be opened directly.')));
    return;
  }
  final item = FileItem.tryFromPath(path);
  if (item == null) {
    messenger.showSnackBar(const SnackBar(content: Text('File not found.')));
    return;
  }
  if (!context.mounted) return;
  await openFile(context, ref, item);
}
