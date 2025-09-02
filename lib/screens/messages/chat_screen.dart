import 'package:flutter/material.dart';
import 'package:myarea_app/models/message_model.dart';
import 'package:myarea_app/models/conversation_model.dart';
import 'package:myarea_app/services/messaging_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:provider/provider.dart';
import '../../main.dart';
import 'conversations_screen.dart';
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/models/event_model.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String? otherParticipantName;

  static bool isActive = false;
  static String? activeConversationId;

  const ChatScreen({
    Key? key,
    required this.conversationId,
    this.otherParticipantName,
  }) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final MessagingService _messagingService = MessagingService.instance;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  RealtimeChannel? _messagesChannel;
  String? _currentUserId;
  String? _participantName;
  String? _participantUsername;
  bool _showTimestamps = false; // Track if timestamps should be shown
  double _timestampReveal = 0.0;
  AnimationController? _revealController;
  Animation<double>? _revealAnimation;
  
  // Group conversation support
  Conversation? _conversation;
  bool _isGroupConversation = false;

  Event? _event;

  @override
  void initState() {
    super.initState();
    ChatScreen.isActive = true;
    ChatScreen.activeConversationId = widget.conversationId;
    _currentUserId = Supabase.instance.client.auth.currentUser!.id;
    _loadMessages();
    _subscribeToMessages();
    _loadConversationDetails();
    _revealController = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Always re-subscribe to ensure we have the latest subscription
    _subscribeToMessages();
  }

  @override
  void dispose() {
    ChatScreen.isActive = false;
    ChatScreen.activeConversationId = null;
    _messageController.dispose();
    _scrollController.dispose();
    _messagesChannel?.unsubscribe();
    _revealController?.dispose();
    super.dispose();
  }

  Future<void> _loadConversationDetails() async {
    try {
      final conversation = await _messagingService.getConversationById(widget.conversationId);
      if (mounted && conversation != null) {
        setState(() {
          _conversation = conversation;
          _isGroupConversation = conversation.isGroupConversation();
          
          if (_isGroupConversation) {
            _participantName = conversation.getGroupDisplayName(_currentUserId!);
            _participantUsername = ''; // Group conversations don't have a single username
          } else {
            _participantName = conversation.getOtherParticipantName(_currentUserId!);
            _participantUsername = conversation.getOtherParticipantUsername(_currentUserId!);
          }
        });
        // Fetch event if linked
        if (conversation.eventId != null) {
          final event = await SupabaseDatabase.instance.getEvent(conversation.eventId!);
          if (mounted) {
            setState(() {
              _event = event;
            });
          }
        }
      }
    } catch (e) {
      print('Error loading conversation details: $e');
    }
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      print('ChatScreen: Loading messages for conversation: ${widget.conversationId}');
      final messages = await _messagingService.getConversationMessages(widget.conversationId);
      print('ChatScreen: Loaded ${messages.length} messages');
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
      // Mark as read after loading messages
      if (mounted) {
        _markMessagesAsRead();
      }
    } catch (e) {
      print('ChatScreen: Error loading messages: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading messages: $e')),
        );
      }
    }
  }

  // Refresh messages manually (useful for debugging)
  Future<void> _refreshMessages() async {
    print('ChatScreen: Manually refreshing messages for conversation: ${widget.conversationId}');
    await _loadMessages();
  }

  void _subscribeToMessages() {
    // Unsubscribe from previous channel if exists
    _messagesChannel?.unsubscribe();
    
    print('ChatScreen: Subscribing to messages for conversation: ${widget.conversationId}');
    _messagesChannel = _messagingService.subscribeToMessages(
      widget.conversationId,
      (message) {
        print('ChatScreen: Received new message: ${message.content}');
        setState(() {
          _messages.add(message);
        });
        
        // Scroll to bottom for new messages
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
        
        // Mark messages as read if they're from the other person
        if (message.senderId != _currentUserId) {
          _markMessagesAsRead();
        }
      },
    );
    
    // Add a small delay to ensure subscription is active
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        print('ChatScreen: Real-time subscription should now be active for conversation: ${widget.conversationId}');
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    try {
      print('ChatScreen: Marking messages as read for conversation: ${widget.conversationId}');
      final success = await _messagingService.markMessagesAsRead(widget.conversationId);
      
      if (success) {
        print('ChatScreen: Successfully marked messages as read');
        // After marking as read, update the badge count
        final unreadCount = await _messagingService.getUnreadConversationsCount();
        print('ChatScreen: Updated unread count: $unreadCount');
        
        // Update the provider for the nav badge
        if (mounted) {
          context.read<UnreadMessagesProvider>().setUnreadCount(unreadCount);
          // Update app badge with combined count
          BadgeManager.updateAppBadge(context);
          
          // Also refresh the conversations screen if it's available
          if (ConversationsScreen.globalKey.currentState != null) {
            print('ChatScreen: Refreshing ConversationsScreen after marking as read');
            ConversationsScreen.globalKey.currentState!.refreshData();
          }
        }
      } else {
        print('ChatScreen: Failed to mark messages as read');
      }
    } catch (e) {
      print('Error marking messages as read: $e');
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() {
      _isSending = true;
    });

    try {
      print('ChatScreen: Sending message: "$content" to conversation: ${widget.conversationId}');
      final message = await _messagingService.sendMessage(
        widget.conversationId,
        content,
      );
      
      if (message != null) {
        print('ChatScreen: Message sent successfully: ${message.id}');
        _messageController.clear();
        
        // Add the message to the local list immediately for better UX
        setState(() {
          _messages.add(message);
        });
        
        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottom();
        });
      } else {
        print('ChatScreen: Failed to send message - returned null');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to send message. Please try again.')),
          );
        }
      }
    } catch (e) {
      print('ChatScreen: Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending message: $e')),
        );
      }
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  String _formatMessageTime(DateTime dateTime) {
    return DateFormat('HH:mm').format(dateTime);
  }

  bool _shouldShowDate(int index) {
    if (index == 0) return true;
    
    final currentMessage = _messages[index];
    final previousMessage = _messages[index - 1];
    
    final currentDate = DateTime(
      currentMessage.createdAt.year,
      currentMessage.createdAt.month,
      currentMessage.createdAt.day,
    );
    final previousDate = DateTime(
      previousMessage.createdAt.year,
      previousMessage.createdAt.month,
      previousMessage.createdAt.day,
    );
    
    return currentDate.isAfter(previousDate);
  }

  String _formatDate(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM d, y').format(dateTime);
    }
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

  void _showGroupInfo() {
    if (_conversation == null) return;
    
    final participantNames = _conversation!.getAllParticipantNames(_currentUserId!);
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.group, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _participantName ?? 'Group Chat',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${_conversation!.participantIds.length} participants',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text(
              'Participants',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            ...participantNames.map((name) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.grey[200],
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    name,
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            if (_isGroupConversation && _event != null && _event!.coverPhoto != null && _event!.coverPhoto!.isNotEmpty)
              CircleAvatar(
                backgroundImage: NetworkImage(_event!.coverPhoto!),
                radius: 20,
                backgroundColor: Colors.grey[200],
              )
            else
              CircleAvatar(
                backgroundColor: _isGroupConversation 
                    ? Colors.orange 
                    : Theme.of(context).colorScheme.primary,
                child: Icon(
                  _isGroupConversation ? Icons.group : Icons.person,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _participantName ?? 'Loading...',
                    style: const TextStyle(fontSize: 18),
                  ),
                  if (_isGroupConversation && _conversation != null)
                    Text(
                      '${_conversation!.participantIds.length} participants',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  if (_event != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _event!.title,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.deepPurple,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  if (!_isGroupConversation && _participantUsername != null && _participantUsername!.isNotEmpty)
                    Text(
                      '@$_participantUsername',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_isGroupConversation)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                _showGroupInfo();
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _timestampReveal = (_timestampReveal - details.delta.dx).clamp(0.0, 100.0);
                });
              },
              onHorizontalDragEnd: (details) {
                _revealController?.reset();
                _revealAnimation = Tween<double>(begin: _timestampReveal, end: 0.0)
                  .animate(CurvedAnimation(parent: _revealController!, curve: Curves.easeOut));
                _revealController?.addListener(() {
                  setState(() {
                    _timestampReveal = _revealAnimation!.value;
                  });
                });
                _revealController?.forward();
              },
              child: Stack(
                children: [
                  // Main messages list
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                          ? _buildEmptyState()
                          : RefreshIndicator(
                              onRefresh: _refreshMessages,
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: EdgeInsets.only(
                                  left: 16,
                                  right: 16 + _timestampReveal,
                                  top: 16,
                                  bottom: 16,
                                ),
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  final isFromCurrentUser = message.senderId == _currentUserId;
                                  return Column(
                                    children: [
                                      if (_shouldShowDate(index))
                                        _buildDateDivider(message.createdAt),
                                      _buildMessageBubble(message, isFromCurrentUser, index),
                                    ],
                                  );
                                },
                              ),
                            ),
                  // Timestamp column (revealed by swipe)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: _timestampReveal == 0,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 350),
                        width: _timestampReveal,
                        color: Colors.transparent,
                        child: Column(
                          children: List.generate(_messages.length, (index) {
                            return Container(
                              alignment: Alignment.center,
                              height: 44, // Should match message bubble height
                              child: Opacity(
                                opacity: _timestampReveal / 100.0,
                                child: Text(
                                  _formatMessageTime(_messages[index].createdAt),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            bottom: true,
            top: false,
            left: false,
            right: false,
            child: _buildMessageInput(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDivider(DateTime dateTime) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey[300])),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _formatDate(dateTime),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey[300])),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isFromCurrentUser, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      height: 44, // Fixed height for alignment with timestamp
      child: Row(
        mainAxisAlignment: isFromCurrentUser 
            ? MainAxisAlignment.end 
            : MainAxisAlignment.start,
        children: [
          if (!isFromCurrentUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                _getAvatarInitials(widget.otherParticipantName ?? '', _participantUsername ?? ''),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isFromCurrentUser ? Theme.of(context).colorScheme.primary : Colors.grey[200],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              message.content,
              style: TextStyle(
                color: isFromCurrentUser ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25)),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Color(0xFFF5F5F5),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
} 