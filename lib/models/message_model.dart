enum MessageType {
  text,
  image,
  file,
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final MessageType messageType;
  final bool isRead;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? senderName;
  
  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.messageType = MessageType.text,
    this.isRead = false,
    required this.createdAt,
    required this.updatedAt,
    this.senderName,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'sender_id': senderId,
      'content': content,
      'message_type': messageType.toString().split('.').last,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sender_name': senderName,
    };
  }
  
  static Message fromMap(Map<String, dynamic> map) {
    return Message(
      id: map['id'],
      conversationId: map['conversation_id'],
      senderId: map['sender_id'],
      content: map['content'],
      messageType: MessageType.values.firstWhere(
        (e) => e.toString() == 'MessageType.${map['message_type']}',
        orElse: () => MessageType.text,
      ),
      isRead: map['is_read'] ?? false,
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      senderName: map['sender_name'],
    );
  }
  
  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? content,
    MessageType? messageType,
    bool? isRead,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? senderName,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      senderName: senderName ?? this.senderName,
    );
  }
} 