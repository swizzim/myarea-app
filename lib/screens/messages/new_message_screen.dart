import 'package:flutter/material.dart';
import 'package:myarea_app/models/user_model.dart';
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/services/messaging_service.dart';
import 'package:myarea_app/screens/messages/chat_screen.dart';

class NewMessageScreen extends StatefulWidget {
  const NewMessageScreen({super.key});

  static bool isActive = false;

  @override
  State<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends State<NewMessageScreen> {
  final SupabaseDatabase _database = SupabaseDatabase.instance;
  final MessagingService _messagingService = MessagingService.instance;
  final TextEditingController _searchController = TextEditingController();
  
  List<User> _friends = [];
  List<User> _filteredFriends = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    NewMessageScreen.isActive = true;
    _loadFriends();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    NewMessageScreen.isActive = false;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userId = _messagingService.supabase.auth.currentUser!.id;
      final friends = await _database.getFriendsList(userId);
      setState(() {
        _friends = friends;
        _filteredFriends = friends;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading friends: $e')),
        );
      }
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredFriends = _friends;
      } else {
        _filteredFriends = _friends.where((friend) {
          final name = '${friend.firstName ?? ''} ${friend.lastName ?? ''}'.toLowerCase();
          final username = friend.username.toLowerCase();
          return name.contains(query) || username.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _startConversation(User friend) async {
    try {
      final userId = _messagingService.supabase.auth.currentUser!.id;
      
      print('NewMessageScreen: Starting conversation between $userId and ${friend.id}');
      
      // Check if conversation already exists
      final existingConversationId = await _messagingService.findExistingOneOnOneConversation(
        userId,
        friend.id!,
      );
      
      print('NewMessageScreen: Existing conversation ID: $existingConversationId');
      
      final conversationId = existingConversationId ?? await _messagingService.getOrCreateConversation(
        userId,
        friend.id!,
      );
      
      print('NewMessageScreen: Final conversation ID: $conversationId');
      
      if (mounted) {
        // Show message if opening existing conversation
        if (existingConversationId != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Opening existing conversation'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              conversationId: conversationId,
              otherParticipantName: friend.firstName != null && friend.lastName != null
                  ? '${friend.firstName} ${friend.lastName}'
                  : friend.username,
            ),
          ),
        );
      }
    } catch (e) {
      print('NewMessageScreen: Error starting conversation: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting conversation: $e')),
        );
      }
    }
  }

  String _getDisplayName(User user) {
    if (user.firstName != null && user.lastName != null) {
      return '${user.firstName} ${user.lastName}';
    }
    return user.username;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Message'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search friends...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredFriends.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: _filteredFriends.length,
                        itemBuilder: (context, index) {
                          final friend = _filteredFriends[index];
                          return _buildFriendTile(friend);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_searchQuery.isNotEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No friends found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    } else {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              'No friends yet',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Add some friends to start messaging!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildFriendTile(User friend) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Text(
          _getDisplayName(friend)[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        _getDisplayName(friend),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('@${friend.username}'),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => _startConversation(friend),
    );
  }
} 