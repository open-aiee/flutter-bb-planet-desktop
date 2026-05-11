import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

class ConversationListPanel extends StatelessWidget {
  const ConversationListPanel({required this.title, super.key});

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
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.searchUserHint,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Center(
              child: Text(
                l10n.selectCompanionFirst,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
