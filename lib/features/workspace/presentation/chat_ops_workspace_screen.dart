import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../app_account_auth/presentation/app_account_panel.dart';
import '../../conversations/presentation/conversation_list_panel.dart';
import '../../messages/presentation/chat_panel.dart';

class ChatOpsWorkspaceScreen extends StatelessWidget {
  const ChatOpsWorkspaceScreen({super.key});

  static const routePath = '/workspace';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 280,
            child: AppAccountPanel(title: l10n.leftPanelTitle),
          ),
          const VerticalDivider(width: 1),
          SizedBox(
            width: 360,
            child: ConversationListPanel(title: l10n.middlePanelTitle),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: ChatPanel(title: l10n.rightPanelTitle)),
        ],
      ),
    );
  }
}
