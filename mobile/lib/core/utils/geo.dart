import 'dart:math' as math;

/// Shared Haversine helpers (distance in kilometres).
class Geo {
  static const earthRadiusKm = 6371.0;

  static double distanceKm(double lat1, double lon1, double lat2, double lon2) {
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    return distanceKm(lat1, lon1, lat2, lon2) * 1000.0;
  }

  static double _toRadians(double degree) => degree * (math.pi / 180.0);
}
