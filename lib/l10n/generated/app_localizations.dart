import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'BB Planet Chat Ops'**
  String get appTitle;

  /// No description provided for @operatorLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in with an admin account, then connect a real APP account for 1:1 chat operations.'**
  String get operatorLoginSubtitle;

  /// No description provided for @operatorAccount.
  ///
  /// In en, this message translates to:
  /// **'Operator account'**
  String get operatorAccount;

  /// No description provided for @operatorAccountRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the operator account.'**
  String get operatorAccountRequired;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the password.'**
  String get passwordRequired;

  /// No description provided for @googleCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Google code (if required)'**
  String get googleCodeOptional;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @devEnterWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Development: enter workspace'**
  String get devEnterWorkspace;

  /// No description provided for @leftPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get leftPanelTitle;

  /// No description provided for @middlePanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get middlePanelTitle;

  /// No description provided for @rightPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get rightPanelTitle;

  /// No description provided for @operatorIdentity.
  ///
  /// In en, this message translates to:
  /// **'Operator identity'**
  String get operatorIdentity;

  /// No description provided for @speakingIdentity.
  ///
  /// In en, this message translates to:
  /// **'Speaking identity'**
  String get speakingIdentity;

  /// No description provided for @noAppAccountSelected.
  ///
  /// In en, this message translates to:
  /// **'No APP account selected'**
  String get noAppAccountSelected;

  /// No description provided for @addAppAccount.
  ///
  /// In en, this message translates to:
  /// **'Add APP account'**
  String get addAppAccount;

  /// No description provided for @switchAppAccount.
  ///
  /// In en, this message translates to:
  /// **'Switch APP account'**
  String get switchAppAccount;

  /// No description provided for @signingInAppAccount.
  ///
  /// In en, this message translates to:
  /// **'Signing in...'**
  String get signingInAppAccount;

  /// No description provided for @appAccountLoginTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign in APP account'**
  String get appAccountLoginTitle;

  /// No description provided for @appAccountLoginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use a real APP account as the speaking identity for IM.'**
  String get appAccountLoginSubtitle;

  /// No description provided for @appAccountEmail.
  ///
  /// In en, this message translates to:
  /// **'APP account email'**
  String get appAccountEmail;

  /// No description provided for @appAccountEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the APP account email.'**
  String get appAccountEmailRequired;

  /// No description provided for @appAccountPassword.
  ///
  /// In en, this message translates to:
  /// **'APP account password'**
  String get appAccountPassword;

  /// No description provided for @appAccountPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter the APP account password.'**
  String get appAccountPasswordRequired;

  /// No description provided for @forceAppAccountLogin.
  ///
  /// In en, this message translates to:
  /// **'Force login'**
  String get forceAppAccountLogin;

  /// No description provided for @forceAppAccountLoginHint.
  ///
  /// In en, this message translates to:
  /// **'Use this only when the server says the device is already bound.'**
  String get forceAppAccountLoginHint;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @signInAppAccount.
  ///
  /// In en, this message translates to:
  /// **'Sign in APP account'**
  String get signInAppAccount;

  /// No description provided for @appAccountHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Real APP account list'**
  String get appAccountHistoryTitle;

  /// No description provided for @appAccountHistorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the real APP account used as the current chat identity.'**
  String get appAccountHistorySubtitle;

  /// No description provided for @appAccountHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No real APP accounts have been signed in on this device yet.'**
  String get appAccountHistoryEmpty;

  /// No description provided for @appAccountStatusOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get appAccountStatusOnline;

  /// No description provided for @appAccountStatusSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get appAccountStatusSwitch;

  /// No description provided for @appAccountStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get appAccountStatusOffline;

  /// No description provided for @searchUserHint.
  ///
  /// In en, this message translates to:
  /// **'Search UID, nickname, or email'**
  String get searchUserHint;

  /// No description provided for @selectCompanionFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a companion account first.'**
  String get selectCompanionFirst;

  /// No description provided for @identityGuardHint.
  ///
  /// In en, this message translates to:
  /// **'Confirm who is speaking and who receives the message before sending.'**
  String get identityGuardHint;

  /// No description provided for @selectConversationFirst.
  ///
  /// In en, this message translates to:
  /// **'Select a chat target to open the 1:1 conversation.'**
  String get selectConversationFirst;

  /// No description provided for @messageInputDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Message input is available after selecting a chat target.'**
  String get messageInputDisabledHint;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageTraditionalChinese.
  ///
  /// In en, this message translates to:
  /// **'Traditional Chinese'**
  String get languageTraditionalChinese;

  /// No description provided for @languageVietnamese.
  ///
  /// In en, this message translates to:
  /// **'Vietnamese'**
  String get languageVietnamese;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @navChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get navChats;

  /// No description provided for @navNew.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get navNew;

  /// No description provided for @navOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get navOnline;

  /// No description provided for @navRichs.
  ///
  /// In en, this message translates to:
  /// **'Richs'**
  String get navRichs;

  /// No description provided for @navLogin.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get navLogin;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @workspaceSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search or start a new chat'**
  String get workspaceSearchHint;

  /// No description provided for @workspaceLoadingUsers.
  ///
  /// In en, this message translates to:
  /// **'Loading users...'**
  String get workspaceLoadingUsers;

  /// No description provided for @workspaceUsersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No users found for this category.'**
  String get workspaceUsersEmpty;

  /// No description provided for @workspaceUsersLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in an APP account before loading real users.'**
  String get workspaceUsersLoginRequired;

  /// No description provided for @workspaceUsersLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load users. Please try again later.'**
  String get workspaceUsersLoadFailed;

  /// No description provided for @workspaceMessageInputHint.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get workspaceMessageInputHint;

  /// No description provided for @messageReadMore.
  ///
  /// In en, this message translates to:
  /// **'Read more'**
  String get messageReadMore;

  /// No description provided for @workspaceUserOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get workspaceUserOnline;

  /// No description provided for @mockClairePreview.
  ///
  /// In en, this message translates to:
  /// **'Haha oh man'**
  String get mockClairePreview;

  /// No description provided for @mockJoePreview.
  ///
  /// In en, this message translates to:
  /// **'Haha that’s terrifying 😂'**
  String get mockJoePreview;

  /// No description provided for @mockOptimusPreview.
  ///
  /// In en, this message translates to:
  /// **'My name is Optimus prime 🤖'**
  String get mockOptimusPreview;

  /// No description provided for @mockYvesPreview.
  ///
  /// In en, this message translates to:
  /// **'Bro, that’s so sick ⚡'**
  String get mockYvesPreview;

  /// No description provided for @mockNewUserPreview.
  ///
  /// In en, this message translates to:
  /// **'New user joined 2 minutes ago'**
  String get mockNewUserPreview;

  /// No description provided for @mockNeedsGreetingPreview.
  ///
  /// In en, this message translates to:
  /// **'Needs first greeting'**
  String get mockNeedsGreetingPreview;

  /// No description provided for @mockViewedProfilePreview.
  ///
  /// In en, this message translates to:
  /// **'Viewed profile card'**
  String get mockViewedProfilePreview;

  /// No description provided for @mockActiveNowPreview.
  ///
  /// In en, this message translates to:
  /// **'Active now'**
  String get mockActiveNowPreview;

  /// No description provided for @mockBrowsingChatPreview.
  ///
  /// In en, this message translates to:
  /// **'Browsing chat page'**
  String get mockBrowsingChatPreview;

  /// No description provided for @mockReplyRatePreview.
  ///
  /// In en, this message translates to:
  /// **'Reply rate is high'**
  String get mockReplyRatePreview;

  /// No description provided for @mockHighValuePreview.
  ///
  /// In en, this message translates to:
  /// **'High value user'**
  String get mockHighValuePreview;

  /// No description provided for @mockToppedUpPreview.
  ///
  /// In en, this message translates to:
  /// **'Recently topped up'**
  String get mockToppedUpPreview;

  /// No description provided for @mockFastRepliesPreview.
  ///
  /// In en, this message translates to:
  /// **'Prefers fast replies'**
  String get mockFastRepliesPreview;

  /// No description provided for @mockWelcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome to BB Planet. Nice to meet you.'**
  String get mockWelcomeMessage;

  /// No description provided for @mockHelpStartMessage.
  ///
  /// In en, this message translates to:
  /// **'Can someone help me start?'**
  String get mockHelpStartMessage;

  /// No description provided for @mockPremiumMessage.
  ///
  /// In en, this message translates to:
  /// **'Show me premium profiles.'**
  String get mockPremiumMessage;

  /// No description provided for @mockPremiumReply.
  ///
  /// In en, this message translates to:
  /// **'I can help you find the best matches.'**
  String get mockPremiumReply;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
