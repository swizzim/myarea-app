import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myarea_app/models/conversation_model.dart';
import 'package:myarea_app/models/message_model.dart';
import 'package:myarea_app/models/user_model.dart' as app;

class MessagingService {
  static final MessagingService instance = MessagingService._();
  MessagingService._();

  late final SupabaseClient _supabase;

  // Getter to access supabase client
  SupabaseClient get supabase => _supabase;

  Future<void> initialize() async {
    _supabase = Supabase.instance.client;
  }

  // Get all conversations for the current user
  Future<List<Conversation>> getUserConversations() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('Error getting user conversations: No authenticated user');
        return [];
      }
      
      final userId = currentUser.id;
      
      final response = await _supabase
          .from('conversations')
          .select('''
            *,
            conversation_participants!inner(user_id),
            messages(
              id,
              content,
              sender_id,
              created_at,
              updated_at
            )
          ''')
          .eq('conversation_participants.user_id', userId)
          .order('updated_at', ascending: false);

      final conversations = <Conversation>[];
      
      for (final conv in response) {
        final participants = await _getConversationParticipants(conv['id']);
        final lastMessage = await _getLastMessage(conv['id']);
        
        conversations.add(Conversation(
          id: conv['id'],
          createdAt: DateTime.parse(conv['created_at']),
          updatedAt: DateTime.parse(conv['updated_at']),
          participantIds: participants.map((p) => p.id!).toList(),
          lastMessage: lastMessage,
          participantDetails: await _getParticipantDetails(participants),
          eventId: conv['event_id'],
        ));
      }
      
      return conversations;
    } catch (e) {
      print('Error getting user conversations: $e');
      return [];
    }
  }

  // Get conversation participants
  Future<List<app.User>> _getConversationParticipants(String conversationId) async {
    try {
      final response = await _supabase
          .from('conversation_participants')
          .select('user_id')
          .eq('conversation_id', conversationId);
      
      // Get user details for each participant
      final userIds = response.map((p) => p['user_id'] as String).toList();
      final users = <app.User>[];
      
      for (final userId in userIds) {
        try {
          final userResponse = await _supabase
              .from('users')
              .select('id, email, username, first_name, last_name')
              .eq('id', userId)
              .single();
          
          // Handle null values properly
          final user = app.User(
            id: userResponse['id']?.toString(),
            email: userResponse['email'] ?? '',
            username: userResponse['username'] ?? '',
            firstName: userResponse['first_name'],
            lastName: userResponse['last_name'],
            postcode: userResponse['postcode'],
            ageGroup: userResponse['age_group'],
            interests: userResponse['interests'] != null 
                ? List<String>.from(userResponse['interests'])
                : null,
          );
          
          users.add(user);
        } catch (e) {
          print('Error getting user details for $userId: $e');
        }
      }
      
      return users;
    } catch (e) {
      print('Error getting conversation participants: $e');
      return [];
    }
  }

  // Get participant details for display
  Future<Map<String, dynamic>> _getParticipantDetails(List<app.User> participants) async {
    final details = <String, dynamic>{};
    for (final participant in participants) {
      details[participant.id!] = {
        'username': participant.username,
        'first_name': participant.firstName,
        'last_name': participant.lastName,
      };
    }
    return details;
  }

  // Get last message in conversation
  Future<Message?> _getLastMessage(String conversationId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response == null) return null;
      
      return Message.fromMap(response);
    } catch (e) {
      print('Error getting last message: $e');
      return null;
    }
  }

  // Check if a group conversation with the same participants and event already exists
  Future<String?> findExistingGroupConversation(List<String> participantIds, {int? eventId}) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('Error finding existing group conversation: No authenticated user');
        return null;
      }
      
      // Sort participant IDs for consistent comparison
      final sortedParticipantIds = List<String>.from(participantIds)..sort();
      
      // Get all conversations for the current user
      final userConversations = await getUserConversations();
      
      for (final conversation in userConversations) {
        
        // Check if this conversation has the same event context
        if (conversation.eventId != eventId) {
          continue;
        }
        
        // Check if this conversation has the same participants
        final conversationParticipantIds = List<String>.from(conversation.participantIds)..sort();
        
        // Check if the participant lists match exactly
        if (conversationParticipantIds.length == sortedParticipantIds.length &&
            conversationParticipantIds.every((id) => sortedParticipantIds.contains(id))) {
          return conversation.id;
        }
      }
      
      return null;
    } catch (e) {
      print('Error finding existing group conversation: $e');
      return null;
    }
  }

  // Find a conversation that has exactly the given participants (regardless of event)
  Future<Conversation?> findConversationByExactParticipants(List<String> participantIds) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('Error finding conversation by participants: No authenticated user');
        return null;
      }

      final sortedParticipantIds = List<String>.from(participantIds)..sort();
      final userConversations = await getUserConversations();

      for (final conversation in userConversations) {
        final ids = List<String>.from(conversation.participantIds)..sort();
        if (ids.length == sortedParticipantIds.length &&
            ids.every((id) => sortedParticipantIds.contains(id))) {
          return conversation;
        }
      }
      return null;
    } catch (e) {
      print('Error finding conversation by exact participants: $e');
      return null;
    }
  }

  // Attach an event to an existing conversation (set event_id)
  Future<bool> attachEventToConversation(String conversationId, int eventId) async {
    try {
      await _supabase
          .from('conversations')
          .update({'event_id': eventId, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', conversationId);
      return true;
    } catch (e) {
      print('Error attaching event to conversation: $e');
      return false;
    }
  }

  // Check if a 1:1 conversation between two users already exists
  Future<String?> findExistingOneOnOneConversation(String user1Id, String user2Id) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('Error finding existing 1:1 conversation: No authenticated user');
        return null;
      }
      
      // Get all conversations for the current user
      final userConversations = await getUserConversations();
      
      for (final conversation in userConversations) {
        
        // Skip group conversations
        if (conversation.isGroupConversation()) {
          continue;
        }
        
        // Check if this conversation has exactly these two participants
        final participantIds = conversation.participantIds;
        if (participantIds.length == 2 &&
            participantIds.contains(user1Id) &&
            participantIds.contains(user2Id)) {
          return conversation.id;
        }
      }
      
      return null;
    } catch (e) {
      print('Error finding existing 1:1 conversation: $e');
      return null;
    }
  }

  // Get or create conversation between two users
  Future<String> getOrCreateConversation(String user1Id, String user2Id) async {
    try {
      print('MessagingService: Getting or creating conversation between $user1Id and $user2Id');
      
      // First try the database function
      final response = await _supabase
          .rpc('get_or_create_conversation', params: {
            'user1_id': user1Id,
            'user2_id': user2Id,
          });
      
      print('MessagingService: Database function returned conversation ID: $response');
      return response;
    } catch (e) {
      print('MessagingService: Database function failed, falling back to manual check: $e');
      
      // Fallback: check if conversation exists manually
      final existingConversationId = await findExistingOneOnOneConversation(user1Id, user2Id);
      
      if (existingConversationId != null) {
        print('MessagingService: Found existing 1:1 conversation: $existingConversationId');
        return existingConversationId;
      }
      
      print('MessagingService: Creating new conversation manually');
      
      // Create new conversation manually
      final conversationResponse = await _supabase
          .from('conversations')
          .insert({
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select('id')
          .single();
      
      final conversationId = conversationResponse['id'];
      print('MessagingService: Created new conversation with ID: $conversationId');
      
      // Add both participants
      await _supabase
          .from('conversation_participants')
          .insert([
            {
              'conversation_id': conversationId,
              'user_id': user1Id,
            },
            {
              'conversation_id': conversationId,
              'user_id': user2Id,
            },
          ]);
      
      print('MessagingService: Added participants to conversation: $conversationId');
      return conversationId;
    }
  }

  // Create a group conversation with multiple participants and optional eventId
  Future<String> createGroupConversation(List<String> participantIds, {int? eventId}) async {
    try {
      // First, check if a conversation with the same participants and event already exists
      final existingConversationId = await findExistingGroupConversation(participantIds, eventId: eventId);
      
      if (existingConversationId != null) {
        print('✅ Reusing existing group conversation: $existingConversationId');
        return existingConversationId;
      }
      
      // Create a new conversation
      final conversationResponse = await _supabase
          .from('conversations')
          .insert({
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
            if (eventId != null) 'event_id': eventId,
          })
          .select('id')
          .single();
      
      final conversationId = conversationResponse['id'];
      print('✅ Created new group conversation: $conversationId');
      
      // Add all participants to the conversation
      final participantData = participantIds.map((userId) => {
        'conversation_id': conversationId,
        'user_id': userId,
      }).toList();
      
      await _supabase
          .from('conversation_participants')
          .insert(participantData);
      
      print('✅ Added ${participantIds.length} participants to conversation');
      
      return conversationId;
    } catch (e) {
      print('Error creating group conversation: $e');
      rethrow;
    }
  }

  // Get messages for a conversation
  Future<List<Message>> getConversationMessages(String conversationId) async {
    try {
      final response = await _supabase
          .from('messages')
          .select('*')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      
      return response.map((msg) => Message.fromMap(msg)).toList();
    } catch (e) {
      print('Error getting conversation messages: $e');
      return [];
    }
  }

  // Send a message
  Future<Message?> sendMessage(String conversationId, String content, {MessageType messageType = MessageType.text}) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('Error sending message: No authenticated user');
        return null;
      }
      
      final userId = currentUser.id;
      
      final response = await _supabase
          .from('messages')
          .insert({
            'conversation_id': conversationId,
            'sender_id': userId,
            'content': content,
            'message_type': messageType.toString().split('.').last,
          })
          .select('*')
          .single();
      
      // Update conversation's updated_at timestamp
      await _supabase
          .from('conversations')
          .update({'updated_at': DateTime.now().toIso8601String()})
          .eq('id', conversationId);
      
      return Message.fromMap(response);
    } catch (e) {
      print('Error sending message: $e');
      return null;
    }
  }

  // Mark messages as read
  Future<bool> markMessagesAsRead(String conversationId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        return false;
      }
      final response = await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId)
          .eq('is_read', false);
      return true;
    } catch (e) {
      print('[markMessagesAsRead] Error marking messages as read: $e');
      return false;
    }
  }

  // Mark conversation as read (wrapper for markMessagesAsRead)
  Future<bool> markConversationAsRead(String conversationId) async {
    try {
      final success = await markMessagesAsRead(conversationId);
      if (success) {
        print('[MessagingService] Successfully marked conversation $conversationId as read');
      } else {
        print('[MessagingService] Failed to mark conversation $conversationId as read');
      }
      return success;
    } catch (e) {
      print('[MessagingService] Error marking conversation as read: $e');
      return false;
    }
  }

  // Get unread message count for a conversation
  Future<int> getUnreadMessageCount(String conversationId) async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('Error getting unread message count: No authenticated user');
        return 0;
      }
      
      final userId = currentUser.id;
      
      final response = await _supabase
          .from('messages')
          .select('id')
          .eq('conversation_id', conversationId)
          .neq('sender_id', userId)
          .eq('is_read', false);
      
      return response.length;
    } catch (e) {
      print('Error getting unread message count: $e');
      return 0;
    }
  }

  // Get total unread message count for all conversations
  Future<int> getTotalUnreadMessageCount() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('Error getting total unread message count: No authenticated user');
        return 0;
      }
      
      final userId = currentUser.id;
      
      final response = await _supabase
          .from('messages')
          .select('id')
          .neq('sender_id', userId)
          .eq('is_read', false);
      
      return response.length;
    } catch (e) {
      print('Error getting total unread message count: $e');
      return 0;
    }
  }

  // Get count of conversations with unread messages
  Future<int> getUnreadConversationsCount() async {
    try {
      final currentUser = _supabase.auth.currentUser;
      if (currentUser == null) {
        print('Error getting unread conversations count: No authenticated user');
        return 0;
      }
      
      final userId = currentUser.id;
      
      // Get all conversations for the user
      final conversations = await getUserConversations();
      int unreadConversationsCount = 0;
      
      for (final conversation in conversations) {
        final lastMessage = conversation.lastMessage;
        if (lastMessage != null && 
            lastMessage.senderId != userId && 
            lastMessage.isRead == false) {
          unreadConversationsCount++;
        }
      }
      
      return unreadConversationsCount;
    } catch (e) {
      print('Error getting unread conversations count: $e');
      return 0;
    }
  }

  // Subscribe to real-time message updates
  RealtimeChannel subscribeToMessages(String conversationId, Function(Message) onMessageReceived) {
    print('MessagingService: Setting up real-time subscription for conversation: $conversationId');
    
    final channel = _supabase
        .channel('messages:$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            print('MessagingService: Received real-time message for conversation: $conversationId');
            final messageData = payload.newRecord;
            if (messageData != null) {
              try {
                final message = Message.fromMap(messageData);
                print('MessagingService: Parsed message: ${message.content}');
                onMessageReceived(message);
              } catch (e) {
                print('MessagingService: Error parsing real-time message: $e');
              }
            }
          },
        )
        .subscribe((status, [error]) {
          if (error != null) {
            print('MessagingService: Real-time subscription error for conversation $conversationId: $error');
          } else {
            print('MessagingService: Real-time subscription status for conversation $conversationId: $status');
          }
        });
    
    return channel;
  }

  // Subscribe to conversation updates and new conversations
  RealtimeChannel subscribeToConversations(Function(Conversation) onConversationUpdated) {
    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) {
      print('Error subscribing to conversations: No authenticated user');
      // Return a dummy channel that does nothing
      return _supabase.channel('dummy');
    }
    
    final userId = currentUser.id;
    
    return _supabase
        .channel('conversations:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'conversations',
          callback: (payload) async {
            final conversationData = payload.newRecord;
            if (conversationData != null) {
              final conversationId = conversationData['id'];
              
              // Check if current user is a participant in this new conversation
              final participants = await _getConversationParticipants(conversationId);
              final isParticipant = participants.any((p) => p.id == userId);
              
              if (isParticipant) {
                // Get the new conversation with participants and last message
                final lastMessage = await _getLastMessage(conversationId);
                
                final conversation = Conversation(
                  id: conversationId,
                  createdAt: DateTime.parse(conversationData['created_at']),
                  updatedAt: DateTime.parse(conversationData['updated_at']),
                  participantIds: participants.map((p) => p.id!).toList(),
                  lastMessage: lastMessage,
                  participantDetails: await _getParticipantDetails(participants),
                  eventId: conversationData['event_id'],
                );
                
                onConversationUpdated(conversation);
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'conversations',
          callback: (payload) async {
            final conversationData = payload.newRecord;
            if (conversationData != null) {
              final conversationId = conversationData['id'];
              
              // Get updated conversation with participants and last message
              final participants = await _getConversationParticipants(conversationId);
              final lastMessage = await _getLastMessage(conversationId);
              
              final conversation = Conversation(
                id: conversationId,
                createdAt: DateTime.parse(conversationData['created_at']),
                updatedAt: DateTime.parse(conversationData['updated_at']),
                participantIds: participants.map((p) => p.id!).toList(),
                lastMessage: lastMessage,
                participantDetails: await _getParticipantDetails(participants),
                eventId: conversationData['event_id'],
              );
              
              onConversationUpdated(conversation);
            }
          },
        )
        .subscribe();
  }

  // Fetch a single conversation by ID
  Future<Conversation?> getConversationById(String conversationId) async {
    try {
      final response = await _supabase
          .from('conversations')
          .select('''
            *,
            conversation_participants!inner(user_id),
            messages(
              id,
              content,
              sender_id,
              created_at,
              updated_at
            )
          ''')
          .eq('id', conversationId)
          .maybeSingle();
      if (response == null) return null;
      final participants = await _getConversationParticipants(response['id']);
      final lastMessage = await _getLastMessage(response['id']);
      return Conversation(
        id: response['id'],
        createdAt: DateTime.parse(response['created_at']),
        updatedAt: DateTime.parse(response['updated_at']),
        participantIds: participants.map((p) => p.id!).toList(),
        lastMessage: lastMessage,
        participantDetails: await _getParticipantDetails(participants),
        eventId: response['event_id'],
      );
    } catch (e) {
      print('Error getting conversation by id: $e');
      return null;
    }
  }
} 