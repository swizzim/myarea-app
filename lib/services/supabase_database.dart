import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myarea_app/models/event_model.dart';
import 'package:myarea_app/models/event_response_model.dart';
import 'package:myarea_app/models/friend_request_model.dart';
import 'package:myarea_app/models/user_model.dart' as app;
import 'package:myarea_app/models/event_category_model.dart';
import 'dart:math' as math;

class SupabaseDatabase {
  static final SupabaseDatabase instance = SupabaseDatabase._();
  SupabaseDatabase._();

  late final SupabaseClient _supabase;

  Future<void> initialize() async {
    _supabase = Supabase.instance.client;
  }

  // Referral helpers
  Future<String?> getUserIdByReferralCode(String referralCode) async {
    try {
      final response = await _supabase
          .from('users')
          .select('id')
          .eq('username', referralCode)
          .maybeSingle();
      return response != null ? response['id'] as String : null;
    } catch (e) {
      print('Error getting user by referral code: $e');
      return null;
    }
  }

  Future<bool> createFriendshipIfNone(String userIdA, String userIdB) async {
    try {
      if (userIdA == userIdB) return false;
      final existing = await _supabase
          .from('friend_requests')
          .select('id, status')
          .or('and(sender_id.eq.$userIdA,receiver_id.eq.$userIdB),and(sender_id.eq.$userIdB,receiver_id.eq.$userIdA)')
          .maybeSingle();
      if (existing != null) {
        final status = existing['status'] as String?;
        if (status == 'accepted') return true;
        // Upgrade to accepted if pending between these users
        await _supabase
            .from('friend_requests')
            .update({'status': 'accepted', 'updated_at': DateTime.now().toIso8601String()})
            .eq('id', existing['id']);
        return true;
      }
      // Insert accepted friendship directly
      await _supabase
          .from('friend_requests')
          .insert({
            'sender_id': userIdA,
            'receiver_id': userIdB,
            'status': 'accepted',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });
      return true;
    } catch (e) {
      print('Error creating friendship: $e');
      return false;
    }
  }

  Future<bool> setUserReferredByIfEmpty(String userId, String referrerUserId) async {
    try {
      if (userId == referrerUserId) return false;
      final user = await _supabase
          .from('users')
          .select('referred_by')
          .eq('id', userId)
          .maybeSingle();
      if (user == null) return false;
      if (user['referred_by'] != null) return true; // already set
      await _supabase
          .from('users')
          .update({'referred_by': referrerUserId})
          .eq('id', userId);
      return true;
    } catch (e) {
      print('Error setting referred_by: $e');
      return false;
    }
  }

  // Events methods
  Future<List<Event>> getAllEvents() async {
    final response = await _supabase
        .from('events')
        .select()
        .eq('is_deleted', false)
        .order('created_at', ascending: false);
    return response.map((event) => Event.fromMap(event)).toList();
  }

  Future<List<Event>> getEventsPaginated({int limit = 10, int offset = 0}) async {
    final response = await _supabase
        .from('events')
        .select()
        .eq('is_deleted', false)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return response.map((event) => Event.fromMap(event)).toList();
  }

  // New method for filtered events with backend filtering
  Future<List<Event>> getEventsFiltered({
    int limit = 10,
    int offset = 0,
    List<String>? categories,
    DateTime? fromDate,
    DateTime? toDate,
    double? distanceKm,
    double? searchCenterLat,
    double? searchCenterLng,
    EventResponseType? userResponse,
    String? userId,
    bool? freeOnly,
  }) async {
    try {
      bool hasDateFilter = fromDate != null || toDate != null;
      
      if (hasDateFilter) {
        // For date filtering, fetch all events and filter them (simpler for smaller datasets)
        return await _getEventsWithDateFiltering(
          limit: limit,
          offset: offset,
          categories: categories,
          fromDate: fromDate,
          toDate: toDate,
          distanceKm: distanceKm,
          searchCenterLat: searchCenterLat,
          searchCenterLng: searchCenterLng,
          userResponse: userResponse,
          userId: userId,
          freeOnly: freeOnly,
        );
      } else {
        // For non-date filtering, use normal pagination
        return await _getEventsWithNormalPagination(
          limit: limit,
          offset: offset,
          categories: categories,
          distanceKm: distanceKm,
          searchCenterLat: searchCenterLat,
          searchCenterLng: searchCenterLng,
          userResponse: userResponse,
          userId: userId,
          freeOnly: freeOnly,
        );
      }
    } catch (e) {
      print('Error getting filtered events: $e');
      return [];
    }
  }

  // Helper method for date filtering using cursor-based pagination
  Future<List<Event>> _getEventsWithDateFiltering({
    required int limit,
    required int offset,
    List<String>? categories,
    DateTime? fromDate,
    DateTime? toDate,
    double? distanceKm,
    double? searchCenterLat,
    double? searchCenterLng,
    EventResponseType? userResponse,
    String? userId,
    bool? freeOnly,
  }) async {
    try {
      // For smaller datasets, fetch all events at once and filter them
      // This is simpler and more efficient than cursor-based pagination
      
      // Build the base query
      var query = _supabase
          .from('events')
          .select()
          .eq('is_deleted', false)
          .eq('status', 'approved');

      // For now, we'll do basic date filtering at DB level and detailed schedule filtering in Flutter
      // This is because Supabase doesn't easily support complex JSON parsing in WHERE clauses
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // Filter out events that ended before today
      query = query.gte('end_date', today.toIso8601String());
      


      // Apply category filter (array overlap)
      if (categories != null && categories.isNotEmpty) {
        query = query.overlaps('category', categories);
      }

      // Apply basic date range filter as a broad pre-filter
      if (fromDate != null) {
        query = query.gte('end_date', fromDate.toIso8601String());
      }
      if (toDate != null) {
        query = query.lte('start_date', toDate.toIso8601String());
      }

      // Apply user response filter
      if (userResponse != null && userId != null) {
        if (userResponse == EventResponseType.interested) {
          final responseQuery = _supabase
              .from('event_responses')
              .select('event_id')
              .eq('user_id', userId)
              .eq('response_type', userResponse.toString().split('.').last);
          
          final responseResult = await responseQuery;
          if (responseResult.isNotEmpty) {
            final eventIds = responseResult.map((r) => r['event_id'] as int).toList();
            query = query.inFilter('id', eventIds);
          } else {
            return [];
          }
        } else if (userResponse == EventResponseType.noResponse) {
          final userResponsesQuery = _supabase
              .from('event_responses')
              .select('event_id')
              .eq('user_id', userId);
          
          final userResponsesResult = await userResponsesQuery;
          if (userResponsesResult.isNotEmpty) {
            final respondedEventIds = userResponsesResult.map((r) => r['event_id'] as int).toList();
            query = query.not('id', 'in', '(${respondedEventIds.join(',')})');
          }
        }
      }

      // Apply sorting and fetch all events (end_date ASC, id DESC as tie-breaker)
      final finalQuery = query
          .order('end_date', ascending: true)
          .order('id', ascending: false);

      final response = await finalQuery;
      
      List<Event> events = response.map((event) => Event.fromMap(event)).toList();

      // Apply distance filter
      if (distanceKm != null && searchCenterLat != null && searchCenterLng != null) {
        events = events.where((event) {
          final distance = _calculateDistance(
            searchCenterLat, 
            searchCenterLng, 
            event.latitude, 
            event.longitude
          );
          return distance <= distanceKm;
        }).toList();
      }

      // Apply free filter
      if (freeOnly == true) {
        events = events.where((event) => event.ticketPrice == 0).toList();
      }

      // Apply schedule-based date filtering
      final actualFromDate = fromDate ?? DateTime.now();
      final actualToDate = toDate ?? DateTime.now().add(Duration(days: 365));
      
      print('🔍 DEBUG: Applying schedule-based date filtering');
      print('🔍 DEBUG: Date range: ${actualFromDate.toIso8601String()} to ${actualToDate.toIso8601String()}');
      print('🔍 DEBUG: Events before filtering: ${events.length}');
      
      events = events.where((event) {
        print('🔍 DEBUG: Checking event ${event.id} (${event.title})');
        print('🔍 DEBUG: Event dates: ${event.startDate.toIso8601String()} to ${event.endDate.toIso8601String()}');
        
        // Check if event is currently active using schedule data
        final isActive = event.isCurrentlyActive;
        
        if (!isActive) {
          return false;
        }
        
        // Check if event has occurrences in the specified date range
        final hasOccurrences = event.hasOccurrencesInDateRange(actualFromDate, actualToDate);
        
        if (!hasOccurrences) {
          return false;
        }
        
        return true;
      }).toList();

      // Ensure desired ordering after filtering: end_date ASC, id DESC
      events.sort((a, b) {
        final endCompare = a.endDate.compareTo(b.endDate);
        if (endCompare != 0) return endCompare;
        return b.id.compareTo(a.id);
      });
      
      // Apply pagination to the filtered results
      final startIndex = offset;
      final endIndex = offset + limit;
      if (startIndex < events.length) {
        final paginatedEvents = events.sublist(startIndex, endIndex > events.length ? events.length : endIndex);
        return paginatedEvents;
      } else {
        return [];
      }
    } catch (e) {
      print('Error getting events with date filtering: $e');
      return [];
    }
  }

  // Helper method for normal pagination (no date filtering)
  Future<List<Event>> _getEventsWithNormalPagination({
    required int limit,
    required int offset,
    List<String>? categories,
    double? distanceKm,
    double? searchCenterLat,
    double? searchCenterLng,
    EventResponseType? userResponse,
    String? userId,
    bool? freeOnly,
  }) async {
    try {
      var query = _supabase
          .from('events')
          .select()
          .eq('is_deleted', false)
          .eq('status', 'approved');

      // Always filter out past events at the database level
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // Filter out events that ended before today
      query = query.gte('end_date', today.toIso8601String());
      


      // Apply category filter (array overlap)
      if (categories != null && categories.isNotEmpty) {
        query = query.overlaps('category', categories);
      }

      // Apply user response filter
      if (userResponse != null && userId != null) {
        if (userResponse == EventResponseType.interested) {
          final responseQuery = _supabase
              .from('event_responses')
              .select('event_id')
              .eq('user_id', userId)
              .eq('response_type', userResponse.toString().split('.').last);
          
          final responseResult = await responseQuery;
          if (responseResult.isNotEmpty) {
            final eventIds = responseResult.map((r) => r['event_id'] as int).toList();
            query = query.inFilter('id', eventIds);
          } else {
            return [];
          }
        } else if (userResponse == EventResponseType.noResponse) {
          final userResponsesQuery = _supabase
              .from('event_responses')
              .select('event_id')
              .eq('user_id', userId);
          
          final userResponsesResult = await userResponsesQuery;
          if (userResponsesResult.isNotEmpty) {
            final respondedEventIds = userResponsesResult.map((r) => r['event_id'] as int).toList();
            query = query.not('id', 'in', '(${respondedEventIds.join(',')})');
          }
        }
      }

      // Apply sorting and pagination (end_date ASC, id DESC)
      final finalQuery = query
          .order('end_date', ascending: true)
          .order('id', ascending: false)
          .range(offset, offset + limit - 1);

      final response = await finalQuery;
      List<Event> events = response.map((event) => Event.fromMap(event)).toList();

      // Apply distance filter
      if (distanceKm != null && searchCenterLat != null && searchCenterLng != null) {
        events = events.where((event) {
          final distance = _calculateDistance(
            searchCenterLat, 
            searchCenterLng, 
            event.latitude, 
            event.longitude
          );
          return distance <= distanceKm;
        }).toList();
      }

      // Apply free filter
      if (freeOnly == true) {
        events = events.where((event) => event.ticketPrice == 0).toList();
      }

      // Apply schedule-based filtering to remove past events
      events = events.where((event) {
        // Check if event is currently active using schedule data
        final isActive = event.isCurrentlyActive;
        
        if (!isActive) {
          return false;
        }
        
        return true;
      }).toList();

      return events;
    } catch (e) {
      print('Error getting events with normal pagination: $e');
      return [];
    }
  }

  Future<Event?> getEvent(int id) async {
    final response = await _supabase
        .from('events')
        .select()
        .eq('id', id)
        .eq('is_deleted', false)
        .maybeSingle();
    if (response == null) return null;
    return Event.fromMap(response);
  }

  Future<bool> insertEvent(Event event) async {
    try {
      await _supabase
          .from('events')
          .insert(event.toMap());
      return true;
    } catch (e) {
      print('Error creating event: $e');
      return false;
    }
  }

  Future<bool> updateEvent(Event event) async {
    try {
      await _supabase
          .from('events')
          .update(event.toMap())
          .eq('id', event.id);
      return true;
    } catch (e) {
      print('Error updating event: $e');
      return false;
    }
  }

  Future<bool> deleteEvent(int id) async {
    try {
      await _supabase
          .from('events')
          .delete()
          .eq('id', id);
      return true;
    } catch (e) {
      print('Error deleting event: $e');
      return false;
    }
  }

  // Event Response methods
  Future<List<EventResponse>> getEventResponses(int eventId) async {
    final response = await _supabase
        .from('event_responses')
        .select()
        .eq('event_id', eventId)
        .order('created_at', ascending: false);
    return response.map((resp) => EventResponse.fromMap(resp)).toList();
  }

  Future<EventResponse?> getUserEventResponse(int eventId, String userId) async {
    final response = await _supabase
        .from('event_responses')
        .select()
        .eq('event_id', eventId)
        .eq('user_id', userId)
        .maybeSingle();
    if (response == null) return null;
    return EventResponse.fromMap(response);
  }

  Future<bool> upsertEventResponse(EventResponse response) async {
    try {
      // First delete any existing response for this event/user combination
      await _supabase
          .from('event_responses')
          .delete()
          .eq('event_id', response.eventId)
          .eq('user_id', response.userId);

      // Then insert the new response
      await _supabase
          .from('event_responses')
          .insert(response.toMap());
      return true;
    } catch (e) {
      print('Error upserting event response: $e');
      return false;
    }
  }

  Future<bool> deleteEventResponse(int eventId, String userId) async {
    try {
      await _supabase
          .from('event_responses')
          .delete()
          .eq('event_id', eventId)
          .eq('user_id', userId);
      return true;
    } catch (e) {
      print('Error deleting event response: $e');
      return false;
    }
  }

  Future<Map<EventResponseType, int>> getEventResponseCounts(int eventId) async {
    try {
      final response = await _supabase
          .from('event_responses')
          .select('response_type')
          .eq('event_id', eventId);
      
      final counts = <EventResponseType, int>{
        EventResponseType.interested: 0,
      };
      
      for (final resp in response) {
        final type = EventResponseType.values.firstWhere(
          (e) => e.toString() == 'EventResponseType.${resp['response_type']}',
        );
        counts[type] = (counts[type] ?? 0) + 1;
      }
      
      return counts;
    } catch (e) {
      print('Error getting event response counts: $e');
      return {
        EventResponseType.interested: 0,
      };
    }
  }

  Future<List<Event>> getEventsByUserResponse(String userId, EventResponseType? responseType) async {
    try {
      if (responseType == null) {
        // If no response type specified, return all events
        return getAllEvents();
      }

      if (responseType == EventResponseType.interested) {
        // Get event IDs where user has the specified response
        final response = await _supabase
            .from('event_responses')
            .select('event_id')
            .eq('user_id', userId)
            .eq('response_type', responseType.toString().split('.').last);

        if (response.isEmpty) {
          return [];
        }

        final eventIds = response.map((r) => r['event_id'] as int).toList();

        // Get events with those IDs
        final eventsResponse = await _supabase
            .from('events')
            .select()
            .inFilter('id', eventIds)
            .eq('is_deleted', false)
            .eq('status', 'approved')
            .order('created_at', ascending: false);

        return eventsResponse.map((event) => Event.fromMap(event)).toList();
      } else {
        // For "no response" case, we need to find events where user has no response
        // First get all events
        final allEvents = await getAllEvents();
        
        // Get events where user has any response
        final userResponses = await _supabase
            .from('event_responses')
            .select('event_id')
            .eq('user_id', userId);

        final respondedEventIds = userResponses.map((r) => r['event_id'] as int).toSet();
        
        // Filter out events where user has responded
        return allEvents.where((event) => !respondedEventIds.contains(event.id)).toList();
      }
    } catch (e) {
      print('Error getting events by user response: $e');
      return [];
    }
  }

  // Friend Request methods
  Future<List<FriendRequest>> getPendingFriendRequests(String userId) async {
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('''
            *,
            sender:users!friend_requests_sender_id_fkey(
              username,
              first_name,
              last_name
            ),
            receiver:users!friend_requests_receiver_id_fkey(
              username,
              first_name,
              last_name
            )
          ''')
          .eq('receiver_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      
      return response.map((req) {
        final sender = req['sender'] as Map<String, dynamic>?;
        final receiver = req['receiver'] as Map<String, dynamic>?;
        
        return FriendRequest.fromMap({
          ...req,
          'sender_username': sender?['username'],
          'sender_first_name': sender?['first_name'],
          'sender_last_name': sender?['last_name'],
          'receiver_username': receiver?['username'],
          'receiver_first_name': receiver?['first_name'],
          'receiver_last_name': receiver?['last_name'],
        });
      }).toList();
    } catch (e) {
      print('Error getting pending friend requests: $e');
      return [];
    }
  }

  Future<List<FriendRequest>> getSentFriendRequests(String userId) async {
    try {
      final response = await _supabase
          .from('friend_requests')
          .select('''
            *,
            sender:users!friend_requests_sender_id_fkey(
              username,
              first_name,
              last_name
            ),
            receiver:users!friend_requests_receiver_id_fkey(
              username,
              first_name,
              last_name
            )
          ''')
          .eq('sender_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      
      return response.map((req) {
        final sender = req['sender'] as Map<String, dynamic>?;
        final receiver = req['receiver'] as Map<String, dynamic>?;
        
        return FriendRequest.fromMap({
          ...req,
          'sender_username': sender?['username'],
          'sender_first_name': sender?['first_name'],
          'sender_last_name': sender?['last_name'],
          'receiver_username': receiver?['username'],
          'receiver_first_name': receiver?['first_name'],
          'receiver_last_name': receiver?['last_name'],
        });
      }).toList();
    } catch (e) {
      print('Error getting sent friend requests: $e');
      return [];
    }
  }

  Future<bool> sendFriendRequest(String senderId, String receiverId) async {
    try {
      // Check if a request already exists
      final existingRequest = await _supabase
          .from('friend_requests')
          .select()
          .or('and(sender_id.eq.$senderId,receiver_id.eq.$receiverId),and(sender_id.eq.$receiverId,receiver_id.eq.$senderId)')
          .maybeSingle();

      if (existingRequest != null) {
        final status = existingRequest['status'];
        if (status == 'rejected' || status == 'retracted') {
          // Update the old request to pending
          await _supabase
              .from('friend_requests')
              .update({
                'status': 'pending',
                'updated_at': DateTime.now().toIso8601String(),
                'created_at': DateTime.now().toIso8601String(),
              })
              .eq('id', existingRequest['id']);
          return true;
        }
        if (status == 'pending' || status == 'accepted') {
          return false; // Block if already pending or accepted
        }
      }

      // No request exists, insert a new one
      await _supabase
          .from('friend_requests')
          .insert({
            'sender_id': senderId,
            'receiver_id': receiverId,
            'status': 'pending',
          });
      return true;
    } catch (e) {
      print('Error sending friend request: $e');
      return false;
    }
  }

  Future<bool> respondToFriendRequest(String requestId, FriendRequestStatus status) async {
    try {
      await _supabase
          .from('friend_requests')
          .update({
            'status': status.toString().split('.').last,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', requestId);
      return true;
    } catch (e) {
      print('Error responding to friend request: $e');
      return false;
    }
  }

  Future<List<app.User>> getFriendsList(String userId) async {
    try {
      // Get accepted friend requests where user is either sender or receiver
      final response = await _supabase
          .from('friend_requests')
          .select('''
            *,
            sender:users!friend_requests_sender_id_fkey(*),
            receiver:users!friend_requests_receiver_id_fkey(*)
          ''')
          .or('sender_id.eq.$userId,receiver_id.eq.$userId')
          .eq('status', 'accepted')
          .order('updated_at', ascending: false);
      
      final friends = <app.User>[];
      
      for (final req in response) {
        final sender = req['sender'] as Map<String, dynamic>;
        final receiver = req['receiver'] as Map<String, dynamic>;
        
        // Add the other user (not the current user) to friends list
        if (sender['id'] == userId) {
          friends.add(app.User.fromMap(receiver));
        } else {
          friends.add(app.User.fromMap(sender));
        }
      }
      
      return friends;
    } catch (e) {
      print('Error getting friends list: $e');
      return [];
    }
  }

  Future<List<app.User>> searchUsers(String query, String currentUserId) async {
    try {
      final response = await _supabase
          .from('users')
          .select()
          .or('username.ilike.%$query%,first_name.ilike.%$query%,last_name.ilike.%$query%')
          .neq('id', currentUserId)
          .limit(10);
      
      return response.map((user) => app.User.fromMap(user)).toList();
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  Future<bool> checkFriendRequestExists(String userId1, String userId2) async {
    try {
      final response = await _supabase
          .from('friend_requests')
          .select()
          .or('and(sender_id.eq.$userId1,receiver_id.eq.$userId2),and(sender_id.eq.$userId2,receiver_id.eq.$userId1)')
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      print('Error checking friend request: $e');
      return false;
    }
  }

  Future<bool> areFriends(String userId1, String userId2) async {
    try {
      final response = await _supabase
          .from('friend_requests')
          .select()
          .or('and(sender_id.eq.$userId1,receiver_id.eq.$userId2),and(sender_id.eq.$userId2,receiver_id.eq.$userId1)')
          .eq('status', 'accepted')
          .maybeSingle();
      
      return response != null;
    } catch (e) {
      print('Error checking if users are friends: $e');
      return false;
    }
  }

  // Get friends' responses to a specific event
  Future<Map<String, EventResponseType>> getFriendsEventResponses(int eventId, List<String> friendIds) async {
    try {
      if (friendIds.isEmpty) return {};
      
      final response = await _supabase
          .from('event_responses')
          .select('user_id, response_type')
          .eq('event_id', eventId)
          .inFilter('user_id', friendIds);
      
      final Map<String, EventResponseType> friendResponses = {};
      
      for (final resp in response) {
        final userId = resp['user_id'] as String;
        final responseType = EventResponseType.values.firstWhere(
          (e) => e.toString() == 'EventResponseType.${resp['response_type']}',
        );
        friendResponses[userId] = responseType;
      }
      
      return friendResponses;
    } catch (e) {
      print('Error getting friends event responses: $e');
      return {};
    }
  }

  // Get friends responses for a specific event (for event details screen)
  Future<Map<String, EventResponseType>> getEventFriendsResponses(int eventId) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id; // User will always be logged in
      // First get the user's friends list
      final friendsList = await getFriendsList(userId);
      if (friendsList.isEmpty) return {};
      final friendIds = friendsList.map((friend) => friend.id!).toList();
      // Then get their responses to this event
      return await getFriendsEventResponses(eventId, friendIds);
    } catch (e) {
      print('Error getting event friends responses: $e');
      return {};
    }
  }

  // Get friends' user objects grouped by response type for a specific event
  Future<Map<EventResponseType, List<app.User>>> getEventFriendsByResponseType(int eventId) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id; // User will always be logged in
      // Get friends list
      final friendsList = await getFriendsList(userId);
      if (friendsList.isEmpty) return {
        EventResponseType.interested: [],
      };
      final friendIds = friendsList.map((f) => f.id!).toList();
      // Get their responses to this event
      final responses = await _supabase
        .from('event_responses')
        .select('user_id, response_type')
        .eq('event_id', eventId)
        .inFilter('user_id', friendIds);
      final Map<String, EventResponseType> friendResponseMap = {};
      for (final resp in responses) {
        final userId = resp['user_id'] as String;
        final responseType = EventResponseType.values.firstWhere(
          (e) => e.toString() == 'EventResponseType.${resp['response_type']}',
        );
        friendResponseMap[userId] = responseType;
      }
      // Group friends by response type
      final interested = <app.User>[];
      for (final friend in friendsList) {
        final resp = friendResponseMap[friend.id];
        if (resp == EventResponseType.interested) {
          interested.add(friend);
        }
      }
      return {
        EventResponseType.interested: interested,
      };
    } catch (e) {
      print('Error getting event friends by response type: $e');
      return {
        EventResponseType.interested: [],
      };
    }
  }

  // Cancel (retract) a sent friend request by its ID
  Future<bool> cancelSentFriendRequest(String requestId) async {
    try {
      print('Cancelling friend request $requestId (setting status to retracted)');
      await _supabase
          .from('friend_requests')
          .update({'status': 'retracted', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', requestId);
      print('Friend request $requestId set to retracted');
      return true;
    } catch (e) {
      print('Error cancelling sent friend request: '
          '\x1B[31m$e\x1B[0m');
      return false;
    }
  }

  // Fetch all event categories from Supabase
  Future<List<EventCategory>> getAllEventCategories() async {
    try {
      final response = await _supabase
          .from('event_categories')
          .select();
      return response.map((cat) => EventCategory.fromMap(cat)).toList();
    } catch (e) {
      print('Error fetching event categories: $e');
      return [];
    }
  }

  // Helper method to calculate distance
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    const double R = 6371; // Earth's radius in kilometers
    double dLat = _deg2rad(lat2 - lat1);
    double dLng = _deg2rad(lng2 - lng1);
    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(lat1)) * math.cos(_deg2rad(lat2)) *
            math.sin(dLng / 2) * math.sin(dLng / 2);
    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _deg2rad(double deg) => deg * (math.pi / 180);
} 