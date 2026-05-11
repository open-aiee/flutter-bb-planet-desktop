// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'BB Planet 運營聊天工作台';

  @override
  String get operatorLoginSubtitle => '先使用管理後台帳號登入，再連接真實 APP 帳號進行 1 對 1 聊天運營。';

  @override
  String get operatorAccount => '操作人帳號';

  @override
  String get operatorAccountRequired => '請輸入操作人帳號。';

  @override
  String get password => '密碼';

  @override
  String get passwordRequired => '請輸入密碼。';

  @override
  String get googleCodeOptional => 'Google 驗證碼（如需要）';

  @override
  String get signIn => '登入';

  @override
  String get devEnterWorkspace => '開發模式：直接進入工作台';

  @override
  String get leftPanelTitle => '帳號';

  @override
  String get middlePanelTitle => '會話';

  @override
  String get rightPanelTitle => '聊天';

  @override
  String get operatorIdentity => '操作人身份';

  @override
  String get speakingIdentity => '發言身份';

  @override
  String get noAppAccountSelected => '尚未選擇 APP 帳號';

  @override
  String get addAppAccount => '新增 APP 帳號';

  @override
  String get switchAppAccount => '切換 APP 帳號';

  @override
  String get signingInAppAccount => '登入中...';

  @override
  String get appAccountLoginTitle => '登入 APP 帳號';

  @override
  String get appAccountLoginSubtitle => '使用真實 APP 帳號作為 IM 發言身份。';

  @override
  String get appAccountEmail => 'APP 帳號郵箱';

  @override
  String get appAccountEmailRequired => '請輸入 APP 帳號郵箱。';

  @override
  String get appAccountPassword => 'APP 帳號密碼';

  @override
  String get appAccountPasswordRequired => '請輸入 APP 帳號密碼。';

  @override
  String get forceAppAccountLogin => '強制登入';

  @override
  String get forceAppAccountLoginHint => '僅在服務端提示設備已綁定時使用。';

  @override
  String get cancel => '取消';

  @override
  String get signInAppAccount => '登入 APP 帳號';

  @override
  String get searchUserHint => '搜尋 UID、暱稱或郵箱';

  @override
  String get selectCompanionFirst => '請先選擇陪聊帳號。';

  @override
  String get identityGuardHint => '發送前請確認誰在發言、誰在接收訊息。';

  @override
  String get selectConversationFirst => '請選擇聊天對象以開啟 1 對 1 會話。';

  @override
  String get messageInputDisabledHint => '選擇聊天對象後才可以輸入訊息。';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get appTitle => 'BB Planet 運營聊天工作台';

  @override
  String get operatorLoginSubtitle => '先使用管理後台帳號登入，再連接真實 APP 帳號進行 1 對 1 聊天運營。';

  @override
  String get operatorAccount => '操作人帳號';

  @override
  String get operatorAccountRequired => '請輸入操作人帳號。';

  @override
  String get password => '密碼';

  @override
  String get passwordRequired => '請輸入密碼。';

  @override
  String get googleCodeOptional => 'Google 驗證碼（如需要）';

  @override
  String get signIn => '登入';

  @override
  String get devEnterWorkspace => '開發模式：直接進入工作台';

  @override
  String get leftPanelTitle => '帳號';

  @override
  String get middlePanelTitle => '會話';

  @override
  String get rightPanelTitle => '聊天';

  @override
  String get operatorIdentity => '操作人身份';

  @override
  String get speakingIdentity => '發言身份';

  @override
  String get noAppAccountSelected => '尚未選擇 APP 帳號';

  @override
  String get addAppAccount => '新增 APP 帳號';

  @override
  String get switchAppAccount => '切換 APP 帳號';

  @override
  String get signingInAppAccount => '登入中...';

  @override
  String get appAccountLoginTitle => '登入 APP 帳號';

  @override
  String get appAccountLoginSubtitle => '使用真實 APP 帳號作為 IM 發言身份。';

  @override
  String get appAccountEmail => 'APP 帳號郵箱';

  @override
  String get appAccountEmailRequired => '請輸入 APP 帳號郵箱。';

  @override
  String get appAccountPassword => 'APP 帳號密碼';

  @override
  String get appAccountPasswordRequired => '請輸入 APP 帳號密碼。';

  @override
  String get forceAppAccountLogin => '強制登入';

  @override
  String get forceAppAccountLoginHint => '僅在服務端提示設備已綁定時使用。';

  @override
  String get cancel => '取消';

  @override
  String get signInAppAccount => '登入 APP 帳號';

  @override
  String get searchUserHint => '搜尋 UID、暱稱或郵箱';

  @override
  String get selectCompanionFirst => '請先選擇陪聊帳號。';

  @override
  String get identityGuardHint => '發送前請確認誰在發言、誰在接收訊息。';

  @override
  String get selectConversationFirst => '請選擇聊天對象以開啟 1 對 1 會話。';

  @override
  String get messageInputDisabledHint => '選擇聊天對象後才可以輸入訊息。';
}
