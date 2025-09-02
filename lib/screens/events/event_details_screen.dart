// Flutter core
import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';



// Third-party packages
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_html/flutter_html.dart';


import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Local imports
import 'package:myarea_app/models/event_model.dart';
import 'package:myarea_app/models/event_response_model.dart';
import 'package:myarea_app/services/supabase_database.dart';

import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/main.dart';


import 'package:myarea_app/screens/auth/auth_flow_screen.dart';


import 'package:myarea_app/widgets/invite_friends_modal.dart';
import 'package:myarea_app/screens/events/heart_celebration.dart';
import 'package:myarea_app/styles/app_colours.dart';

String cleanDescription(String html) {
  // Remove <br> tags that immediately follow </p>
  html = html.replaceAll(RegExp(r'</p>\s*(<br\s*/?>\s*)+'), '</p>');
  // Remove <br> tags that immediately precede <p>
  html = html.replaceAll(RegExp(r'(<br\s*/?>\s*)+<p'), '<p');
  // Remove empty paragraphs (e.g., <p><br></p> or <p></p>)
  html = html.replaceAll(RegExp(r'<p>\s*(<br\s*/?>\s*)*\s*</p>'), '');

  // Add class to last <p> tag
  final matches = RegExp(r'<p[^>]*>').allMatches(html).toList();
  if (matches.isNotEmpty) {
    final lastMatch = matches.last;
    html = html.replaceRange(
      lastMatch.start,
      lastMatch.end,
      html.substring(lastMatch.start, lastMatch.end - 1) + ' class="last-paragraph">'
    );
  }
  return html;
}

class EventDetailsScreen extends StatefulWidget {
  final Event event;
  final String adminBaseUrl;
  final VoidCallback onBack;
  final EventResponse? preloadedUserResponse;
  final Map<EventResponseType, int>? preloadedResponseCounts;
  final Map<String, EventResponseType>? preloadedFriendsResponses;
  final List<dynamic>? preloadedAllFriends;
  final bool hideBackButton;

  const EventDetailsScreen({
    super.key,
    required this.event,
    required this.onBack,
    this.adminBaseUrl = 'http://localhost:5002',
    this.preloadedUserResponse,
    this.preloadedResponseCounts,
    this.preloadedFriendsResponses,
    this.preloadedAllFriends,
    this.hideBackButton = false, // New parameter to hide back button when called from map
  });

  @override
  State<EventDetailsScreen> createState() => _EventDetailsScreenState();
}

class _EventDetailsScreenState extends State<EventDetailsScreen> {
  late Event _event;
  EventResponse? _userResponse;
  bool _isLoading = false;
  bool _isDeleted = false;
  Map<EventResponseType, int> _responseCounts = {
    EventResponseType.interested: 0,
  };

  // Friends responses state
  Map<String, EventResponseType> _friendsResponses = {};
  bool _isLoadingFriends = false;
  // Friends user objects grouped by response type
  Map<EventResponseType, List<dynamic>> _friendsByResponseType = {
    EventResponseType.interested: [],
  };
  // All friends and those with no response (for preloading chat modal)
  List<dynamic> _allFriends = [];
  List<dynamic> _friendsNoResponse = [];

  // Celebration overlay state
  bool _showCelebration = false;
  IconData? _celebrationIcon;
  Color? _celebrationColor;

  // Description character limit
  static const int _descriptionCharLimit = 200;

  // Add a key to force rebuild of celebration widget
  Key _celebrationKey = UniqueKey();

  // Schedule display flags
  bool _hasMultipleTimes = false;
  bool _hasMultipleDates = false;

  // Swipe animation state
  double _dragOffset = 0.0;
  bool _isDragging = false;

  // Scroll controller for dynamic header
  late ScrollController _scrollController;
  bool _showTitleInHeader = false;
  bool _showTitleForModal = false;

  // Cache for image URL to avoid recalculation on every rebuild
  String? _cachedImageUrl;

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _scrollController = ScrollController();
    _scrollController.addListener(_onScroll);
    
    // Set pre-loaded data immediately in initState to prevent any flashing
    if (widget.preloadedUserResponse != null) {
      _userResponse = widget.preloadedUserResponse;
    }
    
    if (widget.preloadedResponseCounts != null) {
      _responseCounts = Map.from(widget.preloadedResponseCounts!);
    }
    
    if (widget.preloadedFriendsResponses != null) {
      _friendsResponses = Map.from(widget.preloadedFriendsResponses!);
    }
    
          if (widget.preloadedAllFriends != null) {
        _allFriends = List.from(widget.preloadedAllFriends!);
        // Build friends list immediately and synchronously to prevent flashing
        _buildFriendsByResponseTypeFromPreloadedSync();
        
        // Force a rebuild to ensure the UI shows the friends immediately
        if (mounted) {
          setState(() {});
        }
      }
    
    _initializeData();
  }

  Future<void> _initializeData() async {
    // Only show loading if we actually need to fetch data
    final needsFetching = widget.preloadedUserResponse == null ||
                         widget.preloadedResponseCounts == null ||
                         widget.preloadedFriendsResponses == null;
    
    if (needsFetching) {
      setState(() => _isLoading = true);
    }
    
    try {
      // Only fetch data that wasn't pre-loaded
      final futures = <Future<void>>[];
      
      if (widget.preloadedUserResponse == null) {
        futures.add(_loadUserResponse());
      }
      
      if (widget.preloadedResponseCounts == null) {
        futures.add(_loadResponseCounts());
      }
      
      if (widget.preloadedFriendsResponses == null) {
        futures.add(_loadFriendsResponses());
      }
      
      // Always load these as they're not pre-loaded
      futures.addAll([
        _loadEvent(),
        _loadAllFriendsList(),
      ]);
      
      // If we have pre-loaded friends responses, populate the full friend objects
      if (widget.preloadedFriendsResponses != null && widget.preloadedFriendsResponses!.isNotEmpty) {
        futures.add(_buildFriendsByResponseTypeFromPreloaded());
      } else {
        futures.add(_loadFriendsByResponseType());
      }
      
      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }
      
      // Compute friends with no response once both friends and responses are loaded
      _computeFriendsNoResponse();
    } finally {
      if (mounted && needsFetching) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadEvent() async {
    try {
      final event = await SupabaseDatabase.instance.getEvent(_event.id);
      if (mounted) {
        setState(() {
          if (event == null) {
            _isDeleted = true;
          } else {
            _event = event;
            _isDeleted = event.isDeleted;
            // Clear cached image URL when event changes
            _cachedImageUrl = null;
            // Reset schedule flags
            _hasMultipleTimes = false;
            _hasMultipleDates = false;
          }
        });
      }
    } catch (e) {
      print('Error loading event: $e');
      if (mounted) {
        setState(() {
          _isDeleted = true;
        });
      }
    }
  }

  Future<void> _loadUserResponse() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final userId = user.id;

    try {
      final response = await SupabaseDatabase.instance.getUserEventResponse(
        _event.id,
        userId,
      );
      if (mounted) {
        setState(() => _userResponse = response);
      }
    } catch (e) {
      print('Error loading user response: $e');
    }
  }

  Future<void> _loadResponseCounts() async {
    try {
      final counts = await SupabaseDatabase.instance.getEventResponseCounts(_event.id);
      if (mounted) {
        setState(() => _responseCounts = counts);
      }
    } catch (e) {
      print('Error loading response counts: $e');
    }
  }

  Future<void> _loadFriendsResponses() async {
    try {
      final responses = await SupabaseDatabase.instance.getEventFriendsResponses(_event.id);
      if (mounted) {
        setState(() => _friendsResponses = responses);
      }
    } catch (e) {
      print('Error loading friends responses: $e');
    }
  }

  Future<void> _loadFriendsByResponseType() async {
    try {
      // If we have pre-loaded friends responses, build the data structure from that
      if (widget.preloadedFriendsResponses != null && widget.preloadedFriendsResponses!.isNotEmpty) {
        await _buildFriendsByResponseTypeFromPreloaded();
      } else {
        // Fallback to database call if no pre-loaded data
        final result = await SupabaseDatabase.instance.getEventFriendsByResponseType(_event.id);
        if (mounted) {
          setState(() => _friendsByResponseType = result);
        }
      }
    } catch (e) {
      print('Error loading friends by response type: $e');
    }
  }

  void _buildFriendsByResponseTypeFromPreloadedSync() {
    try {
      // Use real friend objects from pre-loaded data to prevent any flashing
      final interested = <dynamic>[];
      
      if (widget.preloadedFriendsResponses != null && widget.preloadedAllFriends != null) {
        for (final entry in widget.preloadedFriendsResponses!.entries) {
          if (entry.value == EventResponseType.interested) {
            // Find the real friend object from the pre-loaded friends list
            try {
              final realFriend = widget.preloadedAllFriends!.firstWhere(
                (friend) => friend.id == entry.key,
              );
              interested.add(realFriend);
            } catch (e) {
              // Friend not found, continue
            }
          }
        }
      }

      // Set the friends list immediately to prevent flashing
      _friendsByResponseType = {
        EventResponseType.interested: interested,
      };
    } catch (e) {
      print('Error building friends by response type from preloaded data: $e');
    }
  }

  Future<void> _buildFriendsByResponseTypeFromPreloaded() async {
    try {
      // Get the current user's friends list
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      
      final friendsList = await SupabaseDatabase.instance.getFriendsList(user.id);
      if (friendsList.isEmpty) return;

      // Build the response type groups from pre-loaded data
      final interested = <dynamic>[];
      
      for (final friend in friendsList) {
        if (friend.id != null) {
          final responseType = widget.preloadedFriendsResponses![friend.id];
          if (responseType == EventResponseType.interested) {
            interested.add(friend);
          }
        }
      }

      if (mounted) {
        setState(() {
          _friendsByResponseType = {
            EventResponseType.interested: interested,
          };
        });
      }
    } catch (e) {
      print('Error building friends by response type from preloaded data: $e');
    }
  }

  Future<void> _loadAllFriendsList() async {
    try {
      // If we already have friends loaded, don't fetch again
      if (_allFriends.isNotEmpty) return;
      
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      final friends = await SupabaseDatabase.instance.getFriendsList(user.id);
      if (mounted) {
        setState(() {
          _allFriends = friends;
        });
      }
    } catch (e) {
      print('Error loading all friends list: $e');
    }
  }

  void _computeFriendsNoResponse() {
    try {
      if (_allFriends.isEmpty) {
        _friendsNoResponse = [];
        return;
      }
      final respondedIds = <String>{};
      for (final list in _friendsByResponseType.values) {
        for (final friend in list) {
          if (friend.id != null) respondedIds.add(friend.id);
        }
      }
      _friendsNoResponse = _allFriends.where((f) => !respondedIds.contains(f.id)).toList();
    } catch (e) {
      print('Error computing friends with no response: $e');
    }
  }

  void _onScroll() {
    // Show title in header when scrolled past the image
    final showTitle = _scrollController.offset > 180; // Adjusted threshold
    if (showTitle != _showTitleInHeader) {
      setState(() {
        _showTitleInHeader = showTitle;
      });
    }
  }

  void _showTitleInHeaderForModal(bool show) {
    setState(() {
      _showTitleForModal = show;
    });
  }

  Future<void> _handleResponse(EventResponseType responseType) async {
    // Check if user is authenticated
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated) {
      // Show auth flow screen for unauthenticated users
      AuthFlowScreen.push(context);
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      AuthFlowScreen.push(context);
      return;
    }
    final userId = user.id;

    // Reset celebration state immediately
    setState(() {
      _showCelebration = false;
      _celebrationKey = UniqueKey(); // Force new celebration instance
    });

    setState(() => _isLoading = true);
    try {
      bool isNew = _userResponse?.responseType != responseType;
      if (_userResponse?.responseType == responseType) {
        // If clicking the same response type, remove the response
        await SupabaseDatabase.instance.deleteEventResponse(
          _event.id,
          userId,
        );
        setState(() => _userResponse = null);
      } else {
        // Create new response without specifying an id
        final response = EventResponse(
          eventId: _event.id,
          userId: userId,
          responseType: responseType,
          createdAt: DateTime.now(),
        );
        await SupabaseDatabase.instance.upsertEventResponse(response);
        setState(() => _userResponse = response);
      }
      // Reload counts after response change
      await _loadResponseCounts();
      // Show celebration if new response
      if (isNew) {
        _triggerCelebration(responseType);
        

      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _triggerCelebration(EventResponseType type) {
    setState(() {
      _showCelebration = true;
      _celebrationIcon = Icons.favorite;
      _celebrationColor = AppColours.heart;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  // Calculate background opacity based on drag progress
  double _getBackgroundOpacity() {
    if (_dragOffset <= 0) {
      return 0.3; // Full opacity when not dragged or dragged left
    }
    
    // Make background completely transparent as soon as drag starts
    // This reveals the events list immediately
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    if (_isDeleted) {
      return Scaffold(
        backgroundColor: AppColours.background,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(40.0),
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              toolbarHeight: 40.0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: !widget.hideBackButton,
                                      leading: widget.hideBackButton ? null : IconButton(
                icon: Icon(Icons.arrow_back, color: AppColours.buttonPrimary),
                onPressed: widget.onBack,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
              ),
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.event_busy,
                  size: 64,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 24),
                Text(
                  'This event has been deleted',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'The event you\'re looking for is no longer available.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: widget.onBack,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: Colors.transparent,
                  ),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: Colors.transparent,
      child: Stack(
        children: [
        // Semi-transparent background overlay that fades as modal is dragged
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onBack,
            child: Container(
              color: Colors.black.withOpacity(_getBackgroundOpacity()),
            ),
          ),
        ),
        
        GestureDetector(
          onHorizontalDragStart: (details) {
            setState(() {
              _isDragging = true;
            });
          },
          onHorizontalDragUpdate: (details) {
            // Allow both directions but with resistance for leftward drag
            final screenWidth = MediaQuery.of(context).size.width;
            final newOffset = _dragOffset + details.delta.dx;
            
            if (newOffset >= 0) {
              // Rightward drag - normal movement with slight resistance
              setState(() {
                _dragOffset = newOffset.clamp(0.0, screenWidth * 0.8);
              });
            } else {
              // Leftward drag - add resistance (rubber band effect)
              final resistance = 0.3;
              setState(() {
                _dragOffset = newOffset * resistance;
              });
            }
          },
          onHorizontalDragEnd: (details) {
            setState(() {
              _isDragging = false;
            });
            
            final screenWidth = MediaQuery.of(context).size.width;
            final velocity = details.primaryVelocity ?? 0;
            final dragPercentage = _dragOffset / screenWidth;
            
            // More natural iOS-like dismissal logic
            final shouldDismiss = dragPercentage > 0.3 || // Dragged more than 30% of screen
                                 (dragPercentage > 0.1 && velocity > 500) || // Quick swipe with decent distance
                                 velocity > 1200; // Very fast swipe
            
            if (shouldDismiss && _dragOffset >= 0) {
              // Animate out with momentum-based duration
              final animationDuration = velocity > 800 
                  ? const Duration(milliseconds: 150)
                  : const Duration(milliseconds: 250);
              
              setState(() {
                _dragOffset = screenWidth;
              });
              
              // Call back after animation
              Future.delayed(animationDuration, () {
                if (mounted) widget.onBack();
              });
            } else {
              // Snap back with spring-like animation
              setState(() {
                _dragOffset = 0.0;
              });
            }
          },
          child: AnimatedContainer(
            duration: _isDragging ? Duration.zero : const Duration(milliseconds: 300),
            curve: _isDragging ? Curves.linear : Curves.fastOutSlowIn,
            transform: Matrix4.translationValues(_dragOffset, 0.0, 0.0),
            child: Container(
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              decoration: BoxDecoration(
                color: AppColours.background,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                children: [

                  
                  // App bar
                  PreferredSize(
                    preferredSize: const Size.fromHeight(40.0),
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: AppBar(
                        backgroundColor: AppColours.background,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                        toolbarHeight: 40.0,
                        scrolledUnderElevation: 0,
                        surfaceTintColor: Colors.transparent,
                        automaticallyImplyLeading: !widget.hideBackButton,
                        leading: widget.hideBackButton ? null : Container(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.only(left: 2),
                          width: 48,
                          child: IconButton(
                            icon: Icon(Icons.arrow_back, color: AppColours.buttonPrimary),
                            onPressed: widget.onBack,
                            splashColor: Colors.transparent,
                            highlightColor: Colors.transparent,
                            hoverColor: Colors.transparent,
                          ),
                        ),
                        leadingWidth: widget.hideBackButton ? 0 : 48,
                        titleSpacing: widget.hideBackButton ? 12 : 0,
                        title: (_showTitleInHeader || _showTitleForModal) ? AnimatedOpacity(
                          opacity: (_showTitleInHeader || _showTitleForModal) ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            _event.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ) : null,
                        centerTitle: false,
                        actions: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: _isLoading ? null : () => _handleResponse(EventResponseType.interested),
                                child: Container(
                                  margin: EdgeInsets.only(right: 0),
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    _userResponse?.responseType == EventResponseType.interested
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    color: _userResponse?.responseType == EventResponseType.interested ? AppColours.heart : Colors.grey[600],
                                    size: 24,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: null,
                                child: Container(
                                  margin: EdgeInsets.only(right: 10),
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(Icons.share, color: Colors.grey[400], size: 24),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Content
                  Expanded(
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const ClampingScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.of(context).padding.bottom + 32, // Safe area + space for floating feedback button
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (_event.coverPhoto != null && _event.coverPhoto!.isNotEmpty)
                                  _buildEventImage(),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildEventDetailsSection(context),
                                    const SizedBox(height: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                      child: _buildCategoryTags(),
                                    ),
                                    const SizedBox(height: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                      child: _buildDescriptionSection(),
                                    ),
                                    const SizedBox(height: 12),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                                      child: _buildFriendsResponsesSection(),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showCelebration && _celebrationIcon != null)
          HeartCelebration(
            key: _celebrationKey, // Add key to force rebuild
            show: _showCelebration,
            icon: _celebrationIcon!,
            color: _celebrationColor ?? Colors.red,
            onEnd: () {
              if (mounted) setState(() => _showCelebration = false);
            },
            originFromBottomNav: true, // Add parameter to indicate origin from bottom nav
          ),
        ],
      ),
    );
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
        print('Error parsing crop data for event ${event.id}: $e');
      }
    }
    
    // Fallback to original cover photo
    final fallbackUrl = event.coverPhoto!.startsWith('http') 
        ? event.coverPhoto! 
        : '${widget.adminBaseUrl}${event.coverPhoto}';
    return fallbackUrl;
  }

  Widget _buildEventImage() {
    // Use cached image URL if available, otherwise calculate and cache it
    _cachedImageUrl ??= _getBestImageUrl(_event);
    final imageUrl = _cachedImageUrl;
    
    if (imageUrl == null) {
      return Container(
        height: 160,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey[200],
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

    return Container(
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
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
            ),
          ),
        ),
        errorWidget: (context, url, error) {
          // If this was a cropped image that failed, try to fall back to original
          if (url != _event.coverPhoto && _event.coverPhoto != null && _event.coverPhoto!.isNotEmpty) {
            final fallbackUrl = _event.coverPhoto!.startsWith('http') 
                ? _event.coverPhoto! 
                : '${widget.adminBaseUrl}${_event.coverPhoto}';
            
            return CachedNetworkImage(
              imageUrl: fallbackUrl,
              fit: BoxFit.cover,
              placeholder: (context, fallbackUrl) => Container(
                color: Colors.grey[200],
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
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
    );
  }

  Widget _buildPlaceholderImage(IconData icon) {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Icon(
          icon,
          size: 40,
          color: Colors.grey[400],
        ),
      ),
    );
  }

  Widget _buildTitleSection(BuildContext context) {
    return const SizedBox.shrink();
  }

  Widget _buildCategoryTags() {
    if (_event.category.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: _event.category.map((cat) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _getCategoryIconColor(cat).withOpacity(0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getCategoryIconColor(cat).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _getCategoryIcon(cat),
              const SizedBox(width: 4),
              Text(
                cat,
                style: TextStyle(
                  color: _getCategoryIconColor(cat),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
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
        return AppColours.buttonPrimary;
    }
  }

  // Helper to get category icon
  Widget _getCategoryIcon(String category) {
    final color = _getCategoryIconColor(category);
    final size = 12.0;
    
    switch (category.toLowerCase()) {
      case 'exhibitions':
        return Icon(Icons.palette, size: size, color: color);
      case 'theatre, dance & film':
        return Icon(Icons.theater_comedy, size: size, color: color);
      case 'music':
        return Icon(Icons.music_note, size: size, color: color);
      case 'tours':
        return Icon(Icons.directions_walk, size: size, color: color);
      case 'markets':
        return Icon(Icons.shopping_basket, size: size, color: color);
      case 'nightlife':
        return Icon(Icons.nightlife, size: size, color: color);
      case 'food & drink':
        return Icon(Icons.restaurant, size: size, color: color);
      case 'dating':
        return Icon(Icons.favorite, size: size, color: color);
      case 'comedy':
        return Icon(Icons.emoji_emotions, size: size, color: color);
      case 'talks, courses & workshops':
        return Icon(Icons.record_voice_over, size: size, color: color);
      case 'health & fitness':
        return Icon(Icons.fitness_center, size: size, color: color);
      default:
        return Icon(Icons.category, size: size, color: color);
    }
  }

  Widget _buildDescriptionSection() {
    final cleanedDescription = cleanDescription(_event.description);
    final plainText = cleanedDescription.replaceAll(RegExp(r'<[^>]*>'), '');
    final isLong = plainText.length > _descriptionCharLimit;
    
    // Calculate collapsed height more accurately
    const collapsedLines = 6;
    const lineHeight = 1.4;
    const fontSize = 13.0;
    final collapsedHeight = fontSize * lineHeight * collapsedLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About This Event',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.grey[900],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        
        // Always show collapsed version
        Container(
          height: collapsedHeight,
          child: ClipRect(
            child: Html(
              data: cleanedDescription,
              style: {
                'body': Style(
                  padding: HtmlPaddings.zero,
                  margin: Margins.zero,
                  fontSize: FontSize(fontSize),
                  lineHeight: LineHeight(lineHeight),
                  color: Colors.black87,
                ),
                'p': Style(
                  margin: Margins.only(bottom: 16),
                  padding: HtmlPaddings.zero,
                  fontSize: FontSize(12.5),
                ),
                'p.last-paragraph': Style(
                  margin: Margins.only(bottom: 0),
                  padding: HtmlPaddings.zero,
                  fontSize: FontSize(12.5),
                ),
                'ul': Style(
                  margin: Margins.only(left: -12, bottom: 8),
                  fontSize: FontSize(12.5),
                ),
                'ol': Style(
                  margin: Margins.only(left: -12, bottom: 8),
                  fontSize: FontSize(12.5),
                ),
                'li': Style(
                  margin: Margins.only(bottom: 4),
                  fontSize: FontSize(12.5),
                ),
                'a': Style(
                  color: AppColours.buttonPrimary,
                  textDecoration: TextDecoration.underline,
                  fontSize: FontSize(12.5),
                ),
                'strong': Style(
                  fontWeight: FontWeight.bold,
                  fontSize: FontSize(12.5),
                ),
                'em': Style(
                  fontStyle: FontStyle.italic,
                  fontSize: FontSize(12.5),
                ),
              },
              onLinkTap: (url, _, __) {
                if (url != null) {
                  _launchWebsite(url);
                }
              },
            ),
          ),
        ),
        
        if (isLong)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _showDescriptionModal();
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Read more',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                    ),
                  ],
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: Colors.transparent,
                  foregroundColor: AppColours.buttonPrimary,
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildFriendsResponsesSection() {
    final interestedFriends = _friendsByResponseType[EventResponseType.interested] ?? [];
    final hasFriends = _allFriends.isNotEmpty;
    final hasInterestedFriends = interestedFriends.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Friends',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.grey[900],
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        
        if (!hasFriends)
          // No friends added - show CTA to add friends
          Row(
            children: [
              Icon(
                Icons.people_outline,
                size: 20,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 12),
                             Expanded(
                 child: Text(
                   'Add friends to see who\'s interested in events',
                   style: TextStyle(
                     color: Colors.grey.shade800,
                     fontSize: 13,
                   ),
                 ),
               ),
              const SizedBox(width: 12),
                             ElevatedButton.icon(
                 onPressed: () {
                   // Check if user is authenticated before navigating to friends tab
                   final authProvider = Provider.of<AuthProvider>(context, listen: false);
                   if (!authProvider.isAuthenticated) {
                     // Show auth flow screen for unauthenticated users
                     AuthFlowScreen.push(context);
                     return;
                   }
                   // Navigate to friends tab
                   MainScreen.navigateToTab(context, 2);
                 },
                 style: ElevatedButton.styleFrom(
                   backgroundColor: AppColours.background,
                   foregroundColor: AppColours.buttonPrimary,
                   padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 8),
                   shape: RoundedRectangleBorder(
                     borderRadius: BorderRadius.circular(6),
                   ),
                   side: BorderSide(color: AppColours.buttonPrimary),
                   splashFactory: NoSplash.splashFactory,
                   overlayColor: Colors.transparent,
                 ),
                 icon: const Icon(Icons.person_add, size: 16),
                 label: const Text(
                   'Add Friends',
                   style: TextStyle(
                     fontSize: 12,
                     fontWeight: FontWeight.w600,
                   ),
                 ),
               ),
            ],
          )
        else if (!hasInterestedFriends)
          // Has friends but none interested - show no response message with compact chat button
          Row(
            children: [
              Icon(
                Icons.people_outline,
                size: 20,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 12),
                             Expanded(
                 child: Text(
                   'No friends have responded to this event yet',
                   style: TextStyle(
                     color: Colors.grey.shade800,
                     fontSize: 13,
                   ),
                 ),
               ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _showInviteFriendsModal,
                icon: const Icon(Icons.message, size: 16),
                label: const Text(
                  'Start a Chat',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColours.background,
                  foregroundColor: AppColours.buttonPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  side: BorderSide(color: AppColours.buttonPrimary),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: Colors.transparent,
                ),
              ),
            ],
          )
        else
          // Has interested friends - show friends with compact chat button
          Padding(
            padding: const EdgeInsets.only(top: 0),
            child: Row(
              children: [
                Expanded(
                  child: _buildFriendsAvatarsRow('Interested', interestedFriends, AppColours.heart, Icons.favorite),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _showInviteFriendsModal,
                  icon: const Icon(Icons.message, size: 16),
                  label: const Text(
                    'Start a Chat',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColours.background,
                    foregroundColor: AppColours.buttonPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    side: BorderSide(color: AppColours.buttonPrimary),
                    splashFactory: NoSplash.splashFactory,
                    overlayColor: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildFriendsAvatarsRow(String label, List<dynamic> friends, Color color, IconData icon) {
    // Show only up to 3 friends, with +X more indicator
    final displayFriends = friends.take(3).toList();
    final remainingCount = friends.length - 3;
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 36,
            child: Row(
              children: [
                ...displayFriends.map((friend) {
                  final hasValidFirstName = friend.firstName != null && friend.firstName.isNotEmpty;
                  final hasValidLastName = friend.lastName != null && friend.lastName.isNotEmpty;
                  final hasValidUsername = friend.username != null && friend.username.isNotEmpty;
                  
                  final initials = (hasValidFirstName && hasValidLastName)
                      ? '${friend.firstName[0]}${friend.lastName[0]}'
                      : hasValidUsername ? friend.username[0] : '?';
                  final displayName = (hasValidFirstName && hasValidLastName)
                      ? '${friend.firstName} ${friend.lastName}'
                      : hasValidUsername ? friend.username : 'Loading...';
                  
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: displayName,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: color.withOpacity(0.15),
                        child: Text(
                          initials.toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                if (remainingCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: color.withOpacity(0.15),
                      child: Text(
                        '+$remainingCount',
                        style: TextStyle(
                          color: color,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showInviteFriendsModal() {
    // Check if user is authenticated before showing the modal
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isAuthenticated) {
      // Show auth flow screen for unauthenticated users
      AuthFlowScreen.push(context);
      return;
    }
    
    // Show title in header when modal opens
    _showTitleInHeaderForModal(true);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => InviteFriendsModal(
        event: _event,
        preloadedAllFriends: _allFriends,
        preloadedFriendsByResponse: _friendsByResponseType,
        preloadedFriendsNoResponse: _friendsNoResponse,
      ),
    ).whenComplete(() {
      // Hide title in header when modal closes
      _showTitleInHeaderForModal(false);
    });
  }



  Widget _buildEventDetailsSection(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 200),
            child: Text(
              _event.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Date & Time',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          _buildDateTimeCard(context),
          const SizedBox(height: 10),
          Text(
            'Ticket Price',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          _buildPriceCard(context),
          const SizedBox(height: 10),
          Text(
            'Location',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Colors.grey[800],
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          _buildLocationSection(context),
          if (_event.website.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildWebsiteButtons(context),
          ],
        ],
      ),
    );
  }

  Widget _buildDateTimeCard(BuildContext context) {
    final startDateTime = tz.TZDateTime.from(_event.dateTime, tz.getLocation(_event.timezone));
    final endDateTime = tz.TZDateTime.from(_event.endDateTime, tz.getLocation(_event.timezone));

    final isSameDay = startDateTime.year == endDateTime.year &&
        startDateTime.month == endDateTime.month &&
        startDateTime.day == endDateTime.day;

    // Check if event has schedule data
    final hasScheduleData = _event.scheduleData != null;
    
    String dateText;
    String? timeText;
    bool hasMultipleTimes = false;
    bool hasMultipleDates = false;
    
    if (hasScheduleData) {
      final scheduleData = _event.scheduleData!;
      final recurring = scheduleData['recurring'] as Map<String, dynamic>?;
      final single = scheduleData['single'];
      final exceptions = scheduleData['exceptions'] as List<dynamic>?;
      
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
      
      // Check if it has multiple specific dates (even if single sessions)
      final hasMultipleDates = single is List && single.length > 1;
      
      if (isSameDay) {
        dateText = DateFormat('EEE, d MMM yy').format(startDateTime);
        if (isSingleSession && sessionTime != null) {
          // Same day, single session with time
          timeText = sessionTime;
        } else if (hasRecurring || hasMultipleSessions) {
          // Same day, multiple sessions
          timeText = 'Multiple times';
          _hasMultipleTimes = true;
        }
              } else {
          // Different start and end dates
          dateText = '${DateFormat('EEE, d MMM yy').format(startDateTime)} - ${DateFormat('EEE, d MMM yy').format(endDateTime)}';
          if (hasRecurring || hasMultipleSessions || hasMultipleDates) {
            // Date range with multiple sessions or multiple specific dates
            timeText = 'Multiple dates';
            _hasMultipleDates = true;
          }
        }
    } else {
      // No schedule data, use original logic
      if (isSameDay) {
        dateText = DateFormat('EEE, d MMM yy').format(startDateTime);
        timeText = '${DateFormat('h:mm a').format(startDateTime)} - ${DateFormat('h:mm a').format(endDateTime)}';
      } else {
        // Multi-day events without schedule data should show "Multiple dates"
        dateText = '${DateFormat('EEE, d MMM yy').format(startDateTime)} - ${DateFormat('EEE, d MMM yy').format(endDateTime)}';
        timeText = 'Multiple dates';
        _hasMultipleDates = true;
      }
    }

    return Row(
      children: [
        Icon(
          Icons.calendar_today,
          size: 22,
          color: AppColours.titleAccent,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            timeText != null && timeText != 'Multiple times' && timeText != 'Multiple dates'
                ? '$dateText • $timeText'
                : dateText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
            ),
          ),
        ),
        if (_hasMultipleTimes)
          GestureDetector(
            onTap: () => _showScheduleModal(),
            child: Text(
              'Multiple times',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColours.buttonPrimary,
              ),
            ),
          ),
        if (_hasMultipleDates)
          GestureDetector(
            onTap: () => _showScheduleModal(),
            child: Text(
              'Multiple dates',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColours.buttonPrimary,
              ),
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

  void _showScheduleModal() {
    // Show title in header when modal opens
    _showTitleInHeaderForModal(true);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ScheduleModal(event: _event),
    ).whenComplete(() {
      // Hide title in header when modal closes
      _showTitleInHeaderForModal(false);
    });
  }

  Widget _buildPriceCard(BuildContext context) {
    final price = _event.ticketPrice;
    final variable = _event.variable;
    String priceText;
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
          size: 22,
          color: const Color(0xFFFF7043),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                priceText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[800],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWebsiteButtons(BuildContext context) {
    final hasWebsite = _event.website.isNotEmpty;
    
    if (!hasWebsite) {
      return const SizedBox.shrink();
    }

    Widget buildButton(String text, String url, {bool isPrimary = false}) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _launchWebsite(url),
          style: ElevatedButton.styleFrom(
            backgroundColor: isPrimary ? AppColours.buttonPrimary : Colors.white,
            foregroundColor: isPrimary ? Colors.white : AppColours.buttonPrimary,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: isPrimary ? BorderSide.none : BorderSide(color: AppColours.buttonPrimary),
            ),
            splashFactory: NoSplash.splashFactory,
            overlayColor: Colors.transparent,
          ),
          icon: const Icon(Icons.public),
          label: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return buildButton('Visit Website', _event.website, isPrimary: true);
  }

  Future<void> _launchWebsite(String website) async {
    final url = website.startsWith('http')
        ? website
        : 'https://$website';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  void _showDescriptionModal() {
    // Show title in header when modal opens
    _showTitleInHeaderForModal(true);
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DescriptionModal(
        event: _event,
        adminBaseUrl: widget.adminBaseUrl,
      ),
    ).whenComplete(() {
      // Hide title in header when modal closes
      _showTitleInHeaderForModal(false);
    });
  }

  Widget _buildLocationSection(BuildContext context) {
    // Build the full location text with venue and address
    String locationText = '';
    
    if (_event.venue != null && _event.venue!.isNotEmpty) {
      // Check if the address already starts with the venue name
      final venueName = _event.venue!.trim();
      final address = _event.address.trim();
      
      // Check if address starts with venue (case insensitive)
      if (address.toLowerCase().startsWith(venueName.toLowerCase())) {
        // Address already contains venue, just use the address
        locationText = address;
      } else {
        // Add venue and address with comma separator
        locationText = venueName;
        if (address.isNotEmpty) {
          locationText += ', $address';
        }
      }
    } else {
      locationText = _event.address;
    }
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.location_on,
          size: 22,
          color: AppColours.buttonPrimary,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            locationText,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () async {
            final encoded = Uri.encodeComponent(locationText);
            final url = 'https://www.google.com/maps/search/?api=1&query=$encoded';
            if (await canLaunchUrl(Uri.parse(url))) {
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            }
          },
          child: Icon(
            Icons.open_in_new,
            size: 18,
            color: AppColours.buttonPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSection(BuildContext context, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 22,
          color: Theme.of(context).primaryColor,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.grey[800],
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}


class _DescriptionModal extends StatelessWidget {
  final Event event;
  final String adminBaseUrl;

  const _DescriptionModal({
    required this.event,
    required this.adminBaseUrl,
  });

  @override
  Widget build(BuildContext context) {
    final cleanedDescription = cleanDescription(event.description);
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'About This Event',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          const Divider(height: 1),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Html(
                data: cleanedDescription,
                style: {
                  'body': Style(
                    padding: HtmlPaddings.zero,
                    margin: Margins.zero,
                    fontSize: FontSize(13),
                    lineHeight: LineHeight(1.5),
                    color: Colors.black87,
                  ),
                  'p': Style(
                    margin: Margins.only(bottom: 16),
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(13),
                  ),
                  'p.last-paragraph': Style(
                    margin: Margins.only(bottom: 0),
                    padding: HtmlPaddings.zero,
                    fontSize: FontSize(13),
                  ),
                  'ul': Style(
                    margin: Margins.only(left: -12, bottom: 16),
                    fontSize: FontSize(13),
                  ),
                  'ol': Style(
                    margin: Margins.only(left: -12, bottom: 16),
                    fontSize: FontSize(13),
                  ),
                  'li': Style(
                    margin: Margins.only(bottom: 8),
                    fontSize: FontSize(13),
                  ),
                  'a': Style(
                    color: AppColours.buttonPrimary,
                    textDecoration: TextDecoration.underline,
                    fontSize: FontSize(13),
                  ),
                  'strong': Style(
                    fontWeight: FontWeight.bold,
                    fontSize: FontSize(13),
                  ),
                  'em': Style(
                    fontStyle: FontStyle.italic,
                    fontSize: FontSize(13),
                  ),
                  'h1': Style(
                    fontSize: FontSize(16),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(bottom: 16, top: 24),
                  ),
                  'h2': Style(
                    fontSize: FontSize(15),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(bottom: 12, top: 20),
                  ),
                  'h3': Style(
                    fontSize: FontSize(13),
                    fontWeight: FontWeight.bold,
                    margin: Margins.only(bottom: 10, top: 16),
                  ),
                },
                onLinkTap: (url, _, __) {
                  if (url != null) {
                    _launchWebsite(url);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchWebsite(String website) async {
    final url = website.startsWith('http')
        ? website
        : 'https://$website';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }
}

class _ScheduleModal extends StatelessWidget {
  final Event event;

  const _ScheduleModal({required this.event});

  @override
  Widget build(BuildContext context) {
    final scheduleData = event.scheduleData;
    if (scheduleData == null) {
      return Container(
        height: 200,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: const Center(
          child: Text('No schedule information available'),
        ),
      );
    }

    final recurring = scheduleData['recurring'] as Map<String, dynamic>?;
    final single = scheduleData['single'];
    final exceptions = scheduleData['exceptions'] as List<dynamic>?;

    // Check if sections have content
    final hasSingleSessions = single != null && 
        ((single is Map<String, dynamic>) || (single is List && single.isNotEmpty));
    final hasRecurringSessions = recurring != null && recurring.isNotEmpty;
    final hasExceptions = exceptions != null && exceptions.isNotEmpty;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 5,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              'Event Schedule',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[900],
              ),
            ),
          ),
          
          const SizedBox(height: 8),
          
          const Divider(height: 1),
          
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Overall date range at the top
                  _buildOverallDateRange(),
                  const SizedBox(height: 24),
                  
                  // Only show sections that have content
                  if (hasSingleSessions) _buildSingleSessions(single),
                  if (hasRecurringSessions) ...[
                    if (hasSingleSessions) const SizedBox(height: 24),
                    _buildRecurringSessions(recurring!),
                  ],
                  if (hasExceptions) ...[
                    if (hasSingleSessions || hasRecurringSessions) 
                      const SizedBox(height: 24),
                    _buildExceptions(exceptions!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverallDateRange() {
    final startDateTime = tz.TZDateTime.from(event.dateTime, tz.getLocation(event.timezone));
    final endDateTime = tz.TZDateTime.from(event.endDateTime, tz.getLocation(event.timezone));
    
    final isSameDay = startDateTime.year == endDateTime.year &&
        startDateTime.month == endDateTime.month &&
        startDateTime.day == endDateTime.day;

    final dateTitle = isSameDay
        ? DateFormat('EEE, d MMM yy').format(startDateTime)
        : '${DateFormat('EEE, d MMM yy').format(startDateTime)} - ${DateFormat('EEE, d MMM yy').format(endDateTime)}';

    return Text(
      dateTitle,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.grey[900],
      ),
    );
  }

  Widget _buildSingleSessions(dynamic single) {
    List<Map<String, dynamic>> sessions = [];
    
    if (single is Map<String, dynamic>) {
      sessions = [single];
    } else if (single is List) {
      sessions = single.cast<Map<String, dynamic>>();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Specific Dates',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[900],
          ),
        ),
        const SizedBox(height: 12),
        ...sessions.map((session) => _buildSessionCard(session, isRecurring: false)),
      ],
    );
  }

  Widget _buildRecurringSessions(Map<String, dynamic> recurring) {
    // Group days by their open/close rule (same logic as events.html)
    final dayOrder = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final weekOrder = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    
    Map<String, List<String>> ruleToDays = {};
    
    for (final day in dayOrder) {
      if (recurring.containsKey(day)) {
        final rule = recurring[day] as Map<String, dynamic>;
        final open = rule['open'] as String?;
        final close = rule['close'] as String?;
        if (open != null && close != null) {
          final key = '$open-$close';
          ruleToDays.putIfAbsent(key, () => []);
          ruleToDays[key]!.add(day.substring(0, 1).toUpperCase() + day.substring(1));
        }
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recurring Schedule',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[900],
          ),
        ),
        const SizedBox(height: 12),
        ...ruleToDays.entries.map((entry) {
          final open = entry.key.split('-')[0];
          final close = entry.key.split('-')[1];
          final days = entry.value;
          
          String dayText;
          if (days.length == weekOrder.length) {
            dayText = 'Daily';
          } else if (days.length == 5 && days.contains('Monday') && days.contains('Tuesday') && 
                     days.contains('Wednesday') && days.contains('Thursday') && days.contains('Friday')) {
            dayText = 'Weekdays';
          } else if (days.length == 2 && days.contains('Saturday') && days.contains('Sunday')) {
            dayText = 'Weekends';
          } else {
            // Group consecutive days
            dayText = _groupConsecutiveDays(days, weekOrder);
          }
          
          return _buildRecurringRuleCard(dayText, open, close);
        }),
      ],
    );
  }

  String _groupConsecutiveDays(List<String> days, List<String> weekOrder) {
    if (days.isEmpty) return '';
    if (days.length == 1) return days.first;
    
    // Sort days according to week order
    days.sort((a, b) => weekOrder.indexOf(a).compareTo(weekOrder.indexOf(b)));
    
    List<String> groups = [];
    List<String> currentGroup = [days.first];
    
    for (int i = 1; i < days.length; i++) {
      final currentDay = days[i];
      final previousDay = days[i - 1];
      final currentIndex = weekOrder.indexOf(currentDay);
      final previousIndex = weekOrder.indexOf(previousDay);
      
      // Check if consecutive (accounting for week wrap-around)
      bool isConsecutive = false;
      if (currentIndex == previousIndex + 1) {
        isConsecutive = true;
      } else if (previousIndex == weekOrder.length - 1 && currentIndex == 0) {
        // Sunday to Monday
        isConsecutive = true;
      }
      
      if (isConsecutive) {
        currentGroup.add(currentDay);
      } else {
        // End current group and start new one
        groups.add(_formatDayGroup(currentGroup));
        currentGroup = [currentDay];
      }
    }
    
    // Add the last group
    groups.add(_formatDayGroup(currentGroup));
    
    return groups.join(', ');
  }

  String _formatDayGroup(List<String> days) {
    if (days.length == 1) return days.first;
    if (days.length == 2) return '${days.first}, ${days.last}';
    return '${days.first}-${days.last}';
  }

  Widget _buildRecurringRuleCard(String dayText, String open, String close) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.repeat, color: AppColours.buttonPrimary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayText,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  '${_formatTime(open)} - ${_formatTime(close)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExceptions(List<dynamic> exceptions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Exceptions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey[900],
          ),
        ),
        const SizedBox(height: 12),
        ...exceptions.map((exception) => _buildExceptionCard(exception)),
      ],
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, {required bool isRecurring}) {
    final date = session['date'] as String?;
    final open = session['open'] as String?;
    final close = session['close'] as String?;
    final closed = session['closed'] as bool?;

    if (closed == true) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(Icons.block, color: Colors.grey[600], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (date != null)
                    Text(
                      _formatDate(date),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  Text(
                    'Closed',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.access_time, color: AppColours.titleAccent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date != null)
                  Text(
                    _formatDate(date),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                if (open != null && close != null)
                  Text(
                    '${_formatTime(open)} - ${_formatTime(close)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildExceptionCard(dynamic exception) {
    final date = exception['date'] as String?;
    final open = exception['open'] as String?;
    final close = exception['close'] as String?;
    final closed = exception['closed'] as bool?;
    final note = exception['note'] as String?;

    if (closed == true) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.block, color: Colors.red[600], size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (date != null)
                    Text(
                      _formatDate(date),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.red[800],
                      ),
                    ),
                  Text(
                    'Exception: Closed',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.red[600],
                    ),
                  ),
                  if (note != null && note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        note,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule, color: const Color(0xFFFF7043), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (date != null)
                  Text(
                    _formatDate(date),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[800],
                    ),
                  ),
                if (open != null && close != null)
                  Text(
                    'Exception: ${_formatTime(open)} - ${_formatTime(close)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange[800],
                    ),
                  ),
                if (note != null && note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      note,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String timeString) {
    // Convert 24-hour format to 12-hour format
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
      return timeString;
    }
    return timeString;
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('EEE, d MMM yy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatDayName(String day) {
    // Convert day abbreviation to full name with proper capitalization
    switch (day.toLowerCase()) {
      case 'mon':
        return 'Monday';
      case 'tue':
        return 'Tuesday';
      case 'wed':
        return 'Wednesday';
      case 'thu':
        return 'Thursday';
      case 'fri':
        return 'Friday';
      case 'sat':
        return 'Saturday';
      case 'sun':
        return 'Sunday';
      default:
        // If it's already a full day name, capitalize it properly
        if (day.length > 3) {
          return day[0].toUpperCase() + day.substring(1).toLowerCase();
        }
        return day;
    }
  }
}

 