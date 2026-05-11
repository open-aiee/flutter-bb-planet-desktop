import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../domain/app_user_session.dart';

class AppAccountAuthApi {
  AppAccountAuthApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: appConfig.appApiBaseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              headers: const {
                'Content-Type': 'application/json',
                'Lang': 'en_US',
                'Platform': 'PC',
                'Version': '1.0.0',
                'X-Client': 'flutter-bb-planet-desktop',
              },
            ),
          );

  final Dio _dio;

  Future<AppUserSession> login({
    required String email,
    required String password,
    required String deviceId,
    bool forceLogin = false,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/base/auth/user/login',
        data: {
          'email': email.trim(),
          'password': _md5Upper32(password),
          if (forceLogin) 'forceLogin': 1,
        },
        options: Options(headers: {'DeviceId': deviceId}),
      );
    } on DioException catch (error) {
      throw AppAccountLoginException(message: _dioErrorMessage(error));
    }

    final body = response.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw AppAccountLoginException(
        message: body['message']?.toString() ?? 'APP account login failed',
        messageKey: body['messageKey']?.toString(),
      );
    }

    final certificate = response.headers.value('certificate');
    if (certificate == null || certificate.isEmpty) {
      throw const AppAccountLoginException(message: 'Missing APP certificate');
    }

    final data = body['data'];
    if (data is! Map) {
      throw const AppAccountLoginException(
        message: 'Invalid APP login response',
      );
    }

    return AppUserSession.fromLoginResponse(
      data: Map<String, dynamic>.from(data),
      certificate: certificate,
    );
  }

  static String _md5Upper32(String input) {
    return md5.convert(utf8.encode(input)).toString().toUpperCase();
  }

  static String _dioErrorMessage(DioException error) {
    final response = error.response;
    final data = response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    if (response != null) {
      return 'HTTP ${response.statusCode}: ${response.statusMessage ?? 'Request failed'}';
    }
    return error.message ?? 'Network error';
  }
}

class AppAccountLoginException implements Exception {
  const AppAccountLoginException({required this.message, this.messageKey});

  final String message;
  final String? messageKey;

  @override
  String toString() => message;
}
