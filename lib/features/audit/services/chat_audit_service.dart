class ChatAuditService {
  Future<void> recordMessageSend({
    required String operatorId,
    required String appUserId,
    required String targetUserId,
    required String originalText,
    required String finalText,
    required bool translated,
    required bool success,
  }) async {
    throw UnimplementedError('Audit API integration is not implemented.');
  }
}
