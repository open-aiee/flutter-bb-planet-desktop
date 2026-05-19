import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/storage/chat_ops_sqlite_database.dart';
import '../domain/local_chat_message.dart';

final localChatMessageStoreProvider = FutureProvider<LocalChatMessageStore>((
  ref,
) async {
  final database = await ref.watch(chatOpsSqliteDatabaseProvider.future);
  return LocalChatMessageStore(database);
});

class LocalChatMessageStore {
  const LocalChatMessageStore(this._database);

  static const _table = 'chat_messages';
  static const _stateTable = 'chat_conversation_state';

  final Database _database;

  Future<void> upsert(LocalChatMessage message) async {
    await _database.insert(
      _table,
      _toRow(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint(
      '[CHAT_OPS][LOCAL][MESSAGE_STORE] upsert sqlite '
      'sender=${message.appUserId} peer=${message.peerUserId} '
      'local=${message.localId} server=${message.serverMessageId}',
    );
  }

  Future<List<LocalChatMessage>> loadConversation({
    required int appUserId,
    required int peerUserId,
    int? roomId,
  }) async {
    final rows = await _database.query(
      _table,
      where: 'app_user_id = ? AND peer_user_id = ?',
      whereArgs: [appUserId, peerUserId],
      orderBy: 'created_at ASC, updated_at ASC',
    );
    final messages = rows.map(_fromRow).toList(growable: false);
    return _deduplicate(messages)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  }

  Future<Map<int, LocalChatMessage>> loadLatestByAppUser({
    required int appUserId,
  }) async {
    final rows = await _database.query(
      _table,
      where: 'app_user_id = ? AND peer_user_id > 0',
      whereArgs: [appUserId],
      orderBy: 'created_at DESC, updated_at DESC',
    );
    final latestByPeer = <int, LocalChatMessage>{};
    for (final row in rows) {
      final message = _fromRow(row);
      latestByPeer.putIfAbsent(message.peerUserId, () => message);
    }
    return latestByPeer;
  }

  Future<Map<int, int>> loadUnreadByAppUser({required int appUserId}) async {
    final rows = await _database.query(
      _stateTable,
      where: 'app_user_id = ? AND peer_user_id > 0',
      whereArgs: [appUserId],
    );
    return {
      for (final row in rows)
        _asInt(row['peer_user_id']): _asInt(row['unread_count']),
    }..removeWhere((peerUserId, _) => peerUserId <= 0);
  }

  Future<int> incrementUnread({
    required int appUserId,
    required int peerUserId,
  }) async {
    if (appUserId <= 0 || peerUserId <= 0) {
      return 0;
    }
    final rows = await _database.query(
      _stateTable,
      columns: const ['unread_count'],
      where: 'app_user_id = ? AND peer_user_id = ?',
      whereArgs: [appUserId, peerUserId],
      limit: 1,
    );
    final next = (rows.isEmpty ? 0 : _asInt(rows.first['unread_count'])) + 1;
    await setUnreadCount(
      appUserId: appUserId,
      peerUserId: peerUserId,
      unreadCount: next,
    );
    return next;
  }

  Future<void> setUnreadCount({
    required int appUserId,
    required int peerUserId,
    required int unreadCount,
  }) async {
    if (appUserId <= 0 || peerUserId <= 0) {
      return;
    }
    await _database.insert(_stateTable, {
      'app_user_id': appUserId,
      'peer_user_id': peerUserId,
      'unread_count': unreadCount < 0 ? 0 : unreadCount,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    debugPrint(
      '[CHAT_OPS][LOCAL][UNREAD_STORE] sender=$appUserId '
      'peer=$peerUserId unread=$unreadCount',
    );
  }

  Future<List<LocalChatMessage>> markOutgoingReadByRoom({
    required int appUserId,
    required int roomId,
    required int readMsgIndex,
  }) async {
    if (roomId <= 0 || readMsgIndex <= 0) {
      return const [];
    }

    final rows = await _database.query(
      _table,
      where:
          'app_user_id = ? AND room_id = ? AND direction = ? '
          'AND send_status NOT IN (?, ?) AND server_message_id IS NOT NULL',
      whereArgs: [
        appUserId,
        roomId,
        ChatMessageDirection.outgoing.name,
        ChatMessageSendStatus.read.name,
        ChatMessageSendStatus.failed.name,
      ],
    );

    final updatedMessages = <LocalChatMessage>[];
    final batch = _database.batch();
    final now = DateTime.now();
    for (final row in rows) {
      final message = _fromRow(row);
      final serverId = int.tryParse(message.serverMessageId ?? '') ?? 0;
      if (serverId <= 0 || serverId > readMsgIndex) {
        continue;
      }
      final updated = message.copyWith(
        sendStatus: ChatMessageSendStatus.read,
        updatedAt: now,
      );
      batch.update(
        _table,
        _toRow(updated),
        where: 'app_user_id = ? AND peer_user_id = ? AND local_id = ?',
        whereArgs: [updated.appUserId, updated.peerUserId, updated.localId],
      );
      updatedMessages.add(updated);
    }
    if (updatedMessages.isNotEmpty) {
      await batch.commit(noResult: true);
    }
    return updatedMessages;
  }

  Map<String, Object?> _toRow(LocalChatMessage message) {
    return {
      'app_user_id': message.appUserId,
      'peer_user_id': message.peerUserId,
      'local_id': message.localId,
      'conversation_key': message.conversationKey,
      'room_id': message.roomId,
      'direction': message.direction.name,
      'text': message.text,
      'created_at': message.createdAt.millisecondsSinceEpoch,
      'updated_at': message.updatedAt.millisecondsSinceEpoch,
      'send_status': message.sendStatus.name,
      'client_message_id': message.clientMessageId,
      'server_message_id': message.serverMessageId,
      'error_message': message.errorMessage,
      'send_type': message.sendType,
      'msg_data': message.msgData,
      'local_media_path': message.localMediaPath,
    };
  }

  LocalChatMessage _fromRow(Map<String, Object?> row) {
    return LocalChatMessage(
      localId: row['local_id']?.toString() ?? '',
      appUserId: _asInt(row['app_user_id']),
      peerUserId: _asInt(row['peer_user_id']),
      roomId: _asNullableInt(row['room_id']),
      conversationKey: row['conversation_key']?.toString() ?? '',
      direction: _enumByName(
        ChatMessageDirection.values,
        row['direction']?.toString(),
        ChatMessageDirection.outgoing,
      ),
      text: row['text']?.toString() ?? '',
      createdAt: _dateFromMillis(row['created_at']),
      updatedAt: _dateFromMillis(row['updated_at']),
      sendStatus: _enumByName(
        ChatMessageSendStatus.values,
        row['send_status']?.toString(),
        ChatMessageSendStatus.pending,
      ),
      clientMessageId: row['client_message_id']?.toString(),
      serverMessageId: row['server_message_id']?.toString(),
      errorMessage: row['error_message']?.toString(),
      sendType: _asIntWithFallback(row['send_type'], 1),
      msgData: row['msg_data']?.toString(),
      localMediaPath: row['local_media_path']?.toString(),
    );
  }
}

List<LocalChatMessage> _deduplicate(List<LocalChatMessage> messages) {
  final deduped = <LocalChatMessage>[];
  for (final message in messages) {
    final index = deduped.indexWhere((current) {
      final sameServerId =
          message.serverMessageId != null &&
          current.serverMessageId == message.serverMessageId;
      final sameClientId =
          message.clientMessageId != null &&
          current.clientMessageId == message.clientMessageId;
      final sameLocalId = current.localId == message.localId;
      return sameServerId || sameClientId || sameLocalId;
    });
    if (index < 0) {
      deduped.add(message);
      continue;
    }
    deduped[index] = _preferServerMessage(deduped[index], message);
  }
  return deduped;
}

LocalChatMessage _preferServerMessage(
  LocalChatMessage current,
  LocalChatMessage next,
) {
  if (current.serverMessageId == null && next.serverMessageId != null) {
    return next;
  }
  if (current.sendStatus == ChatMessageSendStatus.pending &&
      next.sendStatus != ChatMessageSendStatus.pending) {
    return next;
  }
  if (current.sendStatus == ChatMessageSendStatus.read &&
      next.sendStatus == ChatMessageSendStatus.sent) {
    return current;
  }
  return next.updatedAt.isAfter(current.updatedAt) ? next : current;
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int _asIntWithFallback(Object? value, int fallback) {
  if (value is int) {
    return value;
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _asNullableInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  return int.tryParse(value.toString());
}

DateTime _dateFromMillis(Object? value) {
  final millis = _asInt(value);
  if (millis <= 0) {
    return DateTime.now();
  }
  return DateTime.fromMillisecondsSinceEpoch(millis);
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) {
      return value;
    }
  }
  return fallback;
}
