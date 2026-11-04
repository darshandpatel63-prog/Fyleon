import 'dart:io';

import 'package:path/path.dart' as p;

class FileOpException implements Exception {
  const FileOpException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns low-level errors into short messages for the user.
FileOpException friendlyError(Object e) {
  if (e is FileOpException) return e;
  if (e is FileSystemException) {
    final code = e.osError?.errorCode;
    if (code == 13 || code == 1 || code == 30) {
      return const FileOpException(
          'Permission denied. Allow "all files access" for Fyleon in Settings.');
    }
    return FileOpException(e.message.isEmpty ? 'File operation failed.' : e.message);
  }
  return const FileOpException('Something went wrong.');
}

String? validateName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'Name cannot be empty';
  if (n == '.' || n == '..') return 'Invalid name';
  if (n.contains('/') || n.contains('\\')) return 'Name cannot contain / or \\';
  if (n.length > 200) return 'Name is too long';
  return null;
}

bool _exists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) != FileSystemEntityType.notFound;

bool _isDir(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) == FileSystemEntityType.directory;

String uniquePath(String dir, String name) {
  var candidate = p.join(dir, name);
  if (!_exists(candidate)) return candidate;
  final base = p.basenameWithoutExtension(name);
  final ext = p.extension(name);
  for (var i = 1; i < 1000; i++) {
    candidate = p.join(dir, '$base ($i)$ext');
    if (!_exists(candidate)) return candidate;
  }
  throw const FileOpException('Too many items with the same name');
}

Future<String> createFolder(String parent, String name) async {
  final err = validateName(name);
  if (err != null) throw FileOpException(err);
  final path = p.join(parent, name.trim());
  if (_exists(path)) throw const FileOpException('An item with this name already exists');
  try {
    await Directory(path).create();
  } catch (e) {
    throw friendlyError(e);
  }
  return path;
}

Future<String> createFile(String parent, String name, {String content = ''}) async {
  final err = validateName(name);
  if (err != null) throw FileOpException(err);
  final path = p.join(parent, name.trim());
  if (_exists(path)) throw const FileOpException('An item with this name already exists');
  try {
    await File(path).writeAsString(content);
  } catch (e) {
    throw friendlyError(e);
  }
  return path;
}

Future<String> renameEntity(String path, String newName) async {
  final err = validateName(newName);
  if (err != null) throw FileOpException(err);
  final target = p.join(p.dirname(path), newName.trim());
  if (_exists(target)) throw const FileOpException('An item with this name already exists');
  try {
    if (_isDir(path)) {
      await Directory(path).rename(target);
    } else {
      await File(path).rename(target);
    }
  } catch (e) {
    throw friendlyError(e);
  }
  return target;
}

Future<void> deleteEntity(String path) async {
  try {
    if (_isDir(path)) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  } catch (e) {
    throw friendlyError(e);
  }
}

Future<void> _copyDir(Directory src, String target) async {
  await Directory(target).create(recursive: true);
  await for (final e in src.list(followLinks: false)) {
    final dest = p.join(target, p.basename(e.path));
    if (e is Directory) {
      await _copyDir(e, dest);
    } else if (e is File) {
      await e.copy(dest);
    }
  }
}

Future<String> copyEntity(String src, String destDir) async {
  final target = uniquePath(destDir, p.basename(src));
  try {
    if (_isDir(src)) {
      if (p.isWithin(src, destDir) || p.equals(src, destDir)) {
        throw const FileOpException('Cannot copy a folder into itself');
      }
      await _copyDir(Directory(src), target);
    } else {
      await File(src).copy(target);
    }
  } catch (e) {
    throw friendlyError(e);
  }
  return target;
}

Future<String?> moveEntity(String src, String destDir) async {
  if (p.equals(p.dirname(src), destDir)) return null;
  if (_isDir(src) && (p.isWithin(src, destDir) || p.equals(src, destDir))) {
    throw const FileOpException('Cannot move a folder into itself');
  }
  final target = uniquePath(destDir, p.basename(src));
  try {
    if (_isDir(src)) {
      await Directory(src).rename(target);
    } else {
      await File(src).rename(target);
    }
  } on FileSystemException {
    // rename fails between different storages: copy, then delete the original
    try {
      await copyEntity(src, destDir);
      await deleteEntity(src);
    } catch (e) {
      throw friendlyError(e);
    }
  }
  return target;
}

// ---------------- templates ----------------

const quickExtensions = [
  '.txt', '.md', '.html', '.css', '.js', '.json', '.dart', '.py', '.java',
  '.kt', '.rs', '.xml', '.yaml',
];

String templateFor(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  final base = p.basenameWithoutExtension(fileName);
  switch (ext) {
    case '.html':
    case '.htm':
      return _htmlTemplate(base);
    case '.md':
      return '# $base\n\nWrite here.\n';
    case '.css':
      return 'body {\n  font-family: system-ui, sans-serif;\n  margin: 0;\n  padding: 16px;\n}\n';
    case '.js':
      return "console.log('Hello from $base');\n";
    case '.json':
      return '{\n  \n}\n';
    case '.dart':
      return "void main() {\n  print('Hello, Fyleon!');\n}\n";
    case '.py':
      return "print('Hello, Fyleon!')\n";
    case '.java':
      return 'public class $base {\n    public static void main(String[] args) {\n        System.out.println("Hello, Fyleon!");\n    }\n}\n';
    case '.kt':
      return 'fun main() {\n    println("Hello, Fyleon!")\n}\n';
    case '.rs':
      return 'fn main() {\n    println!("Hello, Fyleon!");\n}\n';
    case '.xml':
      return '<?xml version="1.0" encoding="utf-8"?>\n<root>\n</root>\n';
    case '.yaml':
    case '.yml':
      return '# $base\n';
    default:
      return '';
  }
}

String _htmlTemplate(String title) => '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$title</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <h1>Hello, Fyleon!</h1>
  <p>Edit this page and tap Preview.</p>
  <script src="script.js"></script>
</body>
</html>
''';

/// Creates folder `name` with index.html, style.css and script.js. Returns the index.html path.
Future<String> createWebProject(String parent, String name) async {
  final folder = await createFolder(parent, name);
  await File(p.join(folder, 'index.html')).writeAsString(_htmlTemplate(name.trim()));
  await File(p.join(folder, 'style.css')).writeAsString(
    ':root { color-scheme: light dark; }\n'
    'body {\n  font-family: system-ui, sans-serif;\n  margin: 0;\n  padding: 24px;\n  line-height: 1.5;\n}\n'
    'h1 { color: #4f46e5; }\n',
  );
  await File(p.join(folder, 'script.js')).writeAsString(
    "document.addEventListener('DOMContentLoaded', () => {\n  console.log('Project ready');\n});\n",
  );
  return p.join(folder, 'index.html');
}
