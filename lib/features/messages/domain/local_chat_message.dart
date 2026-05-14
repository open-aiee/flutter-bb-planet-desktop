enum ChatMessageDirection { incoming, outgoing }

enum ChatMessageSendStatus { pending, sent, read, failed }

class LocalChatMessage {
  const LocalChatMessage({
    required this.localId,
    required this.appUserId,
    required this.peerUserId,
    required this.conversationKey,
    required this.direction,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
    required this.sendStatus,
    this.roomId,
    this.clientMessageId,
    this.serverMessageId,
    this.errorMessage,
    this.sendType = 1,
    this.msgData,
    this.localMediaPath,
  });

  final String localId;
  final int appUserId;
  final int peerUserId;
  final int? roomId;
  final String conversationKey;
  final ChatMessageDirection direction;
  final String text;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ChatMessageSendStatus sendStatus;
  final String? clientMessageId;
  final String? serverMessageId;
  final String? errorMessage;
  final int sendType;
  final String? msgData;
  final String? localMediaPath;

  LocalChatMessage copyWith({
    int? roomId,
    String? conversationKey,
    ChatMessageSendStatus? sendStatus,
    String? clientMessageId,
    String? serverMessageId,
    String? errorMessage,
    int? sendType,
    String? msgData,
    String? localMediaPath,
    DateTime? updatedAt,
  }) {
    return LocalChatMessage(
      localId: localId,
      appUserId: appUserId,
      peerUserId: peerUserId,
      roomId: roomId ?? this.roomId,
      conversationKey: conversationKey ?? this.conversationKey,
      direction: direction,
      text: text,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      sendStatus: sendStatus ?? this.sendStatus,
      clientMessageId: clientMessageId ?? this.clientMessageId,
      serverMessageId: serverMessageId ?? this.serverMessageId,
      errorMessage: errorMessage,
      sendType: sendType ?? this.sendType,
      msgData: msgData ?? this.msgData,
      localMediaPath: localMediaPath ?? this.localMediaPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'localId': localId,
      'appUserId': appUserId,
      'peerUserId': peerUserId,
      'roomId': roomId,
      'conversationKey': conversationKey,
      'direction': direction.name,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'sendStatus': sendStatus.name,
      'clientMessageId': clientMessageId,
      'serverMessageId': serverMessageId,
      'errorMessage': errorMessage,
      'sendType': sendType,
      'msgData': msgData,
      'localMediaPath': localMediaPath,
    };
  }

  factory LocalChatMessage.fromJson(Map<String, dynamic> json) {
    return LocalChatMessage(
      localId: json['localId']?.toString() ?? '',
      appUserId: _asInt(json['appUserId']),
      peerUserId: _asInt(json['peerUserId']),
      roomId: _asNullableInt(json['roomId']),
      conversationKey: json['conversationKey']?.toString() ?? '',
      direction: _enumByName(
        ChatMessageDirection.values,
        json['direction']?.toString(),
        ChatMessageDirection.outgoing,
      ),
      text: json['text']?.toString() ?? '',
      createdAt: _asDateTime(json['createdAt']),
      updatedAt: _asDateTime(json['updatedAt']),
      sendStatus: _enumByName(
        ChatMessageSendStatus.values,
        json['sendStatus']?.toString(),
        ChatMessageSendStatus.pending,
      ),
      clientMessageId: json['clientMessageId']?.toString(),
      serverMessageId: json['serverMessageId']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      sendType: _asIntWithFallback(json['sendType'], 1),
      msgData: json['msgData']?.toString(),
      localMediaPath: json['localMediaPath']?.toString(),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static int _asIntWithFallback(Object? value, int fallback) {
    if (value is int) {
      return value;
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int? _asNullableInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    return int.tryParse(value.toString());
  }

  static DateTime _asDateTime(Object? value) {
    return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) {
        return value;
      }
    }
    return fallback;
  }
}

String directConversationKey({
  required int appUserId,
  required int peerUserId,
}) {
  return 'sender:$appUserId:direct-peer:$peerUserId';
}
