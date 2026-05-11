import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/widgets/identity_badge.dart';

class AppAccountPanel extends StatelessWidget {
  const AppAccountPanel({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          IdentityBadge(
            label: l10n.operatorIdentity,
            name: 'Operator',
            uid: 'admin',
          ),
          const SizedBox(height: 12),
          IdentityBadge(
            label: l10n.speakingIdentity,
            name: l10n.noAppAccountSelected,
            uid: '--',
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.person_add_alt_1),
            label: Text(l10n.addAppAccount),
          ),
        ],
      ),
    );
  }
}
