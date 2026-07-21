import 'dart:io';

import 'package:dio/dio.dart';
import '../constants/api_endpoints.dart';
import '../network/api_client.dart';

/// Single production SFA API surface used by [AppProvider].
class ProductionApiService {
  ProductionApiService(this._client);

  final ApiClient _client;

  // ── Auth ──────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> login({
    required String password,
    String? email,
    String? phone,
    String? orgSlug,
    String? loginSelfieUrl,
    String? deviceId,
  }) async {
    final response = await _client.post(ApiEndpoints.login, data: {
      if (email != null && email.isNotEmpty) 'email': email,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
      'password': password,
      // Production auth schema requires device_id (VALIDATION_ERROR → "Invalid request.").
      'device_id': (deviceId != null && deviceId.trim().isNotEmpty)
          ? deviceId.trim()
          : 'flutter-unknown-device',
      if (orgSlug != null && orgSlug.isNotEmpty) 'org_slug': orgSlug,
      if (loginSelfieUrl != null && loginSelfieUrl.isNotEmpty) 'login_selfie_url': loginSelfieUrl,
    });
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(
                requestOptions: response.requestOptions,
                response: response,
                type: DioExceptionType.badResponse,
              ),
            ) ??
            'Login failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> logout() async {
    try {
      await _client.post(ApiEndpoints.logout);
    } catch (_) {}
  }

  // ── Attendance ────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> attendanceCheckIn({
    required double latitude,
    required double longitude,
  }) async {
    final response = await _client.post(ApiEndpoints.attendanceCheckIn, data: {
      'latitude': latitude,
      'longitude': longitude,
    });
    // 409 already checked in → treat as ok
    if (response.statusCode == 409) {
      return {'already_checked_in': true};
    }
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Attendance check-in failed',
      );
    }
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<List<Map<String, dynamic>>> attendanceMy() async {
    final response = await _client.get(ApiEndpoints.attendanceMy);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  // ── Breaks (friend backlog — soft fail) ───────────────────────────
  Future<Response> startBreak(String breakType) {
    return _client.post(ApiEndpoints.breaksStart, data: {
      'break_type': breakType,
      'breakType': breakType,
    });
  }

  Future<Response> endBreak(String breakId) {
    return _client.patch(ApiEndpoints.breaksEnd(breakId));
  }

  Future<Response> todayBreaks() => _client.get(ApiEndpoints.breaksMy);

  // ── GPS ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> gpsLog({
    required double latitude,
    required double longitude,
    String? timestamp,
    String? address,
  }) async {
    final response = await _client.post(ApiEndpoints.gpsLog, data: {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp ?? DateTime.now().toUtc().toIso8601String(),
      if (address != null && address.isNotEmpty) 'address': address,
    });
    if (response.statusCode != null && response.statusCode! >= 400) return null;
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  // ── Field routes & outlets ────────────────────────────────────────
  Future<List<Map<String, dynamic>>> fieldRoutes() async {
    final response = await _client.get(ApiEndpoints.fieldRoutes);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> outlets({String? territoryId}) async {
    final response = await _client.get(
      ApiEndpoints.outlets,
      queryParameters: {
        if (territoryId != null) 'territory_id': territoryId,
      },
    );
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>?> createOutlet(Map<String, dynamic> body) async {
    final response = await _client.post(ApiEndpoints.outlets, data: body);
    if (response.statusCode != null && response.statusCode! >= 400) return null;
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Map<String, dynamic>?> updateOutlet(String outletId, Map<String, dynamic> body) async {
    final response = await _client.patch(ApiEndpoints.outlet(outletId), data: body);
    if (response.statusCode != null && response.statusCode! >= 400) return null;
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<bool> deleteOutlet(String outletId) async {
    final response = await _client.delete(ApiEndpoints.outlet(outletId));
    // 204 No Content or 200 = success
    return response.statusCode == 204 ||
        response.statusCode == 200 ||
        (response.statusCode != null && response.statusCode! < 300);
  }

  // ── Visits ────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listVisits() async {
    final response = await _client.get(ApiEndpoints.visits);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map) {
      final list = data['visits'] ?? data['items'] ?? data['results'] ?? data['data'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return const [];
  }

  Future<Map<String, dynamic>> visitStart({
    required String outletId,
    required double latitude,
    required double longitude,
    String? startedAt,
    String? selfieMediaId,
    String? selfieUrl,
    String? notes,
  }) async {
    final response = await _client.post(ApiEndpoints.visitsStart, data: {
      'outlet_id': outletId,
      'start_latitude': latitude,
      'start_longitude': longitude,
      'started_at': startedAt ?? DateTime.now().toUtc().toIso8601String(),
      if (selfieMediaId != null) 'selfie_media_id': selfieMediaId,
      if (selfieUrl != null) 'selfie_url': selfieUrl,
      if (notes != null) 'notes': notes,
    });
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Visit start failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> visitEnd({
    required String visitId,
    required double latitude,
    required double longitude,
    String? outcome,
    String? endedAt,
    String? notes,
    DateTime? nextVisitDate,
  }) async {
    final response = await _client.post(ApiEndpoints.visitsEnd(visitId), data: {
      'end_latitude': latitude,
      'end_longitude': longitude,
      'outcome': outcome ?? 'completed',
      'ended_at': endedAt ?? DateTime.now().toUtc().toIso8601String(),
      if (notes != null) 'notes': notes,
      if (nextVisitDate != null) 'next_visit_date': nextVisitDate.toUtc().toIso8601String(),
    });
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Visit end failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>?> createOrder({
    required String outletId,
    String? visitId,
    required List<Map<String, dynamic>> items,
    double? totalAmount,
    String? notes,
    String status = 'pending',
  }) async {
    final response = await _client.post(ApiEndpoints.orders, data: {
      'outlet_id': outletId,
      if (visitId != null) 'visit_id': visitId,
      'total_amount': totalAmount ?? 0,
      'status': status,
      'items': items,
      if (notes != null) 'notes': notes,
    });
    if (response.statusCode != null && response.statusCode! >= 400) return null;
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<List<Map<String, dynamic>>> listOrders() async {
    try {
      final response = await _client.get(ApiEndpoints.orders);
      final data = ApiClient.unwrap(response);
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      if (data is Map) {
        final list = data['orders'] ?? data['items'] ?? data['results'] ?? data['data'];
        if (list is List) {
          return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (_) {}
    return const [];
  }

  // ── Products ──────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> products({String? query}) async {
    final response = await _client.get(
      ApiEndpoints.products,
      queryParameters: query == null || query.isEmpty ? null : {'q': query},
    );
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> productCategories() async {
    final response = await _client.get(ApiEndpoints.productCategories);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> productBrands() async {
    final response = await _client.get(ApiEndpoints.productBrands);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>> createProduct(Map<String, dynamic> body) async {
    final response = await _client.post(ApiEndpoints.products, data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Create product failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateProduct(String id, Map<String, dynamic> body) async {
    final response = await _client.patch(ApiEndpoints.product(id), data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Update product failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<bool> deleteProduct(String id) async {
    final response = await _client.delete(ApiEndpoints.product(id));
    if (response.statusCode == 204 || response.statusCode == 200) return true;
    if (response.statusCode != null && response.statusCode! >= 400) return false;
    try {
      ApiClient.unwrap(response);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> createProductCategory(Map<String, dynamic> body) async {
    final response = await _client.post(ApiEndpoints.productCategories, data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Create category failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateProductCategory(String id, Map<String, dynamic> body) async {
    final response = await _client.patch(ApiEndpoints.productCategory(id), data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Update category failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<bool> deleteProductCategory(String id) async {
    final response = await _client.delete(ApiEndpoints.productCategory(id));
    return response.statusCode == 204 || response.statusCode == 200;
  }

  Future<Map<String, dynamic>> createProductBrand(Map<String, dynamic> body) async {
    final response = await _client.post(ApiEndpoints.productBrands, data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Create brand failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updateProductBrand(String id, Map<String, dynamic> body) async {
    final response = await _client.patch(ApiEndpoints.productBrand(id), data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Update brand failed',
      );
    }
    final data = ApiClient.unwrap(response);
    return Map<String, dynamic>.from(data as Map);
  }

  Future<bool> deleteProductBrand(String id) async {
    final response = await _client.delete(ApiEndpoints.productBrand(id));
    return response.statusCode == 204 || response.statusCode == 200;
  }

  // ── Incidents ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> createIncident({
    required String type,
    required String description,
  }) async {
    final response = await _client.post(ApiEndpoints.incidents, data: {
      'type': type,
      'description': description,
    });
    if (response.statusCode != null && response.statusCode! >= 400) return null;
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<List<Map<String, dynamic>>> listIncidents() async {
    final response = await _client.get(ApiEndpoints.incidents);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  // ── Leads ─────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> listLeads() async {
    final response = await _client.get(ApiEndpoints.leads);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Future<Map<String, dynamic>?> saveLead(Map<String, dynamic> data) async {
    final body = {
      'name': data['name'] ?? data['businessName'] ?? data['business_name'] ?? 'Lead',
      'phone': data['phone'] ?? data['contactPhone'] ?? data['contact_phone'],
      'email': data['email'] ?? data['contactEmail'] ?? data['contact_email'],
      'address': data['address'] ?? '',
      if (data['business_type'] != null || data['businessCategory'] != null || data['category'] != null)
        'business_type': data['business_type'] ?? data['businessCategory'] ?? data['category'],
      if (data['notes'] != null) 'notes': data['notes'],
    };
    final response = await _client.post(ApiEndpoints.leads, data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Save lead failed',
      );
    }
    final unwrapped = ApiClient.unwrap(response);
    if (unwrapped is Map) return Map<String, dynamic>.from(unwrapped);
    return null;
  }

  /// Production has no `/leads/:id/convert` — create outlet + mark lead converted.
  Future<Map<String, dynamic>?> convertLead(String leadId, {Map<String, dynamic>? lead}) async {
    Map<String, dynamic>? detail = lead;
    if (detail == null) {
      final all = await listLeads();
      for (final item in all) {
        if (item['id']?.toString() == leadId) {
          detail = item;
          break;
        }
      }
    }
    if (detail == null) return null;

    final name = (detail['name'] ?? detail['businessName'] ?? 'Outlet').toString();
    final address = (detail['address'] ?? name).toString();
    final phone = (detail['phone'] ?? detail['contactPhone'] ?? '').toString();
    final lat = double.tryParse((detail['gps_lat'] ?? detail['gpsLat'] ?? detail['latitude'] ?? 0).toString()) ?? 0.0;
    final lng = double.tryParse((detail['gps_lng'] ?? detail['gpsLng'] ?? detail['longitude'] ?? 0).toString()) ?? 0.0;

    final outlet = await createOutlet({
      'name': name,
      'address': address,
      if (phone.isNotEmpty) 'phone': phone,
      'latitude': lat,
      'longitude': lng,
      'type': 'retailer',
    });

    try {
      await _client.patch(ApiEndpoints.leadById(leadId), data: {
        'status': 'converted',
        if (outlet != null) 'converted_outlet_id': outlet['id'],
      });
    } catch (_) {}

    return outlet;
  }

  // ── Uploads ───────────────────────────────────────────────────────
  Future<String?> uploadSelfie(File file) async {
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: file.uri.pathSegments.last),
      });
      final response = await _client.post(ApiEndpoints.uploadSelfie, data: form);
      if (response.statusCode != null && response.statusCode! >= 400) return null;
      final body = response.data;
      final data = body is Map && body['data'] != null ? body['data'] : body;
      if (data is Map) {
        final url = data['url']?.toString() ?? data['path']?.toString();
        if (url == null) return null;
        if (url.startsWith('http')) return url;
        return '${ApiEndpoints.baseUrl}$url';
      }
    } catch (_) {}
    return null;
  }

  // ── Admin ─────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> adminStats() async {
    final response = await _client.get(ApiEndpoints.adminStats);
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<List<Map<String, dynamic>>> adminUsers() async {
    final response = await _client.get(ApiEndpoints.adminUsers);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data is Map) {
      final list = data['users'] ?? data['data'];
      if (list is List) {
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return const [];
  }

  Future<Map<String, dynamic>> createUser(Map<String, dynamic> body) async {
    final response = await _client.post(ApiEndpoints.users, data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Create user failed',
      );
    }
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<Map<String, dynamic>> updateUser(String userId, Map<String, dynamic> body) async {
    final response = await _client.patch(ApiEndpoints.user(userId), data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Update user failed',
      );
    }
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  Future<bool> deleteUser(String userId) async {
    // Production rejects empty JSON body with Content-Type set — send no body.
    final response = await _client.delete(ApiEndpoints.user(userId));
    if (response.statusCode == 204 || response.statusCode == 200) return true;
    if (response.statusCode != null && response.statusCode! >= 400) return false;
    try {
      ApiClient.unwrap(response);
      return true;
    } catch (_) {
      return response.statusCode != null && response.statusCode! < 400;
    }
  }

  Future<Response> adminLiveVisits() => _client.get(ApiEndpoints.adminLiveVisits);

  Future<Response> getAdminSettings() => _client.get(ApiEndpoints.adminSettings);

  Future<Response> patchAdminSettings(Map<String, dynamic> body) {
    return _client.patch(ApiEndpoints.adminSettings, data: body);
  }

  // ── Organisations ─────────────────────────────────────────────────
  Future<Map<String, dynamic>> registerOrganisation(Map<String, dynamic> body) async {
    final response = await _client.post(ApiEndpoints.orgsRegister, data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Organisation registration failed',
      );
    }
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'message': 'Organisation registered successfully and is pending approval.'};
  }

  Future<List<Map<String, dynamic>>> pendingOrganisations() async {
    final response = await _client.get(ApiEndpoints.adminOrgsPending);
    final data = ApiClient.unwrap(response);
    if (data is List) {
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  /// Approve org — production stamps trial (+7d) and grace (+10d from approve).
  /// Returns the response payload (often includes `org` with subscription fields).
  Future<Map<String, dynamic>?> approveOrganisation(String orgId) async {
    // Production rejects empty body when Content-Type is application/json.
    final response = await _client.patch(ApiEndpoints.adminOrgApprove(orgId), data: {});
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Approve failed',
      );
    }
    try {
      final data = ApiClient.unwrap(response);
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'ok': true};
    } catch (_) {
      if (response.statusCode != null && response.statusCode! < 400) return {'ok': true};
      return null;
    }
  }

  Future<bool> rejectOrganisation(String orgId) async {
    final response = await _client.patch(ApiEndpoints.adminOrgReject(orgId), data: {});
    if (response.statusCode != null && response.statusCode! >= 400) return false;
    try {
      ApiClient.unwrap(response);
      return true;
    } catch (_) {
      return response.statusCode != null && response.statusCode! < 400;
    }
  }

  /// Current organisation subscription (admin token).
  Future<Map<String, dynamic>?> getAdminOrg() async {
    final response = await _client.get(ApiEndpoints.adminOrg);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Could not load organisation',
      );
    }
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  /// Super-admin: update subscription status / trial / grace dates.
  Future<Map<String, dynamic>?> updateOrgSubscription(
    String orgId,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.patch(ApiEndpoints.adminOrgSubscription(orgId), data: body);
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: ApiClient.errorMessage(
              DioException(requestOptions: response.requestOptions, response: response),
            ) ??
            'Subscription update failed',
      );
    }
    final data = ApiClient.unwrap(response);
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}
