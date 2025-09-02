import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:myarea_app/services/auth_storage_service.dart';
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/models/user_model.dart' as app;
import 'package:profanity_filter/profanity_filter.dart';
import 'package:myarea_app/models/friend_request_model.dart';
import 'package:myarea_app/models/event_response_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:supabase_flutter/supabase_flutter.dart' show OAuthProvider;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:myarea_app/main.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:convert' show base64Url;
import 'dart:math' show Random;
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType, PostgresChangePayload;


class AuthProvider with ChangeNotifier {
  final ProfanityFilter _profanityFilter = ProfanityFilter();
  app.User? _currentUser;
  bool _isLoading = false;
  String _errorMessage = '';
  String _ssoErrorMessage = '';
  bool _shouldRefreshMap = false;
  String? _loginEmail;
  bool _resumeCheckInProgress = false;

  Completer<bool>? _authCompleter;
  
  // Friend-related state
  List<FriendRequest> _pendingFriendRequests = [];
  List<FriendRequest> _sentFriendRequests = [];
  List<app.User> _friendsList = [];
  bool _isLoadingFriends = false;
  
  // Global real-time listeners for friend requests
  RealtimeChannel? _globalFriendRequestChannel;
  RealtimeChannel? _globalFriendRequestSenderChannel;
  
  // Callback for friend request accepted notifications
  Function(String)? _onFriendRequestAccepted;
  
  // Getters
  app.User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  String get ssoErrorMessage => _ssoErrorMessage;
  bool get shouldRefreshMap => _shouldRefreshMap;
  String? get loginEmail => _loginEmail;
  
  // Friend-related getters
  List<FriendRequest> get pendingFriendRequests => _pendingFriendRequests;
  List<FriendRequest> get sentFriendRequests => _sentFriendRequests;
  List<app.User> get friendsList => _friendsList;
  bool get isLoadingFriends => _isLoadingFriends;
  
  // Setter for friend request accepted callback
  set onFriendRequestAccepted(Function(String)? callback) {
    _onFriendRequestAccepted = callback;
  }
  
  // Constructor - check if user is already logged in
  AuthProvider() {
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    try {
      // Generate a new PKCE verifier on startup using the centralized service
      final authStorage = AuthStorageService();
      await authStorage.generateAndStoreVerifier();
      
      // Then check login state
      await checkLoginState();
    } catch (e) {
      print('Error initializing auth: $e');
    }
  }

  // Setup global real-time listeners for friend requests
  void _setupGlobalFriendRequestListeners() {
    if (_currentUser == null) return;
    
    print('🔔 AuthProvider: Setting up global friend request listeners for user: ${_currentUser!.id}');
    
    // Clean up existing listeners first
    _cleanupGlobalFriendRequestListeners();
    
    // Setup receiver listener
    _globalFriendRequestChannel = Supabase.instance.client
        .channel('global:friend_requests')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'friend_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: _currentUser!.id!,
          ),
          callback: (payload) {
            print('🔔 Global Realtime: INSERT detected, refreshing friend data');
            refreshFriendData();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'friend_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: _currentUser!.id!,
          ),
          callback: (payload) {
            print('🔔 Global Realtime: DELETE detected, refreshing friend data');
            refreshFriendData();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'friend_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: _currentUser!.id!,
          ),
          callback: (payload) {
            print('🔔 Global Realtime: UPDATE detected, refreshing friend data');
            refreshFriendData();
          },
        )
        .subscribe();

    // Setup sender listener
    _globalFriendRequestSenderChannel = Supabase.instance.client
        .channel('global:friend_requests_sender')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'friend_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'sender_id',
            value: _currentUser!.id!,
          ),
          callback: (payload) {
            print('🔔 Global Sender Realtime: UPDATE event received!');
            final oldStatus = payload.oldRecord['status'];
            final newStatus = payload.newRecord['status'];
            print('🔔 Global Sender Realtime: Status changed from $oldStatus to $newStatus');
            if ((oldStatus == 'pending' || oldStatus == null) && (newStatus == 'accepted' || newStatus == 'rejected')) {
              print('🔔 Global Sender Realtime: Friend request status changed, refreshing all friend data');
              refreshFriendData();
              
              // Show notification for accepted friend requests
              if (newStatus == 'accepted') {
                _showFriendRequestAcceptedNotification(payload);
              }
            }
          },
        )
        .subscribe();
  }

  // Cleanup global real-time listeners
  void _cleanupGlobalFriendRequestListeners() {
    if (_globalFriendRequestChannel != null) {
      print('🔔 AuthProvider: Cleaning up global friend request channel');
      Supabase.instance.client.removeChannel(_globalFriendRequestChannel!);
      _globalFriendRequestChannel = null;
    }
    if (_globalFriendRequestSenderChannel != null) {
      print('🔔 AuthProvider: Cleaning up global friend request sender channel');
      Supabase.instance.client.removeChannel(_globalFriendRequestSenderChannel!);
      _globalFriendRequestSenderChannel = null;
    }
  }

  // Show notification for accepted friend requests
  void _showFriendRequestAcceptedNotification(PostgresChangePayload payload) {
    try {
      final receiverId = payload.newRecord['receiver_id'];
      final senderId = payload.newRecord['sender_id'];
      
      // Get the receiver's name for the notification (the person who accepted the request)
      _getUserDisplayName(receiverId).then((receiverName) {
        if (receiverName != null) {
          // Import the showCustomNotification function from main.dart
          // We'll need to use a different approach since we can't import main.dart here
          // For now, we'll use a callback approach
          if (_onFriendRequestAccepted != null) {
            _onFriendRequestAccepted!(receiverName);
          }
        }
      });
    } catch (e) {
      print('Error showing friend request accepted notification: $e');
    }
  }

  // Helper method to get user display name
  Future<String?> _getUserDisplayName(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('first_name, last_name, username')
          .eq('id', userId)
          .maybeSingle();
      
      if (response != null) {
        final firstName = response['first_name'];
        final lastName = response['last_name'];
        final username = response['username'];
        
        if (firstName != null && lastName != null) {
          return '$firstName $lastName';
        } else if (firstName != null) {
          return firstName;
        } else if (username != null) {
          return username;
        }
      }
      return null;
    } catch (e) {
      print('Error getting user display name: $e');
      return null;
    }
  }

  // Handle deep link authentication
  Future<bool> handleDeepLink(String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.path == '/login-callback' && uri.queryParameters['code'] != null) {
        final code = uri.queryParameters['code']!;
        print('🔐 Handling deep link auth code: ${code.substring(0, 8)}...');
        
        // Get stored PKCE verifier using AuthStorageService
        final authStorage = AuthStorageService();
        final verifier = await authStorage.getVerifier();
        
        if (verifier != null) {
          try {
            await Supabase.instance.client.auth.exchangeCodeForSession(code);
            print('🔐 Successfully exchanged code for session');
            // Clear verifier after successful exchange
            await authStorage.clearVerifier();
            return true;
          } catch (e) {
            print('🔐 Error exchanging code: $e');
            
            // Handle specific PKCE verification errors
            if (e.toString().contains('Code verifier could not be found')) {
              print('🔐 PKCE verification failed - verifier not found');
              // Try to regenerate verifier and retry
              try {
                final pkceData = await authStorage.generateAndStoreVerifier();
                if (pkceData != null) {
                  print('🔐 Regenerated PKCE verifier, retrying code exchange...');
                  await Supabase.instance.client.auth.exchangeCodeForSession(code);
                  print('🔐 Code exchange successful after verifier regeneration');
                  await authStorage.clearVerifier();
                  return true;
                }
              } catch (retryError) {
                print('🔐 Failed to retry code exchange: $retryError');
                await authStorage.clearVerifier();
                _errorMessage = 'Authentication failed. Please try again.';
              }
            } else {
              // Clear verifier on other errors to prevent future issues
              await authStorage.clearVerifier();
              _errorMessage = 'Authentication failed: ${e.toString()}';
            }
          }
        } else {
          print('🔐 No PKCE verifier found for code exchange');
          _errorMessage = 'Authentication failed: PKCE verification error';
        }
      }
    } catch (e) {
      print('🔐 Error handling deep link: $e');
      _errorMessage = 'Authentication failed: ${e.toString()}';
    }
    return false;
  }
  
  // Check if user is already logged in via shared preferences
  Future<void> checkLoginState() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      
      if (email != null) {
        // Check if we have a valid Supabase session
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null && session.user.emailConfirmedAt != null) {
          // Only allow login if email is verified
          final userData = await Supabase.instance.client
              .from('users')
              .select()
              .eq('email', email)
              .single();
          
          if (userData != null) {
            _currentUser = app.User.fromMap(userData);
            _shouldRefreshMap = true;
            // Setup global real-time listeners for friend requests
            _setupGlobalFriendRequestListeners();
            // Process any pending referral now that we have a logged-in user
            await processPendingReferral();
            // Load friend data for the authenticated user
            print('🔔 AuthProvider: Loading friend data after successful login check');
            await refreshFriendData();
          } else {
            await prefs.remove('user_email');
            _currentUser = null;
          }
        } else {
          // Session exists but email not verified, clear the session
          await prefs.remove('user_email');
          _currentUser = null;
          // Sign out to clear the unverified session
          try {
            await Supabase.instance.client.auth.signOut();
          } catch (e) {
            print('Error signing out unverified user: $e');
          }
        }
      }
    } catch (e) {
      print('Error checking login state: $e');
      _currentUser = null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Check if email already exists
  Future<bool> checkEmailExists(String email) async {
    try {
      final normalizedEmail = email.toLowerCase().trim();
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .ilike('email', normalizedEmail)
          .maybeSingle();
      return response != null;
    } catch (e) {
      _errorMessage = 'Error checking email: ${e.toString()}';
      return false;
    }
  }
  
  // Reserved usernames that cannot be used
  static const List<String> _reservedUsernames = [
    'admin', 'administrator', 'mod', 'moderator', 'support', 'help', 'info',
    'contact', 'system', 'root', 'superuser', 'staff', 'team', 'official',
    'myarea', 'myareaapp', 'myarea_app', 'myarea-app', 'myarea.app',
    'null', 'undefined', 'none', 'anonymous', 'guest', 'user', 'test',
    'demo', 'example', 'sample', 'temporary', 'temp', 'delete', 'remove'
  ];

  // Check if username is reserved
  bool _isReservedUsername(String username) {
    return _reservedUsernames.contains(username.toLowerCase().trim());
  }

  // Validate username format
  String? validateUsernameFormat(String username) {
    // Normalize for profanity checks
    final String lowered = username.toLowerCase();
    final String withSpaces = lowered.replaceAll(RegExp(r'[_.]'), ' ');
    final String collapsed = lowered.replaceAll(RegExp(r'[_.]'), '');
    // Additional collapsed phrase bans
    const Set<String> _bannedCollapsedSubstrings = {
      'ballgravy',
    };
    if (_profanityFilter.hasProfanity(lowered) ||
        _profanityFilter.hasProfanity(withSpaces) ||
        _profanityFilter.hasProfanity(collapsed) ||
        _bannedCollapsedSubstrings.any((p) => collapsed.contains(p))) {
      return 'Please choose a different username';
    }
    if (username.length < 3) {
      return 'Username must be at least 3 characters';
    }
    if (username.length > 20) {
      return 'Username must be 20 characters or less';
    }
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(username)) {
      return 'Username can only contain letters, numbers, underscores, and dots';
    }
    if (_isReservedUsername(username)) {
      return 'This username is reserved and cannot be used';
    }
    return null;
  }

  // Check if username already exists
  Future<bool> checkUsernameExists(String username) async {
    try {
      // First check if it's a reserved username
      if (_isReservedUsername(username)) {
        return true; // Treat reserved usernames as "taken"
      }

      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('username', username.toLowerCase().trim())
          .maybeSingle();
      return response != null;
    } catch (e) {
      _errorMessage = 'Error checking username: ${e.toString()}';
      return false;
    }
  }
  
  // Login
  Future<Map<String, dynamic>> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    // Handle both email and username login
    String emailToUse = email.toLowerCase().trim();

    try {
      
      // Check if input is a username (doesn't contain @)
      if (!email.contains('@')) {
        // Try to find user by username
        final userData = await Supabase.instance.client
            .from('users')
            .select('email')
            .eq('username', email.trim())
            .maybeSingle();
        
        if (userData == null) {
          _errorMessage = 'Invalid username or password';
          return {'success': false, 'error': 'invalid_credentials'};
        }
        
        emailToUse = userData['email'];
      }

      // Now try to sign in with the email
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: emailToUse,
        password: password.trim(),
      );

      print('Login response: user=${response.user != null}, emailConfirmedAt=${response.user?.emailConfirmedAt}');

      if (response.user != null) {
        // Check if email is verified
        if (response.user!.emailConfirmedAt == null) {
          print('Email not verified, returning email_not_verified error');
          _errorMessage = 'Email not verified';
          return {
            'success': false, 
            'error': 'email_not_verified',
            'email': emailToUse,
            'password': password
          };
        }
        
        // Get user data from users table
        final userData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('email', response.user!.email ?? '')
            .single();
        
        if (userData != null) {
          _currentUser = app.User.fromMap(userData);
          _shouldRefreshMap = true;
          _errorMessage = '';

          // Save login state
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_email', _currentUser!.email);
          // Setup global real-time listeners for friend requests
          _setupGlobalFriendRequestListeners();
          // Process any pending referral
          await processPendingReferral();
          
          // Device token will be saved by the auth state change listener in main.dart
          // No need to call _saveDeviceToken() here to avoid duplicates
          
          notifyListeners();
          // Suppress listener refresh once; standard flow will refresh
          AuthRefreshCoordinator.suppressOnce();
          refreshAllTabsAfterAuthChange(onSignOut: false);
          return {'success': true};
        }
      }
      
      _errorMessage = 'Invalid username or password';
      _currentUser = null;
      notifyListeners();
      return {'success': false, 'error': 'invalid_credentials'};
    } catch (e) {
      print('Error during login: $e');
      
      // Check if it's an AuthException and handle email verification specifically
      if (e.toString().contains('Email not confirmed')) {
        _errorMessage = 'Email not verified';
        return {
          'success': false, 
          'error': 'email_not_verified',
          'email': emailToUse,
          'password': password
        };
      }
      
      _errorMessage = 'Invalid username or password';
      _currentUser = null;
      notifyListeners();
      return {'success': false, 'error': 'invalid_credentials'};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Save device token to database with retry logic
  Future<void> _saveDeviceToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      
      // First try to get APNS token on iOS
      if (Platform.isIOS) {
        try {
          await messaging.getAPNSToken();
        } catch (e) {
          print('Warning: Could not get APNS token: $e');
        }
      }
      
      // Retry getting FCM token a few times with delay
      String? fcmToken;
      for (int i = 0; i < 3; i++) {
        fcmToken = await messaging.getToken();
        if (fcmToken != null) break;
        await Future.delayed(Duration(seconds: 1));
      }
      
      if (fcmToken != null && _currentUser != null && _currentUser!.id != null) {
        print('Saving device token for user: ${_currentUser!.id}');
        // Retry saving token to database
        for (int i = 0; i < 3; i++) {
          try {
            await Supabase.instance.client
                .from('device_tokens')
                .upsert({
                  'user_id': _currentUser!.id!,
                  'token': fcmToken,
                });
            print('Device token saved successfully');
            break;
          } catch (e) {
            print('Attempt ${i + 1} to save token failed: $e');
            if (i == 2) rethrow;
            await Future.delayed(Duration(milliseconds: 500));
          }
        }
      } else {
        print('Could not save device token - token: ${fcmToken != null}, user: ${_currentUser != null}, userId: ${_currentUser?.id}');
      }
    } catch (e) {
      print('Error saving device token: $e');
    }
  }

  // Public method to save device token (can be called from other parts of the app)
  Future<void> saveDeviceToken() async {
    await _saveDeviceToken();
  }

  // Debug method to check if device token is saved
  Future<void> checkDeviceToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final fcmToken = await messaging.getToken();
      
      if (fcmToken != null && _currentUser != null && _currentUser!.id != null) {
        final response = await Supabase.instance.client
            .from('device_tokens')
            .select('*')
            .eq('user_id', _currentUser!.id!)
            .eq('token', fcmToken);
        
        if (response.isNotEmpty) {
          print('✅ Device token found in database for user: ${_currentUser!.id}');
        } else {
          print('❌ Device token NOT found in database for user: ${_currentUser!.id}');
          print('Current FCM token: ${fcmToken.substring(0, 20)}...');
        }
      } else {
        print('❌ Cannot check device token - FCM token or user is null');
      }
    } catch (e) {
      print('Error checking device token: $e');
    }
  }

  // Method to handle post-email-verification login
  Future<bool> handlePostVerificationLogin(String email) async {
    try {
      print('handlePostVerificationLogin called for email: $email');
      
      // Check if we already have a valid session
      final session = Supabase.instance.client.auth.currentSession;
      print('Current session: ${session != null ? 'exists' : 'null'}, emailConfirmedAt: ${session?.user.emailConfirmedAt}');
      
      if (session != null && session.user.emailConfirmedAt != null) {
        // User is already signed in and verified, just get the user data
        print('User already signed in and verified, getting user data');
        final userData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('email', email)
            .single();
        
        if (userData != null) {
          print('User data retrieved successfully');
          _currentUser = app.User.fromMap(userData);
          _shouldRefreshMap = true;
          _errorMessage = '';

          // Save login state
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_email', _currentUser!.email);
          // Setup global real-time listeners for friend requests
          _setupGlobalFriendRequestListeners();
          // Process any pending referral
          await processPendingReferral();
          
          notifyListeners();
          return true;
        }
      }
      
      // If no valid session, try to get user data anyway (fallback)
      print('No valid session, trying fallback approach');
      final userData = await Supabase.instance.client
          .from('users')
          .select()
          .eq('email', email)
          .single();
      
      if (userData != null) {
        print('User data retrieved via fallback');
        _currentUser = app.User.fromMap(userData);
        _shouldRefreshMap = true;
        _errorMessage = '';

        // Save login state
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', _currentUser!.email);
        // Setup global real-time listeners for friend requests
        _setupGlobalFriendRequestListeners();
        // Process any pending referral
        await processPendingReferral();
        
        notifyListeners();
        return true;
      }
      
      print('No user data found');
      return false;
    } catch (e) {
      print('Error handling post-verification login: $e');
      return false;
    }
  }
  
  // Register
  Future<bool> register(String email, String username, String password, {String? firstName, String? lastName}) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Validate username format first
      final usernameValidationError = validateUsernameFormat(username);
      if (usernameValidationError != null) {
        _errorMessage = usernameValidationError;
        return false;
      }

      // Check if email or username already exists
      final emailExists = await checkEmailExists(email);
      if (emailExists) {
        _errorMessage = 'Email already registered';
        return false;
      }

      final usernameExists = await checkUsernameExists(username);
      if (usernameExists) {
        _errorMessage = 'Username already taken';
        return false;
      }

      try {
        // Create user in Supabase Auth
        final response = await Supabase.instance.client.auth.signUp(
          email: email.toLowerCase().trim(),
          password: password.trim(),
          data: {
            'username': username.trim(),
            'first_name': firstName?.trim() ?? '',
            'last_name': lastName?.trim() ?? '',
          },
        );

        if (response.user != null) {
          // Manually create the user profile since we removed the trigger
          try {
            final newUserData = {
              'id': response.user!.id,
              'email': response.user!.email ?? '',
              'username': username.trim(),
              'first_name': firstName?.trim() ?? '',
              'last_name': lastName?.trim() ?? '',
              'created_at': DateTime.now().toIso8601String(),
            };
            
            final userData = await Supabase.instance.client
                .from('users')
                .insert(newUserData)
                .select()
                .single();
            
            if (userData != null) {
              // Don't set user as logged in until email is verified
              // Just return success to indicate registration completed
              _errorMessage = '';
              
              // Don't save login state or device token until email is verified
              // The user will need to verify email and then login properly
              
              return true;
            } else {
              _errorMessage = 'Profile creation failed - please try again';
              return false;
            }
          } catch (e) {
            print('Error creating user profile: $e');
            _errorMessage = 'Profile creation failed: $e';
            return false;
          }
        }
      } on AuthException catch (e) {
        if (e.message.contains('over_email_send_rate_limit')) {
          _errorMessage = 'Please wait a moment before trying again. For security, we limit how often you can request email verification.';
        } else {
          _errorMessage = 'Registration failed: ${e.message}';
        }
        return false;
      }
      
      _errorMessage = 'Registration failed';
      return false;
    } catch (e) {
      print('Error during registration: $e');
      if (e is AuthException) {
        _errorMessage = e.message;
      } else {
        _errorMessage = 'Registration failed: ${e.toString()}';
      }
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  // Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Clear any pending auth operations first
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        print('🔐 Clearing pending auth completer during logout');
        _authCompleter!.complete(false);
        _authCompleter = null;
      }
      
      // Clear any SSO error messages
      clearSSOErrorMessage();
      
      // Remove device token from database before logout
      if (_currentUser != null) {
        await _removeDeviceToken();
      }
      
      // Clear PKCE verifier and other auth storage
      final authStorage = AuthStorageService();
      await authStorage.clearVerifier();
      await authStorage.clearPendingReferrer();
      
      await Supabase.instance.client.auth.signOut();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_email');
      
      // Clear all state
      _currentUser = null;
      _errorMessage = '';
      _shouldRefreshMap = true;
      
      // Clean up global real-time listeners
      _cleanupGlobalFriendRequestListeners();
      
      // Clear friend-related state
      _pendingFriendRequests = [];
      _sentFriendRequests = [];
      _friendsList = [];
      
      // Clear notification counts and app badge
      FlutterAppBadger.removeBadge();
      
      notifyListeners();
      // Suppress listener refresh once; standard flow will refresh
      AuthRefreshCoordinator.suppressOnce();
      // Trigger unified post-auth UI refresh for sign-out
      refreshAllTabsAfterAuthChange(onSignOut: true);
    } catch (e) {
      print('Error during logout: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Remove device token from database
  Future<void> _removeDeviceToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
      final fcmToken = await messaging.getToken();
      
      if (fcmToken != null && _currentUser != null && _currentUser!.id != null) {
        print('Removing device token for user: ${_currentUser!.id}');
        await Supabase.instance.client
            .from('device_tokens')
            .delete()
            .eq('user_id', _currentUser!.id!)
            .eq('token', fcmToken);
        print('Device token removed successfully');
      }
    } catch (e) {
      print('Error removing device token: $e');
    }
  }
  
  // Clear error message
  void clearError() {
    if (_errorMessage.isNotEmpty) {
      _errorMessage = '';
      notifyListeners();
    }
  }

  void refreshMap() {
    if (!_shouldRefreshMap) {
      _shouldRefreshMap = true;
      notifyListeners();
    }
  }

  void clearMapRefresh() {
    if (_shouldRefreshMap) {
      _shouldRefreshMap = false;
      notifyListeners();
    }
  }

  void setLoginEmail(String email) {
    _loginEmail = email;
    notifyListeners();
  }
  
  void clearLoginEmail() {
    _loginEmail = null;
    notifyListeners();
  }

  Future<bool> updateUserInfo({
    required String userId,
    String? postcode,
    String? ageGroup,
    List<String>? interests,
  }) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .update({
            if (postcode != null) 'postcode': postcode,
            if (ageGroup != null) 'age_group': ageGroup,
            if (interests != null) 'interests': interests,
          })
          .eq('id', userId)
          .select()
          .single();
      
      if (response != null && _currentUser != null) {
        _currentUser = app.User.fromMap(response);
        notifyListeners();
        return true;
      }
      
      return false;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }

  // Friend-related methods
  Future<void> loadFriendRequests() async {
    if (_currentUser == null) {
      print('🔔 AuthProvider: loadFriendRequests called but _currentUser is null');
      return;
    }
    print('🔔 AuthProvider: loadFriendRequests called for user: ${_currentUser!.id}');
    _isLoadingFriends = true;
    notifyListeners();
    
    try {
      final pending = await SupabaseDatabase.instance.getPendingFriendRequests(_currentUser!.id!);
      final sent = await SupabaseDatabase.instance.getSentFriendRequests(_currentUser!.id!);
      print('🔔 AuthProvider: loaded pending=${pending.length}, sent=${sent.length}');
      _pendingFriendRequests = pending;
      _sentFriendRequests = sent;
      // Update badge count using central manager
      if (MainScreen.globalKey.currentContext != null) {
        BadgeManager.updateAppBadge(MainScreen.globalKey.currentContext!);
      }
    } catch (e) {
      print('Error loading friend requests: $e');
    } finally {
      _isLoadingFriends = false;
      notifyListeners();
    }
  }

  Future<void> loadFriendsList() async {
    if (_currentUser == null) return;
    
    _isLoadingFriends = true;
    notifyListeners();
    
    try {
      final friends = await SupabaseDatabase.instance.getFriendsList(_currentUser!.id!);
      _friendsList = friends;
    } catch (e) {
      print('Error loading friends list: $e');
    } finally {
      _isLoadingFriends = false;
      notifyListeners();
    }
  }

  Future<bool> sendFriendRequest(String receiverId) async {
    if (_currentUser == null) return false;
    
    try {
      final success = await SupabaseDatabase.instance.sendFriendRequest(
        _currentUser!.id!,
        receiverId,
      );
      
      if (success) {
        // Reload sent requests
        await loadFriendRequests();
      }
      
      return success;
    } catch (e) {
      print('Error sending friend request: $e');
      return false;
    }
  }

  Future<bool> respondToFriendRequest(String requestId, FriendRequestStatus status) async {
    try {
      final success = await SupabaseDatabase.instance.respondToFriendRequest(requestId, status);
      
      if (success) {
        // Reload requests and friends list
        await loadFriendRequests();
        await loadFriendsList();
        // Badge will be updated in loadFriendRequests
      }
      
      return success;
    } catch (e) {
      print('Error responding to friend request: $e');
      return false;
    }
  }

  Future<List<app.User>> searchUsers(String query) async {
    if (_currentUser == null) return [];
    
    try {
      return await SupabaseDatabase.instance.searchUsers(query, _currentUser!.id!);
    } catch (e) {
      print('Error searching users: $e');
      return [];
    }
  }

  Future<bool> checkFriendRequestExists(String otherUserId) async {
    if (_currentUser == null) return false;
    
    try {
      return await SupabaseDatabase.instance.checkFriendRequestExists(
        _currentUser!.id!,
        otherUserId,
      );
    } catch (e) {
      print('Error checking friend request: $e');
      return false;
    }
  }

  Future<bool> areFriends(String otherUserId) async {
    if (_currentUser == null) return false;
    
    try {
      return await SupabaseDatabase.instance.areFriends(
        _currentUser!.id!,
        otherUserId,
      );
    } catch (e) {
      print('Error checking if friends: $e');
      return false;
    }
  }

  // Refresh all friend-related data
  Future<void> refreshFriendData() async {
    print('🔔 AuthProvider: refreshFriendData called');
    if (_currentUser == null) {
      print('🔔 AuthProvider: refreshFriendData called but _currentUser is null');
      return;
    }
    print('🔔 AuthProvider: refreshFriendData called for user: ${_currentUser!.id}');
    await Future.wait([
      loadFriendRequests(),
      loadFriendsList(),
    ]);
  }

  // Get friends' responses to a specific event
  Future<Map<String, EventResponseType>> getFriendsEventResponses(int eventId) async {
    if (_currentUser == null || _friendsList.isEmpty) return {};
    
    try {
      final friendIds = _friendsList.map((friend) => friend.id!).toList();
      final responses = await SupabaseDatabase.instance.getFriendsEventResponses(eventId, friendIds);
      return responses;
    } catch (e) {
      print('Error getting friends event responses: $e');
      return {};
    }
  }

  // Google Sign-In via Supabase OAuth
  Future<Map<String, dynamic>> signInWithGoogle() async {
    print('🔐 signInWithGoogle called - setting loading to true');
    _isLoading = true;
    notifyListeners();
    
    try {
      print('🔐 Starting Google OAuth flow...');
      
      // Ensure we're starting with a clean slate - clear any existing auth state
      // This is especially important after logout to prevent race conditions
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        print('🔐 Completing existing auth completer');
        _authCompleter!.complete(false);
      }
      _authCompleter = Completer<bool>();
      
      // Clear any existing error messages
      clearSSOErrorMessage();
      
      // Reset resume check state to ensure fresh OAuth flow
      _resumeCheckInProgress = false;
      
      // Generate and store PKCE verifier using dedicated service
      final authStorage = AuthStorageService();
      Map<String, String>? pkceData;
      
      try {
        print('🔐 Generating PKCE verifier...');
        // Clear any existing verifier first
        await authStorage.clearVerifier();
        
        // Generate and store new verifier
        pkceData = await authStorage.generateAndStoreVerifier();
        
        // Verify storage
        final storedVerifier = await authStorage.getVerifier();
        if (storedVerifier == null || storedVerifier != pkceData['verifier']) {
          throw Exception('PKCE verifier verification failed after storage');
        }
        
        print('🔐 Starting OAuth flow with external browser...');
        // Start the OAuth flow with external browser
        await Supabase.instance.client.auth.signInWithOAuth(
          OAuthProvider.google,
          queryParams: {
            'access_type': 'offline',
            'prompt': 'consent',
            'code_challenge': pkceData['codeChallenge'] ?? '',
            'code_challenge_method': 'plain',
          },
          redirectTo: 'https://myarea.com.au/auth/callback',
          authScreenLaunchMode: LaunchMode.externalApplication,
          scopes: 'email profile',
        );
      } catch (e) {
        print('🔐 Error preparing OAuth flow: $e');
        // Clean up on error
        await authStorage.clearVerifier();
        throw Exception('Failed to prepare OAuth flow: $e');
      }
      
      print('🔐 OAuth flow initiated, waiting for user to complete authentication...');
      print('🔐 Redirect URL: io.supabase.myareaapp://login-callback');
      print('🔐 Launch mode: externalApplication (external browser)');
      
      // Wait for the completer to complete (OAuth completion from deep link service)
      // This will happen when the user completes the OAuth flow and returns to the app
      // 
      // Add a reasonable timeout to prevent hanging indefinitely
      // Users should be able to take time for Google SSO, but we need a safety net
      bool authenticationSuccess = false;
      try {
        print('🔐 Waiting for auth completer...');
        authenticationSuccess = await _authCompleter!.future.timeout(
          const Duration(minutes: 5), // 5 minute timeout for OAuth
          onTimeout: () {
            print('🔐 OAuth timeout - user took too long to complete authentication');
            // Complete the completer with false on timeout
            _completeOAuthFlow(false);
            return false;
          },
        );
        print('🔐 Auth completer completed with result: $authenticationSuccess');
      } catch (e) {
        print('🔐 Auth completer completed with error: $e');
        authenticationSuccess = false;
      }
      
      if (!authenticationSuccess) {
        print('🔐 Authentication failed or was cancelled');
        _setSSOError('Sign-in was not completed. Please try again.');
        return {
          'success': false,
          'needsUsername': false,
          'error': _ssoErrorMessage,
        };
      }
      
      if (authenticationSuccess) {
        // Load user data from database
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          print('🔐 Google OAuth: Loading user data for ${user.email}');
          
          // Check if user exists and has a username (similar to Apple SSO)
          final userCheckResult = await _checkUserAndUsername(user.email!);
          
          if (userCheckResult['needsUsername'] == true) {
            // User exists but needs to set a username
            print('🔐 Google user needs to set username');
            // Not an error; surface via needsUsername result only
            clearSSOErrorMessage();
            
            // Extract first/last name from user metadata
            String? firstName;
            String? lastName;
            
            // Try to get name from full_name first
            final fullName = user.userMetadata?['full_name']?.toString();
            if (fullName != null && fullName.isNotEmpty) {
              final nameParts = fullName.split(' ');
              firstName = nameParts.first;
              lastName = nameParts.length > 1 ? nameParts.last : null;
            }
            
            // If not found, try given_name and family_name
            firstName ??= user.userMetadata?['given_name']?.toString();
            lastName ??= user.userMetadata?['family_name']?.toString();
            
            print('🔐 Google user name data: firstName=$firstName, lastName=$lastName');
            
            return {
              'success': true,
              'needsUsername': true,
              'email': user.email,
              'firstName': firstName,
              'lastName': lastName,
              'provider': 'google',
            };
          } else if (userCheckResult['success'] == true) {
            // User exists and has username - proceed normally
            print('🔐 Google user exists with username, proceeding normally');
            clearSSOErrorMessage();
            
            // Clear PKCE verifier
            final authStorage = AuthStorageService();
            await authStorage.clearVerifier();
            print('🔐 PKCE verifier cleaned up');
            // Process pending referral for SSO sign-in
            await processPendingReferral();
            
            return {
              'success': true,
              'needsUsername': false,
            };
          } else {
            // Error occurred
            _setSSOError(userCheckResult['error'] ?? 'Failed to check user data');
            return {
              'success': false,
              'needsUsername': false,
              'error': _ssoErrorMessage,
            };
          }
        }
      }
      
      _setSSOError('Google sign-in failed. Please try again.');
      return {
        'success': false,
        'needsUsername': false,
        'error': _ssoErrorMessage,
      };
      
    } catch (e) {
      print('🔐 Google OAuth error: $e');
      _setSSOError('Sign-in was not completed. Please try again.');
      return {
        'success': false,
        'needsUsername': false,
        'error': _ssoErrorMessage,
      };
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Method to check authentication status
  Future<bool> checkAuthenticationStatus() async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      final session = Supabase.instance.client.auth.currentSession;
      
      if (currentUser != null && currentUser.email != null) {
        print('🔐 User is authenticated: ${currentUser.email}');
        return true;
      }
      
      if (session != null && session.user.email != null) {
        print('🔐 Valid session found: ${session.user.email}');
        return true;
      }
      
      print('🔐 No authentication found');
      return false;
    } catch (e) {
      print('🔐 Error checking authentication status: $e');
      return false;
    }
  }

  // Method to immediately check and clear SSO loading states when app resumes
  Future<void> checkAndClearSSOLoadingState() async {
    print('🔐 checkAndClearSSOLoadingState called - current loading state: $_isLoading');
    
    // If we're in a loading state, immediately check if user is authenticated
    if (_isLoading) {
      // Prevent multiple simultaneous resume checks
      if (_resumeCheckInProgress) {
        print('🔐 Resume check already in progress, skipping');
        return;
      }
      _resumeCheckInProgress = true;
      print('🔐 App resumed while SSO was loading, checking authentication status...');
      
      try {
        // Check if user is already authenticated
        final currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser != null && currentUser.email != null) {
          print('🔐 User is already authenticated: ${currentUser.email}');
          // Clear loading state since user is authenticated
          _isLoading = false;
          clearSSOErrorMessage();
          notifyListeners();
          _resumeCheckInProgress = false;
          return;
        }
        
        // Check if there's a valid session
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null && session.user.email != null) {
          print('🔐 Valid session found: ${session.user.email}');
          // Clear loading state since session is valid
          _isLoading = false;
          clearSSOErrorMessage();
          notifyListeners();
          _resumeCheckInProgress = false;
          return;
        }
        
        // If no authentication found yet, allow a short grace period for deep link and auth events
        print('🔐 No authentication found yet, waiting briefly for deep link/auth to complete...');
        await Future.delayed(const Duration(milliseconds: 2000)); // Increased grace period
        
        // Re-check after delay
        final delayedUser = Supabase.instance.client.auth.currentUser;
        final delayedSession = Supabase.instance.client.auth.currentSession;
        if (delayedUser != null && delayedUser.email != null) {
          print('🔐 User authenticated after grace period: ${delayedUser.email}');
          _isLoading = false;
          clearSSOErrorMessage();
          notifyListeners();
          _resumeCheckInProgress = false;
          
          // Complete the auth completer if it's still waiting
          if (_authCompleter != null && !_authCompleter!.isCompleted) {
            print('🔐 Completing auth completer after app resume');
            _authCompleter!.complete(true);
          }
          return;
        }
        if (delayedSession != null && delayedSession.user.email != null) {
          print('🔐 Session valid after grace period: ${delayedSession.user.email}');
          _isLoading = false;
          clearSSOErrorMessage();
          notifyListeners();
          _resumeCheckInProgress = false;
          
          // Complete the auth completer if it's still waiting
          if (_authCompleter != null && !_authCompleter!.isCompleted) {
            print('🔐 Completing auth completer after app resume');
            _authCompleter!.complete(true);
          }
          return;
        }
        
        // After grace period, consider the flow not completed
        print('🔐 SSO not completed after grace period, clearing loading state');
        _isLoading = false;
        clearSSOErrorMessage();
        notifyListeners();
        
        // Only set a generic error if a browser-based OAuth flow (e.g., Google) was in progress.
        // Native Apple Sign In does not use _authCompleter, so avoid showing an error for that case.
        if (_authCompleter != null) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!_authCompleter!.isCompleted) {
            print('🔐 Completing pending auth flow due to error during resume check');
            _completeOAuthFlow(false);
          }
          _setSSOError('Sign-in was not completed. Please try again.');
        }
        _resumeCheckInProgress = false;
        
      } catch (e) {
        print('🔐 Error checking authentication status on resume: $e');
        // Clear loading state on error
        _isLoading = false;
        // Ensure any pending auth flow unblocks
        // Only surface the generic error if a browser-based OAuth was in progress, after a brief wait
        if (_authCompleter != null) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!_authCompleter!.isCompleted) {
            print('🔐 Completing pending auth flow due to error during resume check');
            _completeOAuthFlow(false);
          }
          _setSSOError('Sign-in was not completed. Please try again.');
        }
        _resumeCheckInProgress = false;
      }
    } else {
      print('🔐 Not in loading state, no action needed');
    }
  }

  // Method to clear error messages (useful for resetting state between SSO attempts)
  void clearErrorMessage() {
    if (_errorMessage.isNotEmpty) {
      _errorMessage = '';
      notifyListeners();
    }
  }

  // SSO-specific error controls (kept separate from standard auth errors)
  void clearSSOErrorMessage() {
    if (_ssoErrorMessage.isNotEmpty) {
      _ssoErrorMessage = '';
      notifyListeners();
    }
  }
  void _setSSOError(String message) {
    _ssoErrorMessage = message;
    notifyListeners();
  }

  // Apple Sign-In via native iOS Sign in with Apple
  Future<Map<String, dynamic>> signInWithApple() async {
    // Only available on iOS
    if (!Platform.isIOS) {
      _setSSOError('Apple Sign In is only available on iOS devices');
      return {'success': false, 'needsUsername': false, 'error': 'ios_only'};
    }

    _isLoading = true;
    notifyListeners();
    
    try {
      print('🍎 Starting Apple Sign In flow...');
      
      // Check if Apple Sign In is available on this device
      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        _setSSOError('Apple Sign In is not available on this device');
        return {'success': false, 'needsUsername': false, 'error': 'not_available'};
      }
      
      // Get Apple ID credential
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      
      print('🍎 Apple credential received');
      print('🍎 User ID: ${credential.userIdentifier}');
      print('🍎 Email: ${credential.email ?? 'not provided'}');
      print('🍎 Given Name: ${credential.givenName ?? 'null'}');
      print('🍎 Family Name: ${credential.familyName ?? 'null'}');
      print('🍎 Full Name: ${credential.givenName ?? ''} ${credential.familyName ?? ''}');
      
      if (credential.identityToken == null) {
        _setSSOError('Failed to get Apple identity token');
        return {'success': false, 'needsUsername': false, 'error': 'no_token'};
      }
      
      // Sign in with Supabase using Apple ID token
      final response = await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: credential.identityToken!,
        accessToken: credential.authorizationCode,
      );
      
      if (response.user != null) {
        print('🍎 Apple Sign In successful: ${response.user!.email}');
        
        // Check if user exists and has a username
        final userCheckResult = await _checkUserAndUsername(response.user!.email ?? '');
        
        if (userCheckResult['needsUsername'] == true) {
          // User exists but needs to set a username
          print('🍎 User needs to set username');
          // Clear any stale error that might have been set during app resume checks
          clearSSOErrorMessage();
          
          // Get stored name from database if Apple didn't provide it
          String storedFirstName = credential.givenName ?? '';
          String storedLastName = credential.familyName ?? '';
          
          // If Apple didn't provide names, try to get them from existing user data
          if (storedFirstName.isEmpty && storedLastName.isEmpty) {
            final existingUser = await Supabase.instance.client
                .from('users')
                .select('first_name, last_name')
                .eq('email', response.user!.email ?? '')
                .maybeSingle();
            
            if (existingUser != null) {
              storedFirstName = existingUser['first_name'] ?? '';
              storedLastName = existingUser['last_name'] ?? '';
              print('🍎 Retrieved stored names: $storedFirstName $storedLastName');
            }
          }
          
          return {
            'success': true,
            'needsUsername': true,
            'email': response.user!.email ?? '',
            'firstName': storedFirstName,
            'lastName': storedLastName,
            'appleUserId': credential.userIdentifier ?? '',
          };
        } else if (userCheckResult['success'] == true) {
          // User exists and has username - proceed normally
          print('🍎 User exists with username, proceeding normally');
          clearSSOErrorMessage();
          
          // Only navigate to events tab if we're not already on a valid tab
          // This prevents jumping away from map screen during authentication checks
          final mainState = MainScreen.globalKey.currentState;
          if (mainState != null) {
            final currentTab = MainScreen.currentTabName;
            if (currentTab == 'events' || currentTab == 'map' || currentTab == 'messages' || currentTab == 'friends' || currentTab == 'profile') {
              // Already on a valid tab, don't navigate
              print('🍎 Already on valid tab ($currentTab), not navigating');
            } else {
              print('🍎 MainScreen found, navigating to events tab');
              mainState.navigateToScreen('events');
            }
          } else {
            print('🍎 MainScreen not found, but continuing anyway');
          }
          // Process pending referral for Apple sign-in
          await processPendingReferral();
          
          return {'success': true, 'needsUsername': false};
        } else {
          // Error occurred
          _setSSOError(userCheckResult['error'] ?? 'Failed to check user data');
          return {'success': false, 'needsUsername': false, 'error': _ssoErrorMessage};
        }
      }
      
      _setSSOError('Apple sign-in failed. Please try again.');
      return {'success': false, 'needsUsername': false, 'error': 'signin_failed'};
      
    } on SignInWithAppleAuthorizationException catch (e) {
      print('🍎 Apple Sign In authorization error: ${e.code} - ${e.message}');
      
      // Handle specific Apple Sign In errors
      switch (e.code) {
        case AuthorizationErrorCode.canceled:
          // User canceled - don't show error or close auth flow
          print('🍎 Apple Sign In was canceled by user');
          return {'success': false, 'needsUsername': false, 'error': 'canceled'};
        case AuthorizationErrorCode.failed:
          _setSSOError('Apple Sign In failed. Please try again.');
          break;
        case AuthorizationErrorCode.invalidResponse:
          _setSSOError('Invalid response from Apple Sign In');
          break;
        case AuthorizationErrorCode.notHandled:
          _setSSOError('Apple Sign In not handled');
          break;
        case AuthorizationErrorCode.unknown:
          _setSSOError('Unknown error during Apple Sign In');
          break;
        default:
          _setSSOError('Apple Sign In error: ${e.message}');
      }
      
      return {'success': false, 'needsUsername': false, 'error': 'authorization_failed'};
    } catch (e) {
      print('🍎 Apple Sign In error: $e');
      _setSSOError('Apple sign-in failed: $e');
      return {'success': false, 'needsUsername': false, 'error': _ssoErrorMessage};
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Check if user exists and has a username
  Future<Map<String, dynamic>> _checkUserAndUsername(String email) async {
    try {
      // Check if user exists in database
      final userData = await Supabase.instance.client
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();
      
      if (userData != null) {
        // User exists in database - load their data
        print('🔐 User exists in database');
        _currentUser = app.User.fromMap(userData);
        _shouldRefreshMap = true;
        
        // Save email to shared preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', email);
        
        // Setup global real-time listeners for friend requests
        _setupGlobalFriendRequestListeners();
        
        notifyListeners();
        return {
          'success': true,
          'needsUsername': false,
          'userData': userData,
        };
      } else {
        // User doesn't exist in database yet - they need to set a username
        print('🔐 New user - needs to set username');
        return {
          'success': true,
          'needsUsername': true,
          'userData': null,
        };
      }
    } catch (e) {
      print('🔐 Error checking user and username: $e');
      return {
        'success': false,
        'needsUsername': false,
        'error': e.toString(),
      };
    }
  }

  // Create user with username for Apple Sign In
  Future<bool> createAppleUserWithUsername({
    required String email,
    required String username,
    String? firstName,
    String? lastName,
    String? appleUserId,
  }) async {
    try {
      print('🍎 Creating Apple user with username: $username');
      
      // Check if username is available
      final usernameExists = await checkUsernameExists(username);
      if (usernameExists) {
        _errorMessage = 'Username already taken';
        return false;
      }
      
      // Validate username format
      final usernameValidationError = validateUsernameFormat(username);
      if (usernameValidationError != null) {
        _errorMessage = usernameValidationError;
        return false;
      }
      
      // Check if user already exists (for users who signed in before but didn't set username)
      final existingUser = await Supabase.instance.client
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();
      
      if (existingUser != null) {
        // Update existing user with username
        print('🍎 Updating existing user with username');
        final updatedFirstName = firstName ?? existingUser['first_name'] ?? '';
        final updatedLastName = lastName ?? existingUser['last_name'] ?? '';
        
        print('🍎 Updating user with names: first_name="$updatedFirstName", last_name="$updatedLastName"');
        
        final result = await Supabase.instance.client
            .from('users')
            .update({
              'username': username,
              'first_name': updatedFirstName,
              'last_name': updatedLastName,
              'apple_user_id': appleUserId ?? existingUser['apple_user_id'],
            })
            .eq('email', email)
            .select()
            .single();
        
        _currentUser = app.User.fromMap(result);
      } else {
        // Create new user record
        print('🍎 Creating new user record');
        final currentUser = Supabase.instance.client.auth.currentUser;
        if (currentUser?.id == null) {
          throw Exception('No authenticated user found');
        }
        
        final newUserData = {
          'id': currentUser!.id, // This ensures the ID is set
          'email': email,
          'username': username,
          'first_name': firstName ?? '',
          'last_name': lastName ?? '',
          'apple_user_id': appleUserId,
          'created_at': DateTime.now().toIso8601String(),
        };
        
        print('🍎 Creating user with names: first_name="${firstName ?? 'null'}", last_name="${lastName ?? 'null'}"');
        
        final result = await Supabase.instance.client
            .from('users')
            .insert(newUserData)
            .select()
            .single();
        
        _currentUser = app.User.fromMap(result);
      }
      
      _shouldRefreshMap = true;
      
      // Save email to shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', email);
      // Setup global real-time listeners for friend requests
      _setupGlobalFriendRequestListeners();
      // Process any pending referral now that user exists
      await processPendingReferral();
      
      print('🍎 Apple user created/updated successfully: ${_currentUser?.email}');
      
      notifyListeners();
      return true;
      
    } catch (e) {
      print('🍎 Error creating/updating Apple user: $e');
      _errorMessage = 'Failed to create user: $e';
      return false;
    }
  }

  // Create user with username for Google and other SSO providers
  Future<bool> createUserWithUsername({
    required String email,
    required String username,
    String? firstName,
    String? lastName,
  }) async {
    try {
      print('🔐 Creating user with username: $username');
      
      // Check if username is available
      final usernameExists = await checkUsernameExists(username);
      if (usernameExists) {
        _errorMessage = 'Username already taken';
        return false;
      }
      
      // Validate username format
      final usernameValidationError = validateUsernameFormat(username);
      if (usernameValidationError != null) {
        _errorMessage = usernameValidationError;
        return false;
      }
      
      // Create new user record
      print('🔐 Creating new user record');
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser?.id == null) {
        throw Exception('No authenticated user found');
      }
      
      final newUserData = {
        'id': currentUser!.id, // This ensures the ID is set
        'email': email,
        'username': username,
        'first_name': firstName ?? '',
        'last_name': lastName ?? '',
        'created_at': DateTime.now().toIso8601String(),
      };
      
      final result = await Supabase.instance.client
          .from('users')
          .insert(newUserData)
          .select()
          .single();
      
      _currentUser = app.User.fromMap(result);
      _shouldRefreshMap = true;
      
      // Save email to shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_email', email);
      // Setup global real-time listeners for friend requests
      _setupGlobalFriendRequestListeners();
      // Process any pending referral now that user exists
      await processPendingReferral();
      
      print('🔐 User created successfully: ${_currentUser?.email}');
      
      notifyListeners();
      return true;
      
    } catch (e) {
      print('🔐 Error creating user: $e');
      _errorMessage = 'Failed to create user: $e';
      return false;
    }
  }

  // Cancel a sent friend request
  Future<bool> cancelSentFriendRequest(String requestId) async {
    try {
      final success = await SupabaseDatabase.instance.cancelSentFriendRequest(requestId);
      if (success) {
        await loadFriendRequests();
      }
      return success;
    } catch (e) {
      print('Error cancelling sent friend request: $e');
      return false;
    }
  }

  // External browser cleanup (no longer needed with external browser)
  Future<void> cleanupAuthFlow() async {
    try {
      print('🔐 Cleaning up auth flow...');
      
      // Complete any pending auth operation
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        _authCompleter!.complete(true);
      }
      _authCompleter = null;
      
      print('🔐 Auth flow cleanup completed');
    } catch (e) {
      print('🔐 Error cleaning up auth flow: $e');
      // Still try to complete the auth operation
      if (_authCompleter != null && !_authCompleter!.isCompleted) {
        _authCompleter!.complete(true);
      }
      _authCompleter = null;
    }
  }

  // Handle manual OAuth completion (fallback for when deep links don't work)
  Future<bool> handleManualOAuthCompletion() async {
    try {
      print('🔐 Attempting manual OAuth completion...');
      
      // Check if user is already signed in
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null && currentUser.email != null) {
        print('🔐 User already signed in: ${currentUser.email}');
        await _loadUserData(currentUser.email!);
        return true;
      }
      
      // Try to get the session from storage
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && session.user.email != null) {
        print('🔐 Session found: ${session.user.email}');
        await _loadUserData(session.user.email!);
        return true;
      }
      
      // Try to refresh the session
      try {
        final refreshResult = await Supabase.instance.client.auth.refreshSession();
        if (refreshResult.session != null && refreshResult.session!.user.email != null) {
          print('🔐 Session refreshed: ${refreshResult.session!.user.email}');
          await _loadUserData(refreshResult.session!.user.email!);
          return true;
        }
      } catch (refreshError) {
        print('🔐 Session refresh failed: $refreshError');
      }
      
      return false;
    } catch (e) {
      print('🔐 Manual OAuth completion error: $e');
      return false;
    }
  }

  // Load user data from database
  Future<void> _loadUserData(String email) async {
    try {
      // First, try to find existing user by email
      final userData = await Supabase.instance.client
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();
      
      if (userData != null) {
        // User exists - just load their data
        print('Found existing user, loading data...');
        
        _currentUser = app.User.fromMap(userData);
        _shouldRefreshMap = true;
        
        // Save email to shared preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', email);
        
        // Setup global real-time listeners for friend requests
        _setupGlobalFriendRequestListeners();
        
        // Load friend data for the authenticated user
        print('🔔 AuthProvider: Loading friend data after loading user data');
        await refreshFriendData();
        
        print('User data loaded successfully: ${_currentUser?.email}');
        
        // Notify listeners that authentication state has changed
        notifyListeners();
        print('🔐 Notified listeners of authentication state change');
      } else {
        // User doesn't exist in database - they need to set a username
        print('User not found in database - needs to set username');
        // Don't set current user - they need to complete username setup first
      }
    } catch (e) {
      print('Error loading user data: $e');
      // Don't throw here - let the calling method handle the error
    }
  }

  // Handle pending referral captured from deep links
  Future<void> processPendingReferral() async {
    try {
      if (_currentUser == null || _currentUser!.id == null) return;
      final authStorage = AuthStorageService();
      final code = await authStorage.getPendingReferrer();
      if (code == null || code.isEmpty) return;
      print('🔗 Processing pending referral for code: $code');
      final referrerId = await SupabaseDatabase.instance.getUserIdByReferralCode(code);
      if (referrerId == null) {
        print('🔗 Referral code did not match a user');
        await authStorage.clearPendingReferrer();
        return;
      }
      // Send a friend request to the referrer (no auto-accept)
      final requestSent = await SupabaseDatabase.instance.sendFriendRequest(
        _currentUser!.id!,
        referrerId,
      );
      print('🔗 Referral friend request sent: ${requestSent ? 'success' : 'skipped/exists'}');
      // Set referred_by on the new user if not already set
      await SupabaseDatabase.instance.setUserReferredByIfEmpty(_currentUser!.id!, referrerId);
      await authStorage.clearPendingReferrer();
      // Refresh friend data silently
      await refreshFriendData();
    } catch (e) {
      print('🔗 Error processing pending referral: $e');
      try {
        final authStorage = AuthStorageService();
        await authStorage.clearPendingReferrer();
      } catch (_) {}
    }
  }

  // Method to check if OAuth flow is still in progress
  bool get isOAuthFlowInProgress => _authCompleter != null && !_authCompleter!.isCompleted;

  // Method to handle OAuth completion from deep link service
  void handleOAuthCompletion(bool success) {
    print('🔐 OAuth completion received: $success');
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      _completeOAuthFlow(success);
    } else {
      print('🔐 No active OAuth flow to complete');
    }
  }

  // Method to safely complete OAuth flow
  void _completeOAuthFlow(bool success) {
    if (_authCompleter != null && !_authCompleter!.isCompleted) {
      print('🔐 Completing OAuth flow with result: $success');
      _authCompleter!.complete(success);
      _authCompleter = null;
    }
  }

  // Dispose method to clean up resources
  void dispose() {
    _cleanupGlobalFriendRequestListeners();
  }
}