import 'dart:async';

import 'connection_status.dart';
import 'im_socket_client.dart';

class ImSessionManager {
  ImSessionManager({required ImSocketClient socketClient})
    : _socketClient = socketClient;

  final ImSocketClient _socketClient;

  Stream<ConnectionStatus> get statusStream => _socketClient.statusStream;

  Stream<Map<String, dynamic>> get messageStream => _socketClient.messageStream;

  void start({required Map<String, dynamic> authPayload}) {
    _socketClient.connect(authPayload: authPayload);
  }

  void sendPrivateMessage({
    required String conversationId,
    required String targetUserId,
    required String content,
  }) {
    _socketClient.emit('private_message', {
      'conversationId': conversationId,
      'targetUserId': targetUserId,
      'content': content,
    });
  }

  Future<void> stop() {
    return _socketClient.dispose();
  }
}
