import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/api_endpoints.dart';

/// HTTP client for production SFA (`{ success, data }` / `{ success: false, error }`).
class ApiClient {
  final Dio _dio;

  /// Flips true when any request gets 402 SUBSCRIPTION_EXPIRED (AuthGate listens).
  static final ValueNotifier<bool> subscriptionLockedNotifier = ValueNotifier(false);

  ApiClient() : _dio = Dio() {
    _dio.options.baseUrl = ApiEndpoints.baseUrl;
    _dio.options.connectTimeout = const Duration(seconds: 20);
    _dio.options.receiveTimeout = const Duration(seconds: 20);
    _dio.options.headers = {'Accept': 'application/json'};
    _dio.options.validateStatus = (code) => code != null && code < 500;

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('jwt_token');

          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          // Only set JSON content-type when a body is sent (DELETE with empty body fails on production).
          if (options.data != null && options.data is! FormData) {
            options.headers['Content-Type'] = 'application/json';
          } else if (options.data == null) {
            options.headers.remove('Content-Type');
          }

          return handler.next(options);
        },
        onResponse: (response, handler) async {
          if (response.statusCode == 402) {
            final body = response.data;
            String? code;
            String? message;
            if (body is Map) {
              final err = body['error'];
              if (err is Map) {
                code = err['code']?.toString();
                message = err['message']?.toString();
              }
            }
            if ((code ?? '').toUpperCase() == 'SUBSCRIPTION_EXPIRED' ||
                (message ?? '').toLowerCase().contains('subscription')) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('subscription_locked', true);
              await prefs.setString(
                'subscription_lock_message',
                message?.isNotEmpty == true
                    ? message!
                    : ApiClient.subscriptionExpiredUserMessage,
              );
              await prefs.remove('jwt_token');
              subscriptionLockedNotifier.value = true;
            }
          }
          return handler.next(response);
        },
        onError: (error, handler) async {
          if (ApiClient.isSubscriptionExpired(error)) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('subscription_locked', true);
            await prefs.setString(
              'subscription_lock_message',
              ApiClient.errorMessage(error) ?? ApiClient.subscriptionExpiredUserMessage,
            );
            await prefs.remove('jwt_token');
            subscriptionLockedNotifier.value = true;
          }
          return handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  Future<Response> get(String path, {Map<String, dynamic>? queryParameters}) {
    return _dio.get(path, queryParameters: queryParameters);
  }

  Future<Response> post(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.post(path, data: data, queryParameters: queryParameters);
  }

  Future<Response> patch(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.patch(path, data: data, queryParameters: queryParameters);
  }

  Future<Response> delete(String path, {dynamic data, Map<String, dynamic>? queryParameters}) {
    return _dio.delete(path, data: data, queryParameters: queryParameters);
  }

  /// Unwrap production `{ success, data }` body. Throws [DioException] on failure envelope.
  static dynamic unwrap(Response response) {
    final body = response.data;
    if (body is! Map) return body;

    if (body['success'] == false) {
      final err = body['error'];
      String message = 'Request failed';
      if (err is Map) {
        message = err['message']?.toString() ?? message;
      } else if (err != null) {
        message = err.toString();
      } else if (body['message'] != null) {
        message = body['message'].toString();
      }
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
        message: message,
      );
    }

    if (body.containsKey('data')) return body['data'];
    return body;
  }

  static String? errorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final err = data['error'];
      if (err is Map && err['message'] != null) return err['message'].toString();
      if (data['message'] != null) return data['message'].toString();
    }
    return e.message;
  }

  static String? errorCode(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      return data['error']['code']?.toString();
    }
    return null;
  }

  /// Production gate: past grace_period_ends_at → 402 + SUBSCRIPTION_EXPIRED.
  static bool isSubscriptionExpired(DioException e) {
    if (e.response?.statusCode == 402) return true;
    final code = (errorCode(e) ?? '').toUpperCase();
    if (code == 'SUBSCRIPTION_EXPIRED') return true;
    final msg = (errorMessage(e) ?? '').toLowerCase();
    return msg.contains('subscription') && msg.contains('expired');
  }

  static const String subscriptionExpiredUserMessage =
      'Access locked — your organisation\'s free trial and 3-day grace period have ended. '
      'Payment is required to continue. Contact your administrator or platform support.';
}
