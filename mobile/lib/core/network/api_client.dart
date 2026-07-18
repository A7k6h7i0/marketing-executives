import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_endpoints.dart';

class ApiClient {
  final Dio _dio;

  ApiClient() : _dio = Dio() {
    _dio.options.baseUrl = ApiEndpoints.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 20);
    _dio.options.headers = {'Accept': 'application/json'};

    // Add interceptor to automatically attach JWT token and log requests
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('jwt_token');

          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          // Let Dio set multipart boundary when uploading files.
          if (options.data is! FormData) {
            options.headers['Content-Type'] = 'application/json';
          }

          print('--> [API REQUEST] ${options.method} ${options.baseUrl}${options.path}');
          if (options.data != null && options.data is! FormData) {
            print('Body: ${options.data}');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          print('<-- [API RESPONSE] ${response.statusCode} ${response.requestOptions.path}');
          return handler.next(response);
        },
        onError: (DioException error, handler) {
          print('[API ERROR] ${error.response?.statusCode} ${error.requestOptions.path}');
          print('Message: ${error.message}');
          if (error.response?.data != null) {
            print('Response Data: ${error.response?.data}');
          }
          return handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  // Helper methods for common HTTP operations
  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters);
    } on DioException {
      rethrow;
    }
  }

  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    try {
      return await _dio.post(path, data: data, queryParameters: queryParameters);
    } on DioException {
      rethrow;
    }
  }

  Future<Response> patch(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    try {
      return await _dio.patch(path, data: data, queryParameters: queryParameters);
    } on DioException {
      rethrow;
    }
  }

  Future<Response> delete(String path, {dynamic data, Map<String, dynamic>? queryParameters}) async {
    try {
      return await _dio.delete(path, data: data, queryParameters: queryParameters);
    } on DioException {
      rethrow;
    }
  }
}
