# BB Planet Chat Ops Desktop

独立 Flutter Desktop 子项目，用于承接运营聊天桌面工作台。

## 项目定位

- 使用管理后台账号登录工作台。
- 登录真实 APP 账号作为 IM 发言身份。
- 基于真实 WebSocket / Socket.IO 完成 `1 对 1` 私聊收发。
- 支持主动搜索用户、会话列表、本地加密缓存、翻译辅助和审计扩展。

首期不做群聊、聊天室、星球频道、多 APP 账号同时在线、自动回复机器人、语音视频和直播间。

## 技术栈

- Flutter Desktop
- Dart 3.x
- Riverpod
- go_router
- Dio
- socket_io_client
- flutter_secure_storage
- Hive CE encrypted cache
- Flutter gen-l10n

## 目录结构

```text
lib/
  app/
  core/
    config/
    network/
    security/
    storage/
    websocket/
  features/
    operator_auth/
    app_account_auth/
    conversations/
    messages/
    translation/
    audit/
    workspace/
  l10n/
  shared/
```

## 本地命令

```bash
flutter pub get
flutter gen-l10n
flutter analyze
flutter test
flutter run -d macos
```

环境变量可通过 `--dart-define` 覆盖：

```bash
flutter run -d macos \
  --dart-define=ADMIN_API_BASE_URL=https://microblueplanet.com/beep-admin \
  --dart-define=APP_API_BASE_URL=https://microblueplanet.com/beep-user \
  --dart-define=IM_SOCKET_URL=https://microblueplanet.com
```

## 关联文档

- `/Users/open/Desktop/work/bb-planet/bb-planet-command-center/doc/CHAT-OPS-DESKTOP-2026-05-10/DESKTOP-CHAT-OPS-REQUIREMENTS.md`
- `/Users/open/Desktop/work/bb-planet/bb-planet-command-center/doc/CHAT-OPS-DESKTOP-2026-05-10/DESKTOP-CHAT-OPS-ARCHITECTURE.md`
- `/Users/open/Desktop/work/bb-planet/bb-planet-command-center/doc/CHAT-OPS-DESKTOP-2026-05-10/DESKTOP-CHAT-OPS-TECH-FRAMEWORK.md`
