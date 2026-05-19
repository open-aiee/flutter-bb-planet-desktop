import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../application/app_account_auth_controller.dart';
import '../domain/app_account_history_entry.dart';
import 'app_account_panel.dart';

class AppAccountHistoryDialog extends ConsumerStatefulWidget {
  const AppAccountHistoryDialog({super.key, this.showCloseButton = false});

  final bool showCloseButton;

  @override
  ConsumerState<AppAccountHistoryDialog> createState() =>
      _AppAccountHistoryDialogState();
}

class _AppAccountHistoryDialogState
    extends ConsumerState<AppAccountHistoryDialog> {
  late Future<List<AppAccountHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadHistory();
  }

  Future<List<AppAccountHistoryEntry>> _loadHistory() {
    return ref
        .read(appAccountAuthControllerProvider.notifier)
        .readLoginHistory();
  }

  List<AppAccountHistoryEntry> _mergeCurrentAccount(
    List<AppAccountHistoryEntry> accounts,
    AppAccountAuthState appState,
  ) {
    final session = appState.session;
    if (session == null) {
      return accounts;
    }
    final exists = accounts.any(
      (account) =>
          (session.id > 0 && account.id == session.id) ||
          (session.email.trim().isNotEmpty &&
              account.email.trim().toLowerCase() ==
                  session.email.trim().toLowerCase()),
    );
    if (exists) {
      return accounts;
    }
    return [
      AppAccountHistoryEntry(
        id: session.id,
        email: session.email,
        displayName: session.displayName,
        avatarUrl: session.avatarUrl ?? '',
        password: '',
        token: session.certificate,
        updatedAt: DateTime.now(),
      ),
      ...accounts,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appState = ref.watch(appAccountAuthControllerProvider);
    final screenSize = MediaQuery.sizeOf(context);
    final height = (screenSize.height - 72).clamp(560.0, 840.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 34, vertical: 30),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 540,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xff0b141a).withValues(alpha: 0.16),
              offset: const Offset(0, 24),
              blurRadius: 58,
            ),
          ],
        ),
        child: Column(
          children: [
            _DialogHeader(
              title: l10n.appAccountHistoryTitle,
              subtitle: l10n.appAccountHistorySubtitle,
              showCloseButton: widget.showCloseButton,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: FutureBuilder<List<AppAccountHistoryEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xff1da855),
                        strokeWidth: 2.4,
                      ),
                    );
                  }
                  final accounts = _mergeCurrentAccount(
                    snapshot.data ?? const [],
                    appState,
                  );
                  if (accounts.isEmpty) {
                    return _EmptyHistory(
                      message: l10n.appAccountHistoryEmpty,
                      buttonLabel: l10n.addAppAccount,
                      onAdd: _openLoginDialog,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 20),
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      final isCurrent = appState.session?.id == account.id;
                      return _AccountHistoryTile(
                        account: account,
                        isCurrent: isCurrent,
                        isLoading: appState.isLoading,
                        onlineLabel: l10n.appAccountStatusOnline,
                        switchLabel: l10n.appAccountStatusSwitch,
                        offlineLabel: l10n.appAccountStatusOffline,
                        onSelect: account.canLogin
                            ? () => _selectAccount(account)
                            : isCurrent
                            ? () => _selectAccount(account)
                            : null,
                      );
                    },
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemCount: accounts.length,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
              child: SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: appState.isLoading ? null : _openLoginDialog,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                  label: Text(l10n.addAppAccount),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xff1f2c34),
                    side: const BorderSide(color: Color(0xffd9dee3)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectAccount(AppAccountHistoryEntry account) async {
    final current = ref.read(appAccountAuthControllerProvider).session;
    if (current?.id == account.id) {
      Navigator.of(context).pop();
      return;
    }
    final success = await ref
        .read(appAccountAuthControllerProvider.notifier)
        .login(
          email: account.email,
          password: account.password,
          forceLogin: true,
        );
    if (!mounted) {
      return;
    }
    if (success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _future = _loadHistory());
  }

  Future<void> _openLoginDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppAccountLoginDialog(),
    );
    if (!mounted) {
      return;
    }
    setState(() => _future = _loadHistory());
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.title,
    required this.subtitle,
    required this.showCloseButton,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final bool showCloseButton;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 126,
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 18),
      decoration: const BoxDecoration(
        color: Color(0xfff7f7fc),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xffe8f5ef),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.manage_accounts_rounded,
              color: Color(0xff1da855),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff111b21),
                    fontSize: 20,
                    height: 28 / 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff667781),
                    fontSize: 13,
                    height: 18 / 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (showCloseButton) ...[
            const SizedBox(width: 10),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
              color: const Color(0xff667781),
              splashRadius: 20,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountHistoryTile extends StatelessWidget {
  const _AccountHistoryTile({
    required this.account,
    required this.isCurrent,
    required this.isLoading,
    required this.onlineLabel,
    required this.switchLabel,
    required this.offlineLabel,
    required this.onSelect,
  });

  final AppAccountHistoryEntry account;
  final bool isCurrent;
  final bool isLoading;
  final String onlineLabel;
  final String switchLabel;
  final String offlineLabel;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final displayName = account.displayName.trim().isEmpty
        ? account.email
        : account.displayName;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onSelect,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isCurrent ? const Color(0xfff0f2f5) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xffeef1f3)),
          ),
          child: Row(
            children: [
              _HistoryAvatar(
                label: displayName,
                avatarUrl: account.avatarUrl,
                online: isCurrent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff111b21),
                        fontSize: 15,
                        height: 22 / 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.email,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xff667781),
                        fontSize: 12,
                        height: 16 / 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusButton(
                isCurrent: isCurrent,
                isLoading: isLoading,
                onlineLabel: onlineLabel,
                switchLabel: switchLabel,
                offlineLabel: offlineLabel,
                onSelect: onSelect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryAvatar extends StatelessWidget {
  const _HistoryAvatar({
    required this.label,
    required this.avatarUrl,
    required this.online,
  });

  final String label;
  final String avatarUrl;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final initial = label.characters.isEmpty
        ? '#'
        : label.characters.first.toUpperCase();
    final url = avatarUrl.trim();
    return Stack(
      children: [
        Container(
          width: 52,
          height: 52,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xffd9c2a6),
            shape: BoxShape.circle,
          ),
          child: url.isEmpty
              ? Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xff54656f),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : Image.network(
                  url,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Text(
                    initial,
                    style: const TextStyle(
                      color: Color(0xff54656f),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
        ),
        if (online)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xff1da855),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.isCurrent,
    required this.isLoading,
    required this.onlineLabel,
    required this.switchLabel,
    required this.offlineLabel,
    required this.onSelect,
  });

  final bool isCurrent;
  final bool isLoading;
  final String onlineLabel;
  final String switchLabel;
  final String offlineLabel;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      return SizedBox(
        height: 34,
        child: FilledButton.icon(
          onPressed: isLoading ? null : onSelect,
          icon: const Icon(Icons.circle, size: 9),
          label: Text(onlineLabel),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xffe8f5ef),
            foregroundColor: const Color(0xff1da855),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 34,
      child: FilledButton(
        onPressed: isLoading ? null : onSelect,
        style: FilledButton.styleFrom(
          backgroundColor: onSelect == null
              ? const Color(0xffeef1f3)
              : const Color(0xff111b21),
          foregroundColor: onSelect == null
              ? const Color(0xff667781)
              : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Text(onSelect == null ? offlineLabel : switchLabel),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({
    required this.message,
    required this.buttonLabel,
    required this.onAdd,
  });

  final String message;
  final String buttonLabel;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_circle_outlined,
              size: 58,
              color: Color(0xffaebac1),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff667781),
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
