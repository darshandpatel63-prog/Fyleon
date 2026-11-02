import 'package:flutter/material.dart';

enum FileKind {
  pdf,
  epub,
  word,
  excel,
  powerpoint,
  code,
  text,
  image,
  archive,
  apk,
  audio,
  video,
  other,
}

extension FileKindX on FileKind {
  String get label {
    switch (this) {
      case FileKind.pdf:
        return 'PDF';
      case FileKind.epub:
        return 'EPUB';
      case FileKind.word:
        return 'Word';
      case FileKind.excel:
        return 'Excel';
      case FileKind.powerpoint:
        return 'PowerPoint';
      case FileKind.code:
        return 'Code';
      case FileKind.text:
        return 'Text';
      case FileKind.image:
        return 'Image';
      case FileKind.archive:
        return 'Archive';
      case FileKind.apk:
        return 'APK';
      case FileKind.audio:
        return 'Audio';
      case FileKind.video:
        return 'Video';
      case FileKind.other:
        return 'File';
    }
  }

  IconData get icon {
    switch (this) {
      case FileKind.pdf:
        return Icons.picture_as_pdf_rounded;
      case FileKind.epub:
        return Icons.menu_book_rounded;
      case FileKind.word:
        return Icons.description_rounded;
      case FileKind.excel:
        return Icons.table_chart_rounded;
      case FileKind.powerpoint:
        return Icons.slideshow_rounded;
      case FileKind.code:
        return Icons.code_rounded;
      case FileKind.text:
        return Icons.article_rounded;
      case FileKind.image:
        return Icons.image_rounded;
      case FileKind.archive:
        return Icons.folder_zip_rounded;
      case FileKind.apk:
        return Icons.android_rounded;
      case FileKind.audio:
        return Icons.audiotrack_rounded;
      case FileKind.video:
        return Icons.movie_rounded;
      case FileKind.other:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color get color {
    switch (this) {
      case FileKind.pdf:
        return const Color(0xFFE5484D);
      case FileKind.epub:
        return const Color(0xFFF59E0B);
      case FileKind.word:
        return const Color(0xFF2B6CD9);
      case FileKind.excel:
        return const Color(0xFF1F9D55);
      case FileKind.powerpoint:
        return const Color(0xFFE8590C);
      case FileKind.code:
        return const Color(0xFF7C3AED);
      case FileKind.text:
        return const Color(0xFF64748B);
      case FileKind.image:
        return const Color(0xFFDB2777);
      case FileKind.archive:
        return const Color(0xFF0891B2);
      case FileKind.apk:
        return const Color(0xFF3DDC84);
      case FileKind.audio:
        return const Color(0xFF9333EA);
      case FileKind.video:
        return const Color(0xFFEA580C);
      case FileKind.other:
        return const Color(0xFF94A3B8);
    }
  }
}

const _codeExt = {
  'dart', 'java', 'kt', 'kts', 'js', 'mjs', 'cjs', 'ts', 'jsx', 'tsx', 'html',
  'htm', 'css', 'scss', 'sass', 'less', 'json', 'xml', 'svg', 'yaml', 'yml',
  'py', 'c', 'h', 'cpp', 'cc', 'hpp', 'cs', 'go', 'rs', 'rb', 'php', 'swift',
  'sh', 'bash', 'zsh', 'bat', 'cmd', 'ps1', 'sql', 'gradle', 'toml', 'ini',
  'lua', 'r', 'm', 'vue', 'svelte', 'dockerfile', 'properties', 'cfg', 'conf',
  'smali', 'pl', 'scala', 'groovy', 'tf', 'proto', 'graphql',
};
const _textExt = {'txt', 'md', 'markdown', 'log', 'csv', 'tsv', 'rtf', 'tex', 'nfo'};
const _imageExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'wbmp', 'ico'};
const _archiveExt = {
  'zip', 'jar', 'war', 'aar', 'aab', 'ipa', 'tar', 'gz', 'tgz', 'rar', '7z',
  'bz2', 'xz',
};
const _audioExt = {'mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus'};
const _videoExt = {'mp4', 'mkv', 'webm', 'avi', 'mov', '3gp', 'm4v'};

FileKind kindForExtension(String ext) {
  final e = ext.toLowerCase();
  if (e == 'pdf') return FileKind.pdf;
  if (e == 'epub') return FileKind.epub;
  if (e == 'docx' || e == 'doc' || e == 'odt') return FileKind.word;
  if (e == 'xlsx' || e == 'xls' || e == 'ods') return FileKind.excel;
  if (e == 'pptx' || e == 'ppt' || e == 'odp') return FileKind.powerpoint;
  if (e == 'apk') return FileKind.apk;
  if (_codeExt.contains(e)) return FileKind.code;
  if (_textExt.contains(e)) return FileKind.text;
  if (_imageExt.contains(e)) return FileKind.image;
  if (_archiveExt.contains(e)) return FileKind.archive;
  if (_audioExt.contains(e)) return FileKind.audio;
  if (_videoExt.contains(e)) return FileKind.video;
  return FileKind.other;
}

/// highlight.js language id for the syntax highlighter (null = plain text).
String? highlightLanguageFor(String ext) {
  switch (ext.toLowerCase()) {
    case 'dart':
      return 'dart';
    case 'java':
      return 'java';
    case 'kt':
    case 'kts':
      return 'kotlin';
    case 'js':
    case 'mjs':
    case 'cjs':
    case 'jsx':
      return 'javascript';
    case 'ts':
    case 'tsx':
      return 'typescript';
    case 'html':
    case 'htm':
    case 'xml':
    case 'svg':
    case 'vue':
      return 'xml';
    case 'css':
      return 'css';
    case 'scss':
      return 'scss';
    case 'less':
      return 'less';
    case 'json':
      return 'json';
    case 'yaml':
    case 'yml':
      return 'yaml';
    case 'py':
      return 'python';
    case 'c':
    case 'h':
      return 'c';
    case 'cpp':
    case 'cc':
    case 'hpp':
      return 'cpp';
    case 'cs':
      return 'cs';
    case 'go':
      return 'go';
    case 'rs':
      return 'rust';
    case 'rb':
      return 'ruby';
    case 'php':
      return 'php';
    case 'swift':
      return 'swift';
    case 'sh':
    case 'bash':
    case 'zsh':
      return 'bash';
    case 'bat':
    case 'cmd':
      return 'dos';
    case 'ps1':
      return 'powershell';
    case 'sql':
      return 'sql';
    case 'gradle':
    case 'groovy':
      return 'gradle';
    case 'toml':
    case 'ini':
    case 'properties':
    case 'cfg':
    case 'conf':
      return 'ini';
    case 'lua':
      return 'lua';
    case 'r':
      return 'r';
    case 'scala':
      return 'scala';
    case 'md':
    case 'markdown':
      return 'markdown';
    case 'dockerfile':
      return 'dockerfile';
    default:
      return null;
  }
}

/// Filter chips shown above the file list.
enum KindFilter { all, pdf, docs, books, code, images, archives, other }

extension KindFilterX on KindFilter {
  String get label {
    switch (this) {
      case KindFilter.all:
        return 'All';
      case KindFilter.pdf:
        return 'PDF';
      case KindFilter.docs:
        return 'Docs';
      case KindFilter.books:
        return 'Books';
      case KindFilter.code:
        return 'Code';
      case KindFilter.images:
        return 'Images';
      case KindFilter.archives:
        return 'Archives';
      case KindFilter.other:
        return 'Other';
    }
  }

  bool matches(FileKind k) {
    switch (this) {
      case KindFilter.all:
        return true;
      case KindFilter.pdf:
        return k == FileKind.pdf;
      case KindFilter.docs:
        return k == FileKind.word ||
            k == FileKind.excel ||
            k == FileKind.powerpoint ||
            k == FileKind.text;
      case KindFilter.books:
        return k == FileKind.epub;
      case KindFilter.code:
        return k == FileKind.code;
      case KindFilter.images:
        return k == FileKind.image;
      case KindFilter.archives:
        return k == FileKind.archive || k == FileKind.apk;
      case KindFilter.other:
        return k == FileKind.audio || k == FileKind.video || k == FileKind.other;
    }
  }
}
