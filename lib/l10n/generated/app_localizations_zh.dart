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
  String get appAccountHistoryTitle => '運營真實 APP 帳號列表';

  @override
  String get appAccountHistorySubtitle => '選擇當前用於聊天發言的真實 APP 帳號。';

  @override
  String get appAccountHistoryEmpty => '這台設備還沒有登入過真實 APP 帳號。';

  @override
  String get appAccountStatusOnline => '在線';

  @override
  String get appAccountStatusSwitch => '切換';

  @override
  String get appAccountStatusOffline => '離線';

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
  String get emojiRecentTitle => '最近使用';

  @override
  String get emojiSmileysTitle => '表情符號與人物';

  @override
  String get mediaUnsupportedFile => '請選擇一張圖片或一個影片。';

  @override
  String mediaVideoSizeLimit(String sizeMb) {
    return '影片大小不能超過 $sizeMb MB。';
  }

  @override
  String mediaSelected(String fileName) {
    return '已選擇：$fileName';
  }

  @override
  String get mediaPreviewTitle => '1 個媒體';

  @override
  String get mediaCaptionHint => '添加說明...';

  @override
  String get mediaVideoLabel => '影片';

  @override
  String get mediaSend => '發送';

  @override
  String get mediaSending => '發送中...';

  @override
  String get mediaSendPending => '媒體發送暫未接入。';

  @override
  String get voiceRecordTitle => '語音訊息';

  @override
  String get voiceRecordHint => '點擊開始後說話，再發送。最多 60 秒。';

  @override
  String get voiceRecordingHint => '錄音中...完成後點擊停止。';

  @override
  String get voiceRecordReady => '語音已準備好，可以發送或重新錄製。';

  @override
  String get voiceRecordAgain => '重新錄製';

  @override
  String get voiceStart => '開始';

  @override
  String get voiceStop => '停止';

  @override
  String get voicePermissionDenied => '需要麥克風權限才能錄製語音。';

  @override
  String get voiceTooShort => '語音訊息太短。';

  @override
  String get voiceRecordFailed => '語音錄製失敗，請重試。';

  @override
  String get voiceCancelRecording => '取消錄音';

  @override
  String get voiceInputTooltip => '語音';

  @override
  String get attachmentTooltip => '附件';

  @override
  String get chatInputWriteMessageHint => '輸入訊息...';

  @override
  String get chatOpenFailed => '無法開啟聊天。';

  @override
  String get chatPrivateAccountBlocked => '對方開啟了私密帳戶。';

  @override
  String get chatYouBlockedPeer => '你已拉黑對方。';

  @override
  String get chatYouWereBlocked => '你已被拉黑。';

  @override
  String get chatPeerClosedPrivateChat => '對方關閉了私聊。';

  @override
  String get dateToday => '今天';

  @override
  String get dateYesterday => '昨天';

  @override
  String get contactInfoBack => '返回';

  @override
  String get contactInfoTitle => '資料';

  @override
  String get contactInfoMessage => '訊息';

  @override
  String get contactInfoCall => '通話';

  @override
  String get contactInfoMore => '更多';

  @override
  String get contactInfoUsername => '用戶名';

  @override
  String get contactInfoLastSeenRecently => '最近上線';

  @override
  String get contactInfoAddContact => '新增聯絡人';

  @override
  String get contactInfoBlockUser => '封鎖用戶';

  @override
  String get contactInfoMedia => '媒體';

  @override
  String get contactInfoNoMedia => '暫無媒體';

  @override
  String get loginQrTitle => '若要在電腦上使用 Desktop：';

  @override
  String get loginQrStepOpenApp => '在手機上開啟 App';

  @override
  String get loginQrStepFindQr => '找到我的頁面右上角';

  @override
  String get loginQrStepTapQr => '點擊 QR';

  @override
  String get loginQrStepScanCode => '將手機對準此畫面以掃描代碼';

  @override
  String get loginQrScanToSignIn => '掃描登入';

  @override
  String get appAccountListPanelTitle => '編輯&切換帳號';

  @override
  String get appAccountListAddOrSwitch => '切換&新增';

  @override
  String get appAccountListEmpty => '這台設備還沒有登入過真實 APP 帳號。';

  @override
  String get appAccountListLoadFailed => 'APP 帳號載入失敗，請稍後再試。';

  @override
  String get appAccountListSelectAccount => '請選擇一個真實 APP 帳號查看資料。';

  @override
  String get appAccountInfoAccount => '帳號';

  @override
  String get appAccountInfoNickname => '暱稱';

  @override
  String get appAccountInfoBasicProfile => '基本檔案';

  @override
  String get appAccountInfoEditProfile => '編輯檔案';

  @override
  String get appAccountInfoProfile => '個人檔案';

  @override
  String get appAccountInfoHonor => '榮譽';

  @override
  String get appAccountInfoActivity => '動態';

  @override
  String get appAccountInfoRelationship => '關係';

  @override
  String get appAccountInfoAlbum => '相冊';

  @override
  String get appAccountInfoFamily => '家族';

  @override
  String get appAccountInfoGoldCoin => '獲得金幣';

  @override
  String get appAccountInfoPrivateAlbum => '隱私相冊';

  @override
  String get appAccountInfoPhotoWall => '照片牆';

  @override
  String get appAccountInfoId => 'ID';

  @override
  String get appAccountInfoBirthday => '生日';

  @override
  String get appAccountInfoZodiac => '星座';

  @override
  String get appAccountInfoRegisterTime => '註冊時間';

  @override
  String get appAccountInfoSignature => '個性簽名';

  @override
  String get appAccountInfoSignaturePlaceholder => '說點什麼...';

  @override
  String get appAccountInfoVoiceIntro => '語音介紹';

  @override
  String get appAccountInfoHeight => '身高';

  @override
  String get appAccountInfoWeight => '體重';

  @override
  String get appAccountInfoIndustry => '行業';

  @override
  String get appAccountInfoOccupation => '職業';

  @override
  String get appAccountInfoBirthplace => '出生地';

  @override
  String get appAccountInfoResidence => '居住地';

  @override
  String get appAccountAvatarChange => '更換頭像';

  @override
  String get appAccountAvatarPickerTitle => '選擇頭像圖片';

  @override
  String get appAccountAvatarUploadSuccess => '頭像已更新。';

  @override
  String get appAccountAvatarUploadFailed => '頭像更新失敗，請稍後再試。';

  @override
  String get appAccountInfoEmptyTab => '暫無內容';

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
  String get appAccountHistoryTitle => '運營真實 APP 帳號列表';

  @override
  String get appAccountHistorySubtitle => '選擇當前用於聊天發言的真實 APP 帳號。';

  @override
  String get appAccountHistoryEmpty => '這台設備還沒有登入過真實 APP 帳號。';

  @override
  String get appAccountStatusOnline => '在線';

  @override
  String get appAccountStatusSwitch => '切換';

  @override
  String get appAccountStatusOffline => '離線';

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
  String get emojiRecentTitle => '最近使用';

  @override
  String get emojiSmileysTitle => '表情符號與人物';

  @override
  String get mediaUnsupportedFile => '請選擇一張圖片或一個影片。';

  @override
  String mediaVideoSizeLimit(String sizeMb) {
    return '影片大小不能超過 $sizeMb MB。';
  }

  @override
  String mediaSelected(String fileName) {
    return '已選擇：$fileName';
  }

  @override
  String get mediaPreviewTitle => '1 個媒體';

  @override
  String get mediaCaptionHint => '添加說明...';

  @override
  String get mediaVideoLabel => '影片';

  @override
  String get mediaSend => '發送';

  @override
  String get mediaSending => '發送中...';

  @override
  String get mediaSendPending => '媒體發送暫未接入。';

  @override
  String get voiceRecordTitle => '語音訊息';

  @override
  String get voiceRecordHint => '點擊開始後說話，再發送。最多 60 秒。';

  @override
  String get voiceRecordingHint => '錄音中...完成後點擊停止。';

  @override
  String get voiceRecordReady => '語音已準備好，可以發送或重新錄製。';

  @override
  String get voiceRecordAgain => '重新錄製';

  @override
  String get voiceStart => '開始';

  @override
  String get voiceStop => '停止';

  @override
  String get voicePermissionDenied => '需要麥克風權限才能錄製語音。';

  @override
  String get voiceTooShort => '語音訊息太短。';

  @override
  String get voiceRecordFailed => '語音錄製失敗，請重試。';

  @override
  String get voiceCancelRecording => '取消錄音';

  @override
  String get voiceInputTooltip => '語音';

  @override
  String get attachmentTooltip => '附件';

  @override
  String get chatInputWriteMessageHint => '輸入訊息...';

  @override
  String get chatOpenFailed => '無法開啟聊天。';

  @override
  String get chatPrivateAccountBlocked => '對方開啟了私密帳戶。';

  @override
  String get chatYouBlockedPeer => '你已拉黑對方。';

  @override
  String get chatYouWereBlocked => '你已被拉黑。';

  @override
  String get chatPeerClosedPrivateChat => '對方關閉了私聊。';

  @override
  String get dateToday => '今天';

  @override
  String get dateYesterday => '昨天';

  @override
  String get contactInfoBack => '返回';

  @override
  String get contactInfoTitle => '資料';

  @override
  String get contactInfoMessage => '訊息';

  @override
  String get contactInfoCall => '通話';

  @override
  String get contactInfoMore => '更多';

  @override
  String get contactInfoUsername => '用戶名';

  @override
  String get contactInfoLastSeenRecently => '最近上線';

  @override
  String get contactInfoAddContact => '新增聯絡人';

  @override
  String get contactInfoBlockUser => '封鎖用戶';

  @override
  String get contactInfoMedia => '媒體';

  @override
  String get contactInfoNoMedia => '暫無媒體';

  @override
  String get loginQrTitle => '若要在電腦上使用 Desktop：';

  @override
  String get loginQrStepOpenApp => '在手機上開啟 App';

  @override
  String get loginQrStepFindQr => '找到我的頁面右上角';

  @override
  String get loginQrStepTapQr => '點擊 QR';

  @override
  String get loginQrStepScanCode => '將手機對準此畫面以掃描代碼';

  @override
  String get loginQrScanToSignIn => '掃描登入';

  @override
  String get appAccountListPanelTitle => '編輯&切換帳號';

  @override
  String get appAccountListAddOrSwitch => '切換&新增';

  @override
  String get appAccountListEmpty => '這台設備還沒有登入過真實 APP 帳號。';

  @override
  String get appAccountListLoadFailed => 'APP 帳號載入失敗，請稍後再試。';

  @override
  String get appAccountListSelectAccount => '請選擇一個真實 APP 帳號查看資料。';

  @override
  String get appAccountInfoAccount => '帳號';

  @override
  String get appAccountInfoNickname => '暱稱';

  @override
  String get appAccountInfoBasicProfile => '基本檔案';

  @override
  String get appAccountInfoEditProfile => '編輯檔案';

  @override
  String get appAccountInfoProfile => '個人檔案';

  @override
  String get appAccountInfoHonor => '榮譽';

  @override
  String get appAccountInfoActivity => '動態';

  @override
  String get appAccountInfoRelationship => '關係';

  @override
  String get appAccountInfoAlbum => '相冊';

  @override
  String get appAccountInfoFamily => '家族';

  @override
  String get appAccountInfoGoldCoin => '獲得金幣';

  @override
  String get appAccountInfoPrivateAlbum => '隱私相冊';

  @override
  String get appAccountInfoPhotoWall => '照片牆';

  @override
  String get appAccountInfoId => 'ID';

  @override
  String get appAccountInfoBirthday => '生日';

  @override
  String get appAccountInfoZodiac => '星座';

  @override
  String get appAccountInfoRegisterTime => '註冊時間';

  @override
  String get appAccountInfoSignature => '個性簽名';

  @override
  String get appAccountInfoSignaturePlaceholder => '說點什麼...';

  @override
  String get appAccountInfoVoiceIntro => '語音介紹';

  @override
  String get appAccountInfoHeight => '身高';

  @override
  String get appAccountInfoWeight => '體重';

  @override
  String get appAccountInfoIndustry => '行業';

  @override
  String get appAccountInfoOccupation => '職業';

  @override
  String get appAccountInfoBirthplace => '出生地';

  @override
  String get appAccountInfoResidence => '居住地';

  @override
  String get appAccountAvatarChange => '更換頭像';

  @override
  String get appAccountAvatarPickerTitle => '選擇頭像圖片';

  @override
  String get appAccountAvatarUploadSuccess => '頭像已更新。';

  @override
  String get appAccountAvatarUploadFailed => '頭像更新失敗，請稍後再試。';

  @override
  String get appAccountInfoEmptyTab => '暫無內容';

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
