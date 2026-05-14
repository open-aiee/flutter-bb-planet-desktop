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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xfff7f8f5), Color(0xffe9f4ee), Colors.white],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 42),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xfffff3cd),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xffffd45a)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: Color(0xff8a6100),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'High-risk operator workspace',
                                style: TextStyle(
                                  color: Color(0xff6f4e00),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          l10n.appTitle,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: const Color(0xff111b21),
                                fontSize: 38,
                              ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.operatorLoginSubtitle,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: const Color(0xff3b4a54),
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 24),
                        _IdentityBoundaryCard(l10n: l10n),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 440,
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
                              l10n.operatorIdentity,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.identityGuardHint,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _userNameController,
                              enabled: !authState.isLoading,
                              decoration: InputDecoration(
                                labelText: l10n.operatorAccount,
                              ),
                              validator: (value) => _isBlank(value)
                                  ? l10n.operatorAccountRequired
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _passwordController,
                              enabled: !authState.isLoading,
                              obscureText: true,
                              decoration: InputDecoration(
                                labelText: l10n.password,
                              ),
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
                              _LoginErrorBanner(
                                message: authState.errorMessage!,
                              ),
                            ],
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: authState.isLoading ? null : _submit,
                              child: authState.isLoading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(l10n.signIn),
                            ),
                            if (appConfig.allowAuthBypass) ...[
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: authState.isLoading
                                    ? null
                                    : _bypass,
                                child: Text(l10n.devEnterWorkspace),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
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

class _IdentityBoundaryCard extends StatelessWidget {
  const _IdentityBoundaryCard({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xffd9e5df)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BoundaryRow(
              icon: Icons.admin_panel_settings_rounded,
              title: l10n.operatorIdentity,
              detail: l10n.operatorLoginSubtitle,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Divider(height: 1),
            ),
            _BoundaryRow(
              icon: Icons.record_voice_over_rounded,
              title: l10n.speakingIdentity,
              detail: l10n.appAccountLoginSubtitle,
            ),
          ],
        ),
      ),
    );
  }
}

class _BoundaryRow extends StatelessWidget {
  const _BoundaryRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xff1da855), size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xff111b21),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(
                  color: Color(0xff54656f),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
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
