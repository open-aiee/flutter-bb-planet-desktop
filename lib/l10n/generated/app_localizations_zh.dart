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

  @override
  String get settings => '設定';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageVietnamese => 'Tiếng Việt';

  @override
  String get close => '關閉';

  @override
  String get navChats => '聊天';

  @override
  String get navNew => '新增';

  @override
  String get navOnline => '在線';

  @override
  String get navRichs => '高價值';

  @override
  String get navLogin => '登入';

  @override
  String get navSettings => '設定';

  @override
  String get workspaceSearchHint => '搜尋或開始新聊天';

  @override
  String get workspaceLoadingUsers => '正在載入用戶...';

  @override
  String get workspaceUsersEmpty => '目前沒有符合條件的用戶。';

  @override
  String get workspaceUsersLoginRequired => '請先登入 APP 帳號，再載入真實用戶。';

  @override
  String get workspaceUsersLoadFailed => '用戶載入失敗，請稍後再試。';

  @override
  String get workspaceMessageInputHint => '輸入訊息';

  @override
  String get messageReadMore => '閱讀更多';

  @override
  String get workspaceUserOnline => '在線';

  @override
  String get mockClairePreview => '哈哈，天啊';

  @override
  String get mockJoePreview => '哈哈，這有點嚇人 😂';

  @override
  String get mockOptimusPreview => '我是 Optimus prime 🤖';

  @override
  String get mockYvesPreview => '兄弟，這太酷了 ⚡';

  @override
  String get mockNewUserPreview => '新用戶 2 分鐘前加入';

  @override
  String get mockNeedsGreetingPreview => '需要首次問候';

  @override
  String get mockViewedProfilePreview => '已查看個人資料卡';

  @override
  String get mockActiveNowPreview => '目前活躍';

  @override
  String get mockBrowsingChatPreview => '正在瀏覽聊天頁';

  @override
  String get mockReplyRatePreview => '回覆率高';

  @override
  String get mockHighValuePreview => '高價值用戶';

  @override
  String get mockToppedUpPreview => '最近已充值';

  @override
  String get mockFastRepliesPreview => '偏好快速回覆';

  @override
  String get mockWelcomeMessage => '歡迎來到 BB Planet，很高興認識你。';

  @override
  String get mockHelpStartMessage => '有人可以幫我開始嗎？';

  @override
  String get mockPremiumMessage => '給我看看高級資料。';

  @override
  String get mockPremiumReply => '我可以幫你找到最合適的匹配。';
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

  @override
  String get settings => '設定';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageVietnamese => 'Tiếng Việt';

  @override
  String get close => '關閉';

  @override
  String get navChats => '聊天';

  @override
  String get navNew => '新增';

  @override
  String get navOnline => '在線';

  @override
  String get navRichs => '高價值';

  @override
  String get navLogin => '登入';

  @override
  String get navSettings => '設定';

  @override
  String get workspaceSearchHint => '搜尋或開始新聊天';

  @override
  String get workspaceLoadingUsers => '正在載入用戶...';

  @override
  String get workspaceUsersEmpty => '目前沒有符合條件的用戶。';

  @override
  String get workspaceUsersLoginRequired => '請先登入 APP 帳號，再載入真實用戶。';

  @override
  String get workspaceUsersLoadFailed => '用戶載入失敗，請稍後再試。';

  @override
  String get workspaceMessageInputHint => '輸入訊息';

  @override
  String get messageReadMore => '閱讀更多';

  @override
  String get workspaceUserOnline => '在線';

  @override
  String get mockClairePreview => '哈哈，天啊';

  @override
  String get mockJoePreview => '哈哈，這有點嚇人 😂';

  @override
  String get mockOptimusPreview => '我是 Optimus prime 🤖';

  @override
  String get mockYvesPreview => '兄弟，這太酷了 ⚡';

  @override
  String get mockNewUserPreview => '新用戶 2 分鐘前加入';

  @override
  String get mockNeedsGreetingPreview => '需要首次問候';

  @override
  String get mockViewedProfilePreview => '已查看個人資料卡';

  @override
  String get mockActiveNowPreview => '目前活躍';

  @override
  String get mockBrowsingChatPreview => '正在瀏覽聊天頁';

  @override
  String get mockReplyRatePreview => '回覆率高';

  @override
  String get mockHighValuePreview => '高價值用戶';

  @override
  String get mockToppedUpPreview => '最近已充值';

  @override
  String get mockFastRepliesPreview => '偏好快速回覆';

  @override
  String get mockWelcomeMessage => '歡迎來到 BB Planet，很高興認識你。';

  @override
  String get mockHelpStartMessage => '有人可以幫我開始嗎？';

  @override
  String get mockPremiumMessage => '給我看看高級資料。';

  @override
  String get mockPremiumReply => '我可以幫你找到最合適的匹配。';
}
