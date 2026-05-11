import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';

class ChatPanel extends StatelessWidget {
  const ChatPanel({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(l10n.identityGuardHint),
                      ],
                    ),
                  ),
                  const Chip(
                    label: Text('idle'),
                    avatar: Icon(Icons.circle_outlined, size: 16),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Text(
                l10n.selectConversationFirst,
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            enabled: false,
            decoration: InputDecoration(
              hintText: l10n.messageInputDisabledHint,
              suffixIcon: const Icon(Icons.send_outlined),
            ),
          ),
        ],
      ),
    );
  }
}
