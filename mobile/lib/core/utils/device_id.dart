import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Stable per-install device fingerprint used for attendance / multi-login lock.
class DeviceId {
  static const _prefsKey = 'device_fingerprint';

  static Future<String> get() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null && existing.isNotEmpty) return existing;

    final created = const Uuid().v4();
    await prefs.setString(_prefsKey, created);
    return created;
  }
}
