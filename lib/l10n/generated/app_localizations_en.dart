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
}
