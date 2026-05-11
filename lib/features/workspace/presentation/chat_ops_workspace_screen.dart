import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_account_auth/application/app_account_auth_controller.dart';
import '../../app_account_auth/presentation/app_account_panel.dart';
import '../../operator_auth/application/operator_auth_controller.dart';

class ChatOpsWorkspaceScreen extends ConsumerWidget {
  const ChatOpsWorkspaceScreen({super.key});

  static const routePath = '/workspace';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final operatorSession = ref.watch(
      operatorAuthControllerProvider.select((state) => state.session),
    );
    final appAccountState = ref.watch(appAccountAuthControllerProvider);

    return Scaffold(
      body: _HomeScreenMainWindow(
        operatorName: operatorSession?.displayName ?? 'Dev Operator',
        appAccountName:
            appAccountState.session?.displayName ?? 'No APP account',
        appAccountOnline: appAccountState.isAuthenticated,
        appAccountBusy: appAccountState.isLoading,
        onAppAccountTap: () => showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AppAccountLoginDialog(),
        ),
      ),
    );
  }
}

class _HomeScreenMainWindow extends StatelessWidget {
  const _HomeScreenMainWindow({
    required this.operatorName,
    required this.appAccountName,
    required this.appAccountOnline,
    required this.appAccountBusy,
    required this.onAppAccountTap,
  });

  final String operatorName;
  final String appAccountName;
  final bool appAccountOnline;
  final bool appAccountBusy;
  final VoidCallback onAppAccountTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Row(
        children: [
          _LeftSection(
            operatorName: operatorName,
            appAccountName: appAccountName,
            appAccountOnline: appAccountOnline,
            appAccountBusy: appAccountBusy,
            onAppAccountTap: onAppAccountTap,
          ),
          const Expanded(child: _ChatSection()),
        ],
      ),
    );
  }
}

class _LeftSection extends StatelessWidget {
  const _LeftSection({
    required this.operatorName,
    required this.appAccountName,
    required this.appAccountOnline,
    required this.appAccountBusy,
    required this.onAppAccountTap,
  });

  final String operatorName;
  final String appAccountName;
  final bool appAccountOnline;
  final bool appAccountBusy;
  final VoidCallback onAppAccountTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 424,
      child: Row(
        children: [
          _NavigationRail(
            operatorName: operatorName,
            appAccountName: appAccountName,
            appAccountOnline: appAccountOnline,
            appAccountBusy: appAccountBusy,
            onAppAccountTap: onAppAccountTap,
          ),
          const Expanded(child: _ConversationPane()),
        ],
      ),
    );
  }
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.operatorName,
    required this.appAccountName,
    required this.appAccountOnline,
    required this.appAccountBusy,
    required this.onAppAccountTap,
  });

  final String operatorName;
  final String appAccountName;
  final bool appAccountOnline;
  final bool appAccountBusy;
  final VoidCallback onAppAccountTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 94,
      color: const Color(0xfffbfbfb),
      child: Stack(
        children: [
          Positioned(
            top: 53,
            left: 0,
            right: 0,
            child: Column(
              children: const [
                _RailItem(
                  icon: Icons.chat_bubble_rounded,
                  label: 'Chats',
                  active: true,
                  badge: '6',
                ),
                SizedBox(height: 12),
                _RailItem(icon: Icons.update_rounded, label: 'Updates'),
                SizedBox(height: 12),
                _RailItem(icon: Icons.groups_2_rounded, label: 'Commun...'),
                SizedBox(height: 12),
                _RailItem(icon: Icons.call_rounded, label: 'Calls'),
                SizedBox(height: 12),
                _RailItem(icon: Icons.campaign_rounded, label: 'Channels'),
              ],
            ),
          ),
          Positioned(
            left: 35,
            bottom: 197,
            child: Icon(
              Icons.help_outline_rounded,
              color: const Color(0xff54656f),
              size: 24,
            ),
          ),
          Positioned(
            left: 23,
            bottom: 22,
            child: Tooltip(
              message: '$operatorName\n$appAccountName',
              child: InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: onAppAccountTap,
                child: _AccountAvatar(
                  label: appAccountOnline ? appAccountName : operatorName,
                  online: appAccountOnline,
                  busy: appAccountBusy,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final bool active;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final iconColor = active
        ? const Color(0xff3b4a54)
        : const Color(0xff667781);
    final textColor = active
        ? const Color(0xff1d1b20)
        : const Color(0xff667781);

    return SizedBox(
      width: 94,
      height: 68,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 64,
                height: 32,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xff1d1b20).withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              if (badge != null)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    height: 16,
                    constraints: const BoxConstraints(minWidth: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xffb3261e),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badge!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        height: 1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              height: 16 / 12,
              letterSpacing: 0.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.label,
    required this.online,
    required this.busy,
  });

  final String label;
  final bool online;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final initials = label.trim().isEmpty
        ? 'BB'
        : label
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((part) => part.characters.first.toUpperCase())
              .join();

    return Stack(
      children: [
        Container(
          width: 49,
          height: 49,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xffff8a68), Color(0xffdd3e84)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x7ae4e4e4)),
          ),
          alignment: Alignment.center,
          child: busy
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        Positioned(
          right: 2,
          bottom: 2,
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: online ? const Color(0xff1da855) : const Color(0xffd7dfe3),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane();

  static const _items = [
    _Conversation(
      name: 'Claire',
      message: 'Haha oh man',
      time: '05:14 pm',
      color: Color(0xffffb7ca),
      emoji: 'C',
      pinned: true,
    ),
    _Conversation(
      name: 'Joe',
      message: 'Haha that’s terrifying 😂',
      time: '07:38 am',
      color: Color(0xffb7d9ff),
      emoji: 'J',
      selected: true,
      delivered: true,
    ),
    _Conversation(
      name: 'Optimus prime',
      message: 'My name is Optimus prime 🤖',
      time: '11:49',
      color: Color(0xffff523a),
      emoji: 'O',
      unread: 5,
    ),
    _Conversation(
      name: 'Progate Rwanda Deve...',
      message: '>Theotime: This is amazing...',
      time: '07:40',
      color: Color(0xff8f90ff),
      emoji: 'P',
      unread: 1,
    ),
    _Conversation(
      name: 'Yves',
      message: 'Bro, that’s so sick ⚡',
      time: '08:20',
      color: Color(0xffb48764),
      emoji: 'Y',
      unread: 1,
    ),
    _Conversation(
      name: 'Mucyo',
      message: 'The new update is live 🚀',
      time: '01:09',
      color: Color(0xffd8dddf),
      emoji: 'M',
      unread: 1,
    ),
    _Conversation(
      name: 'Joy',
      message: 'Haha that’s terrifying 😂',
      time: '01:55',
      color: Color(0xff1d1b20),
      emoji: 'J',
      unread: 1,
    ),
    _Conversation(
      name: 'Elvin',
      message: 'Are yu still there?',
      time: '01:52',
      color: Color(0xffd8dddf),
      emoji: 'E',
      unread: 1,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          Positioned(
            left: 90,
            top: 13,
            child: Icon(
              Icons.edit_square,
              color: const Color(0xff54656f),
              size: 24,
            ),
          ),
          Positioned(
            right: 20,
            top: 13,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: const Color(0xff54656f),
              size: 24,
            ),
          ),
          Positioned(left: 18, top: 42, width: 312, child: _SearchField()),
          Positioned(
            left: 10,
            width: 312,
            top: 108,
            bottom: 0,
            child: ListView.separated(
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) =>
                  _ConversationTile(item: _items[index]),
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemCount: _items.length,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 312,
      height: 32,
      decoration: BoxDecoration(
        color: const Color(0xfff0f2f5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: const [
          SizedBox(width: 13),
          Icon(Icons.search, color: Color(0xff667781), size: 18),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Search or start a new chat',
              style: TextStyle(
                color: Color(0xff667781),
                fontSize: 14,
                height: 1,
              ),
            ),
          ),
          Icon(Icons.tune_rounded, color: Color(0xff667781), size: 16),
          SizedBox(width: 13),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.item});

  final _Conversation item;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 312,
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: item.selected ? const Color(0xfff0f2f5) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _LetterAvatar(color: item.color, label: item.emoji),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff3b4a54),
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.message,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff3b4a54),
                    fontSize: 12,
                    height: 16 / 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.time,
                style: TextStyle(
                  color: item.unread > 0
                      ? const Color(0xff1da855)
                      : const Color(0xff667781),
                  fontSize: 10,
                  height: 16 / 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              if (item.unread > 0)
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xff21c563),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${item.unread}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (item.pinned)
                const Icon(Icons.push_pin, size: 14, color: Color(0xff667781))
              else if (item.delivered)
                const Icon(Icons.done_all, size: 16, color: Color(0xff53bdeb))
              else
                const SizedBox(height: 20),
            ],
          ),
        ],
      ),
    );
  }
}

class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({
    required this.color,
    required this.label,
    this.size = 60,
  });

  final Color color;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: color.computeLuminance() > 0.55
              ? const Color(0xff54656f)
              : Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ChatSection extends StatelessWidget {
  const _ChatSection();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xfffafafa),
              child: CustomPaint(painter: _ChatWallpaperPainter()),
            ),
          ),
          const Positioned(left: 0, right: 0, top: 0, child: _ChatHeader()),
          const Positioned(
            left: 85,
            right: 85,
            top: 112,
            child: _EncryptionNotice(),
          ),
          const Positioned(
            top: 202,
            left: 0,
            right: 0,
            child: Center(child: _DatePill()),
          ),
          const Positioned(
            left: 31,
            top: 232,
            child: _IncomingBubble(
              width: 342,
              text:
                  'Hey brother, are you still a fan of UI design?\nCan I show you something?',
              time: '17:07',
            ),
          ),
          const Positioned(
            right: 24,
            top: 280,
            child: _OutgoingBubble(
              width: 203,
              text: 'Hey Regis, absolutely',
              time: '17:09',
            ),
          ),
          const Positioned(left: 30, top: 315, child: _ImageMessageBubble()),
          const Positioned(
            left: 30,
            top: 441,
            child: _IncomingBubble(
              width: 333,
              text: 'Checkout this cool project am working on 🤯',
              time: '17:12',
              singleLine: true,
            ),
          ),
          const Positioned(
            right: 24,
            top: 474,
            child: _OutgoingBubble(
              width: 173,
              text: 'Looks awesome',
              time: '17:13',
            ),
          ),
          Positioned(
            right: 4,
            top: 206,
            child: Container(
              width: 4,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xffb0c5c2),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MessageInput(),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 81,
      color: const Color(0xfff7f7fc),
      padding: const EdgeInsets.only(left: 24, right: 18, top: 16),
      child: Row(
        children: [
          const _LetterAvatar(color: Color(0xffd9c1aa), label: 'R', size: 48),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Text(
                  'RegisSaffi',
                  style: TextStyle(
                    color: Color(0xff111b21),
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    _OnlineDot(),
                    SizedBox(width: 5),
                    Text(
                      'Online',
                      style: TextStyle(
                        color: Color(0xff54656f),
                        fontSize: 12,
                        height: 16 / 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const _HeaderIcon(Icons.videocam_rounded),
          const SizedBox(width: 22),
          const _HeaderIcon(Icons.call_rounded),
          const SizedBox(width: 22),
          Container(width: 1, height: 24, color: const Color(0xffd8dfe3)),
          const SizedBox(width: 22),
          const _HeaderIcon(Icons.search_rounded),
          const SizedBox(width: 22),
          const _HeaderIcon(Icons.keyboard_arrow_down_rounded),
        ],
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: Color(0xff1da855),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Icon(icon, color: const Color(0xff253443), size: 22);
  }
}

class _EncryptionNotice extends StatelessWidget {
  const _EncryptionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xffffecdc),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: const [
          Icon(Icons.lock_rounded, color: Color(0xff3b4a54), size: 14),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Messages are end-to-end encrypted. No one outside of this chat, not even WhatsApp can read or listen to them click to learn more.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(0xff3b4a54),
                fontSize: 10,
                height: 1.18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(7.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0b141a).withValues(alpha: 0.13),
            offset: const Offset(0, 1),
            blurRadius: 0.5,
          ),
        ],
      ),
      child: const Text(
        'TODAY',
        style: TextStyle(color: Color(0xff54656f), fontSize: 12.5),
      ),
    );
  }
}

class _IncomingBubble extends StatelessWidget {
  const _IncomingBubble({
    required this.width,
    required this.text,
    required this.time,
    this.singleLine = false,
  });

  final double width;
  final String text;
  final String time;
  final bool singleLine;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -8,
          top: 0,
          child: CustomPaint(
            size: const Size(8, 13),
            painter: _BubbleTailPainter(color: Colors.white, incoming: true),
          ),
        ),
        Container(
          width: width,
          padding: EdgeInsets.fromLTRB(9, 6, singleLine ? 38 : 7, 3),
          decoration: _bubbleDecoration(Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  text,
                  maxLines: singleLine ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff111b21),
                    fontSize: 14.2,
                    height: 19 / 14.2,
                  ),
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  color: Color(0xff667781),
                  fontSize: 10,
                  height: 15 / 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OutgoingBubble extends StatelessWidget {
  const _OutgoingBubble({
    required this.width,
    required this.text,
    required this.time,
  });

  final double width;
  final String text;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(9, 6, 7, 3),
          decoration: _bubbleDecoration(const Color(0xffd9fdd3)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff111b21),
                    fontSize: 14.2,
                    height: 19 / 14.2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                time,
                style: const TextStyle(
                  color: Color(0xff667781),
                  fontSize: 10,
                  height: 15 / 10,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.done_all, size: 15, color: Color(0xff53bdeb)),
            ],
          ),
        ),
        Positioned(
          right: -8,
          top: 0,
          child: CustomPaint(
            size: const Size(8, 13),
            painter: _BubbleTailPainter(
              color: const Color(0xffd9fdd3),
              incoming: false,
            ),
          ),
        ),
      ],
    );
  }
}

BoxDecoration _bubbleDecoration(Color color) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(7.5),
    boxShadow: [
      BoxShadow(
        color: const Color(0xff0b141a).withValues(alpha: 0.13),
        offset: const Offset(0, 1),
        blurRadius: 0.25,
      ),
    ],
  );
}

class _ImageMessageBubble extends StatelessWidget {
  const _ImageMessageBubble();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -8,
          top: 0,
          child: CustomPaint(
            size: const Size(8, 13),
            painter: _BubbleTailPainter(color: Colors.white, incoming: true),
          ),
        ),
        Container(
          width: 336,
          height: 126,
          padding: const EdgeInsets.all(3),
          decoration: _bubbleDecoration(Colors.white),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xff1f2933),
                          Color(0xfff7f5f1),
                          Color(0xffcbd7e1),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 198,
                    height: 78,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 44,
                          height: 8,
                          decoration: BoxDecoration(
                            color: const Color(0xffff4b84),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: 126,
                          height: 5,
                          color: const Color(0xffcfd8df),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: 92,
                          height: 5,
                          color: const Color(0xffdfe6eb),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            Container(
                              width: 36,
                              height: 8,
                              color: const Color(0xfff24e8a),
                            ),
                            const Spacer(),
                            for (var i = 0; i < 3; i++)
                              Padding(
                                padding: const EdgeInsets.only(left: 5),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xff5877ff),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 5,
                  child: Text(
                    '17:10',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: -33,
          top: 57,
          child: Container(
            width: 25,
            height: 25,
            decoration: BoxDecoration(
              color: const Color(0xff0b141a).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.reply_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageInput extends StatelessWidget {
  const _MessageInput();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      color: const Color(0xfff6f6f6),
      padding: const EdgeInsets.fromLTRB(23, 16, 22, 16),
      child: Row(
        children: [
          const Icon(
            Icons.emoji_emotions_outlined,
            color: Color(0xff54656f),
            size: 26,
          ),
          const SizedBox(width: 24),
          const Icon(Icons.add_rounded, color: Color(0xff253443), size: 25),
          const SizedBox(width: 24),
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: const Text(
                'Type a message',
                style: TextStyle(
                  color: Color(0xff8f8f8f),
                  fontSize: 14,
                  height: 24 / 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 24),
          const Icon(Icons.mic_rounded, color: Color(0xff54656f), size: 24),
        ],
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter({required this.color, required this.incoming});

  final Color color;
  final bool incoming;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path();
    if (incoming) {
      path
        ..moveTo(size.width, 0)
        ..lineTo(0, 0)
        ..quadraticBezierTo(
          size.width * 0.7,
          size.height * 0.2,
          size.width,
          size.height,
        )
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..quadraticBezierTo(size.width * 0.3, size.height * 0.2, 0, size.height)
        ..close();
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.incoming != incoming;
  }
}

class _ChatWallpaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xffe9eeee).withValues(alpha: 0.42);

    for (var y = 110.0; y < size.height; y += 68) {
      for (var x = 28.0; x < size.width; x += 86) {
        final radius = 5 + ((x + y) % 4);
        canvas.drawCircle(Offset(x, y), radius, paint);
        canvas.drawLine(Offset(x + 20, y - 8), Offset(x + 34, y + 6), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Conversation {
  const _Conversation({
    required this.name,
    required this.message,
    required this.time,
    required this.color,
    required this.emoji,
    this.selected = false,
    this.pinned = false,
    this.delivered = false,
    this.unread = 0,
  });

  final String name;
  final String message;
  final String time;
  final Color color;
  final String emoji;
  final bool selected;
  final bool pinned;
  final bool delivered;
  final int unread;
}
