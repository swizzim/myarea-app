import 'package:myarea_app/models/message_model.dart';

class Conversation {
  final String id;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> participantIds;
  final Message? lastMessage;
  final Map<String, dynamic>? participantDetails;
  final int? eventId;
  
  Conversation({
    required this.id,
    required this.createdAt,
    required this.updatedAt,
    required this.participantIds,
    this.lastMessage,
    this.participantDetails,
    this.eventId,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'participant_ids': participantIds,
      'last_message': lastMessage?.toMap(),
      'participant_details': participantDetails,
      'event_id': eventId,
    };
  }
  
  static Conversation fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'],
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      participantIds: List<String>.from(map['participant_ids'] ?? []),
      lastMessage: map['last_message'] != null 
          ? Message.fromMap(map['last_message'])
          : null,
      participantDetails: map['participant_details'],
      eventId: map['event_id'],
    );
  }
  
  // Get the other participant's ID (not the current user)
  String getOtherParticipantId(String currentUserId) {
    try {
      return participantIds.firstWhere((id) => id != currentUserId);
    } catch (e) {
      // Handle cases where no other participant is found
      // This could happen if the conversation is malformed or the current user is the only participant
      if (participantIds.isNotEmpty) {
        // Return the first participant if no other is found (fallback)
        return participantIds.first;
      }
      // Return empty string if no participants at all
      return '';
    }
  }
  
  // Get the other participant's display name
  String getOtherParticipantName(String currentUserId) {
    if (participantDetails == null) return 'Unknown User';
    
    final otherId = getOtherParticipantId(currentUserId);
    
    // Handle case where no other participant was found
    if (otherId.isEmpty) {
      return 'Unknown User';
    }
    
    final otherUser = participantDetails![otherId];
    
    if (otherUser != null) {
      final firstName = otherUser['first_name'];
      final lastName = otherUser['last_name'];
      final username = otherUser['username'];
      
      if (firstName != null && lastName != null) {
        return '$firstName $lastName';
      }
      return username ?? 'Unknown User';
    }
    
    return 'Unknown User';
  }
  
  // Get the other participant's username
  String getOtherParticipantUsername(String currentUserId) {
    if (participantDetails == null) return '';
    final otherId = getOtherParticipantId(currentUserId);
    if (otherId.isEmpty) return '';
    final otherUser = participantDetails![otherId];
    if (otherUser != null) {
      return otherUser['username'] ?? '';
    }
    return '';
  }

  // Check if this is a group conversation (more than 2 participants)
  bool isGroupConversation() {
    return participantIds.length > 2;
  }

  // Get group display name (for group conversations)
  String getGroupDisplayName(String currentUserId) {
    if (!isGroupConversation()) return getOtherParticipantName(currentUserId);
    
    if (participantDetails == null) return 'Group Chat';
    
    final otherParticipants = participantIds
        .where((id) => id != currentUserId)
        .map((id) => participantDetails![id])
        .where((user) => user != null)
        .toList();
    
    if (otherParticipants.isEmpty) return 'Group Chat';
    
    // Create a list of names
    final names = <String>[];
    for (final user in otherParticipants) {
      final firstName = user['first_name'];
      final lastName = user['last_name'];
      final username = user['username'];
      
      if (firstName != null && lastName != null) {
        names.add('$firstName $lastName');
      } else if (firstName != null) {
        names.add(firstName);
      } else if (username != null) {
        names.add('@$username');
      }
    }
    
    if (names.isEmpty) return 'Group Chat';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    if (names.length == 3) return '${names[0]}, ${names[1]} & ${names[2]}';
    return '${names[0]}, ${names[1]} & ${names.length - 2} others';
  }

  // Get all participant names for group conversations
  List<String> getAllParticipantNames(String currentUserId) {
    if (participantDetails == null) return [];
    
    return participantIds
        .where((id) => id != currentUserId)
        .map((id) {
          final user = participantDetails![id];
          if (user == null) return 'Unknown User';
          
          final firstName = user['first_name'];
          final lastName = user['last_name'];
          final username = user['username'];
          
          if (firstName != null && lastName != null) {
            return '$firstName $lastName';
          } else if (firstName != null) {
            return firstName;
          } else if (username != null) {
            return '@$username';
          }
          return 'Unknown User';
        })
        .toList()
        .cast<String>();
  }
} 