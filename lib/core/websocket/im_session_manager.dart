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

  Stream<ImClientIndexEvent> get clientIndexStream =>
      _socketClient.clientIndexStream;

  bool get isConnected => _socketClient.isConnected;

  void start({required String certificate}) {
    _socketClient.connect(certificate: certificate);
  }

  void refreshChatRooms() {
    _socketClient.refreshChatRooms();
  }

  Future<ImSendAck> sendTextMessage({
    required int senderUserId,
    required int roomId,
    required String text,
    required String clientMessageId,
  }) {
    return _socketClient.sendTextMessage(
      senderUserId: senderUserId,
      roomId: roomId,
      text: text,
      clientMessageId: clientMessageId,
    );
  }

  Future<ImSendAck> sendEmojiGameMessage({
    required int senderUserId,
    required int roomId,
    required String type,
    required int value,
    required String clientMessageId,
  }) {
    return _socketClient.sendEmojiGameMessage(
      senderUserId: senderUserId,
      roomId: roomId,
      type: type,
      value: value,
      clientMessageId: clientMessageId,
    );
  }

  Future<ImSendAck> sendMediaMessage({
    required int senderUserId,
    required int roomId,
    required List<Map<String, dynamic>> msgData,
    required String clientMessageId,
  }) {
    return _socketClient.sendMediaMessage(
      senderUserId: senderUserId,
      roomId: roomId,
      msgData: msgData,
      clientMessageId: clientMessageId,
    );
  }

  Future<ImSyncRecordAck> syncRecords({int startMsgIndex = 0, int? roomId}) {
    return _socketClient.syncRecords(
      startMsgIndex: startMsgIndex,
      roomId: roomId,
    );
  }

  Future<bool> syncClientIndex({
    required int roomId,
    int? curMsgIndex,
    int? readMsgIndex,
  }) {
    return _socketClient.syncClientIndex(
      roomId: roomId,
      curMsgIndex: curMsgIndex,
      readMsgIndex: readMsgIndex,
    );
  }

  void disconnect() {
    _socketClient.disconnect();
  }

  Future<void> stop() {
    return _socketClient.dispose();
  }
}
