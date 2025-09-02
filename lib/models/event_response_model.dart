import 'package:supabase_flutter/supabase_flutter.dart';

enum EventResponseType {
  interested,
  noResponse,
}

class EventResponse {
  final int? id;
  final int eventId;
  final String userId;
  final EventResponseType responseType;
  final DateTime createdAt;

  EventResponse({
    this.id,
    required this.eventId,
    required this.userId,
    required this.responseType,
    required this.createdAt,
  });

  factory EventResponse.fromMap(Map<String, dynamic> map) {
    return EventResponse(
      id: map['id'],
      eventId: map['event_id'],
      userId: map['user_id'],
      responseType: EventResponseType.values.firstWhere(
        (e) => e.toString() == 'EventResponseType.${map['response_type']}',
      ),
      createdAt: DateTime.parse(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    final map = {
      'event_id': eventId,
      'user_id': userId,
      'response_type': responseType.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
    };
    
    if (id != null) {
      map['id'] = id as int;
    }
    
    return map;
  }
} 