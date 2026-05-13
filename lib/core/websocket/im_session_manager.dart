import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'connection_status.dart';
import 'im_socket_client.dart';

final imSessionManagerProvider = Provider<ImSessionManager>((ref) {
  final manager = ImSessionManager(
    socketClient: ImSocketClient(socketUrl: appConfig.imSocketUrl),
  );
  ref.onDispose(() => unawaited(manager.stop()));
  return manager;
});

class ImSessionManager {
  ImSessionManager({required ImSocketClient socketClient})
    : _socketClient = socketClient;

  final ImSocketClient _socketClient;

  Stream<ConnectionStatus> get statusStream => _socketClient.statusStream;

  Stream<Map<String, dynamic>> get messageStream => _socketClient.messageStream;

  bool get isConnected => _socketClient.isConnected;

  void start({required String certificate}) {
    _socketClient.connect(certificate: certificate);
  }

  void refreshChatRooms() {
    _socketClient.refreshChatRooms();
  }

  Future<ImSendAck> sendTextMessage({
    required int roomId,
    required String text,
    required String clientMessageId,
  }) {
    return _socketClient.sendTextMessage(
      roomId: roomId,
      text: text,
      clientMessageId: clientMessageId,
    );
  }

  Future<ImSyncRecordAck> syncRecords({int startMsgIndex = 0, int? roomId}) {
    return _socketClient.syncRecords(
      startMsgIndex: startMsgIndex,
      roomId: roomId,
    );
  }

  void disconnect() {
    _socketClient.disconnect();
  }

  Future<void> stop() {
    return _socketClient.dispose();
  }
}
