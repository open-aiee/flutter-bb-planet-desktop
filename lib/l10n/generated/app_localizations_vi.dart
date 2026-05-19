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
  String get voiceRecordTitle => 'Tin nhắn thoại';

  @override
  String get voiceRecordHint => 'Bấm bắt đầu, nói, rồi gửi. Tối đa 60 giây.';

  @override
  String get voiceRecordingHint => 'Đang ghi âm... bấm dừng khi hoàn tất.';

  @override
  String get voiceRecordReady =>
      'Tin nhắn thoại đã sẵn sàng. Gửi hoặc ghi lại.';

  @override
  String get voiceRecordAgain => 'Ghi lại';

  @override
  String get voiceStart => 'Bắt đầu';

  @override
  String get voiceStop => 'Dừng';

  @override
  String get voicePermissionDenied => 'Cần quyền micro để ghi âm.';

  @override
  String get voiceTooShort => 'Tin nhắn thoại quá ngắn.';

  @override
  String get voiceRecordFailed => 'Ghi âm thất bại. Vui lòng thử lại.';

  @override
  String get voiceCancelRecording => 'Hủy ghi âm';

  @override
  String get voiceInputTooltip => 'Giọng nói';

  @override
  String get attachmentTooltip => 'Đính kèm';

  @override
  String get chatInputWriteMessageHint => 'Viết tin nhắn...';

  @override
  String get chatOpenFailed => 'Không thể mở cuộc trò chuyện.';

  @override
  String get chatPrivateAccountBlocked =>
      'Đối phương đã bật tài khoản riêng tư.';

  @override
  String get chatYouBlockedPeer => 'Bạn đã chặn đối phương.';

  @override
  String get chatYouWereBlocked => 'Bạn đã bị chặn.';

  @override
  String get chatPeerClosedPrivateChat => 'Đối phương đã đóng chat riêng.';

  @override
  String get dateToday => 'HÔM NAY';

  @override
  String get dateYesterday => 'HÔM QUA';

  @override
  String get contactInfoBack => 'Quay lại';

  @override
  String get contactInfoTitle => 'Thông tin';

  @override
  String get contactInfoMessage => 'Tin nhắn';

  @override
  String get contactInfoCall => 'Gọi';

  @override
  String get contactInfoMore => 'Thêm';

  @override
  String get contactInfoUsername => 'tên người dùng';

  @override
  String get contactInfoLastSeenRecently => 'hoạt động gần đây';

  @override
  String get contactInfoAddContact => 'Thêm liên hệ';

  @override
  String get contactInfoBlockUser => 'Chặn người dùng';

  @override
  String get contactInfoMedia => 'Media';

  @override
  String get contactInfoNoMedia => 'Chưa có media';

  @override
  String get loginQrTitle => 'Để dùng Desktop trên máy tính:';

  @override
  String get loginQrStepOpenApp => 'Mở App trên điện thoại';

  @override
  String get loginQrStepFindQr => 'Tìm góc trên bên phải của trang cá nhân';

  @override
  String get loginQrStepTapQr => 'Bấm vào QR';

  @override
  String get loginQrStepScanCode =>
      'Hướng điện thoại vào màn hình này để quét mã';

  @override
  String get loginQrScanToSignIn => 'Quét để đăng nhập';

  @override
  String get appAccountListPanelTitle => 'Sửa & đổi tài khoản';

  @override
  String get appAccountListAddOrSwitch => 'Đổi & thêm';

  @override
  String get appAccountListEmpty =>
      'Thiết bị này chưa đăng nhập tài khoản APP thật nào.';

  @override
  String get appAccountListLoadFailed =>
      'Không thể tải tài khoản APP. Vui lòng thử lại sau.';

  @override
  String get appAccountListSelectAccount =>
      'Chọn một tài khoản APP thật để xem chi tiết.';

  @override
  String get appAccountInfoAccount => 'Tài khoản';

  @override
  String get appAccountInfoNickname => 'Biệt danh';

  @override
  String get appAccountInfoBasicProfile => 'Hồ sơ cơ bản';

  @override
  String get appAccountInfoEditProfile => 'Sửa hồ sơ';

  @override
  String get appAccountInfoProfile => 'Hồ sơ';

  @override
  String get appAccountInfoHonor => 'Danh dự';

  @override
  String get appAccountInfoActivity => 'Hoạt động';

  @override
  String get appAccountInfoRelationship => 'Quan hệ';

  @override
  String get appAccountInfoAlbum => 'Album';

  @override
  String get appAccountInfoFamily => 'Gia đình';

  @override
  String get appAccountInfoGoldCoin => 'Nhận xu vàng';

  @override
  String get appAccountInfoPrivateAlbum => 'Album riêng tư';

  @override
  String get appAccountInfoPhotoWall => 'Tường ảnh';

  @override
  String get appAccountInfoId => 'ID';

  @override
  String get appAccountInfoBirthday => 'Sinh nhật';

  @override
  String get appAccountInfoZodiac => 'Cung hoàng đạo';

  @override
  String get appAccountInfoRegisterTime => 'Thời gian đăng ký';

  @override
  String get appAccountInfoSignature => 'Chữ ký';

  @override
  String get appAccountInfoSignaturePlaceholder => 'Nói điều gì đó...';

  @override
  String get appAccountInfoVoiceIntro => 'Giới thiệu bằng giọng nói';

  @override
  String get appAccountInfoHeight => 'Chiều cao';

  @override
  String get appAccountInfoWeight => 'Cân nặng';

  @override
  String get appAccountInfoIndustry => 'Ngành nghề';

  @override
  String get appAccountInfoOccupation => 'Nghề nghiệp';

  @override
  String get appAccountInfoBirthplace => 'Nơi sinh';

  @override
  String get appAccountInfoResidence => 'Nơi ở';

  @override
  String get appAccountAvatarChange => 'Đổi ảnh đại diện';

  @override
  String get appAccountAvatarPickerTitle => 'Chọn ảnh đại diện';

  @override
  String get appAccountAvatarUploadSuccess => 'Đã cập nhật ảnh đại diện.';

  @override
  String get appAccountAvatarUploadFailed =>
      'Không thể cập nhật ảnh đại diện. Vui lòng thử lại.';

  @override
  String get appAccountInfoEmptyTab => 'Chưa có nội dung';

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
