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

## 本地消息缓存约定

- 本地消息使用 Hive CE 加密缓存，路径固定在系统应用支持目录，避免应用卸载或重新构建时误删。
- 本地 `1 对 1` 会话 key 固定为：`sender:{发消息APP用户ID}:direct-peer:{对方用户ID}`。
- `sender` 表示这段会话归属的真实 APP 发言账号；`direct-peer` 表示该发言账号正在单聊的对方用户。
- `roomId` 仅作为服务端发消息、同步历史消息接口的辅助字段，不参与本地缓存 key，不用于区分单聊、群聊或聊天室。
- 后续支持多 APP 账号时，`sender:{发消息APP用户ID}` 天然隔离不同发言账号的本地消息。

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
  --dart-define=ALLOW_AUTH_BYPASS=true \
  --dart-define=APP_API_BASE_URL=https://microblueplanet.com/beep-user/ \
  --dart-define=IM_SOCKET_URL=https://microblueplanet.com/common
```

也可以使用 `APP_ENV` 切换默认环境：

```bash
# 本地环境，默认值
flutter run -d macos --dart-define=APP_ENV=local

# 测试环境
flutter run -d macos --dart-define=APP_ENV=test --dart-define=ALLOW_AUTH_BYPASS=true

# 生产环境
flutter run -d macos --dart-define=APP_ENV=prod
```

当前内置默认值：

| APP_ENV | ADMIN_API_BASE_URL | APP_API_BASE_URL | IM_SOCKET_URL |
| --- | --- | --- | --- |
| local | `http://192.168.0.101:31111` | `http://192.168.0.101:31110` | `http://192.168.0.101:5464/common` |
| test | `https://microblueplanet.com/beep-admin` | `https://microblueplanet.com/beep-user` | `https://microblueplanet.com/common` |
| prod | `https://beepbeepplanet.com/beep-admin` | `https://beepbeepplanet.com/beep-user` | `https://beepbeepplanet.com/common` |

本地环境默认允许跳过后台登录进入工作台，便于先开发主页和 user 端能力。其他环境默认不允许。也可以显式覆盖：

```bash
flutter run -d macos --dart-define=ALLOW_AUTH_BYPASS=true
```

如果只启动了本地 `beep-admin`，但 APP 账号登录希望走测试服 `beep-user`，可以混合覆盖：

```bash
flutter run -d macos \
  --dart-define=ADMIN_API_BASE_URL=http://192.168.0.101:31111 \
  --dart-define=APP_API_BASE_URL=https://microblueplanet.com/beep-user/ \
  --dart-define=IM_SOCKET_URL=https://microblueplanet.com/common
```

## 关联文档

- `/Users/open/Desktop/work/bb-planet/bb-planet-command-center/doc/CHAT-OPS-DESKTOP-2026-05-10/DESKTOP-CHAT-OPS-REQUIREMENTS.md`
- `/Users/open/Desktop/work/bb-planet/bb-planet-command-center/doc/CHAT-OPS-DESKTOP-2026-05-10/DESKTOP-CHAT-OPS-ARCHITECTURE.md`
- `/Users/open/Desktop/work/bb-planet/bb-planet-command-center/doc/CHAT-OPS-DESKTOP-2026-05-10/DESKTOP-CHAT-OPS-TECH-FRAMEWORK.md`
