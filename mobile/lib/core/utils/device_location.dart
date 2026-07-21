import 'dart:io';

import 'package:geolocator/geolocator.dart';

enum LocationAccessResult {
  granted,
  serviceDisabled,
  denied,
  deniedForever,
}

/// Cross-OEM location helpers so GPS works on Play Services and non-GMS phones.
class DeviceLocation {
  DeviceLocation._();

  static LocationSettings trackingSettings({
    LocationAccuracy accuracy = LocationAccuracy.medium,
    Duration timeLimit = const Duration(seconds: 12),
  }) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: 0,
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 5),
        timeLimit: timeLimit,
      );
    }
    return LocationSettings(accuracy: accuracy, timeLimit: timeLimit);
  }

  static LocationSettings oneShotSettings({
    LocationAccuracy accuracy = LocationAccuracy.high,
    Duration timeLimit = const Duration(seconds: 10),
  }) {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        forceLocationManager: true,
        timeLimit: timeLimit,
      );
    }
    return LocationSettings(accuracy: accuracy, timeLimit: timeLimit);
  }

  /// Explicitly request location access (shows the system permission dialog).
  static Future<LocationAccessResult> ensureAccess({bool requestBackground = false}) async {
    final serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) return LocationAccessResult.serviceDisabled;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return LocationAccessResult.denied;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationAccessResult.deniedForever;
    }

    // Background is optional; while-in-use is enough for active field tracking.
    if (requestBackground &&
        permission == LocationPermission.whileInUse &&
        Platform.isAndroid) {
      await Geolocator.requestPermission();
    }

    return LocationAccessResult.granted;
  }

  static Future<void> openSettings({bool locationServices = false}) async {
    if (locationServices) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  /// Prefer last-known (fast), then a fresh fix. Returns null if unavailable.
  static Future<Position?> resolvePosition({
    Duration timeLimit = const Duration(seconds: 8),
    bool requestIfNeeded = true,
  }) async {
    try {
      if (requestIfNeeded) {
        final access = await ensureAccess();
        if (access != LocationAccessResult.granted) return null;
      } else {
        if (!await Geolocator.isLocationServiceEnabled()) return null;
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return null;
        }
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && last.latitude.abs() > 0.01 && last.longitude.abs() > 0.01) {
        // Refresh in background-ish: still try a current fix when last is stale (>2 min).
        final age = DateTime.now().difference(last.timestamp);
        if (age.inMinutes < 2) return last;
      }

      return await Geolocator.getCurrentPosition(
        locationSettings: oneShotSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }
}
