import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/identity_badge.dart';
import '../application/app_account_auth_controller.dart';
import '../../operator_auth/application/operator_auth_controller.dart';

class AppAccountPanel extends ConsumerWidget {
  const AppAccountPanel({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final operatorSession = ref.watch(
      operatorAuthControllerProvider.select((state) => state.session),
    );
    final appAccountState = ref.watch(appAccountAuthControllerProvider);
    final appSession = appAccountState.session;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          IdentityBadge(
            label: l10n.operatorIdentity,
            name: operatorSession?.displayName ?? 'Operator',
            uid: operatorSession?.id.toString() ?? 'admin',
          ),
          const SizedBox(height: 12),
          IdentityBadge(
            label: l10n.speakingIdentity,
            name: appSession?.displayName ?? l10n.noAppAccountSelected,
            uid: appSession?.id.toString() ?? '--',
          ),
          if (appSession != null) ...[
            const SizedBox(height: 8),
            Text(
              appSession.email,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const Spacer(),
          if (appAccountState.errorMessage != null) ...[
            _AppAccountError(message: appAccountState.errorMessage!),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: appAccountState.isLoading
                ? null
                : () => _showAppAccountLoginDialog(context),
            icon: const Icon(Icons.person_add_alt_1),
            label: appAccountState.isLoading
                ? Text(l10n.signingInAppAccount)
                : Text(
                    appSession == null
                        ? l10n.addAppAccount
                        : l10n.switchAppAccount,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAppAccountLoginDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppAccountLoginDialog(),
    );
  }
}

class AppAccountLoginDialog extends ConsumerStatefulWidget {
  const AppAccountLoginDialog({super.key});

  @override
  ConsumerState<AppAccountLoginDialog> createState() =>
      _AppAccountLoginDialogState();
}

class _AppAccountLoginDialogState extends ConsumerState<AppAccountLoginDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _forceLogin = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appAccountState = ref.watch(appAccountAuthControllerProvider);

    return AlertDialog(
      title: Text(l10n.appAccountLoginTitle),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.appAccountLoginSubtitle),
              const SizedBox(height: 18),
              TextFormField(
                controller: _emailController,
                enabled: !appAccountState.isLoading,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: l10n.appAccountEmail),
                validator: (value) =>
                    _isBlank(value) ? l10n.appAccountEmailRequired : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                enabled: !appAccountState.isLoading,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.appAccountPassword),
                validator: (value) =>
                    _isBlank(value) ? l10n.appAccountPasswordRequired : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _forceLogin,
                onChanged: appAccountState.isLoading
                    ? null
                    : (value) => setState(() => _forceLogin = value ?? false),
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.forceAppAccountLogin),
                subtitle: Text(l10n.forceAppAccountLoginHint),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: appAccountState.isLoading
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: appAccountState.isLoading ? null : _submit,
          child: appAccountState.isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.signInAppAccount),
        ),
      ],
    );
  }

  bool _isBlank(String? value) => value == null || value.trim().isEmpty;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final success = await ref
        .read(appAccountAuthControllerProvider.notifier)
        .login(
          email: _emailController.text,
          password: _passwordController.text,
          forceLogin: _forceLogin,
        );
    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _AppAccountError extends StatelessWidget {
  const _AppAccountError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          message,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }
}
