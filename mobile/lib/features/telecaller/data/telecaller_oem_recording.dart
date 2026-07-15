import 'dart:io';

import 'telecaller_recording_setup.dart';

class OemRecordingHit {
  const OemRecordingHit({
    required this.path,
    required this.displayName,
    required this.modifiedMs,
    required this.size,
    required this.mimeType,
  });

  final String path;
  final String displayName;
  final int modifiedMs;
  final int size;
  final String mimeType;
}

/// Scans the linked OEM call-recordings folder for the newest audio file.
class TelecallerOemRecording {
  TelecallerOemRecording._();

  static const _audioExtensions = {
    '.m4a',
    '.mp3',
    '.aac',
    '.wav',
    '.amr',
    '.mp4',
    '.3gp',
    '.ogg',
    '.opus',
  };

  static String mimeForPath(String path) {
    final ext = path.toLowerCase().split('.').last;
    switch (ext) {
      case 'm4a':
      case 'mp4':
        return 'audio/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'amr':
        return 'audio/amr';
      case '3gp':
        return 'video/3gpp';
      case 'ogg':
      case 'opus':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }

  static Future<OemRecordingHit?> findNewestWithRetry({
    DateTime? modifiedAfter,
    int attempts = 10,
    Duration delay = const Duration(seconds: 2),
  }) async {
    for (var i = 0; i < attempts; i++) {
      final hit = await findNewest(modifiedAfter: modifiedAfter);
      if (hit != null) return hit;
      if (i < attempts - 1) await Future.delayed(delay);
    }
    return null;
  }

  static Future<OemRecordingHit?> findNewest({DateTime? modifiedAfter}) async {
    await TelecallerRecordingSetup.load();
    final folder = TelecallerRecordingSetup.folderPath;
    if (folder == null || folder.isEmpty) return null;

    final skipPath = TelecallerRecordingSetup.lastUploadedPath;
    final skipMs = TelecallerRecordingSetup.lastUploadedModifiedMs;

    File? best;
    var bestMs = 0;

    void consider(File file) {
      final lower = file.path.toLowerCase();
      if (!_audioExtensions.any(lower.endsWith)) return;
      if (!file.existsSync()) return;
      final modified = file.lastModifiedSync();
      final ms = modified.millisecondsSinceEpoch;
      if (modifiedAfter != null && modified.isBefore(modifiedAfter)) return;
      if (skipPath != null &&
          skipMs != null &&
          file.path == skipPath &&
          ms == skipMs) {
        return;
      }
      if (ms > bestMs) {
        bestMs = ms;
        best = file;
      }
    }

    try {
      final type = FileSystemEntity.typeSync(folder);
      if (type == FileSystemEntityType.file) {
        consider(File(folder));
      } else if (type == FileSystemEntityType.directory) {
        await for (final entity
            in Directory(folder).list(recursive: true, followLinks: false)) {
          if (entity is File) consider(entity);
        }
      }
    } catch (_) {
      return null;
    }

    final file = best;
    if (file == null) return null;
    return OemRecordingHit(
      path: file.path,
      displayName: file.path.split(Platform.pathSeparator).last,
      modifiedMs: bestMs,
      size: file.lengthSync(),
      mimeType: mimeForPath(file.path),
    );
  }
}
