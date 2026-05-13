import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/desktop_device_id.dart';
import '../../../core/security/secure_store_provider.dart';
import '../data/app_account_history_store.dart';
import '../data/app_account_auth_api.dart';
import '../domain/app_account_history_entry.dart';
import '../domain/app_user_session.dart';

final appAccountAuthApiProvider = Provider<AppAccountAuthApi>((ref) {
  return AppAccountAuthApi();
});

final appAccountAuthControllerProvider =
    NotifierProvider<AppAccountAuthController, AppAccountAuthState>(
      AppAccountAuthController.new,
    );

class AppAccountAuthController extends Notifier<AppAccountAuthState> {
  static const _certificateKey = 'appAccount.certificate';
  static const _idKey = 'appAccount.id';
  static const _emailKey = 'appAccount.email';
  static const _displayNameKey = 'appAccount.displayName';
  static const _savedLoginEmailKey = 'appAccount.savedLogin.email';
  static const _savedLoginPasswordKey = 'appAccount.savedLogin.password';
  static const _legacyHistoryKey = 'appAccount.history';

  @override
  AppAccountAuthState build() {
    return const AppAccountAuthState();
  }

  Future<bool> login({
    required String email,
    required String password,
    bool forceLogin = false,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final secureStore = ref.read(secureStoreProvider);
      final deviceId = await DesktopDeviceId(
        secureStore: secureStore,
      ).getOrCreate();
      final session = await ref
          .read(appAccountAuthApiProvider)
          .login(
            email: email,
            password: password,
            deviceId: deviceId,
            forceLogin: forceLogin,
          );
      await _persistSession(session);
      await _persistSavedLoginCredentials(email: email, password: password);
      await _persistHistoryEntry(
        session: session,
        email: email,
        password: password,
      );
      state = state.copyWith(isLoading: false, session: session);
      return true;
    } on AppAccountLoginException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.message);
      return false;
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Login failed: $error',
      );
      return false;
    }
  }

  Future<void> logout() async {
    final store = ref.read(secureStoreProvider);
    await store.delete(_certificateKey);
    await store.delete(_idKey);
    await store.delete(_emailKey);
    await store.delete(_displayNameKey);
    state = const AppAccountAuthState();
  }

  Future<void> _persistSession(AppUserSession session) async {
    final store = ref.read(secureStoreProvider);
    await store.write(_certificateKey, session.certificate);
    await store.write(_idKey, session.id.toString());
    await store.write(_emailKey, session.email);
    await store.write(_displayNameKey, session.displayName);
  }

  Future<void> _persistSavedLoginCredentials({
    required String email,
    required String password,
  }) async {
    final store = ref.read(secureStoreProvider);
    await store.write(_savedLoginEmailKey, email.trim());
    await store.write(_savedLoginPasswordKey, password);
  }

  Future<AppAccountSavedLoginCredentials> readSavedLoginCredentials() async {
    final store = ref.read(secureStoreProvider);
    final email = await store.read(_savedLoginEmailKey);
    final password = await store.read(_savedLoginPasswordKey);
    return AppAccountSavedLoginCredentials(
      email: email ?? '',
      password: password ?? '',
    );
  }

  Future<List<AppAccountHistoryEntry>> readLoginHistory() async {
    final store = await ref.read(appAccountHistoryStoreProvider.future);
    final current = await store.loadAll();
    if (current.isNotEmpty) {
      return current;
    }
    final migrated = await _migrateLegacyHistory(store);
    if (migrated.isNotEmpty) {
      return migrated;
    }
    return const [];
  }

  Future<void> _persistHistoryEntry({
    required AppUserSession session,
    required String email,
    required String password,
  }) async {
    final nextEntry = AppAccountHistoryEntry(
      id: session.id,
      email: email.trim().isEmpty ? session.email : email.trim(),
      displayName: session.displayName,
      avatarUrl: session.avatarUrl ?? '',
      password: password,
      token: session.certificate,
      updatedAt: DateTime.now(),
    );
    final store = await ref.read(appAccountHistoryStoreProvider.future);
    await store.upsert(nextEntry);
  }

  Future<List<AppAccountHistoryEntry>> _migrateLegacyHistory(
    AppAccountHistoryStore historyStore,
  ) async {
    final store = ref.read(secureStoreProvider);
    final migrated = <AppAccountHistoryEntry>[];
    final raw = await store.read(_legacyHistoryKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded.whereType<Map>()) {
            var entry = AppAccountHistoryEntry.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (entry.id > 0 || entry.email.trim().isNotEmpty) {
              final currentCertificate = await store.read(_certificateKey);
              final currentId = int.tryParse(await store.read(_idKey) ?? '');
              final currentEmail = await store.read(_emailKey);
              final isCurrent =
                  (currentId != null &&
                      currentId > 0 &&
                      currentId == entry.id) ||
                  ((currentEmail ?? '').trim().isNotEmpty &&
                      currentEmail!.trim().toLowerCase() ==
                          entry.email.trim().toLowerCase());
              if (entry.token.isEmpty &&
                  isCurrent &&
                  (currentCertificate ?? '').trim().isNotEmpty) {
                entry = AppAccountHistoryEntry(
                  id: entry.id,
                  email: entry.email,
                  displayName: entry.displayName,
                  avatarUrl: entry.avatarUrl,
                  password: entry.password,
                  token: currentCertificate ?? '',
                  updatedAt: entry.updatedAt,
                );
              }
              migrated.add(entry);
            }
          }
        }
      } catch (_) {
        // Ignore legacy data that cannot be decoded.
      }
    }

    final certificate = await store.read(_certificateKey);
    final id = int.tryParse(await store.read(_idKey) ?? '') ?? 0;
    final email = await store.read(_emailKey);
    final displayName = await store.read(_displayNameKey);
    final savedEmail = await store.read(_savedLoginEmailKey);
    final savedPassword = await store.read(_savedLoginPasswordKey);
    if ((id > 0 || (email ?? savedEmail ?? '').trim().isNotEmpty) &&
        (certificate ?? '').trim().isNotEmpty) {
      migrated.add(
        AppAccountHistoryEntry(
          id: id,
          email: (savedEmail ?? email ?? '').trim(),
          displayName: (displayName ?? email ?? savedEmail ?? '').trim(),
          avatarUrl: '',
          password: savedPassword ?? '',
          token: certificate ?? '',
          updatedAt: DateTime.now(),
        ),
      );
    }

    final deduped = <String, AppAccountHistoryEntry>{};
    for (final entry in migrated) {
      final key = entry.id > 0
          ? 'id:${entry.id}'
          : 'email:${entry.email.trim().toLowerCase()}';
      deduped[key] = entry;
    }
    for (final entry in deduped.values) {
      await historyStore.upsert(entry);
    }
    final values = deduped.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return values;
  }
}

class AppAccountSavedLoginCredentials {
  const AppAccountSavedLoginCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;

  bool get isNotEmpty => email.trim().isNotEmpty || password.isNotEmpty;
}

class AppAccountAuthState {
  const AppAccountAuthState({
    this.isLoading = false,
    this.session,
    this.errorMessage,
  });

  final bool isLoading;
  final AppUserSession? session;
  final String? errorMessage;

  bool get isAuthenticated => session != null;

  AppAccountAuthState copyWith({
    bool? isLoading,
    AppUserSession? session,
    String? errorMessage,
  }) {
    return AppAccountAuthState(
      isLoading: isLoading ?? this.isLoading,
      session: session ?? this.session,
      errorMessage: errorMessage,
    );
  }
}
