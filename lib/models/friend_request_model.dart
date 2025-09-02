enum FriendRequestStatus {
  pending,
  accepted,
  rejected,
  retracted,
}

class FriendRequest {
  final String? id;
  final String senderId;
  final String receiverId;
  final FriendRequestStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  
  // Additional fields for display purposes
  final String? senderUsername;
  final String? senderFirstName;
  final String? senderLastName;
  final String? receiverUsername;
  final String? receiverFirstName;
  final String? receiverLastName;
  
  FriendRequest({
    this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.senderUsername,
    this.senderFirstName,
    this.senderLastName,
    this.receiverUsername,
    this.receiverFirstName,
    this.receiverLastName,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'status': status.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
  
  static FriendRequest fromMap(Map<String, dynamic> map) {
    return FriendRequest(
      id: map['id']?.toString(),
      senderId: map['sender_id'],
      receiverId: map['receiver_id'],
      status: FriendRequestStatus.values.firstWhere(
        (e) => e.toString() == 'FriendRequestStatus.${map['status']}',
      ),
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
      senderUsername: map['sender_username'],
      senderFirstName: map['sender_first_name'],
      senderLastName: map['sender_last_name'],
      receiverUsername: map['receiver_username'],
      receiverFirstName: map['receiver_first_name'],
      receiverLastName: map['receiver_last_name'],
    );
  }
  
  // Helper method to get display name for sender
  String get senderDisplayName {
    if (senderFirstName != null && senderLastName != null) {
      return '$senderFirstName $senderLastName';
    }
    return senderUsername ?? 'Unknown User';
  }
  
  // Helper method to get display name for receiver
  String get receiverDisplayName {
    if (receiverFirstName != null && receiverLastName != null) {
      return '$receiverFirstName $receiverLastName';
    }
    return receiverUsername ?? 'Unknown User';
  }
} 