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
import '../../app_account_auth/domain/app_account_history_entry.dart';
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

String _chatPreviewText(String text) {
  return text
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();
}

String _chatListTimeText(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
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

String _accountDisplayName(AppAccountHistoryEntry account) {
  final displayName = account.displayName.trim();
  if (displayName.isNotEmpty) {
    return displayName;
  }
  final email = account.email.trim();
  if (email.isNotEmpty) {
    return email;
  }
  return account.id > 0 ? 'Beepian${account.id}' : 'BB Planet';
}

String _accountInitial(String label) {
  return label.characters.isEmpty ? 'B' : label.characters.first.toUpperCase();
}

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
  int? _selectedConversationPeerUserId;
  _Conversation? _activeConversation;
  bool _isConversationLoading = false;
  bool _isAppAccountListMode = false;
  bool _isAppAccountListLoading = false;
  bool _isAppAccountAvatarUpdating = false;
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
  String? _appAccountListNotice;
  final Map<String, String> _drafts = {};
  List<_Conversation> _chatConversations = const [];
  List<_Conversation> _searchConversations = const [];
  List<AppAccountHistoryEntry> _appAccountEntries = const [];
  int? _selectedAppAccountInfoId;
  final Map<_RailTab, List<_Conversation>> _remoteConversations = {};
  final Map<_RailTab, String> _remoteNotices = {};
  final Map<int, int> _directRoomIds = {};
  final Map<int, Future<int?>> _directRoomRequests = {};
  final Map<String, List<LocalChatMessage>> _storedMessages = {};
  final Map<int, LocalChatMessage> _recentMessagesByPeer = {};
  final Map<int, int> _localUnreadByPeer = {};
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
      final wasAppAccountListMode = _isAppAccountListMode;
      _resetAccountScopedState();
      _syncImSocketSession();
      unawaited(_loadRecentConversationPreviews());
      unawaited(_loadChatConversations());
      if (wasAppAccountListMode) {
        unawaited(_openAppAccountListMode());
      }
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
    final conversations = _isAppAccountListMode
        ? const <_Conversation>[]
        : _withRecentMessagePreviews(
            isSearching
                ? _searchConversations
                : _conversationsForTab(l10n, _selectedTab),
          );
    final chatBadge = _chatBadgeText();
    final selectedConversationIndex = _selectedIndexIn(conversations);
    final selectedConversation = _selectedConversationFrom(conversations);
    final selectedAppAccount = _isAppAccountListMode
        ? _selectedAppAccountEntry()
        : null;
    final storageKey = selectedConversation == null
        ? null
        : _storageKeyFor(selectedConversation);
    final draftKey = storageKey == null ? null : 'draft:$storageKey';
    final messages = selectedConversation == null
        ? const <_ChatMessage>[]
        : _messagesForConversation(selectedConversation);
    debugPrint(
      '[CHAT_OPS][UI][BUILD_SELECTION] '
      'selectedPeer=${selectedConversation?.targetUserId} '
      'selectedRoom=${selectedConversation?.roomId} '
      'activePeer=${_activeConversation?.targetUserId} '
      'listIndex=$selectedConversationIndex '
      'listCount=${conversations.length} messages=${messages.length} '
      'canSend=${selectedConversation != null}',
    );

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
            selectedConversationIndex: selectedConversation == null
                ? -1
                : selectedConversationIndex,
            conversations: conversations,
            isConversationLoading: _isAppAccountListMode
                ? _isAppAccountListLoading
                : isSearching
                ? _isSearchLoading
                : _isConversationLoading,
            emptyMessage: _isAppAccountListMode
                ? (_appAccountListNotice ?? l10n.appAccountListEmpty)
                : _emptyMessageFor(l10n, isSearching: isSearching),
            searchQuery: _searchQuery,
            appAccountListMode: _isAppAccountListMode,
            appAccounts: _appAccountEntries,
            selectedAppAccountIndex: _selectedAppAccountIndex(),
            onTabSelected: _selectTab,
            onConversationSelected: (index) {
              final safeIndex = index.clamp(0, conversations.length - 1);
              final conversation = conversations[safeIndex];
              debugPrint(
                '[CHAT_OPS][UI][SELECT_CONVERSATION] index=$safeIndex '
                'peer=${conversation.targetUserId} room=${conversation.roomId} '
                'name=${conversation.name}',
              );
              setState(() {
                _selectedConversationPeerUserId = conversation.targetUserId;
                _activeConversation = conversation;
              });
              _activateConversation(conversation);
            },
            onAppAccountSelected: _selectAppAccountInfo,
            onSearchChanged: _onSearchChanged,
            onAppAccountTap: _openAppAccountListMode,
            onAppAccountDialogTap: _openAppAccountDialog,
            onSettingsTap: widget.onSettingsTap,
            chatBadge: chatBadge,
            l10n: l10n,
          ),
          Expanded(
            child: _isAppAccountListMode
                ? _AppAccountInfoSection(
                    account: selectedAppAccount,
                    l10n: l10n,
                    isCurrent:
                        selectedAppAccount != null &&
                        widget.appAccountSession?.id == selectedAppAccount.id,
                    isAvatarUpdating: _isAppAccountAvatarUpdating,
                    onAvatarTap: _pickAndUploadAppAccountAvatar,
                  )
                : _ChatSection(
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
                        : (text) {
                            final activeConversation =
                                _selectedConversation() ?? selectedConversation;
                            debugPrint(
                              '[CHAT_OPS][UI][ON_SEND] '
                              'displayPeer=${selectedConversation.targetUserId} '
                              'activePeer=${activeConversation.targetUserId} '
                              'activeRoom=${activeConversation.roomId} '
                              'textLength=${text.trim().length}',
                            );
                            _sendLocalMessage(activeConversation, text);
                          },
                    onSendEmojiGame: selectedConversation == null
                        ? null
                        : (game) => _sendEmojiGameMessage(
                            _selectedConversation() ?? selectedConversation,
                            game,
                          ),
                    onSendMedia: selectedConversation == null
                        ? null
                        : (media) => _sendMediaMessage(
                            _selectedConversation() ?? selectedConversation,
                            media,
                          ),
                    onSendVoice: selectedConversation == null
                        ? null
                        : (voice) => _sendVoiceMessage(
                            _selectedConversation() ?? selectedConversation,
                            voice,
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTab(_RailTab tab) async {
    if (!_isAppAccountListMode &&
        tab == _selectedTab &&
        !_isConversationLoading &&
        (tab == _RailTab.chats
            ? _chatConversations.isNotEmpty
            : (_remoteConversations[tab]?.isNotEmpty ?? false))) {
      return;
    }

    setState(() {
      _isAppAccountListMode = false;
      _selectedAppAccountInfoId = null;
      _selectedTab = tab;
      _selectedConversationPeerUserId = null;
      _activeConversation = null;
    });

    if (tab == _RailTab.chats) {
      unawaited(_loadChatConversations());
      return;
    }

    await _loadRemoteUsersForTab(tab);
  }

  Future<void> _openAppAccountListMode() async {
    setState(() {
      _isAppAccountListMode = true;
      _selectedConversationPeerUserId = null;
      _activeConversation = null;
      _searchQuery = '';
    });
    await _loadAppAccountList();
  }

  Future<void> _openAppAccountDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppAccountHistoryDialog(showCloseButton: true),
    );
    if (!mounted || !_isAppAccountListMode) {
      return;
    }
    await _loadAppAccountList();
  }

  Future<void> _loadAppAccountList() async {
    final requestId = ++_loadRequestId;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isAppAccountListLoading = true;
      _appAccountListNotice = null;
    });
    try {
      final rawAccounts = await ref
          .read(appAccountAuthControllerProvider.notifier)
          .readLoginHistory();
      final accounts = _mergeCurrentAppAccount(rawAccounts);
      if (!mounted || requestId != _loadRequestId || !_isAppAccountListMode) {
        return;
      }
      final currentId = widget.appAccountSession?.id;
      setState(() {
        _appAccountEntries = accounts;
        _selectedAppAccountInfoId =
            _selectedAppAccountInfoId ??
            (currentId != null && accounts.any((item) => item.id == currentId)
                ? currentId
                : accounts.firstOrNull?.id);
        _appAccountListNotice = accounts.isEmpty
            ? l10n.appAccountListEmpty
            : null;
        _isAppAccountListLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      setState(() {
        _appAccountEntries = const [];
        _selectedAppAccountInfoId = null;
        _appAccountListNotice = l10n.appAccountListLoadFailed;
        _isAppAccountListLoading = false;
      });
    }
  }

  List<AppAccountHistoryEntry> _mergeCurrentAppAccount(
    List<AppAccountHistoryEntry> accounts,
  ) {
    final session = widget.appAccountSession;
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
      return accounts
          .map(
            (account) =>
                (session.id > 0 && account.id == session.id) ||
                    (session.email.trim().isNotEmpty &&
                        account.email.trim().toLowerCase() ==
                            session.email.trim().toLowerCase())
                ? account.copyWith(
                    displayName: session.displayName,
                    avatarUrl: session.avatarUrl ?? account.avatarUrl,
                    token: session.certificate,
                    updatedAt: DateTime.now(),
                  )
                : account,
          )
          .toList();
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

  void _selectAppAccountInfo(int index) {
    if (index < 0 || index >= _appAccountEntries.length) {
      return;
    }
    setState(() {
      _selectedAppAccountInfoId = _appAccountEntries[index].id;
    });
  }

  Future<void> _pickAndUploadAppAccountAvatar(
    AppAccountHistoryEntry account,
  ) async {
    if (_isAppAccountAvatarUpdating) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final certificate = account.token.trim().isNotEmpty
        ? account.token.trim()
        : widget.appAccountSession?.certificate.trim() ?? '';
    if (certificate.isEmpty) {
      _showWorkspaceNotice(l10n.workspaceUsersLoginRequired);
      return;
    }
    final requestLang = _requestLangOf(context);

    final result = await FilePicker.platform.pickFiles(
      dialogTitle: l10n.appAccountAvatarPickerTitle,
      initialDirectory: _downloadsDirectoryPath(),
      type: FileType.custom,
      allowedExtensions: _chatImageExtensions,
      allowMultiple: false,
      withData: false,
      withReadStream: false,
      lockParentWindow: true,
    );
    final pickedFile = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    final path = pickedFile?.path;
    if (path == null || path.trim().isEmpty) {
      return;
    }
    if (!_chatImageExtensions.contains(_fileExtension(path))) {
      _showWorkspaceNotice(l10n.mediaUnsupportedFile);
      return;
    }

    setState(() => _isAppAccountAvatarUpdating = true);
    try {
      final sessionDeviceId = widget.appAccountSession?.deviceId.trim() ?? '';
      final deviceId = sessionDeviceId.isNotEmpty
          ? sessionDeviceId
          : await DesktopDeviceId(
              secureStore: ref.read(secureStoreProvider),
            ).getOrCreate();
      final avatarUrl = await ref
          .read(chatMediaUploadApiProvider)
          .uploadAvatarImage(
            path: path,
            certificate: certificate,
            deviceId: deviceId,
            lang: requestLang,
          );
      await ref
          .read(appAccountAuthApiProvider)
          .updateAvatar(
            avatarUrl: avatarUrl,
            certificate: certificate,
            deviceId: deviceId,
            lang: requestLang,
          );
      await ref
          .read(appAccountAuthControllerProvider.notifier)
          .updateHistoryAvatar(account: account, avatarUrl: avatarUrl);
      if (!mounted) {
        return;
      }
      setState(() {
        _appAccountEntries = _appAccountEntries
            .map(
              (entry) => entry.id == account.id
                  ? entry.copyWith(
                      avatarUrl: avatarUrl,
                      updatedAt: DateTime.now(),
                    )
                  : entry,
            )
            .toList();
      });
      _showWorkspaceNotice(l10n.appAccountAvatarUploadSuccess);
    } catch (_) {
      if (mounted) {
        _showWorkspaceNotice(l10n.appAccountAvatarUploadFailed);
      }
    } finally {
      if (mounted) {
        setState(() => _isAppAccountAvatarUpdating = false);
      }
    }
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
        _selectedConversationPeerUserId = null;
        _activeConversation = null;
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isSearchLoading = true;
      _searchNotice = null;
      _selectedConversationPeerUserId = null;
      _activeConversation = null;
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
        return conversation.copyWith(unread: _effectiveUnread(conversation));
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
        unread: latest.direction == ChatMessageDirection.outgoing
            ? 0
            : _effectiveUnread(conversation),
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

  String? _chatBadgeText() {
    final unread = _chatConversationsWithLocalFallback().fold<int>(
      0,
      (total, conversation) => conversation.nodisturbStatus == 0
          ? total + _effectiveUnread(conversation)
          : total,
    );
    if (unread <= 0) {
      return null;
    }
    return unread > 99 ? '99+' : unread.toString();
  }

  int _effectiveUnread(_Conversation conversation) {
    final peerUserId = conversation.targetUserId;
    if (peerUserId == null || peerUserId <= 0) {
      return conversation.unread;
    }
    return _localUnreadByPeer[peerUserId] ?? conversation.unread;
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
    final peerUserId = conversation.targetUserId;
    if (peerUserId != null && peerUserId > 0) {
      setState(() {
        _localUnreadByPeer[peerUserId] = 0;
      });
      unawaited(_persistUnreadCount(peerUserId, 0));
    }
    unawaited(_loadStoredMessages(conversation));
    if (peerUserId == null || peerUserId <= 0) {
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
    return _selectedConversationFrom(conversations);
  }

  _Conversation? _selectedConversationFrom(List<_Conversation> conversations) {
    final selectedPeerUserId = _selectedConversationPeerUserId;
    if (selectedPeerUserId == null || selectedPeerUserId <= 0) {
      return null;
    }
    final index = _selectedIndexIn(conversations);
    if (index >= 0) {
      return conversations[index];
    }
    final active = _activeConversation;
    if (active?.targetUserId == selectedPeerUserId) {
      return active;
    }
    return null;
  }

  int _selectedIndexIn(List<_Conversation> conversations) {
    if (conversations.isEmpty) {
      return -1;
    }
    final selectedPeerUserId = _selectedConversationPeerUserId;
    if (selectedPeerUserId != null && selectedPeerUserId > 0) {
      final index = conversations.indexWhere(
        (conversation) => conversation.targetUserId == selectedPeerUserId,
      );
      if (index >= 0) {
        return index;
      }
    }
    return -1;
  }

  int _selectedAppAccountIndex() {
    final selectedId = _selectedAppAccountInfoId;
    if (selectedId == null || selectedId <= 0) {
      return -1;
    }
    return _appAccountEntries.indexWhere((account) => account.id == selectedId);
  }

  AppAccountHistoryEntry? _selectedAppAccountEntry() {
    final index = _selectedAppAccountIndex();
    if (index < 0 || index >= _appAccountEntries.length) {
      return null;
    }
    return _appAccountEntries[index];
  }

  int? _roomIdFor(_Conversation conversation) {
    final peerUserId = conversation.targetUserId;
    if (peerUserId != null && _directRoomIds[peerUserId] != null) {
      return _directRoomIds[peerUserId];
    }
    return conversation.roomId;
  }

  bool _isCurrentAppSession(AppUserSession session) {
    final current = widget.appAccountSession;
    return mounted &&
        current?.id == session.id &&
        current?.certificate == session.certificate;
  }

  Future<int?> _ensureConversationRoomId(
    _Conversation conversation, {
    bool forceStart = false,
  }) async {
    final session = widget.appAccountSession;
    final peerUserId = conversation.targetUserId;
    final existingRoomId = _roomIdFor(conversation);
    if (!forceStart && existingRoomId != null && existingRoomId > 0) {
      return existingRoomId;
    }
    if (session == null || peerUserId == null || peerUserId <= 0) {
      return null;
    }
    final pendingRequest = _directRoomRequests[peerUserId];
    if (pendingRequest != null) {
      debugPrint(
        '[CHAT_OPS][LOCAL][ROOM_REUSE_PENDING] sender=${session.id} '
        'peer=$peerUserId forceStart=$forceStart existing=$existingRoomId',
      );
      return pendingRequest;
    }

    final request = _openConversationRoom(conversation, session, peerUserId);
    _directRoomRequests[peerUserId] = request;
    try {
      return await request;
    } finally {
      if (identical(_directRoomRequests[peerUserId], request)) {
        _directRoomRequests.remove(peerUserId);
      }
    }
  }

  Future<int?> _openConversationRoom(
    _Conversation conversation,
    AppUserSession session,
    int peerUserId,
  ) async {
    final existingRoomId = _roomIdFor(conversation);
    final requestLang = _requestLangOf(context);
    final l10n = AppLocalizations.of(context);

    final deviceId = await DesktopDeviceId(
      secureStore: ref.read(secureStoreProvider),
    ).getOrCreate();
    debugPrint(
      '[CHAT_OPS][LOCAL][ROOM_START] sender=${session.id} '
      'peer=$peerUserId existing=$existingRoomId',
    );
    final DirectChatStartResult room;
    try {
      room = await ref
          .read(directChatApiProvider)
          .startDirectChat(
            peerUserId: peerUserId,
            certificate: session.certificate,
            deviceId: deviceId,
            lang: requestLang,
          );
    } catch (error) {
      debugPrint(
        '[CHAT_OPS][LOCAL][ROOM_FAILED] sender=${session.id} '
        'peer=$peerUserId error=$error',
      );
      rethrow;
    }
    if (!_isCurrentAppSession(session)) {
      debugPrint(
        '[CHAT_OPS][LOCAL][ROOM_SKIP] reason=session_changed '
        'sender=${session.id} peer=$peerUserId room=${room.roomId}',
      );
      return null;
    }
    if (room.fromUserId != session.id || room.toUserId != peerUserId) {
      debugPrint(
        '[CHAT_OPS][LOCAL][ROOM_SKIP] reason=participant_mismatch '
        'sender=${session.id} peer=$peerUserId room=${room.roomId} '
        'from=${room.fromUserId} to=${room.toUserId}',
      );
      return null;
    }
    if (room.personalChatStatus != 1) {
      debugPrint(
        '[CHAT_OPS][LOCAL][ROOM_SKIP] reason=personal_chat_status '
        'sender=${session.id} peer=$peerUserId room=${room.roomId} '
        'status=${room.personalChatStatus}',
      );
      throw DirectChatException(
        _personalChatStatusMessage(l10n, room.personalChatStatus),
      );
    }
    _directRoomIds[peerUserId] = room.roomId;
    debugPrint(
      '[CHAT_OPS][LOCAL][ROOM] sender=${session.id} peer=$peerUserId '
      'room=${room.roomId} from=${room.fromUserId} to=${room.toUserId} '
      'status=${room.personalChatStatus} deduct=${room.deductStatus} '
      'chatFee=${room.chatFee}',
    );
    return room.roomId;
  }

  String _personalChatStatusMessage(AppLocalizations l10n, int status) {
    return switch (status) {
      2 => l10n.chatPrivateAccountBlocked,
      3 => l10n.chatYouBlockedPeer,
      4 => l10n.chatYouWereBlocked,
      5 => l10n.chatPeerClosedPrivateChat,
      _ => l10n.chatOpenFailed,
    };
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
    debugPrint(
      '[CHAT_OPS][SEND][ENTRY] sender=${session?.id} peer=$peerUserId '
      'room=${conversation.roomId} rawLength=${text.length} '
      'trimLength=${messageText.length}',
    );
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

    debugPrint(
      '[CHAT_OPS][SEND][LOCAL_STORE_START] sender=${session.id} '
      'peer=$peerUserId local=${localMessage.localId}',
    );
    final storeFuture = ref
        .read(localChatMessageStoreProvider.future)
        .timeout(
          const Duration(milliseconds: 900),
          onTimeout: () =>
              throw TimeoutException('Local message store open timeout.'),
        );
    unawaited(
      _upsertLocalMessageInBackground(
        storeFuture: storeFuture,
        message: localMessage,
        phase: 'send_pending',
      ),
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

    var sendStage = 'prepare';
    try {
      debugPrint(
        '[CHAT_OPS][SEND][START] type=text '
        'sender=${session.id} peer=$peerUserId local=${localMessage.localId}',
      );
      sendStage = 'open_room';
      final roomId = await _ensureConversationRoomId(conversation);
      if (roomId == null || roomId <= 0) {
        throw const DirectChatException('Unable to open chat.');
      }
      if (!_isCurrentAppSession(session)) {
        return;
      }
      final updated = localMessage.copyWith(
        roomId: roomId,
        sendStatus: ChatMessageSendStatus.pending,
        updatedAt: DateTime.now(),
      );
      unawaited(
        _upsertLocalMessageInBackground(
          storeFuture: storeFuture,
          message: updated,
          phase: 'send_room',
        ),
      );
      if (!_isCurrentAppSession(session)) {
        return;
      }
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=send_room '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'local=${updated.localId}',
      );
      _replaceStoredMessage(conversation, updated);

      sendStage = 'send_socket';
      final ack = await ref
          .read(imSessionManagerProvider)
          .sendTextMessage(
            senderUserId: session.id,
            roomId: roomId,
            text: messageText,
            clientMessageId: clientMessageId,
          );
      if (!_isCurrentAppSession(session)) {
        return;
      }
      debugPrint(
        '[CHAT_OPS][SEND][ACK] type=text sender=${session.id} '
        'peer=$peerUserId room=$roomId cid=$clientMessageId '
        'success=${ack.success} server=${ack.serverMessageId} '
        'event=${ack.event} message=${ack.message} raw=${ack.rawPayload}',
      );
      final completed = updated.copyWith(
        sendStatus: ack.success
            ? ChatMessageSendStatus.sent
            : ChatMessageSendStatus.failed,
        serverMessageId: ack.serverMessageId?.toString(),
        errorMessage: ack.success ? null : ack.failureSummary(),
        updatedAt: DateTime.now(),
      );
      unawaited(
        _upsertLocalMessageInBackground(
          storeFuture: storeFuture,
          message: completed,
          phase: 'send_completed',
        ),
      );
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=send_completed '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'local=${completed.localId} server=${completed.serverMessageId} '
        'status=${completed.sendStatus.name} error=${completed.errorMessage}',
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
        errorMessage: 'stage=$sendStage; error=$error',
        updatedAt: DateTime.now(),
      );
      unawaited(
        _upsertLocalMessageInBackground(
          storeFuture: storeFuture,
          message: failed,
          phase: 'send_failed',
        ),
      );
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=send_failed '
        'sender=${session.id} peer=$peerUserId local=${failed.localId} '
        'stage=$sendStage error=$error',
      );
      _replaceStoredMessage(conversation, failed);
    }
  }

  Future<void> _upsertLocalMessageInBackground({
    required Future<LocalChatMessageStore> storeFuture,
    required LocalChatMessage message,
    required String phase,
  }) async {
    try {
      final store = await storeFuture;
      debugPrint(
        '[CHAT_OPS][SEND][LOCAL_STORE_READY] sender=${message.appUserId} '
        'peer=${message.peerUserId} local=${message.localId} phase=$phase',
      );
      await store
          .upsert(message)
          .timeout(
            const Duration(milliseconds: 900),
            onTimeout: () =>
                throw TimeoutException('Local message $phase upsert timeout.'),
          );
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=$phase '
        'sender=${message.appUserId} peer=${message.peerUserId} '
        'room=${message.roomId} local=${message.localId}',
      );
    } catch (error) {
      debugPrint(
        '[CHAT_OPS][SEND][LOCAL_STORE_FAILED] '
        'sender=${message.appUserId} peer=${message.peerUserId} '
        'local=${message.localId} phase=$phase error=$error',
      );
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
      debugPrint(
        '[CHAT_OPS][SEND][START] type=emoji_game '
        'sender=${session.id} peer=$peerUserId local=${localMessage.localId} '
        'gameType=${game.type} value=${game.value}',
      );
      final roomId = await _ensureConversationRoomId(conversation);
      if (roomId == null || roomId <= 0) {
        throw const DirectChatException('Unable to open chat.');
      }
      if (!_isCurrentAppSession(session)) {
        return;
      }
      final updated = localMessage.copyWith(
        roomId: roomId,
        sendStatus: ChatMessageSendStatus.pending,
        updatedAt: DateTime.now(),
      );
      await store.upsert(updated);
      if (!_isCurrentAppSession(session)) {
        return;
      }
      _replaceStoredMessage(conversation, updated);

      final ack = await ref
          .read(imSessionManagerProvider)
          .sendEmojiGameMessage(
            senderUserId: session.id,
            roomId: roomId,
            type: game.type,
            value: game.value,
            clientMessageId: clientMessageId,
          );
      if (!_isCurrentAppSession(session)) {
        return;
      }
      debugPrint(
        '[CHAT_OPS][SEND][ACK] type=emoji_game sender=${session.id} '
        'peer=$peerUserId room=$roomId cid=$clientMessageId '
        'success=${ack.success} server=${ack.serverMessageId} '
        'event=${ack.event} message=${ack.message} raw=${ack.rawPayload}',
      );
      final completed = updated.copyWith(
        sendStatus: ack.success
            ? ChatMessageSendStatus.sent
            : ChatMessageSendStatus.failed,
        serverMessageId: ack.serverMessageId?.toString(),
        errorMessage: ack.success
            ? null
            : ack.failureSummary(fallback: 'Emoji send failed'),
        updatedAt: DateTime.now(),
      );
      await store.upsert(completed);
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=emoji_game_completed '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'local=${completed.localId} server=${completed.serverMessageId} '
        'status=${completed.sendStatus.name} error=${completed.errorMessage}',
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
      debugPrint(
        '[CHAT_OPS][SEND][START] type=${media.isVideo ? 'video' : 'photo'} '
        'sender=${session.id} peer=$peerUserId local=${localMessage.localId} '
        'path=${media.path}',
      );
      final roomId = await _ensureConversationRoomId(conversation);
      if (roomId == null || roomId <= 0) {
        throw const DirectChatException('Unable to open chat.');
      }
      if (!_isCurrentAppSession(session)) {
        return false;
      }
      final updated = localMessage.copyWith(
        roomId: roomId,
        sendStatus: ChatMessageSendStatus.pending,
        updatedAt: DateTime.now(),
      );
      await store.upsert(updated);
      if (!_isCurrentAppSession(session)) {
        return false;
      }
      _replaceStoredMessage(conversation, updated);

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
      if (!_isCurrentAppSession(session)) {
        return false;
      }

      final ack = await ref
          .read(imSessionManagerProvider)
          .sendMediaMessage(
            senderUserId: session.id,
            roomId: roomId,
            msgData: [mediaData],
            clientMessageId: clientMessageId,
          );
      if (!_isCurrentAppSession(session)) {
        return false;
      }
      debugPrint(
        '[CHAT_OPS][SEND][ACK] type=${media.isVideo ? 'video' : 'photo'} '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'cid=$clientMessageId success=${ack.success} '
        'server=${ack.serverMessageId} event=${ack.event} '
        'message=${ack.message} raw=${ack.rawPayload}',
      );
      final completed = updated.copyWith(
        sendStatus: ack.success
            ? ChatMessageSendStatus.sent
            : ChatMessageSendStatus.failed,
        serverMessageId: ack.serverMessageId?.toString(),
        errorMessage: ack.success
            ? null
            : ack.failureSummary(fallback: 'Media send failed'),
        msgData: jsonEncode(mediaData),
        localMediaPath: media.path,
        updatedAt: DateTime.now(),
      );
      await store.upsert(completed);
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=media_completed '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'local=${completed.localId} server=${completed.serverMessageId} '
        'status=${completed.sendStatus.name} error=${completed.errorMessage}',
      );
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
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=media_failed '
        'sender=${session.id} peer=$peerUserId room=${failed.roomId} '
        'local=${failed.localId} error=$error',
      );
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
      debugPrint(
        '[CHAT_OPS][SEND][START] type=voice '
        'sender=${session.id} peer=$peerUserId local=${localMessage.localId} '
        'path=${voice.path} duration=$durationSeconds',
      );
      final roomId = await _ensureConversationRoomId(conversation);
      if (roomId == null || roomId <= 0) {
        throw const DirectChatException('Unable to open chat.');
      }
      if (!_isCurrentAppSession(session)) {
        return false;
      }
      final updated = localMessage.copyWith(
        roomId: roomId,
        sendStatus: ChatMessageSendStatus.pending,
        updatedAt: DateTime.now(),
      );
      await store.upsert(updated);
      if (!_isCurrentAppSession(session)) {
        return false;
      }
      _replaceStoredMessage(conversation, updated);

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
      if (!_isCurrentAppSession(session)) {
        return false;
      }
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
            senderUserId: session.id,
            roomId: roomId,
            msgData: [voiceData],
            clientMessageId: clientMessageId,
          );
      if (!_isCurrentAppSession(session)) {
        return false;
      }
      debugPrint(
        '[CHAT_OPS][SEND][ACK] type=voice sender=${session.id} '
        'peer=$peerUserId room=$roomId cid=$clientMessageId '
        'success=${ack.success} server=${ack.serverMessageId} '
        'event=${ack.event} message=${ack.message} raw=${ack.rawPayload}',
      );
      final completed = updated.copyWith(
        sendStatus: ack.success
            ? ChatMessageSendStatus.sent
            : ChatMessageSendStatus.failed,
        serverMessageId: ack.serverMessageId?.toString(),
        errorMessage: ack.success
            ? null
            : ack.failureSummary(fallback: 'Voice send failed'),
        msgData: jsonEncode(voiceData),
        localMediaPath: voice.path,
        updatedAt: DateTime.now(),
      );
      await store.upsert(completed);
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=voice_completed '
        'sender=${session.id} peer=$peerUserId room=$roomId '
        'local=${completed.localId} server=${completed.serverMessageId} '
        'status=${completed.sendStatus.name} error=${completed.errorMessage}',
      );
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
      debugPrint(
        '[CHAT_OPS][LOCAL][UPSERT] phase=voice_failed '
        'sender=${session.id} peer=$peerUserId room=${failed.roomId} '
        'local=${failed.localId} error=$error',
      );
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
    final socketCertificate = payload['__socketCertificate']?.toString() ?? '';
    if (socketCertificate.isNotEmpty &&
        socketCertificate != session.certificate) {
      debugPrint(
        '[CHAT_OPS][SOCKET][SKIP] reason=session_mismatch '
        'sender=${session.id}',
      );
      return;
    }

    final socketMessage = _IncomingSocketMessage.fromJson(payload);
    await _persistIncomingSocketMessage(socketMessage, session);
  }

  Future<void> _handleClientIndexEvent(ImClientIndexEvent event) async {
    final session = widget.appAccountSession;
    final readMsgIndex = event.readMsgIndex;
    if (session == null ||
        (event.socketCertificate?.isNotEmpty == true &&
            event.socketCertificate != session.certificate) ||
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
            .lastOrNull;
    if (roomId == null || roomId <= 0) {
      debugPrint(
        '[CHAT_OPS][LOCAL][SYNC_SKIP] reason=no_room '
        'sender=${session.id} peer=$peerUserId',
      );
      return;
    }
    if (!_isCurrentAppSession(session)) {
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
      if (!_isCurrentAppSession(session)) {
        return;
      }
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
      if (!_isCurrentAppSession(session)) {
        return;
      }
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
    if (!_isCurrentAppSession(session)) {
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
      if (isOutgoing || activeConversation?.targetUserId == peerUserId) {
        _localUnreadByPeer[peerUserId] = 0;
        unawaited(_persistUnreadCount(peerUserId, 0));
      } else {
        final base =
            _localUnreadByPeer[peerUserId] ??
            _chatConversations
                .where(
                  (conversation) => conversation.targetUserId == peerUserId,
                )
                .map((conversation) => conversation.unread)
                .firstOrNull ??
            0;
        final unread = base + 1;
        _localUnreadByPeer[peerUserId] = unread;
        unawaited(_persistUnreadCount(peerUserId, unread));
      }
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
          _localUnreadByPeer.clear();
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
    final unread = await store.loadUnreadByAppUser(appUserId: session.id);
    final profiles = await profileStore.loadByAppUser(appUserId: session.id);
    if (!mounted || widget.appAccountSession?.id != session.id) {
      return;
    }
    setState(() {
      _recentMessagesByPeer
        ..clear()
        ..addAll(latest);
      _localUnreadByPeer
        ..clear()
        ..addAll(unread);
      _peerProfiles
        ..clear()
        ..addAll(profiles);
    });
    final selected = _selectedConversation();
    if (selected != null && selected.targetUserId != null) {
      _activateConversation(selected);
    }
  }

  Future<void> _persistUnreadCount(int peerUserId, int unreadCount) async {
    final session = widget.appAccountSession;
    if (session == null || peerUserId <= 0) {
      return;
    }
    final store = await ref.read(localChatMessageStoreProvider.future);
    await store.setUnreadCount(
      appUserId: session.id,
      peerUserId: peerUserId,
      unreadCount: unreadCount,
    );
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
          .map(
            (record) => _ConversationData.fromChatConversation(
              l10n,
              record,
              session.id,
            ),
          )
          .map((conversation) {
            final peerUserId = conversation.targetUserId;
            final userInfo = peerUserId == null
                ? null
                : userInfoById[peerUserId];
            return userInfo == null
                ? conversation
                : conversation.copyWith(
                    name: userInfo.displayName,
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
          final selectedIndex = _selectedIndexIn(conversations);
          if (selectedIndex >= 0) {
            _activeConversation = conversations[selectedIndex];
          }
          if (_selectedConversationPeerUserId != null &&
              !validPeerIds.contains(_selectedConversationPeerUserId)) {
            _selectedConversationPeerUserId = null;
            _activeConversation = null;
          }
        }
      });
      final selected = _selectedConversation();
      if (_selectedTab == _RailTab.chats && selected != null) {
        _activateConversation(selected);
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
    return _chatPreviewText(text);
  }

  String _formatConversationTime(DateTime time) {
    return _chatListTimeText(time);
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
      _selectedConversationPeerUserId = null;
      _selectedAppAccountInfoId = null;
      _activeConversation = null;
      _isConversationLoading = false;
      _isAppAccountListMode = false;
      _isAppAccountListLoading = false;
      _isAppAccountAvatarUpdating = false;
      _isSearchLoading = false;
      _isActiveConversationSyncing = false;
      _searchQuery = '';
      _searchNotice = null;
      _chatNotice = null;
      _appAccountListNotice = null;
      _chatConversations = const [];
      _searchConversations = const [];
      _appAccountEntries = const [];
      _remoteConversations.clear();
      _remoteNotices.clear();
      _directRoomIds.clear();
      _storedMessages.clear();
      _recentMessagesByPeer.clear();
      _localUnreadByPeer.clear();
      _peerProfiles.clear();
    });
  }

  void _showWorkspaceNotice(String message) {
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
    required this.appAccountListMode,
    required this.appAccounts,
    required this.selectedAppAccountIndex,
    required this.onTabSelected,
    required this.onConversationSelected,
    required this.onAppAccountSelected,
    required this.onSearchChanged,
    required this.onAppAccountTap,
    required this.onAppAccountDialogTap,
    required this.onSettingsTap,
    required this.chatBadge,
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
  final bool appAccountListMode;
  final List<AppAccountHistoryEntry> appAccounts;
  final int selectedAppAccountIndex;
  final ValueChanged<_RailTab> onTabSelected;
  final ValueChanged<int> onConversationSelected;
  final ValueChanged<int> onAppAccountSelected;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAppAccountTap;
  final VoidCallback onAppAccountDialogTap;
  final VoidCallback onSettingsTap;
  final String? chatBadge;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 382,
      child: Row(
        children: [
          _NavigationRail(
            operatorName: operatorName,
            appAccountName: appAccountName,
            appAccountOnline: appAccountOnline,
            appAccountBusy: appAccountBusy,
            appAccountAvatarUrl: appAccountAvatarUrl,
            selectedTab: selectedTab,
            appAccountListMode: appAccountListMode,
            onTabSelected: onTabSelected,
            onAppAccountTap: onAppAccountTap,
            onAppAccountDialogTap: onAppAccountDialogTap,
            onSettingsTap: onSettingsTap,
            chatBadge: chatBadge,
            l10n: l10n,
          ),
          Expanded(
            child: appAccountListMode
                ? _AppAccountListPane(
                    accounts: appAccounts,
                    selectedIndex: selectedAppAccountIndex,
                    isLoading: isConversationLoading,
                    emptyMessage: emptyMessage,
                    l10n: l10n,
                    onAddOrSwitch: onAppAccountDialogTap,
                    onSelected: onAppAccountSelected,
                  )
                : _ConversationPane(
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
    required this.appAccountListMode,
    required this.onTabSelected,
    required this.onAppAccountTap,
    required this.onAppAccountDialogTap,
    required this.onSettingsTap,
    required this.chatBadge,
    required this.l10n,
  });

  final String operatorName;
  final String appAccountName;
  final bool appAccountOnline;
  final bool appAccountBusy;
  final String? appAccountAvatarUrl;
  final _RailTab selectedTab;
  final bool appAccountListMode;
  final ValueChanged<_RailTab> onTabSelected;
  final VoidCallback onAppAccountTap;
  final VoidCallback onAppAccountDialogTap;
  final VoidCallback onSettingsTap;
  final String? chatBadge;
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
                  badge: chatBadge,
                  active: !appAccountListMode && selectedTab == _RailTab.chats,
                  onTap: () => onTabSelected(_RailTab.chats),
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.person_add_alt_1_rounded,
                  label: l10n.navNew,
                  active:
                      !appAccountListMode && selectedTab == _RailTab.updates,
                  onTap: () => onTabSelected(_RailTab.updates),
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.radio_button_checked_rounded,
                  label: l10n.navOnline,
                  active:
                      !appAccountListMode &&
                      selectedTab == _RailTab.communities,
                  onTap: () => onTabSelected(_RailTab.communities),
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.diamond_rounded,
                  label: l10n.navRichs,
                  active: !appAccountListMode && selectedTab == _RailTab.calls,
                  onTap: () => onTabSelected(_RailTab.calls),
                ),
                const SizedBox(height: 12),
                _RailItem(
                  icon: Icons.login_rounded,
                  label: l10n.navLogin,
                  onTap: onAppAccountDialogTap,
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

class _AppAccountListPane extends StatelessWidget {
  const _AppAccountListPane({
    required this.accounts,
    required this.selectedIndex,
    required this.isLoading,
    required this.emptyMessage,
    required this.l10n,
    required this.onAddOrSwitch,
    required this.onSelected,
  });

  final List<AppAccountHistoryEntry> accounts;
  final int selectedIndex;
  final bool isLoading;
  final String emptyMessage;
  final AppLocalizations l10n;
  final VoidCallback onAddOrSwitch;
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
            width: 246,
            child: Text(
              l10n.appAccountListPanelTitle,
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
            left: 0,
            top: 42,
            width: 299,
            child: SizedBox(
              height: 34,
              child: FilledButton.icon(
                onPressed: onAddOrSwitch,
                icon: const Icon(Icons.manage_accounts_rounded, size: 17),
                label: Text(l10n.appAccountListAddOrSwitch),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xffe8f5ef),
                  foregroundColor: const Color(0xff177345),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    fontWeight: FontWeight.w700,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            width: 281,
            top: 96,
            bottom: 0,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: isLoading
                  ? _ConversationLoading(message: l10n.workspaceLoadingUsers)
                  : accounts.isEmpty
                  ? _ConversationEmpty(message: emptyMessage)
                  : Scrollbar(
                      thumbVisibility: accounts.length > 8,
                      radius: const Radius.circular(99),
                      child: ListView.separated(
                        key: ValueKey(
                          'app_accounts_${accounts.first.id}_${accounts.length}',
                        ),
                        padding: const EdgeInsets.only(bottom: 18),
                        physics: const ClampingScrollPhysics(),
                        itemBuilder: (context, index) => _AppAccountListTile(
                          account: accounts[index],
                          selected: index == selectedIndex,
                          onTap: () => onSelected(index),
                        ),
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemCount: accounts.length,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppAccountListTile extends StatelessWidget {
  const _AppAccountListTile({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final AppAccountHistoryEntry account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = _accountDisplayName(account);
    final email = account.email.trim();

    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Container(
            height: 68,
            padding: const EdgeInsets.fromLTRB(6, 5, 14, 5),
            decoration: BoxDecoration(
              color: selected ? const Color(0xfff0f2f5) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _LetterAvatar(
                  color: _ConversationData.avatarColorFor(account.id),
                  label: _accountInitial(title),
                  avatarUrl: account.avatarUrl,
                  online: account.token.trim().isNotEmpty,
                  size: 50,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xff3b4a54),
                          fontSize: 15,
                          height: 20 / 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        email.isEmpty ? 'UID ${account.id}' : email,
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
              ],
            ),
          ),
        ),
      ),
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
            width: 246,
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
            right: 14,
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
            width: 281,
            child: _SearchField(
              hintText: l10n.workspaceSearchHint,
              value: searchQuery,
              onChanged: onSearchChanged,
            ),
          ),
          Positioned(
            left: 10,
            width: 281,
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
      width: 281,
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

class _AppAccountInfoSection extends StatefulWidget {
  const _AppAccountInfoSection({
    required this.account,
    required this.l10n,
    required this.isCurrent,
    required this.isAvatarUpdating,
    required this.onAvatarTap,
  });

  final AppAccountHistoryEntry? account;
  final AppLocalizations l10n;
  final bool isCurrent;
  final bool isAvatarUpdating;
  final ValueChanged<AppAccountHistoryEntry> onAvatarTap;

  @override
  State<_AppAccountInfoSection> createState() => _AppAccountInfoSectionState();
}

class _AppAccountInfoSectionState extends State<_AppAccountInfoSection> {
  int _selectedTab = 0;
  bool _isEditingBasicProfile = false;

  @override
  void didUpdateWidget(covariant _AppAccountInfoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account?.id != widget.account?.id) {
      _selectedTab = 0;
      _isEditingBasicProfile = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final l10n = widget.l10n;
    if (account == null) {
      return Container(
        color: const Color(0xfff0f1f5),
        alignment: Alignment.center,
        child: Text(
          l10n.appAccountListSelectAccount,
          style: const TextStyle(
            color: Color(0xff667781),
            fontSize: 14,
            height: 20 / 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final displayName = _accountDisplayName(account);

    return Container(
      color: const Color(0xfff4f5f8),
      child: Column(
        children: [
          _AppAccountInfoTitleBar(
            title: _isEditingBasicProfile
                ? l10n.appAccountInfoBasicProfile
                : l10n.contactInfoTitle,
            showBack: _isEditingBasicProfile,
            onBack: () => setState(() => _isEditingBasicProfile = false),
            onEdit: _isEditingBasicProfile
                ? null
                : () => setState(() => _isEditingBasicProfile = true),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isEditingBasicProfile
                  ? _BasicProfileEditor(
                      key: ValueKey('basic_profile_${account.id}'),
                      account: account,
                      l10n: l10n,
                      displayName: displayName,
                      isAvatarUpdating: widget.isAvatarUpdating,
                      onAvatarTap: () => widget.onAvatarTap(account),
                    )
                  : _ProfileOverview(
                      key: ValueKey('profile_overview_${account.id}'),
                      account: account,
                      l10n: l10n,
                      displayName: displayName,
                      isCurrent: widget.isCurrent,
                      isAvatarUpdating: widget.isAvatarUpdating,
                      onAvatarTap: () => widget.onAvatarTap(account),
                      selectedTab: _selectedTab,
                      onTabSelected: (index) {
                        setState(() => _selectedTab = index);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppAccountInfoTitleBar extends StatelessWidget {
  const _AppAccountInfoTitleBar({
    required this.title,
    required this.showBack,
    required this.onBack,
    required this.onEdit,
  });

  final String title;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: showBack
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.chevron_left_rounded, size: 25),
                      label: Text(AppLocalizations.of(context).contactInfoBack),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xff287bc5),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(
                          fontSize: 15,
                          height: 20 / 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff111b21),
                fontSize: 19,
                height: 26 / 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(
            width: 88,
            child: onEdit == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: AppLocalizations.of(
                        context,
                      ).appAccountInfoEditProfile,
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_square),
                      color: const Color(0xff111b21),
                      splashRadius: 20,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfileOverview extends StatelessWidget {
  const _ProfileOverview({
    super.key,
    required this.account,
    required this.l10n,
    required this.displayName,
    required this.isCurrent,
    required this.isAvatarUpdating,
    required this.onAvatarTap,
    required this.selectedTab,
    required this.onTabSelected,
  });

  final AppAccountHistoryEntry account;
  final AppLocalizations l10n;
  final String displayName;
  final bool isCurrent;
  final bool isAvatarUpdating;
  final VoidCallback onAvatarTap;
  final int selectedTab;
  final ValueChanged<int> onTabSelected;

  @override
  Widget build(BuildContext context) {
    final email = account.email.trim();
    final idText = account.id > 0 ? '${account.id}' : '--';
    final registerDate = _formatAppAccountDate(account.updatedAt);

    return CustomScrollView(
      key: ValueKey('profile_overview_scroll_${account.id}'),
      slivers: [
        SliverToBoxAdapter(
          child: _ProfileHeroHeader(
            account: account,
            displayName: displayName,
            isCurrent: isCurrent,
            isAvatarUpdating: isAvatarUpdating,
            onAvatarTap: onAvatarTap,
            l10n: l10n,
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _ProfileTabsHeaderDelegate(
            child: _AppAccountProfileTabs(
              l10n: l10n,
              selectedIndex: selectedTab,
              onSelected: onTabSelected,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(34, 24, 34, 34),
          sliver: SliverToBoxAdapter(
            child: selectedTab == 0
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ProfileAlbumSection(title: l10n.appAccountInfoPhotoWall),
                      const SizedBox(height: 28),
                      _ProfileAlbumSection(
                        title: l10n.appAccountInfoPrivateAlbum,
                      ),
                      const SizedBox(height: 28),
                      _ProfileCard(
                        children: [
                          _ProfileSectionHeader(
                            title: l10n.appAccountInfoProfile,
                          ),
                          const SizedBox(height: 10),
                          _ProfileInfoRow(
                            assetPath: 'assets/profile/icon_user_64.webp',
                            label: l10n.appAccountInfoId,
                            value: idText,
                            copyable: true,
                          ),
                          _ProfileInfoRow(
                            assetPath: 'assets/profile/icon_birthday_64.webp',
                            label: l10n.appAccountInfoBirthday,
                            value: '--',
                          ),
                          _ProfileInfoRow(
                            assetPath: 'assets/profile/icon_zodiac_64.webp',
                            label: l10n.appAccountInfoZodiac,
                            value: '--',
                          ),
                          _ProfileInfoRow(
                            assetPath:
                                'assets/profile/icon_register_time_64.webp',
                            label: l10n.appAccountInfoRegisterTime,
                            value: registerDate,
                          ),
                          if (email.isNotEmpty)
                            _ProfileInfoRow(
                              icon: Icons.mail_outline_rounded,
                              label: l10n.appAccountInfoAccount,
                              value: email,
                              showDivider: false,
                            ),
                        ],
                      ),
                    ],
                  )
                : _ProfileEmptyTab(message: l10n.appAccountInfoEmptyTab),
          ),
        ),
      ],
    );
  }
}

class _ProfileTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ProfileTabsHeaderDelegate({required this.child});

  static const double _height = 48;

  final Widget child;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: const Color(0xfff4f5f8),
      padding: const EdgeInsets.fromLTRB(34, 0, 34, 0),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabsHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

class _ProfileAlbumSection extends StatelessWidget {
  const _ProfileAlbumSection({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileSectionHeader(title: title, trailing: '0'),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xffededed)),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.add_rounded,
              color: Color(0xffd1d1d1),
              size: 30,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeroHeader extends StatelessWidget {
  const _ProfileHeroHeader({
    required this.account,
    required this.displayName,
    required this.isCurrent,
    required this.isAvatarUpdating,
    required this.onAvatarTap,
    required this.l10n,
  });

  final AppAccountHistoryEntry account;
  final String displayName;
  final bool isCurrent;
  final bool isAvatarUpdating;
  final VoidCallback onAvatarTap;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfff4f5f8),
      padding: const EdgeInsets.fromLTRB(44, 36, 44, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _EditableProfileAvatar(
            color: _ConversationData.avatarColorFor(account.id),
            label: _accountInitial(displayName),
            avatarUrl: account.avatarUrl,
            online: isCurrent,
            size: 122,
            isUpdating: isAvatarUpdating,
            onTap: onAvatarTap,
          ),
          const SizedBox(height: 22),
          Text(
            displayName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xff111b21),
              fontSize: 28,
              height: 35 / 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.contactInfoLastSeenRecently,
                style: const TextStyle(
                  color: Color(0xff9b9b9b),
                  fontSize: 17,
                  height: 24 / 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const _ProfileBadge(
                text: '♂18',
                color: Color(0xff6dccf8),
                icon: Icons.male_rounded,
              ),
              const _ProfileBadge(
                text: 'New',
                color: Color(0xff54d39a),
                icon: Icons.auto_awesome_rounded,
              ),
              const _ProfileBadge(
                text: '0',
                color: Color(0xffd9d9d9),
                icon: Icons.warning_amber_rounded,
              ),
              const _ProfileBadge(
                text: 'VIP0',
                color: Color(0xffcfcfcf),
                icon: Icons.workspace_premium_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 3),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableProfileAvatar extends StatelessWidget {
  const _EditableProfileAvatar({
    required this.color,
    required this.label,
    required this.avatarUrl,
    required this.online,
    required this.size,
    required this.isUpdating,
    required this.onTap,
  });

  final Color color;
  final String label;
  final String avatarUrl;
  final bool online;
  final double size;
  final bool isUpdating;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).appAccountAvatarChange,
      child: GestureDetector(
        onTap: isUpdating ? null : onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _LetterAvatar(
              color: color,
              label: label,
              avatarUrl: avatarUrl,
              online: online,
              size: size,
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xff287bc5),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: isUpdating
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.photo_camera_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BasicProfileEditor extends StatelessWidget {
  const _BasicProfileEditor({
    super.key,
    required this.account,
    required this.l10n,
    required this.displayName,
    required this.isAvatarUpdating,
    required this.onAvatarTap,
  });

  final AppAccountHistoryEntry account;
  final AppLocalizations l10n;
  final String displayName;
  final bool isAvatarUpdating;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final nickname = displayName.trim().isEmpty ? '--' : displayName.trim();
    final nicknameCount = min(nickname.characters.length, 20);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(38, 24, 38, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _EditableProfileAvatar(
              color: _ConversationData.avatarColorFor(account.id),
              label: _accountInitial(displayName),
              avatarUrl: account.avatarUrl,
              online: true,
              size: 104,
              isUpdating: isAvatarUpdating,
              onTap: onAvatarTap,
            ),
          ),
          const SizedBox(height: 24),
          _BasicProfileFieldCard(
            label: l10n.appAccountInfoNickname,
            trailing: '$nicknameCount/20',
            height: 76,
            child: Text(
              nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff111b21),
                fontSize: 17,
                height: 24 / 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _BasicProfileFieldCard(
            label: l10n.appAccountInfoBirthday,
            height: 76,
            trailingIcon: Icons.chevron_right_rounded,
            child: const Text(
              '--',
              style: TextStyle(
                color: Color(0xff111b21),
                fontSize: 17,
                height: 24 / 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _BasicProfileFieldCard(
            label: l10n.appAccountInfoSignature,
            trailing: '0/140',
            height: 148,
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                l10n.appAccountInfoSignaturePlaceholder,
                style: const TextStyle(
                  color: Color(0xff9ca3af),
                  fontSize: 16,
                  height: 23 / 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          _ProfileCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            children: [
              _ProfileInfoRow(
                icon: Icons.record_voice_over_outlined,
                label: l10n.appAccountInfoVoiceIntro,
                value: '',
              ),
              _ProfileInfoRow(
                icon: Icons.straighten_rounded,
                label: l10n.appAccountInfoHeight,
                value: '--',
              ),
              _ProfileInfoRow(
                icon: Icons.monitor_weight_outlined,
                label: l10n.appAccountInfoWeight,
                value: '--',
              ),
              _ProfileInfoRow(
                icon: Icons.business_center_outlined,
                label: l10n.appAccountInfoIndustry,
                value: '--',
              ),
              _ProfileInfoRow(
                icon: Icons.work_outline_rounded,
                label: l10n.appAccountInfoOccupation,
                value: '--',
              ),
              _ProfileInfoRow(
                icon: Icons.public_rounded,
                label: l10n.appAccountInfoBirthplace,
                value: '--',
              ),
              _ProfileInfoRow(
                icon: Icons.location_on_outlined,
                label: l10n.appAccountInfoResidence,
                value: '--',
                showDivider: false,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AppAccountProfileTabs extends StatelessWidget {
  const _AppAccountProfileTabs({
    required this.l10n,
    required this.selectedIndex,
    required this.onSelected,
  });

  final AppLocalizations l10n;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      l10n.appAccountInfoProfile,
      '${l10n.appAccountInfoActivity} 0',
      l10n.appAccountInfoRelationship,
      l10n.appAccountInfoAlbum,
    ];
    return Row(
      children: [
        for (var index = 0; index < tabs.length; index++) ...[
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelected(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  child: Text(
                    tabs[index],
                    style: TextStyle(
                      color: index == selectedIndex
                          ? const Color(0xff111b21)
                          : const Color(0xffa0a0a0),
                      fontSize: 17,
                      height: 24 / 17,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: index == selectedIndex ? 46 : 0,
                height: 2,
                color: const Color(0xff111b21),
              ),
            ],
          ),
          if (index != tabs.length - 1) const SizedBox(width: 34),
        ],
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 8),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _BasicProfileFieldCard extends StatelessWidget {
  const _BasicProfileFieldCard({
    required this.label,
    required this.child,
    required this.height,
    this.trailing,
    this.trailingIcon,
    this.alignment = Alignment.centerLeft,
  });

  final String label;
  final Widget child;
  final double height;
  final String? trailing;
  final IconData? trailingIcon;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xff9ca3af),
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (trailing != null)
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: Color(0xffa6a6a6),
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Align(alignment: alignment, child: child),
              ),
              if (trailingIcon != null)
                Icon(trailingIcon, color: const Color(0xffb8b8b8), size: 22),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileEmptyTab extends StatelessWidget {
  const _ProfileEmptyTab({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xff8b98a1),
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ProfileSectionHeader extends StatelessWidget {
  const _ProfileSectionHeader({required this.title, this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xff111b21),
            fontSize: 18,
            height: 25 / 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              color: Color(0xff9a9a9a),
              fontSize: 16,
              height: 22 / 16,
            ),
          ),
        if (trailing != null)
          const Icon(
            Icons.chevron_right_rounded,
            color: Color(0xffb8b8b8),
            size: 25,
          ),
      ],
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.label,
    required this.value,
    this.icon,
    this.assetPath,
    this.copyable = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? assetPath;
  final bool copyable;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(
                bottom: BorderSide(color: Color(0xffeeeeee), width: 1),
              )
            : null,
      ),
      child: Row(
        children: [
          if (assetPath != null)
            Image.asset(assetPath!, width: 25, height: 25)
          else
            Icon(icon, color: const Color(0xff24292f), size: 24),
          const SizedBox(width: 16),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff111b21),
              fontSize: 16,
              height: 22 / 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xff333333),
                fontSize: 16,
                height: 22 / 16,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          if (copyable)
            const Icon(Icons.copy_rounded, color: Color(0xffc4c4c4), size: 17),
        ],
      ),
    );
  }
}

String _formatAppAccountDate(DateTime dateTime) {
  if (dateTime.millisecondsSinceEpoch <= 0) {
    return '--';
  }
  return '${dateTime.year}/${dateTime.month}/${dateTime.day}';
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
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Container(
            height: 60,
            padding: const EdgeInsets.fromLTRB(6, 4, 16, 4),
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
                        width: item.unread > 99 ? 30 : 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Color(0xff21c563),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          item.unread > 99 ? '99+' : '${item.unread}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
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
  bool _showContactInfo = false;

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
    if (oldWidget.conversation?.targetUserId !=
            widget.conversation?.targetUserId ||
        oldWidget.conversation?.name != widget.conversation?.name) {
      _showContactInfo = false;
    }
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

    if (_showContactInfo) {
      return _ContactInfoPage(
        conversation: conversation,
        messages: widget.messages,
        l10n: widget.l10n,
        onlineText: widget.l10n.workspaceUserOnline,
        offlineText: widget.l10n.appAccountStatusOffline,
        onBack: () => setState(() => _showContactInfo = false),
      );
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
              onOpenInfo: () => setState(() => _showContactInfo = true),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 50,
            bottom: 48,
            child: _ScrollableMessageList(
              controller: _messageScrollController,
              messages: widget.messages,
              l10n: widget.l10n,
            ),
          ),
          Positioned(
            right: 24,
            bottom: 56,
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
              key: ValueKey(
                conversation.targetUserId == null
                    ? conversation.name
                    : 'peer:${conversation.targetUserId}',
              ),
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
    required this.l10n,
  });

  final ScrollController controller;
  final List<_ChatMessage> messages;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final items = _MessageTimelineItem.build(messages, l10n);
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
        padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final dateLabel = item.dateLabel;
          if (dateLabel != null) {
            return Padding(
              padding: EdgeInsets.only(bottom: 18),
              child: Center(child: _DatePill(label: dateLabel)),
            );
          }
          return _MessageListItem(message: item.message!);
        },
      ),
    );
  }
}

class _MessageTimelineItem {
  const _MessageTimelineItem.date(this.dateLabel) : message = null;

  const _MessageTimelineItem.message(this.message) : dateLabel = null;

  final String? dateLabel;
  final _ChatMessage? message;

  static List<_MessageTimelineItem> build(
    List<_ChatMessage> messages,
    AppLocalizations l10n,
  ) {
    if (messages.isEmpty) {
      return [
        _MessageTimelineItem.date(_formatDatePillLabel(DateTime.now(), l10n)),
      ];
    }

    final items = <_MessageTimelineItem>[];
    DateTime? previousDay;
    for (final message in messages) {
      final currentDay = _dateOnly(message.createdAt.toLocal());
      if (previousDay == null || currentDay != previousDay) {
        items.add(
          _MessageTimelineItem.date(_formatDatePillLabel(currentDay, l10n)),
        );
        previousDay = currentDay;
      }
      items.add(_MessageTimelineItem.message(message));
    }
    return items;
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _formatDatePillLabel(DateTime date, AppLocalizations l10n) {
  final local = date.toLocal();
  final today = _dateOnly(DateTime.now());
  final yesterday = today.subtract(const Duration(days: 1));
  if (_isSameDate(local, today)) {
    return l10n.dateToday;
  }
  if (_isSameDate(local, yesterday)) {
    return l10n.dateYesterday;
  }

  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final month = months[local.month - 1];
  if (local.year == today.year) {
    return '$month ${local.day}';
  }
  return '$month ${local.day}, ${local.year}';
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
    required this.onOpenInfo,
  });

  final _Conversation conversation;
  final AppUserSession? appAccountSession;
  final ConnectionStatus connectionStatus;
  final AppLocalizations l10n;
  final String onlineText;
  final VoidCallback onOpenInfo;

  @override
  Widget build(BuildContext context) {
    final peerUserId = conversation.targetUserId;
    final peerText = peerUserId == null ? '' : 'UID $peerUserId';
    final statusText = conversation.isOnline
        ? onlineText
        : l10n.appAccountStatusOffline;

    return Material(
      color: const Color(0xfff7f7fc),
      child: InkWell(
        onTap: onOpenInfo,
        child: Container(
          height: 50,
          padding: const EdgeInsets.only(
            left: 18,
            right: 16,
            top: 6,
            bottom: 6,
          ),
          child: Row(
            children: [
              _LetterAvatar(
                color: conversation.color,
                label: conversation.emoji,
                avatarUrl: conversation.avatarUrl,
                online: conversation.isOnline,
                size: 40,
              ),
              const SizedBox(width: 12),
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
                        fontSize: 14,
                        height: 18 / 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 1),
                    if (peerText.isNotEmpty)
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              peerText,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff667781),
                                fontSize: 11,
                                height: 13 / 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _OnlineDot(online: conversation.isOnline),
                          const SizedBox(width: 5),
                          Text(
                            statusText,
                            style: TextStyle(
                              color: conversation.isOnline
                                  ? const Color(0xff1da855)
                                  : const Color(0xff8d969c),
                              fontSize: 11,
                              height: 13 / 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const _HeaderIcon(Icons.call_rounded),
              const SizedBox(width: 22),
              const _HeaderIcon(Icons.search_rounded),
              const SizedBox(width: 22),
              const _HeaderIcon(Icons.more_horiz_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactInfoPage extends StatelessWidget {
  const _ContactInfoPage({
    required this.conversation,
    required this.messages,
    required this.l10n,
    required this.onlineText,
    required this.offlineText,
    required this.onBack,
  });

  final _Conversation conversation;
  final List<_ChatMessage> messages;
  final AppLocalizations l10n;
  final String onlineText;
  final String offlineText;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final peerUserId = conversation.targetUserId;
    final statusText = conversation.isOnline ? onlineText : offlineText;
    final username = peerUserId == null
        ? '@${conversation.name}'
        : '@bbp_$peerUserId';
    final mediaMessages = messages
        .where((message) => message.media != null && !message.media!.isVoice)
        .map((message) => message.media!)
        .toList(growable: false);

    return Container(
      color: const Color(0xfff0f1f5),
      child: Column(
        children: [
          Container(
            height: 58,
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onBack,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chevron_left_rounded,
                          color: Color(0xff2383d2),
                          size: 34,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          l10n.contactInfoBack,
                          style: const TextStyle(
                            color: Color(0xff2383d2),
                            fontSize: 16,
                            height: 22 / 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      l10n.contactInfoTitle,
                      style: const TextStyle(
                        color: Color(0xff0b141a),
                        fontSize: 18,
                        height: 24 / 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 86),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 42),
                  _LetterAvatar(
                    color: conversation.color,
                    label: conversation.emoji,
                    avatarUrl: conversation.avatarUrl,
                    online: conversation.isOnline,
                    size: 128,
                  ),
                  const SizedBox(height: 22),
                  Text(
                    conversation.name,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 24,
                      height: 30 / 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    conversation.isOnline
                        ? statusText
                        : l10n.contactInfoLastSeenRecently,
                    style: const TextStyle(
                      color: Color(0xff9a9a9a),
                      fontSize: 17,
                      height: 24 / 17,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Row(
                      children: [
                        Expanded(
                          child: _InfoActionButton(
                            icon: Icons.chat_bubble_rounded,
                            label: l10n.contactInfoMessage,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _InfoActionButton(
                            icon: Icons.call_rounded,
                            label: l10n.contactInfoCall,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: _InfoActionButton(
                            icon: Icons.more_horiz_rounded,
                            label: l10n.contactInfoMore,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: _InfoDetailsCard(
                      l10n: l10n,
                      username: username,
                      peerUserId: peerUserId,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _InfoMediaSection(l10n: l10n, mediaItems: mediaMessages),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoActionButton extends StatelessWidget {
  const _InfoActionButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xff2383d2), size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xff2383d2),
              fontSize: 14,
              height: 18 / 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoDetailsCard extends StatelessWidget {
  const _InfoDetailsCard({
    required this.l10n,
    required this.username,
    required this.peerUserId,
  });

  final AppLocalizations l10n;
  final String username;
  final int? peerUserId;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.contactInfoUsername,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 14,
              height: 20 / 14,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  username,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xff2383d2),
                    fontSize: 15,
                    height: 21 / 15,
                  ),
                ),
              ),
              const Icon(
                Icons.copy_rounded,
                color: Color(0xff2383d2),
                size: 24,
              ),
            ],
          ),
          if (peerUserId != null) ...[
            const SizedBox(height: 8),
            Text(
              'UID $peerUserId',
              style: const TextStyle(
                color: Color(0xff667781),
                fontSize: 13,
                height: 18 / 13,
              ),
            ),
          ],
          const Divider(height: 22, color: Color(0xffe6e9eb)),
          Text(
            l10n.contactInfoAddContact,
            style: const TextStyle(
              color: Color(0xff2383d2),
              fontSize: 15,
              height: 21 / 15,
            ),
          ),
          const Divider(height: 22, color: Color(0xffe6e9eb)),
          Text(
            l10n.contactInfoBlockUser,
            style: const TextStyle(
              color: Color(0xffff3b30),
              fontSize: 15,
              height: 21 / 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoMediaSection extends StatelessWidget {
  const _InfoMediaSection({required this.l10n, required this.mediaItems});

  final AppLocalizations l10n;
  final List<_ChatMedia> mediaItems;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 6),
            child: Text(
              l10n.contactInfoMedia,
              style: const TextStyle(
                color: Color(0xff2383d2),
                fontSize: 17,
                height: 24 / 17,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 28),
            width: 54,
            height: 3,
            decoration: BoxDecoration(
              color: const Color(0xff2383d2),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Divider(height: 1, color: Color(0xffe2e4e7)),
          if (mediaItems.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 60),
              child: Text(
                l10n.contactInfoNoMedia,
                style: const TextStyle(
                  color: Color(0xff9a9a9a),
                  fontSize: 15,
                  height: 22 / 15,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 60),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: mediaItems
                    .map((media) => _InfoMediaTile(media: media))
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoMediaTile extends StatelessWidget {
  const _InfoMediaTile({required this.media});

  final _ChatMedia media;

  @override
  Widget build(BuildContext context) {
    final source = media.previewSource;
    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          barrierColor: const Color(0xdd0b141a),
          builder: (_) => _MediaViewerDialog(media: media),
        );
      },
      child: SizedBox(
        width: 120,
        height: 120,
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
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _formatVoiceDuration(media.durationSeconds ?? 0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      height: 16 / 12,
                    ),
                  ),
                ),
              ),
            if (media.isVideo)
              const Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
          ],
        ),
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
  const _DatePill({required this.label});

  final String label;

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
      child: Text(
        label,
        style: const TextStyle(color: Color(0xff54656f), fontSize: 12.5),
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
  void didUpdateWidget(covariant _MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.key != widget.key) {
      _resetVoiceUiState();
    }
    if (widget.initialValue != _controller.text && !_focusNode.hasFocus) {
      _controller.text = widget.initialValue;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
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

  void _resetVoiceUiState() {
    _voiceTimer?.cancel();
    _voiceStopwatch
      ..stop()
      ..reset();
    if (_isVoiceRecording) {
      unawaited(_voiceRecorder.cancel());
    }
    _isVoiceRecording = false;
    _isVoiceSending = false;
    _voiceSeconds = 0;
    _voicePath = null;
  }

  void _ensureTextInputReady() {
    if (_isVoiceRecording && !_voiceStopwatch.isRunning && !_isVoiceSending) {
      _resetVoiceUiState();
    }
    if (!_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
  }

  void _send() {
    debugPrint(
      '[CHAT_OPS][UI][INPUT_SEND] hasOnSend=${widget.onSend != null} '
      'isVoiceRecording=$_isVoiceRecording isVoiceSending=$_isVoiceSending '
      'textLength=${_controller.text.trim().length}',
    );
    if (_isVoiceRecording) {
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

  Future<void> _cancelVoiceRecording() async {
    if (!_isVoiceRecording || _isVoiceSending) {
      return;
    }
    _voiceTimer?.cancel();
    _voiceStopwatch
      ..stop()
      ..reset();
    final path = _voicePath;
    setState(() {
      _isVoiceRecording = false;
      _voiceSeconds = 0;
      _voicePath = null;
    });
    try {
      await _voiceRecorder.cancel();
    } catch (_) {
      // The recorder may already have stopped on some desktop backends.
    }
    if (path != null && path.isNotEmpty) {
      unawaited(File(path).delete().catchError((_) => File(path)));
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
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xffdfe5e8), width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 3, 18, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            tooltip: _isVoiceRecording
                ? AppLocalizations.of(context).voiceCancelRecording
                : AppLocalizations.of(context).attachmentTooltip,
            onPressed: _isVoiceRecording
                ? _cancelVoiceRecording
                : _toggleAttachmentMenu,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            icon: _isVoiceRecording
                ? Image.asset(
                    'assets/chat_input/telegram_delete.png',
                    width: 25,
                    height: 25,
                  )
                : AnimatedRotation(
                    turns: _attachOverlayEntry == null ? 0 : 0.125,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOutCubic,
                    child: Image.asset(
                      'assets/chat_input/telegram_attach.png',
                      width: 24,
                      height: 24,
                      color: _attachOverlayEntry == null
                          ? const Color(0xff8d969c)
                          : const Color(0xff1da855),
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 38,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _ensureTextInputReady,
                    child: Shortcuts(
                      shortcuts: const {
                        SingleActivator(LogicalKeyboardKey.enter):
                            _SendMessageIntent(),
                      },
                      child: Actions(
                        actions: {
                          _SendMessageIntent:
                              CallbackAction<_SendMessageIntent>(
                                onInvoke: (_) {
                                  _send();
                                  return null;
                                },
                              ),
                        },
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled:
                              !_isVoiceRecording || !_voiceStopwatch.isRunning,
                          readOnly:
                              _isVoiceRecording && _voiceStopwatch.isRunning,
                          inputFormatters: [
                            LengthLimitingTextInputFormatter(
                              _maxChatMessageLength,
                            ),
                          ],
                          keyboardType: TextInputType.multiline,
                          maxLines: null,
                          onTap: _ensureTextInputReady,
                          onChanged: (value) {
                            widget.onChanged(value);
                            setState(() {});
                          },
                          textInputAction: TextInputAction.newline,
                          cursorColor: const Color(0xff5aa4e8),
                          style: const TextStyle(
                            color: Color(0xff111b21),
                            fontSize: 15,
                            height: 22 / 15,
                          ),
                          decoration:
                              const InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                filled: false,
                                fillColor: Colors.transparent,
                                hoverColor: Colors.transparent,
                                isCollapsed: true,
                                contentPadding: EdgeInsets.zero,
                              ).copyWith(
                                hintText: AppLocalizations.of(
                                  context,
                                ).chatInputWriteMessageHint,
                                hintStyle: const TextStyle(
                                  color: Color(0xff9a9a9a),
                                  fontSize: 15,
                                  height: 22 / 15,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                  if (_isVoiceRecording)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
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
          const SizedBox(width: 12),
          MouseRegion(
            opaque: true,
            cursor: SystemMouseCursors.click,
            onEnter: _handleEmojiButtonEnter,
            onHover: (_) {
              if (_emojiOverlayEntry == null) {
                _showEmojiPanel();
              }
            },
            onExit: _handleEmojiButtonExit,
            child: SizedBox(
              width: 38,
              height: 38,
              child: IconButton(
                onPressed: _toggleEmojiPanel,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 38,
                  height: 38,
                ),
                icon: Image.asset(
                  'assets/chat_input/telegram_emoji.png',
                  width: 25,
                  height: 25,
                  color: _emojiOverlayEntry == null
                      ? const Color(0xff8d969c)
                      : const Color(0xff1da855),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: _isVoiceRecording
                ? AppLocalizations.of(context).mediaSend
                : hasText
                ? widget.hintText
                : AppLocalizations.of(context).voiceInputTooltip,
            onPressed: _isVoiceSending
                ? null
                : _isVoiceRecording
                ? _stopAndSendVoice
                : hasText
                ? (widget.onSend == null ? null : _send)
                : (widget.onSendVoice == null ? null : _toggleVoiceRecording),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            icon: _isVoiceSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Color(0xff1da855),
                    ),
                  )
                : _isVoiceRecording || hasText
                ? Icon(
                    Icons.send_rounded,
                    color: _isVoiceRecording
                        ? const Color(0xff1da855)
                        : const Color(0xff8d969c),
                    size: 30,
                  )
                : Image.asset(
                    'assets/chat_input/telegram_mic.png',
                    width: 25,
                    height: 25,
                    color: const Color(0xff8d969c),
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
    final backgroundRect = Offset.zero & size;
    canvas.drawRect(backgroundRect, Paint()..color = const Color(0xffbed79b));
    canvas.drawRect(
      backgroundRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xffc8dc9d), Color(0xffa8cfaa)],
        ).createShader(backgroundRect),
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xff8fa79c).withValues(alpha: 0.34);
    final softLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xff7e9d72).withValues(alpha: 0.24);
    const tileWidth = 82.0;
    const tileHeight = 74.0;
    for (var row = 0; row * tileHeight - 54 < size.height; row += 1) {
      for (var col = 0; col * tileWidth - 56 < size.width; col += 1) {
        final origin = Offset(
          col * tileWidth + (row.isOdd ? 30 : -18),
          row * tileHeight + 8,
        );
        _drawWallpaperDoodle(
          canvas,
          origin + const Offset(42, 42),
          variant: (row * 7 + col * 11) % 35,
          paint: linePaint,
        );
        _drawPatternDust(
          canvas,
          origin,
          row: row,
          col: col,
          paint: softLinePaint,
        );
      }
    }
  }

  void _drawBubble(Canvas canvas, Offset center, Paint paint) {
    final rect = Rect.fromCenter(center: center, width: 30, height: 20);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      paint,
    );
    final tail = Path()
      ..moveTo(center.dx - 8, center.dy + 10)
      ..quadraticBezierTo(
        center.dx - 2,
        center.dy + 16,
        center.dx + 4,
        center.dy + 9,
      );
    canvas.drawPath(tail, paint);
  }

  void _drawLeaf(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - 13, center.dy + 2)
      ..quadraticBezierTo(center.dx, center.dy - 18, center.dx + 14, center.dy)
      ..quadraticBezierTo(
        center.dx,
        center.dy + 16,
        center.dx - 13,
        center.dy + 2,
      );
    canvas.drawPath(path, paint);
    canvas.drawLine(
      center + const Offset(-8, 2),
      center + const Offset(10, 0),
      paint,
    );
  }

  void _drawStar(Canvas canvas, Offset center, Paint paint) {
    canvas.drawLine(
      center + const Offset(-9, 0),
      center + const Offset(9, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, -9),
      center + const Offset(0, 9),
      paint,
    );
    canvas.drawLine(
      center + const Offset(-5, -5),
      center + const Offset(5, 5),
      paint,
    );
    canvas.drawLine(
      center + const Offset(5, -5),
      center + const Offset(-5, 5),
      paint,
    );
  }

  void _drawSpark(Canvas canvas, Offset center, Paint paint) {
    canvas.drawLine(
      center + const Offset(-7, 0),
      center + const Offset(7, 0),
      paint,
    );
    canvas.drawLine(
      center + const Offset(0, -7),
      center + const Offset(0, 7),
      paint,
    );
  }

  void _drawDoubleRing(Canvas canvas, Offset center, Paint paint) {
    canvas.drawCircle(center, 9, paint);
    canvas.drawCircle(center + const Offset(14, 2), 4, paint);
  }

  void _drawTinyHeart(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy + 8)
      ..cubicTo(
        center.dx - 16,
        center.dy - 4,
        center.dx - 6,
        center.dy - 14,
        center.dx,
        center.dy - 6,
      )
      ..cubicTo(
        center.dx + 6,
        center.dy - 14,
        center.dx + 16,
        center.dy - 4,
        center.dx,
        center.dy + 8,
      );
    canvas.drawPath(path, paint);
  }

  void _drawPatternDust(
    Canvas canvas,
    Offset origin, {
    required int row,
    required int col,
    required Paint paint,
  }) {
    final seed = row * 31 + col * 17;
    final first = origin + Offset(18 + (seed % 22), 18 + (seed % 13));
    final second = origin + Offset(62 + (seed % 16), 50 + (seed % 19));
    final third = origin + Offset(36 + (seed % 28), 8 + (seed % 46));
    canvas.drawCircle(first, 1.9, paint);
    canvas.drawCircle(second, 1.5, paint);
    canvas.drawCircle(third, 1.3, paint);
    if (seed.isEven) {
      _drawSpark(canvas, origin + Offset(82, 18 + (seed % 18)), paint);
    } else {
      canvas.drawArc(
        Rect.fromCenter(
          center: origin + Offset(20 + (seed % 10), 66),
          width: 14,
          height: 14,
        ),
        0.2,
        pi * 1.45,
        false,
        paint,
      );
    }
    if (seed % 3 == 0) {
      _drawTinyHeart(canvas, origin + Offset(64, 24 + (seed % 24)), paint);
    }
  }

  void _drawChubbyCat(Canvas canvas, Offset center, Paint paint) {
    final head = Path()
      ..moveTo(center.dx - 22, center.dy - 4)
      ..lineTo(center.dx - 16, center.dy - 22)
      ..lineTo(center.dx - 4, center.dy - 12)
      ..quadraticBezierTo(
        center.dx,
        center.dy - 16,
        center.dx + 4,
        center.dy - 12,
      )
      ..lineTo(center.dx + 16, center.dy - 22)
      ..lineTo(center.dx + 22, center.dy - 4)
      ..quadraticBezierTo(
        center.dx + 24,
        center.dy + 20,
        center.dx,
        center.dy + 22,
      )
      ..quadraticBezierTo(
        center.dx - 24,
        center.dy + 20,
        center.dx - 22,
        center.dy - 4,
      )
      ..close();
    canvas.drawPath(head, paint);
    canvas.drawCircle(center + const Offset(-8, 2), 2, paint);
    canvas.drawCircle(center + const Offset(8, 2), 2, paint);
    canvas.drawArc(
      Rect.fromCenter(
        center: center + const Offset(0, 8),
        width: 14,
        height: 8,
      ),
      0.1,
      pi - 0.2,
      false,
      paint,
    );
    canvas.drawLine(
      center + const Offset(-18, 8),
      center + const Offset(-28, 5),
      paint,
    );
    canvas.drawLine(
      center + const Offset(18, 8),
      center + const Offset(28, 5),
      paint,
    );
  }

  void _drawChubbyBird(Canvas canvas, Offset center, Paint paint) {
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 48, height: 36),
      paint,
    );
    canvas.drawCircle(center + const Offset(-8, -4), 2, paint);
    final beak = Path()
      ..moveTo(center.dx + 12, center.dy - 2)
      ..lineTo(center.dx + 24, center.dy + 3)
      ..lineTo(center.dx + 12, center.dy + 7)
      ..close();
    canvas.drawPath(beak, paint);
    canvas.drawArc(
      Rect.fromCenter(
        center: center + const Offset(-4, 6),
        width: 18,
        height: 14,
      ),
      0.2,
      pi * 0.9,
      false,
      paint,
    );
    canvas.drawLine(
      center + const Offset(-10, 18),
      center + const Offset(-16, 24),
      paint,
    );
    canvas.drawLine(
      center + const Offset(6, 18),
      center + const Offset(10, 24),
      paint,
    );
  }

  void _drawRoundPenguin(Canvas canvas, Offset center, Paint paint) {
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 38, height: 50),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: center + const Offset(0, 8),
        width: 22,
        height: 26,
      ),
      paint,
    );
    canvas.drawCircle(center + const Offset(-7, -10), 2, paint);
    canvas.drawCircle(center + const Offset(7, -10), 2, paint);
    final beak = Path()
      ..moveTo(center.dx - 4, center.dy - 4)
      ..lineTo(center.dx + 4, center.dy - 4)
      ..lineTo(center.dx, center.dy + 2)
      ..close();
    canvas.drawPath(beak, paint);
    canvas.drawLine(
      center + const Offset(-18, 4),
      center + const Offset(-28, 12),
      paint,
    );
    canvas.drawLine(
      center + const Offset(18, 4),
      center + const Offset(28, 12),
      paint,
    );
  }

  void _drawTinyWhale(Canvas canvas, Offset center, Paint paint) {
    final body = Path()
      ..moveTo(center.dx - 28, center.dy + 4)
      ..quadraticBezierTo(
        center.dx - 14,
        center.dy - 18,
        center.dx + 14,
        center.dy - 12,
      )
      ..quadraticBezierTo(
        center.dx + 30,
        center.dy - 8,
        center.dx + 26,
        center.dy + 8,
      )
      ..quadraticBezierTo(
        center.dx + 2,
        center.dy + 22,
        center.dx - 28,
        center.dy + 4,
      )
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawCircle(center + const Offset(8, -4), 2, paint);
    final tail = Path()
      ..moveTo(center.dx - 28, center.dy + 4)
      ..lineTo(center.dx - 42, center.dy - 8)
      ..lineTo(center.dx - 38, center.dy + 8)
      ..lineTo(center.dx - 48, center.dy + 18);
    canvas.drawPath(tail, paint);
    canvas.drawArc(
      Rect.fromCenter(
        center: center + const Offset(-4, 4),
        width: 16,
        height: 12,
      ),
      0.1,
      pi * 0.8,
      false,
      paint,
    );
  }

  void _drawPaperPlane(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - 24, center.dy - 10)
      ..lineTo(center.dx + 26, center.dy)
      ..lineTo(center.dx - 18, center.dy + 18)
      ..lineTo(center.dx - 8, center.dy + 2)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      center + const Offset(-8, 2),
      center + const Offset(26, 0),
      paint,
    );
  }

  void _drawBanana(Canvas canvas, Offset center, Paint paint) {
    final outer = Path()
      ..moveTo(center.dx - 28, center.dy - 8)
      ..cubicTo(
        center.dx - 8,
        center.dy + 26,
        center.dx + 26,
        center.dy + 18,
        center.dx + 32,
        center.dy - 12,
      );
    final inner = Path()
      ..moveTo(center.dx - 18, center.dy - 2)
      ..cubicTo(
        center.dx - 2,
        center.dy + 12,
        center.dx + 16,
        center.dy + 8,
        center.dx + 22,
        center.dy - 10,
      );
    canvas.drawPath(outer, paint);
    canvas.drawPath(inner, paint);
  }

  void _drawRocket(Canvas canvas, Offset center, Paint paint) {
    final body = Path()
      ..moveTo(center.dx, center.dy - 28)
      ..quadraticBezierTo(
        center.dx + 18,
        center.dy - 8,
        center.dx + 8,
        center.dy + 22,
      )
      ..lineTo(center.dx - 8, center.dy + 22)
      ..quadraticBezierTo(
        center.dx - 18,
        center.dy - 8,
        center.dx,
        center.dy - 28,
      )
      ..close();
    canvas.drawPath(body, paint);
    canvas.drawCircle(center + const Offset(0, -4), 5, paint);
    canvas.drawLine(
      center + const Offset(-8, 18),
      center + const Offset(-18, 28),
      paint,
    );
    canvas.drawLine(
      center + const Offset(8, 18),
      center + const Offset(18, 28),
      paint,
    );
  }

  void _drawFlower(Canvas canvas, Offset center, Paint paint) {
    for (var i = 0; i < 5; i += 1) {
      final angle = i * pi * 2 / 5;
      canvas.drawOval(
        Rect.fromCenter(
          center: center + Offset(cos(angle) * 10, sin(angle) * 10),
          width: 12,
          height: 8,
        ),
        paint,
      );
    }
    canvas.drawCircle(center, 3, paint);
    canvas.drawLine(
      center + const Offset(0, 12),
      center + const Offset(0, 28),
      paint,
    );
  }

  void _drawCloud(Canvas canvas, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - 28, center.dy + 8)
      ..cubicTo(
        center.dx - 26,
        center.dy - 8,
        center.dx - 10,
        center.dy - 10,
        center.dx - 4,
        center.dy - 3,
      )
      ..cubicTo(
        center.dx + 2,
        center.dy - 18,
        center.dx + 24,
        center.dy - 10,
        center.dx + 20,
        center.dy + 4,
      )
      ..cubicTo(
        center.dx + 34,
        center.dy + 4,
        center.dx + 32,
        center.dy + 18,
        center.dx + 18,
        center.dy + 18,
      )
      ..lineTo(center.dx - 18, center.dy + 18)
      ..cubicTo(
        center.dx - 30,
        center.dy + 18,
        center.dx - 36,
        center.dy + 10,
        center.dx - 28,
        center.dy + 8,
      );
    canvas.drawPath(path, paint);
  }

  void _drawPineapple(Canvas canvas, Offset center, Paint paint) {
    canvas.drawOval(
      Rect.fromCenter(center: center, width: 26, height: 42),
      paint,
    );
    canvas.drawLine(
      center + const Offset(-8, -8),
      center + const Offset(8, 8),
      paint,
    );
    canvas.drawLine(
      center + const Offset(8, -8),
      center + const Offset(-8, 8),
      paint,
    );
    final crown = Path()
      ..moveTo(center.dx - 8, center.dy - 22)
      ..lineTo(center.dx - 14, center.dy - 38)
      ..lineTo(center.dx, center.dy - 26)
      ..lineTo(center.dx + 10, center.dy - 40)
      ..lineTo(center.dx + 8, center.dy - 22);
    canvas.drawPath(crown, paint);
  }

  void _drawCandy(Canvas canvas, Offset center, Paint paint) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 28, height: 14),
        const Radius.circular(8),
      ),
      paint,
    );
    canvas.drawLine(
      center + const Offset(-14, 0),
      center + const Offset(-24, -8),
      paint,
    );
    canvas.drawLine(
      center + const Offset(-14, 0),
      center + const Offset(-24, 8),
      paint,
    );
    canvas.drawLine(
      center + const Offset(14, 0),
      center + const Offset(24, -8),
      paint,
    );
    canvas.drawLine(
      center + const Offset(14, 0),
      center + const Offset(24, 8),
      paint,
    );
  }

  void _drawWallpaperDoodle(
    Canvas canvas,
    Offset center, {
    required int variant,
    required Paint paint,
  }) {
    switch (variant) {
      case 0:
        _drawChubbyCat(canvas, center, paint);
      case 1:
        _drawPaperPlane(canvas, center, paint);
      case 2:
        _drawBanana(canvas, center, paint);
      case 3:
        _drawRocket(canvas, center, paint);
      case 4:
        _drawChubbyBird(canvas, center, paint);
      case 5:
        _drawPineapple(canvas, center, paint);
      case 6:
        _drawLeaf(canvas, center, paint);
      case 7:
        _drawRoundPenguin(canvas, center, paint);
      case 8:
        _drawTinyWhale(canvas, center, paint);
      case 9:
        _drawCloud(canvas, center, paint);
      case 10:
        _drawFlower(canvas, center, paint);
      case 11:
        _drawBubble(canvas, center, paint);
      case 12:
        _drawCandy(canvas, center, paint);
      case 13:
        _drawTinyHeart(canvas, center, paint);
      case 14:
        _drawStar(canvas, center, paint);
      case 15:
        _drawDoubleRing(canvas, center, paint);
      case 16:
        _drawCastle(canvas, center, paint);
      case 17:
        _drawPizza(canvas, center, paint);
      case 18:
        _drawDonut(canvas, center, paint);
      case 19:
        _drawMoon(canvas, center, paint);
      case 20:
        _drawRobot(canvas, center, paint);
      case 21:
        _drawPlanet(canvas, center, paint);
      case 22:
        _drawGamepad(canvas, center, paint);
      case 23:
        _drawGift(canvas, center, paint);
      case 24:
        _drawIceCream(canvas, center, paint);
      case 25:
        _drawFish(canvas, center, paint);
      case 26:
        _drawBone(canvas, center, paint);
      case 27:
        _drawBurger(canvas, center, paint);
      case 28:
        _drawCrown(canvas, center, paint);
      case 29:
        _drawMushroom(canvas, center, paint);
      case 30:
        _drawBalloon(canvas, center, paint);
      case 31:
        _drawAnchor(canvas, center, paint);
      case 32:
        _drawSubmarine(canvas, center, paint);
      case 33:
        _drawPencil(canvas, center, paint);
      case 34:
        _drawUfo(canvas, center, paint);
      default:
        _drawCamera(canvas, center, paint);
    }
  }

  void _drawCastle(Canvas canvas, Offset c, Paint p) {
    final path = Path()
      ..moveTo(c.dx - 18, c.dy + 14)
      ..lineTo(c.dx - 18, c.dy - 10)
      ..lineTo(c.dx - 10, c.dy - 10)
      ..lineTo(c.dx - 10, c.dy - 18)
      ..lineTo(c.dx - 2, c.dy - 18)
      ..lineTo(c.dx - 2, c.dy - 10)
      ..lineTo(c.dx + 8, c.dy - 10)
      ..lineTo(c.dx + 8, c.dy - 18)
      ..lineTo(c.dx + 16, c.dy - 18)
      ..lineTo(c.dx + 16, c.dy + 14)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(-1, 14), width: 12, height: 18),
      pi,
      pi,
      false,
      p,
    );
  }

  void _drawPizza(Canvas canvas, Offset c, Paint p) {
    final path = Path()
      ..moveTo(c.dx - 16, c.dy - 14)
      ..lineTo(c.dx + 18, c.dy - 6)
      ..lineTo(c.dx - 6, c.dy + 18)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(-1, -4), width: 34, height: 12),
      0.2,
      pi * 0.9,
      false,
      p,
    );
    canvas.drawCircle(c + const Offset(-2, 0), 1.8, p);
    canvas.drawCircle(c + const Offset(6, -4), 1.5, p);
  }

  void _drawDonut(Canvas canvas, Offset c, Paint p) {
    canvas.drawCircle(c, 15, p);
    canvas.drawCircle(c, 6, p);
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(1, -1), width: 22, height: 18),
      0.4,
      pi * 0.8,
      false,
      p,
    );
  }

  void _drawMoon(Canvas canvas, Offset c, Paint p) {
    canvas.drawArc(
      Rect.fromCenter(center: c, width: 28, height: 32),
      pi * 0.34,
      pi * 1.34,
      false,
      p,
    );
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(8, -1), width: 22, height: 28),
      pi * 0.44,
      pi * 1.12,
      false,
      p,
    );
  }

  void _drawRobot(Canvas canvas, Offset c, Paint p) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 28, height: 24),
        const Radius.circular(5),
      ),
      p,
    );
    canvas.drawLine(c + const Offset(0, -12), c + const Offset(0, -20), p);
    canvas.drawCircle(c + const Offset(0, -22), 2, p);
    canvas.drawCircle(c + const Offset(-7, -2), 2, p);
    canvas.drawCircle(c + const Offset(7, -2), 2, p);
    canvas.drawLine(c + const Offset(-7, 8), c + const Offset(7, 8), p);
  }

  void _drawPlanet(Canvas canvas, Offset c, Paint p) {
    canvas.drawCircle(c, 12, p);
    canvas.drawArc(
      Rect.fromCenter(center: c, width: 40, height: 14),
      0,
      pi,
      false,
      p,
    );
    canvas.drawArc(
      Rect.fromCenter(center: c, width: 40, height: 14),
      pi,
      pi,
      false,
      p,
    );
  }

  void _drawGamepad(Canvas canvas, Offset c, Paint p) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 38, height: 22),
        const Radius.circular(10),
      ),
      p,
    );
    canvas.drawLine(c + const Offset(-13, 0), c + const Offset(-5, 0), p);
    canvas.drawLine(c + const Offset(-9, -4), c + const Offset(-9, 4), p);
    canvas.drawCircle(c + const Offset(8, -2), 1.8, p);
    canvas.drawCircle(c + const Offset(15, 3), 1.8, p);
  }

  void _drawGift(Canvas canvas, Offset c, Paint p) {
    canvas.drawRect(Rect.fromCenter(center: c, width: 28, height: 24), p);
    canvas.drawLine(c + const Offset(0, -12), c + const Offset(0, 12), p);
    canvas.drawLine(c + const Offset(-14, -4), c + const Offset(14, -4), p);
    canvas.drawOval(
      Rect.fromCenter(center: c + const Offset(-6, -16), width: 12, height: 8),
      p,
    );
    canvas.drawOval(
      Rect.fromCenter(center: c + const Offset(6, -16), width: 12, height: 8),
      p,
    );
  }

  void _drawIceCream(Canvas canvas, Offset c, Paint p) {
    canvas.drawCircle(c + const Offset(0, -10), 11, p);
    final cone = Path()
      ..moveTo(c.dx - 10, c.dy)
      ..lineTo(c.dx + 10, c.dy)
      ..lineTo(c.dx, c.dy + 24)
      ..close();
    canvas.drawPath(cone, p);
  }

  void _drawFish(Canvas canvas, Offset c, Paint p) {
    canvas.drawOval(Rect.fromCenter(center: c, width: 34, height: 18), p);
    final tail = Path()
      ..moveTo(c.dx - 17, c.dy)
      ..lineTo(c.dx - 30, c.dy - 10)
      ..lineTo(c.dx - 30, c.dy + 10)
      ..close();
    canvas.drawPath(tail, p);
    canvas.drawCircle(c + const Offset(9, -2), 1.8, p);
  }

  void _drawBone(Canvas canvas, Offset c, Paint p) {
    canvas.drawLine(c + const Offset(-14, -8), c + const Offset(14, 8), p);
    canvas.drawCircle(c + const Offset(-18, -10), 5, p);
    canvas.drawCircle(c + const Offset(-12, -16), 5, p);
    canvas.drawCircle(c + const Offset(18, 10), 5, p);
    canvas.drawCircle(c + const Offset(12, 16), 5, p);
  }

  void _drawBurger(Canvas canvas, Offset c, Paint p) {
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(0, -4), width: 34, height: 22),
      pi,
      pi,
      false,
      p,
    );
    canvas.drawLine(c + const Offset(-17, 2), c + const Offset(17, 2), p);
    canvas.drawLine(c + const Offset(-15, 10), c + const Offset(15, 10), p);
  }

  void _drawCrown(Canvas canvas, Offset c, Paint p) {
    final path = Path()
      ..moveTo(c.dx - 18, c.dy + 10)
      ..lineTo(c.dx - 14, c.dy - 12)
      ..lineTo(c.dx - 4, c.dy + 2)
      ..lineTo(c.dx + 4, c.dy - 14)
      ..lineTo(c.dx + 14, c.dy + 2)
      ..lineTo(c.dx + 18, c.dy - 12)
      ..lineTo(c.dx + 18, c.dy + 10)
      ..close();
    canvas.drawPath(path, p);
  }

  void _drawMushroom(Canvas canvas, Offset c, Paint p) {
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(0, -2), width: 34, height: 26),
      pi,
      pi,
      false,
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c + const Offset(0, 10), width: 14, height: 20),
        const Radius.circular(7),
      ),
      p,
    );
    canvas.drawCircle(c + const Offset(-8, -8), 2, p);
    canvas.drawCircle(c + const Offset(8, -7), 2, p);
  }

  void _drawBalloon(Canvas canvas, Offset c, Paint p) {
    canvas.drawOval(
      Rect.fromCenter(center: c + const Offset(0, -8), width: 24, height: 30),
      p,
    );
    canvas.drawLine(c + const Offset(0, 8), c + const Offset(-4, 24), p);
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(0, 23), width: 10, height: 8),
      0,
      pi,
      false,
      p,
    );
  }

  void _drawAnchor(Canvas canvas, Offset c, Paint p) {
    canvas.drawCircle(c + const Offset(0, -14), 5, p);
    canvas.drawLine(c + const Offset(0, -9), c + const Offset(0, 16), p);
    canvas.drawLine(c + const Offset(-10, -2), c + const Offset(10, -2), p);
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(0, 6), width: 34, height: 28),
      0.15,
      pi - 0.3,
      false,
      p,
    );
  }

  void _drawSubmarine(Canvas canvas, Offset c, Paint p) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 40, height: 20),
        const Radius.circular(12),
      ),
      p,
    );
    canvas.drawLine(c + const Offset(0, -10), c + const Offset(0, -20), p);
    canvas.drawLine(c + const Offset(0, -20), c + const Offset(10, -20), p);
    canvas.drawCircle(c + const Offset(-9, 0), 3, p);
    canvas.drawCircle(c + const Offset(7, 0), 3, p);
  }

  void _drawPencil(Canvas canvas, Offset c, Paint p) {
    final path = Path()
      ..moveTo(c.dx - 20, c.dy + 12)
      ..lineTo(c.dx + 10, c.dy - 18)
      ..lineTo(c.dx + 20, c.dy - 8)
      ..lineTo(c.dx - 10, c.dy + 22)
      ..close();
    canvas.drawPath(path, p);
    canvas.drawLine(c + const Offset(10, -18), c + const Offset(20, -8), p);
  }

  void _drawUfo(Canvas canvas, Offset c, Paint p) {
    canvas.drawOval(Rect.fromCenter(center: c, width: 42, height: 14), p);
    canvas.drawArc(
      Rect.fromCenter(center: c + const Offset(0, -4), width: 22, height: 20),
      pi,
      pi,
      false,
      p,
    );
    canvas.drawCircle(c + const Offset(-10, 2), 1.6, p);
    canvas.drawCircle(c + const Offset(10, 2), 1.6, p);
  }

  void _drawCamera(Canvas canvas, Offset c, Paint p) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 34, height: 24),
        const Radius.circular(5),
      ),
      p,
    );
    canvas.drawRect(
      Rect.fromCenter(center: c + const Offset(-8, -14), width: 12, height: 6),
      p,
    );
    canvas.drawCircle(c, 7, p);
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
    this.nodisturbStatus = 0,
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
  final int nodisturbStatus;
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
      nodisturbStatus: nodisturbStatus,
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
    int appUserId,
  ) {
    final displayName = conversation.displayName;
    final initial = displayName.characters.isEmpty
        ? '#'
        : displayName.characters.first.toUpperCase();
    final hasLastMessage = conversation.lastMessage.trim().isNotEmpty;
    final isOutgoingLastMessage = conversation.lastSenderUserId == appUserId;
    return _Conversation(
      name: displayName,
      message: hasLastMessage
          ? _chatPreviewText(conversation.lastMessage)
          : conversation.isOnline
          ? l10n.workspaceUserOnline
          : l10n.appAccountStatusOffline,
      time: conversation.lastMessageTime == null
          ? ''
          : _chatListTimeText(conversation.lastMessageTime!),
      color: avatarColorFor(conversation.peerUserId),
      emoji: initial,
      avatarUrl: conversation.roomImg,
      targetUserId: conversation.peerUserId,
      roomId: conversation.roomId,
      pinned: conversation.topStatus == 1,
      delivered: isOutgoingLastMessage && hasLastMessage,
      deliveredRead:
          isOutgoingLastMessage &&
          hasLastMessage &&
          conversation.readReceipt != 0 &&
          conversation.lastMessageStatus == 2,
      readReceiptEnabled: conversation.readReceipt != 0,
      isOnline: conversation.isOnline,
      nodisturbStatus: conversation.nodisturbStatus,
      unread: conversation.unreadCount,
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
    required this.createdAt,
    this.width = 342,
    this.singleLine = false,
    this.media,
  }) : outgoing = false,
       sendStatus = ChatMessageSendStatus.sent;

  const _ChatMessage.outgoing({
    required this.text,
    required this.time,
    required this.createdAt,
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
        createdAt: message.createdAt,
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
      createdAt: message.createdAt,
      width: media == null ? _bubbleWidthFor(message.text) : media.bubbleWidth,
      sendStatus: message.sendStatus,
      media: media,
    );
  }

  final String text;
  final String time;
  final DateTime createdAt;
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
