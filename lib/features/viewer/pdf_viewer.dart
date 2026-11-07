import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/utils/format.dart';
import '../../shared/widgets/bottom_safe.dart';
import '../files/domain/file_item.dart';

/// PDF viewer. Opens the document itself so that it can
///  - ask for a password (protected PDFs),
///  - show a clear error for damaged / unsupported PDFs instead of a blank screen.
class PdfViewerScreen extends StatefulWidget {
  const PdfViewerScreen({super.key, required this.item});

  final FileItem item;

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PdfDocument? _doc;
  bool _loading = true;
  String? _error;
  String? _details;
  bool _cancelledPassword = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    final d = _doc;
    if (d != null) unawaited(d.dispose().catchError((Object _) {}));
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
      _details = null;
      _cancelledPassword = false;
    });
    try {
      final doc = await PdfDocument.openFile(
        widget.item.path,
        passwordProvider: _askPassword,
        firstAttemptByEmptyPassword: true,
      );
      if (!mounted) {
        unawaited(doc.dispose().catchError((Object _) {}));
        return;
      }
      setState(() {
        _doc = doc;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final text = e.toString();
      final isPassword = _cancelledPassword || e.runtimeType.toString().toLowerCase().contains('password');
      setState(() {
        _loading = false;
        _details = text;
        _error = isPassword
            ? 'This PDF is password protected and could not be unlocked.'
            : 'This PDF could not be opened. The file may be damaged, incomplete, or use a feature that is not supported yet.';
      });
    }
  }

  Future<String?> _askPassword() async {
    if (!mounted) return null;
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_rounded),
        title: const Text('Password required'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'PDF password'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Open')),
        ],
      ),
    );
    if (result == null) _cancelledPassword = true;
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: BottomSafe(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, size: 64, color: scheme.error),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 6),
                        Text(formatSize(widget.item.size), style: TextStyle(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _open,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try again'),
                        ),
                        if (_details != null) ...[
                          const SizedBox(height: 20),
                          SelectableText(
                            _details!,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : PdfViewer(PdfDocumentRefDirect(_doc!))),
    );
  }
}
