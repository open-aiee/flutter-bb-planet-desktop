import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client_flutter/v3/socket_io_client_flutter.dart'
    as io;

import 'connection_status.dart';

class ImSocketClient {
  ImSocketClient({required this.socketUrl});

  static const _sendChatEvent = 'sendChat';
  static const _syncRecordEvent = 'syncRecord';
  static const _joinCommonRoomEvent = 'joinCommonRoom';
  static const _chatPushEvent = 'CHAT';

  final String socketUrl;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  io.Socket? _socket;
  bool _connected = false;
  String _certificate = '';
  Timer? _reconnectTimer;

  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  bool get isConnected => _connected;

  void connect({required String certificate}) {
    final nextCertificate = certificate.trim();
    if (nextCertificate.isEmpty) {
      disconnect();
      return;
    }

    if (_socket != null && _certificate == nextCertificate) {
      if (!_connected) {
        _socket!.connect();
      }
      return;
    }

    disconnect();
    _certificate = nextCertificate;
    _statusController.add(ConnectionStatus.connecting);

    final options = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()
        .enableReconnection()
        .setReconnectionAttempts(999999)
        .setReconnectionDelay(1000)
        .setReconnectionDelayMax(10000)
        .setQuery({'certificate': _certificate})
        .setExtraHeaders({'Certificate': _certificate})
        .enableForceNewConnection()
        .build();

    final socket = io.io(socketUrl, options);
    _socket = socket;

    socket
      ..onConnect((_) {
        _connected = true;
        _reconnectTimer?.cancel();
        _statusController.add(ConnectionStatus.connected);
        debugPrint('[CHAT_OPS][SOCKET] connected url=$socketUrl');
        joinCommonRoom();
      })
      ..onDisconnect((_) {
        _connected = false;
        _statusController.add(ConnectionStatus.disconnected);
        debugPrint('[CHAT_OPS][SOCKET] disconnected');
        _scheduleReconnect();
      })
      ..onReconnect((_) {
        _statusController.add(ConnectionStatus.reconnecting);
      })
      ..onConnectError((error) {
        _connected = false;
        _statusController.add(ConnectionStatus.failed);
        debugPrint('[CHAT_OPS][SOCKET][CONNECT_ERROR] $error');
        _scheduleReconnect();
      })
      ..onError((error) {
        _connected = false;
        _statusController.add(ConnectionStatus.failed);
        debugPrint('[CHAT_OPS][SOCKET][ERROR] $error');
        _scheduleReconnect();
      })
      ..on(_chatPushEvent, (payload) {
        debugPrint('[CHAT_OPS][SOCKET][INBOUND_RAW] $payload');
        final data = _extractEventData(payload);
        if (data is Map<String, dynamic>) {
          debugPrint('[CHAT_OPS][SOCKET][INBOUND_DATA] $data');
          _messageController.add(data);
        } else if (data is Map) {
          final mapped = _asMap(data);
          debugPrint('[CHAT_OPS][SOCKET][INBOUND_DATA] $mapped');
          _messageController.add(mapped);
        }
      })
      ..connect();
  }

  void refreshChatRooms() {
    final certificate = _certificate;
    if (certificate.trim().isEmpty) {
      return;
    }
    debugPrint('[CHAT_OPS][SOCKET] refresh chat rooms');
    disconnect();
    connect(certificate: certificate);
  }

  void joinCommonRoom() {
    if (!_connected) {
      return;
    }
    _socket?.emitWithAck(
      _joinCommonRoomEvent,
      ['CHAT'],
      ack: (payload) {
        debugPrint('[CHAT_OPS][SOCKET][JOIN_COMMON_ROOM_ACK] $payload');
      },
    );
  }

  Future<ImSendAck> sendTextMessage({
    required int roomId,
    required String text,
    required String clientMessageId,
  }) async {
    if (!_connected && _socket != null) {
      await _waitUntilConnected();
    }
    if (!_connected || _socket == null) {
      return const ImSendAck(success: false, message: 'Socket disconnected');
    }
    final payload = <String, dynamic>{
      'roomId': roomId,
      'msg': text,
      'sendType': 1,
      'msgId': 100,
      'cid': clientMessageId,
    };
    final completer = Completer<ImSendAck>();
    _socket!.emitWithAck(
      _sendChatEvent,
      [payload],
      ack: (payload) {
        debugPrint('[CHAT_OPS][SOCKET][SEND_CHAT_ACK] $payload');
        if (!completer.isCompleted) {
          completer.complete(ImSendAck.fromPayload(payload));
        }
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => const ImSendAck(success: false, message: 'Send timeout'),
    );
  }

  Future<ImSyncRecordAck> syncRecords({
    int startMsgIndex = 0,
    int? roomId,
  }) async {
    if (!_connected && _socket != null) {
      await _waitUntilConnected();
    }
    if (!_connected || _socket == null) {
      return const ImSyncRecordAck(success: false);
    }
    final payload = <String, dynamic>{
      'startMsgIndex': startMsgIndex,
      if (roomId != null && roomId > 0) 'roomId': roomId,
    };
    final completer = Completer<ImSyncRecordAck>();
    _socket!.emitWithAck(
      _syncRecordEvent,
      [payload],
      ack: (payload) {
        debugPrint('[CHAT_OPS][SOCKET][SYNC_RECORD_ACK] $payload');
        if (!completer.isCompleted) {
          completer.complete(ImSyncRecordAck.fromPayload(payload));
        }
      },
    );
    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => const ImSyncRecordAck(success: false),
    );
  }

  Future<void> _waitUntilConnected() async {
    if (_connected) {
      return;
    }
    final completer = Completer<void>();
    late final StreamSubscription<ConnectionStatus> subscription;
    subscription = statusStream.listen((status) {
      if (status == ConnectionStatus.connected && !completer.isCompleted) {
        completer.complete();
      }
      if (status == ConnectionStatus.failed && !completer.isCompleted) {
        completer.complete();
      }
    });
    await completer.future.timeout(
      const Duration(seconds: 6),
      onTimeout: () {},
    );
    await subscription.cancel();
  }

  void _scheduleReconnect() {
    if (_certificate.isEmpty || _connected) {
      return;
    }
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_certificate.isEmpty || _connected || _socket == null) {
        return;
      }
      _statusController.add(ConnectionStatus.reconnecting);
      _socket!.io.options['query'] = {'certificate': _certificate};
      _socket!.io.options['extraHeaders'] = {'Certificate': _certificate};
      _socket!.connect();
    });
  }

  dynamic _extractEventData(dynamic payload) {
    dynamic source = payload;
    if (source is List && source.isNotEmpty) {
      source = source.first;
    }
    if (source is String) {
      try {
        source = jsonDecode(source);
      } catch (_) {
        return source;
      }
    }
    if (source is Map) {
      final data = source['data'];
      if (data != null) {
        return _normalize(data);
      }
      return _normalize(source);
    }
    return source;
  }

  dynamic _normalize(dynamic value) {
    if (value is List) {
      return value.map(_normalize).toList(growable: false);
    }
    if (value is Map) {
      return _asMap(value);
    }
    if (value is String) {
      final text = value.trim();
      if ((text.startsWith('{') && text.endsWith('}')) ||
          (text.startsWith('[') && text.endsWith(']'))) {
        try {
          return _normalize(jsonDecode(text));
        } catch (_) {
          return value;
        }
      }
    }
    return value;
  }

  Map<String, dynamic> _asMap(Map value) {
    return value.map((key, val) => MapEntry(key.toString(), _normalize(val)));
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _connected = false;
    _statusController.add(ConnectionStatus.disconnected);
  }

  Future<void> dispose() async {
    disconnect();
    await _statusController.close();
    await _messageController.close();
  }
}

class ImSyncRecordAck {
  const ImSyncRecordAck({required this.success, this.records = const []});

  final bool success;
  final List<Map<String, dynamic>> records;

  factory ImSyncRecordAck.fromPayload(dynamic payload) {
    final source = ImSendAck._unwrap(payload);
    if (source is! Map) {
      return const ImSyncRecordAck(success: false);
    }
    final map = source.map((key, value) => MapEntry(key.toString(), value));
    final data = map['data'];
    return ImSyncRecordAck(
      success: ImSendAck._successFrom(map),
      records: _recordsFrom(data),
    );
  }

  static List<Map<String, dynamic>> _recordsFrom(Object? data) {
    final source = data is String ? _tryDecode(data) : data;
    if (source is! List) {
      return const [];
    }
    return source
        .whereType<Map>()
        .map(
          (item) => item.map((key, value) => MapEntry(key.toString(), value)),
        )
        .toList(growable: false);
  }

  static Object? _tryDecode(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }
}

class ImSendAck {
  const ImSendAck({
    required this.success,
    this.serverMessageId,
    this.roomId,
    this.sendTime,
    this.message,
  });

  final bool success;
  final int? serverMessageId;
  final int? roomId;
  final int? sendTime;
  final String? message;

  factory ImSendAck.fromPayload(dynamic payload) {
    final source = _unwrap(payload);
    if (source is! Map) {
      return const ImSendAck(success: false);
    }
    final map = source.map((key, value) => MapEntry(key.toString(), value));
    final data = map['data'] is Map
        ? (map['data'] as Map).map(
            (key, value) => MapEntry(key.toString(), value),
          )
        : const <String, dynamic>{};
    return ImSendAck(
      success: _successFrom(map),
      serverMessageId: _toNullableInt(data['id']),
      roomId: _toNullableInt(data['roomId']),
      sendTime: _toNullableInt(data['sendTime'] ?? data['timestamp']),
      message: _messageFrom(map),
    );
  }

  static dynamic _unwrap(dynamic payload) {
    dynamic source = payload;
    if (source is List && source.isNotEmpty) {
      source = source.first;
    }
    if (source is String) {
      try {
        return jsonDecode(source);
      } catch (_) {
        return source;
      }
    }
    return source;
  }

  static bool _successFrom(Map<String, dynamic> map) {
    if (_isNonBlockingPushFailure(map)) {
      return true;
    }
    final success = map['success'];
    if (success is bool) {
      return success;
    }
    final code = _toNullableInt(map['code']);
    return code == 200 || code == 0;
  }

  static bool _isNonBlockingPushFailure(Map<String, dynamic> map) {
    if (map['event']?.toString() != 'sendChat') {
      return false;
    }
    final data = map['data']?.toString() ?? '';
    return data.contains('FirebaseApp with name [DEFAULT]') ||
        data.contains('FirebaseMessaging');
  }

  static String? _messageFrom(Map<String, dynamic> map) {
    final message = map['message']?.toString();
    if (message != null && message.trim().isNotEmpty) {
      return message;
    }
    return map['data']?.toString();
  }

  static int? _toNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }
}
