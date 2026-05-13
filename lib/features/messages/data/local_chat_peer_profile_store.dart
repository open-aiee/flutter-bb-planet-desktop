import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/security/secure_store_provider.dart';
import '../../../core/storage/encrypted_cache_store.dart';
import '../domain/local_chat_peer_profile.dart';
import 'local_chat_message_store.dart';

final localChatPeerProfileStoreProvider =
    FutureProvider<LocalChatPeerProfileStore>((ref) async {
      final secureStore = ref.read(secureStoreProvider);
      final cacheKey = await readOrCreateMessageCacheKey(secureStore);
      final box = await EncryptedCacheStore(
        encryptionKey: EncryptedCacheStore.normalizeKey(cacheKey),
      ).openBox('chat_peer_profiles_v1');
      return LocalChatPeerProfileStore(box);
    });

class LocalChatPeerProfileStore {
  const LocalChatPeerProfileStore(this._box);

  final Box<String> _box;

  Future<void> upsert(LocalChatPeerProfile profile) async {
    if (profile.appUserId <= 0 || profile.peerUserId <= 0) {
      return;
    }
    await _box.put(
      _storageKey(profile.appUserId, profile.peerUserId),
      jsonEncode(profile.toJson()),
    );
    await _box.flush();
    debugPrint(
      '[CHAT_OPS][LOCAL][PROFILE_STORE] upsert '
      'sender=${profile.appUserId} peer=${profile.peerUserId} '
      'avatar=${profile.avatarUrl.isNotEmpty} boxLength=${_box.length}',
    );
  }

  Future<Map<int, LocalChatPeerProfile>> loadByAppUser({
    required int appUserId,
  }) async {
    final profiles = <int, LocalChatPeerProfile>{};
    for (final raw in _box.values) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        continue;
      }
      final profile = LocalChatPeerProfile.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (profile.appUserId != appUserId || profile.peerUserId <= 0) {
        continue;
      }
      profiles[profile.peerUserId] = profile;
    }
    return profiles;
  }

  String _storageKey(int appUserId, int peerUserId) {
    return 'sender:$appUserId:direct-peer:$peerUserId';
  }
}
