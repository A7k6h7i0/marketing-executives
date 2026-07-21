import 'dart:math' as math;

import 'package:dio/dio.dart';

/// Client for https://data.mytaskking.com business directory.
class BusinessDataService {
  BusinessDataService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'Accept': 'application/json',
                  'User-Agent': 'FieldForceMobile/1.0',
                },
                validateStatus: (code) => code != null && code < 500,
              ),
            );

  final Dio _dio;

  static const _searchUrl = 'https://data.mytaskking.com/api/v1/businesses/search';
  static const _nominatimUrl = 'https://nominatim.openstreetmap.org/search';

  static final _stopWords = {
    'the', 'and', 'for', 'near', 'shop', 'store', 'stores', 'in', 'at', 'of', 'a', 'an',
  };

  /// Search shops by keyword and/or area. Kept to a few API calls so results load quickly.
  Future<List<Map<String, dynamic>>> searchBusinesses({
    required String query,
    String? area,
    double? latitude,
    double? longitude,
    double radiusKm = 10,
    int page = 1,
    int limit = 30,
  }) async {
    final q = query.trim();
    final areaText = area?.trim() ?? '';
    if (q.isEmpty && areaText.isEmpty && latitude == null) {
      return [];
    }

    double? lat = latitude;
    double? lng = longitude;

    if ((lat == null || lng == null) && areaText.isNotEmpty) {
      final geo = await _geocodeAreaHttp(areaText);
      if (geo != null) {
        lat = geo.$1;
        lng = geo.$2;
      }
    }

    // Prefer one strong query term (full phrase, else first meaningful token).
    final term = q.isNotEmpty ? q : areaText;
    final tokens = q
        .split(RegExp(r'[\s,./|+-]+'))
        .map((t) => t.trim())
        .where((t) => t.length >= 3 && !_stopWords.contains(t.toLowerCase()))
        .toList();
    final shortTerm = tokens.isNotEmpty ? tokens.first : term;

    final attempts = <Map<String, dynamic>>[];

    void add(Map<String, dynamic> params) {
      // Deduplicate identical attempt maps.
      final key = params.entries.map((e) => '${e.key}=${e.value}').join('&');
      if (attempts.any((a) => a.entries.map((e) => '${e.key}=${e.value}').join('&') == key)) {
        return;
      }
      attempts.add(params);
    }

    if (lat != null && lng != null && term.isNotEmpty) {
      add({
        'page': page,
        'limit': limit,
        'q': term,
        'lat': lat,
        'lng': lng,
        'radius': radiusKm,
      });
    }
    if (term.isNotEmpty) {
      add({'page': page, 'limit': limit, 'q': term});
    }
    // One lightweight fallback if phrase is long.
    if (shortTerm.isNotEmpty && shortTerm.toLowerCase() != term.toLowerCase()) {
      if (lat != null && lng != null) {
        add({
          'page': page,
          'limit': limit,
          'q': shortTerm,
          'lat': lat,
          'lng': lng,
          'radius': radiusKm,
        });
      } else {
        add({'page': page, 'limit': limit, 'q': shortTerm});
      }
    }
    if (q.isEmpty && areaText.isNotEmpty && lat != null && lng != null) {
      add({
        'page': page,
        'limit': limit,
        'lat': lat,
        'lng': lng,
        'radius': radiusKm,
      });
    }

    final seenIds = <String>{};
    final pooled = <Map<String, dynamic>>[];
    DioException? lastError;

    for (final params in attempts) {
      try {
        final response = await _dio.get(_searchUrl, queryParameters: params);
        if (response.statusCode != null && response.statusCode! >= 400) continue;
        for (final raw in _parseList(response.data)) {
          final item = _normalize(raw, originLat: lat, originLng: lng);
          final id = item['id']?.toString() ?? item['placeId']?.toString() ?? '';
          final key = id.isNotEmpty ? id : '${item['businessName']}|${item['address']}';
          if (seenIds.add(key)) pooled.add(item);
        }
        // Stop early once we have enough candidates.
        if (pooled.length >= limit) break;
      } on DioException catch (e) {
        lastError = e;
      }
    }

    if (pooled.isEmpty) {
      if (lastError != null) throw lastError;
      return [];
    }

    if (q.isEmpty) {
      _sortByDistance(pooled);
      return pooled.take(limit).toList();
    }

    final ranked = pooled
        .map((item) => (item: item, score: _relevanceScore(item, q, areaText)))
        .where((e) => e.score > 0)
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final da = a.item['distanceMeters'];
        final db = b.item['distanceMeters'];
        if (da is int && db is int) return da.compareTo(db);
        return 0;
      });

    if (ranked.isEmpty) return [];
    return ranked.take(limit).map((e) => e.item).toList();
  }

  void _sortByDistance(List<Map<String, dynamic>> items) {
    items.sort((a, b) {
      final da = a['distanceMeters'];
      final db = b['distanceMeters'];
      if (da is int && db is int) return da.compareTo(db);
      if (da is int) return -1;
      if (db is int) return 1;
      return 0;
    });
  }

  int _relevanceScore(Map<String, dynamic> item, String query, String area) {
    final name = (item['businessName']?.toString() ?? '').toLowerCase();
    final category = (item['businessCategory']?.toString() ?? '').toLowerCase();
    final address = (item['address']?.toString() ?? '').toLowerCase();
    final identity = '$name $category';
    final qLower = query.toLowerCase().trim();

    var score = 0;

    if (name == qLower) score += 100;
    if (name.contains(qLower)) score += 50;
    if (identity.contains(qLower)) score += 30;

    final tokens = qLower
        .split(RegExp(r'[\s,./|+-]+'))
        .where((t) => t.length >= 3 && !_stopWords.contains(t))
        .toList();

    var tokenHits = 0;
    for (final t in tokens) {
      if (name.contains(t)) {
        score += 20;
        tokenHits++;
      } else if (category.contains(t)) {
        score += 14;
        tokenHits++;
      }
    }

    if (tokens.isEmpty) return 0;
    if (tokenHits == 0) return 0;

    if (tokens.length >= 2 && tokenHits < (tokens.length / 2).ceil()) return 0;

    if (area.isNotEmpty && address.contains(area.toLowerCase())) score += 8;

    if (qLower.contains('general store') &&
        !(name.contains('general') || category.contains('general'))) {
      return 0;
    }

    return score;
  }

  Future<(double, double)?> _geocodeAreaHttp(String area) async {
    try {
      final response = await _dio.get(
        _nominatimUrl,
        queryParameters: {
          'q': '$area, India',
          'format': 'json',
          'limit': 1,
          'countrycodes': 'in',
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
            'User-Agent': 'FieldForceMobile/1.0 (prospect search)',
          },
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final list = response.data;
      if (list is! List || list.isEmpty) return null;
      final first = Map<String, dynamic>.from(list.first as Map);
      final lat = double.tryParse(first['lat']?.toString() ?? '');
      final lng = double.tryParse(first['lon']?.toString() ?? '');
      if (lat == null || lng == null) return null;
      return (lat, lng);
    } catch (_) {
      return null;
    }
  }

  List<dynamic> _parseList(dynamic body) {
    if (body is Map && body['data'] is List) return body['data'] as List;
    if (body is List) return body;
    return const [];
  }

  double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  double _rad(double deg) => deg * math.pi / 180.0;

  Map<String, dynamic> _normalize(dynamic raw, {double? originLat, double? originLng}) {
    final item = Map<String, dynamic>.from(raw as Map);
    final lat = double.tryParse(item['latitude']?.toString() ?? '') ??
        double.tryParse(item['lat']?.toString() ?? '') ??
        0.0;
    final lng = double.tryParse(item['longitude']?.toString() ?? '') ??
        double.tryParse(item['lng']?.toString() ?? '') ??
        double.tryParse(item['lon']?.toString() ?? '') ??
        0.0;

    int? distanceMeters;
    final distanceKm = double.tryParse(item['distance']?.toString() ?? '');
    if (distanceKm != null) {
      distanceMeters = (distanceKm * 1000).round();
    } else if (originLat != null &&
        originLng != null &&
        !(lat.abs() < 0.01 && lng.abs() < 0.01)) {
      distanceMeters = _haversineMeters(originLat, originLng, lat, lng).round();
    }

    final categories = item['categories'];
    final categoryLabel = categories is List
        ? categories.join(', ')
        : (item['main_category'] ?? categories ?? 'Business');

    final featured = item['featured_image'] ??
        item['featuredImage'] ??
        item['image'] ??
        item['photo'] ??
        item['thumbnail'] ??
        (item['images'] is List && (item['images'] as List).isNotEmpty
            ? (item['images'] as List).first
            : null);

    return {
      'id': item['id']?.toString() ?? item['place_id']?.toString() ?? '',
      'placeId': item['place_id']?.toString() ?? '',
      'businessName': item['name'] ?? 'Unknown Business',
      'businessCategory': categoryLabel,
      'address': item['address'] ?? '',
      'contactPhone': item['phone'] ?? '',
      'contactEmail': '',
      'website': item['website'] ?? '',
      'rating': item['rating'],
      'gpsLat': lat,
      'gpsLng': lng,
      'distanceMeters': distanceMeters,
      'featuredImage': featured?.toString(),
      'source': 'mytaskking',
    };
  }
}
