import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../../../core/config/app_config.dart';
import '../domain/operator_session.dart';

class OperatorAuthApi {
  OperatorAuthApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: appConfig.adminApiBaseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
              headers: const {
                'Content-Type': 'application/json',
                'Lang': 'zh_CN',
              },
            ),
          );

  final Dio _dio;

  Future<OperatorSession> login({
    required String userName,
    required String password,
    String? googleCode,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      final verify = await _fetchVerifyHeader();
      response = await _dio.post<Map<String, dynamic>>(
        '/sys-user/login',
        data: {
          'userName': userName.trim(),
          'passWord': _md5Upper32(password),
          'googleCode': googleCode?.trim() ?? '',
          'source': 'admin',
        },
        options: Options(headers: {'Verify': verify}),
      );
    } on DioException catch (error) {
      throw OperatorLoginException(message: _dioErrorMessage(error));
    }

    final body = response.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw OperatorLoginException(
        message: body['message']?.toString() ?? 'Login failed',
        messageKey: body['messageKey']?.toString(),
      );
    }

    final certificate = response.headers.value('certificate');
    if (certificate == null || certificate.isEmpty) {
      throw const OperatorLoginException(message: 'Missing login certificate');
    }

    final data = body['data'];
    if (data is! Map) {
      throw const OperatorLoginException(message: 'Invalid login response');
    }

    return OperatorSession.fromLoginResponse(
      data: Map<String, dynamic>.from(data),
      certificate: certificate,
    );
  }

  Future<String> _fetchVerifyHeader() async {
    final Response<List<int>> response;
    try {
      response = await _dio.get<List<int>>(
        '/sys-user/getCode',
        options: Options(responseType: ResponseType.bytes),
      );
    } on DioException catch (error) {
      throw OperatorLoginException(message: _dioErrorMessage(error));
    }
    final verify = response.headers.value('verify');
    if (verify == null || verify.isEmpty) {
      throw const OperatorLoginException(message: 'Missing verify header');
    }
    return verify;
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

class OperatorLoginException implements Exception {
  const OperatorLoginException({required this.message, this.messageKey});

  final String message;
  final String? messageKey;

  @override
  String toString() => message;
}
