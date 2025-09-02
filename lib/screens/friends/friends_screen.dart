import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/models/friend_request_model.dart';
import 'package:myarea_app/models/user_model.dart' as app;
import 'package:myarea_app/services/messaging_service.dart';
import 'package:myarea_app/screens/messages/chat_screen.dart';
import 'package:myarea_app/screens/auth/auth_flow_screen.dart';
import 'dart:async';

class FriendsScreen extends StatefulWidget {
  static final GlobalKey<_FriendsScreenState> globalKey = GlobalKey<_FriendsScreenState>();
  
  // Static flag to handle notification navigation
  static bool shouldNavigateToAddFriends = false;
  
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();

  // Static method to trigger navigation from anywhere
  static void triggerAddFriendsNavigation() {
    print('🔔 FriendsScreen: Static trigger called');
    shouldNavigateToAddFriends = true;
    print('🔔 FriendsScreen: Flag set to true');
    print('🔔 FriendsScreen: globalKey.currentState is ${globalKey.currentState != null ? 'not null' : 'null'}');
    if (globalKey.currentState != null) {
      print('🔔 FriendsScreen: Calling navigateToAddFriendsTab on current state');
      globalKey.currentState!.navigateToAddFriendsTab();
    } else {
      print('🔔 FriendsScreen: globalKey.currentState is null, cannot navigate');
      // Retry after a short delay
      Future.delayed(const Duration(milliseconds: 200), () {
        if (globalKey.currentState != null) {
          print('🔔 FriendsScreen: Retry navigation after delay');
          globalKey.currentState!.navigateToAddFriendsTab();
        }
      });
    }
  }
}

class _FriendsScreenState extends State<FriendsScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<app.User> _searchResults = [];
  bool _isSearching = false;
  int _previousTabIndex = 0; // Track previous tab index for slide detection
  
  // Vibrant blue color
  final Color vibrantBlue = const Color(0xFF0065FF);
  // Removed local real-time listeners since we now have global listeners in AuthProvider

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Add listener to close keyboard when switching from Add Friends to My Friends tab
    _tabController.addListener(() {
      // Check if user slid from Add Friends tab (index 1) to My Friends tab (index 0)
      if (_tabController.index == 0 && _previousTabIndex == 1) {
        // User slid from Add Friends to My Friends tab
        // Close keyboard if it's open
        FocusScope.of(context).unfocus();
      }
      // Update previous index for next comparison
      _previousTabIndex = _tabController.index;
    });
    
    // Load friend data when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated) {
        authProvider.refreshFriendData();
        // Removed local listener setup since we now have global listeners
      }
      
      // Simple approach: if flag is set, navigate to Add Friends tab
      if (FriendsScreen.shouldNavigateToAddFriends) {
        print('🔔 FriendsScreen: Flag detected in initState, navigating to Add Friends tab');
        FriendsScreen.shouldNavigateToAddFriends = false;
        _navigateToAddFriendsTab();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Simple approach: if flag is set, navigate to Add Friends tab
    if (FriendsScreen.shouldNavigateToAddFriends) {
      print('🔔 FriendsScreen: Flag detected in didChangeDependencies, navigating to Add Friends tab');
      FriendsScreen.shouldNavigateToAddFriends = false;
      _navigateToAddFriendsTab();
    }
  }

  // Handle notification navigation - can be called from initState or externally
  void handleNotificationNavigation(AuthProvider authProvider) {
    if (FriendsScreen.shouldNavigateToAddFriends) {
      print('🔔 FriendsScreen: Processing notification navigation flag');
      FriendsScreen.shouldNavigateToAddFriends = false;
      
      // Use a more robust approach to ensure TabController is ready
      _navigateToAddFriendsTab();
      
      // Refresh friend data after navigation
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          authProvider.refreshFriendData();
          print('🔔 FriendsScreen: Refreshed friend data');
        }
      });
    }
  }

  // Simple method to navigate to Add Friends tab
  void _navigateToAddFriendsTab() {
    print('🔔 FriendsScreen: Attempting to navigate to Add Friends tab');
    print('🔔 FriendsScreen: TabController length: ${_tabController.length}');
    print('🔔 FriendsScreen: TabController index: ${_tabController.index}');
    
    if (_tabController.length > 1) {
      _tabController.animateTo(1); // Navigate to "Add Friends" tab
      print('🔔 FriendsScreen: Successfully navigated to Add Friends tab');
      // Clear the flag after successful navigation
      FriendsScreen.shouldNavigateToAddFriends = false;
    } else {
      print('🔔 FriendsScreen: TabController not ready, will try again in 100ms');
      // Multiple retry attempts
      _retryNavigation(attempts: 3);
    }
  }

  // Helper method for retrying navigation
  void _retryNavigation({int attempts = 3}) {
    if (attempts <= 0) {
      print('🔔 FriendsScreen: Failed to navigate to Add Friends tab after all retries');
      FriendsScreen.shouldNavigateToAddFriends = false;
      return;
    }
    
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _tabController.length > 1) {
        _tabController.animateTo(1);
        print('🔔 FriendsScreen: Navigated to Add Friends tab (retry ${4 - attempts})');
        FriendsScreen.shouldNavigateToAddFriends = false;
      } else {
        print('🔔 FriendsScreen: TabController still not ready, retrying... (${attempts - 1} attempts left)');
        _retryNavigation(attempts: attempts - 1);
      }
    });
  }

  // Public method to navigate to Add Friends tab
  void navigateToAddFriendsTab() {
    print('🔔 FriendsScreen: Public navigation method called');
    print('🔔 FriendsScreen: TabController length: ${_tabController.length}');
    print('🔔 FriendsScreen: TabController index: ${_tabController.index}');
    _navigateToAddFriendsTab();
    // Add a short delay before refreshing friend data
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        print('🔔 FriendsScreen: Triggering delayed refreshFriendData');
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.refreshFriendData();
      }
    });
  }

  // Removed local real-time listener setup methods since we now have global listeners in AuthProvider

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    // Removed local channel cleanup since we now have global listeners
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check for notification flag in build method
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (FriendsScreen.shouldNavigateToAddFriends) {
        print('🔔 FriendsScreen: Flag detected in build method, navigating to Add Friends tab');
        FriendsScreen.shouldNavigateToAddFriends = false;
        _navigateToAddFriendsTab();
      }
    });

    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Only show friends if user is authenticated
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
                      Icons.people_outline,
                      size: 80,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Sign in to Connect',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Create an account or sign in to connect with friends, share events, and stay updated on local activities.',
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
        
        return _buildAuthenticatedView(context, authProvider);
      },
    );
  }

  // View when user is logged in
  Widget _buildAuthenticatedView(BuildContext context, AuthProvider authProvider) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: TabBar(
          controller: _tabController,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(
              color: vibrantBlue,
              width: 3.5,
            ),
            insets: EdgeInsets.symmetric(horizontal: -6),
          ),
          indicatorSize: TabBarIndicatorSize.label,
          labelColor: vibrantBlue,
          unselectedLabelColor: Colors.grey.shade600,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
          unselectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
          overlayColor: MaterialStateProperty.all(Colors.transparent),
          tabs: [
            const Tab(text: 'My Friends'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Add Friends'),
                  Builder(
                    builder: (context) {
                      final authProvider = Provider.of<AuthProvider>(context, listen: false);
                      final count = authProvider.pendingFriendRequests.length;
                      if (count == 0) return SizedBox.shrink();
                      return Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: vibrantBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: true,
        toolbarHeight: 48,
      ),
      backgroundColor: const Color(0xFF0065FF).withOpacity(0.05),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(context, authProvider),
          _buildFindFriendsTab(context, authProvider),
        ],
      ),
    );
  }

  // Friends tab: just show friends
  Widget _buildFriendsTab(BuildContext context, AuthProvider authProvider) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          const Text(
            'Your Friends',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: authProvider.friendsList.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5 - 100, // 100 for consistency with Add Friends
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.group_outlined, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 18),
                                Text(
                                  'No friends yet',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap "Add" above to find and add friends!',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 15,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.zero, // match Add Friends
                        itemCount: authProvider.friendsList.length,
                        itemBuilder: (context, index) {
                          final friend = authProvider.friendsList[index];
                          return Column(
                            children: [
                              _buildFriendCard(context, friend),
                              const SizedBox(height: 10), // match Add Friends spacing
                            ],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  // Find Friends tab content
  Widget _buildFindFriendsTab(BuildContext context, AuthProvider authProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          
          // Friend Requests Section
          if (authProvider.pendingFriendRequests.isNotEmpty) ...[
            const Text(
              'Friend Requests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: authProvider.pendingFriendRequests.length,
                itemBuilder: (context, index) {
                  final request = authProvider.pendingFriendRequests[index];
                  return _buildFriendRequestCard(context, request, authProvider);
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          const Text(
            'Add Friends',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Material(
            elevation: 0.5,
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users by username or name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _isSearching
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : (_searchController.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: Colors.grey.shade600),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchResults.clear();
                              });
                            },
                          )
                        : null),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                if (value.length >= 2) {
                  _searchUsers(value);
                } else {
                  setState(() {
                    _searchResults.clear();
                  });
                }
              },
            ),
          ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Search Results',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Builder(
                builder: (context) {
                  final pendingRequestSenderIds = authProvider.pendingFriendRequests
                      .map((req) => req.senderId)
                      .toSet();
                  final friendIds = authProvider.friendsList.map((f) => f.id).toSet();
                  final filteredResults = _searchResults
                      .where((user) => !pendingRequestSenderIds.contains(user.id) && !friendIds.contains(user.id))
                      .toList();
                  return ListView.builder(
                    itemCount: filteredResults.length,
                    itemBuilder: (context, index) {
                      final user = filteredResults[index];
                      return Column(
                        children: [
                          _buildUserCard(context, user, authProvider),
                          const SizedBox(height: 10),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ] else if (_searchController.text.isNotEmpty && _searchResults.isEmpty) ...[
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5 - 100, // 100 accounts for search bar and padding
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 18),
                        Text(
                          'No users found',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Try a different name or username.',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.5 - 100, // 100 accounts for search bar and padding
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_search, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 18),
                        Text(
                          'Find new friends',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start typing above to search for users.',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 15,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Helper method to search users
  Future<void> _searchUsers(String query) async {
    if (!mounted) return; // Check if widget is still mounted
    
    setState(() {
      _isSearching = true;
    });
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final results = await authProvider.searchUsers(query);
      
      if (mounted) { // Check again before updating state
        setState(() {
          _searchResults = results;
        });
      }
    } catch (e) {
      print('Error searching users: $e');
    } finally {
      if (mounted) { // Check before updating state
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  // Helper widget for user cards in search results
  Widget _buildUserCard(BuildContext context, app.User user, AuthProvider authProvider) {
    final theme = Theme.of(context);
    final displayName = user.firstName != null && user.lastName != null
        ? '${user.firstName} ${user.lastName}'
        : user.username;
    final usernameTag = '@${user.username}';
    // Precompute status
    final bool isFriend = authProvider.friendsList.any((f) => f.id == user.id);
    final sentRequest = authProvider.sentFriendRequests
        .where((r) => r.receiverId == user.id && r.status == FriendRequestStatus.pending)
        .toList();
    final bool hasPendingRequest = sentRequest.isNotEmpty;
    print('Sent requests: '
      '${authProvider.sentFriendRequests.map((r) => 'to \\${r.receiverId} status \\${r.status}').toList()}');
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              radius: 20,
              child: Text(
                (user.firstName != null && user.lastName != null && user.firstName!.isNotEmpty && user.lastName!.isNotEmpty)
                  ? (user.firstName![0] + user.lastName![0]).toUpperCase()
                  : user.username[0].toUpperCase(),
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
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '@${user.username}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // Show status based on precomputed info
            if (isFriend)
              const Chip(
                label: Text('Friends'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white),
              )
            else if (hasPendingRequest)
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.only(left: 2),
                    child: IconButton(
                      icon: Icon(Icons.hourglass_top, color: Colors.orange, size: 28),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onPressed: () async {
                        if (sentRequest.first.id != null) {
                          print('UI: Cancelling friend request with id: \\${sentRequest.first.id} to user: \\${user.id}');
                          await authProvider.cancelSentFriendRequest(sentRequest.first.id!);
                        }
                      },
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: IconButton(
                    icon: Icon(Icons.person_add, color: vibrantBlue, size: 28),
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    onPressed: () async {
                      await authProvider.sendFriendRequest(user.id!);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Helper widget for friend cards
  Widget _buildFriendCard(BuildContext context, app.User friend) {
    final theme = Theme.of(context);
    final displayName = friend.firstName != null && friend.lastName != null
        ? '${friend.firstName} ${friend.lastName}'
        : friend.username;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              radius: 20,
              child: Text(
                (friend.firstName != null && friend.lastName != null && friend.firstName!.isNotEmpty && friend.lastName!.isNotEmpty)
                  ? (friend.firstName![0] + friend.lastName![0]).toUpperCase()
                  : friend.username[0].toUpperCase(),
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
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
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
            IconButton(
              icon: Icon(Icons.message, color: vibrantBlue, size: 28),
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              onPressed: () async {
                final messagingService = MessagingService.instance;
                final currentUserId = messagingService.supabase.auth.currentUser!.id;
                try {
                  // Check if conversation already exists
                  final existingConversationId = await messagingService.findExistingOneOnOneConversation(
                    currentUserId,
                    friend.id!,
                  );
                  
                  final conversationId = existingConversationId ?? await messagingService.getOrCreateConversation(
                    currentUserId,
                    friend.id!,
                  );
                  
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
                    
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatScreen(
                          conversationId: conversationId,
                          otherParticipantName: displayName,
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error starting conversation: $e')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget for friend request cards
  Widget _buildFriendRequestCard(BuildContext context, FriendRequest request, AuthProvider authProvider) {
    final theme = Theme.of(context);
    final senderName = request.senderDisplayName;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0.5,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 4, top: 14, bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              radius: 20,
              child: Text(
                (request.senderFirstName != null && request.senderLastName != null && request.senderFirstName!.isNotEmpty && request.senderLastName!.isNotEmpty)
                  ? (request.senderFirstName![0] + request.senderLastName![0]).toUpperCase()
                  : (request.senderUsername?.isNotEmpty == true ? request.senderUsername![0].toUpperCase() : '?'),
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    senderName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '@${request.senderUsername}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onPressed: () async {
                    await authProvider.respondToFriendRequest(
                      request.id!,
                      FriendRequestStatus.accepted,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red, size: 28),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onPressed: () async {
                    await authProvider.respondToFriendRequest(
                      request.id!,
                      FriendRequestStatus.rejected,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void selectTab(int index) {
    _tabController.animateTo(index);
  }
}