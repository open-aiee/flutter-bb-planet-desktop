import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';

final directChatApiProvider = Provider<DirectChatApi>((ref) {
  return DirectChatApi();
});

class DirectChatApi {
  DirectChatApi({Dio? dio})
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

  Future<DirectChatStartResult> startDirectChat({
    required int peerUserId,
    required String certificate,
    required String deviceId,
    required String lang,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/chat/start',
        data: {'toUserId': peerUserId, 'chatSourceType': 1},
        options: Options(
          headers: {
            'Certificate': certificate,
            'DeviceId': deviceId,
            'Lang': lang,
          },
        ),
      );
    } on DioException catch (error) {
      throw DirectChatException.fromDio(error);
    }

    final body = response.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw DirectChatException(
        body['message']?.toString() ?? 'Unable to open chat.',
      );
    }

    final data = body['data'];
    if (data is! Map) {
      throw const DirectChatException('Unable to open chat.');
    }
    return DirectChatStartResult.fromJson(Map<String, dynamic>.from(data));
  }
}

class DirectChatStartResult {
  const DirectChatStartResult({required this.roomId});

  final int roomId;

  factory DirectChatStartResult.fromJson(Map<String, dynamic> json) {
    final value = json['roomId'];
    final roomId = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (roomId == null || roomId <= 0) {
      throw const DirectChatException('Unable to open chat.');
    }
    return DirectChatStartResult(roomId: roomId);
  }
}

class DirectChatException implements Exception {
  const DirectChatException(this.message);

  final String message;

  factory DirectChatException.fromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return DirectChatException(data['message'].toString());
    }
    return const DirectChatException('Unable to open chat.');
  }

  @override
  String toString() => message;
}
