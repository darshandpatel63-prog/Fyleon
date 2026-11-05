import 'package:flutter/material.dart';

enum FileCategory { images, videos, audio, documents, packages }

extension FileCategoryX on FileCategory {
  String get label {
    switch (this) {
      case FileCategory.images:
        return 'Images';
      case FileCategory.videos:
        return 'Videos';
      case FileCategory.audio:
        return 'Audio';
      case FileCategory.documents:
        return 'Documents';
      case FileCategory.packages:
        return 'APKs & archives';
    }
  }

  IconData get icon {
    switch (this) {
      case FileCategory.images:
        return Icons.image_rounded;
      case FileCategory.videos:
        return Icons.movie_rounded;
      case FileCategory.audio:
        return Icons.music_note_rounded;
      case FileCategory.documents:
        return Icons.description_rounded;
      case FileCategory.packages:
        return Icons.inventory_2_rounded;
    }
  }

  Color get color {
    switch (this) {
      case FileCategory.images:
        return const Color(0xFFDB2777);
      case FileCategory.videos:
        return const Color(0xFFEA580C);
      case FileCategory.audio:
        return const Color(0xFF9333EA);
      case FileCategory.documents:
        return const Color(0xFF2B6CD9);
      case FileCategory.packages:
        return const Color(0xFF0891B2);
    }
  }
}

const _images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'};
const _videos = {'mp4', 'mkv', 'webm', 'avi', 'mov', '3gp', 'm4v'};
const _audio = {'mp3', 'wav', 'ogg', 'm4a', 'aac', 'flac', 'opus', 'amr'};
const _documents = {
  'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'csv', 'epub',
  'rtf', 'odt', 'ods', 'odp',
};
const _packages = {'apk', 'aab', 'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'jar'};

FileCategory? categoryOfExtension(String ext) {
  final e = ext.toLowerCase();
  if (_images.contains(e)) return FileCategory.images;
  if (_videos.contains(e)) return FileCategory.videos;
  if (_audio.contains(e)) return FileCategory.audio;
  if (_documents.contains(e)) return FileCategory.documents;
  if (_packages.contains(e)) return FileCategory.packages;
  return null;
}
