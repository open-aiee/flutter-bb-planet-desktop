import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../../app/locale/app_locale_provider.dart';
import '../../../core/security/desktop_device_id.dart';
import '../../../core/security/secure_store_provider.dart';
import '../../../core/websocket/im_session_manager.dart';
import '../../../core/websocket/im_socket_client.dart' show ImSyncRecordAck;
import '../../../l10n/generated/app_localizations.dart';
import '../../app_account_auth/application/app_account_auth_controller.dart';
import '../../app_account_auth/domain/app_user_session.dart';
import '../../app_account_auth/presentation/app_account_panel.dart';
import '../../messages/data/direct_chat_api.dart';
import '../../messages/data/local_chat_message_store.dart';
import '../../messages/domain/local_chat_message.dart';
import '../../operator_auth/application/operator_auth_controller.dart';
import '../../recommended_users/data/recommended_user_api.dart';
import '../../recommended_users/domain/recommended_user.dart';

enum _RailTab { chats, updates, communities, calls }

const _maxChatMessageLength = 3000;
const _collapsedMessageMaxLines = 15;

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
        onAppAccountTap: () => showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AppAccountLoginDialog(),
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
    required this.onAppAccountTap,
    required this.onSettingsTap,
  });

  final String operatorName;
  final String appAccountName;
  final AppUserSession? appAccountSession;
  final bool appAccountOnline;
  final bool appAccountBusy;
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
  int _loadRequestId = 0;
  int _searchRequestId = 0;
  Timer? _searchDebounce;
  Timer? _activeConversationSyncTimer;
  StreamSubscription<Map<String, dynamic>>? _incomingMessageSubscription;
  bool _isActiveConversationSyncing = false;
  String _searchQuery = '';
  String? _searchNotice;
  final Map<String, String> _drafts = {};
  List<_Conversation> _searchConversations = const [];
  final Map<_RailTab, List<_Conversation>> _remoteConversations = {};
  final Map<_RailTab, String> _remoteNotices = {};
  final Map<int, int> _directRoomIds = {};
  final Map<String, List<LocalChatMessage>> _storedMessages = {};
  final Map<int, LocalChatMessage> _recentMessagesByPeer = {};

  @override
  void initState() {
    super.initState();
    _incomingMessageSubscription = ref
        .read(imSessionManagerProvider)
        .messageStream
        .listen(_handleIncomingSocketMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncImSocketSession();
      unawaited(_loadRecentConversationPreviews());
    });
  }

  @override
  void didUpdateWidget(covariant _HomeScreenMainWindow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appAccountSession?.certificate !=
        widget.appAccountSession?.certificate) {
      _syncImSocketSession();
      unawaited(_loadRecentConversationPreviews());
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _activeConversationSyncTimer?.cancel();
    unawaited(_incomingMessageSubscription?.cancel());
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
              messages: messages,
              draft: draftKey == null ? '' : _drafts[draftKey] ?? '',
              l10n: l10n,
              onDraftChanged: (value) {
                if (draftKey != null) {
                  _drafts[draftKey] = value;
                }
              },
              onSend: selectedConversation == null
                  ? null
                  : (text) => _sendLocalMessage(selectedConversation, text),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTab(_RailTab tab) async {
    if (tab == _selectedTab && !_isConversationLoading) {
      return;
    }

    final requestId = ++_loadRequestId;
    setState(() {
      _selectedTab = tab;
      _selectedConversationIndex = 0;
      _isConversationLoading = tab != _RailTab.chats;
      _remoteNotices.remove(tab);
      if (tab != _RailTab.chats) {
        _remoteConversations[tab] = const [];
      }
    });

    if (tab == _RailTab.chats) {
      return;
    }

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
      final users = tab == _RailTab.communities
          ? await userApi.fetchOnlineUsersFromDynamicPage(
              certificate: session.certificate,
              deviceId: deviceId,
              lang: requestLang,
            )
          : await userApi.fetchFriendRecommendations(
              certificate: session.certificate,
              deviceId: deviceId,
              lang: requestLang,
            );
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
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
      _RailTab.chats => _localRecentConversations(),
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
            latest.sendStatus == ChatMessageSendStatus.sent,
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

  List<_Conversation> _localRecentConversations() {
    final latestMessages = _recentMessagesByPeer.values.toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return latestMessages.map((message) {
      final peerUserId = message.peerUserId;
      final label = 'Beepian$peerUserId';
      return _Conversation(
        name: label,
        message: _conversationPreviewText(message.text),
        time: _formatConversationTime(message.createdAt),
        color: _ConversationData.avatarColorFor(peerUserId),
        emoji: label.characters.first.toUpperCase(),
        targetUserId: peerUserId,
        roomId: message.roomId,
        delivered:
            message.direction == ChatMessageDirection.outgoing &&
            message.sendStatus == ChatMessageSendStatus.sent,
        unread: message.direction == ChatMessageDirection.incoming ? 1 : 0,
        messages: const [],
      );
    }).toList();
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
  }

  int? _peerUserIdForRoomId(int roomId) {
    for (final entry in _directRoomIds.entries) {
      if (entry.value == roomId) {
        return entry.key;
      }
    }
    return null;
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
      current[existingIndex] = localMessage;
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
        setState(_recentMessagesByPeer.clear);
      }
      return;
    }
    final store = await ref.read(localChatMessageStoreProvider.future);
    final latest = await store.loadLatestByAppUser(appUserId: session.id);
    if (!mounted || widget.appAccountSession?.id != session.id) {
      return;
    }
    setState(() {
      _recentMessagesByPeer
        ..clear()
        ..addAll(latest);
    });
    final selected = _selectedConversation();
    if (selected != null && selected.targetUserId != null) {
      _activateConversation(selected);
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
}

class _LeftSection extends StatelessWidget {
  const _LeftSection({
    required this.operatorName,
    required this.appAccountName,
    required this.appAccountOnline,
    required this.appAccountBusy,
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
                    const Icon(
                      Icons.done_all,
                      size: 16,
                      color: Color(0xff53bdeb),
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
    this.size = 60,
  });

  final Color color;
  final String label;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    return Container(
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
    required this.messages,
    required this.draft,
    required this.l10n,
    required this.onDraftChanged,
    required this.onSend,
  });

  final _Conversation? conversation;
  final List<_ChatMessage> messages;
  final String draft;
  final AppLocalizations l10n;
  final ValueChanged<String> onDraftChanged;
  final ValueChanged<String>? onSend;

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
      return _ChatEmptyState(message: widget.l10n.selectConversationFirst);
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
              onlineText: widget.l10n.workspaceUserOnline,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 81,
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
  const _ChatHeader({required this.conversation, required this.onlineText});

  final _Conversation conversation;
  final String onlineText;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 81,
      color: const Color(0xfff7f7fc),
      padding: const EdgeInsets.only(left: 24, right: 18, top: 16),
      child: Row(
        children: [
          _LetterAvatar(
            color: conversation.color,
            label: conversation.emoji,
            avatarUrl: conversation.avatarUrl,
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
                Row(
                  children: [
                    const _OnlineDot(),
                    const SizedBox(width: 5),
                    Text(
                      onlineText,
                      style: const TextStyle(
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
                child: _ExpandableMessageText(
                  text,
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
    required this.status,
  });

  final double width;
  final String text;
  final String time;
  final ChatMessageSendStatus status;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(9, 6, 7, 3),
          decoration: _bubbleDecoration(const Color(0xffd9fdd3)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _ExpandableMessageText(
                  text,
                  style: const TextStyle(
                    color: Color(0xff111b21),
                    fontSize: 14.2,
                    height: 19 / 14.2,
                  ),
                ),
              ),
              const SizedBox(height: 1),
              Row(
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final textDirection = Directionality.of(context);
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
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
              style: widget.style,
            ),
            if (isOverflowing && !_expanded)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => setState(() => _expanded = true),
                  child: Text(
                    l10n.messageReadMore,
                    style: widget.style.copyWith(
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
    super.key,
  });

  final String initialValue;
  final String hintText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSend;

  @override
  State<_MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<_MessageInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _send() {
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
              child: Shortcuts(
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
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(_maxChatMessageLength),
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
                          contentPadding: EdgeInsets.fromLTRB(24, 12, 24, 12),
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
            ),
          ),
          const SizedBox(width: 24),
          IconButton(
            tooltip: widget.hintText,
            onPressed: widget.onSend == null ? null : _send,
            icon: Icon(
              _controller.text.trim().isEmpty
                  ? Icons.mic_rounded
                  : Icons.send_rounded,
              color: const Color(0xff54656f),
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
  final int unread;

  _Conversation copyWith({
    String? message,
    String? time,
    bool? delivered,
    int? unread,
  }) {
    return _Conversation(
      name: name,
      message: message ?? this.message,
      time: time ?? this.time,
      color: color,
      emoji: emoji,
      messages: messages,
      avatarUrl: avatarUrl,
      targetUserId: targetUserId,
      roomId: roomId,
      pinned: pinned,
      delivered: delivered ?? this.delivered,
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
      message: '',
      time: user.isOnline
          ? l10n.workspaceUserOnline
          : _formatRecommendedTime(user.lastLoginTime),
      color: avatarColorFor(user.id),
      emoji: initial,
      avatarUrl: user.avatarUrl,
      targetUserId: user.id,
      roomId: null,
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
  }) : outgoing = false,
       sendStatus = ChatMessageSendStatus.sent;

  const _ChatMessage.outgoing({
    required this.text,
    required this.time,
    this.width = 203,
    this.sendStatus = ChatMessageSendStatus.sent,
  }) : outgoing = true,
       singleLine = true;

  factory _ChatMessage.fromLocal(LocalChatMessage message) {
    final hour = message.createdAt.hour.toString().padLeft(2, '0');
    final minute = message.createdAt.minute.toString().padLeft(2, '0');
    if (message.direction == ChatMessageDirection.incoming) {
      return _ChatMessage.incoming(
        text: message.text,
        time: '$hour:$minute',
        width: _bubbleWidthFor(message.text),
        singleLine: message.text.characters.length < 24,
      );
    }
    return _ChatMessage.outgoing(
      text: message.text,
      time: '$hour:$minute',
      width: _bubbleWidthFor(message.text),
      sendStatus: message.sendStatus,
    );
  }

  final String text;
  final String time;
  final double width;
  final bool outgoing;
  final bool singleLine;
  final ChatMessageSendStatus sendStatus;

  static double _bubbleWidthFor(String text) {
    final estimated = 72 + text.characters.length * 7.2;
    return estimated.clamp(136, 342).toDouble();
  }
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
  });

  final int? id;
  final int userId;
  final int? roomId;
  final int sendType;
  final String previewText;
  final String? clientMessageId;
  final int? sendTime;

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
    final sendType = _toInt(json['sendType'] ?? json['msgType']);
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
          : (payloadText.isNotEmpty ? payloadText : _fallbackText(sendType)),
      sendTime: _nullableInt(
        json['sendTime'] ?? json['createTime'] ?? json['timestamp'],
      ),
    );
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
