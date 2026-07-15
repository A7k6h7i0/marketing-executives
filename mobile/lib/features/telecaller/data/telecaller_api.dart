import 'package:dio/dio.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';

class TelecallerApi {
  TelecallerApi({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<List<Map<String, dynamic>>> listLeads({
    String? q,
    String? status,
    int pageSize = 100,
  }) async {
    final response = await _client.get(
      ApiEndpoints.telecallerLeads,
      queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        if (status != null && status.isNotEmpty) 'status': status,
        'pageSize': pageSize,
      },
    );
    final items = response.data['items'] as List<dynamic>? ?? [];
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> createLead(Map<String, dynamic> payload) async {
    final response = await _client.post(ApiEndpoints.telecallerLeads, data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateLead(String id, Map<String, dynamic> payload) async {
    final response = await _client.patch('${ApiEndpoints.telecallerLeads}/$id', data: payload);
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> callLead(String leadId, {String mode = 'PHONE'}) async {
    final response = await _client.post(
      '${ApiEndpoints.telecallerLeads}/$leadId/call',
      data: {'mode': mode},
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  /// Upload a local OEM call recording and attach it to the call log.
  Future<Map<String, dynamic>> attachCallRecordingFile({
    required String callId,
    required String filePath,
    required String fileName,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
    });
    final response = await _client.dio.post(
      '${ApiEndpoints.telecallerCalls}/$callId/recording',
      data: form,
      options: Options(
        sendTimeout: const Duration(minutes: 2),
        receiveTimeout: const Duration(minutes: 2),
      ),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> updateCallOutcome(
    String callId, {
    required String outcome,
    String? notes,
  }) async {
    final response = await _client.patch(
      '${ApiEndpoints.telecallerCalls}/$callId/outcome',
      data: {
        'outcome': outcome,
        if (notes != null) 'notes': notes,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<Map<String, dynamic>>> listTelecallers() async {
    final response = await _client.get(ApiEndpoints.telecallerUsers);
    final items = response.data['items'] as List<dynamic>? ?? [];
    return items.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> bulkDistribute({
    required List<String> telecallerIds,
    required String startDate,
    required String endDate,
    required int recordsPerTelecallerPerDay,
    String? source,
    required List<Map<String, dynamic>> records,
  }) async {
    final response = await _client.post(
      ApiEndpoints.telecallerBulkDistribute,
      data: {
        'telecallerIds': telecallerIds,
        'startDate': startDate,
        'endDate': endDate,
        'recordsPerTelecallerPerDay': recordsPerTelecallerPerDay,
        if (source != null) 'source': source,
        'records': records,
      },
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<Map<String, dynamic>> bulkDistributeFile({
    required String filePath,
    required String fileName,
    required List<String> telecallerIds,
    required String startDate,
    required String endDate,
    required int recordsPerTelecallerPerDay,
    String? source,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: fileName),
      'telecallerIds': telecallerIds.join(','),
      'startDate': startDate,
      'endDate': endDate,
      'recordsPerTelecallerPerDay': recordsPerTelecallerPerDay.toString(),
      if (source != null) 'source': source,
    });
    final response = await _client.dio.post(
      ApiEndpoints.telecallerBulkDistributeFile,
      data: form,
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}

String formatTelecallerError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final nested = data['error'];
      if (nested is Map && nested['message'] != null) return nested['message'].toString();
      if (data['error'] != null) return data['error'].toString();
      if (data['message'] != null) return data['message'].toString();
    }
    return error.message ?? 'Request failed';
  }
  return error.toString();
}
