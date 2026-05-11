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
  String get password => 'Password';

  @override
  String get signIn => 'Sign in';

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
