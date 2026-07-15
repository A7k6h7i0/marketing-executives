import 'package:shared_preferences/shared_preferences.dart';

/// Persists telecaller phone call-recording onboarding + linked folder.
class TelecallerRecordingSetup {
  TelecallerRecordingSetup._();

  static const _completeKey = 'telecaller_recording_setup_v1';
  static const _folderPathKey = 'telecaller_recording_folder_path';
  static const _folderLabelKey = 'telecaller_recording_folder_label';
  static const _lastUploadedPathKey = 'telecaller_recording_last_path';
  static const _lastUploadedMsKey = 'telecaller_recording_last_ms';

  static bool _complete = false;
  static String? _folderPath;
  static String? _folderLabel;
  static String? _lastUploadedPath;
  static int? _lastUploadedModifiedMs;
  static bool _loaded = false;

  static bool get isLoaded => _loaded;
  static bool get isComplete => _complete;
  static String? get folderPath => _folderPath;
  static String? get folderLabel => _folderLabel;
  static String? get lastUploadedPath => _lastUploadedPath;
  static int? get lastUploadedModifiedMs => _lastUploadedModifiedMs;

  static bool get hasLinkedFolder =>
      _folderPath != null && _folderPath!.isNotEmpty;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _complete = prefs.getBool(_completeKey) ?? false;
    _folderPath = prefs.getString(_folderPathKey);
    _folderLabel = prefs.getString(_folderLabelKey);
    _lastUploadedPath = prefs.getString(_lastUploadedPathKey);
    _lastUploadedModifiedMs = prefs.getInt(_lastUploadedMsKey);
    _loaded = true;
  }

  static Future<void> setFolderPath({
    required String path,
    String? displayName,
  }) async {
    _folderPath = path;
    _folderLabel = displayName ?? path.split(RegExp(r'[\\/]')).last;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_folderPathKey, path);
    await prefs.setString(_folderLabelKey, _folderLabel!);
  }

  static Future<void> markLastUploaded(String path, int modifiedMs) async {
    _lastUploadedPath = path;
    _lastUploadedModifiedMs = modifiedMs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUploadedPathKey, path);
    await prefs.setInt(_lastUploadedMsKey, modifiedMs);
  }

  static Future<void> markComplete() async {
    _complete = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completeKey, true);
  }

  static Future<void> reset() async {
    _complete = false;
    _folderPath = null;
    _folderLabel = null;
    _lastUploadedPath = null;
    _lastUploadedModifiedMs = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completeKey);
    await prefs.remove(_folderPathKey);
    await prefs.remove(_folderLabelKey);
    await prefs.remove(_lastUploadedPathKey);
    await prefs.remove(_lastUploadedMsKey);
  }
}
