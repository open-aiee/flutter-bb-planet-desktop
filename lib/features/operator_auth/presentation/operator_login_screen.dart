import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../workspace/presentation/chat_ops_workspace_screen.dart';
import '../application/operator_auth_controller.dart';

class OperatorLoginScreen extends ConsumerStatefulWidget {
  const OperatorLoginScreen({super.key});

  static const routePath = '/login';

  @override
  ConsumerState<OperatorLoginScreen> createState() =>
      _OperatorLoginScreenState();
}

class _OperatorLoginScreenState extends ConsumerState<OperatorLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _userNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _googleCodeController = TextEditingController();

  @override
  void dispose() {
    _userNameController.dispose();
    _passwordController.dispose();
    _googleCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final authState = ref.watch(operatorAuthControllerProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.appTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.operatorLoginSubtitle,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _userNameController,
                      enabled: !authState.isLoading,
                      decoration: InputDecoration(
                        labelText: l10n.operatorAccount,
                      ),
                      validator: (value) =>
                          _isBlank(value) ? l10n.operatorAccountRequired : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !authState.isLoading,
                      obscureText: true,
                      decoration: InputDecoration(labelText: l10n.password),
                      validator: (value) =>
                          _isBlank(value) ? l10n.passwordRequired : null,
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _googleCodeController,
                      enabled: !authState.isLoading,
                      decoration: InputDecoration(
                        labelText: l10n.googleCodeOptional,
                      ),
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    if (authState.errorMessage != null) ...[
                      const SizedBox(height: 14),
                      _LoginErrorBanner(message: authState.errorMessage!),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: authState.isLoading ? null : _submit,
                      child: authState.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.signIn),
                    ),
                    if (appConfig.allowAuthBypass) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: authState.isLoading ? null : _bypass,
                        child: Text(l10n.devEnterWorkspace),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final success = await ref
        .read(operatorAuthControllerProvider.notifier)
        .login(
          userName: _userNameController.text,
          password: _passwordController.text,
          googleCode: _googleCodeController.text,
        );
    if (success && mounted) {
      context.go(ChatOpsWorkspaceScreen.routePath);
    }
  }

  void _bypass() {
    ref.read(operatorAuthControllerProvider.notifier).bypassForDevelopment();
    context.go(ChatOpsWorkspaceScreen.routePath);
  }
}

class _LoginErrorBanner extends StatelessWidget {
  const _LoginErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
