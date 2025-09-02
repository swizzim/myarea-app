import 'package:flutter/material.dart';
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/models/event_model.dart';
import 'package:myarea_app/models/event_response_model.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:myarea_app/screens/events/event_details_screen.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myarea_app/services/deep_link_service.dart';
import 'dart:async';
import 'package:myarea_app/main.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/screens/auth/auth_flow_screen.dart';
import 'package:myarea_app/screens/events/heart_celebration.dart';
import 'package:myarea_app/styles/app_colours.dart';
import 'package:myarea_app/screens/events/category_filter_panel.dart';
import 'package:myarea_app/screens/events/date_filter_panel.dart';
import 'package:myarea_app/screens/events/location_filter_panel.dart';
import 'dart:math' as math;



// Global key and programmatic refresh API for EventScreen
class EventScreen extends StatefulWidget {
  static final GlobalKey<EventScreenState> globalKey = GlobalKey<EventScreenState>();

  static void refreshEvents() {
    final state = globalKey.currentState;
    if (state != null) {
      state._loadEvents();
    }
  }

  const EventScreen({super.key});

  @override
  State<EventScreen> createState() => EventScreenState();
}

class EventScreenState extends State<EventScreen> with RouteAware {
  // State variables
  List<Event> _events = [];
  List<String> _categories = [];
  bool _isLoading = true;
  Event? _selectedEvent;
  List<String> _selectedCategories = [];
  double? _distanceKm;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _freeOnly = false;
  bool _savedOnly = false;
  bool _isEventDetailsVisible = false;
  double? _searchCenterLat;
  double? _searchCenterLng;
  Map<int, EventResponseType?> _userResponses = {};
  final ValueNotifier<bool> _showBackToTopNotifier = ValueNotifier<bool>(false);
  bool _isLoadingFriendsResponses = false;
  Map<int, Map<String, EventResponseType>> _friendsResponses = {};
  List<dynamic>? _preloadedFriendsList;

  // Auth state handling
  AuthProvider? _authProvider;
  bool _wasAuthenticated = false;

  // Scroll position management
  final ScrollController _scrollController = ScrollController();
  
  // Infinite scroll state management
  bool _isLoadingMore = false;
  bool _hasMoreEvents = true;
  int _currentOffset = 0;
  static const int _eventsPerPage = 5;

  // Event response state
  final Map<int, Map<EventResponseType, int>> _responseCounts = {};
  
  // Celebration overlay state
  bool _showCelebration = false;
  IconData? _celebrationIcon;
  Color? _celebrationColor;
  int? _celebratingEventId;
  Key _celebrationKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    tz_data.initializeTimeZones();
    _fetchCategories();
    _loadEvents();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
    
    // Add scroll listener for infinite scrolling
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    // Handle back-to-top button immediately for responsiveness
    _updateBackToTopButton();
    
    // Early return only if there are no more events to load
    if (!_hasMoreEvents) return;
    
    // Early return if already loading more events
    if (_isLoadingMore) return;
    
    // Check if we should load more events immediately (no debouncing)
    // Load very aggressively - start loading after user has seen just a few events
    final scrollPosition = _scrollController.position;
    final currentPixels = scrollPosition.pixels;
    
    // Start loading when user has scrolled past the first 2-3 events
    // This ensures we're always ahead of the user
    if (currentPixels > 200) { // After just 2-3 events
      // Only trigger if not already loading and there are more events
      if (!_isLoadingMore && _hasMoreEvents) {
        _loadMoreEvents();
      }
    }
  }

  // Separate method for updating back-to-top button (no debouncing)
  void _updateBackToTopButton() {
    // Safety check: ensure scroll controller is attached and has positions
    if (!_scrollController.hasClients || _scrollController.positions.isEmpty) return;
    
    // Check if we should show back to top button - show when past the first event card
    final cardHeight = 160.0 + 12.0 + 12.0 + 80.0; // Image + top padding + bottom padding + content height
    final shouldShowBackToTop = _scrollController.position.pixels > cardHeight;
    if (shouldShowBackToTop != _showBackToTopNotifier.value) {
      _showBackToTopNotifier.value = shouldShowBackToTop;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Subscribe to route observer only if route is a PageRoute
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }

    // Attach auth listener once and react when auth state changes
    final provider = Provider.of<AuthProvider>(context, listen: false);
    if (!identical(_authProvider, provider)) {
      // No explicit addListener/removeListener API on Provider itself; rely on change notifications via Consumer calls
      // We cache the instance and poll auth state transitions on frame callbacks
      _authProvider = provider;
      _wasAuthenticated = _authProvider?.isAuthenticated ?? false;

      // Defer to next microtask to avoid setState during build
      Future.microtask(() {
        if (!mounted) return;
        _handleAuthTransition();
      });
    }
  }

  @override
  void dispose() {
    // Unsubscribe from route observer
    routeObserver.unsubscribe(this);
    
    // Dispose scroll controller
    _scrollController.dispose();
    
    super.dispose();
  }

  // Handle transitions in authentication state to (re)load friends' responses
  void _handleAuthTransition() {
    if (!mounted) return;
    final isAuthed = _authProvider?.isAuthenticated ?? false;
    if (isAuthed && !_wasAuthenticated) {
      _wasAuthenticated = true;
      // When user logs in after screen loaded, fetch friends list and reload friends' responses
      _reloadFriendsDataForCurrentEvents();
    } else if (!isAuthed && _wasAuthenticated) {
      // User logged out; clear any friend-related state
      _wasAuthenticated = false;
      setState(() {
        _friendsResponses.clear();
        _preloadedFriendsList = null;
      });
    }
  }

  Future<void> _reloadFriendsDataForCurrentEvents() async {
    if (!mounted) return;
    try {
      final authProvider = _authProvider ?? Provider.of<AuthProvider>(context, listen: false);
      // Ensure friends list is loaded
      if (authProvider.isAuthenticated && authProvider.friendsList.isEmpty) {
        try { await authProvider.loadFriendsList(); } catch (_) {}
      }
      // Preload for details screen
      if (authProvider.isAuthenticated) {
        _preloadedFriendsList = authProvider.friendsList;
      }
      if (_events.isNotEmpty) {
        // Reload friends' responses for already loaded events
        await _loadFriendsResponses(_events);
      }
    } catch (_) {}
  }



  Future<void> _fetchCategories() async {
    try {
      final categories = await SupabaseDatabase.instance.getAllEventCategories();
      setState(() {
        _categories = categories.map((cat) => cat.name).toList();
      });
    } catch (e) {
      setState(() {
        _categories = [
          'Music',
          'Nightlife',
          'Performing & Visual Arts',
          'Holidays',
          'Dating',
          'Hobbies',
          'Business',
          'Food & Drink',
        ];
      });
    }
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    
    // Reset pagination state
    _currentOffset = 0;
    _hasMoreEvents = true;
    _isLoadingMore = false;
    
    // Clear responses when loading new events
    _userResponses.clear();
    _friendsResponses.clear();
    _preloadedFriendsList = null;
    
    // Get current user for response filtering
    final user = Supabase.instance.client.auth.currentUser;
    
    // Convert response filter string to enum
    EventResponseType? responseFilter;
    if (_savedOnly) {
      responseFilter = EventResponseType.interested;
    }
    
    try {
      // Load first page of filtered events from backend
      final events = await SupabaseDatabase.instance.getEventsFiltered(
        limit: _eventsPerPage,
        offset: 0,
        categories: _selectedCategories.isNotEmpty ? _selectedCategories : null,
        fromDate: _fromDate,
        toDate: _toDate,
        distanceKm: _distanceKm,
        searchCenterLat: _searchCenterLat,
        searchCenterLng: _searchCenterLng,
        userResponse: responseFilter,
        userId: user?.id,
        freeOnly: _freeOnly,
      );
      
      if (!mounted) return;
      
      // Load user responses and friends' responses for events
      await Future.wait([
        _loadUserResponses(events),
        _loadFriendsResponses(events),
      ]);
      
      // Pre-cache images for the first batch BEFORE ending loading state
      await _precacheEventImagesAndNotify(events);
      
      if (mounted) {
        setState(() {
          // Backend now handles all filtering including schedule-based date filtering
          _events = events;
          // Check if we have more events (either got a full page or there might be more)
          // Consider there are more events as long as we received any
          _hasMoreEvents = events.isNotEmpty;
          _isLoading = false; // Only end loading after images are ready
        });
      }
      
      // Notify DeepLinkService that EventScreen is ready
      DeepLinkService().onEventScreenReady(this);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreEvents() async {
    // Prevent multiple simultaneous calls
    if (_isLoadingMore || !_hasMoreEvents || !mounted || _events.isEmpty) return;
    
    // Set loading state immediately so user sees feedback right away
    setState(() => _isLoadingMore = true);
    
    try {
      // Get current user for response filtering
      final user = Supabase.instance.client.auth.currentUser;
      
      // Convert response filter string to enum
      EventResponseType? responseFilter;
      if (_savedOnly) {
        responseFilter = EventResponseType.interested;
      }
      
      // Calculate next offset
      final nextOffset = _currentOffset + _eventsPerPage;
      
      // Fetch more events
      final moreEvents = await SupabaseDatabase.instance.getEventsFiltered(
        limit: _eventsPerPage,
        offset: nextOffset,
        categories: _selectedCategories.isNotEmpty ? _selectedCategories : null,
        fromDate: _fromDate,
        toDate: _toDate,
        distanceKm: _distanceKm,
        searchCenterLat: _searchCenterLat,
        searchCenterLng: _searchCenterLng,
        userResponse: responseFilter,
        userId: user?.id,
        freeOnly: _freeOnly,
      );
      
      if (!mounted) return;
      
      // Update state with new events
      setState(() {
        _events.addAll(moreEvents);
        _currentOffset = nextOffset;
        // Consider there are more events as long as we received any
        _hasMoreEvents = moreEvents.isNotEmpty;
        _isLoadingMore = false; // Only end loading after events are added
      });
      
      // Load responses and pre-cache images in background without blocking UI
      if (moreEvents.isNotEmpty) {
        // Use compute or isolate for heavy operations to prevent scroll jank
        _loadResponsesAndImagesInBackground(moreEvents);
      }
      
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  // Background loading to prevent scroll performance impact
  void _loadResponsesAndImagesInBackground(List<Event> newEvents) {
    // Use Future.microtask to defer heavy operations
    Future.microtask(() async {
      try {
        // Load responses for new events asynchronously
        await _loadResponsesForNewEvents(newEvents);
        
        // Pre-cache images for smooth scrolling
        _precacheEventImages(newEvents);
      } catch (e) {
        // Silently handle errors for background operations
      }
    });
  }

  // Load responses for new events asynchronously
  Future<void> _loadResponsesForNewEvents(List<Event> newEvents) async {
    if (!mounted || newEvents.isEmpty) return;
    
    try {
      // Load user responses and friends' responses for new events
      // Pass isPagination: true to prevent unnecessary setState calls
      await Future.wait([
        _loadUserResponses(newEvents, isPagination: true),
        _loadFriendsResponses(newEvents, isPagination: true),
      ]);
    } catch (e) {
      // Silently handle errors for background loading
    }
  }

  Future<void> _loadUserResponses(List<Event> events, {bool isPagination = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    
    // If user is not authenticated, skip loading responses
    if (user == null) {
      // Only update state if this is the initial load, not for pagination
      if (!isPagination) {
        setState(() {
          _userResponses = {};
        });
      }
      return;
    }

    final userResponses = <int, EventResponseType?>{};
    
    for (final event in events) {
      final response = await SupabaseDatabase.instance.getUserEventResponse(event.id, user.id);
      userResponses[event.id] = response?.responseType;
    }
    
    // Only update state if this is the initial load, not for pagination
    if (!isPagination) {
      setState(() {
        _userResponses.addAll(userResponses);
      });
    } else {
      // For pagination, update the map directly without setState to avoid rebuilds
      _userResponses.addAll(userResponses);
    }
  }

  Future<void> _loadFriendsResponses(List<Event> events, {bool isPagination = false}) async {
    // Only set loading state for initial load, not for pagination
    if (!isPagination) {
      setState(() => _isLoadingFriendsResponses = true);
    }
    
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    // Ensure friends list is loaded on initial app load and preload it for EventDetailsScreen
    if (authProvider.isAuthenticated && authProvider.friendsList.isEmpty) {
      try {
        await authProvider.loadFriendsList();
      } catch (_) {}
    }
    
    // Preload friends list for EventDetailsScreen optimization
    if (authProvider.isAuthenticated && _preloadedFriendsList == null) {
      try {
        _preloadedFriendsList = authProvider.friendsList;
      } catch (_) {}
    }
    
    final friendsResponses = <int, Map<String, EventResponseType>>{};
    
    for (final event in events) {
      final responses = await authProvider.getFriendsEventResponses(event.id);
      if (mounted) {
        friendsResponses[event.id] = responses;
      }
    }
    
    if (mounted) {
      // Only update state if this is the initial load, not for pagination
      if (!isPagination) {
        setState(() {
          _friendsResponses.addAll(friendsResponses);
          _isLoadingFriendsResponses = false;
        });
      } else {
        // For pagination, update the map directly without setState to avoid rebuilds
        _friendsResponses.addAll(friendsResponses);
      }
    }
  }

  Future<void> _precacheEventImagesAndNotify(List<Event> events) async {
    final ctx = context;
    final futures = <Future<void>>[];
    
    // Precache all images for initial load (now 5 instead of 5)
    for (final event in events.take(5)) {
      final imageUrl = await _resolvePrecacheUrl(event);
      if (imageUrl != null && imageUrl.isNotEmpty) {
        try {
          futures.add(precacheImage(CachedNetworkImageProvider(imageUrl), ctx).catchError((_) {}));
        } catch (_) {}
      }
    }
    
    // Wait for all images to be properly loaded before proceeding
    if (futures.isNotEmpty) {
      try {
        await Future.wait(futures).timeout(const Duration(milliseconds: 3000));
      } catch (_) {
        // If any image fails or times out, continue gracefully
      }
    }
    
    // All images are now ready - loading state can end
  }

  // Enhanced precaching for ongoing user experience
  void _precacheEventImages(List<Event> events) {
    final ctx = context;
    // Precache all images (5) for smooth scrolling and browsing
    for (final event in events.take(5)) {
      _resolvePrecacheUrl(event).then((imageUrl) {
        if (imageUrl != null && imageUrl.isNotEmpty) {
          try {
            precacheImage(CachedNetworkImageProvider(imageUrl), ctx).catchError((_) {});
          } catch (_) {}
        }
      });
    }
  }

  // Validate URL with a quick HEAD, fallback to original if cropped fails
  Future<String?> _resolvePrecacheUrl(Event event) async {
    final best = _getBestImageUrlForEvent(event);
    // Just return the URL without HTTP validation to avoid network requests during scroll
    return best;
  }

  // Helper to get category icon color
  Color _getCategoryIconColor(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return const Color(0xFF9C27B0); // Purple
      case 'nightlife':
        return const Color(0xFF673AB7); // Deep purple
      case 'exhibitions':
        return const Color(0xFFE91E63); // Pink
      case 'theatre, dance & film':
        return const Color(0xFFFF5722); // Deep orange
      case 'tours':
        return const Color(0xFF4CAF50); // Green
      case 'markets':
        return const Color(0xFF795548); // Brown
      case 'food & drink':
        return const Color(0xFFFF9800); // Orange
      case 'dating':
        return const Color(0xFFE91E63); // Pink
      case 'comedy':
        return const Color(0xFFFFC107); // Amber
      case 'talks, courses & workshops':
        return const Color(0xFF2196F3); // Blue
      case 'health & fitness':
        return const Color(0xFF4CAF50); // Green
      default:
        return Theme.of(context).primaryColor;
    }
  }

  // Helper to choose best image URL (cropped if present), matching EventListView/EventDetails logic
  String? _getBestImageUrlForEvent(Event event) {
    if (event.coverPhoto == null || event.coverPhoto!.isEmpty) {
      return null;
    }
    if (event.coverPhotoCrop != null && event.coverPhotoCrop!.isNotEmpty) {
      try {
        Map<String, dynamic> cropData = {};
        try {
          cropData = Map<String, dynamic>.from(jsonDecode(event.coverPhotoCrop!));
        } catch (_) {
          cropData = {};
        }
        final croppedUrl = cropData['croppedImageUrl']?.toString();
        if (croppedUrl != null && croppedUrl.isNotEmpty) {
          if (croppedUrl.startsWith('http') || croppedUrl.startsWith('data:image')) {
            return croppedUrl;
          }
        }
        final storagePath = cropData['storagePath']?.toString();
        if (storagePath != null && storagePath.isNotEmpty) {
          final publicUrl = Supabase.instance.client.storage.from('event-covers').getPublicUrl(storagePath);
          if (publicUrl.isNotEmpty) {
            return publicUrl;
          }
        }
      } catch (_) {}
    }
    // Only return if it's a valid HTTP URL
    return event.coverPhoto!.startsWith('http') ? event.coverPhoto! : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColours.background,
      body: Stack(
        children: [
          // Main event list content
          SafeArea(
            child: Stack(
              children: [
                // Main content area
                Padding(
                  padding: const EdgeInsets.only(top: 74.0),
                  child: _isLoading
                      ? _buildSkeletonEventList()
                      : _events.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                                SizedBox(height: 16),
                                Text(
                                  'No events found',
                                  style: TextStyle(fontSize: 20, color: Colors.grey[700], fontWeight: FontWeight.w600),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Try adjusting your filters.',
                                  style: TextStyle(fontSize: 15, color: Colors.grey[500]),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : _isLoadingFriendsResponses
                          ? Center(child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppColours.buttonPrimary),
                          ))
                          : _buildEventList(),
                ),
                
                // Title and filter pills - always visible
                Positioned(
                  top: 0,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 2),
                      Padding(
                        padding: const EdgeInsets.only(left: 0, right: 0, bottom: 0),
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                            children: [
                              const TextSpan(text: 'Discover '),
                              TextSpan(
                                text: 'what\'s on',
                                style: TextStyle(
                                  color: AppColours.titleAccent,
                                ),
                              ),
                              const TextSpan(text: ' in '),
                              TextSpan(
                                text: 'Sydney',
                                style: TextStyle(
                                  color: AppColours.titleAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 2),
                      _buildFilterPills(),
                    ],
                  ),
                ),
                
                // Back to top button positioned near the top
                Positioned(
                  top: 82,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _showBackToTopNotifier,
                      builder: (context, showBackToTop, child) {
                        return Visibility(
                          visible: showBackToTop && _events.isNotEmpty,
                          maintainState: false,
                          maintainSize: false,
                          maintainAnimation: false,
                          child: GestureDetector(
                            onTap: showBackToTop ? _scrollToTop : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColours.buttonPrimary,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.keyboard_arrow_up,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Back to top',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Event details modal overlay
          if (_isEventDetailsVisible && _selectedEvent != null)
            _buildEventDetailsModal(),
          
          // Celebration overlay
          _buildCelebrationOverlay(),
        ],
      ),
    );
  }

  // Skeleton loading state that maintains UI structure
  Widget _buildSkeletonEventList() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(
        left: 12,
        right: 12,
        top: 6,
        bottom: 20,
      ),
      itemCount: 5, // Show 5 skeleton cards
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildSkeletonEventCard(),
        );
      },
    );
  }

  // Skeleton event card
  Widget _buildSkeletonEventCard() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: AppColours.eventCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Skeleton image
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Skeleton title
                Container(
                  height: 20,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                // Skeleton title line 2
                Container(
                  height: 16,
                  width: MediaQuery.of(context).size.width * 0.6,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                // Skeleton category chips
                Row(
                  children: [
                    Container(
                      height: 24,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 24,
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Skeleton date
                Row(
                  children: [
                    Container(
                      height: 14,
                      width: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      height: 14,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Skeleton location
                Row(
                  children: [
                    Container(
                      height: 14,
                      width: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      height: 14,
                      width: 100,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Skeleton price
                Row(
                  children: [
                    Container(
                      height: 14,
                      width: 14,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Container(
                      height: 14,
                      width: 60,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Event details modal overlay
  Widget _buildEventDetailsModal() {
    return EventDetailsScreen(
      event: _selectedEvent!,
      preloadedUserResponse: _userResponses[_selectedEvent!.id] != null 
        ? EventResponse(
            eventId: _selectedEvent!.id,
            userId: Supabase.instance.client.auth.currentUser?.id ?? '',
            responseType: _userResponses[_selectedEvent!.id]!,
            createdAt: DateTime.now(),
          )
        : null,
      preloadedResponseCounts: _responseCounts[_selectedEvent!.id] ?? {
        EventResponseType.interested: 0,
      },
      preloadedFriendsResponses: _friendsResponses[_selectedEvent!.id] ?? {},
      preloadedAllFriends: _preloadedFriendsList,
      onBack: () {
        setState(() {
          _isEventDetailsVisible = false;
          _selectedEvent = null;
        });
        // No need to reload events or restore scroll position since we're just hiding the modal
      },
    );
  }

  // Celebration overlay
  Widget _buildCelebrationOverlay() {
    if (!_showCelebration || _celebrationIcon == null) {
      return const SizedBox.shrink();
    }
    
    return HeartCelebration(
      key: _celebrationKey,
      show: _showCelebration,
      icon: _celebrationIcon!,
      color: _celebrationColor ?? Colors.red,
      onEnd: () {
        if (mounted) {
          setState(() {
            _showCelebration = false;
          });
        }
      },
      originFromBottomNav: true,
    );
  }

  // Event list building
  Widget _buildEventList() {
    // Calculate bottom padding to account for safe area and navigation bar
    final bottomPadding = MediaQuery.of(context).padding.bottom + 72; // 72 is nav bar height
    
    // Reduce bottom padding when showing "No more events" message
    final shouldShowNoMoreEvents = _events.isNotEmpty && !_isLoadingMore && !_hasMoreEvents;
    final effectiveBottomPadding = shouldShowNoMoreEvents ? 20.0 : bottomPadding + 20;
    
    return RefreshIndicator(
      onRefresh: _loadEvents,
      color: AppColours.buttonPrimary,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: 6,
          bottom: effectiveBottomPadding,
        ),
        itemCount: _events.length + (_isLoadingMore ? 1 : 0) + (_events.isNotEmpty && !_isLoadingMore && !_hasMoreEvents ? 1 : 0),
        itemBuilder: (context, index) {
          // Show loading indicator at the bottom
          if (index == _events.length && _isLoadingMore) {
            return Container(
              padding: const EdgeInsets.all(24.0),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColours.buttonPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading more events...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please wait while we fetch the next batch',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          
          // Show "No more events" message
          if (index == _events.length && _events.isNotEmpty && !_isLoadingMore && !_hasMoreEvents) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 12.0, 24.0, 12.0),
              child: Column(
                children: [
                  Icon(
                    Icons.event_busy,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No more events',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ve reached the end of the list',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          
          // Show subtle hint that more events are available
          if (index == _events.length && _events.isNotEmpty && !_isLoadingMore && _hasMoreEvents) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24.0, 12.0, 24.0, 12.0),
              child: Column(
                children: [
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 32,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scroll down for more events',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          
          final event = _events[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildEventCard(event),
          );
        },
      ),
    );
  }

  Widget _buildEventCard(Event event) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: AppColours.eventCard,
      child: Material(
        color: Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _navigateToEventDetails(event),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEventImage(event),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEventHeader(event),
                    const SizedBox(height: 8),
                    _buildEventDateTime(event),
                    const SizedBox(height: 6),
                    _buildEventLocation(event),
                    const SizedBox(height: 6),
                    _buildEventPrice(event),
                    if (_getFriendsInterestedCount(event) > 0) ...[
                      const SizedBox(height: 6),
                      _buildFriendsInterestedCount(event),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPills() {
    return Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 14, left: 0, right: 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          height: 38,
          clipBehavior: Clip.none,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            child: Row(
              children: _getOrderedFilterChips(),
            ),
          ),
        ),
      ),
    );
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  // Event card components
  Widget _buildEventImage(Event event) {
    final imageUrl = _getBestImageUrl(event);
    
    if (imageUrl == null) {
      return Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Center(
          child: Icon(
            Icons.event,
            size: 40,
            color: Colors.grey[400],
          ),
        ),
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      child: SizedBox(
        height: 160,
        width: double.infinity,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(
            color: Colors.grey[200],
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColours.buttonPrimary),
              ),
            ),
          ),
          errorWidget: (context, url, error) {
            // If this was a cropped image that failed, try to fall back to original
            if (url != event.coverPhoto && event.coverPhoto != null && event.coverPhoto!.isNotEmpty && event.coverPhoto!.startsWith('http')) {
              final fallbackUrl = event.coverPhoto!;
              
              return CachedNetworkImage(
                imageUrl: fallbackUrl,
                fit: BoxFit.cover,
                placeholder: (context, fallbackUrl) => Container(
                  color: Colors.grey[200],
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColours.buttonPrimary),
                    ),
                  ),
                ),
                errorWidget: (context, fallbackUrl, fallbackError) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: Icon(
                      Icons.image_not_supported,
                      size: 40,
                      color: Colors.grey,
                    ),
                  ),
                ),
                fadeInDuration: Duration.zero,
                fadeOutDuration: Duration.zero,
              );
            }
            
            return Container(
              color: Colors.grey[200],
              child: const Center(
                child: Icon(
                  Icons.image_not_supported,
                  size: 40,
                  color: Colors.grey,
                ),
              ),
            );
          },
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
        ),
      ),
    );
  }

  Widget _buildEventHeader(Event event) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                event.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            // Interested button
            GestureDetector(
              onTap: () => _handleResponse(event, EventResponseType.interested),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  _userResponses[event.id] == EventResponseType.interested
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: _userResponses[event.id] == EventResponseType.interested 
                      ? AppColours.heart 
                      : Colors.grey[600],
                  size: 24,
                ),
              ),
            ),
            // Share button (disabled)
            GestureDetector(
              onTap: null,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.share,
                  color: Colors.grey[400],
                  size: 24,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            for (final cat in event.category)
              Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getCategoryIconColor(cat).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (cat.toLowerCase() == 'exhibitions') ...[
                        Icon(Icons.palette, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'theatre, dance & film') ...[
                        Icon(Icons.theater_comedy, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'music') ...[
                        Icon(Icons.music_note, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'tours') ...[
                        Icon(Icons.directions_walk, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'markets') ...[
                        Icon(Icons.shopping_basket, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'nightlife') ...[
                        Icon(Icons.nightlife, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'food & drink') ...[
                        Icon(Icons.restaurant, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'dating') ...[
                        Icon(Icons.favorite, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'comedy') ...[
                        Icon(Icons.emoji_emotions, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'talks, courses & workshops') ...[
                        Icon(Icons.record_voice_over, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ] else if (cat.toLowerCase() == 'health & fitness') ...[
                        Icon(Icons.fitness_center, size: 13, color: _getCategoryIconColor(cat)),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        cat,
                        style: TextStyle(
                          color: AppColours.buttonPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(width: 8),
          ],
        ),
      ],
    );
  }

  Widget _buildEventDateTime(Event event) {
    final startTime = tz.TZDateTime.from(event.dateTime, tz.getLocation(event.timezone));
    final endTime = tz.TZDateTime.from(event.endDateTime, tz.getLocation(event.timezone));

    final isSameDay = startTime.year == endTime.year &&
        startTime.month == endTime.month &&
        startTime.day == endTime.day;

    // Check if event has schedule data
    final hasScheduleData = event.scheduleData != null;
    
    String dateTimeText;
    
    if (hasScheduleData) {
      final scheduleData = event.scheduleData!;
      final recurring = scheduleData['recurring'] as Map<String, dynamic>?;
      final single = scheduleData['single'];
      
      // Collect all exceptions from recurring rules
      List<Map<String, dynamic>> allExceptions = [];
      if (recurring != null) {
        for (final dayRule in recurring.values) {
          if (dayRule is Map<String, dynamic> && dayRule.containsKey('exceptions')) {
            final dayExceptions = dayRule['exceptions'] as List<dynamic>?;
            if (dayExceptions != null) {
              allExceptions.addAll(dayExceptions.cast<Map<String, dynamic>>());
            }
          }
        }
      }
      
      // Check if it's a single session event
      bool isSingleSession = false;
      String? sessionTime;
      
      if (single != null) {
        if (single is Map<String, dynamic>) {
          // Single session with one entry
          isSingleSession = true;
          final open = single['open'] as String?;
          final close = single['close'] as String?;
          if (open != null && close != null) {
            sessionTime = '${_formatTime(open)} - ${_formatTime(close)}';
          }
        } else if (single is List && single.length == 1) {
          // Single session with one entry in list
          isSingleSession = true;
          final session = single[0] as Map<String, dynamic>;
          final open = session['open'] as String?;
          final close = session['close'] as String?;
          if (open != null && close != null) {
            sessionTime = '${_formatTime(open)} - ${_formatTime(close)}';
          }
        }
      }
      
      // Check if it has recurring rules
      final hasRecurring = recurring != null && recurring.isNotEmpty;
      
      // Check if it has multiple single sessions
      final hasMultipleSessions = single is List && single.length > 1;
      
      // Check if there are exceptions that might affect the display
      final hasExceptions = allExceptions.isNotEmpty;
      
      if (isSameDay) {
        if (isSingleSession && sessionTime != null) {
          // Same day, single session with time
          dateTimeText = '${DateFormat('EEE, d MMM yy').format(startTime)} • $sessionTime';
        } else if (hasRecurring || hasMultipleSessions || hasExceptions) {
          // Same day, multiple sessions or has exceptions that create complexity
          dateTimeText = '${DateFormat('EEE, d MMM yy').format(startTime)} • Multiple times';
        } else {
          // Same day, no specific time info
          dateTimeText = DateFormat('EEE, d MMM yy').format(startTime);
        }
      } else {
        // Different start and end dates
        // For multi-day events with schedule data (recurring, multiple sessions, or exceptions), show "Multiple dates"
        if (hasRecurring || hasMultipleSessions || hasExceptions) {
          dateTimeText = '${DateFormat('EEE, d MMM yy').format(startTime)} - ${DateFormat('EEE, d MMM yy').format(endTime)} • Multiple dates';
        } else {
          // Date range without complex schedule data
          dateTimeText = '${DateFormat('EEE, d MMM yy').format(startTime)} - ${DateFormat('EEE, d MMM yy').format(endTime)}';
        }
      }
    } else {
      // No schedule data, use original logic
      if (isSameDay) {
        dateTimeText = DateFormat('EEE, d MMM yy').format(startTime);
      } else {
        dateTimeText = '${DateFormat('EEE, d MMM yy').format(startTime)} - ${DateFormat('EEE, d MMM yy').format(endTime)}';
      }
    }

    return Row(
      children: [
        Icon(
          Icons.calendar_today,
          size: 14,
          color: AppColours.eventCalendar,
        ),
        const SizedBox(width: 4),
        Text(
          dateTimeText,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  String _formatTime(String timeString) {
    // Convert 24-hour format to 12-hour format
    // Expected format: "HH:MM" or "HH:MM:SS"
    try {
      final parts = timeString.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = parts[1];
        
        if (hour == 0) {
          return '12:$minute AM';
        } else if (hour < 12) {
          return '$hour:$minute AM';
        } else if (hour == 12) {
          return '12:$minute PM';
        } else {
          return '${hour - 12}:$minute PM';
        }
      }
    } catch (e) {
      // If parsing fails, return original string
      return timeString;
    }
    return timeString;
  }

  Widget _buildEventLocation(Event event) {
    return Row(
      children: [
        Icon(
          Icons.location_on,
          size: 14,
          color: AppColours.eventLocation,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            _extractSuburb(event),
            style: TextStyle(
              color: Colors.black87,
              fontSize: 12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _extractSuburb(Event event) {
    // Show "Venue, City" if both are present
    if (event.venue != null && event.venue!.isNotEmpty && event.city != null && event.city!.isNotEmpty) {
      return '${event.venue}, ${event.city}';
    }
    // Show "Street, City" if both are present and venue is not available
    if (event.street != null && event.street!.isNotEmpty && event.city != null && event.city!.isNotEmpty) {
      return '${event.street}, ${event.city}';
    }
    // If only city is present
    if (event.city != null && event.city!.isNotEmpty) {
      return event.city!;
    }
    // If only venue is present
    if (event.venue != null && event.venue!.isNotEmpty) {
      return event.venue!;
    }
    // If only street is present
    if (event.street != null && event.street!.isNotEmpty) {
      return event.street!;
    }
    // Fallback to parsing the address
    final parts = event.address.split(',');
    if (parts.length >= 2) {
      final relevantParts = parts.sublist(0, parts.length - 2);
      return relevantParts.join(',').trim();
    }
    return event.address;
  }

  Widget _buildEventPrice(Event event) {
    String priceText;
    final price = event.ticketPrice;
    final variable = event.variable;
    if (price == 0 && variable) {
      priceText = 'From \$0';
    } else if (price == 0) {
      priceText = 'Free';
    } else if (variable) {
      priceText = 'From \$${price % 1 == 0 ? price.toInt() : price.toStringAsFixed(2)}';
    } else {
      priceText = '\$${price % 1 == 0 ? price.toInt() : price.toStringAsFixed(2)}';
    }
    return Row(
      children: [
        Icon(
          Icons.confirmation_number,
          size: 14,
          color: AppColours.eventTicket,
        ),
        const SizedBox(width: 4),
        Text(
          priceText,
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildFriendsInterestedCount(Event event) {
    final friendsInterested = _getFriendsInterestedCount(event);
    if (friendsInterested == 0) return const SizedBox.shrink();
    
    final friendText = friendsInterested == 1 ? 'friend' : 'friends';
    
    return Row(
      children: [
        Icon(
          Icons.people,
          size: 14,
          color: AppColours.buttonPrimary,
        ),
        const SizedBox(width: 4),
        Text(
          '$friendsInterested $friendText interested',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  int _getFriendsInterestedCount(Event event) {
    final friendsResponses = _friendsResponses[event.id];
    int friendsInterested = 0;
    if (friendsResponses != null) {
      for (final response in friendsResponses.values) {
        if (response == EventResponseType.interested) {
          friendsInterested++;
        }
      }
    }
    return friendsInterested;
  }



  /// Gets the best available image URL for an event, prioritizing cropped images
  String? _getBestImageUrl(Event event) {
    if (event.coverPhoto == null || event.coverPhoto!.isEmpty) {
      return null;
    }

    // Check if we have crop data with a cropped image URL
    if (event.coverPhotoCrop != null && event.coverPhotoCrop!.isNotEmpty) {
      try {
        Map<String, dynamic> cropData = {};
        try {
          cropData = Map<String, dynamic>.from(jsonDecode(event.coverPhotoCrop!));
        } catch (_) {
          cropData = {};
        }
        
        // If we have a cropped image URL, use it
        if (cropData['croppedImageUrl'] != null && cropData['croppedImageUrl'].toString().isNotEmpty) {
          final croppedUrl = cropData['croppedImageUrl'].toString();
          if (croppedUrl.startsWith('http')) {
            return croppedUrl;
          } else if (croppedUrl.startsWith('data:image')) {
            // Handle base64 data URLs if needed
            return croppedUrl;
          }
        }

        // Fallback: build public URL from storagePath if available
        final storagePath = cropData['storagePath']?.toString();
        if (storagePath != null && storagePath.isNotEmpty) {
          final publicUrl = Supabase.instance.client.storage.from('event-covers').getPublicUrl(storagePath);
          if (publicUrl.isNotEmpty) {
            return publicUrl;
          }
        }
      } catch (e) {
        // Error parsing crop data
      }
    }
    
    // Fallback to original cover photo - only return if it's a valid HTTP URL
    return event.coverPhoto!.startsWith('http') ? event.coverPhoto! : null;
  }

  // Filter methods
  List<Widget> _getOrderedFilterChips() {
    // Build a list of filter chip data
    final chips = [
      {
        'label': _selectedCategories.isEmpty
            ? 'Category'
            : 'Category (${_selectedCategories.length})',
        'selected': _selectedCategories.isNotEmpty,
        'onTap': _openCategoryFilterPanel,
        'textColor': _selectedCategories.isNotEmpty ? AppColours.buttonPrimary : (Colors.grey[700] ?? Colors.grey),
        'icon': Icons.category,
      },
      {
        'label': _fromDate == null && _toDate == null ? 'Date' : _dateRangeSummary(),
        'selected': _fromDate != null || _toDate != null,
        'onTap': _openDateFilterPanel,
        'textColor': (_fromDate != null || _toDate != null) ? AppColours.buttonPrimary : (Colors.grey[700] ?? Colors.grey),
        'icon': Icons.calendar_today,
      },
      {
        'label': _distanceKm == null ? 'Location' : '${_distanceKm!.toStringAsFixed(0)} km',
        'selected': _distanceKm != null,
        'onTap': _openDistanceFilterPanel,
        'textColor': _distanceKm != null ? AppColours.buttonPrimary : (Colors.grey[700] ?? Colors.grey),
        'icon': Icons.location_on,
      },
      {
        'label': 'Free',
        'selected': _freeOnly,
        'onTap': () => _handleFreeFilterChanged(!_freeOnly),
        'textColor': _freeOnly ? AppColours.buttonPrimary : (Colors.grey[700] ?? Colors.grey),
        'icon': Icons.money_off,
      },
      {
        'label': 'Saved',
        'selected': _savedOnly,
        'onTap': () => _handleSavedFilterChanged(!_savedOnly),
        'textColor': _savedOnly ? AppColours.buttonPrimary : (Colors.grey[700] ?? Colors.grey),
        'icon': Icons.favorite,
      },
    ];
    
    // Separate selected and unselected
    final selected = chips.where((c) => c['selected'] as bool).toList();
    final unselected = chips.where((c) => !(c['selected'] as bool)).toList();
    
    // Combine, keeping selected first
    final ordered = [...selected, ...unselected];
    
    // Build widgets with spacing
    List<Widget> widgets = [];
    for (int i = 0; i < ordered.length; i++) {
      final c = ordered[i];
      widgets.add(_buildFilterChip(
        label: c['label'] as String,
        selected: c['selected'] as bool,
        onTap: c['onTap'] as VoidCallback,
        textColor: c['textColor'] as Color,
        icon: c['icon'] as IconData?,
      ));
      if (i != ordered.length - 1) widgets.add(SizedBox(width: 7));
    }
    return widgets;
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color textColor,
    IconData? icon,
  }) {
    return Card(
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: FilterChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: icon == Icons.favorite
                      ? AppColours.heart
                      : (icon == Icons.location_on
                          ? AppColours.buttonPrimary
                          : (icon == Icons.money_off
                              ? AppColours.filterFree
                              : (icon == Icons.calendar_today
                                  ? AppColours.titleAccent
                                  : (icon == Icons.category
                                      ? AppColours.filterCategory
                                      : textColor)))),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                  color: textColor,
                ),
              ),
            ],
          ),
          selected: selected,
          onSelected: (_) => onTap(),
          backgroundColor: AppColours.eventCard,
          selectedColor: AppColours.filterSelected.withOpacity(0.22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          visualDensity: VisualDensity(horizontal: -3, vertical: -3),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          showCheckmark: false,
          avatar: null,
        ),
      ),
    );
  }

  String _dateRangeSummary() {
    if (_fromDate == null && _toDate == null) return 'Any';
    final from = _fromDate != null ? DateFormat('MMM d').format(_fromDate!) : '';
    final to = _toDate != null ? DateFormat('MMM d').format(_toDate!) : '';
    if (_fromDate != null && _toDate != null) return '$from - $to';
    if (_fromDate != null) return 'From $from';
    if (_toDate != null) return 'Until $to';
    return 'Date';
  }

  // Event handling methods
  void _navigateToEventDetails(Event event) {
    // Show event details as modal overlay
    setState(() {
      _selectedEvent = event;
      _isEventDetailsVisible = true;
    });
  }

  Future<void> _handleResponse(Event event, EventResponseType responseType) async {
    // Check if user is authenticated
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated) {
      // Show auth flow screen for unauthenticated users
      AuthFlowScreen.push(context);
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser!.id;

    // Reset celebration state immediately
    setState(() {
      _showCelebration = false;
      _celebrationKey = UniqueKey(); // Force new celebration instance
    });

    try {
      bool isNew = _userResponses[event.id] != responseType;
      if (_userResponses[event.id] == responseType) {
        // If clicking the same response type, remove the response
        await SupabaseDatabase.instance.deleteEventResponse(
          event.id,
          userId,
        );
        setState(() {
          _userResponses[event.id] = null;
        });
      } else {
        // Create new response
        final response = EventResponse(
          eventId: event.id,
          userId: userId,
          responseType: responseType,
          createdAt: DateTime.now(),
        );
        await SupabaseDatabase.instance.upsertEventResponse(response);
        setState(() {
          _userResponses[event.id] = responseType;
        });
      }
      
      // Reload counts after response change
      final counts = await SupabaseDatabase.instance.getEventResponseCounts(event.id);
      if (mounted) {
        setState(() {
          _responseCounts[event.id] = counts;
        });
      }
      
      // Show celebration if new response
      if (isNew) {
        _triggerCelebration(responseType, event.id);
        

      }
    } catch (e) {
      // Error handling response silently
    }
  }

  void _triggerCelebration(EventResponseType type, int eventId) {
    setState(() {
      _showCelebration = true;
      _celebrationIcon = Icons.favorite;
      _celebrationColor = AppColours.heart;
      _celebratingEventId = eventId;
    });
  }

  // Filter panel methods
  void _openCategoryFilterPanel() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => CategoryFilterPanel(
        categories: _categories,
        selectedCategories: _selectedCategories,
      ),
    );
    if (result != null) _handleCategoriesSelected(result);
  }

  void _openDateFilterPanel() async {
    final result = await showModalBottomSheet<Map<String, DateTime?>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DateFilterPanel(
        fromDate: _fromDate,
        toDate: _toDate,
      ),
    );
    if (result != null) _handleDateChanged(result['from'], result['to']);
  }

  void _openDistanceFilterPanel() async {
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => LocationFilterPanel(
        distanceKm: _distanceKm,
        searchCenterLat: _searchCenterLat,
        searchCenterLng: _searchCenterLng,
      ),
    );
    if (result != null) {
      if (result.containsKey('clear')) {
        // User clicked Clear button
        _handleDistanceChanged(null, null, null);
      } else {
        // User clicked Apply button
        _handleDistanceChanged(result['distance'], result['searchCenterLat'], result['searchCenterLng']);
      }
    }
  }

  // Helper method to handle filter changes
  void _handleFilterChange(VoidCallback updateState) {
    setState(updateState);
    // Always scroll to top and hide back to top button immediately
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    _showBackToTopNotifier.value = false;
    _loadEvents(); // Reload from backend with new filters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && _scrollController.offset <= 0) {
        _showBackToTopNotifier.value = false;
      }
    });
  }

  // Filter change handlers
  void _handleCategoriesSelected(List<String> cats) {
    _handleFilterChange(() {
      _selectedCategories = cats;
      _resetPagination();
      // Clear responses when filters change
      _userResponses.clear();
      _friendsResponses.clear();
      _preloadedFriendsList = null;
    });
  }

  void _handleDistanceChanged(double? dist, double? searchCenterLat, double? searchCenterLng) {
    _handleFilterChange(() {
      _distanceKm = dist;
      _searchCenterLat = searchCenterLat;
      _searchCenterLng = searchCenterLng;
      _resetPagination();
      // Clear responses when filters change
      _userResponses.clear();
      _friendsResponses.clear();
      _preloadedFriendsList = null;
    });
  }

  void _handleDateChanged(DateTime? from, DateTime? to) {
    _handleFilterChange(() {
      _fromDate = from;
      _toDate = to;
      _resetPagination();
      // Clear responses when filters change
      _userResponses.clear();
      _friendsResponses.clear();
      _preloadedFriendsList = null;
    });
  }

  void _handleFreeFilterChanged(bool freeOnly) {
    _handleFilterChange(() {
      _freeOnly = freeOnly;
      _resetPagination();
      // Clear responses when filters change
      _userResponses.clear();
      _friendsResponses.clear();
      _preloadedFriendsList = null;
    });
  }

  void _handleSavedFilterChanged(bool savedOnly) {
    // Check if user is authenticated when trying to use saved filter
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated) {
      // Show auth flow screen for unauthenticated users
      AuthFlowScreen.push(context);
      return;
    }

    _handleFilterChange(() {
      _savedOnly = savedOnly;
      _resetPagination();
      // Clear responses when filters change
      _userResponses.clear();
      _friendsResponses.clear();
      _preloadedFriendsList = null;
    });
  }

  // Reset pagination when filters change
  void _resetPagination() {
    _currentOffset = 0;
    _hasMoreEvents = true;
    _isLoadingMore = false;
  }

  // Method to reset to event list view - called when Events tab is tapped
  void resetToEventList() {
    if (_isEventDetailsVisible) {
      setState(() {
        _isEventDetailsVisible = false;
        _selectedEvent = null;
      });
    } else {
      // Always scroll to top and hide back to top button immediately
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _showBackToTopNotifier.value = false;
      setState(() {
        // Clear responses when refreshing
        _userResponses.clear();
        _friendsResponses.clear();
        _preloadedFriendsList = null;
      });
      // Already on event list, so refresh
      _loadEvents();
      // Also check again after build in case of async timing
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients && _scrollController.offset <= 0) {
          _showBackToTopNotifier.value = false;
        }
      });
    }
  }

  // Method to navigate to a specific event by ID - used for deep links
  Future<void> navigateToEventById(String eventId) async {
    try {
      // First check if the event is already loaded
      final existingEvent = _events.firstWhere(
        (event) => event.id.toString() == eventId,
        orElse: () => throw Exception('Event not found in loaded events'),
      );
      
      _navigateToEventDetails(existingEvent);
    } catch (e) {
      // If event not found in loaded events, try to fetch it from database
      try {
        final event = await SupabaseDatabase.instance.getEvent(int.parse(eventId));
        if (event != null) {
          // Add to events list if not already there
          if (!_events.any((e) => e.id == event.id)) {
            setState(() {
              _events.add(event);
            });
          }
          _navigateToEventDetails(event);
        } else {
          // Show error message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Event not found'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error loading event'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }
}