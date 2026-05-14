import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';

final chatConversationApiProvider = Provider<ChatConversationApi>((ref) {
  return ChatConversationApi();
});

class ChatConversationApi {
  ChatConversationApi({Dio? dio})
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

  Future<List<ChatConversationSummary>> fetchConversations({
    required String certificate,
    required String deviceId,
    required String lang,
    int page = 1,
    int size = 50,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/chat/pageList',
        data: {'page': page, 'size': size},
        options: Options(
          headers: {
            'Certificate': certificate,
            'DeviceId': deviceId,
            'Lang': lang,
          },
        ),
      );
    } on DioException catch (error) {
      throw ChatConversationException.fromDio(error);
    }

    final body = response.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw ChatConversationException(
        body['message']?.toString() ?? 'Unable to load conversations.',
      );
    }

    return _extractRecords(body['data'])
        .whereType<Map>()
        .map(
          (item) =>
              ChatConversationSummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.peerUserId > 0)
        .toList();
  }

  Future<List<ChatUserInfoSummary>> fetchUserInfos({
    required String certificate,
    required String deviceId,
    required String lang,
    required List<int> userIds,
  }) async {
    final ids = userIds.where((id) => id > 0).toSet().toList();
    if (ids.isEmpty) {
      return const [];
    }
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/chat/batch/userInfo',
        data: {'userIds': ids},
        options: Options(
          headers: {
            'Certificate': certificate,
            'DeviceId': deviceId,
            'Lang': lang,
          },
        ),
      );
    } on DioException catch (error) {
      throw ChatConversationException.fromDio(error);
    }

    final body = response.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw ChatConversationException(
        body['message']?.toString() ?? 'Unable to load user status.',
      );
    }

    final data = body['data'];
    final records = data is List ? data : _extractRecords(data);
    return records
        .whereType<Map>()
        .map(
          (item) =>
              ChatUserInfoSummary.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((item) => item.id > 0)
        .toList();
  }

  static List<Object?> _extractRecords(Object? data) {
    if (data is List) {
      return data;
    }
    if (data is Map) {
      final records = data['records'] ?? data['list'] ?? data['rows'];
      if (records is List) {
        return records;
      }
    }
    return const [];
  }
}

class ChatConversationSummary {
  const ChatConversationSummary({
    required this.roomId,
    required this.peerUserId,
    required this.roomName,
    required this.roomAlias,
    required this.roomImg,
    required this.roomType,
    required this.topStatus,
    required this.readReceipt,
    required this.onlineStatus,
  });

  final int roomId;
  final int peerUserId;
  final String roomName;
  final String roomAlias;
  final String roomImg;
  final int roomType;
  final int topStatus;
  final int readReceipt;
  final int onlineStatus;

  bool get isOnline => onlineStatus == 1;

  String get displayName {
    final alias = roomAlias.trim();
    if (alias.isNotEmpty) {
      return alias;
    }
    final name = roomName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    return 'Beepian$peerUserId';
  }

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    return ChatConversationSummary(
      roomId: _asInt(json['roomId']),
      peerUserId: _asInt(json['toId']),
      roomName: json['roomName']?.toString() ?? '',
      roomAlias: json['roomAlias']?.toString() ?? '',
      roomImg: json['roomImg']?.toString() ?? '',
      roomType: _asInt(json['roomType']),
      topStatus: _asInt(json['topStatus']),
      readReceipt: _asIntWithFallback(json['readReceipt'], 1),
      onlineStatus: _firstNonZeroInt([
        _onlineDataValue(json['onlineData']),
        json['onlineStatus'],
        json['online'],
        json['isOnline'],
        json['userOnlineStatus'],
        json['status'],
        json['toOnlineStatus'],
      ]),
    );
  }

  static int _asInt(Object? value) {
    if (value is bool) {
      return value ? 1 : 0;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _firstNonZeroInt(List<Object?> values) {
    for (final value in values) {
      final parsed = _asInt(value);
      if (parsed != 0) {
        return parsed;
      }
    }
    return 0;
  }

  static Object? _onlineDataValue(Object? value) {
    final data = _asMap(value);
    if (data.isEmpty) {
      return null;
    }
    return data['online'];
  }

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  static int _asIntWithFallback(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }
}

class ChatUserInfoSummary {
  const ChatUserInfoSummary({
    required this.id,
    required this.avatarUrl,
    required this.nickName,
    required this.nameAlias,
    required this.onlineStatus,
  });

  final int id;
  final String avatarUrl;
  final String nickName;
  final String nameAlias;
  final int onlineStatus;

  bool get isOnline => onlineStatus == 1;

  String get displayName {
    final alias = nameAlias.trim();
    if (alias.isNotEmpty) {
      return alias;
    }
    final name = nickName.trim();
    return name.isEmpty ? 'Beepian$id' : name;
  }

  factory ChatUserInfoSummary.fromJson(Map<String, dynamic> json) {
    return ChatUserInfoSummary(
      id: ChatConversationSummary._asInt(json['id'] ?? json['userId']),
      avatarUrl: json['avatarUrl']?.toString() ?? '',
      nickName: json['nickName']?.toString() ?? '',
      nameAlias: json['nameAlias']?.toString() ?? '',
      onlineStatus: ChatConversationSummary._firstNonZeroInt([
        ChatConversationSummary._onlineDataValue(json['onlineData']),
        json['onlineStatus'],
        json['online'],
        json['isOnline'],
        json['userOnlineStatus'],
        json['status'],
      ]),
    );
  }
}

class ChatConversationException implements Exception {
  const ChatConversationException(this.message);

  final String message;

  factory ChatConversationException.fromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return ChatConversationException(data['message'].toString());
    }
    return const ChatConversationException('Unable to load conversations.');
  }

  @override
  String toString() => message;
}
