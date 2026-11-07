import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/archive_utils.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/animations.dart';
import '../../shared/widgets/bottom_safe.dart';
import '../files/application/browse_controller.dart';
import '../files/domain/file_item.dart';
import '../files/domain/file_kind.dart';
import 'viewer_screen.dart';

class ArchiveEntry {
  const ArchiveEntry(this.name, this.size, this.isDir);
  final String name;
  final int size;
  final bool isDir;
}

Archive _decode(String path) {
  final bytes = File(path).readAsBytesSync();
  final lower = path.toLowerCase();
  if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz')) {
    return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  }
  if (lower.endsWith('.tar')) return TarDecoder().decodeBytes(bytes);
  if (lower.endsWith('.rar') || lower.endsWith('.7z')) {
    throw const FormatException('RAR and 7z are not supported yet (ZIP, JAR, APK, AAB, TAR and TGZ work).');
  }
  if (lower.endsWith('.gz') || lower.endsWith('.bz2') || lower.endsWith('.xz')) {
    throw const FormatException('Single compressed files cannot be browsed (only archives with several files).');
  }
  return ZipDecoder().decodeBytes(bytes);
}

/// Runs in an isolate. Lists every entry of the archive.
List<ArchiveEntry> readArchiveListing(String path) {
  final archive = _decode(path);
  final out = <ArchiveEntry>[];
  for (final f in archive.files) {
    out.add(ArchiveEntry(f.name, f.size, !f.isFile));
  }
  return out;
}

String _safeJoin(String root, String entryName) {
  final cleaned = entryName.replaceAll('\\', '/');
  final full = p.normalize(p.join(root, cleaned));
  if (!(p.isWithin(root, full) || p.equals(root, full))) {
    throw const FormatException('Unsafe path inside the archive.');
  }
  return full;
}

/// Isolate: extracts ONE entry to [outDir] and returns the file path. args = [archive, entry, outDir]
String extractEntryTo(List<String> args) {
  final archive = _decode(args[0]);
  for (final f in archive.files) {
    if (f.isFile && f.name == args[1]) {
      final out = _safeJoin(args[2], f.name);
      Directory(p.dirname(out)).createSync(recursive: true);
      File(out).writeAsBytesSync(archiveFileBytes(f));
      return out;
    }
  }
  throw const FormatException('That file is not inside the archive.');
}

/// Isolate: extracts everything. args = [archive, destDir]. Returns the number of files.
int extractAllTo(List<String> args) {
  final archive = _decode(args[0]);
  var n = 0;
  for (final f in archive.files) {
    final out = _safeJoin(args[1], f.name);
    if (f.isFile) {
      Directory(p.dirname(out)).createSync(recursive: true);
      File(out).writeAsBytesSync(archiveFileBytes(f));
      n++;
    } else {
      Directory(out).createSync(recursive: true);
    }
  }
  return n;
}

class _Row {
  const _Row.folder(this.name)
      : isDir = true,
        size = 0,
        full = '';
  const _Row.file(this.name, this.size, this.full) : isDir = false;
  final String name;
  final bool isDir;
  final int size;
  final String full;
}

/// Browse ZIP / JAR / APK / AAB / TAR like a normal folder: folders open, files open in
/// their viewer (code, images, PDF...), and "Extract all" unpacks next to the archive.
class ArchiveViewerScreen extends ConsumerStatefulWidget {
  const ArchiveViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  ConsumerState<ArchiveViewerScreen> createState() => _ArchiveViewerScreenState();
}

class _ArchiveViewerScreenState extends ConsumerState<ArchiveViewerScreen> {
  List<ArchiveEntry>? _entries;
  String? _error;
  String _cwd = ''; // "", "src/", "src/main/"
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.item.size > AppConstants.maxArchiveBytes) {
        throw FormatException('File is too large to browse on this device (limit ${formatSize(AppConstants.maxArchiveBytes)}).');
      }
      final list = await compute(readArchiveListing, widget.item.path);
      if (mounted) setState(() => _entries = list);
    } catch (e) {
      if (mounted) setState(() => _error = e is FormatException ? e.message : 'Could not open this archive.');
    }
  }

  List<_Row> _rows() {
    final folders = <String>{};
    final files = <_Row>[];
    for (final e in _entries ?? const <ArchiveEntry>[]) {
      var name = e.name.replaceAll('\\', '/');
      if (name.startsWith('./')) name = name.substring(2);
      if (!name.startsWith(_cwd)) continue;
      final rest = name.substring(_cwd.length);
      if (rest.isEmpty) continue;
      final slash = rest.indexOf('/');
      if (slash == -1) {
        if (!e.isDir) files.add(_Row.file(rest, e.size, e.name));
      } else {
        folders.add(rest.substring(0, slash));
      }
    }
    final f = folders.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    files.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [for (final n in f) _Row.folder(n), ...files];
  }

  void _up() {
    final parts = _cwd.split('/')..removeWhere((s) => s.isEmpty);
    if (parts.isNotEmpty) parts.removeLast();
    setState(() => _cwd = parts.isEmpty ? '' : '${parts.join('/')}/');
  }

  Future<void> _openEntry(_Row r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final tmp = await getTemporaryDirectory();
      final dir = p.join(tmp.path, 'zip_open', widget.item.path.hashCode.toUnsigned(31).toString());
      final out = await compute(extractEntryTo, [widget.item.path, r.full, dir]);
      final item = FileItem.tryFromPath(out);
      if (item != null && mounted) {
        await Navigator.of(context).push(fadeSlideRoute(ViewerScreen(item: item)));
      }
    } catch (e) {
      _toast(e is FormatException ? e.message : 'Could not open this file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _extractAll() async {
    final name = p.basenameWithoutExtension(widget.item.name);
    final dest = p.join(p.dirname(widget.item.path), name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Extract all?'),
        content: Text('Everything will be extracted to:\n$dest'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Extract')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await compute(extractAllTo, [widget.item.path, dest]);
      ref.invalidate(directoryListingProvider);
      _toast('Extracted $n files to $name');
    } catch (e) {
      _toast(e is FormatException ? e.message : 'Could not extract. Allow "all files access" in Settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entries = _entries;
    final rows = entries == null ? const <_Row>[] : _rows();
    final fileCount = entries?.where((e) => !e.isDir).length ?? 0;
    final total = entries?.where((e) => !e.isDir).fold<int>(0, (s, e) => s + e.size) ?? 0;

    return PopScope(
      canPop: _cwd.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _up();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (entries != null)
              IconButton(tooltip: 'Extract all', icon: const Icon(Icons.unarchive_rounded), onPressed: _busy ? null : _extractAll),
          ],
        ),
        body: BottomSafe(
          child: _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : entries == null
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        if (_busy) const LinearProgressIndicator(minHeight: 3),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(16)),
                          child: Row(
                            children: [
                              if (_cwd.isNotEmpty)
                                IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.arrow_upward_rounded), onPressed: _up),
                              Expanded(
                                child: Text(
                                  '${_cwd.isEmpty ? '/' : '/$_cwd'}\n$fileCount files - ${formatSize(total)} uncompressed',
                                  style: const TextStyle(fontSize: 12.5),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: rows.isEmpty
                              ? const Center(child: Text('Empty folder'))
                              : ListView.builder(
                                  itemCount: rows.length,
                                  itemBuilder: (context, i) {
                                    final r = rows[i];
                                    final kind = r.isDir ? null : kindForExtension(extensionOf(r.name));
                                    return FadeSlideIn(
                                      index: i,
                                      child: ListTile(
                                        leading: Icon(r.isDir ? Icons.folder_rounded : kind!.icon, color: r.isDir ? scheme.primary : kind!.color),
                                        title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                        subtitle: r.isDir ? null : Text(formatSize(r.size)),
                                        trailing: r.isDir ? const Icon(Icons.chevron_right_rounded) : null,
                                        onTap: r.isDir ? () => setState(() => _cwd = '$_cwd${r.name}/') : () => _openEntry(r),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}
