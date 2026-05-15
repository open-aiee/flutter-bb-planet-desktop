import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';

final chatMediaUploadApiProvider = Provider<ChatMediaUploadApi>((ref) {
  return ChatMediaUploadApi();
});

class ChatMediaUploadApi {
  ChatMediaUploadApi({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: appConfig.appApiBaseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 60),
              headers: const {
                'Lang': 'en_US',
                'Platform': 'PC',
                'Version': '1.0.0',
                'X-Client': 'flutter-bb-planet-desktop',
              },
            ),
          );

  final Dio _dio;

  Future<String> uploadTempImage({
    required String path,
    required String certificate,
    required String deviceId,
    required String lang,
  }) {
    return _uploadTempMedia(
      path: path,
      endpoint: '/file/upload/temp/image',
      certificate: certificate,
      deviceId: deviceId,
      lang: lang,
    );
  }

  Future<String> uploadTempVideo({
    required String path,
    required String certificate,
    required String deviceId,
    required String lang,
  }) {
    return _uploadTempMedia(
      path: path,
      endpoint: '/file/upload/temp/video',
      certificate: certificate,
      deviceId: deviceId,
      lang: lang,
    );
  }

  Future<String> uploadTempVoice({
    required String path,
    required String certificate,
    required String deviceId,
    required String lang,
  }) {
    return _uploadTempMedia(
      path: path,
      endpoint: '/file/upload/temp/audio',
      certificate: certificate,
      deviceId: deviceId,
      lang: lang,
    );
  }

  Future<String> _uploadTempMedia({
    required String path,
    required String endpoint,
    required String certificate,
    required String deviceId,
    required String lang,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const ChatMediaUploadException('Selected file no longer exists.');
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path),
      'type': '5',
    });

    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        endpoint,
        data: formData,
        options: Options(
          headers: {
            'Certificate': certificate,
            'DeviceId': deviceId,
            'Lang': lang,
          },
          contentType: 'multipart/form-data',
        ),
      );
    } on DioException catch (error) {
      throw ChatMediaUploadException.fromDio(error);
    }

    final body = response.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw ChatMediaUploadException(
        body['message']?.toString() ?? 'Media upload failed.',
      );
    }
    final url = body['data']?.toString().trim() ?? '';
    if (url.isEmpty) {
      throw const ChatMediaUploadException('Media upload returned empty URL.');
    }
    return url;
  }
}

class ChatMediaUploadException implements Exception {
  const ChatMediaUploadException(this.message);

  final String message;

  factory ChatMediaUploadException.fromDio(DioException error) {
    final response = error.response?.data;
    if (response is Map && response['message'] != null) {
      return ChatMediaUploadException(response['message'].toString());
    }
    if (error.type == DioExceptionType.connectionError) {
      return const ChatMediaUploadException(
        'Network connection failed. Please try again.',
      );
    }
    return ChatMediaUploadException(error.message ?? 'Media upload failed.');
  }

  @override
  String toString() => message;
}
