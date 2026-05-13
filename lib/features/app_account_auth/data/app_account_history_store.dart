import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../core/security/secure_store.dart';
import '../../../core/security/secure_store_provider.dart';
import '../../../core/storage/encrypted_cache_store.dart';
import '../domain/app_account_history_entry.dart';

final appAccountHistoryStoreProvider = FutureProvider<AppAccountHistoryStore>((
  ref,
) async {
  final secureStore = ref.read(secureStoreProvider);
  final cacheKey = await _readOrCreateHistoryCacheKey(secureStore);
  final box = await EncryptedCacheStore(
    encryptionKey: EncryptedCacheStore.normalizeKey(cacheKey),
  ).openBox('app_account_login_history_v1');
  return AppAccountHistoryStore(box);
});

class AppAccountHistoryStore {
  const AppAccountHistoryStore(this._box);

  final Box<String> _box;

  Future<void> upsert(AppAccountHistoryEntry entry) async {
    if (entry.id <= 0 && entry.email.trim().isEmpty) {
      return;
    }
    await _box.put(_storageKey(entry), jsonEncode(entry.toJson()));
    await _box.flush();
    debugPrint(
      '[CHAT_OPS][LOCAL][APP_ACCOUNT_HISTORY] upsert '
      'id=${entry.id} email=${entry.email} avatar=${entry.avatarUrl.isNotEmpty} '
      'token=${entry.token.isNotEmpty} boxLength=${_box.length}',
    );
  }

  Future<List<AppAccountHistoryEntry>> loadAll() async {
    final entries = <AppAccountHistoryEntry>[];
    for (final raw in _box.values) {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        continue;
      }
      final entry = AppAccountHistoryEntry.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (entry.id <= 0 && entry.email.trim().isEmpty) {
        continue;
      }
      entries.add(entry);
    }
    entries.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return entries;
  }

  String _storageKey(AppAccountHistoryEntry entry) {
    if (entry.id > 0) {
      return 'app-account:${entry.id}';
    }
    return 'app-account-email:${entry.email.trim().toLowerCase()}';
  }
}

Future<String> _readOrCreateHistoryCacheKey(SecureStore secureStore) async {
  var cacheKey = await secureStore.read('appAccount.history.encryptionKey');
  if (cacheKey == null || cacheKey.isEmpty) {
    cacheKey = _randomCacheKey();
    await secureStore.write('appAccount.history.encryptionKey', cacheKey);
  }
  return cacheKey;
}

String _randomCacheKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64UrlEncode(bytes);
}
