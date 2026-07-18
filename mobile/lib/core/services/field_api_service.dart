import 'dart:io';

import 'package:dio/dio.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';

/// Thin typed wrappers over the field-force REST API.
/// Keeps HTTP details out of [AppProvider].
class FieldApiService {
  FieldApiService(this._client);

  final ApiClient _client;

  // ── Auth ──────────────────────────────────────────────────────────
  Future<Response> login({
    required String password,
    required String deviceId,
    String? email,
    String? phone,
  }) {
    return _client.post(ApiEndpoints.login, data: {
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      'password': password,
      'deviceId': deviceId,
    });
  }

  Future<Response> logout(String deviceId) {
    return _client.post(ApiEndpoints.logout, data: {'deviceId': deviceId});
  }

  // ── Attendance ────────────────────────────────────────────────────
  Future<Response> attendanceToday(String userId) {
    return _client.get(ApiEndpoints.attendanceToday(userId));
  }

  // ── Breaks ────────────────────────────────────────────────────────
  Future<Response> startBreak(String breakType) {
    return _client.post(ApiEndpoints.breaksStart, data: {'breakType': breakType});
  }

  Future<Response> endBreak(String breakId) {
    return _client.patch(ApiEndpoints.breaksEnd(breakId));
  }

  Future<Response> todayBreaks(String userId) {
    return _client.get(ApiEndpoints.breaksToday(userId));
  }

  // ── GPS ───────────────────────────────────────────────────────────
  Future<Response> gpsPing({
    required double latitude,
    required double longitude,
    required String trackingStartPoint,
    String? timestamp,
  }) {
    return _client.post(ApiEndpoints.gpsPing, data: {
      'latitude': latitude,
      'longitude': longitude,
      'trackingStartPoint': trackingStartPoint,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  Future<Response> gpsSummary(String userId, String date) {
    return _client.get(ApiEndpoints.gpsSummary(userId, date));
  }

  Future<Response> gpsRoute(String userId, String date) {
    return _client.get(ApiEndpoints.gpsRoute(userId, date));
  }

  // ── Plans ─────────────────────────────────────────────────────────
  Future<Response> getRoutes() => _client.get(ApiEndpoints.routes);

  Future<Response> getRouteOutlets(String routeId) {
    return _client.get(ApiEndpoints.routeOutlets(routeId));
  }

  Future<Response> savePlan({
    required String areaName,
    required int plannedVisits,
    String? routeId,
    String? planDate,
  }) {
    return _client.post(ApiEndpoints.plans, data: {
      'areaName': areaName,
      'plannedVisits': plannedVisits,
      if (routeId != null) 'routeId': routeId,
      if (planDate != null) 'planDate': planDate,
    });
  }

  Future<Response> todayPlan(String userId) {
    return _client.get(ApiEndpoints.plansToday(userId));
  }

  // ── Visits ────────────────────────────────────────────────────────
  Future<Response> checkInVisit({
    required double gpsLat,
    required double gpsLng,
    required String selfieUrl,
    String? outletId,
    Map<String, dynamic>? outlet,
    bool managerOverrideFlag = false,
  }) {
    return _client.post(ApiEndpoints.visitsCheckIn, data: {
      if (outletId != null) 'outletId': outletId,
      if (outlet != null) 'outlet': outlet,
      'gpsLat': gpsLat,
      'gpsLng': gpsLng,
      'selfieUrl': selfieUrl,
      'managerOverrideFlag': managerOverrideFlag,
    });
  }

  Future<Response> submitVisitOrder({
    required String visitId,
    required List<Map<String, dynamic>> productsOrdered,
    String? remarks,
  }) {
    return _client.post(ApiEndpoints.visitOrder(visitId), data: {
      'productsOrdered': productsOrdered,
      if (remarks != null) 'remarks': remarks,
    });
  }

  Future<Response> checkoutVisit(String visitId) {
    return _client.patch(ApiEndpoints.visitCheckout(visitId));
  }

  Future<Response> visitsForDate(String userId, String date) {
    return _client.get(ApiEndpoints.visitsByDate(userId, date));
  }

  Future<Response> products({String? query}) {
    return _client.get(
      ApiEndpoints.products,
      queryParameters: query == null || query.isEmpty ? null : {'q': query},
    );
  }

  Future<String> uploadSelfie(File file) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
    });
    final response = await _client.post(ApiEndpoints.uploadSelfie, data: form);
    final body = response.data;
    if (body is Map && body['url'] != null) {
      final url = body['url'].toString();
      if (url.startsWith('http')) return url;
      return '${ApiEndpoints.baseUrl}$url';
    }
    throw Exception('Selfie upload did not return a URL');
  }

  // ── Outlets / ratings ─────────────────────────────────────────────
  Future<Response> ensureOutlet(Map<String, dynamic> outlet) {
    return _client.post(ApiEndpoints.outlets, data: outlet);
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
  }) {
    return _client.post(ApiEndpoints.incidents, data: {
      'incidentType': incidentType,
      'description': description,
      'imageUrls': imageUrls ?? [],
      'videoUrls': videoUrls ?? [],
    });
  }

  Future<Response> userIncidents(String userId) {
    return _client.get(ApiEndpoints.incidentsByUser(userId));
  }

  // ── Leads ─────────────────────────────────────────────────────────
  Future<Response> nearbyLeads({
    required double lat,
    required double lng,
    String? category,
  }) {
    return _client.get(ApiEndpoints.leadsNearby, queryParameters: {
      'lat': lat,
      'lng': lng,
      if (category != null) 'category': category,
    });
  }

  Future<Response> saveLead(Map<String, dynamic> data) {
    return _client.post(ApiEndpoints.leads, data: data);
  }

  Future<Response> listLeads() => _client.get(ApiEndpoints.leads);

  Future<Response> convertLead(String leadId) {
    return _client.post(ApiEndpoints.leadConvert(leadId));
  }

  // ── Route optimize ────────────────────────────────────────────────
  Future<Response> optimizeRoute(Map<String, dynamic> data) {
    return _client.post(ApiEndpoints.routesOptimize, data: data);
  }

  Future<Response> skipRouteStop(String routeId, String stopId) {
    return _client.patch(ApiEndpoints.routesOptimizeSkip(routeId, stopId));
  }

  // ── Admin ─────────────────────────────────────────────────────────
  Future<Response> adminKpis() => _client.get(ApiEndpoints.adminKpis);

  Future<Response> adminUsers() => _client.get(ApiEndpoints.adminUsers);
}
