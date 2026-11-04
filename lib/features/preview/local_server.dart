import 'dart:io';

import 'package:path/path.dart' as p;

/// A tiny web server that lives only on this device (127.0.0.1).
/// It serves a project folder so relative CSS/JS/images work in the preview,
/// and can serve unsaved editor text instead of the file on disk.
class LocalPreviewServer {
  LocalPreviewServer(this.root);

  final String root;
  final Map<String, String> overrides = {}; // "/index.html" -> text
  HttpServer? _server;

  int get port => _server?.port ?? 0;

  Future<void> start() async {
    final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = s;
    s.listen(_handle);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      var rel = Uri.decodeComponent(req.uri.path);
      if (rel.endsWith('/')) rel += 'index.html';

      final override = overrides[rel];
      if (override != null) {
        req.response.headers.contentType = _mime(rel);
        req.response.headers.set('Cache-Control', 'no-store');
        req.response.write(override);
        await req.response.close();
        return;
      }

      final full = p.normalize(p.join(root, rel.substring(1)));
      if (!(p.isWithin(root, full) || p.equals(root, full))) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }
      final f = File(full);
      if (!await f.exists()) {
        req.response.statusCode = HttpStatus.notFound;
        req.response.headers.contentType = ContentType.text;
        req.response.write('404 Not found: $rel');
        await req.response.close();
        return;
      }
      req.response.headers.contentType = _mime(full);
      req.response.headers.set('Cache-Control', 'no-store');
      await req.response.addStream(f.openRead());
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  ContentType _mime(String path) {
    switch (p.extension(path).toLowerCase()) {
      case '.html':
      case '.htm':
        return ContentType.parse('text/html; charset=utf-8');
      case '.css':
        return ContentType.parse('text/css; charset=utf-8');
      case '.js':
      case '.mjs':
        return ContentType.parse('application/javascript; charset=utf-8');
      case '.json':
        return ContentType.parse('application/json; charset=utf-8');
      case '.svg':
        return ContentType.parse('image/svg+xml');
      case '.png':
        return ContentType.parse('image/png');
      case '.jpg':
      case '.jpeg':
        return ContentType.parse('image/jpeg');
      case '.gif':
        return ContentType.parse('image/gif');
      case '.webp':
        return ContentType.parse('image/webp');
      case '.ico':
        return ContentType.parse('image/x-icon');
      case '.woff':
        return ContentType.parse('font/woff');
      case '.woff2':
        return ContentType.parse('font/woff2');
      case '.ttf':
        return ContentType.parse('font/ttf');
      case '.txt':
      case '.md':
        return ContentType.parse('text/plain; charset=utf-8');
      default:
        return ContentType.binary;
    }
  }
}
