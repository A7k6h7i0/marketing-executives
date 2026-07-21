import 'dart:io';

import 'package:dio/dio.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';
import 'production_api_service.dart';

/// Compatibility facade used by [AppProvider].
/// All calls go to [ProductionApiService] (sales.digitalleadpro.com).
class FieldApiService {
  FieldApiService(this._client) : _prod = ProductionApiService(_client);

  final ApiClient _client;
  final ProductionApiService _prod;

  ProductionApiService get production => _prod;

  Response _ok(dynamic data, {int status = 200}) {
    return Response(
      requestOptions: RequestOptions(path: ''),
      data: data is Map && data.containsKey('success')
          ? data
          : {'success': true, 'data': data},
      statusCode: status,
    );
  }

  // ── Auth ──────────────────────────────────────────────────────────
  Future<Response> login({
    required String password,
    String deviceId = '',
    String? email,
    String? phone,
    String? orgSlug,
    String? loginSelfieUrl,
  }) async {
    final data = await _prod.login(
      password: password,
      email: email,
      phone: phone,
      orgSlug: orgSlug,
      loginSelfieUrl: loginSelfieUrl,
      deviceId: deviceId,
    );
    return _ok(data);
  }

  Future<Response> logout(String deviceId, {String? refreshToken}) async {
    await _prod.logout(deviceId: deviceId, refreshToken: refreshToken);
    return _ok({});
  }

  Future<Map<String, dynamic>?> checkOutAttendance({
    required double latitude,
    required double longitude,
  }) {
    return _prod.attendanceCheckOut(latitude: latitude, longitude: longitude);
  }

  Future<List<Map<String, dynamic>>> attendanceList({int page = 1, int perPage = 100}) {
    return _prod.attendanceList(page: page, perPage: perPage);
  }

  Future<bool> adminForceLogout(String userId) => _prod.adminForceLogout(userId);

  // ── Attendance ────────────────────────────────────────────────────
  Future<Response> attendanceToday(String userId) async {
    final list = await _prod.attendanceMy();
    Map<String, dynamic>? open;
    for (final a in list) {
      if (a['check_out_at'] == null) {
        open = a;
        break;
      }
    }
    open ??= list.isNotEmpty ? list.first : null;
    if (open == null) return _ok({});
    return _ok({
      'attendanceId': open['id'],
      'status': open['status'] == 'checked_in' ? 'LOGGED_IN' : open['status'],
      'loginTime': open['check_in_at'],
      'logoutTime': open['check_out_at'],
      'raw': open,
      'list': list,
    });
  }

  Future<Map<String, dynamic>?> checkInAttendance({
    required double latitude,
    required double longitude,
  }) {
    return _prod.attendanceCheckIn(latitude: latitude, longitude: longitude);
  }

  // ── Breaks ────────────────────────────────────────────────────────
  Future<Response> startBreak(String breakType) => _prod.startBreak(breakType);

  Future<Response> endBreak(String breakId) => _prod.endBreak(breakId);

  Future<Response> todayBreaks(String userId) => _prod.todayBreaks();

  // ── GPS ───────────────────────────────────────────────────────────
  Future<Response> gpsPing({
    required double latitude,
    required double longitude,
    required String trackingStartPoint,
    String? timestamp,
    String? address,
    String? deviceId,
    double? accuracy,
    String? offlineId,
  }) async {
    final ping = await _prod.gpsLog(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      address: address,
      deviceId: deviceId,
      trackingStartPoint: trackingStartPoint,
      accuracy: accuracy,
      offlineId: offlineId,
    );
    return _ok({'ping': ping});
  }

  Future<List<Map<String, dynamic>>> gpsLive() => _prod.gpsLive();

  Future<List<Map<String, dynamic>>> gpsHistory({String? userId, int page = 1, int perPage = 100}) {
    return _prod.gpsHistory(userId: userId, page: page, perPage: perPage);
  }

  Future<List<Map<String, dynamic>>> adminUserSessions(String userId) {
    return _prod.adminUserSessions(userId);
  }

  Future<Response> gpsSummary(String userId, String date) async {
    return _ok({'totalDistanceKm': 0});
  }

  Future<Response> gpsRoute(String userId, String date) async {
    return _ok([]);
  }

  // ── Routes / plan (production field-routes + outlets) ─────────────
  Future<Response> getRoutes() async {
    final routes = await _prod.fieldRoutes();
    final mapped = routes.map((r) {
      return {
        'id': r['id'],
        'name': r['name'] ?? 'Route',
        'region': r['description'] ?? r['territory_id'] ?? '',
        'outlet_ids': r['outlet_ids'] ?? [],
        'raw': r,
      };
    }).toList();
    return _ok(mapped);
  }

  Future<Response> getRouteOutlets(String routeId) async {
    final routes = await _prod.fieldRoutes();
    Map<String, dynamic>? route;
    for (final r in routes) {
      if (r['id']?.toString() == routeId) {
        route = r;
        break;
      }
    }
    final outletIds = (route?['outlet_ids'] as List?)?.map((e) => e.toString()).toSet() ?? {};
    final allOutlets = await _prod.outlets();
    final filtered = outletIds.isEmpty
        ? allOutlets
        : allOutlets.where((o) => outletIds.contains(o['id']?.toString())).toList();

    final mapped = filtered.map(_mapOutlet).toList();
    return _ok({'outlets': mapped, 'data': mapped});
  }

  Map<String, dynamic> _mapOutlet(Map<String, dynamic> o) {
    return {
      'id': o['id'],
      'name': o['name'] ?? 'Outlet',
      'address': o['address'] ?? o['city'] ?? '',
      'latitude': o['latitude'] ?? o['gpsLat'] ?? 0,
      'longitude': o['longitude'] ?? o['gpsLng'] ?? 0,
      'phone': o['phone'],
      'visitStatus': 'PENDING',
      'raw': o,
    };
  }

  Future<Response> savePlan({
    required String areaName,
    required int plannedVisits,
    String? routeId,
    String? planDate,
  }) async {
    // Production uses field-routes; selecting a route is enough for the mobile plan.
    return _ok({
      'plan': {
        'id': routeId ?? 'plan-local',
        'areaName': areaName,
        'plannedVisits': plannedVisits,
        'routeId': routeId,
        'planDate': planDate,
      },
    });
  }

  Future<Response> todayPlan(String userId) async {
    final routes = await _prod.fieldRoutes();
    final outlets = await _prod.outlets();
    final mappedOutlets = outlets.map(_mapOutlet).toList();
    return _ok({
      'plan': {
        'id': routes.isNotEmpty ? routes.first['id'] : 'today',
        'areaName': routes.isNotEmpty ? routes.first['name'] : 'Today',
        'plannedVisits': mappedOutlets.length,
        'completedVisits': 0,
      },
      'outlets': mappedOutlets,
      'progress': {
        'planned': mappedOutlets.length,
        'completed': 0,
        'percentage': 0,
      },
    });
  }

  // ── Visits ────────────────────────────────────────────────────────
  Future<Response> checkInVisit({
    required double gpsLat,
    required double gpsLng,
    required String selfieUrl,
    String? outletId,
    Map<String, dynamic>? outlet,
    bool managerOverrideFlag = false,
  }) async {
    String resolvedOutletId = outletId ?? '';
    if (resolvedOutletId.isEmpty && outlet != null) {
      final created = await _prod.createOutlet({
        'name': outlet['name'] ?? 'Outlet',
        'phone': outlet['phone'] ?? outlet['contactPhone'],
        'address': outlet['address'],
        'latitude': outlet['gpsLat'] ?? outlet['latitude'] ?? gpsLat,
        'longitude': outlet['gpsLng'] ?? outlet['longitude'] ?? gpsLng,
        'type': 'retailer',
      });
      resolvedOutletId = created?['id']?.toString() ?? '';
    }
    if (resolvedOutletId.isEmpty) {
      throw DioException(
        requestOptions: RequestOptions(path: ApiEndpoints.visitsStart),
        message: 'outlet_id is required',
      );
    }

    final visit = await _prod.visitStart(
      outletId: resolvedOutletId,
      latitude: gpsLat,
      longitude: gpsLng,
    );
    return _ok({'visit': visit}, status: 201);
  }

  Future<Response> submitVisitOrder({
    required String visitId,
    required List<Map<String, dynamic>> productsOrdered,
    String? remarks,
    String? outletId,
  }) async {
    final totalAmount = productsOrdered.fold<double>(
      0,
      (sum, p) =>
          sum +
          ((double.tryParse(p['unitPrice']?.toString() ?? '') ?? 0) *
              (double.tryParse(p['qty']?.toString() ?? '1') ?? 1)),
    );

    // Keep order total in notes so admin Logs can read it from GET /visits
    // (production stores money on /orders, not visit.sales_value).
    final orderTag = 'ORDER_TOTAL=${totalAmount.toStringAsFixed(2)}';
    final baseRemarks = (remarks ?? '').trim();
    final notesWithTotal = baseRemarks.isEmpty
        ? orderTag
        : (baseRemarks.contains('ORDER_TOTAL=') ? baseRemarks : '$baseRemarks|$orderTag');

    final items = productsOrdered.map((p) {
      return {
        'product_id': p['productId'] ?? p['product_id'] ?? p['id'] ?? p['sku'],
        'quantity': p['qty'] ?? p['quantity'] ?? 1,
        'price': p['unitPrice'] ?? p['price'] ?? 0,
      };
    }).toList();

    final order = await _prod.createOrder(
      outletId: outletId ?? '',
      visitId: visitId,
      items: items,
      notes: notesWithTotal,
      totalAmount: totalAmount,
    );
    return _ok({
      'order': order,
      'order_total': totalAmount,
      'notes': notesWithTotal,
    }, status: 201);
  }

  Future<Response> checkoutVisit(
    String visitId, {
    double? latitude,
    double? longitude,
    String? outcome,
    String? notes,
    DateTime? nextVisitDate,
  }) async {
    final visit = await _prod.visitEnd(
      visitId: visitId,
      latitude: latitude ?? 0,
      longitude: longitude ?? 0,
      outcome: outcome ?? 'completed',
      notes: notes,
      nextVisitDate: nextVisitDate,
    );
    return _ok({'visit': visit});
  }

  Future<Response> visitsForDate(String userId, String date) async {
    return _ok([]);
  }

  Future<Response> products({String? query}) async {
    final list = await _prod.products(query: query);
    final mapped = list.map((p) {
      return {
        'id': p['id'],
        'sku': p['sku'],
        'name': p['name'],
        'price': p['ptr'] ?? p['mrp'] ?? p['price'] ?? 0,
        'unitPrice': p['ptr'] ?? p['mrp'] ?? p['price'] ?? 0,
        'unit_price': p['ptr'] ?? p['mrp'] ?? p['price'] ?? 0,
        'mrp': p['mrp'],
        'ptr': p['ptr'],
        'size': p['pack_size'] ?? p['size'] ?? p['uom'],
        'raw': p,
      };
    }).toList();
    return _ok({'products': mapped});
  }

  Future<String> uploadSelfie(File file) async {
    final url = await _prod.uploadLoginSelfie(file) ?? await _prod.uploadSelfie(file);
    if (url == null || url.isEmpty) {
      throw Exception('Selfie upload not available on server yet');
    }
    return url;
  }

  /// Upload blink/login selfie to production `/media/upload-login-selfie`.
  Future<String?> uploadLoginSelfie(File file) => _prod.uploadLoginSelfie(file);

  // ── Outlets ───────────────────────────────────────────────────────
  Future<Response> ensureOutlet(Map<String, dynamic> outlet) async {
    final created = await _prod.createOutlet({
      'name': outlet['name'],
      'address': outlet['address'],
      'phone': outlet['contactPhone'] ?? outlet['phone'],
      'email': outlet['contactEmail'] ?? outlet['email'],
      'latitude': outlet['gpsLat'] ?? outlet['latitude'],
      'longitude': outlet['gpsLng'] ?? outlet['longitude'],
      'type': outlet['type'] ?? 'retailer',
    });
    return _ok({'outlet': created}, status: created == null ? 400 : 201);
  }

  Future<Response> submitRating({
    required String outletId,
    required int paymentScore,
    required int volumeScore,
    required int cooperationScore,
    required int consistencyScore,
    required int relationshipScore,
  }) {
    return _client.post(ApiEndpoints.outletRatings(outletId), data: {
      'paymentScore': paymentScore,
      'volumeScore': volumeScore,
      'cooperationScore': cooperationScore,
      'consistencyScore': consistencyScore,
      'relationshipScore': relationshipScore,
    });
  }

  Future<Response> outletGrade(String outletId) {
    return _client.get(ApiEndpoints.outletGrade(outletId));
  }

  // ── Incidents ─────────────────────────────────────────────────────
  Future<Response> createIncident({
    required String incidentType,
    required String description,
    List<String>? imageUrls,
    List<String>? videoUrls,
  }) async {
    final type = incidentType.toLowerCase().contains('vehicle')
        ? 'vehicle_breakdown'
        : incidentType.toLowerCase();
    final created = await _prod.createIncident(type: type, description: description);
    return _ok({'incident': created}, status: created == null ? 400 : 201);
  }

  Future<Response> userIncidents(String userId) async {
    final list = await _prod.listIncidents();
    final mapped = list.map((i) {
      return {
        'id': i['id'],
        'incidentType': i['type'] ?? i['incidentType'],
        'description': i['description'],
        'status': i['status'],
        'createdAt': i['created_at'],
        'raw': i,
      };
    }).toList();
    return _ok({'incidents': mapped});
  }

  // ── Leads ─────────────────────────────────────────────────────────
  Future<Response> nearbyLeads({
    required double lat,
    required double lng,
    String? category,
  }) async {
    final list = await _prod.listLeads();
    return _ok({'leads': list});
  }

  Future<Response> saveLead(Map<String, dynamic> data) async {
    final created = await _prod.saveLead(data);
    return _ok({'lead': created}, status: created == null ? 400 : 201);
  }

  Future<Response> listLeads() async {
    final list = await _prod.listLeads();
    final mapped = list.map((item) {
      return {
        'id': item['id'],
        'businessName': item['name'] ?? item['businessName'] ?? 'Lead',
        'businessCategory': item['business_type'] ?? item['businessCategory'] ?? 'Business',
        'contactPhone': item['phone'] ?? item['contactPhone'] ?? '',
        'contactEmail': item['email'] ?? item['contactEmail'] ?? '',
        'address': item['address'] ?? '',
        'gpsLat': item['gps_lat'] ?? item['latitude'] ?? 0,
        'gpsLng': item['gps_lng'] ?? item['longitude'] ?? 0,
        'leadStatus': (item['status'] ?? 'new').toString().toUpperCase(),
        'raw': item,
      };
    }).toList();
    return _ok({'leads': mapped});
  }

  Future<Response> convertLead(String leadId, {Map<String, dynamic>? lead}) async {
    final outlet = await _prod.convertLead(leadId, lead: lead);
    return _ok({'outlet': outlet}, status: outlet == null ? 400 : 201);
  }

  // ── Route optimize (optional) ─────────────────────────────────────
  Future<Response> optimizeRoute(Map<String, dynamic> data) {
    return _client.post(ApiEndpoints.routesOptimize, data: data);
  }

  Future<Response> skipRouteStop(String routeId, String stopId) {
    return _client.patch(ApiEndpoints.routesOptimizeSkip(routeId, stopId));
  }

  // ── Admin ─────────────────────────────────────────────────────────
  Future<Response> adminKpis() async {
    final stats = await _prod.adminStats();
    return _ok(stats);
  }

  Future<Response> adminUsers() async {
    final users = await _prod.adminUsers();
    final mapped = users.map((u) {
      return {
        'id': u['id'],
        'name': u['name'] ?? u['email'] ?? 'User',
        'email': u['email'],
        'role': u['role'],
        'status': (u['status'] ?? 'active').toString().toLowerCase() == 'active' ? 'active' : 'inactive',
        'designation': u['role'],
        'phone': u['phone'],
        'raw': u,
      };
    }).toList();
    // Return list under both shapes so _responseList can find it.
    return _ok({'users': mapped});
  }
}
