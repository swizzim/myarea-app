import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myarea_app/models/conversation_model.dart';
import 'package:myarea_app/models/message_model.dart';
import 'package:myarea_app/services/messaging_service.dart';
import 'package:myarea_app/screens/messages/chat_screen.dart';
import 'package:myarea_app/screens/messages/new_message_screen.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:myarea_app/widgets/custom_notification.dart';
import 'package:myarea_app/main.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/models/event_model.dart';
import 'package:myarea_app/screens/auth/auth_flow_screen.dart';
import 'package:myarea_app/providers/auth_provider.dart';

class ConversationsScreen extends StatefulWidget {
  static final GlobalKey<_ConversationsScreenState> globalKey = GlobalKey<_ConversationsScreenState>();
  
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> with WidgetsBindingObserver {
  final MessagingService _messagingService = MessagingService.instance;
  static const String _adminBaseUrl = 'http://localhost:5002';
  List<Conversation> _conversations = [];
  bool _isLoading = true;
  RealtimeChannel? _conversationsChannel;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _timer;
  List<RealtimeChannel> _messagesChannels = [];
  bool _hasNavigatedToChat = false;
  Map<int, Event?> _eventCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConversations(showLoading: false);
    _subscribeToMessagesInAllConversations();
    _subscribeToNewConversations(); // Subscribe to new conversations
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _refreshData();
    }
    if (state == AppLifecycleState.resumed && _hasNavigatedToChat) {
      _refreshData();
      _hasNavigatedToChat = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) {
      final unreadProvider = Provider.of<UnreadMessagesProvider>(context, listen: false);
      unreadProvider.refreshUnreadCount();
      BadgeManager.updateAppBadge(context);
    }
  }

  // Public method to refresh data (can be called from outside)
  void refreshData() {
    _refreshData();
  }

  void _subscribeToMessagesInAllConversations() async {
    for (final channel in _messagesChannels) {
      channel.unsubscribe();
    }
    _messagesChannels.clear();
    assert(_messagesChannels.isEmpty, '[ConversationsScreen] _messagesChannels should be empty after clearing!');
    try {
      final conversations = await _messagingService.getUserConversations();
      final currentUser = MessagingService.instance.supabase.auth.currentUser;
      if (currentUser == null) {
        print('[ConversationsScreen] No authenticated user, skipping message subscriptions');
        return;
      }
      
      final userId = currentUser.id;
      for (final conv in conversations) {
        final channelName = 'messages:${conv.id}';
        // Prevent duplicate subscription for the same conversation
        if (_messagesChannels.any((c) => c.topic == channelName || c.topic == 'realtime:$channelName')) {
          continue;
        }
        final channel = _messagingService.supabase
          .channel(channelName)
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conv.id,
            ),
            callback: (payload) async {
              final messageData = payload.newRecord;
              if (messageData != null) {
                if (messageData['sender_id'] != userId) {
                  try {
                    final updatedConv = await _messagingService.getConversationById(conv.id);
                    if (updatedConv != null) {
                      setState(() {
                        final idx = _conversations.indexWhere((c) => c.id == conv.id);
                        if (idx != -1) {
                          // Only update if the conversation has messages, otherwise remove it
                          if (updatedConv.lastMessage != null) {
                            _conversations[idx] = updatedConv;
                          } else {
                            _conversations.removeAt(idx);
                          }
                        } else {
                          // Only add if the conversation has messages
                          if (updatedConv.lastMessage != null) {
                            _conversations.insert(0, updatedConv);
                          }
                        }
                        _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                      });
                      if (mounted) {
                        final unreadProvider = Provider.of<UnreadMessagesProvider>(context, listen: false);
                        unreadProvider.refreshUnreadCount();
                        BadgeManager.updateAppBadge(context);
                      }
                    }
                  } catch (e) {
                    print('[ConversationsScreen] Error updating conversation after realtime message: $e');
                  }
                }
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'conversation_id',
              value: conv.id,
            ),
            callback: (payload) async {
              final oldData = payload.oldRecord;
              final newData = payload.newRecord;
              if (oldData != null && newData != null && oldData['is_read'] != newData['is_read']) {
                try {
                  final updatedConv = await _messagingService.getConversationById(conv.id);
                  if (updatedConv != null) {
                    setState(() {
                      final idx = _conversations.indexWhere((c) => c.id == conv.id);
                      if (idx != -1) {
                        // Only update if the conversation has messages, otherwise remove it
                        if (updatedConv.lastMessage != null) {
                          _conversations[idx] = updatedConv;
                        } else {
                          _conversations.removeAt(idx);
                        }
                      } else {
                        // Only add if the conversation has messages
                        if (updatedConv.lastMessage != null) {
                          _conversations.insert(0, updatedConv);
                        }
                      }
                      _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                    });
                    
                    // Fetch event data if the conversation has an event and it's not in cache
                    if (updatedConv.eventId != null && !_eventCache.containsKey(updatedConv.eventId)) {
                      try {
                        final event = await SupabaseDatabase.instance.getEvent(updatedConv.eventId!);
                        if (mounted) {
                          setState(() {
                            _eventCache[updatedConv.eventId!] = event;
                          });
                        }
                      } catch (e) {
                        print('[ConversationsScreen] Error fetching event for conversation after read status update: $e');
                      }
                    }
                    
                    if (mounted) {
                      final unreadProvider = Provider.of<UnreadMessagesProvider>(context, listen: false);
                      unreadProvider.refreshUnreadCount();
                      BadgeManager.updateAppBadge(context);
                    }
                  }
                } catch (e) {
                  print('[ConversationsScreen] Error updating conversation after is_read update: $e');
                }
              }
            },
          )
          .subscribe();
      }
    } catch (e) {
      print('[ConversationsScreen] Error setting up realtime subscriptions: $e');
    }
  }

  // Subscribe to new conversations being created
  void _subscribeToNewConversations() {
    // Unsubscribe from existing channel if any
    _conversationsChannel?.unsubscribe();
    
    try {
      _conversationsChannel = _messagingService.subscribeToConversations((conversation) async {
        // This will be called when a conversation is created or updated
        if (mounted) {
          // Check if conversation already exists
          final existingIndex = _conversations.indexWhere((c) => c.id == conversation.id);
          
          if (existingIndex != -1) {
            // Update existing conversation
            setState(() {
              _conversations[existingIndex] = conversation;
              _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
            });
            
            // Fetch event data if the conversation has an event and it's not in cache
            if (conversation.eventId != null && !_eventCache.containsKey(conversation.eventId)) {
              try {
                final event = await SupabaseDatabase.instance.getEvent(conversation.eventId!);
                if (mounted) {
                  setState(() {
                    _eventCache[conversation.eventId!] = event;
                  });
                }
              } catch (e) {
                print('[ConversationsScreen] Error fetching event for updated conversation: $e');
              }
            }
          } else {
            // Add new conversation if it has messages
            if (conversation.lastMessage != null) {
              // Fetch event data for the new conversation if it has an event
              if (conversation.eventId != null) {
                try {
                  final event = await SupabaseDatabase.instance.getEvent(conversation.eventId!);
                  setState(() {
                    _conversations.insert(0, conversation);
                    _eventCache[conversation.eventId!] = event;
                    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  });
                } catch (e) {
                  print('[ConversationsScreen] Error fetching event for new conversation: $e');
                  setState(() {
                    _conversations.insert(0, conversation);
                    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  });
                }
              } else {
                setState(() {
                  _conversations.insert(0, conversation);
                  _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                });
              }
            } else {
              // For new conversations without messages, refresh the entire list
              // to ensure we get the latest state
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _loadConversations(showLoading: false);
              });
              return;
            }
          }
          
          // Refresh unread count and badge
          if (mounted) {
            final unreadProvider = Provider.of<UnreadMessagesProvider>(context, listen: false);
            unreadProvider.refreshUnreadCount();
            BadgeManager.updateAppBadge(context);
          }
        }
      });
      
      print('[ConversationsScreen] Subscribed to new conversations');
    } catch (e) {
      print('[ConversationsScreen] Error subscribing to new conversations: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conversationsChannel?.unsubscribe();
    for (final channel in _messagesChannels) {
      channel.unsubscribe();
    }
    _messagesChannels.clear();
    _searchController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void forceResubscribeRealtime() {
    _subscribeToMessagesInAllConversations();
    _subscribeToNewConversations(); // Also re-subscribe to new conversations
  }

  void _refreshData() {
    if (mounted) {
      _loadConversations(showLoading: false);
      forceResubscribeRealtime();
      final unreadProvider = Provider.of<UnreadMessagesProvider>(context, listen: false);
      unreadProvider.refreshUnreadCount();
      BadgeManager.updateAppBadge(context);
    }
  }

  Future<void> _loadConversations({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      final conversations = await _messagingService.getUserConversations();
      
      // Filter out conversations with no messages
      final conversationsWithMessages = conversations.where((conv) => conv.lastMessage != null).toList();
      
      // Fetch all events in parallel
      final eventIds = conversationsWithMessages
          .map((c) => c.eventId)
          .where((id) => id != null)
          .cast<int>()
          .toSet()
          .toList();
      final events = await Future.wait(eventIds.map((id) => SupabaseDatabase.instance.getEvent(id)));
      final eventCache = <int, Event?>{};
      for (var i = 0; i < eventIds.length; i++) {
        eventCache[eventIds[i]] = events[i];
      }

      if (mounted) {
        setState(() {
          _conversations = conversationsWithMessages;
          _eventCache = eventCache;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('ConversationsScreen: Error loading conversations: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading conversations: $e')),
        );
      }
    }
  }

  String _formatLastMessageTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }

  String _getLastMessagePreview(Message? lastMessage) {
    if (lastMessage == null) {
      return 'No messages yet';
    }
    
    final content = lastMessage.content;
    if (content.length > 50) {
      return '${content.substring(0, 50)}...';
    }
    return content;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Only show messages if user is authenticated
        if (!authProvider.isAuthenticated) {
          return Scaffold(
            backgroundColor: const Color(0xFF0065FF).withOpacity(0.05),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.message_outlined,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Sign in to Message',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Create an account or sign in to chat with friends, coordinate events, and stay connected with your community.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: () {
                        AuthFlowScreen.push(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0065FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        
        return Scaffold(
      key: ConversationsScreen.globalKey,
      appBar: AppBar(
        title: const Text('Messages'),
        centerTitle: true,
        toolbarHeight: 48,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 6, bottom: 6),
            child: Material(
              color: Colors.transparent,
              elevation: 2,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NewMessageScreen(),
                    ),
                  ).then((_) {
                    _loadConversations(showLoading: false);
                    _subscribeToMessagesInAllConversations();
                    _subscribeToNewConversations(); // Re-subscribe to new conversations
                  });
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0065FF),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x220065FF),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.edit_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Material(
                        elevation: 0.5,
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search messages...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: Colors.grey.shade600),
                                    onPressed: () {
                                      _searchController.clear();
                                    },
                                  )
                                : null,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(20)),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(20)),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(20)),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _loadConversations,
                        child: ListView.builder(
                          itemCount: _filteredConversations().length,
                          itemBuilder: (context, index) {
                            final conversation = _filteredConversations()[index];
                            final event = conversation.eventId != null ? _eventCache[conversation.eventId] : null;
                            return _buildConversationTile(conversation, event);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.message_outlined,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start a conversation with your friends!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationTile(Conversation conversation, Event? event) {
    final currentUser = MessagingService.instance.supabase.auth.currentUser;
    if (currentUser == null) {
      print('[ConversationsScreen] No authenticated user in _buildConversationTile');
      return const SizedBox.shrink();
    }
    
    final currentUserId = currentUser.id;
    final isGroupConversation = conversation.isGroupConversation();
    final displayName = isGroupConversation 
        ? conversation.getGroupDisplayName(currentUserId)
        : conversation.getOtherParticipantName(currentUserId);
    final displayUsername = isGroupConversation 
        ? '' 
        : conversation.getOtherParticipantUsername(currentUserId);
    final lastMessage = conversation.lastMessage;
    final isFromCurrentUser = lastMessage?.senderId == currentUserId;
    final bool isUnread = lastMessage?.isRead == false && !isFromCurrentUser;

    // Compute image URL for conversations linked to an event (prefer cropped image, support relative URLs)
    final String? eventImageUrl = (event != null) ? _getBestEventImageUrl(event) : null;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      splashColor: Colors.transparent,
      highlightColor: Colors.grey.withOpacity(0.1),
      onTap: () {
        _hasNavigatedToChat = true;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversation.id,
              otherParticipantName: displayName,
            ),
          ),
        ).then((_) {
          _refreshData();
          _hasNavigatedToChat = false;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (eventImageUrl != null)
              ClipOval(
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: CachedNetworkImage(
                    imageUrl: eventImageUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: Colors.grey[200],
                      child: const Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => CircleAvatar(
                      backgroundColor: isGroupConversation
                          ? Colors.orange
                          : Theme.of(context).colorScheme.primary,
                      radius: 20,
                      child: isGroupConversation
                          ? const Icon(Icons.group, color: Colors.white, size: 20)
                          : Text(
                              _getAvatarInitials(displayName, displayUsername),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                  ),
                ),
              )
            else
              CircleAvatar(
                backgroundColor: isGroupConversation 
                    ? Colors.orange 
                    : Theme.of(context).colorScheme.primary,
                radius: 20,
                child: isGroupConversation
                    ? const Icon(
                        Icons.group,
                        color: Colors.white,
                        size: 20,
                      )
                    : Text(
                        _getAvatarInitials(displayName, displayUsername),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          event != null
                              ? event.title
                              : (isGroupConversation
                                  ? displayName
                                  : (displayUsername.isNotEmpty
                                      ? '$displayName (@$displayUsername)'
                                      : displayName)),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isUnread ? FontWeight.w700 : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 0.5),
                  _buildMessagePreviewWithTimestamp(
                    isFromCurrentUser
                        ? 'You: ${_getLastMessagePreview(lastMessage)}'
                        : _getLastMessagePreview(lastMessage),
                    lastMessage != null ? _formatLastMessageTime(lastMessage.createdAt) : null,
                    isUnread,
                  ),
                ],
              ),
            ),
            if (isUnread)
              Container(
                width: 12,
                height: 12,
                decoration: const BoxDecoration(
                  color: Color(0xFF0065FF),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: _buildUnreadCount(conversation),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Conversation> _filteredConversations() {
    if (_searchQuery.isEmpty) return _conversations;
    
    final currentUser = MessagingService.instance.supabase.auth.currentUser;
    if (currentUser == null) {
      print('[ConversationsScreen] No authenticated user in _filteredConversations');
      return _conversations;
    }
    
    final currentUserId = currentUser.id;
    return _conversations.where((c) {
      final name = c.getOtherParticipantName(currentUserId).toLowerCase();
      final username = c.getOtherParticipantUsername(currentUserId).toLowerCase();
      return name.contains(_searchQuery) || username.contains(_searchQuery);
    }).toList();
  }

  // Prefer cropped image URL if present; support relative URLs
  String? _getBestEventImageUrl(Event event) {
    if (event.coverPhoto == null || event.coverPhoto!.isEmpty) {
      return null;
    }

    // Try cropped image URL from coverPhotoCrop
    if (event.coverPhotoCrop != null && event.coverPhotoCrop!.isNotEmpty) {
      try {
        final cropData = Map<String, dynamic>.from(
          event.coverPhotoCrop!.startsWith('{') ? jsonDecode(event.coverPhotoCrop!) : {},
        );
        final croppedUrl = cropData['croppedImageUrl']?.toString();
        if (croppedUrl != null && croppedUrl.isNotEmpty) {
          if (croppedUrl.startsWith('http') || croppedUrl.startsWith('data:image')) {
            return croppedUrl;
          }
        }
      } catch (_) {}
    }

    // Fallback to original cover photo; handle relative path
    if (event.coverPhoto!.startsWith('http')) {
      return event.coverPhoto!;
    }
    return '$_adminBaseUrl${event.coverPhoto}';
  }

  String _getAvatarInitials(String name, String username) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    } else if (name.isNotEmpty) {
      return name[0].toUpperCase();
    } else if (username.isNotEmpty) {
      return username[0].toUpperCase();
    } else {
      return '?';
    }
  }

  Widget _buildMessagePreviewWithTimestamp(String preview, String? timestamp, bool isUnread) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isUnread ? Colors.black87 : Colors.grey[600],
              fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
        if (timestamp != null) ...[
          const SizedBox(width: 6),
          Text(
            '•',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            timestamp,
            style: TextStyle(
              fontSize: 13,
              color: isUnread ? Colors.black87 : Colors.grey[600],
              fontWeight: isUnread ? FontWeight.w500 : FontWeight.normal,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUnreadCount(Conversation conversation) {
    // If you have a field for unread count, use it. Otherwise, just show a blue dot.
    // Example: if (conversation.unreadCount != null && conversation.unreadCount > 0)
    // For now, just show a blue dot (empty Container for spacing)
    // Replace with count logic if available.
    return Container();
    // Example for count:
    // return Text(
    //   conversation.unreadCount > 0 ? conversation.unreadCount.toString() : '',
    //   style: const TextStyle(
    //     color: Colors.white,
    //     fontSize: 12,
    //     fontWeight: FontWeight.bold,
    //   ),
    // );
  }

  Future<Event?> _getEvent(int? eventId) async {
    if (eventId == null) return null;
    if (_eventCache.containsKey(eventId)) return _eventCache[eventId];
    final event = await SupabaseDatabase.instance.getEvent(eventId);
    setState(() {
      _eventCache[eventId] = event;
    });
    return event;
  }
} 