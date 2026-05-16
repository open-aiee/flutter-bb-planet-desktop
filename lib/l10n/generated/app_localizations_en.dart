// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'BB Planet Chat Ops';

  @override
  String get operatorLoginSubtitle =>
      'Sign in with an admin account, then connect a real APP account for 1:1 chat operations.';

  @override
  String get operatorAccount => 'Operator account';

  @override
  String get operatorAccountRequired => 'Please enter the operator account.';

  @override
  String get password => 'Password';

  @override
  String get passwordRequired => 'Please enter the password.';

  @override
  String get googleCodeOptional => 'Google code (if required)';

  @override
  String get signIn => 'Sign in';

  @override
  String get devEnterWorkspace => 'Development: enter workspace';

  @override
  String get leftPanelTitle => 'Accounts';

  @override
  String get middlePanelTitle => 'Conversations';

  @override
  String get rightPanelTitle => 'Chat';

  @override
  String get operatorIdentity => 'Operator identity';

  @override
  String get speakingIdentity => 'Speaking identity';

  @override
  String get noAppAccountSelected => 'No APP account selected';

  @override
  String get addAppAccount => 'Add APP account';

  @override
  String get switchAppAccount => 'Switch APP account';

  @override
  String get signingInAppAccount => 'Signing in...';

  @override
  String get appAccountLoginTitle => 'Sign in APP account';

  @override
  String get appAccountLoginSubtitle =>
      'Use a real APP account as the speaking identity for IM.';

  @override
  String get appAccountEmail => 'APP account email';

  @override
  String get appAccountEmailRequired => 'Please enter the APP account email.';

  @override
  String get appAccountPassword => 'APP account password';

  @override
  String get appAccountPasswordRequired =>
      'Please enter the APP account password.';

  @override
  String get forceAppAccountLogin => 'Force login';

  @override
  String get forceAppAccountLoginHint =>
      'Use this only when the server says the device is already bound.';

  @override
  String get cancel => 'Cancel';

  @override
  String get signInAppAccount => 'Sign in APP account';

  @override
  String get appAccountHistoryTitle => 'Real APP account list';

  @override
  String get appAccountHistorySubtitle =>
      'Choose the real APP account used as the current chat identity.';

  @override
  String get appAccountHistoryEmpty =>
      'No real APP accounts have been signed in on this device yet.';

  @override
  String get appAccountStatusOnline => 'Online';

  @override
  String get appAccountStatusSwitch => 'Switch';

  @override
  String get appAccountStatusOffline => 'Offline';

  @override
  String get searchUserHint => 'Search UID, nickname, or email';

  @override
  String get selectCompanionFirst => 'Select a companion account first.';

  @override
  String get identityGuardHint =>
      'Confirm who is speaking and who receives the message before sending.';

  @override
  String get selectConversationFirst =>
      'Select a chat target to open the 1:1 conversation.';

  @override
  String get messageInputDisabledHint =>
      'Message input is available after selecting a chat target.';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTraditionalChinese => 'Traditional Chinese';

  @override
  String get languageVietnamese => 'Vietnamese';

  @override
  String get close => 'Close';

  @override
  String get navChats => 'Chats';

  @override
  String get navNew => 'New';

  @override
  String get navOnline => 'Online';

  @override
  String get navRichs => 'Richs';

  @override
  String get navLogin => 'Login';

  @override
  String get navSettings => 'Settings';

  @override
  String get workspaceSearchHint => 'Search or start a new chat';

  @override
  String get workspaceLoadingUsers => 'Loading users...';

  @override
  String get workspaceUsersEmpty => 'No users found for this category.';

  @override
  String get workspaceUsersLoginRequired =>
      'Sign in an APP account before loading real users.';

  @override
  String get workspaceUsersLoadFailed =>
      'Unable to load users. Please try again later.';

  @override
  String get workspaceMessageInputHint => 'Type a message';

  @override
  String get messageReadMore => 'Read more';

  @override
  String get emojiRecentTitle => 'Recently used';

  @override
  String get emojiSmileysTitle => 'Smileys & People';

  @override
  String get mediaUnsupportedFile => 'Please select one photo or video.';

  @override
  String mediaVideoSizeLimit(String sizeMb) {
    return 'Video size cannot exceed $sizeMb MB.';
  }

  @override
  String mediaSelected(String fileName) {
    return 'Selected: $fileName';
  }

  @override
  String get mediaPreviewTitle => '1 Media';

  @override
  String get mediaCaptionHint => 'Add a caption...';

  @override
  String get mediaVideoLabel => 'Video';

  @override
  String get mediaSend => 'Send';

  @override
  String get mediaSending => 'Sending...';

  @override
  String get mediaSendPending => 'Media sending is not connected yet.';

  @override
  String get voiceRecordTitle => 'Voice message';

  @override
  String get voiceRecordHint =>
      'Click start, speak, then send. Up to 60 seconds.';

  @override
  String get voiceRecordingHint => 'Recording... click stop when finished.';

  @override
  String get voiceRecordReady => 'Voice is ready. Send it or record again.';

  @override
  String get voiceRecordAgain => 'Record again';

  @override
  String get voiceStart => 'Start';

  @override
  String get voiceStop => 'Stop';

  @override
  String get voicePermissionDenied =>
      'Microphone permission is required to record voice.';

  @override
  String get voiceTooShort => 'Voice message is too short.';

  @override
  String get voiceRecordFailed => 'Voice recording failed. Please try again.';

  @override
  String get voiceCancelRecording => 'Cancel recording';

  @override
  String get voiceInputTooltip => 'Voice';

  @override
  String get attachmentTooltip => 'Attach';

  @override
  String get chatInputWriteMessageHint => 'Write a message...';

  @override
  String get chatOpenFailed => 'Unable to open chat.';

  @override
  String get chatPrivateAccountBlocked =>
      'The other party has opened a private account.';

  @override
  String get chatYouBlockedPeer => 'You have blocked the other party.';

  @override
  String get chatYouWereBlocked => 'You have been blocked.';

  @override
  String get chatPeerClosedPrivateChat =>
      'The other party closed the private chat.';

  @override
  String get dateToday => 'TODAY';

  @override
  String get dateYesterday => 'YESTERDAY';

  @override
  String get contactInfoBack => 'Back';

  @override
  String get contactInfoTitle => 'Info';

  @override
  String get contactInfoMessage => 'Message';

  @override
  String get contactInfoCall => 'Call';

  @override
  String get contactInfoMore => 'More';

  @override
  String get contactInfoUsername => 'username';

  @override
  String get contactInfoLastSeenRecently => 'last seen recently';

  @override
  String get contactInfoAddContact => 'Add Contact';

  @override
  String get contactInfoBlockUser => 'Block User';

  @override
  String get contactInfoMedia => 'Media';

  @override
  String get contactInfoNoMedia => 'No media yet';

  @override
  String get loginQrTitle => 'To use Desktop on your computer:';

  @override
  String get loginQrStepOpenApp => 'Open App on your phone';

  @override
  String get loginQrStepFindQr => 'Find the top right corner of my page';

  @override
  String get loginQrStepTapQr => 'Tap on QR';

  @override
  String get loginQrStepScanCode =>
      'Point your phone to this screen to capture the code';

  @override
  String get loginQrScanToSignIn => 'Scan to sign in';

  @override
  String get workspaceUserOnline => 'Online';

  @override
  String get mockClairePreview => 'Haha oh man';

  @override
  String get mockJoePreview => 'Haha that’s terrifying 😂';

  @override
  String get mockOptimusPreview => 'My name is Optimus prime 🤖';

  @override
  String get mockYvesPreview => 'Bro, that’s so sick ⚡';

  @override
  String get mockNewUserPreview => 'New user joined 2 minutes ago';

  @override
  String get mockNeedsGreetingPreview => 'Needs first greeting';

  @override
  String get mockViewedProfilePreview => 'Viewed profile card';

  @override
  String get mockActiveNowPreview => 'Active now';

  @override
  String get mockBrowsingChatPreview => 'Browsing chat page';

  @override
  String get mockReplyRatePreview => 'Reply rate is high';

  @override
  String get mockHighValuePreview => 'High value user';

  @override
  String get mockToppedUpPreview => 'Recently topped up';

  @override
  String get mockFastRepliesPreview => 'Prefers fast replies';

  @override
  String get mockWelcomeMessage => 'Welcome to BB Planet. Nice to meet you.';

  @override
  String get mockHelpStartMessage => 'Can someone help me start?';

  @override
  String get mockPremiumMessage => 'Show me premium profiles.';

  @override
  String get mockPremiumReply => 'I can help you find the best matches.';
}
