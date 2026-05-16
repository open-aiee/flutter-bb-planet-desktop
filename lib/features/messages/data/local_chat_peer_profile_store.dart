import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/storage/chat_ops_sqlite_database.dart';
import '../domain/local_chat_peer_profile.dart';

final localChatPeerProfileStoreProvider =
    FutureProvider<LocalChatPeerProfileStore>((ref) async {
      final database = await ref.watch(chatOpsSqliteDatabaseProvider.future);
      return LocalChatPeerProfileStore(database);
    });

class LocalChatPeerProfileStore {
  const LocalChatPeerProfileStore(this._database);

  static const _table = 'chat_peer_profiles';

  final Database _database;

  Future<void> upsert(LocalChatPeerProfile profile) async {
    if (profile.appUserId <= 0 || profile.peerUserId <= 0) {
      return;
    }
    await _database.insert(
      _table,
      _toRow(profile),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint(
      '[CHAT_OPS][LOCAL][PROFILE_STORE] upsert sqlite '
      'sender=${profile.appUserId} peer=${profile.peerUserId} '
      'avatar=${profile.avatarUrl.isNotEmpty}',
    );
  }

  Future<Map<int, LocalChatPeerProfile>> loadByAppUser({
    required int appUserId,
  }) async {
    final rows = await _database.query(
      _table,
      where: 'app_user_id = ?',
      whereArgs: [appUserId],
      orderBy: 'updated_at DESC',
    );
    final profiles = <int, LocalChatPeerProfile>{};
    for (final row in rows) {
      final profile = _fromRow(row);
      if (profile.peerUserId > 0) {
        profiles[profile.peerUserId] = profile;
      }
    }
    return profiles;
  }

  Map<String, Object?> _toRow(LocalChatPeerProfile profile) {
    return {
      'app_user_id': profile.appUserId,
      'peer_user_id': profile.peerUserId,
      'display_name': profile.displayName,
      'avatar_url': profile.avatarUrl,
      'updated_at': profile.updatedAt.millisecondsSinceEpoch,
    };
  }

  LocalChatPeerProfile _fromRow(Map<String, Object?> row) {
    return LocalChatPeerProfile(
      appUserId: _asInt(row['app_user_id']),
      peerUserId: _asInt(row['peer_user_id']),
      displayName: row['display_name']?.toString() ?? '',
      avatarUrl: row['avatar_url']?.toString() ?? '',
      updatedAt: _dateFromMillis(row['updated_at']),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime _dateFromMillis(Object? value) {
  final millis = _asInt(value);
  if (millis <= 0) {
    return DateTime.now();
  }
  return DateTime.fromMillisecondsSinceEpoch(millis);
}
