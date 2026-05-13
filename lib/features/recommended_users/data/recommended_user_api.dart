import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../domain/recommended_user.dart';

final recommendedUserApiProvider = Provider<RecommendedUserApi>((ref) {
  return RecommendedUserApi();
});

class RecommendedUserApi {
  RecommendedUserApi({Dio? dio})
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

  Future<List<RecommendedUser>> fetchUsersFromDynamicPage({
    required String certificate,
    required String deviceId,
    required String lang,
    bool onlyOnline = false,
    int page = 1,
    int size = 20,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/v2/user-dynamic/pageList',
        data: {
          'page': page,
          'size': size,
          'dynamicTypePage': 1,
          'orderBy': 'likeNum+replyNum',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Certificate': certificate,
            'DeviceId': deviceId,
            'Lang': lang,
          },
        ),
      );
    } on DioException catch (error) {
      throw RecommendedUserException.fromDio(error);
    }

    final body = response.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw RecommendedUserException(
        body['message']?.toString() ?? 'Dynamic users request failed',
      );
    }

    final records = _extractRecords(body['data']).whereType<Map>().toList();
    final users = <RecommendedUser>[];
    for (final record in records) {
      final map = Map<String, dynamic>.from(record);
      final recommendItems = _extractRecommendItems(map['obj']);
      if (recommendItems.isNotEmpty) {
        users.addAll(
          recommendItems
              .whereType<Map>()
              .map(
                (item) =>
                    RecommendedUser.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((user) => user.id > 0),
        );
        continue;
      }

      final author = RecommendedUser.fromJson(map);
      if (author.id > 0) {
        users.add(author);
      }
    }

    final uniqueUsers = _dedupeUsers(users);
    if (!onlyOnline) {
      return uniqueUsers;
    }
    return uniqueUsers.where((user) => user.isOnline).toList();
  }

  Future<List<RecommendedUser>> searchGlobalUsers({
    required String certificate,
    required String deviceId,
    required String lang,
    required String nickName,
    int page = 1,
    int size = 20,
  }) async {
    final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/chat/global/pageList',
        data: {
          'nickName': nickName.trim(),
          'page': page,
          'size': size,
          'type': 2,
        },
        options: Options(
          headers: {
            'Certificate': certificate,
            'DeviceId': deviceId,
            'Lang': lang,
          },
        ),
      );
    } on DioException catch (error) {
      throw RecommendedUserException.fromDio(error);
    }

    final body = response.data ?? <String, dynamic>{};
    if (body['code'] != 200) {
      throw RecommendedUserException(
        body['message']?.toString() ?? 'User search request failed',
      );
    }

    return _extractRecords(body['data'])
        .whereType<Map>()
        .map(
          (item) => RecommendedUser.fromJson(Map<String, dynamic>.from(item)),
        )
        .where((user) => user.id > 0)
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

  static List<Object?> _extractRecommendItems(Object? data) {
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

  static List<RecommendedUser> _dedupeUsers(List<RecommendedUser> users) {
    final byId = <int, RecommendedUser>{};
    for (final user in users) {
      if (user.id <= 0) {
        continue;
      }
      final current = byId[user.id];
      byId[user.id] = current == null ? user : _preferRicherUser(current, user);
    }
    return byId.values.toList();
  }

  static RecommendedUser _preferRicherUser(
    RecommendedUser current,
    RecommendedUser next,
  ) {
    final currentScore = _userCompletenessScore(current);
    final nextScore = _userCompletenessScore(next);
    return nextScore > currentScore ? next : current;
  }

  static int _userCompletenessScore(RecommendedUser user) {
    var score = 0;
    if (user.nickName.trim().isNotEmpty) {
      score += 2;
    }
    if (user.nameAlias.trim().isNotEmpty) {
      score += 2;
    }
    if (user.avatarUrl.trim().isNotEmpty) {
      score += 2;
    }
    if (user.isOnline) {
      score += 1;
    }
    if (user.fans > 0) {
      score += 1;
    }
    if (user.lastLoginTime != null) {
      score += 1;
    }
    return score;
  }
}

class RecommendedUserException implements Exception {
  const RecommendedUserException(this.message);

  final String message;

  factory RecommendedUserException.fromDio(DioException error) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return RecommendedUserException(data['message'].toString());
    }
    return const RecommendedUserException('Unable to load users.');
  }

  @override
  String toString() => message;
}
