import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../app/locale/app_locale_provider.dart';
import '../../../core/security/desktop_device_id.dart';
import '../../../core/security/secure_store_provider.dart';
import '../../../core/storage/desktop_data_directory.dart';
import '../../../core/websocket/connection_status.dart';
import '../../../core/websocket/im_session_manager.dart';
import '../../../core/websocket/im_socket_client.dart'
    show ImClientIndexEvent, ImSyncRecordAck;
import '../../../l10n/generated/app_localizations.dart';
import '../../app_account_auth/application/app_account_auth_controller.dart';
import '../../app_account_auth/domain/app_user_session.dart';
import '../../app_account_auth/presentation/app_account_history_dialog.dart';
import '../../messages/data/chat_conversation_api.dart';
import '../../messages/data/chat_media_upload_api.dart';
import '../../messages/data/direct_chat_api.dart';
import '../../messages/data/local_chat_peer_profile_store.dart';
import '../../messages/data/local_chat_message_store.dart';
import '../../messages/domain/local_chat_peer_profile.dart';
import '../../messages/domain/local_chat_message.dart';
import '../../operator_auth/application/operator_auth_controller.dart';
import '../../recommended_users/data/recommended_user_api.dart';
import '../../recommended_users/domain/recommended_user.dart';

enum _RailTab { chats, updates, communities, calls }

const _maxChatMessageLength = 3000;
const _collapsedMessageMaxLines = 15;
const _maxChatVideoBytes = 50 * 1024 * 1024;
const _maxVoiceRecordSeconds = 60;
const _chatTextFontSize = 14.2;
const _standaloneEmojiScale = 3.0;
final _standaloneEmojiPattern = RegExp(
  r'^(?:[\u00a9\u00ae\u203c\u2049\u2122\u2139\u2194-\u21aa\u231a-\u231b\u2328\u23cf\u23e9-\u23f3\u23f8-\u23fa\u24c2\u25aa-\u25ab\u25b6\u25c0\u25fb-\u25fe\u2600-\u27bf\u2934-\u2935\u2b05-\u2b55\u3030\u303d\u3297\u3299\ufe0f\u200d]|\ud83c[\udde6-\uddff\udf00-\udfff]|\ud83d[\udc00-\ude4f\ude80-\udeff]|\ud83e[\udd00-\uddff]|\s)+$',
);

const _emojiGameSendType = 47;
const _chatImageExtensions = <String>[
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'heic',
  'heif',
];
const _chatVideoExtensions = <String>[
  'mp4',
  'mov',
  'm4v',
  'avi',
  'mkv',
  'webm',
];

class _SelectedChatMedia {
  const _SelectedChatMedia({
    required this.path,
    required this.fileName,
    required this.isVideo,
    required this.fileSizeBytes,
  });

  final String path;
  final String fileName;
  final bool isVideo;
  final int fileSizeBytes;
}

class _SelectedVoiceRecording {
  const _SelectedVoiceRecording({
    required this.path,
    required this.fileName,
    required this.durationSeconds,
    required this.fileSizeBytes,
  });

  final String path;
  final String fileName;
  final int durationSeconds;
  final int fileSizeBytes;
}

class _MediaDimensions {
  const _MediaDimensions({required this.width, required this.height});

  final int width;
  final int height;
}

final _desktopChatEmojis = <String>[
  '👌',
  '👍',
  '✌',
  ...[
    for (var codePoint = 0x1F600; codePoint <= 0x1F64F; codePoint++)
      String.fromCharCode(codePoint),
  ],
];

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
        appAccountSession: appAccountState.session,
        appAccountOnline: appAccountState.isAuthenticated,
        appAccountBusy: appAccountState.isLoading,
        appAccountAvatarUrl: appAccountState.session?.avatarUrl,
        onAppAccountTap: () => showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AppAccountHistoryDialog(),
        ),
        onSettingsTap: () => showDialog<void>(
          context: context,
          builder: (_) => const _SettingsDialog(),
        ),
      ),
    );
  }
}

class _HomeScreenMainWindow extends ConsumerStatefulWidget {
  const _HomeScreenMainWindow({
    required this.operatorName,
    required this.appAccountName,
    required this.appAccountSession,
    required this.appAccountOnline,
    required this.appAccountBusy,
    required this.appAccountAvatarUrl,
    required this.onAppAccountTap,
    required this.onSettingsTap,
  });

  final String operatorName;
  final String appAccountName;
  final AppUserSession? appAccountSession;
  final bool appAccountOnline;
  final bool appAccountBusy;
  final String? appAccountAvatarUrl;
  final VoidCallback onAppAccountTap;
  final VoidCallback onSettingsTap;

  @override
  ConsumerState<_HomeScreenMainWindow> createState() =>
      _HomeScreenMainWindowState();
}

class _HomeScreenMainWindowState extends ConsumerState<_HomeScreenMainWindow> {
  _RailTab _selectedTab = _RailTab.chats;
  int _selectedConversationIndex = 0;
  bool _isConversationLoading = false;
  bool _isSearchLoading = false;
  bool _didShowAccountHistory = false;
  int _loadRequestId = 0;
  int _searchRequestId = 0;
  Timer? _searchDebounce;
  Timer? _activeConversationSyncTimer;
  StreamSubscription<Map<String, dynamic>>? _incomingMessageSubscription;
  StreamSubscription<ImClientIndexEvent>? _clientIndexSubscription;
  StreamSubscription<ConnectionStatus>? _connectionStatusSubscription;
  bool _isActiveConversationSyncing = false;
  ConnectionStatus _connectionStatus = ConnectionStatus.idle;
  String _searchQuery = '';
  String? _searchNotice;
  String? _chatNotice;
  final Map<String, String> _drafts = {};
  List<_Conversation> _chatConversations = const [];
  List<_Conversation> _searchConversations = const [];
  final Map<_RailTab, List<_Conversation>> _remoteConversations = {};
  final Map<_RailTab, String> _remoteNotices = {};
  final Map<int, int> _directRoomIds = {};
  final Map<String, List<LocalChatMessage>> _storedMessages = {};
  final Map<int, LocalChatMessage> _recentMessagesByPeer = {};
  final Map<int, LocalChatPeerProfile> _peerProfiles = {};
  Set<int>? _validChatPeerIds;

  @override
  void initState() {
    super.initState();
    _incomingMessageSubscription = ref
        .read(imSessionManagerProvider)
        .messageStream
        .listen(_handleIncomingSocketMessage);
    _clientIndexSubscription = ref
        .read(imSessionManagerProvider)
        .clientIndexStream
        .listen(_handleClientIndexEvent);
    _connectionStatusSubscription = ref
        .read(imSessionManagerProvider)
        .statusStream
        .listen((status) {
          if (mounted) {
            setState(() => _connectionStatus = status);
          }
        });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncImSocketSession();
      unawaited(_loadRecentConversationPreviews());
      unawaited(_loadChatConversations());
      _showAccountHistoryOnOpen();
    });
  }

  @override
  void didUpdateWidget(covariant _HomeScreenMainWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appAccountSession?.certificate !=
        widget.appAccountSession?.certificate) {
      _resetAccountScopedState();
      _syncImSocketSession();
      unawaited(_loadRecentConversationPreviews());
      unawaited(_loadChatConversations());
      if (_selectedTab != _RailTab.chats) {
        unawaited(_loadRemoteUsersForTab(_selectedTab));
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _activeConversationSyncTimer?.cancel();
    unawaited(_incomingMessageSubscription?.cancel());
    unawaited(_clientIndexSubscription?.cancel());
    unawaited(_connectionStatusSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSearching = _searchQuery.trim().isNotEmpty;
    final conversations = _withRecentMessagePreviews(
      isSearching
          ? _searchConversations
          : _conversationsForTab(l10n, _selectedTab),
    );
    final safeSelectedIndex = conversations.isEmpty
        ? 0
        : _selectedConversationIndex.clamp(0, conversations.length - 1);
    final selectedConversation = conversations.isEmpty
        ? null
        : conversations[safeSelectedIndex];
    final storageKey = selectedConversation == null
        ? null
        : _storageKeyFor(selectedConversation);
    final draftKey = storageKey == null ? null : 'draft:$storageKey';
    final messages = selectedConversation == null
        ? const <_ChatMessage>[]
        : _messagesForConversation(selectedConversation);

    return Container(
      color: Colors.white,
      child: Row(
        children: [
          _LeftSection(
            operatorName: widget.operatorName,
            appAccountName: widget.appAccountName,
            appAccountOnline: widget.appAccountOnline,
            appAccountBusy: widget.appAccountBusy,
            appAccountAvatarUrl: widget.appAccountAvatarUrl,
            selectedTab: _selectedTab,
            selectedConversationIndex: safeSelectedIndex,
            conversations: conversations,
            isConversationLoading: isSearching
                ? _isSearchLoading
                : _isConversationLoading,
            emptyMessage: _emptyMessageFor(l10n, isSearching: isSearching),
            searchQuery: _searchQuery,
            onTabSelected: _selectTab,
            onConversationSelected: (index) {
              setState(() => _selectedConversationIndex = index);
              _activateConversation(conversations[index]);
            },
            onSearchChanged: _onSearchChanged,
            onAppAccountTap: widget.onAppAccountTap,
            onSettingsTap: widget.onSettingsTap,
            l10n: l10n,
          ),
          Expanded(
            child: _ChatSection(
              conversation: selectedConversation,
              appAccountSession: widget.appAccountSession,
              connectionStatus: _connectionStatus,
              messages: messages,
              draft: draftKey == null ? '' : _drafts[draftKey] ?? '',
              l10n: l10n,
              emptyMessage: widget.appAccountSession == null
                  ? l10n.workspaceUsersLoginRequired
                  : l10n.selectConversationFirst,
              onDraftChanged: (value) {
                if (draftKey != null) {
                  _drafts[draftKey] = value;
                }
              },
              onSend: selectedConversation == null
                  ? null
                  : (text) => _sendLocalMessage(selectedConversation, text),
              onSendEmojiGame: selectedConversation == null
                  ? null
                  : (game) => _sendEmojiGameMessage(selectedConversation, game),
              onSendMedia: selectedConversation == null
                  ? null
                  : (media) => _sendMediaMessage(selectedConversation, media),
              onSendVoice: selectedConversation == null
                  ? null
                  : (voice) => _sendVoiceMessage(selectedConversation, voice),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTab(_RailTab tab) async {
    if (tab == _selectedTab &&
        !_isConversationLoading &&
        (tab == _RailTab.chats
            ? _chatConversations.isNotEmpty
            : (_remoteConversations[tab]?.isNotEmpty ?? false))) {
      return;
    }

    setState(() {
      _selectedTab = tab;
      _selectedConversationIndex = 0;
    });

    if (tab == _RailTab.chats) {
      unawaited(_loadChatConversations());
      return;
    }

    await _loadRemoteUsersForTab(tab);
  }

  Future<void> _loadRemoteUsersForTab(_RailTab tab) async {
    if (tab == _RailTab.chats) {
      return;
    }

    final requestId = ++_loadRequestId;
    setState(() {
      _isConversationLoading = true;
      _remoteNotices.remove(tab);
      _remoteConversations[tab] = const [];
    });

    final l10n = AppLocalizations.of(context);
    final session = widget.appAccountSession;
    final requestLang = _requestLangOf(context);
    if (session == null) {
      setState(() {
        _isConversationLoading = false;
        _remoteNotices[tab] = l10n.workspaceUsersLoginRequired;
      });
      return;
    }

    try {
      final deviceId = await DesktopDeviceId(
        secureStore: ref.read(secureStoreProvider),
      ).getOrCreate();
      final userApi = ref.read(recommendedUserApiProvider);
      final users = await userApi.fetchUsersFromDynamicPage(
        certificate: session.certificate,
        deviceId: deviceId,
        lang: requestLang,
        onlyOnline: tab == _RailTab.communities,
      );
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      unawaited(_persistPeerProfiles(users));
      final conversations = _recommendedConversationsForTab(l10n, tab, users);
      setState(() {
        _remoteConversations[tab] = conversations;
        _isConversationLoading = false;
        if (conversations.isEmpty) {
          _remoteNotices[tab] = l10n.workspaceUsersEmpty;
        }
      });
      if (conversations.isNotEmpty) {
        _activateConversation(conversations.first);
      }
    } catch (_) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _remoteConversations[tab] = const [];
        _remoteNotices[tab] = l10n.workspaceUsersLoadFailed;
        _isConversationLoading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchQuery = '';
        _searchConversations = const [];
        _searchNotice = null;
        _isSearchLoading = false;
        _selectedConversationIndex = 0;
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isSearchLoading = true;
      _searchNotice = null;
      _selectedConversationIndex = 0;
    });
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _searchGlobalUsers(query),
    );
  }

  Future<void> _searchGlobalUsers(String query) async {
    final requestId = ++_searchRequestId;
    final l10n = AppLocalizations.of(context);
    final session = widget.appAccountSession;
    final requestLang = _requestLangOf(context);
    if (session == null) {
      if (!mounted || requestId != _searchRequestId) {
        return;
      }
      setState(() {
        _searchConversations = const [];
        _searchNotice = l10n.workspaceUsersLoginRequired;
        _isSearchLoading = false;
      });
      return;
    }

    try {
      final deviceId = await DesktopDeviceId(
        secureStore: ref.read(secureStoreProvider),
      ).getOrCreate();
      final users = await ref
          .read(recommendedUserApiProvider)
          .searchGlobalUsers(
            certificate: session.certificate,
            deviceId: deviceId,
            lang: requestLang,
            nickName: query,
          );
      if (!mounted ||
          requestId != _searchRequestId ||
          query != _searchQuery.trim()) {
        return;
      }
      unawaited(_persistPeerProfiles(users));
      final conversations = users
          .map(
            (user) =>
                _ConversationData.fromRecommendedUser(l10n, user, _selectedTab),
          )
          .toList();
      setState(() {
        _searchConversations = conversations;
        _isSearchLoading = false;
        _searchNotice = conversations.isEmpty ? l10n.workspaceUsersEmpty : null;
      });
      if (conversations.isNotEmpty) {
        _activateConversation(conversations.first);
      }
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) {
        return;
      }
      setState(() {
        _searchConversations = const [];
        _searchNotice = l10n.workspaceUsersLoadFailed;
        _isSearchLoading = false;
      });
    }
  }

  List<_Conversation> _conversationsForTab(
    AppLocalizations l10n,
    _RailTab tab,
  ) {
    return switch (tab) {
      _RailTab.chats => _chatConversationsWithLocalFallback(),
      _RailTab.updates => _remoteConversations[tab] ?? const [],
      _RailTab.communities => _remoteConversations[tab] ?? const [],
      _RailTab.calls => _remoteConversations[tab] ?? const [],
    };
  }

  String _emptyMessageFor(AppLocalizations l10n, {required bool isSearching}) {
    if (isSearching) {
      return _searchNotice ?? l10n.workspaceUsersEmpty;
    }
    if (_selectedTab == _RailTab.chats && widget.appAccountSession == null) {
      return l10n.workspaceUsersLoginRequired;
    }
    if (_selectedTab == _RailTab.chats) {
      return _chatNotice ?? l10n.workspaceUsersEmpty;
    }
    return _remoteNotices[_selectedTab] ?? l10n.workspaceUsersEmpty;
  }

  List<_Conversation> _withRecentMessagePreviews(
    List<_Conversation> conversations,
  ) {
    return conversations.map((conversation) {
      final peerUserId = conversation.targetUserId;
      if (peerUserId == null || peerUserId <= 0) {
        return conversation;
      }
      final latest = _recentMessagesByPeer[peerUserId];
      if (latest == null) {
        return conversation;
      }
      return conversation.copyWith(
        message: _conversationPreviewText(latest.text),
        time: _formatConversationTime(latest.createdAt),
        delivered:
            latest.direction == ChatMessageDirection.outgoing &&
            (latest.sendStatus == ChatMessageSendStatus.sent ||
                latest.sendStatus == ChatMessageSendStatus.read),
        deliveredRead:
            latest.direction == ChatMessageDirection.outgoing &&
            latest.sendStatus == ChatMessageSendStatus.read,
        unread: latest.direction == ChatMessageDirection.incoming
            ? conversation.unread
            : 0,
      );
    }).toList();
  }

  List<_Conversation> _recommendedConversationsForTab(
    AppLocalizations l10n,
    _RailTab tab,
    List<RecommendedUser> users,
  ) {
    final sorted = [...users];
    if (tab == _RailTab.communities) {
      sorted
        ..retainWhere((user) => user.isOnline)
        ..sort((left, right) => right.id.compareTo(left.id));
    } else if (tab == _RailTab.calls) {
      sorted.sort((left, right) {
        final fansCompare = right.fans.compareTo(left.fans);
        return fansCompare == 0 ? right.id.compareTo(left.id) : fansCompare;
      });
    }

    return sorted
        .take(20)
        .map((user) => _ConversationData.fromRecommendedUser(l10n, user, tab))
        .toList();
  }

  List<_Conversation> _chatConversationsWithLocalFallback() {
    final localConversations = _localRecentConversations();
    if (_chatConversations.isEmpty) {
      return _dedupeConversationsByPeer(localConversations);
    }
    final remotePeerIds = _chatConversations
        .map((conversation) => conversation.targetUserId)
        .whereType<int>()
        .toSet();
    return _dedupeConversationsByPeer([
      ..._chatConversations,
      ...localConversations.where(
        (conversation) => !remotePeerIds.contains(conversation.targetUserId),
      ),
    ]);
  }

  List<_Conversation> _dedupeConversationsByPeer(
    List<_Conversation> conversations,
  ) {
    final byPeer = <int, _Conversation>{};
    final withoutPeer = <_Conversation>[];
    for (final conversation in conversations) {
      final peerUserId = conversation.targetUserId;
      if (peerUserId == null || peerUserId <= 0) {
        withoutPeer.add(conversation);
        continue;
      }
      final current = byPeer[peerUserId];
      if (current == null ||
          _conversationSortTime(
            conversation,
          ).isAfter(_conversationSortTime(current)) ||
          (_conversationSortTime(conversation) ==
                  _conversationSortTime(current) &&
              _conversationHasRealPreview(conversation) &&
              !_conversationHasRealPreview(current))) {
        byPeer[peerUserId] = conversation;
      }
    }
    final deduped = [...byPeer.values, ...withoutPeer]
      ..sort((left, right) {
        final timeCompare = _conversationSortTime(
          right,
        ).compareTo(_conversationSortTime(left));
        if (timeCompare != 0) {
          return timeCompare;
        }
        return right.unread.compareTo(left.unread);
      });
    return deduped;
  }

  DateTime _conversationSortTime(_Conversation conversation) {
    final peerUserId = conversation.targetUserId;
    if (peerUserId != null) {
      final latest = _recentMessagesByPeer[peerUserId];
      if (latest != null) {
        return latest.createdAt;
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _conversationHasRealPreview(_Conversation conversation) {
    final message = conversation.message.trim();
    return message.isNotEmpty &&
        message != AppLocalizations.of(context).workspaceUserOnline &&
        message != AppLocalizations.of(context).appAccountStatusOffline;
  }

  List<_Conversation> _localRecentConversations() {
    final latestMessages = _recentMessagesByPeer.values.toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return latestMessages
        .where((message) {
          final validPeerIds = _validChatPeerIds;
          return validPeerIds == null ||
              validPeerIds.contains(message.peerUserId);
        })
        .map((message) {
          final peerUserId = message.peerUserId;
          final profile = _peerProfiles[peerUserId];
          final profileName = profile?.displayName.trim() ?? '';
          final label = profileName.isEmpty
              ? 'Beepian$peerUserId'
              : profileName;
          return _Conversation(
            name: label,
            message: _conversationPreviewText(message.text),
            time: _formatConversationTime(message.createdAt),
            color: _ConversationData.avatarColorFor(peerUserId),
            emoji: label.characters.first.toUpperCase(),
            avatarUrl: profile?.avatarUrl,
            targetUserId: peerUserId,
            roomId: message.roomId,
            isOnline: false,
            delivered:
                message.direction == ChatMessageDirection.outgoing &&
                (message.sendStatus == ChatMessageSendStatus.sent ||
                    message.sendStatus == ChatMessageSendStatus.read),
            deliveredRead:
                message.direction == ChatMessageDirection.outgoing &&
                message.sendStatus == ChatMessageSendStatus.read,
            unread: message.direction == ChatMessageDirection.incoming ? 1 : 0,
            messages: const [],
          );
        })
        .toList();
  }

  String _requestLangOf(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'vi') {
      return 'vi_VN';
    }
    if (locale.languageCode == 'zh') {
      return 'zh_HK';
    }
    return 'en_US';
  }

  List<_ChatMessage> _messagesForConversation(_Conversation conversation) {
    final stored = _storedMessagesForConversation(conversation);
    if (stored.isEmpty) {
      return conversation.targetUserId == null
          ? conversation.messages
          : const <_ChatMessage>[];
    }
    return [
      if (conversation.targetUserId == null) ...conversation.messages,
      ...stored.map(_ChatMessage.fromLocal),
    ];
  }

  List<LocalChatMessage> _storedMessagesForConversation(
    _Conversation conversation,
  ) {
    return _deduplicateLocalMessages(
      _storedMessages[_storageKeyFor(conversation)] ?? const [],
    )..sort((left, right) => left.createdAt.compareTo(right.createdAt));
  }

  List<LocalChatMessage> _deduplicateLocalMessages(
    List<LocalChatMessage> messages,
  ) {
    final deduped = <LocalChatMessage>[];
    for (final message in messages) {
      final index = deduped.indexWhere(
        (current) =>
            current.localId == message.localId ||
            (message.clientMessageId != null &&
                current.clientMessageId == message.clientMessageId) ||
            (message.serverMessageId != null &&
                current.serverMessageId == message.serverMessageId),
      );
      if (index >= 0) {
        deduped[index] = message;
      } else {
        deduped.add(message);
      }
    }
    return deduped;
  }

  void _activateConversation(_Conversation conversation) {
    _activeConversationSyncTimer?.cancel();
    unawaited(_loadStoredMessages(conversation));
    if (conversation.targetUserId == null || conversation.targetUserId! <= 0) {
      return;
    }
    unawaited(_syncActiveConversation());
    _activeConversationSyncTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_syncActiveConversation()),
    );
  }

  Future<void> _syncActiveConversation() async {
    if (_isActiveConversationSyncing || !mounted) {
      return;
    }
    final conversation = _selectedConversation();
    if (conversation == null ||
        conversation.targetUserId == null ||
        conversation.targetUserId! <= 0) {
      return;
    }
    _isActiveConversationSyncing = true;
    try {
      await _syncRemoteMessages(
        conversation,
        cachedMessages: _storedMessagesForConversation(conversation),
      );
    } finally {
      _isActiveConversationSyncing = false;
    }
  }

  _Conversation? _selectedConversation() {
    final l10n = AppLocalizations.of(context);
    final conversations = _searchQuery.trim().isNotEmpty
        ? _searchConversations
        : _conversationsForTab(l10n, _selectedTab);
    if (conversations.isEmpty) {
      return null;
    }
    return conversations[_selectedConversationIndex.clamp(
      0,
      conversations.length - 1,
    )];
  }

  int? _roomIdFor(_Conversation conversation) {
    final peerUserId = conversation.targetUserId;
    if (peerUserId != null && _directRoomIds[peerUserId] != null) {
      return _directRoomIds[peerUserId];
    }
    return conversation.roomId;
  }

  Future<int?> _ensureConversationRoomId(_Conversation conversation) async {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    final existingRoomId = _roomIdFor(conversation);
    if (existingRoomId != null && existingRoomId > 0) {
      return existingRoomId;
    }
    if (session == null || peerUserId == null || peerUserId <= 0) {
      return null;
    }
    final requestLang = _requestLangOf(context);

    final deviceId = await DesktopDeviceId(
      secureStore: ref.read(secureStoreProvider),
    ).getOrCreate();
    final room = await ref
        .read(directChatApiProvider)
        .startDirectChat(
          peerUserId: peerUserId,
          certificate: session.certificate,
          deviceId: deviceId,
          lang: requestLang,
        );
    _directRoomIds[peerUserId] = room.roomId;
    debugPrint(
      '[CHAT_OPS][LOCAL][ROOM] sender=${session.id} peer=$peerUserId '
      'room=${room.roomId}',
    );
    ref.read(imSessionManagerProvider).refreshChatRooms();
    return room.roomId;
  }

  Future<void> _loadStoredMessages(_Conversation conversation) async {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    if (session == null || peerUserId == null || peerUserId <= 0) {
      return;
    }
    final store = await ref.read(localChatMessageStoreProvider.future);
    final messages = await store.loadConversation(
      appUserId: session.id,
      peerUserId: peerUserId,
    );
    debugPrint(
      '[CHAT_OPS][LOCAL][LOAD] sender=${session.id} peer=$peerUserId '
      'records=${messages.length}',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _storedMessages[_storageKeyFor(conversation)] = messages;
      for (final message in messages) {
        _rememberRecentMessageInMemory(message);
      }
    });
    unawaited(_syncRemoteMessages(conversation, cachedMessages: messages));
  }

  Future<void> _sendLocalMessage(
    _Conversation conversation,
    String text,
  ) async {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    final messageText = _messageTextForSend(text);
    if (session == null ||
        peerUserId == null ||
        peerUserId <= 0 ||
        messageText.isEmpty) {
      return;
    }
    final now = DateTime.now();
    final clientMessageId = now.microsecondsSinceEpoch.toString();
    final initialConversationKey = directConversationKey(
      appUserId: session.id,
      peerUserId: peerUserId,
    );
    final localMessage = LocalChatMessage(
      localId: 'local_$clientMessageId',
      appUserId: session.id,
      peerUserId: peerUserId,
      roomId: _roomIdFor(conversation),
      conversationKey: initialConversationKey,
      direction: ChatMessageDirection.outgoing,
      text: messageText,
      createdAt: now,
      updatedAt: now,
      sendStatus: ChatMessageSendStatus.pending,
      clientMessageId: clientMessageId,
    );

    final store = await ref.read(localChatMessageStoreProvider.future);
    await store.upsert(localMessage);
    debugPrint(
      '[CHAT_OPS][LOCAL][UPSERT] phase=send_pending '
      'sender=${session.id} peer=$peerUserId room=${localMessage.roomId} '
      'local=${localMessage.localId}',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      final key = _storageKeyFor(conversation);
      final current = [...?_storedMessages[key]];
      current.add(localMessage);
      _storedMessages[key] = current;
      _rememberRecentMessageInMemory(localMessage);
    });

    try {
      debugPrint(
        '[CHAT_OPS][VOICE][SEND_STAGE] room_start '
        'sender=${session.id} peer=$peerUserId local=${localMessage.localId}',
      );
      final roomId = await _ensureConversationRoomId(conversation);
      if (roomId == null || roomId <= 0) {
        throw const DirectChatException('Unable to open chat.');
      }
      final updated = localMessage.copyWith(
        roomId: roomId,
        sendStatus: ChatMessageSendStatus.pending,
        updatedAt: DateTime.now(),
      );
      await store.upsert(updated);
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=send_room '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'local=${updated.localId}',
      );
      _replaceStoredMessage(conversation, updated);
      ref.read(imSessionManagerProvider).refreshChatRooms();

      final ack = await ref
          .read(imSessionManagerProvider)
          .sendTextMessage(
            roomId: roomId,
            text: messageText,
            clientMessageId: clientMessageId,
          );
      final completed = updated.copyWith(
        sendStatus: ack.success
            ? ChatMessageSendStatus.sent
            : ChatMessageSendStatus.failed,
        serverMessageId: ack.serverMessageId?.toString(),
        errorMessage: ack.success
            ? null
            : (ack.message == null || ack.message!.trim().isEmpty
                  ? 'Message send failed'
                  : ack.message),
        updatedAt: DateTime.now(),
      );
      await store.upsert(completed);
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=send_completed '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'local=${completed.localId} server=${completed.serverMessageId} '
        'status=${completed.sendStatus.name}',
      );
      _replaceStoredMessage(conversation, completed);
      unawaited(
        _syncRemoteMessages(
          conversation,
          cachedMessages: [completed],
          roomIdOverride: roomId,
        ),
      );
    } catch (error) {
      final failed = localMessage.copyWith(
        sendStatus: ChatMessageSendStatus.failed,
        errorMessage: error.toString(),
        updatedAt: DateTime.now(),
      );
      await store.upsert(failed);
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=send_failed '
        'sender=${session.id} peer=$peerUserId local=${failed.localId} '
        'error=$error',
      );
      _replaceStoredMessage(conversation, failed);
    }
  }

  Future<void> _sendEmojiGameMessage(
    _Conversation conversation,
    _EmojiGameSelection game,
  ) async {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    if (session == null || peerUserId == null || peerUserId <= 0) {
      return;
    }
    final now = DateTime.now();
    final clientMessageId = now.microsecondsSinceEpoch.toString();
    final initialConversationKey = directConversationKey(
      appUserId: session.id,
      peerUserId: peerUserId,
    );
    final localMessage = LocalChatMessage(
      localId: 'local_$clientMessageId',
      appUserId: session.id,
      peerUserId: peerUserId,
      roomId: _roomIdFor(conversation),
      conversationKey: initialConversationKey,
      direction: ChatMessageDirection.outgoing,
      text: game.previewText,
      createdAt: now,
      updatedAt: now,
      sendStatus: ChatMessageSendStatus.pending,
      clientMessageId: clientMessageId,
    );

    final store = await ref.read(localChatMessageStoreProvider.future);
    await store.upsert(localMessage);
    debugPrint(
      '[CHAT_OPS][LOCAL][UPSERT] phase=emoji_game_pending '
      'sender=${session.id} peer=$peerUserId room=${localMessage.roomId} '
      'local=${localMessage.localId} type=${game.type} value=${game.value}',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      final key = _storageKeyFor(conversation);
      final current = [...?_storedMessages[key]];
      current.add(localMessage);
      _storedMessages[key] = current;
      _rememberRecentMessageInMemory(localMessage);
    });

    try {
      final roomId = await _ensureConversationRoomId(conversation);
      if (roomId == null || roomId <= 0) {
        throw const DirectChatException('Unable to open chat.');
      }
      final updated = localMessage.copyWith(
        roomId: roomId,
        sendStatus: ChatMessageSendStatus.pending,
        updatedAt: DateTime.now(),
      );
      await store.upsert(updated);
      _replaceStoredMessage(conversation, updated);
      ref.read(imSessionManagerProvider).refreshChatRooms();

      final ack = await ref
          .read(imSessionManagerProvider)
          .sendEmojiGameMessage(
            roomId: roomId,
            type: game.type,
            value: game.value,
            clientMessageId: clientMessageId,
          );
      final completed = updated.copyWith(
        sendStatus: ack.success
            ? ChatMessageSendStatus.sent
            : ChatMessageSendStatus.failed,
        serverMessageId: ack.serverMessageId?.toString(),
        errorMessage: ack.success
            ? null
            : (ack.message == null || ack.message!.trim().isEmpty
                  ? 'Emoji send failed'
                  : ack.message),
        updatedAt: DateTime.now(),
      );
      await store.upsert(completed);
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=emoji_game_completed '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'local=${completed.localId} server=${completed.serverMessageId} '
        'status=${completed.sendStatus.name}',
      );
      _replaceStoredMessage(conversation, completed);
      unawaited(
        _syncRemoteMessages(
          conversation,
          cachedMessages: [completed],
          roomIdOverride: roomId,
        ),
      );
    } catch (error) {
      final failed = localMessage.copyWith(
        sendStatus: ChatMessageSendStatus.failed,
        errorMessage: error.toString(),
        updatedAt: DateTime.now(),
      );
      await store.upsert(failed);
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=emoji_game_failed '
        'sender=${session.id} peer=$peerUserId local=${failed.localId} '
        'error=$error',
      );
      _replaceStoredMessage(conversation, failed);
    }
  }

  Future<bool> _sendMediaMessage(
    _Conversation conversation,
    _SelectedChatMedia media,
  ) async {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    if (session == null || peerUserId == null || peerUserId <= 0) {
      return false;
    }
    final now = DateTime.now();
    final clientMessageId = now.microsecondsSinceEpoch.toString();
    final initialConversationKey = directConversationKey(
      appUserId: session.id,
      peerUserId: peerUserId,
    );
    final requestLang = _requestLangOf(context);
    final previewText = media.isVideo ? '[Video]' : '[Photo]';
    final localImageDimensions = media.isVideo
        ? null
        : await _readImageDimensions(media.path);
    final localMessage = LocalChatMessage(
      localId: 'local_$clientMessageId',
      appUserId: session.id,
      peerUserId: peerUserId,
      roomId: _roomIdFor(conversation),
      conversationKey: initialConversationKey,
      direction: ChatMessageDirection.outgoing,
      text: previewText,
      createdAt: now,
      updatedAt: now,
      sendStatus: ChatMessageSendStatus.pending,
      clientMessageId: clientMessageId,
      sendType: 2,
      msgData: jsonEncode([
        {
          'localUrl': media.path,
          'mediaType': media.isVideo ? 3 : 2,
          if (localImageDimensions != null) 'width': localImageDimensions.width,
          if (localImageDimensions != null)
            'height': localImageDimensions.height,
        },
      ]),
      localMediaPath: media.path,
    );

    final store = await ref.read(localChatMessageStoreProvider.future);
    await store.upsert(localMessage);
    if (!mounted) {
      return false;
    }
    setState(() {
      final key = _storageKeyFor(conversation);
      final current = [...?_storedMessages[key]];
      current.add(localMessage);
      _storedMessages[key] = current;
      _rememberRecentMessageInMemory(localMessage);
    });

    try {
      final roomId = await _ensureConversationRoomId(conversation);
      if (roomId == null || roomId <= 0) {
        throw const DirectChatException('Unable to open chat.');
      }
      final updated = localMessage.copyWith(
        roomId: roomId,
        sendStatus: ChatMessageSendStatus.pending,
        updatedAt: DateTime.now(),
      );
      await store.upsert(updated);
      _replaceStoredMessage(conversation, updated);
      ref.read(imSessionManagerProvider).refreshChatRooms();

      final uploadApi = ref.read(chatMediaUploadApiProvider);
      final mediaData = media.isVideo
          ? await _uploadVideoForChat(
              media,
              uploadApi: uploadApi,
              certificate: session.certificate,
              deviceId: session.deviceId,
              lang: requestLang,
            )
          : await _uploadImageForChat(
              media,
              uploadApi: uploadApi,
              certificate: session.certificate,
              deviceId: session.deviceId,
              lang: requestLang,
            );

      final ack = await ref
          .read(imSessionManagerProvider)
          .sendMediaMessage(
            roomId: roomId,
            msgData: [mediaData],
            clientMessageId: clientMessageId,
          );
      final completed = updated.copyWith(
        sendStatus: ack.success
            ? ChatMessageSendStatus.sent
            : ChatMessageSendStatus.failed,
        serverMessageId: ack.serverMessageId?.toString(),
        errorMessage: ack.success
            ? null
            : (ack.message == null || ack.message!.trim().isEmpty
                  ? 'Media send failed'
                  : ack.message),
        msgData: jsonEncode(mediaData),
        localMediaPath: media.path,
        updatedAt: DateTime.now(),
      );
      await store.upsert(completed);
      _replaceStoredMessage(conversation, completed);
      unawaited(
        _syncRemoteMessages(
          conversation,
          cachedMessages: [completed],
          roomIdOverride: roomId,
        ),
      );
      return ack.success;
    } catch (error) {
      final failed = localMessage.copyWith(
        sendStatus: ChatMessageSendStatus.failed,
        errorMessage: error.toString(),
        updatedAt: DateTime.now(),
      );
      await store.upsert(failed);
      _replaceStoredMessage(conversation, failed);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      }
      return false;
    }
  }

  Future<bool> _sendVoiceMessage(
    _Conversation conversation,
    _SelectedVoiceRecording voice,
  ) async {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    if (session == null || peerUserId == null || peerUserId <= 0) {
      return false;
    }
    final now = DateTime.now();
    final clientMessageId = now.microsecondsSinceEpoch.toString();
    final initialConversationKey = directConversationKey(
      appUserId: session.id,
      peerUserId: peerUserId,
    );
    final requestLang = _requestLangOf(context);
    final durationSeconds = max(1, voice.durationSeconds);
    final localMessage = LocalChatMessage(
      localId: 'local_$clientMessageId',
      appUserId: session.id,
      peerUserId: peerUserId,
      roomId: _roomIdFor(conversation),
      conversationKey: initialConversationKey,
      direction: ChatMessageDirection.outgoing,
      text: '[Voice]',
      createdAt: now,
      updatedAt: now,
      sendStatus: ChatMessageSendStatus.pending,
      clientMessageId: clientMessageId,
      sendType: 2,
      msgData: jsonEncode([
        {
          'localUrl': voice.path,
          'mediaCover': '',
          'media': '',
          'mediaType': 4,
          'duration': durationSeconds,
        },
      ]),
      localMediaPath: voice.path,
    );

    final store = await ref.read(localChatMessageStoreProvider.future);
    await store.upsert(localMessage);
    if (!mounted) {
      return false;
    }
    setState(() {
      final key = _storageKeyFor(conversation);
      final current = [...?_storedMessages[key]];
      current.add(localMessage);
      _storedMessages[key] = current;
      _rememberRecentMessageInMemory(localMessage);
    });

    try {
      final roomId = await _ensureConversationRoomId(conversation);
      if (roomId == null || roomId <= 0) {
        throw const DirectChatException('Unable to open chat.');
      }
      final updated = localMessage.copyWith(
        roomId: roomId,
        sendStatus: ChatMessageSendStatus.pending,
        updatedAt: DateTime.now(),
      );
      await store.upsert(updated);
      _replaceStoredMessage(conversation, updated);
      ref.read(imSessionManagerProvider).refreshChatRooms();

      final uploadApi = ref.read(chatMediaUploadApiProvider);
      debugPrint(
        '[CHAT_OPS][VOICE][SEND_STAGE] upload_start '
        'room=$roomId path=${voice.path} size=${voice.fileSizeBytes}',
      );
      final voiceUrl = await uploadApi
          .uploadTempVoice(
            path: voice.path,
            certificate: session.certificate,
            deviceId: session.deviceId,
            lang: requestLang,
          )
          .timeout(
            const Duration(seconds: 18),
            onTimeout: () =>
                throw const ChatMediaUploadException('Voice upload timeout.'),
          );
      debugPrint('[CHAT_OPS][VOICE][SEND_STAGE] upload_done url=$voiceUrl');
      final voiceData = {
        'mediaCover': '',
        'media': voiceUrl,
        'mediaType': 4,
        'duration': durationSeconds,
      };
      debugPrint('[CHAT_OPS][VOICE][SEND_STAGE] socket_start room=$roomId');
      final ack = await ref
          .read(imSessionManagerProvider)
          .sendMediaMessage(
            roomId: roomId,
            msgData: [voiceData],
            clientMessageId: clientMessageId,
          );
      debugPrint(
        '[CHAT_OPS][VOICE][SEND_STAGE] socket_done success=${ack.success} '
        'message=${ack.message}',
      );
      final completed = updated.copyWith(
        sendStatus: ack.success
            ? ChatMessageSendStatus.sent
            : ChatMessageSendStatus.failed,
        serverMessageId: ack.serverMessageId?.toString(),
        errorMessage: ack.success
            ? null
            : (ack.message == null || ack.message!.trim().isEmpty
                  ? 'Voice send failed'
                  : ack.message),
        msgData: jsonEncode(voiceData),
        localMediaPath: voice.path,
        updatedAt: DateTime.now(),
      );
      await store.upsert(completed);
      _replaceStoredMessage(conversation, completed);
      unawaited(
        _syncRemoteMessages(
          conversation,
          cachedMessages: [completed],
          roomIdOverride: roomId,
        ),
      );
      return ack.success;
    } catch (error) {
      final failed = localMessage.copyWith(
        sendStatus: ChatMessageSendStatus.failed,
        errorMessage: error.toString(),
        updatedAt: DateTime.now(),
      );
      await store.upsert(failed);
      _replaceStoredMessage(conversation, failed);
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(error.toString()),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
      }
      return false;
    }
  }

  Future<Map<String, dynamic>> _uploadImageForChat(
    _SelectedChatMedia media, {
    required ChatMediaUploadApi uploadApi,
    required String certificate,
    required String deviceId,
    required String lang,
  }) async {
    final dimensions = await _readImageDimensions(media.path);
    final imageUrl = await uploadApi.uploadTempImage(
      path: media.path,
      certificate: certificate,
      deviceId: deviceId,
      lang: lang,
    );
    return {
      'mediaCover': imageUrl,
      'media': imageUrl,
      'mediaType': 2,
      if (dimensions != null) 'width': dimensions.width,
      if (dimensions != null) 'height': dimensions.height,
    };
  }

  Future<Map<String, dynamic>> _uploadVideoForChat(
    _SelectedChatMedia media, {
    required ChatMediaUploadApi uploadApi,
    required String certificate,
    required String deviceId,
    required String lang,
  }) async {
    final coverPath = await _createVideoCover(media.path);
    if (coverPath == null || coverPath.trim().isEmpty) {
      throw const ChatMediaUploadException('Video cover generation failed.');
    }
    try {
      final dimensions = await _readImageDimensions(coverPath);
      final coverUrl = await uploadApi.uploadTempImage(
        path: coverPath,
        certificate: certificate,
        deviceId: deviceId,
        lang: lang,
      );
      final videoUrl = await uploadApi.uploadTempVideo(
        path: media.path,
        certificate: certificate,
        deviceId: deviceId,
        lang: lang,
      );
      return {
        'mediaCover': coverUrl,
        'media': videoUrl,
        'mediaType': 3,
        if (dimensions != null) 'width': dimensions.width,
        if (dimensions != null) 'height': dimensions.height,
      };
    } finally {
      final coverFile = File(coverPath);
      unawaited(coverFile.delete().catchError((_) => coverFile));
    }
  }

  String _messageTextForSend(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (normalized.trim().isEmpty) {
      return '';
    }
    return normalized.replaceAll(RegExp(r'^\n+|\n+$'), '');
  }

  void _replaceStoredMessage(
    _Conversation conversation,
    LocalChatMessage updated,
  ) {
    if (!mounted) {
      return;
    }
    setState(() {
      final key = _storageKeyFor(conversation);
      final current = [...?_storedMessages[key]];
      final index = current.indexWhere(
        (message) => message.localId == updated.localId,
      );
      if (index >= 0) {
        current[index] = updated;
      } else {
        current.add(updated);
      }
      _storedMessages[key] = current;
      _rememberRecentMessageInMemory(updated);
    });
  }

  Future<void> _handleIncomingSocketMessage(
    Map<String, dynamic> payload,
  ) async {
    final session = widget.appAccountSession;
    if (session == null) {
      return;
    }

    final socketMessage = _IncomingSocketMessage.fromJson(payload);
    await _persistIncomingSocketMessage(socketMessage, session);
  }

  Future<void> _handleClientIndexEvent(ImClientIndexEvent event) async {
    final session = widget.appAccountSession;
    final readMsgIndex = event.readMsgIndex;
    if (session == null ||
        event.userId == session.id ||
        readMsgIndex == null ||
        readMsgIndex <= 0) {
      return;
    }
    if (!_isReadReceiptEnabledForRoom(event.roomId)) {
      return;
    }
    final store = await ref.read(localChatMessageStoreProvider.future);
    final updatedMessages = await store.markOutgoingReadByRoom(
      appUserId: session.id,
      roomId: event.roomId,
      readMsgIndex: readMsgIndex,
    );
    if (updatedMessages.isEmpty || !mounted) {
      return;
    }
    setState(() {
      for (final message in updatedMessages) {
        _upsertStoredMessageInMemory(message.conversationKey, message);
        _rememberRecentMessageInMemory(message);
      }
    });
    debugPrint(
      '[CHAT_OPS][LOCAL][READ_INDEX] sender=${session.id} '
      'room=${event.roomId} readMsgIndex=$readMsgIndex '
      'updated=${updatedMessages.length}',
    );
  }

  Future<void> _syncRemoteMessages(
    _Conversation conversation, {
    List<LocalChatMessage> cachedMessages = const [],
    int? roomIdOverride,
  }) async {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    if (session == null || peerUserId == null || peerUserId <= 0) {
      return;
    }

    final roomId =
        roomIdOverride ??
        _roomIdFor(conversation) ??
        cachedMessages
            .map((message) => message.roomId)
            .whereType<int>()
            .where((roomId) => roomId > 0)
            .lastOrNull ??
        await _ensureConversationRoomId(conversation);
    if (roomId == null || roomId <= 0) {
      return;
    }

    final startMsgIndex = cachedMessages
        .map((message) => int.tryParse(message.serverMessageId ?? '') ?? 0)
        .fold<int>(0, (max, value) => value > max ? value : max);
    var ack = const ImSyncRecordAck(success: false);
    for (var attempt = 1; attempt <= 3; attempt++) {
      ack = await ref
          .read(imSessionManagerProvider)
          .syncRecords(startMsgIndex: startMsgIndex, roomId: roomId);
      debugPrint(
        '[CHAT_OPS][LOCAL][SYNC_ATTEMPT] sender=${session.id} '
        'peer=$peerUserId room=$roomId attempt=$attempt '
        'start=$startMsgIndex success=${ack.success} '
        'records=${ack.records.length}',
      );
      final shouldRetry =
          !ack.success || (cachedMessages.isEmpty && ack.records.isEmpty);
      if (!shouldRetry) {
        break;
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
    }
    debugPrint(
      '[CHAT_OPS][LOCAL][SYNC] sender=${session.id} peer=$peerUserId '
      'room=$roomId start=$startMsgIndex success=${ack.success} '
      'records=${ack.records.length}',
    );
    if (!ack.success || ack.records.isEmpty) {
      return;
    }
    for (final record in ack.records) {
      await _persistIncomingSocketMessage(
        _IncomingSocketMessage.fromJson(record),
        session,
        fallbackPeerUserId: peerUserId,
      );
    }
  }

  Future<void> _persistIncomingSocketMessage(
    _IncomingSocketMessage socketMessage,
    AppUserSession session, {
    int? fallbackPeerUserId,
  }) async {
    if (!socketMessage.canDisplay) {
      debugPrint(
        '[CHAT_OPS][LOCAL][SKIP] reason=not_displayable '
        'user=${socketMessage.userId} room=${socketMessage.roomId} '
        'sendType=${socketMessage.sendType}',
      );
      return;
    }
    final socketRoomId = socketMessage.roomId;
    final isOutgoing = socketMessage.userId == session.id;
    final activeConversation = _selectedConversation();
    final peerUserIdFromRoom = socketRoomId == null
        ? null
        : _peerUserIdForRoomId(socketRoomId);
    final peerUserId = isOutgoing
        ? (fallbackPeerUserId ??
              peerUserIdFromRoom ??
              activeConversation?.targetUserId ??
              0)
        : socketMessage.userId;
    if (peerUserId <= 0) {
      debugPrint(
        '[CHAT_OPS][LOCAL][SKIP] reason=peer_missing '
        'sender=${session.id} socketUser=${socketMessage.userId} '
        'room=${socketMessage.roomId} outgoing=$isOutgoing '
        'fallbackPeer=$fallbackPeerUserId activePeer=${activeConversation?.targetUserId}',
      );
      return;
    }
    if (socketRoomId != null && socketRoomId > 0) {
      _directRoomIds[peerUserId] = socketRoomId;
    }
    final now = DateTime.now();
    final createdAt = socketMessage.sendTime == null
        ? now
        : DateTime.fromMillisecondsSinceEpoch(socketMessage.sendTime!);
    final peerKey = directConversationKey(
      appUserId: session.id,
      peerUserId: peerUserId,
    );
    final localMessage = LocalChatMessage(
      localId: isOutgoing && socketMessage.clientMessageId != null
          ? 'local_${socketMessage.clientMessageId}'
          : socketMessage.localId,
      appUserId: session.id,
      peerUserId: peerUserId,
      roomId: socketMessage.roomId,
      conversationKey: peerKey,
      direction: isOutgoing
          ? ChatMessageDirection.outgoing
          : ChatMessageDirection.incoming,
      text: socketMessage.previewText,
      createdAt: createdAt,
      updatedAt: now,
      sendStatus: ChatMessageSendStatus.sent,
      clientMessageId: socketMessage.clientMessageId,
      serverMessageId: socketMessage.id?.toString(),
      sendType: socketMessage.sendType,
      msgData: socketMessage.msgDataJson,
    );

    final store = await ref.read(localChatMessageStoreProvider.future);
    await store.upsert(localMessage);
    debugPrint(
      '[CHAT_OPS][LOCAL][UPSERT] phase=socket '
      'sender=${session.id} peer=$peerUserId room=${localMessage.roomId} '
      'direction=${localMessage.direction.name} local=${localMessage.localId} '
      'server=${localMessage.serverMessageId}',
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _upsertStoredMessageInMemory(peerKey, localMessage);
      _rememberRecentMessageInMemory(localMessage);
    });
    if (!isOutgoing) {
      _reportActiveConversationReadIndex(localMessage);
    }
  }

  void _reportActiveConversationReadIndex(LocalChatMessage message) {
    if (message.direction != ChatMessageDirection.incoming ||
        message.roomId == null ||
        message.roomId! <= 0) {
      return;
    }
    final activeConversation = _selectedConversation();
    if (activeConversation?.targetUserId != message.peerUserId) {
      return;
    }
    final serverId = int.tryParse(message.serverMessageId ?? '') ?? 0;
    if (serverId <= 0) {
      return;
    }
    unawaited(
      ref
          .read(imSessionManagerProvider)
          .syncClientIndex(
            roomId: message.roomId!,
            curMsgIndex: serverId,
            readMsgIndex: serverId,
          ),
    );
  }

  int? _peerUserIdForRoomId(int roomId) {
    for (final entry in _directRoomIds.entries) {
      if (entry.value == roomId) {
        return entry.key;
      }
    }
    return null;
  }

  bool _isReadReceiptEnabledForRoom(int roomId) {
    final l10n = AppLocalizations.of(context);
    final conversations = [
      ..._chatConversations,
      ..._remoteConversations.values.expand((items) => items),
      ..._searchConversations,
      ..._conversationsForTab(l10n, _selectedTab),
    ];
    for (final conversation in conversations) {
      if (conversation.roomId == roomId) {
        return conversation.readReceiptEnabled;
      }
    }
    return true;
  }

  void _upsertStoredMessageInMemory(String key, LocalChatMessage localMessage) {
    final current = [...?_storedMessages[key]];
    final existingIndex = current.indexWhere(
      (message) =>
          message.localId == localMessage.localId ||
          (localMessage.clientMessageId != null &&
              message.clientMessageId == localMessage.clientMessageId) ||
          (localMessage.serverMessageId != null &&
              message.serverMessageId == localMessage.serverMessageId),
    );
    if (existingIndex >= 0) {
      final existing = current[existingIndex];
      current[existingIndex] =
          existing.sendStatus == ChatMessageSendStatus.read &&
              localMessage.sendStatus == ChatMessageSendStatus.sent
          ? existing
          : localMessage;
    } else {
      current.add(localMessage);
    }
    current.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    _storedMessages[key] = current;
  }

  String _storageKeyFor(_Conversation conversation) {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    if (session != null && peerUserId != null && peerUserId > 0) {
      return directConversationKey(
        appUserId: session.id,
        peerUserId: peerUserId,
      );
    }
    return '${_selectedTab.name}:${conversation.name}';
  }

  Future<void> _loadRecentConversationPreviews() async {
    final session = widget.appAccountSession;
    if (session == null) {
      if (mounted) {
        setState(() {
          _recentMessagesByPeer.clear();
          _peerProfiles.clear();
        });
      }
      return;
    }
    final store = await ref.read(localChatMessageStoreProvider.future);
    final profileStore = await ref.read(
      localChatPeerProfileStoreProvider.future,
    );
    final latest = await store.loadLatestByAppUser(appUserId: session.id);
    final profiles = await profileStore.loadByAppUser(appUserId: session.id);
    if (!mounted || widget.appAccountSession?.id != session.id) {
      return;
    }
    setState(() {
      _recentMessagesByPeer
        ..clear()
        ..addAll(latest);
      _peerProfiles
        ..clear()
        ..addAll(profiles);
    });
    final selected = _selectedConversation();
    if (selected != null && selected.targetUserId != null) {
      _activateConversation(selected);
    }
  }

  Future<void> _loadChatConversations() async {
    final requestId = ++_loadRequestId;
    final l10n = AppLocalizations.of(context);
    final session = widget.appAccountSession;
    final requestLang = _requestLangOf(context);
    if (session == null) {
      if (mounted) {
        setState(() {
          _chatConversations = const [];
          _chatNotice = l10n.workspaceUsersLoginRequired;
          if (_selectedTab == _RailTab.chats) {
            _isConversationLoading = false;
          }
        });
      }
      return;
    }

    if (_selectedTab == _RailTab.chats && mounted) {
      setState(() {
        _isConversationLoading = true;
        _chatNotice = null;
      });
    }

    try {
      final deviceId = await DesktopDeviceId(
        secureStore: ref.read(secureStoreProvider),
      ).getOrCreate();
      final records = await ref
          .read(chatConversationApiProvider)
          .fetchConversations(
            certificate: session.certificate,
            deviceId: deviceId,
            lang: requestLang,
          );
      if (!mounted ||
          requestId != _loadRequestId ||
          widget.appAccountSession?.id != session.id) {
        return;
      }
      final userInfos = await ref
          .read(chatConversationApiProvider)
          .fetchUserInfos(
            certificate: session.certificate,
            deviceId: deviceId,
            lang: requestLang,
            userIds: [
              ...records.map((record) => record.peerUserId),
              ..._recentMessagesByPeer.keys,
            ],
          );
      if (!mounted ||
          requestId != _loadRequestId ||
          widget.appAccountSession?.id != session.id) {
        return;
      }
      unawaited(_persistChatConversationProfiles(records));
      final userInfoById = {
        for (final userInfo in userInfos) userInfo.id: userInfo,
      };
      final validPeerIds = userInfoById.keys.toSet();
      final conversations = records
          .where((record) => validPeerIds.contains(record.peerUserId))
          .map((record) => _ConversationData.fromChatConversation(l10n, record))
          .map((conversation) {
            final peerUserId = conversation.targetUserId;
            final userInfo = peerUserId == null
                ? null
                : userInfoById[peerUserId];
            return userInfo == null
                ? conversation
                : conversation.copyWith(
                    name: userInfo.displayName,
                    message: userInfo.isOnline
                        ? l10n.workspaceUserOnline
                        : l10n.appAccountStatusOffline,
                    avatarUrl: userInfo.avatarUrl,
                    isOnline: userInfo.isOnline,
                  );
          })
          .toList();
      setState(() {
        _validChatPeerIds = validPeerIds;
        _chatConversations = conversations;
        _chatNotice = conversations.isEmpty ? l10n.workspaceUsersEmpty : null;
        if (_selectedTab == _RailTab.chats) {
          _isConversationLoading = false;
          _selectedConversationIndex = conversations.isEmpty
              ? 0
              : _selectedConversationIndex.clamp(0, conversations.length - 1);
        }
      });
      if (_selectedTab == _RailTab.chats && conversations.isNotEmpty) {
        _activateConversation(conversations[_selectedConversationIndex]);
      }
    } catch (_) {
      if (!mounted ||
          requestId != _loadRequestId ||
          widget.appAccountSession?.id != session.id) {
        return;
      }
      setState(() {
        _chatConversations = const [];
        _chatNotice = l10n.workspaceUsersLoadFailed;
        if (_selectedTab == _RailTab.chats) {
          _isConversationLoading = false;
        }
      });
    }
  }

  void _rememberRecentMessageInMemory(LocalChatMessage message) {
    if (message.peerUserId <= 0) {
      return;
    }
    final current = _recentMessagesByPeer[message.peerUserId];
    if (current == null || message.createdAt.isAfter(current.createdAt)) {
      _recentMessagesByPeer[message.peerUserId] = message;
    }
  }

  Future<void> _persistPeerProfiles(List<RecommendedUser> users) async {
    final session = widget.appAccountSession;
    if (session == null || users.isEmpty) {
      return;
    }
    final store = await ref.read(localChatPeerProfileStoreProvider.future);
    final now = DateTime.now();
    final profiles = <int, LocalChatPeerProfile>{};
    for (final user in users) {
      if (user.id <= 0) {
        continue;
      }
      final profile = LocalChatPeerProfile(
        appUserId: session.id,
        peerUserId: user.id,
        displayName: user.displayName,
        avatarUrl: user.avatarUrl,
        updatedAt: now,
      );
      await store.upsert(profile);
      profiles[user.id] = profile;
    }
    if (!mounted ||
        profiles.isEmpty ||
        widget.appAccountSession?.id != session.id) {
      return;
    }
    setState(() => _peerProfiles.addAll(profiles));
  }

  Future<void> _persistChatConversationProfiles(
    List<ChatConversationSummary> conversations,
  ) async {
    final session = widget.appAccountSession;
    if (session == null || conversations.isEmpty) {
      return;
    }
    final store = await ref.read(localChatPeerProfileStoreProvider.future);
    final now = DateTime.now();
    final profiles = <int, LocalChatPeerProfile>{};
    for (final conversation in conversations) {
      if (conversation.peerUserId <= 0) {
        continue;
      }
      final profile = LocalChatPeerProfile(
        appUserId: session.id,
        peerUserId: conversation.peerUserId,
        displayName: conversation.displayName,
        avatarUrl: conversation.roomImg,
        updatedAt: now,
      );
      await store.upsert(profile);
      profiles[conversation.peerUserId] = profile;
      if (conversation.roomId > 0) {
        _directRoomIds[conversation.peerUserId] = conversation.roomId;
      }
    }
    if (!mounted ||
        profiles.isEmpty ||
        widget.appAccountSession?.id != session.id) {
      return;
    }
    setState(() => _peerProfiles.addAll(profiles));
  }

  String _conversationPreviewText(String text) {
    return text
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r' {2,}'), ' ')
        .trim();
  }

  String _formatConversationTime(DateTime time) {
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _syncImSocketSession() {
    final session = widget.appAccountSession;
    if (session == null || session.certificate.trim().isEmpty) {
      ref.read(imSessionManagerProvider).disconnect();
      return;
    }
    ref
        .read(imSessionManagerProvider)
        .start(certificate: session.certificate.trim());
  }

  void _resetAccountScopedState() {
    _searchDebounce?.cancel();
    _activeConversationSyncTimer?.cancel();
    setState(() {
      _selectedConversationIndex = 0;
      _isConversationLoading = false;
      _isSearchLoading = false;
      _isActiveConversationSyncing = false;
      _searchQuery = '';
      _searchNotice = null;
      _chatNotice = null;
      _chatConversations = const [];
      _searchConversations = const [];
      _remoteConversations.clear();
      _remoteNotices.clear();
      _directRoomIds.clear();
      _storedMessages.clear();
      _recentMessagesByPeer.clear();
      _peerProfiles.clear();
    });
  }

  void _showAccountHistoryOnOpen() {
    if (_didShowAccountHistory || !mounted) {
      return;
    }
    _didShowAccountHistory = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppAccountHistoryDialog(),
    );
  }
}

class _LeftSection extends StatelessWidget {
  const _LeftSection({
    required this.operatorName,
    required this.appAccountName,
    required this.appAccountOnline,
    required this.appAccountBusy,
    required this.appAccountAvatarUrl,
    required this.selectedTab,
    required this.selectedConversationIndex,
    required this.conversations,
    required this.isConversationLoading,
    required this.emptyMessage,
    required this.searchQuery,
    required this.onTabSelected,
    required this.onConversationSelected,
    required this.onSearchChanged,
    required this.onAppAccountTap,
    required this.onSettingsTap,
    required this.l10n,
  });

  final String operatorName;
  final String appAccountName;
  final bool appAccountOnline;
  final bool appAccountBusy;
  final String? appAccountAvatarUrl;
  final _RailTab selectedTab;
  final int selectedConversationIndex;
  final List<_Conversation> conversations;
  final bool isConversationLoading;
  final String emptyMessage;
  final String searchQuery;
  final ValueChanged<_RailTab> onTabSelected;
  final ValueChanged<int> onConversationSelected;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAppAccountTap;
  final VoidCallback onSettingsTap;
  final AppLocalizations l10n;

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
            appAccountAvatarUrl: appAccountAvatarUrl,
            selectedTab: selectedTab,
            onTabSelected: onTabSelected,
            onAppAccountTap: onAppAccountTap,
            onSettingsTap: onSettingsTap,
            l10n: l10n,
          ),
          Expanded(
            child: _ConversationPane(
              conversations: conversations,
              selectedIndex: selectedConversationIndex,
              isLoading: isConversationLoading,
              emptyMessage: emptyMessage,
              searchQuery: searchQuery,
              l10n: l10n,
              title: _titleForTab(l10n, selectedTab),
              onSearchChanged: onSearchChanged,
              onSelected: onConversationSelected,
            ),
          ),
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
    required this.appAccountAvatarUrl,
    required this.selectedTab,
    required this.onTabSelected,
    required this.onAppAccountTap,
    required this.onSettingsTap,
    required this.l10n,
  });

  final String operatorName;
  final String appAccountName;
  final bool appAccountOnline;
  final bool appAccountBusy;
  final String? appAccountAvatarUrl;
  final _RailTab selectedTab;
  final ValueChanged<_RailTab> onTabSelected;
  final VoidCallback onAppAccountTap;
  final VoidCallback onSettingsTap;
  final AppLocalizations l10n;

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
              children: [
                _RailItem(
                  icon: Icons.chat_bubble_rounded,
                  label: l10n.navChats,
                  badge: '6',
                  active: selectedTab == _RailTab.chats,
                  onTap: () => onTabSelected(_RailTab.chats),
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.person_add_alt_1_rounded,
                  label: l10n.navNew,
                  active: selectedTab == _RailTab.updates,
                  onTap: () => onTabSelected(_RailTab.updates),
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.radio_button_checked_rounded,
                  label: l10n.navOnline,
                  active: selectedTab == _RailTab.communities,
                  onTap: () => onTabSelected(_RailTab.communities),
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.diamond_rounded,
                  label: l10n.navRichs,
                  active: selectedTab == _RailTab.calls,
                  onTap: () => onTabSelected(_RailTab.calls),
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.login_rounded,
                  label: l10n.navLogin,
                  onTap: onAppAccountTap,
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.settings_rounded,
                  label: l10n.navSettings,
                  onTap: onSettingsTap,
                ),
              ],
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
                  avatarUrl: appAccountAvatarUrl,
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
    required this.onTap,
    this.active = false,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
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

    return Semantics(
      selected: active,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
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
        ),
      ),
    );
  }
}

class _SettingsDialog extends ConsumerWidget {
  const _SettingsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final selectedLocale = ref.watch(appLocaleProvider);

    return AlertDialog(
      title: Text(l10n.settings),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.language, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            _LanguageTile(
              title: l10n.languageSystem,
              value: null,
              groupValue: selectedLocale,
            ),
            _LanguageTile(
              title: l10n.languageEnglish,
              value: const Locale('en'),
              groupValue: selectedLocale,
            ),
            _LanguageTile(
              title: l10n.languageTraditionalChinese,
              value: const Locale.fromSubtags(
                languageCode: 'zh',
                scriptCode: 'Hant',
              ),
              groupValue: selectedLocale,
            ),
            _LanguageTile(
              title: l10n.languageVietnamese,
              value: const Locale('vi'),
              groupValue: selectedLocale,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

class _LanguageTile extends ConsumerWidget {
  const _LanguageTile({
    required this.title,
    required this.value,
    required this.groupValue,
  });

  final String title;
  final Locale? value;
  final Locale? groupValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = _sameLocale(value, groupValue);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_unchecked_rounded,
        color: selected ? const Color(0xff1da855) : const Color(0xff667781),
      ),
      title: Text(title),
      onTap: () {
        ref.read(appLocaleProvider.notifier).update(value);
      },
    );
  }

  bool _sameLocale(Locale? left, Locale? right) {
    if (left == null || right == null) {
      return left == right;
    }
    return left.languageCode == right.languageCode &&
        left.scriptCode == right.scriptCode &&
        left.countryCode == right.countryCode;
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({
    required this.label,
    required this.online,
    required this.busy,
    this.avatarUrl,
  });

  final String label;
  final bool online;
  final bool busy;
  final String? avatarUrl;

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
    final url = avatarUrl?.trim() ?? '';

    return Stack(
      children: [
        Container(
          width: 49,
          height: 49,
          decoration: BoxDecoration(
            gradient: url.isEmpty
                ? const LinearGradient(
                    colors: [Color(0xffff8a68), Color(0xffdd3e84)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: url.isEmpty ? null : const Color(0xffd9c2a6),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0x7ae4e4e4)),
          ),
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          child: busy
              ? const SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : url.isNotEmpty
              ? Image.network(
                  url,
                  width: 49,
                  height: 49,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Text(
                    initials,
                    style: const TextStyle(
                      color: Color(0xff54656f),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
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
  const _ConversationPane({
    required this.conversations,
    required this.selectedIndex,
    required this.isLoading,
    required this.emptyMessage,
    required this.searchQuery,
    required this.l10n,
    required this.title,
    required this.onSearchChanged,
    required this.onSelected,
  });

  final List<_Conversation> conversations;
  final int selectedIndex;
  final bool isLoading;
  final String emptyMessage;
  final String searchQuery;
  final AppLocalizations l10n;
  final String title;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 12,
            width: 272,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xff111b21),
                fontSize: 18,
                height: 24 / 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
              ),
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
          Positioned(
            left: 18,
            top: 42,
            width: 312,
            child: _SearchField(
              hintText: l10n.workspaceSearchHint,
              value: searchQuery,
              onChanged: onSearchChanged,
            ),
          ),
          Positioned(
            left: 10,
            width: 312,
            top: 108,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isLoading
                  ? _ConversationLoading(message: l10n.workspaceLoadingUsers)
                  : conversations.isEmpty
                  ? _ConversationEmpty(message: emptyMessage)
                  : Scrollbar(
                      thumbVisibility: conversations.length > 8,
                      radius: const Radius.circular(99),
                      child: ListView.separated(
                        key: ValueKey(
                          '${title}_${conversations.first.name}_${conversations.length}',
                        ),
                        padding: const EdgeInsets.only(bottom: 18),
                        physics: const ClampingScrollPhysics(),
                        itemBuilder: (context, index) => _ConversationTile(
                          item: conversations[index],
                          selected: index == selectedIndex,
                          onTap: () => onSelected(index),
                        ),
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemCount: conversations.length,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

String _titleForTab(AppLocalizations l10n, _RailTab tab) {
  return switch (tab) {
    _RailTab.chats => l10n.navChats,
    _RailTab.updates => l10n.navNew,
    _RailTab.communities => l10n.navOnline,
    _RailTab.calls => l10n.navRichs,
  };
}

class _SearchField extends StatefulWidget {
  const _SearchField({
    required this.hintText,
    required this.value,
    required this.onChanged,
  });

  final String hintText;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _SearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
        children: [
          const SizedBox(width: 13),
          const Icon(Icons.search, color: Color(0xff667781), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hintText,
                hintStyle: const TextStyle(
                  color: Color(0xff667781),
                  fontSize: 14,
                  height: 1,
                ),
              ),
              style: const TextStyle(
                color: Color(0xff111b21),
                fontSize: 14,
                height: 1,
              ),
            ),
          ),
          if (_controller.text.isEmpty)
            const Icon(Icons.tune_rounded, color: Color(0xff667781), size: 16)
          else
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _controller.clear();
                widget.onChanged('');
                setState(() {});
              },
              child: const Icon(
                Icons.close_rounded,
                color: Color(0xff667781),
                size: 16,
              ),
            ),
          const SizedBox(width: 13),
        ],
      ),
    );
  }
}

class _ConversationLoading extends StatelessWidget {
  const _ConversationLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('conversation-loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Color(0xff1da855),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              color: Color(0xff667781),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationEmpty extends StatelessWidget {
  const _ConversationEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: ValueKey('conversation-empty-$message'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xff667781),
            fontSize: 13,
            height: 18 / 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _Conversation item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: item.name,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 312,
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? const Color(0xfff0f2f5) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _LetterAvatar(
                color: item.color,
                label: item.emoji,
                avatarUrl: item.avatarUrl,
                online: item.isOnline,
              ),
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
                    const Icon(
                      Icons.push_pin,
                      size: 14,
                      color: Color(0xff667781),
                    )
                  else if (item.delivered)
                    Icon(
                      Icons.done_all,
                      size: 16,
                      color: item.deliveredRead
                          ? const Color(0xff53bdeb)
                          : const Color(0xff667781),
                    )
                  else
                    const SizedBox(height: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LetterAvatar extends StatelessWidget {
  const _LetterAvatar({
    required this.color,
    required this.label,
    this.avatarUrl,
    this.online = false,
    this.size = 60,
  });

  final Color color;
  final String label;
  final String? avatarUrl;
  final bool online;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            child: url != null && url.isNotEmpty
                ? Image.network(
                    url,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _AvatarFallback(color: color, label: label, size: size),
                  )
                : _AvatarFallback(color: color, label: label, size: size),
          ),
          if (online)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: size * 0.22,
                height: size * 0.22,
                decoration: BoxDecoration(
                  color: const Color(0xff1da855),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({
    required this.color,
    required this.label,
    required this.size,
  });

  final Color color;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
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

class _ChatSection extends StatefulWidget {
  const _ChatSection({
    required this.conversation,
    required this.appAccountSession,
    required this.connectionStatus,
    required this.messages,
    required this.draft,
    required this.l10n,
    required this.emptyMessage,
    required this.onDraftChanged,
    required this.onSend,
    required this.onSendEmojiGame,
    required this.onSendMedia,
    required this.onSendVoice,
  });

  final _Conversation? conversation;
  final AppUserSession? appAccountSession;
  final ConnectionStatus connectionStatus;
  final List<_ChatMessage> messages;
  final String draft;
  final AppLocalizations l10n;
  final String emptyMessage;
  final ValueChanged<String> onDraftChanged;
  final ValueChanged<String>? onSend;
  final ValueChanged<_EmojiGameSelection>? onSendEmojiGame;
  final Future<bool> Function(_SelectedChatMedia media)? onSendMedia;
  final Future<bool> Function(_SelectedVoiceRecording voice)? onSendVoice;

  @override
  State<_ChatSection> createState() => _ChatSectionState();
}

class _ChatSectionState extends State<_ChatSection> {
  final ScrollController _messageScrollController = ScrollController();
  bool _showJumpToBottom = false;

  @override
  void initState() {
    super.initState();
    _messageScrollController.addListener(_handleScrollChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToBottom(animated: false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _ChatSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversation?.name != widget.conversation?.name ||
        oldWidget.messages.length != widget.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_messageScrollController.hasClients) {
          return;
        }
        final distanceToBottom =
            _messageScrollController.position.maxScrollExtent -
            _messageScrollController.offset;
        if (oldWidget.conversation?.name != widget.conversation?.name ||
            distanceToBottom < 180) {
          _scrollToBottom(animated: false);
        }
        _handleScrollChanged();
      });
    }
  }

  @override
  void dispose() {
    _messageScrollController
      ..removeListener(_handleScrollChanged)
      ..dispose();
    super.dispose();
  }

  void _handleScrollChanged() {
    if (!_messageScrollController.hasClients) {
      return;
    }
    final shouldShow =
        _messageScrollController.position.maxScrollExtent -
            _messageScrollController.offset >
        120;
    if (shouldShow != _showJumpToBottom) {
      setState(() => _showJumpToBottom = shouldShow);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_scrollToLatestExtent(animated: animated));
    });
  }

  Future<void> _scrollToLatestExtent({required bool animated}) async {
    if (!_messageScrollController.hasClients) {
      return;
    }
    final position = _messageScrollController.position;
    final target = position.maxScrollExtent;
    try {
      if (animated) {
        await _messageScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      } else {
        _messageScrollController.jumpTo(target);
      }
    } catch (_) {
      return;
    }

    if (!mounted || !_messageScrollController.hasClients) {
      return;
    }
    final latestTarget = _messageScrollController.position.maxScrollExtent;
    if ((latestTarget - _messageScrollController.offset).abs() > 2) {
      _messageScrollController.jumpTo(latestTarget);
    }
    _handleScrollChanged();
  }

  @override
  Widget build(BuildContext context) {
    final conversation = widget.conversation;
    if (conversation == null) {
      return _ChatEmptyState(message: widget.emptyMessage);
    }

    return SizedBox.expand(
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: const Color(0xfffafafa),
              child: CustomPaint(painter: _ChatWallpaperPainter()),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _ChatHeader(
              conversation: conversation,
              appAccountSession: widget.appAccountSession,
              connectionStatus: widget.connectionStatus,
              l10n: widget.l10n,
              onlineText: widget.l10n.workspaceUserOnline,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 150,
            bottom: 80,
            child: _ScrollableMessageList(
              controller: _messageScrollController,
              messages: widget.messages,
            ),
          ),
          Positioned(
            right: 24,
            bottom: 96,
            child: _JumpToBottomButton(
              visible: _showJumpToBottom,
              onPressed: _scrollToBottom,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _MessageInput(
              key: ValueKey(conversation.name),
              initialValue: widget.draft,
              hintText: widget.l10n.workspaceMessageInputHint,
              onChanged: widget.onDraftChanged,
              onSend: widget.onSend,
              onSendEmojiGame: widget.onSendEmojiGame,
              onSendMedia: widget.onSendMedia,
              onSendVoice: widget.onSendVoice,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollableMessageList extends StatelessWidget {
  const _ScrollableMessageList({
    required this.controller,
    required this.messages,
  });

  final ScrollController controller;
  final List<_ChatMessage> messages;

  @override
  Widget build(BuildContext context) {
    return RawScrollbar(
      controller: controller,
      thumbVisibility: true,
      interactive: true,
      thickness: 4,
      radius: const Radius.circular(50),
      thumbColor: const Color(0xffb0c5c2),
      padding: const EdgeInsets.only(right: 4, top: 4, bottom: 4),
      child: ListView.builder(
        controller: controller,
        primary: false,
        padding: const EdgeInsets.fromLTRB(12, 0, 16, 8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: messages.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Center(child: _DatePill()),
            );
          }
          return _MessageListItem(message: messages[index - 1]);
        },
      ),
    );
  }
}

class _ChatEmptyState extends StatelessWidget {
  const _ChatEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfffafafa),
      alignment: Alignment.center,
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xff667781),
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MessageListItem extends StatelessWidget {
  const _MessageListItem({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.outgoing) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Align(
          alignment: Alignment.centerRight,
          child: _OutgoingBubble(
            width: message.width,
            text: message.text,
            time: message.time,
            status: message.sendStatus,
            media: message.media,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _IncomingBubble(
          width: message.width,
          text: message.text,
          time: message.time,
          singleLine: message.singleLine,
          media: message.media,
        ),
      ),
    );
  }
}

class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({required this.visible, required this.onPressed});

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1 : 0.75,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: IgnorePointer(
          ignoring: !visible,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xff0b141a).withValues(alpha: 0.16),
                  offset: const Offset(0, 2),
                  blurRadius: 8,
                ),
              ],
            ),
            child: IconButton(
              tooltip: 'Jump to latest message',
              onPressed: onPressed,
              icon: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xff54656f),
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.conversation,
    required this.appAccountSession,
    required this.connectionStatus,
    required this.l10n,
    required this.onlineText,
  });

  final _Conversation conversation;
  final AppUserSession? appAccountSession;
  final ConnectionStatus connectionStatus;
  final AppLocalizations l10n;
  final String onlineText;

  @override
  Widget build(BuildContext context) {
    final peerUserId = conversation.targetUserId;
    final peerText = peerUserId == null ? '' : 'UID $peerUserId';

    return Container(
      height: 96,
      color: const Color(0xfff7f7fc),
      padding: const EdgeInsets.only(left: 24, right: 18, top: 12, bottom: 10),
      child: Row(
        children: [
          _LetterAvatar(
            color: conversation.color,
            label: conversation.emoji,
            avatarUrl: conversation.avatarUrl,
            online: conversation.isOnline,
            size: 48,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  conversation.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff111b21),
                    fontSize: 16,
                    height: 24 / 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                if (peerText.isNotEmpty)
                  Text(
                    peerText,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xff667781),
                      fontSize: 11,
                      height: 14 / 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Row(
                  children: [
                    _OnlineDot(online: conversation.isOnline),
                    const SizedBox(width: 5),
                    Text(
                      conversation.isOnline
                          ? onlineText
                          : l10n.appAccountStatusOffline,
                      style: TextStyle(
                        color: conversation.isOnline
                            ? const Color(0xff54656f)
                            : const Color(0xff8d969c),
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
  const _OnlineDot({required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: online ? const Color(0xff1da855) : const Color(0xffc7d0d5),
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
    this.media,
  });

  final double width;
  final String text;
  final String time;
  final bool singleLine;
  final _ChatMedia? media;

  @override
  Widget build(BuildContext context) {
    final media = this.media;
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
          width: media == null ? width : media.bubbleWidth,
          padding: media == null
              ? EdgeInsets.fromLTRB(9, 6, singleLine ? 38 : 7, 3)
              : const EdgeInsets.fromLTRB(4, 4, 4, 3),
          decoration: _bubbleDecoration(Colors.white),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (media == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _ExpandableMessageText(
                    text,
                    style: const TextStyle(
                      color: Color(0xff111b21),
                      fontSize: _chatTextFontSize,
                      height: 19 / _chatTextFontSize,
                    ),
                  ),
                )
              else
                _MediaMessagePreview(media: media),
              Padding(
                padding: media == null
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(top: 2, right: 2),
                child: Text(
                  time,
                  style: const TextStyle(
                    color: Color(0xff667781),
                    fontSize: 10,
                    height: 15 / 10,
                  ),
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
    required this.status,
    this.media,
  });

  final double width;
  final String text;
  final String time;
  final ChatMessageSendStatus status;
  final _ChatMedia? media;

  @override
  Widget build(BuildContext context) {
    final media = this.media;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: media == null ? width : media.bubbleWidth,
          padding: media == null
              ? const EdgeInsets.fromLTRB(9, 6, 7, 3)
              : const EdgeInsets.fromLTRB(4, 4, 4, 3),
          decoration: _bubbleDecoration(const Color(0xffd9fdd3)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (media == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _ExpandableMessageText(
                    text,
                    style: const TextStyle(
                      color: Color(0xff111b21),
                      fontSize: _chatTextFontSize,
                      height: 19 / _chatTextFontSize,
                    ),
                  ),
                )
              else
                _MediaMessagePreview(media: media),
              SizedBox(height: media == null ? 1 : 2),
              Padding(
                padding: media == null
                    ? EdgeInsets.zero
                    : const EdgeInsets.only(right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: Color(0xff667781),
                        fontSize: 10,
                        height: 15 / 10,
                      ),
                    ),
                    const SizedBox(width: 3),
                    _MessageStatusIcon(status: status),
                  ],
                ),
              ),
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

class _MessageStatusIcon extends StatelessWidget {
  const _MessageStatusIcon({required this.status});

  final ChatMessageSendStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ChatMessageSendStatus.pending => const SizedBox(
        width: 15,
        height: 15,
        child: CircularProgressIndicator(
          strokeWidth: 1.8,
          color: Color(0xff667781),
        ),
      ),
      ChatMessageSendStatus.failed => const Icon(
        Icons.error_outline_rounded,
        size: 15,
        color: Color(0xffb3261e),
      ),
      ChatMessageSendStatus.sent => const Icon(
        Icons.done_all,
        size: 15,
        color: Color(0xff667781),
      ),
      ChatMessageSendStatus.read => const Icon(
        Icons.done_all,
        size: 15,
        color: Color(0xff53bdeb),
      ),
    };
  }
}

class _ExpandableMessageText extends StatefulWidget {
  const _ExpandableMessageText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  State<_ExpandableMessageText> createState() => _ExpandableMessageTextState();
}

class _ExpandableMessageTextState extends State<_ExpandableMessageText> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableMessageText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final textStyle = _styleForMessageText(widget.text, widget.style);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          maxLines: _collapsedMessageMaxLines,
          textDirection: textDirection,
        )..layout(maxWidth: constraints.maxWidth);
        final isOverflowing = painter.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              maxLines: _expanded ? null : _collapsedMessageMaxLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.fade,
              style: textStyle,
            ),
            if (isOverflowing && !_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => setState(() => _expanded = true),
                  child: Text(
                    l10n.messageReadMore,
                    style: textStyle.copyWith(
                      color: const Color(0xff1da855),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  TextStyle _styleForMessageText(String text, TextStyle baseStyle) {
    if (!_isStandaloneEmojiMessage(text)) {
      return baseStyle;
    }
    final baseFontSize = baseStyle.fontSize ?? _chatTextFontSize;
    return baseStyle.copyWith(
      fontSize: baseFontSize * _standaloneEmojiScale,
      height: 1.08,
    );
  }

  bool _isStandaloneEmojiMessage(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.length > 32) {
      return false;
    }
    if (RegExp(r'[A-Za-z0-9\u4e00-\u9fff]').hasMatch(normalized)) {
      return false;
    }
    return _standaloneEmojiPattern.hasMatch(normalized);
  }
}

const _mediaBubbleMaxWidth = 248.0;
const _mediaBubbleMaxHeight = 260.0;
const _mediaBubbleMinWidth = 132.0;
const _mediaBubbleMinHeight = 96.0;

class _MediaMessagePreview extends StatelessWidget {
  const _MediaMessagePreview({required this.media});

  final _ChatMedia media;

  @override
  Widget build(BuildContext context) {
    if (media.isVoice) {
      return _VoiceMessagePreview(media: media);
    }
    final source = media.previewSource;
    final size = media.previewSize;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showMediaViewer(context, media),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (source.isEmpty)
                  _MediaMessageFallback(isVideo: media.isVideo)
                else if (source.startsWith('http'))
                  Image.network(
                    source,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _MediaMessageFallback(isVideo: media.isVideo),
                  )
                else
                  Image.file(
                    File(source),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _MediaMessageFallback(isVideo: media.isVideo),
                  ),
                if (media.isVideo)
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xff0b141a).withValues(alpha: 0.58),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 34,
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

  void _showMediaViewer(BuildContext context, _ChatMedia media) {
    showDialog<void>(
      context: context,
      barrierColor: const Color(0xdd0b141a),
      builder: (_) => _MediaViewerDialog(media: media),
    );
  }
}

class _VoiceMessagePreview extends StatefulWidget {
  const _VoiceMessagePreview({required this.media});

  final _ChatMedia media;

  @override
  State<_VoiceMessagePreview> createState() => _VoiceMessagePreviewState();
}

class _VoiceMessagePreviewState extends State<_VoiceMessagePreview> {
  late final Player _player;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  bool _opened = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (mounted) {
        setState(() => _playing = playing);
      }
    });
    _positionSubscription = _player.stream.position.listen((position) {
      if (mounted) {
        setState(() => _position = position);
      }
    });
    _durationSubscription = _player.stream.duration.listen((duration) {
      if (mounted) {
        setState(() => _duration = duration);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_playingSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    final source = widget.media.viewerSource;
    if (source.isEmpty) {
      return;
    }
    if (!_opened) {
      await _player.open(Media(source), play: false);
      _opened = true;
    }
    if (_playing) {
      await _player.pause();
      return;
    }
    final duration = _duration;
    if (duration > Duration.zero && _position >= duration) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.media.viewerSource;
    final fallbackSeconds = widget.media.durationSeconds ?? 0;
    final progress = _duration.inMilliseconds <= 0
        ? 0.0
        : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: widget.media.previewSize.width,
      height: widget.media.previewSize.height,
      child: Row(
        children: [
          IconButton.filled(
            style: IconButton.styleFrom(
              backgroundColor: source.isEmpty
                  ? const Color(0xffcfd8dc)
                  : const Color(0xff1da855),
              foregroundColor: Colors.white,
            ),
            onPressed: source.isEmpty ? null : _toggle,
            icon: Icon(
              _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  backgroundColor: const Color(0xffd9e1e5),
                  color: const Color(0xff1da855),
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 6),
                Text(
                  _duration > Duration.zero
                      ? _formatVoiceDuration(_duration.inSeconds)
                      : _formatVoiceDuration(fallbackSeconds),
                  style: const TextStyle(
                    color: Color(0xff667781),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaMessageFallback extends StatelessWidget {
  const _MediaMessageFallback({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xffe8ecef),
      alignment: Alignment.center,
      child: Icon(
        isVideo ? Icons.videocam_rounded : Icons.image_rounded,
        color: const Color(0xff667781),
        size: 44,
      ),
    );
  }
}

class _MediaViewerDialog extends StatelessWidget {
  const _MediaViewerDialog({required this.media});

  final _ChatMedia media;

  @override
  Widget build(BuildContext context) {
    final source = media.viewerSource;
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox.expand(),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width - 96,
                    maxHeight: MediaQuery.sizeOf(context).height - 96,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (media.isVideo && source.isNotEmpty)
                        _LoopingVideoPlayer(
                          source: source,
                          posterSource: media.previewSource,
                        )
                      else if (source.isEmpty)
                        _MediaMessageFallback(isVideo: media.isVideo)
                      else if (source.startsWith('http'))
                        Image.network(
                          source,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              _MediaMessageFallback(isVideo: media.isVideo),
                        )
                      else
                        Image.file(
                          File(source),
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) =>
                              _MediaMessageFallback(isVideo: media.isVideo),
                        ),
                      if (media.isVideo && source.isEmpty) _LargePlayOverlay(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 26,
            right: 28,
            child: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.16),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoopingVideoPlayer extends StatefulWidget {
  const _LoopingVideoPlayer({
    required this.source,
    required this.posterSource,
    this.muted = false,
  });

  final String source;
  final String posterSource;
  final bool muted;

  @override
  State<_LoopingVideoPlayer> createState() => _LoopingVideoPlayerState();
}

class _LoopingVideoPlayerState extends State<_LoopingVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _bufferingSubscription;
  bool _showPoster = true;
  bool _isPlaying = false;
  bool _isBuffering = true;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _playingSubscription = _player.stream.playing.listen((playing) {
      _isPlaying = playing;
      _maybeHidePoster();
    });
    _bufferingSubscription = _player.stream.buffering.listen((buffering) {
      _isBuffering = buffering;
      _maybeHidePoster();
    });
    _open();
  }

  @override
  void didUpdateWidget(covariant _LoopingVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      setState(() {
        _showPoster = true;
        _isPlaying = false;
        _isBuffering = true;
      });
      _open();
    }
  }

  void _maybeHidePoster() {
    if (!_showPoster || !_isPlaying || _isBuffering) {
      return;
    }
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted && _showPoster && _isPlaying && !_isBuffering) {
        setState(() => _showPoster = false);
      }
    });
  }

  Future<void> _open() async {
    await _player.setPlaylistMode(PlaylistMode.loop);
    await _player.setVolume(widget.muted ? 0 : 100);
    await _player.open(Media(widget.source), play: true);
  }

  @override
  void dispose() {
    unawaited(_playingSubscription?.cancel());
    unawaited(_bufferingSubscription?.cancel());
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Video(
          controller: _controller,
          fit: BoxFit.contain,
          controls: AdaptiveVideoControls,
        ),
        AnimatedOpacity(
          opacity: _showPoster ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: IgnorePointer(
            ignoring: !_showPoster,
            child: _VideoStartupPoster(source: widget.posterSource),
          ),
        ),
      ],
    );
  }
}

class _VideoStartupPoster extends StatelessWidget {
  const _VideoStartupPoster({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    if (source.isEmpty) {
      return const ColoredBox(color: Color(0xff0b141a));
    }
    if (source.startsWith('http')) {
      return Image.network(
        source,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xff0b141a)),
      );
    }
    return Image.file(
      File(source),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xff0b141a)),
    );
  }
}

class _LargePlayOverlay extends StatelessWidget {
  const _LargePlayOverlay();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xff0b141a).withValues(alpha: 0.58),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        color: Colors.white,
        size: 52,
      ),
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

class _MessageInput extends StatefulWidget {
  const _MessageInput({
    required this.initialValue,
    required this.hintText,
    required this.onChanged,
    required this.onSend,
    required this.onSendEmojiGame,
    required this.onSendMedia,
    required this.onSendVoice,
    super.key,
  });

  final String initialValue;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSend;
  final ValueChanged<_EmojiGameSelection>? onSendEmojiGame;
  final Future<bool> Function(_SelectedChatMedia media)? onSendMedia;
  final Future<bool> Function(_SelectedVoiceRecording voice)? onSendVoice;

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final Stopwatch _voiceStopwatch = Stopwatch();
  OverlayEntry? _emojiOverlayEntry;
  OverlayEntry? _attachOverlayEntry;
  Timer? _emojiCloseTimer;
  Timer? _voiceTimer;
  bool _emojiButtonHovered = false;
  bool _emojiPanelHovered = false;
  bool _isVoiceRecording = false;
  bool _isVoiceSending = false;
  int _voiceSeconds = 0;
  String? _voicePath;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _hideEmojiPanel(notify: false);
    _hideAttachmentMenu(notify: false);
    _emojiCloseTimer?.cancel();
    _voiceTimer?.cancel();
    if (_isVoiceRecording) {
      unawaited(_voiceRecorder.cancel());
    }
    unawaited(_voiceRecorder.dispose());
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    if (_isVoiceRecording || _isVoiceSending) {
      return;
    }
    final value = _controller.text;
    if (value.trim().isEmpty || widget.onSend == null) {
      return;
    }
    widget.onSend!(value);
    _controller.clear();
    widget.onChanged('');
    setState(() {});
    _focusNode.requestFocus();
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isVoiceSending || widget.onSendVoice == null) {
      return;
    }
    if (_isVoiceRecording) {
      await _stopAndSendVoice();
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    _hideEmojiPanel();
    _hideAttachmentMenu();
    _focusNode.unfocus();
    final hasPermission = await _voiceRecorder.hasPermission();
    if (!mounted) {
      return;
    }
    if (!hasPermission) {
      _showInputNotice(AppLocalizations.of(context).voicePermissionDenied);
      return;
    }
    final previousPath = _voicePath;
    if (previousPath != null && previousPath.isNotEmpty) {
      unawaited(
        File(previousPath).delete().catchError((_) => File(previousPath)),
      );
    }
    final dataDir = await DesktopDataDirectory.resolve();
    final dir = Directory(
      '${dataDir.path}${Platform.pathSeparator}cache${Platform.pathSeparator}voice_records',
    );
    await dir.create(recursive: true);
    final path =
        '${dir.path}${Platform.pathSeparator}bbp_voice_${DateTime.now().microsecondsSinceEpoch}.wav';
    debugPrint('[CHAT_OPS][VOICE][INLINE_RECORD_PATH] $path');
    try {
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (!mounted) {
        return;
      }
      _voiceStopwatch
        ..reset()
        ..start();
      _voiceTimer?.cancel();
      _voiceTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) {
          return;
        }
        final next = _voiceStopwatch.elapsed.inSeconds;
        if (next != _voiceSeconds) {
          setState(() => _voiceSeconds = next);
        }
        if (next >= _maxVoiceRecordSeconds) {
          unawaited(_stopAndSendVoice());
        }
      });
      setState(() {
        _voicePath = path;
        _voiceSeconds = 0;
        _isVoiceRecording = true;
      });
    } catch (_) {
      if (mounted) {
        _showInputNotice(AppLocalizations.of(context).voiceRecordFailed);
      }
    }
  }

  Future<void> _stopAndSendVoice() async {
    if (!_isVoiceRecording || _isVoiceSending) {
      return;
    }
    _voiceTimer?.cancel();
    _voiceStopwatch.stop();
    final elapsed = _voiceStopwatch.elapsed;
    final fallbackPath = _voicePath;
    setState(() {
      _isVoiceRecording = false;
      _isVoiceSending = true;
      _voiceSeconds = max(1, (elapsed.inMilliseconds / 1000).ceil());
    });
    try {
      debugPrint(
        '[CHAT_OPS][VOICE][INLINE_STAGE] stop_start path=$fallbackPath '
        'elapsedMs=${elapsed.inMilliseconds}',
      );
      final stoppedPath = await _voiceRecorder.stop().timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint(
            '[CHAT_OPS][VOICE][INLINE_STOP_TIMEOUT] fallbackPath=$fallbackPath',
          );
          return fallbackPath;
        },
      );
      final path = (stoppedPath?.trim().isNotEmpty == true)
          ? stoppedPath
          : fallbackPath;
      debugPrint('[CHAT_OPS][VOICE][INLINE_STAGE] stop_done path=$path');
      final ready = await _voiceInputFileReady(path);
      debugPrint(
        '[CHAT_OPS][VOICE][INLINE_SEND] path=$path '
        'elapsedMs=${elapsed.inMilliseconds} exists=${ready.exists} '
        'size=${ready.fileSize}',
      );
      if (path == null ||
          path.trim().isEmpty ||
          !ready.exists ||
          widget.onSendVoice == null) {
        throw const ChatMediaUploadException('Voice recording failed.');
      }
      final voice = _SelectedVoiceRecording(
        path: path,
        fileName: path.split(Platform.pathSeparator).last,
        durationSeconds: max(1, (elapsed.inMilliseconds / 1000).ceil()),
        fileSizeBytes: ready.fileSize,
      );
      debugPrint(
        '[CHAT_OPS][VOICE][INLINE_STAGE] send_start path=${voice.path} '
        'size=${voice.fileSizeBytes} duration=${voice.durationSeconds}',
      );
      final success = await widget.onSendVoice!(voice).timeout(
        const Duration(seconds: 25),
        onTimeout: () {
          throw const ChatMediaUploadException('Voice send timeout.');
        },
      );
      debugPrint('[CHAT_OPS][VOICE][INLINE_STAGE] send_done success=$success');
      if (!mounted) {
        return;
      }
      if (!success) {
        setState(() => _isVoiceSending = false);
        return;
      }
      setState(() {
        _isVoiceSending = false;
        _voicePath = null;
        _voiceSeconds = 0;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      debugPrint('[CHAT_OPS][VOICE][INLINE_SEND_FAILED] $error');
      setState(() => _isVoiceSending = false);
      _showInputNotice(AppLocalizations.of(context).voiceRecordFailed);
    }
  }

  Future<({bool exists, int fileSize})> _voiceInputFileReady(
    String? path,
  ) async {
    if (path == null || path.trim().isEmpty) {
      return (exists: false, fileSize: 0);
    }
    final file = File(path);
    for (var attempt = 0; attempt < 50; attempt += 1) {
      final exists = await file.exists();
      if (exists) {
        final fileSize = await file.length();
        if (fileSize > 0) {
          return (exists: true, fileSize: fileSize);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final exists = await file.exists();
    final fileSize = exists ? await file.length() : 0;
    return (exists: exists && fileSize > 0, fileSize: fileSize);
  }

  void _toggleEmojiPanel() {
    if (_emojiOverlayEntry == null) {
      _showEmojiPanel();
      return;
    }
    _hideEmojiPanel();
  }

  void _handleEmojiButtonEnter(PointerEnterEvent _) {
    _emojiButtonHovered = true;
    _emojiCloseTimer?.cancel();
    if (_emojiOverlayEntry == null) {
      _showEmojiPanel();
    }
  }

  void _handleEmojiButtonExit(PointerExitEvent _) {
    _emojiButtonHovered = false;
    _scheduleEmojiPanelClose();
  }

  void _handleEmojiPanelEnter(PointerEnterEvent _) {
    _emojiPanelHovered = true;
    _emojiCloseTimer?.cancel();
  }

  void _handleEmojiPanelExit(PointerExitEvent _) {
    _emojiPanelHovered = false;
    _scheduleEmojiPanelClose();
  }

  void _scheduleEmojiPanelClose() {
    _emojiCloseTimer?.cancel();
    _emojiCloseTimer = Timer(const Duration(milliseconds: 180), () {
      if (!_emojiButtonHovered && !_emojiPanelHovered) {
        _hideEmojiPanel();
      }
    });
  }

  void _showEmojiPanel() {
    final overlay = Overlay.maybeOf(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null || renderBox == null || overlayBox == null) {
      return;
    }
    final inputTopLeft = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final overlaySize = overlayBox.size;
    final panelHeight = (inputTopLeft.dy - 28).clamp(300.0, 520.0);
    final availablePanelWidth = overlaySize.width - inputTopLeft.dx - 48;
    final panelWidth = (availablePanelWidth * 0.7).clamp(320.0, 364.0);
    final left = (inputTopLeft.dx + renderBox.size.width - panelWidth - 22)
        .clamp(16.0, overlaySize.width - panelWidth - 16);
    final top = inputTopLeft.dy - panelHeight - 8;

    _emojiOverlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: panelWidth,
            height: panelHeight,
            child: MouseRegion(
              onEnter: _handleEmojiPanelEnter,
              onExit: _handleEmojiPanelExit,
              child: _EmojiPickerPanel(
                recentTitle: AppLocalizations.of(context).emojiRecentTitle,
                smileysTitle: AppLocalizations.of(context).emojiSmileysTitle,
                onEmojiSelected: _insertEmoji,
                onEmojiGameSelected: _sendEmojiGame,
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_emojiOverlayEntry!);
    setState(() {});
  }

  void _hideEmojiPanel({bool notify = true}) {
    _emojiCloseTimer?.cancel();
    _emojiOverlayEntry?.remove();
    _emojiOverlayEntry = null;
    if (notify && mounted) {
      setState(() {});
    }
  }

  void _insertEmoji(String emoji) {
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, emoji);
    final nextOffset = start + emoji.length;
    _controller.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
    widget.onChanged(nextText);
    setState(() {});
    _focusNode.requestFocus();
  }

  void _sendEmojiGame(String type) {
    if (widget.onSendEmojiGame == null) {
      return;
    }
    final value = type == _EmojiGameSelection.diceType
        ? 1 + _random.nextInt(6)
        : _random.nextInt(3);
    widget.onSendEmojiGame!(_EmojiGameSelection(type: type, value: value));
    _hideEmojiPanel();
    _focusNode.requestFocus();
  }

  void _toggleAttachmentMenu() {
    if (_attachOverlayEntry == null) {
      _showAttachmentMenu();
      return;
    }
    _hideAttachmentMenu();
  }

  void _showAttachmentMenu() {
    _hideEmojiPanel();
    final overlay = Overlay.maybeOf(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (overlay == null || renderBox == null || overlayBox == null) {
      return;
    }
    final inputTopLeft = renderBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final left = (inputTopLeft.dx + 14).clamp(
      16.0,
      overlayBox.size.width - 236,
    );
    final top = inputTopLeft.dy - 190;

    _attachOverlayEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideAttachmentMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: 220,
            child: _AttachmentMenu(
              onPhotoOrVideo: _pickPhotoOrVideo,
              onSelect: _hideAttachmentMenu,
            ),
          ),
        ],
      ),
    );
    overlay.insert(_attachOverlayEntry!);
    setState(() {});
  }

  void _hideAttachmentMenu({bool notify = true}) {
    _attachOverlayEntry?.remove();
    _attachOverlayEntry = null;
    if (notify && mounted) {
      setState(() {});
    }
  }

  Future<void> _pickPhotoOrVideo() async {
    _hideAttachmentMenu();
    final l10n = AppLocalizations.of(context);
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Photo Or Video',
      initialDirectory: _downloadsDirectoryPath(),
      type: FileType.custom,
      allowedExtensions: [..._chatImageExtensions, ..._chatVideoExtensions],
      allowMultiple: false,
      withData: false,
      withReadStream: false,
      lockParentWindow: true,
    );
    final pickedFile = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    if (pickedFile == null) {
      return;
    }
    final path = pickedFile.path;
    if (path == null || path.trim().isEmpty) {
      return;
    }
    final extension = _fileExtension(path);
    final isVideo = _chatVideoExtensions.contains(extension);
    final isImage = _chatImageExtensions.contains(extension);
    if (!isVideo && !isImage) {
      _showInputNotice(l10n.mediaUnsupportedFile);
      return;
    }
    if (isVideo) {
      final fileSize = await File(path).length();
      if (fileSize > _maxChatVideoBytes) {
        _showInputNotice(l10n.mediaVideoSizeLimit('50'));
        return;
      }
    }
    if (!mounted) {
      return;
    }
    await _showMediaPreviewDialog(
      path: path,
      fileName: pickedFile.name,
      isVideo: isVideo,
      fileSizeBytes: await File(path).length(),
    );
  }

  Future<void> _showMediaPreviewDialog({
    required String path,
    required String fileName,
    required bool isVideo,
    required int fileSizeBytes,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MediaPreviewDialog(
        path: path,
        fileName: fileName,
        isVideo: isVideo,
        fileSizeBytes: fileSizeBytes,
        onSend: widget.onSendMedia == null
            ? null
            : () => widget.onSendMedia!(
                _SelectedChatMedia(
                  path: path,
                  fileName: fileName,
                  isVideo: isVideo,
                  fileSizeBytes: fileSizeBytes,
                ),
              ),
        onSendSucceeded: () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        },
      ),
    );
  }

  String? _downloadsDirectoryPath() {
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      final downloads = Directory('$home/Downloads');
      if (downloads.existsSync()) {
        return downloads.path;
      }
      return home;
    }
    final userProfile = Platform.environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      final downloads = Directory('$userProfile\\Downloads');
      if (downloads.existsSync()) {
        return downloads.path;
      }
      return userProfile;
    }
    return null;
  }

  String _fileExtension(String path) {
    final filename = path.split(Platform.pathSeparator).last;
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == filename.length - 1) {
      return '';
    }
    return filename.substring(dotIndex + 1).toLowerCase();
  }

  void _showInputNotice(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Container(
      height: 80,
      color: const Color(0xfff6f6f6),
      padding: const EdgeInsets.fromLTRB(23, 16, 22, 16),
      child: Row(
        children: [
          IconButton(
            tooltip: 'More',
            onPressed: _toggleAttachmentMenu,
            icon: AnimatedRotation(
              turns: _attachOverlayEntry == null ? 0 : 0.125,
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.add_rounded,
                color: _attachOverlayEntry == null
                    ? const Color(0xff253443)
                    : const Color(0xff1da855),
                size: 25,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Stack(
                children: [
                  Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.enter):
                          _SendMessageIntent(),
                    },
                    child: Actions(
                      actions: {
                        _SendMessageIntent: CallbackAction<_SendMessageIntent>(
                          onInvoke: (_) {
                            _send();
                            return null;
                          },
                        ),
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        enabled: !_isVoiceRecording && !_isVoiceSending,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            _maxChatMessageLength,
                          ),
                        ],
                        keyboardType: TextInputType.multiline,
                        maxLines: null,
                        onChanged: (value) {
                          widget.onChanged(value);
                          setState(() {});
                        },
                        textInputAction: TextInputAction.newline,
                        cursorColor: const Color(0xff1da855),
                        style: const TextStyle(
                          color: Color(0xff111b21),
                          fontSize: 14,
                          height: 24 / 14,
                        ),
                        decoration:
                            const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.fromLTRB(
                                24,
                                12,
                                24,
                                12,
                              ),
                            ).copyWith(
                              hintText: widget.hintText,
                              hintStyle: const TextStyle(
                                color: Color(0xff8f8f8f),
                                fontSize: 14,
                                height: 24 / 14,
                              ),
                            ),
                      ),
                    ),
                  ),
                  if (_isVoiceRecording || _isVoiceSending)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _isVoiceSending
                                    ? const Color(0xff1da855)
                                    : const Color(0xffef4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _isVoiceSending
                                  ? AppLocalizations.of(context).mediaSending
                                  : _formatVoiceDuration(_voiceSeconds),
                              style: TextStyle(
                                color: _isVoiceSending
                                    ? const Color(0xff1da855)
                                    : const Color(0xffef4444),
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _isVoiceSending
                                    ? '[Voice]'
                                    : AppLocalizations.of(
                                        context,
                                      ).voiceRecordingHint,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xff667781),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          MouseRegion(
            onEnter: _handleEmojiButtonEnter,
            onExit: _handleEmojiButtonExit,
            child: IconButton(
              tooltip: 'Emoji',
              onPressed: _toggleEmojiPanel,
              icon: Icon(
                Icons.emoji_emotions_outlined,
                color: _emojiOverlayEntry == null
                    ? const Color(0xff54656f)
                    : const Color(0xff1da855),
                size: 26,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _isVoiceRecording
                ? AppLocalizations.of(context).mediaSend
                : hasText
                ? widget.hintText
                : 'Voice',
            onPressed: _isVoiceSending
                ? null
                : _isVoiceRecording
                ? _stopAndSendVoice
                : hasText
                ? (widget.onSend == null ? null : _send)
                : (widget.onSendVoice == null ? null : _toggleVoiceRecording),
            icon: _isVoiceSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Color(0xff1da855),
                    ),
                  )
                : Icon(
                    _isVoiceRecording
                        ? Icons.send_rounded
                        : hasText
                        ? Icons.send_rounded
                        : Icons.mic_rounded,
                    color: _isVoiceRecording
                        ? const Color(0xff1da855)
                        : const Color(0xff54656f),
                    size: 24,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

enum _VoiceRecordStatus { idle, recording, recorded, sending }

class _VoiceRecordDialog extends StatefulWidget {
  const _VoiceRecordDialog({
    required this.onSend,
    required this.onSendSucceeded,
  });

  final Future<bool> Function(_SelectedVoiceRecording voice)? onSend;
  final VoidCallback onSendSucceeded;

  @override
  State<_VoiceRecordDialog> createState() => _VoiceRecordDialogState();
}

class _VoiceRecordDialogState extends State<_VoiceRecordDialog> {
  final AudioRecorder _recorder = AudioRecorder();
  final Stopwatch _recordStopwatch = Stopwatch();
  _VoiceRecordStatus _status = _VoiceRecordStatus.idle;
  Timer? _timer;
  int _seconds = 0;
  String? _path;
  String? _error;
  bool _stopping = false;
  bool _voiceReady = false;
  Future<String?>? _stopFuture;

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_status == _VoiceRecordStatus.recording) {
      await _stopRecording();
      return;
    }
    if (_status == _VoiceRecordStatus.recorded) {
      final previousPath = _path;
      if (previousPath != null && previousPath.isNotEmpty) {
        unawaited(
          File(previousPath).delete().catchError((_) => File(previousPath)),
        );
      }
    }
    setState(() {
      _error = null;
      _seconds = 0;
      _path = null;
      _voiceReady = false;
      _stopFuture = null;
    });
    _recordStopwatch
      ..reset()
      ..stop();
    final hasPermission = await _recorder.hasPermission();
    if (!mounted) {
      return;
    }
    if (!hasPermission) {
      setState(
        () => _error = AppLocalizations.of(context).voicePermissionDenied,
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}${Platform.pathSeparator}bbp_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          numChannels: 1,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _status = _VoiceRecordStatus.recording;
        _path = path;
      });
      _recordStopwatch.start();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted) {
          return;
        }
        final next = _recordStopwatch.elapsed.inSeconds;
        if (next != _seconds) {
          setState(() => _seconds = next);
        }
        if (next >= _maxVoiceRecordSeconds) {
          unawaited(_stopRecording());
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).voiceRecordFailed);
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_stopping) {
      return;
    }
    _timer?.cancel();
    if (_status != _VoiceRecordStatus.recording) {
      return;
    }
    _recordStopwatch.stop();
    final elapsed = _recordStopwatch.elapsed;
    final fallbackPath = _path;
    if (fallbackPath == null || fallbackPath.trim().isEmpty) {
      setState(() {
        _status = _VoiceRecordStatus.idle;
        _stopping = false;
        _voiceReady = false;
        _error = AppLocalizations.of(context).voiceRecordFailed;
      });
      return;
    }
    _markVoiceReady(fallbackPath, elapsed);
    final stopFuture = _finalizeRecording(fallbackPath, elapsed);
    _stopFuture = stopFuture;
    unawaited(stopFuture);
  }

  Future<String?> _finalizeRecording(
    String fallbackPath,
    Duration elapsed,
  ) async {
    try {
      final stoppedPath = await _recorder.stop().timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('[CHAT_OPS][VOICE][STOP_TIMEOUT] fallbackPath=$_path');
          return null;
        },
      );
      if (!mounted) {
        return stoppedPath ?? fallbackPath;
      }
      final path = stoppedPath ?? _path;
      if (path != null && path.trim().isNotEmpty && path != _path) {
        _path = path;
      }
      debugPrint(
        '[CHAT_OPS][VOICE][STOP] path=$path elapsedMs=${elapsed.inMilliseconds} '
        'finalized=true',
      );
      return path ?? fallbackPath;
    } catch (error) {
      if (mounted) {
        debugPrint(
          '[CHAT_OPS][VOICE][STOP_ERROR] error=$error '
          'fallbackPath=$fallbackPath',
        );
      }
      return fallbackPath;
    }
  }

  Future<({bool exists, int fileSize})> _voiceFileReady(String? path) async {
    if (path == null || path.trim().isEmpty) {
      return (exists: false, fileSize: 0);
    }
    final file = File(path);
    for (var attempt = 0; attempt < 8; attempt += 1) {
      final exists = await file.exists();
      if (exists) {
        final fileSize = await file.length();
        if (fileSize > 0) {
          return (exists: true, fileSize: fileSize);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    final exists = await file.exists();
    final fileSize = exists ? await file.length() : 0;
    return (exists: exists && fileSize > 0, fileSize: fileSize);
  }

  void _markVoiceReady(String path, Duration elapsed) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = _VoiceRecordStatus.recorded;
      _stopping = false;
      _voiceReady = true;
      _path = path;
      _seconds = max(1, (elapsed.inMilliseconds / 1000).ceil());
      _error = null;
    });
  }

  Future<void> _cancelRecording() async {
    _timer?.cancel();
    _recordStopwatch
      ..reset()
      ..stop();
    if (_status == _VoiceRecordStatus.recording) {
      await _recorder.cancel();
    }
    final path = _path;
    if (path != null && path.isNotEmpty) {
      unawaited(File(path).delete().catchError((_) => File(path)));
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _send() async {
    final onSend = widget.onSend;
    var path = _path;
    if (!_voiceReady || onSend == null || path == null || path.trim().isEmpty) {
      return;
    }
    setState(() => _status = _VoiceRecordStatus.sending);
    final finalizedPath = await _stopFuture?.timeout(
      const Duration(seconds: 2),
      onTimeout: () => path,
    );
    path = finalizedPath?.trim().isNotEmpty == true ? finalizedPath : path;
    final ready = await _voiceFileReady(path);
    final sendPath = path;
    if (!ready.exists || sendPath == null || sendPath.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _status = _VoiceRecordStatus.recorded;
          _error = AppLocalizations.of(context).voiceRecordFailed;
        });
      }
      return;
    }
    final success = await onSend(
      _SelectedVoiceRecording(
        path: sendPath,
        fileName: sendPath.split(Platform.pathSeparator).last,
        durationSeconds: max(1, _seconds),
        fileSizeBytes: ready.fileSize,
      ),
    );
    if (!mounted) {
      return;
    }
    if (success) {
      widget.onSendSucceeded();
      return;
    }
    setState(() => _status = _VoiceRecordStatus.recorded);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRecording = _status == _VoiceRecordStatus.recording;
    final isRecorded = _status == _VoiceRecordStatus.recorded;
    final isSending = _status == _VoiceRecordStatus.sending;
    final canOperate = !isSending && !_stopping;
    final canSend =
        canOperate && _voiceReady && _path?.trim().isNotEmpty == true;

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: SizedBox(
        width: 360,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: l10n.close,
                    onPressed: canOperate ? _cancelRecording : null,
                    icon: const Icon(Icons.close_rounded),
                  ),
                  Expanded(
                    child: Text(
                      l10n.voiceRecordTitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xff111b21),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color:
                      (isRecording
                              ? const Color(0xffef4444)
                              : const Color(0xff1da855))
                          .withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  isRecorded ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                  color: isRecording
                      ? const Color(0xffef4444)
                      : const Color(0xff1da855),
                  size: 42,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _formatVoiceDuration(_seconds),
                style: const TextStyle(
                  color: Color(0xff111b21),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 38,
                child: Center(
                  child: Text(
                    isRecording
                        ? l10n.voiceRecordingHint
                        : isRecorded
                        ? l10n.voiceRecordReady
                        : l10n.voiceRecordHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xff667781),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xffd92d20),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isRecording
                            ? const Color(0xffef4444)
                            : const Color(0xff1da855),
                        side: BorderSide(
                          color: isRecording
                              ? const Color(0xffef4444)
                              : const Color(0xff1da855),
                        ),
                      ),
                      onPressed: canOperate ? _startRecording : null,
                      child: Text(
                        isRecording
                            ? l10n.voiceStop
                            : isRecorded
                            ? l10n.voiceRecordAgain
                            : l10n.voiceStart,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        disabledBackgroundColor: const Color(0xffd6dadd),
                        disabledForegroundColor: const Color(0xff8c969d),
                        backgroundColor: const Color(0xff1da855),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: canSend ? _send : null,
                      child: isSending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.mediaSend),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPreviewDialog extends StatefulWidget {
  const _MediaPreviewDialog({
    required this.path,
    required this.fileName,
    required this.isVideo,
    required this.fileSizeBytes,
    required this.onSend,
    required this.onSendSucceeded,
  });

  final String path;
  final String fileName;
  final bool isVideo;
  final int fileSizeBytes;
  final Future<bool> Function()? onSend;
  final VoidCallback onSendSucceeded;

  @override
  State<_MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<_MediaPreviewDialog> {
  bool _sending = false;

  Future<void> _send() async {
    final onSend = widget.onSend;
    if (onSend == null || _sending) {
      return;
    }
    setState(() => _sending = true);
    final success = await onSend();
    if (!mounted) {
      return;
    }
    if (success) {
      widget.onSendSucceeded();
      return;
    }
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = min(screenSize.width * 0.72, 560.0);
    final dialogHeight = min(screenSize.height * 0.82, 720.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            SizedBox(
              height: 70,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: IconButton(
                        tooltip: l10n.close,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xff1976d2),
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    l10n.mediaPreviewTitle,
                    style: const TextStyle(
                      color: Color(0xff111b21),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 24 / 20,
                    ),
                  ),
                  const Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: EdgeInsets.only(right: 22),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: Color(0xff1976d2),
                        size: 30,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 8, 40, 24),
                child: _MediaPreviewBody(
                  path: widget.path,
                  fileName: widget.fileName,
                  isVideo: widget.isVideo,
                  fileSizeBytes: widget.fileSizeBytes,
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xffe5e7eb)),
            Container(
              height: 76,
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
              color: Colors.white,
              child: Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: widget.onSend == null || _sending ? null : _send,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xff1976d2),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xff9ec5ee),
                    disabledForegroundColor: Colors.white,
                    minimumSize: const Size(118, 46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 22),
                  label: Text(_sending ? l10n.mediaSending : l10n.mediaSend),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaPreviewBody extends StatelessWidget {
  const _MediaPreviewBody({
    required this.path,
    required this.fileName,
    required this.isVideo,
    required this.fileSizeBytes,
  });

  final String path;
  final String fileName;
  final bool isVideo;
  final int fileSizeBytes;

  @override
  Widget build(BuildContext context) {
    if (isVideo) {
      return _VideoPreviewCard(
        path: path,
        fileName: fileName,
        fileSizeBytes: fileSizeBytes,
      );
    }

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _BrokenMediaPreview(fileName: fileName),
        ),
      ),
    );
  }
}

class _VideoPreviewCard extends StatefulWidget {
  const _VideoPreviewCard({
    required this.path,
    required this.fileName,
    required this.fileSizeBytes,
  });

  final String path;
  final String fileName;
  final int fileSizeBytes;

  @override
  State<_VideoPreviewCard> createState() => _VideoPreviewCardState();
}

class _VideoPreviewCardState extends State<_VideoPreviewCard> {
  String _posterPath = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadPoster());
  }

  @override
  void didUpdateWidget(covariant _VideoPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      setState(() => _posterPath = '');
      unawaited(_loadPoster());
    }
  }

  Future<void> _loadPoster() async {
    final poster = await _createVideoCover(widget.path);
    if (mounted && poster != null && poster.trim().isNotEmpty) {
      setState(() => _posterPath = poster);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
          color: const Color(0xff111b21),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _LoopingVideoPlayer(
                source: widget.path,
                posterSource: _posterPath,
                muted: true,
              ),
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xff0b141a).withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatMediaFileSize(widget.fileSizeBytes),
                          style: const TextStyle(
                            color: Color(0xffd1d5db),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrokenMediaPreview extends StatelessWidget {
  const _BrokenMediaPreview({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined, size: 56),
          const SizedBox(height: 12),
          Text(fileName, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String _formatMediaFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '$bytes B';
}

Future<_MediaDimensions?> _readImageDimensions(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final dimensions = _MediaDimensions(
      width: image.width,
      height: image.height,
    );
    image.dispose();
    return dimensions;
  } catch (_) {
    return null;
  }
}

Future<String?> _createVideoCover(String videoPath) async {
  if (!Platform.isMacOS) {
    return null;
  }
  final outputDir = await Directory.systemTemp.createTemp('bbp_video_cover_');
  final result = await Process.run('qlmanage', [
    '-t',
    '-s',
    '720',
    '-o',
    outputDir.path,
    videoPath,
  ]);
  if (result.exitCode != 0) {
    return null;
  }
  final basename = videoPath.split(Platform.pathSeparator).last;
  final candidates = [
    File('${outputDir.path}/$basename.png'),
    File('${outputDir.path}/$basename.jpg'),
    File('${outputDir.path}/$basename.jpeg'),
  ];
  for (final candidate in candidates) {
    if (await candidate.exists()) {
      return candidate.path;
    }
  }
  final generated = await outputDir
      .list()
      .where((entity) => entity is File)
      .cast<File>()
      .toList();
  return generated.isEmpty ? null : generated.first.path;
}

class _AttachmentMenu extends StatelessWidget {
  const _AttachmentMenu({required this.onPhotoOrVideo, required this.onSelect});

  final VoidCallback onPhotoOrVideo;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 14,
      shadowColor: const Color(0xff0b141a).withValues(alpha: 0.2),
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AttachmentMenuItem(
              icon: Icons.image_outlined,
              color: Color(0xff7c4dff),
              label: 'Photo Or Video',
              onTap: onPhotoOrVideo,
            ),
            _AttachmentMenuItem(
              icon: Icons.insert_drive_file_outlined,
              color: Color(0xff1e88e5),
              label: 'Document',
              onTap: onSelect,
            ),
            _AttachmentMenuItem(
              icon: Icons.person_outline_rounded,
              color: Color(0xff00a884),
              label: 'Contact',
              onTap: onSelect,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentMenuItem extends StatelessWidget {
  const _AttachmentMenuItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xff111b21),
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiPickerPanel extends StatefulWidget {
  const _EmojiPickerPanel({
    required this.recentTitle,
    required this.smileysTitle,
    required this.onEmojiSelected,
    required this.onEmojiGameSelected,
  });

  final String recentTitle;
  final String smileysTitle;
  final ValueChanged<String> onEmojiSelected;
  final ValueChanged<String> onEmojiGameSelected;

  @override
  State<_EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<_EmojiPickerPanel> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recentEmojis = _desktopChatEmojis.take(2).toList(growable: false);
    return Material(
      elevation: 16,
      shadowColor: const Color(0xff0b141a).withValues(alpha: 0.2),
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: RawScrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        interactive: true,
        radius: const Radius.circular(6),
        thickness: 8,
        thumbColor: const Color(0xffb6bcc1),
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 4),
              sliver: SliverToBoxAdapter(
                child: _EmojiSectionTitle(widget.recentTitle),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: recentEmojis.length,
                itemBuilder: (context, index) {
                  final emoji = recentEmojis[index];
                  return _EmojiPickerTile(
                    tooltip: emoji,
                    child: Text(emoji, style: const TextStyle(fontSize: 30)),
                    onTap: () => widget.onEmojiSelected(emoji),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 4),
              sliver: SliverToBoxAdapter(
                child: _EmojiSectionTitle(widget.smileysTitle),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                ),
                itemCount: _desktopChatEmojis.length + 2,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _EmojiPickerTile(
                      tooltip: 'Dice',
                      child: Image.asset(
                        'assets/chat_emoji_games/chat_dice.gif',
                        width: 32,
                        height: 32,
                      ),
                      onTap: () => widget.onEmojiGameSelected(
                        _EmojiGameSelection.diceType,
                      ),
                    );
                  }
                  if (index == 1) {
                    return _EmojiPickerTile(
                      tooltip: 'Rock-Paper-Scissors',
                      child: const _RpsEmojiPreview(),
                      onTap: () => widget.onEmojiGameSelected(
                        _EmojiGameSelection.rpsType,
                      ),
                    );
                  }
                  final emoji = _desktopChatEmojis[index - 2];
                  return _EmojiPickerTile(
                    tooltip: emoji,
                    child: Text(emoji, style: const TextStyle(fontSize: 30)),
                    onTap: () => widget.onEmojiSelected(emoji),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmojiSectionTitle extends StatelessWidget {
  const _EmojiSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xff667781),
        fontSize: 18,
        height: 25 / 18,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _EmojiPickerTile extends StatelessWidget {
  const _EmojiPickerTile({
    required this.tooltip,
    required this.child,
    required this.onTap,
  });

  final String tooltip;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: const Color(0xffeef1f3),
          splashColor: const Color(0xffdfe5e8),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _RpsEmojiPreview extends StatelessWidget {
  const _RpsEmojiPreview();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 30,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 0,
            child: Image.asset(
              'assets/chat_emoji_games/chat_ic_game_rock.webp',
              width: 20,
              height: 20,
            ),
          ),
          Image.asset(
            'assets/chat_emoji_games/chat_ic_game_scissors.webp',
            width: 20,
            height: 20,
          ),
          Positioned(
            right: 0,
            child: Image.asset(
              'assets/chat_emoji_games/chat_ic_game_paper.webp',
              width: 20,
              height: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmojiGameSelection {
  const _EmojiGameSelection({required this.type, required this.value});

  static const diceType = 'dice';
  static const rpsType = 'rps';

  final String type;
  final int value;

  String get previewText {
    if (type == diceType) {
      return '🎲 $value';
    }
    return switch (value) {
      0 => '✊',
      1 => '✌',
      2 => '✋',
      _ => '✊',
    };
  }

  static String previewFromPayload(Map<String, dynamic>? payload) {
    if (payload == null) {
      return '';
    }
    final type = payload['type']?.toString();
    if (type != diceType && type != rpsType) {
      return '';
    }
    final value = _nullableInt(payload['value']) ?? 0;
    return _EmojiGameSelection(type: type!, value: value).previewText;
  }

  static int? _nullableInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
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
    required this.messages,
    this.avatarUrl,
    this.targetUserId,
    this.roomId,
    this.pinned = false,
    this.delivered = false,
    this.deliveredRead = false,
    this.readReceiptEnabled = true,
    this.isOnline = false,
    this.unread = 0,
  });

  final String name;
  final String message;
  final String time;
  final Color color;
  final String emoji;
  final List<_ChatMessage> messages;
  final String? avatarUrl;
  final int? targetUserId;
  final int? roomId;
  final bool pinned;
  final bool delivered;
  final bool deliveredRead;
  final bool readReceiptEnabled;
  final bool isOnline;
  final int unread;

  _Conversation copyWith({
    String? name,
    String? message,
    String? time,
    String? avatarUrl,
    bool? delivered,
    bool? deliveredRead,
    bool? isOnline,
    int? unread,
  }) {
    return _Conversation(
      name: name ?? this.name,
      message: message ?? this.message,
      time: time ?? this.time,
      color: color,
      emoji: emoji,
      messages: messages,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      targetUserId: targetUserId,
      roomId: roomId,
      pinned: pinned,
      delivered: delivered ?? this.delivered,
      deliveredRead: deliveredRead ?? this.deliveredRead,
      readReceiptEnabled: readReceiptEnabled,
      isOnline: isOnline ?? this.isOnline,
      unread: unread ?? this.unread,
    );
  }
}

class _ConversationData {
  const _ConversationData._();

  static _Conversation fromRecommendedUser(
    AppLocalizations l10n,
    RecommendedUser user,
    _RailTab tab,
  ) {
    final displayName = user.displayName;
    final initial = displayName.characters.isEmpty
        ? '#'
        : displayName.characters.first.toUpperCase();
    return _Conversation(
      name: displayName,
      message: user.isOnline
          ? l10n.workspaceUserOnline
          : l10n.appAccountStatusOffline,
      time: user.isOnline ? '' : _formatRecommendedTime(user.lastLoginTime),
      color: avatarColorFor(user.id),
      emoji: initial,
      avatarUrl: user.avatarUrl,
      targetUserId: user.id,
      roomId: null,
      isOnline: user.isOnline,
      messages: const [],
    );
  }

  static _Conversation fromChatConversation(
    AppLocalizations l10n,
    ChatConversationSummary conversation,
  ) {
    final displayName = conversation.displayName;
    final initial = displayName.characters.isEmpty
        ? '#'
        : displayName.characters.first.toUpperCase();
    return _Conversation(
      name: displayName,
      message: conversation.isOnline
          ? l10n.workspaceUserOnline
          : l10n.appAccountStatusOffline,
      time: '',
      color: avatarColorFor(conversation.peerUserId),
      emoji: initial,
      avatarUrl: conversation.roomImg,
      targetUserId: conversation.peerUserId,
      roomId: conversation.roomId,
      pinned: conversation.topStatus == 1,
      readReceiptEnabled: conversation.readReceipt != 0,
      isOnline: conversation.isOnline,
      messages: const [],
    );
  }

  static String _formatRecommendedTime(DateTime? time) {
    if (time == null) {
      return '';
    }
    final local = time.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static Color avatarColorFor(int id) {
    const colors = [
      Color(0xffffb7ca),
      Color(0xffb7d9ff),
      Color(0xff96e6b3),
      Color(0xffffd166),
      Color(0xffff9f9f),
      Color(0xff74c0fc),
      Color(0xffb197fc),
      Color(0xff63e6be),
      Color(0xffffc078),
      Color(0xff4dabf7),
    ];
    return colors[id.abs() % colors.length];
  }
}

class _ChatMessage {
  const _ChatMessage.incoming({
    required this.text,
    required this.time,
    this.width = 342,
    this.singleLine = false,
    this.media,
  }) : outgoing = false,
       sendStatus = ChatMessageSendStatus.sent;

  const _ChatMessage.outgoing({
    required this.text,
    required this.time,
    this.width = 203,
    this.sendStatus = ChatMessageSendStatus.sent,
    this.media,
  }) : outgoing = true,
       singleLine = true;

  factory _ChatMessage.fromLocal(LocalChatMessage message) {
    final hour = message.createdAt.hour.toString().padLeft(2, '0');
    final minute = message.createdAt.minute.toString().padLeft(2, '0');
    final media = _ChatMedia.fromLocal(message);
    if (message.direction == ChatMessageDirection.incoming) {
      return _ChatMessage.incoming(
        text: message.text,
        time: '$hour:$minute',
        width: media == null
            ? _bubbleWidthFor(message.text)
            : media.bubbleWidth,
        singleLine: message.text.characters.length < 24,
        media: media,
      );
    }
    return _ChatMessage.outgoing(
      text: message.text,
      time: '$hour:$minute',
      width: media == null ? _bubbleWidthFor(message.text) : media.bubbleWidth,
      sendStatus: message.sendStatus,
      media: media,
    );
  }

  final String text;
  final String time;
  final double width;
  final bool outgoing;
  final bool singleLine;
  final ChatMessageSendStatus sendStatus;
  final _ChatMedia? media;

  static double _bubbleWidthFor(String text) {
    final estimated = 72 + text.characters.length * 7.2;
    return estimated.clamp(136, 342).toDouble();
  }
}

class _ChatMedia {
  const _ChatMedia({
    required this.mediaType,
    this.mediaUrl,
    this.mediaCoverUrl,
    this.localPath,
    this.width,
    this.height,
    this.durationSeconds,
  });

  final int mediaType;
  final String? mediaUrl;
  final String? mediaCoverUrl;
  final String? localPath;
  final int? width;
  final int? height;
  final int? durationSeconds;

  bool get isVideo => mediaType == 3;
  bool get isVoice => mediaType == 4;

  Size get previewSize {
    if (isVoice) {
      return const Size(220, 48);
    }
    final mediaWidth = width ?? 0;
    final mediaHeight = height ?? 0;
    if (mediaWidth <= 0 || mediaHeight <= 0) {
      return Size(_mediaBubbleMaxWidth - 8, isVideo ? 150 : 190);
    }
    final aspect = mediaWidth / mediaHeight;
    var displayWidth = _mediaBubbleMaxWidth - 8;
    var displayHeight = displayWidth / aspect;
    if (displayHeight > _mediaBubbleMaxHeight) {
      displayHeight = _mediaBubbleMaxHeight;
      displayWidth = displayHeight * aspect;
    }
    displayWidth = displayWidth.clamp(
      _mediaBubbleMinWidth,
      _mediaBubbleMaxWidth - 8,
    );
    displayHeight = displayHeight.clamp(
      _mediaBubbleMinHeight,
      _mediaBubbleMaxHeight,
    );
    return Size(displayWidth.toDouble(), displayHeight.toDouble());
  }

  double get bubbleWidth => previewSize.width + 8;

  String get viewerSource {
    if (isVideo) {
      final media = mediaUrl?.trim() ?? '';
      if (media.isNotEmpty) {
        return media;
      }
      final local = localPath?.trim() ?? '';
      if (local.isNotEmpty && File(local).existsSync()) {
        return local;
      }
    }
    final media = mediaUrl?.trim() ?? '';
    if (media.isNotEmpty && !isVideo && !isVoice) {
      return media;
    }
    return previewSource;
  }

  String get previewSource {
    final local = localPath?.trim() ?? '';
    if (local.isNotEmpty && File(local).existsSync()) {
      return local;
    }
    final cover = mediaCoverUrl?.trim() ?? '';
    if (cover.isNotEmpty) {
      return cover;
    }
    final media = mediaUrl?.trim() ?? '';
    if (media.isNotEmpty && !isVideo) {
      return media;
    }
    return '';
  }

  static _ChatMedia? fromLocal(LocalChatMessage message) {
    if (message.sendType != 2) {
      return null;
    }
    final payload = _mediaPayloadFromJson(message.msgData);
    final mediaType = _chatMediaInt(payload?['mediaType']) ?? 0;
    if (mediaType != 2 && mediaType != 3 && mediaType != 4) {
      return null;
    }
    final duration = _chatMediaInt(payload?['duration']);
    return _ChatMedia(
      mediaType: mediaType,
      mediaUrl: payload?['media']?.toString(),
      mediaCoverUrl: payload?['mediaCover']?.toString(),
      width: _chatMediaInt(payload?['width']),
      height: _chatMediaInt(payload?['height']),
      durationSeconds: mediaType == 4
          ? _normalizeVoiceDurationSeconds(duration)
          : duration,
      localPath: message.localMediaPath?.trim().isNotEmpty == true
          ? message.localMediaPath
          : payload?['localUrl']?.toString(),
    );
  }
}

int? _chatMediaInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

String _formatVoiceDuration(int seconds) {
  final safeSeconds = max(0, seconds);
  final minutes = safeSeconds ~/ 60;
  final remainingSeconds = safeSeconds % 60;
  return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
}

int? _normalizeVoiceDurationSeconds(int? rawDuration) {
  if (rawDuration == null || rawDuration <= 0) {
    return null;
  }
  // Desktop writes seconds. Android/iOS currently provide milliseconds for
  // voice msgData.duration, which otherwise renders as huge minute values.
  if (rawDuration > _maxVoiceRecordSeconds) {
    return max(1, rawDuration ~/ 1000);
  }
  return rawDuration;
}

Map<String, dynamic>? _mediaPayloadFromJson(String? rawValue) {
  final raw = rawValue?.trim() ?? '';
  if (raw.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return (decoded.first as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
  } catch (_) {
    return null;
  }
  return null;
}

class _IncomingSocketMessage {
  const _IncomingSocketMessage({
    required this.userId,
    required this.roomId,
    required this.sendType,
    required this.previewText,
    this.clientMessageId,
    this.id,
    this.sendTime,
    this.msgDataJson,
  });

  final int? id;
  final int userId;
  final int? roomId;
  final int sendType;
  final String previewText;
  final String? clientMessageId;
  final int? sendTime;
  final String? msgDataJson;

  bool get canDisplay => userId > 0 && previewText.trim().isNotEmpty;

  String get localId {
    final messageId = id;
    if (messageId != null && messageId > 0) {
      return 'server_$messageId';
    }
    return 'socket_${roomId ?? 0}_${userId}_${sendTime ?? 0}_${previewText.hashCode}';
  }

  factory _IncomingSocketMessage.fromJson(Map<String, dynamic> json) {
    final rawMsgData = json['msgData'];
    final directText = _firstNonEmptyString([
      json['msg'],
      json['message'],
      json['content'],
    ]);
    final payload = _parseMsgData(rawMsgData);
    final sendType = _toInt(json['sendType'] ?? json['msgType']);
    final userPayload = _firstMap([
      json['user'],
      json['sendUser'],
      json['senderUser'],
      json['fromUser'],
      payload?['user'],
      payload?['sendUser'],
      payload?['senderUser'],
      payload?['fromUser'],
    ]);
    final payloadText = payload == null
        ? ''
        : _firstNonEmptyString([
            payload['msg'],
            payload['text'],
            payload['content'],
            payload['message'],
            payload['title'],
          ]);
    final emojiGameText = sendType == _emojiGameSendType
        ? _EmojiGameSelection.previewFromPayload(payload)
        : '';
    final mediaText = sendType == 2 ? _mediaPreviewText(payload) : '';
    return _IncomingSocketMessage(
      id: _nullableInt(json['id']),
      userId: _firstPositiveInt([
        json['userId'],
        json['sendUserId'],
        json['senderUserId'],
        json['fromUserId'],
        json['fromId'],
        json['senderId'],
        json['uid'],
        payload?['userId'],
        payload?['sendUserId'],
        payload?['senderUserId'],
        payload?['fromUserId'],
        payload?['fromId'],
        payload?['senderId'],
        payload?['uid'],
        userPayload?['id'],
        userPayload?['userId'],
      ]),
      roomId: _nullableInt(
        json['roomId'] ??
            json['chatRoomId'] ??
            payload?['roomId'] ??
            payload?['chatRoomId'],
      ),
      sendType: sendType,
      clientMessageId: _nullableString(
        json['cid'] ??
            json['clientMessageId'] ??
            payload?['cid'] ??
            payload?['clientMessageId'],
      ),
      previewText: directText.isNotEmpty
          ? directText
          : (payloadText.isNotEmpty
                ? payloadText
                : (emojiGameText.isNotEmpty
                      ? emojiGameText
                      : (mediaText.isNotEmpty
                            ? mediaText
                            : _fallbackText(sendType)))),
      sendTime: _nullableInt(
        json['sendTime'] ?? json['createTime'] ?? json['timestamp'],
      ),
      msgDataJson: _normalizeMsgData(rawMsgData),
    );
  }

  static String? _normalizeMsgData(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value.trim().isEmpty ? null : value;
    }
    try {
      return jsonEncode(value);
    } catch (_) {
      return value.toString();
    }
  }

  static Map<String, dynamic>? _parseMsgData(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty ||
        !((raw.startsWith('{') && raw.endsWith('}')) ||
            (raw.startsWith('[') && raw.endsWith(']')))) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
        return (decoded.first as Map).map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Map<String, dynamic>? _firstMap(List<Object?> values) {
    for (final value in values) {
      if (value is Map<String, dynamic>) {
        return value;
      }
      if (value is Map) {
        return value.map((key, value) => MapEntry(key.toString(), value));
      }
    }
    return null;
  }

  static String _fallbackText(int sendType) {
    return switch (sendType) {
      2 => '[Media]',
      6 => '[Message recalled]',
      43 => '[Gift]',
      _emojiGameSendType => '[Emoji]',
      _ => '',
    };
  }

  static String _mediaPreviewText(Map<String, dynamic>? payload) {
    final mediaType = _toInt(payload?['mediaType']);
    return switch (mediaType) {
      2 => '[Photo]',
      3 => '[Video]',
      4 => '[Voice]',
      _ => '',
    };
  }

  static String _firstNonEmptyString(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  static int _toInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _firstPositiveInt(List<Object?> values) {
    for (final value in values) {
      final parsed = _toInt(value);
      if (parsed > 0) {
        return parsed;
      }
    }
    return 0;
  }

  static int? _nullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty || text == '0' ? null : text;
  }
}
