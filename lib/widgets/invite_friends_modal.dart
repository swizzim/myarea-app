import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myarea_app/models/event_model.dart';
import 'package:myarea_app/models/event_response_model.dart';
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/services/messaging_service.dart';
import 'package:myarea_app/screens/messages/chat_screen.dart';
import 'package:myarea_app/main.dart';

class InviteFriendsModal extends StatefulWidget {
  final Event event;
  // Optional preloaded data to avoid loading state shift
  final List<dynamic>? preloadedAllFriends;
  final Map<EventResponseType, List<dynamic>>? preloadedFriendsByResponse;
  final List<dynamic>? preloadedFriendsNoResponse;
  
  const InviteFriendsModal({
    super.key,
    required this.event,
    this.preloadedAllFriends,
    this.preloadedFriendsByResponse,
    this.preloadedFriendsNoResponse,
  });

  @override
  State<InviteFriendsModal> createState() => _InviteFriendsModalState();
}

class _InviteFriendsModalState extends State<InviteFriendsModal> {
  final Color vibrantBlue = const Color(0xFF0065FF);
  
  // Chat data - loaded once when modal opens
  List<dynamic> _allFriends = [];
  Map<String, bool> _selectedFriends = {};
  bool _isChatLoading = true;
  bool _isCreatingChat = false;
  Map<EventResponseType, List<dynamic>> _friendsByResponseType = {
    EventResponseType.interested: [],
  };
  List<dynamic> _friendsNoResponse = [];

  @override
  void initState() {
    super.initState();
    
    // If preloaded data provided, use it and skip loading
    if (widget.preloadedAllFriends != null &&
        widget.preloadedFriendsByResponse != null &&
        widget.preloadedFriendsNoResponse != null) {
      _allFriends = widget.preloadedAllFriends!;
      _friendsByResponseType = widget.preloadedFriendsByResponse!;
      _friendsNoResponse = widget.preloadedFriendsNoResponse!;
      // Initialize selection map
      for (final friend in _allFriends) {
        _selectedFriends[friend.id!] = false;
      }
      _isChatLoading = false;
      setState(() {});
    } else {
      // Load chat data once when modal opens
      _loadChatData();
    }
  }
  
  Future<void> _loadChatData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final database = SupabaseDatabase.instance;
      
      // Load all friends
      final friends = await database.getFriendsList(userId);
      
      // Load friends by response type
      final friendsByResponse = await database.getEventFriendsByResponseType(widget.event.id);
      
      // Get friends with no response
      final respondedFriendIds = <String>{};
      for (final friendsList in friendsByResponse.values) {
        for (final friend in friendsList) {
          respondedFriendIds.add(friend.id!);
        }
      }
      
      final noResponseFriends = friends.where((f) => !respondedFriendIds.contains(f.id!)).toList();
      
      if (mounted) {
        setState(() {
          _allFriends = friends;
          _friendsByResponseType = friendsByResponse;
          _friendsNoResponse = noResponseFriends;
          _isChatLoading = false;
          
          // Initialize selection map
          for (final friend in friends) {
            _selectedFriends[friend.id!] = false;
          }
        });
      }
    } catch (e) {
      print('Error loading chat data: $e');
      if (mounted) {
        setState(() => _isChatLoading = false);
      }
    }
  }
  
  Future<void> _createGroupChat() async {
    final selectedFriendIds = _selectedFriends.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    
    if (selectedFriendIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one friend')),
      );
      return;
    }
    
    setState(() => _isCreatingChat = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;
      final allParticipantIds = [userId, ...selectedFriendIds];
      
      final messagingService = MessagingService.instance;
      
      // Check if conversation already exists for this event
      String? existingConversationId = await messagingService.findExistingGroupConversation(
        allParticipantIds,
        eventId: widget.event.id,
      );

      // If not found by event, try to find by exact participants; if found and no event linked, attach the event
      if (existingConversationId == null) {
        final existingByParticipants = await messagingService.findConversationByExactParticipants(allParticipantIds);
        if (existingByParticipants != null && existingByParticipants.eventId == null) {
          final attached = await messagingService.attachEventToConversation(existingByParticipants.id, widget.event.id);
          if (attached) {
            existingConversationId = existingByParticipants.id;
          }
        }
      }
      
      final conversationId = existingConversationId ?? await messagingService.createGroupConversation(
        allParticipantIds,
        eventId: widget.event.id,
      );
      
      if (mounted) {
        Navigator.pop(context);

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherParticipantName: 'Event Chat',
            ),
          ),
        );
      }
    } catch (e) {
      print('Error creating group chat: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating chat: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreatingChat = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom - 4, // Negative padding to go below safe area
        left: MediaQuery.of(context).viewInsets.left,
        right: MediaQuery.of(context).viewInsets.right,
        top: MediaQuery.of(context).viewInsets.top,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const Text(
              'Start a Chat',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            
            const SizedBox(height: 16),
            
            // Chat Content - Dynamic sizing based on content
            _buildEventChatTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildEventChatTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          Text(
            'Create an individual or group chat for this event',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          
          // Friends list - Dynamic sizing based on content
          Builder(
            builder: (context) {
              if (_isChatLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (_allFriends.isEmpty) {
                return _buildEmptyState();
              }

              final going = _friendsByResponseType[EventResponseType.interested] ?? [];
              final interestedIds = going.map((f) => f.id as String?).whereType<String>().toSet();

              // Build sorted list: interested first, then others; alphabetical within each group
              final List<dynamic> sorted = List<dynamic>.from(_allFriends);
              int compareByName(a, b) {
                final nameA = _getDisplayName(a).toLowerCase();
                final nameB = _getDisplayName(b).toLowerCase();
                return nameA.compareTo(nameB);
              }
              sorted.sort((a, b) {
                final ai = interestedIds.contains(a.id);
                final bi = interestedIds.contains(b.id);
                if (ai != bi) return bi ? 1 : -1; // interested first
                return compareByName(a, b);
              });

              final tiles = sorted
                  .map((friend) => _buildFriendTile(
                        friend,
                        isInterested: interestedIds.contains(friend.id),
                      ))
                  .toList();

              // If few friends, render content directly. If many, cap height and make scrollable.
              if (tiles.length <= 3) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: tiles,
                );
              }

              // For many friends, cap height and make scrollable
              final maxListHeight = MediaQuery.of(context).size.height * 0.4; // Reduced from 0.5
              return SizedBox(
                height: maxListHeight,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: tiles,
                  ),
                ),
              );
            },
          ),
          
          // Button section at the bottom
          Builder(
            builder: (context) {
              final selectedCount = _selectedFriends.values.where((selected) => selected).length;
              return Column(
                children: [
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (selectedCount > 0 && !_isCreatingChat) ? _createGroupChat : null,
                      icon: _isCreatingChat
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Icon(
                              selectedCount > 0 ? Icons.chat_bubble : Icons.chat_bubble_outline,
                              color: selectedCount > 0 ? Colors.white : Colors.grey[400],
                            ),
                      label: _isCreatingChat
                          ? const Text('Starting Chat...')
                          : Text(selectedCount > 1 ? 'Start Group Chat' : 'Start Chat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: vibrantBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        splashFactory: NoSplash.splashFactory,
                        animationDuration: Duration.zero, // Disable button animations
                      ),
                    ),
                  ),
                  // Selected count text below button with fixed height to prevent layout shift
                  SizedBox(
                    height: 28, // Increased height to accommodate text with descenders
                    child: AnimatedSwitcher(
                      duration: Duration.zero, // No animation
                      child: selectedCount > 0
                          ? Padding(
                              key: ValueKey(selectedCount),
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                '$selectedCount friend${selectedCount == 1 ? '' : 's'} selected',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(key: ValueKey('empty')),
                    ),
                  ),
                ],
              );
            },
          ),
          
          const SizedBox(height: 16),
          
          // Sharing removed; modal focuses solely on creating chats
        ],
      ),
    );
  }

  // Deprecated header section removed with new design (no headers)

  Widget _buildFriendTile(dynamic friend, {bool isInterested = false}) {
    final displayName = _getDisplayName(friend);
    final isSelected = _selectedFriends[friend.id!] ?? false;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFriends[friend.id!] = !isSelected;
        });
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0.5,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isSelected 
            ? BorderSide(color: vibrantBlue, width: 2)
            : BorderSide.none,
        ),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: vibrantBlue,
                    radius: 20,
                    child: Text(
                      displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isInterested)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Icon(
                        Icons.favorite,
                        size: 16,
                        color: Colors.red.shade400,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '@${friend.username}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    _selectedFriends[friend.id!] = value ?? false;
                  });
                },
                activeColor: vibrantBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDisplayName(dynamic friend) {
    if (friend.firstName != null && friend.lastName != null) {
      return '${friend.firstName} ${friend.lastName}';
    }
    return friend.username;
  }

  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No friends available',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add some friends to create a group chat',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Navigator.pop(context); // Close the modal
                // Navigate to friends tab in main nav
                MainScreen.navigateToScreen(context, 'friends'); // Navigate to Friends screen
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Find Friends',
                    style: TextStyle(
                      fontSize: 14,
                      color: vibrantBlue,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: vibrantBlue,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
