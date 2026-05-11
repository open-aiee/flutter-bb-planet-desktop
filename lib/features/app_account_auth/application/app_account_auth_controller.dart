import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/desktop_device_id.dart';
import '../../../core/security/secure_store_provider.dart';
import '../data/app_account_auth_api.dart';
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
      state = state.copyWith(isLoading: false, session: session);
      return true;
    } on AppAccountLoginException catch (error) {
      state = state.copyWith(isLoading: false, errorMessage: error.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Network error, please try again.',
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
