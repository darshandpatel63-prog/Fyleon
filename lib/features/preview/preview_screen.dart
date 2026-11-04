import 'dart:io';

import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/utils/platform_utils.dart';
import '../files/domain/file_item.dart';
import 'local_server.dart';

enum PreviewDevice { phone, tablet, desktop }

extension PreviewDeviceX on PreviewDevice {
  String get label {
    switch (this) {
      case PreviewDevice.phone:
        return 'Phone';
      case PreviewDevice.tablet:
        return 'Tablet';
      case PreviewDevice.desktop:
        return 'Desktop';
    }
  }

  double get width {
    switch (this) {
      case PreviewDevice.phone:
        return 390;
      case PreviewDevice.tablet:
        return 820;
      case PreviewDevice.desktop:
        return 1280;
    }
  }

  IconData get icon {
    switch (this) {
      case PreviewDevice.phone:
        return Icons.smartphone_rounded;
      case PreviewDevice.tablet:
        return Icons.tablet_mac_rounded;
      case PreviewDevice.desktop:
        return Icons.desktop_windows_rounded;
    }
  }
}

const _desktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36';

/// Live preview for HTML, SVG and Markdown. Works with relative CSS/JS/images
/// because the project folder is served by a local server on this device.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({super.key, required this.path, this.liveText});

  final String path;

  /// Unsaved editor text (shown instead of the file on disk).
  final String? liveText;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  LocalPreviewServer? _server;
  WebViewController? _web;
  PreviewDevice _device = PreviewDevice.phone;
  String? _error;
  int _progress = 0;
  String _entry = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _server?.stop();
    super.dispose();
  }

  Future<void> _start() async {
    if (!(isAndroid || isIOS)) {
      setState(() => _error = 'Web preview is available on Android and iOS for now.\nDesktop preview comes with the desktop apps.');
      return;
    }
    try {
      final ext = extensionOf(p.basename(widget.path));
      final dir = p.dirname(widget.path);
      final name = p.basename(widget.path);
      final server = LocalPreviewServer(dir);
      var entry = name;

      if (ext == 'md' || ext == 'markdown') {
        final text = widget.liveText ?? await File(widget.path).readAsString();
        entry = '__preview__.html';
        server.overrides['/$entry'] = _markdownPage(text, name);
      } else if (widget.liveText != null) {
        server.overrides['/$name'] = widget.liveText!;
      }
      await server.start();
      _server = server;
      _entry = entry;

      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(NavigationDelegate(
          onProgress: (v) {
            if (mounted) setState(() => _progress = v);
          },
          onWebResourceError: (e) {
            if (mounted && e.isForMainFrame == true) setState(() => _error = 'Could not load the preview: ${e.description}');
          },
        ))
        ..loadRequest(Uri.parse('http://127.0.0.1:${server.port}/$entry'));
      setState(() => _web = controller);
    } catch (e) {
      setState(() => _error = 'Could not start the preview.');
    }
  }

  String _markdownPage(String text, String title) {
    final body = md.markdownToHtml(text, extensionSet: md.ExtensionSet.gitHubFlavored);
    return '''<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>
:root{color-scheme:light dark}
body{font-family:system-ui,sans-serif;line-height:1.6;max-width:820px;margin:0 auto;padding:20px}
pre{background:rgba(127,127,127,.15);padding:12px;border-radius:8px;overflow:auto}
code{background:rgba(127,127,127,.15);padding:2px 5px;border-radius:4px}
pre code{background:none;padding:0}
blockquote{border-left:4px solid #8886;margin-left:0;padding-left:14px;color:#888}
img{max-width:100%}table{border-collapse:collapse}td,th{border:1px solid #8886;padding:6px 10px}
</style></head><body>$body</body></html>''';
  }

  Future<void> _setDevice(PreviewDevice d) async {
    setState(() => _device = d);
    final c = _web;
    if (c == null) return;
    await c.setUserAgent(d == PreviewDevice.desktop ? _desktopUserAgent : null);
    await c.reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Preview - ${p.basename(widget.path)}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _web == null ? null : () => _web!.reload(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<PreviewDevice>(
              showSelectedIcon: false,
              segments: [
                for (final d in PreviewDevice.values)
                  ButtonSegment(value: d, label: Text(d.label), icon: Icon(d.icon, size: 18)),
              ],
              selected: {_device},
              onSelectionChanged: (s) => _setDevice(s.first),
            ),
          ),
        ),
      ),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _web == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    if (_progress < 100) LinearProgressIndicator(value: _progress / 100, minHeight: 2),
                    Expanded(
                      child: Container(
                        color: scheme.surfaceContainerHighest,
                        child: LayoutBuilder(builder: (context, box) {
                          final w = _device.width;
                          if (w <= box.maxWidth) {
                            return Center(
                              child: SizedBox(width: w, child: WebViewWidget(controller: _web!)),
                            );
                          }
                          final scale = box.maxWidth / w;
                          final virtualH = box.maxHeight / scale;
                          return FittedBox(
                            fit: BoxFit.contain,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: w,
                              height: virtualH,
                              child: WebViewWidget(controller: _web!),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
    );
  }
}
