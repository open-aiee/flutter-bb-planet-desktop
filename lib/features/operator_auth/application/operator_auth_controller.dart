import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/secure_store_provider.dart';
import '../data/operator_auth_api.dart';
import '../domain/operator_session.dart';

final operatorAuthApiProvider = Provider<OperatorAuthApi>((ref) {
  return OperatorAuthApi();
});

final operatorAuthControllerProvider =
    NotifierProvider<OperatorAuthController, OperatorAuthState>(
      OperatorAuthController.new,
    );

class OperatorAuthController extends Notifier<OperatorAuthState> {
  static const _certificateKey = 'operator.certificate';
  static const _displayNameKey = 'operator.displayName';

  @override
  OperatorAuthState build() {
    return const OperatorAuthState();
  }

  Future<bool> login({
    required String userName,
    required String password,
    String? googleCode,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final session = await ref
          .read(operatorAuthApiProvider)
          .login(
            userName: userName,
            password: password,
            googleCode: googleCode,
          );
      await _persistSession(session);
      state = state.copyWith(isLoading: false, session: session);
      return true;
    } on OperatorLoginException catch (error) {
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
    await ref.read(secureStoreProvider).delete(_certificateKey);
    await ref.read(secureStoreProvider).delete(_displayNameKey);
    state = const OperatorAuthState();
  }

  void bypassForDevelopment() {
    state = state.copyWith(
      isLoading: false,
      errorMessage: null,
      session: const OperatorSession(
        id: 0,
        userName: 'dev-operator',
        displayName: 'Dev Operator',
        certificate: 'dev-bypass',
        source: 'desktop-dev',
      ),
    );
  }

  Future<void> _persistSession(OperatorSession session) async {
    final store = ref.read(secureStoreProvider);
    await store.write(_certificateKey, session.certificate);
    await store.write(_displayNameKey, session.displayName);
  }
}

class OperatorAuthState {
  const OperatorAuthState({
    this.isLoading = false,
    this.session,
    this.errorMessage,
  });

  final bool isLoading;
  final OperatorSession? session;
  final String? errorMessage;

  bool get isAuthenticated => session != null;

  OperatorAuthState copyWith({
    bool? isLoading,
    OperatorSession? session,
    String? errorMessage,
  }) {
    return OperatorAuthState(
      isLoading: isLoading ?? this.isLoading,
      session: session ?? this.session,
      errorMessage: errorMessage,
    );
  }
}
