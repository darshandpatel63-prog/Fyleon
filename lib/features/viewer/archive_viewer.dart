import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/format.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';

class ArchiveEntry {
  const ArchiveEntry(this.name, this.size, this.isDir);
  final String name;
  final int size;
  final bool isDir;
}

/// Runs in an isolate (top-level). Lists ZIP/JAR/APK/AAB and TAR/TAR.GZ.
List<ArchiveEntry> readArchiveListing(String path) {
  final bytes = File(path).readAsBytesSync();
  final lower = path.toLowerCase();
  Archive archive;
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    archive = TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  } else if (lower.endsWith('.tar')) {
    archive = TarDecoder().decodeBytes(bytes);
  } else if (lower.endsWith('.rar') || lower.endsWith('.7z')) {
    throw const FormatException('RAR and 7z listing is not supported yet (ZIP, JAR, APK, AAB, TAR, TGZ work).');
  } else if (lower.endsWith('.gz') || lower.endsWith('.bz2') || lower.endsWith('.xz')) {
    throw const FormatException('Single compressed files cannot be listed (only archives with several files).');
  } else {
    archive = ZipDecoder().decodeBytes(bytes);
  }
  final out = <ArchiveEntry>[];
  for (final f in archive.files) {
    out.add(ArchiveEntry(f.name, f.size, !f.isFile));
  }
  out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return out;
}

class ArchiveViewerScreen extends StatefulWidget {
  const ArchiveViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<ArchiveViewerScreen> createState() => _ArchiveViewerScreenState();
}

class _ArchiveViewerScreenState extends State<ArchiveViewerScreen> {
  late final Future<List<ArchiveEntry>> _future = _load();

  Future<List<ArchiveEntry>> _load() async {
    if (widget.item.size > AppConstants.maxArchiveBytes) {
      throw FormatException(
        'File is too large to list on this device (limit ${formatSize(AppConstants.maxArchiveBytes)}).',
      );
    }
    return compute(readArchiveListing, widget.item.path);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isApk = widget.item.kind == FileKind.apk;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<List<ArchiveEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            final e = snap.error;
            final msg = e is FormatException ? e.message : 'Could not open this archive.';
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(msg, textAlign: TextAlign.center),
              ),
            );
          }
          final entries = snap.data!;
          final files = entries.where((e) => !e.isDir).toList();
          final total = files.fold<int>(0, (s, e) => s + e.size);
          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  '${files.length} files - ${formatSize(total)} uncompressed'
                  '${isApk ? '\nAn APK is a package: Fyleon lists its contents only.' : ''}',
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    final kind = kindForExtension(extensionOf(e.name));
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        e.isDir ? Icons.folder_rounded : kind.icon,
                        color: e.isDir ? scheme.primary : kind.color,
                      ),
                      title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: e.isDir
                          ? null
                          : Text(formatSize(e.size), style: TextStyle(color: scheme.onSurfaceVariant)),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
