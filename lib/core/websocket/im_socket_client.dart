import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'connection_status.dart';

class ImSocketClient {
  ImSocketClient({required this.socketUrl});

  final String socketUrl;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  io.Socket? _socket;

  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  void connect({required Map<String, dynamic> authPayload}) {
    _statusController.add(ConnectionStatus.connecting);
    _socket = io.io(
      socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth(authPayload)
          .enableReconnection()
          .build(),
    );

    _socket!
      ..onConnect((_) => _statusController.add(ConnectionStatus.connected))
      ..onDisconnect(
        (_) => _statusController.add(ConnectionStatus.disconnected),
      )
      ..onReconnect((_) => _statusController.add(ConnectionStatus.reconnecting))
      ..onConnectError((_) => _statusController.add(ConnectionStatus.failed))
      ..on('message', (data) {
        if (data is Map) {
          _messageController.add(Map<String, dynamic>.from(data));
        }
      })
      ..connect();
  }

  void emit(String event, Map<String, dynamic> payload) {
    _socket?.emit(event, payload);
  }

  void disconnect() {
    _socket?.disconnect();
    _statusController.add(ConnectionStatus.disconnected);
  }

  Future<void> dispose() async {
    disconnect();
    await _statusController.close();
    await _messageController.close();
  }
}
