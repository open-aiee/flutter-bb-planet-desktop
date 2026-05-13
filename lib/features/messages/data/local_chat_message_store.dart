import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/security/secure_store_provider.dart';
import '../../../core/security/secure_store.dart';
import '../../../core/storage/encrypted_cache_store.dart';
import '../domain/local_chat_message.dart';

final localChatMessageStoreProvider = FutureProvider<LocalChatMessageStore>((
  ref,
) async {
  final secureStore = ref.read(secureStoreProvider);
  final cacheKey = await readOrCreateMessageCacheKey(secureStore);

  final box = await EncryptedCacheStore(
    encryptionKey: EncryptedCacheStore.normalizeKey(cacheKey),
  ).openBox('chat_messages_v1');
  return LocalChatMessageStore(box);
});

Future<String> readOrCreateMessageCacheKey(SecureStore secureStore) async {
  var cacheKey = await secureStore.read('chat.messageCache.encryptionKey');
  if (cacheKey == null || cacheKey.isEmpty) {
    cacheKey = _randomCacheKey();
    await secureStore.write('chat.messageCache.encryptionKey', cacheKey);
  }
  return cacheKey;
}

class LocalChatMessageStore {
  const LocalChatMessageStore(this._box);

  final Box<String> _box;

  Future<void> upsert(LocalChatMessage message) async {
    final key = _storageKey(message);
    await _box.put(key, jsonEncode(message.toJson()));
    await _box.flush();
    debugPrint(
      '[CHAT_OPS][LOCAL][MESSAGE_STORE] upsert '
      'sender=${message.appUserId} peer=${message.peerUserId} '
      'local=${message.localId} server=${message.serverMessageId} '
      'boxLength=${_box.length}',
    );
  }

  Future<List<LocalChatMessage>> loadConversation({
    required int appUserId,
    required int peerUserId,
    int? roomId,
  }) async {
    final messages = <LocalChatMessage>[];
    for (final raw in _box.values) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        continue;
      }
      final message = LocalChatMessage.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (message.appUserId != appUserId || message.peerUserId != peerUserId) {
        continue;
      }
      messages.add(message);
    }

    return _deduplicate(messages)
      ..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  }

  Future<Map<int, LocalChatMessage>> loadLatestByAppUser({
    required int appUserId,
  }) async {
    final latestByPeer = <int, LocalChatMessage>{};
    for (final raw in _box.values) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        continue;
      }
      final message = LocalChatMessage.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (message.appUserId != appUserId || message.peerUserId <= 0) {
        continue;
      }
      final current = latestByPeer[message.peerUserId];
      if (current == null || message.createdAt.isAfter(current.createdAt)) {
        latestByPeer[message.peerUserId] = message;
      }
    }
    return latestByPeer;
  }

  String _storageKey(LocalChatMessage message) {
    return '${message.conversationKey}:${message.localId}';
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
  return next.updatedAt.isAfter(current.updatedAt) ? next : current;
}

String _randomCacheKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes);
}
