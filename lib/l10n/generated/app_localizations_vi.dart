// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'BB Planet Chat Ops';

  @override
  String get operatorLoginSubtitle =>
      'Đăng nhập bằng tài khoản quản trị, sau đó kết nối tài khoản APP thật để vận hành chat 1-1.';

  @override
  String get operatorAccount => 'Tài khoản vận hành';

  @override
  String get operatorAccountRequired => 'Vui lòng nhập tài khoản vận hành.';

  @override
  String get password => 'Mật khẩu';

  @override
  String get passwordRequired => 'Vui lòng nhập mật khẩu.';

  @override
  String get googleCodeOptional => 'Mã Google (nếu cần)';

  @override
  String get signIn => 'Đăng nhập';

  @override
  String get devEnterWorkspace => 'Phát triển: vào workspace';

  @override
  String get leftPanelTitle => 'Tài khoản';

  @override
  String get middlePanelTitle => 'Hội thoại';

  @override
  String get rightPanelTitle => 'Chat';

  @override
  String get operatorIdentity => 'Danh tính vận hành';

  @override
  String get speakingIdentity => 'Danh tính đang chat';

  @override
  String get noAppAccountSelected => 'Chưa chọn tài khoản APP';

  @override
  String get addAppAccount => 'Thêm tài khoản APP';

  @override
  String get switchAppAccount => 'Đổi tài khoản APP';

  @override
  String get signingInAppAccount => 'Đang đăng nhập...';

  @override
  String get appAccountLoginTitle => 'Đăng nhập tài khoản APP';

  @override
  String get appAccountLoginSubtitle =>
      'Dùng tài khoản APP thật làm danh tính chat trong IM.';

  @override
  String get appAccountEmail => 'Email tài khoản APP';

  @override
  String get appAccountEmailRequired => 'Vui lòng nhập email tài khoản APP.';

  @override
  String get appAccountPassword => 'Mật khẩu tài khoản APP';

  @override
  String get appAccountPasswordRequired =>
      'Vui lòng nhập mật khẩu tài khoản APP.';

  @override
  String get forceAppAccountLogin => 'Đăng nhập bắt buộc';

  @override
  String get forceAppAccountLoginHint =>
      'Chỉ dùng khi máy chủ báo thiết bị đã được liên kết.';

  @override
  String get cancel => 'Hủy';

  @override
  String get signInAppAccount => 'Đăng nhập tài khoản APP';

  @override
  String get appAccountHistoryTitle => 'Danh sách tài khoản APP thật';

  @override
  String get appAccountHistorySubtitle =>
      'Chọn tài khoản APP thật dùng làm danh tính chat hiện tại.';

  @override
  String get appAccountHistoryEmpty =>
      'Thiết bị này chưa đăng nhập tài khoản APP thật nào.';

  @override
  String get appAccountStatusOnline => 'Online';

  @override
  String get appAccountStatusSwitch => 'Đổi';

  @override
  String get appAccountStatusOffline => 'Offline';

  @override
  String get searchUserHint => 'Tìm UID, biệt danh hoặc email';

  @override
  String get selectCompanionFirst => 'Vui lòng chọn tài khoản chat trước.';

  @override
  String get identityGuardHint =>
      'Xác nhận người gửi và người nhận trước khi gửi tin nhắn.';

  @override
  String get selectConversationFirst =>
      'Chọn đối tượng chat để mở hội thoại 1-1.';

  @override
  String get messageInputDisabledHint =>
      'Có thể nhập tin nhắn sau khi chọn đối tượng chat.';

  @override
  String get settings => 'Cài đặt';

  @override
  String get language => 'Ngôn ngữ';

  @override
  String get languageSystem => 'Theo hệ thống';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageTraditionalChinese => '繁體中文';

  @override
  String get languageVietnamese => 'Tiếng Việt';

  @override
  String get close => 'Đóng';

  @override
  String get navChats => 'Chat';

  @override
  String get navNew => 'Mới';

  @override
  String get navOnline => 'Online';

  @override
  String get navRichs => 'VIP';

  @override
  String get navLogin => 'Đăng nhập';

  @override
  String get navSettings => 'Cài đặt';

  @override
  String get workspaceSearchHint => 'Tìm hoặc bắt đầu chat mới';

  @override
  String get workspaceLoadingUsers => 'Đang tải người dùng...';

  @override
  String get workspaceUsersEmpty => 'Không tìm thấy người dùng phù hợp.';

  @override
  String get workspaceUsersLoginRequired =>
      'Vui lòng đăng nhập tài khoản APP trước khi tải người dùng thật.';

  @override
  String get workspaceUsersLoadFailed =>
      'Không thể tải người dùng. Vui lòng thử lại sau.';

  @override
  String get workspaceMessageInputHint => 'Nhập tin nhắn';

  @override
  String get messageReadMore => 'Xem thêm';

  @override
  String get emojiRecentTitle => 'Đã dùng gần đây';

  @override
  String get emojiSmileysTitle => 'Biểu tượng & Con người';

  @override
  String get mediaUnsupportedFile => 'Vui lòng chọn một ảnh hoặc một video.';

  @override
  String mediaVideoSizeLimit(String sizeMb) {
    return 'Dung lượng video không được vượt quá $sizeMb MB.';
  }

  @override
  String mediaSelected(String fileName) {
    return 'Đã chọn: $fileName';
  }

  @override
  String get mediaPreviewTitle => '1 phương tiện';

  @override
  String get mediaCaptionHint => 'Thêm chú thích...';

  @override
  String get mediaVideoLabel => 'Video';

  @override
  String get mediaSend => 'Gửi';

  @override
  String get mediaSending => 'Đang gửi...';

  @override
  String get mediaSendPending => 'Chưa kết nối chức năng gửi phương tiện.';

  @override
  String get workspaceUserOnline => 'Online';

  @override
  String get mockClairePreview => 'Haha trời ơi';

  @override
  String get mockJoePreview => 'Haha đáng sợ thật 😂';

  @override
  String get mockOptimusPreview => 'Tôi là Optimus prime 🤖';

  @override
  String get mockYvesPreview => 'Bro, quá đỉnh ⚡';

  @override
  String get mockNewUserPreview => 'Người dùng mới tham gia 2 phút trước';

  @override
  String get mockNeedsGreetingPreview => 'Cần lời chào đầu tiên';

  @override
  String get mockViewedProfilePreview => 'Đã xem thẻ hồ sơ';

  @override
  String get mockActiveNowPreview => 'Đang hoạt động';

  @override
  String get mockBrowsingChatPreview => 'Đang xem trang chat';

  @override
  String get mockReplyRatePreview => 'Tỷ lệ phản hồi cao';

  @override
  String get mockHighValuePreview => 'Người dùng giá trị cao';

  @override
  String get mockToppedUpPreview => 'Vừa nạp gần đây';

  @override
  String get mockFastRepliesPreview => 'Thích phản hồi nhanh';

  @override
  String get mockWelcomeMessage =>
      'Chào mừng đến với BB Planet. Rất vui được gặp bạn.';

  @override
  String get mockHelpStartMessage => 'Có ai giúp tôi bắt đầu không?';

  @override
  String get mockPremiumMessage => 'Cho tôi xem hồ sơ cao cấp.';

  @override
  String get mockPremiumReply =>
      'Tôi có thể giúp bạn tìm lựa chọn phù hợp nhất.';
}
