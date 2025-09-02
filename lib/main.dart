import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/screens/auth/welcome_screen.dart';
import 'package:myarea_app/screens/events/events_screen.dart';
import 'package:myarea_app/screens/profile/profile_screen.dart';
import 'package:myarea_app/screens/messages/messages_screen.dart';
import 'package:myarea_app/screens/friends/friends_screen.dart';
import 'package:myarea_app/screens/messages/chat_screen.dart';
import 'package:myarea_app/screens/messages/conversations_screen.dart';
import 'package:myarea_app/screens/messages/new_message_screen.dart';
// import 'package:myarea_app/screens/map/map_screen.dart'; // Removed map screen
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/services/messaging_service.dart';
import 'package:myarea_app/services/deep_link_service.dart';
import 'package:myarea_app/services/auth_storage_service.dart';
import 'package:myarea_app/services/feedback_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter_dotenv/flutter_dotenv.dart' as dotenv;
import 'package:overlay_support/overlay_support.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:myarea_app/widgets/custom_notification.dart';
import 'package:myarea_app/screens/auth/auth_flow_screen.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'dart:async';
import 'package:myarea_app/widgets/feedback_button.dart';
import 'package:myarea_app/styles/app_colours.dart';

import 'package:shared_preferences/shared_preferences.dart';

// Global RouteObserver for navigation events
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

// Supabase credentials
const supabaseUrl = 'https://auth.myarea.com.au';
const supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVlc3lhZnpxa2ljaXBlbnFweWloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDU5NTM5NDksImV4cCI6MjA2MTUyOTk0OX0.N-EZz18MdSewTIrK4fjTtsvsk4GX7D1POUQnpRI4LQI';

// Add a ChangeNotifier for unread message count
class UnreadMessagesProvider extends ChangeNotifier {
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  void setUnreadCount(int count) {

    if (_unreadCount != count) {
      _unreadCount = count;
      notifyListeners();

    } else {

    }
  }

  Future<void> refreshUnreadCount() async {

    final count = await MessagingService.instance.getUnreadConversationsCount();

    setUnreadCount(count);
  }
}

// Central badge update method
class BadgeManager {
  static Future<void> updateAppBadge(BuildContext context) async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final unreadProvider = Provider.of<UnreadMessagesProvider>(context, listen: false);
      
      final friendRequestsCount = authProvider.pendingFriendRequests.length;
      final unreadConversationsCount = unreadProvider.unreadCount;
      
      final totalBadgeCount = friendRequestsCount + unreadConversationsCount;
      FlutterAppBadger.updateBadgeCount(totalBadgeCount);
      

    } catch (e) {
      print('Error updating app badge: $e');
    }
  }
}

// Add background message handler at the top level
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized
  await Firebase.initializeApp();
  
  // Don't show notifications here, let the system handle it
  print("Handling a background message: ${message.messageId}");
}

// Function to ensure all services are properly initialized
Future<void> _ensureServicesInitialized() async {

  
  // Check if Supabase is initialized
  try {
    await SupabaseDatabase.instance.initialize();

  } catch (e) {
    print('⚠️ SupabaseDatabase already initialized or error: $e');
  }
  
  // Check if MessagingService is initialized
  try {
    await MessagingService.instance.initialize();

  } catch (e) {
    print('⚠️ MessagingService already initialized or error: $e');
  }
  
  // Check if DeepLinkService is initialized
  try {
    await DeepLinkService().initialize();

  } catch (e) {
    print('⚠️ DeepLinkService already initialized or error: $e');
  }
  
  // Check if FeedbackService is initialized
  try {
    await FeedbackService.instance.initialize();

  } catch (e) {
    print('⚠️ FeedbackService already initialized or error: $e');
  }
  
  // Refresh unread count
  try {
    final unreadProvider = Provider.of<UnreadMessagesProvider>(MainScreen.globalKey.currentContext!, listen: false);
    await unreadProvider.refreshUnreadCount();

  } catch (e) {
    print('⚠️ Could not refresh unread count: $e');
  }
  

}

// Coordinates avoiding duplicate refreshes between UI flows and auth listener
class AuthRefreshCoordinator {
  static bool _suppressNext = false;

  static void suppressOnce() {
    _suppressNext = true;
  }

  static bool shouldSkipThisListenerInvocation() {
    if (_suppressNext) {
      _suppressNext = false;
      return true;
    }
    return false;
  }
}

// Refresh data across tabs when user signs in/out or switches accounts
Future<void> _refreshAllTabData({bool onSignOut = false}) async {
  try {
    final context = MainScreen.globalKey.currentContext;
    if (context == null) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final unreadProvider = Provider.of<UnreadMessagesProvider>(context, listen: false);

    // Ensure Events screen is showing list (close details) and refresh its data
    final eventsState = EventScreen.globalKey.currentState;
    if (eventsState != null) {
      eventsState.resetToEventList();
      EventScreen.refreshEvents();
    }

    if (onSignOut) {
      // Clear counts immediately on sign out
      unreadProvider.setUnreadCount(0);
      // Ensure friend data reflects signed-out state
      await authProvider.refreshFriendData();
    } else {
      // Refresh user-dependent data on sign in / account switch
      await authProvider.refreshFriendData();
      await unreadProvider.refreshUnreadCount();
    }

    // Force Messages tab to rebuild so lists reflect latest account
    MainScreen.forceMessagesScreenRebuildGlobal();

    // Update app badge with combined counts
    await BadgeManager.updateAppBadge(context);
  } catch (e) {
    print('⚠️ Error refreshing tab data: $e');
  }
}

// Public helper so non-UI layers can trigger a full UI refresh after auth changes
void refreshAllTabsAfterAuthChange({bool onSignOut = false}) {
  _refreshAllTabData(onSignOut: onSignOut);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Initialize Firebase first, before anything else
    await Firebase.initializeApp(
      // Add options to ensure proper initialization
      options: const FirebaseOptions(
        apiKey: 'AIzaSyCUlJ5M_Y-md0vH_p67cLyFFtktoY4fWc0',
        appId: '1:730150888585:ios:45fe858cfd0716d6d55258',
        messagingSenderId: '730150888585',
        projectId: 'myarea-app',
        storageBucket: 'myarea-app.firebasestorage.app',
      ),
    );
    print('Firebase initialized');
    
    // Set up background message handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Generate and store PKCE verifier before Supabase initialization
    final authStorage = AuthStorageService();
    await authStorage.generateAndStoreVerifier();

    // Initialize Supabase with default configuration
    final supabase = await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      debug: true,
    );
    print('Supabase initialized');

    // Listen for auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      final Session? session = data.session;
      
      if (event == AuthChangeEvent.signedIn && session != null) {
        
        // Add a small delay to ensure the auth state is fully processed
        Future.delayed(const Duration(milliseconds: 1000), () {
          // Handle successful sign-in - navigate to events tab
          final mainState = MainScreen.globalKey.currentState;
          if (mainState != null) {


            mainState.navigateToScreen('events'); // Navigate to Events tab
            // Refresh all data unless standard login already handled it
            if (!AuthRefreshCoordinator.shouldSkipThisListenerInvocation()) {
              _refreshAllTabData();
            }

          } else {

            // Retry navigation after a longer delay
            Future.delayed(const Duration(seconds: 2), () {
              final retryMainState = MainScreen.globalKey.currentState;
              if (retryMainState != null) {

                retryMainState.navigateToScreen('events');
                if (!AuthRefreshCoordinator.shouldSkipThisListenerInvocation()) {
                  _refreshAllTabData();
                }
              } else {

              }
            });
          }
        });
      } else if (event == AuthChangeEvent.signedOut) {
        // Handle sign out - navigate to events tab (public) and close any auth flows
        Future.delayed(const Duration(milliseconds: 100), () {
          final mainState = MainScreen.globalKey.currentState;
          if (mainState != null) {
            // Navigate to events tab (public)
            mainState.navigateToScreen('events');
            
            // Close any open auth flows by popping the navigator
            final context = MainScreen.globalKey.currentContext;
            if (context != null) {
              // Pop any auth flow screens that might be open
              Navigator.of(context).popUntil((route) {
                // Keep popping until we reach the main screen
                return route.isFirst;
              });
              // Clear data that depends on auth state unless standard logout handled it
              if (!AuthRefreshCoordinator.shouldSkipThisListenerInvocation()) {
                _refreshAllTabData(onSignOut: true);
              }
            }
          }
        });
      } else if (event == AuthChangeEvent.initialSession && session != null && session.user.email != null) {

        // This might be the OAuth completion - navigate to events tab
        Future.delayed(const Duration(milliseconds: 500), () {
          final context = MainScreen.globalKey.currentContext;
          if (context != null) {
            final mainState = MainScreen.globalKey.currentState;
            if (mainState != null) {
              // Only navigate to events if we're not already on a valid tab
              // This prevents jumping away from screens during initial session
              final currentTab = MainScreen.currentTabName;
              if (currentTab == 'events' || currentTab == 'messages' || currentTab == 'friends' || currentTab == 'profile') {
                // Already on a valid tab, don't navigate
                return;
              }
              mainState.navigateToScreen('events');
            }
          }
        });
      } else if (event == AuthChangeEvent.initialSession && session != null && session.user.email == null) {

        // Check if this is actually a successful OAuth completion
        Future.delayed(const Duration(seconds: 2), () {
          final currentUser = Supabase.instance.client.auth.currentUser;
          if (currentUser != null) {

            final context = MainScreen.globalKey.currentContext;
            if (context != null) {
              final mainState = MainScreen.globalKey.currentState;
              if (mainState != null) {
                // Only navigate to events if we're not already on a valid tab
                // This prevents jumping away from screens during OAuth completion
                final currentTab = MainScreen.currentTabName;
                if (currentTab == 'events' || currentTab == 'messages' || currentTab == 'friends' || currentTab == 'profile') {
                  // Already on a valid tab, don't navigate
                  return;
                }
                mainState.navigateToScreen('events');
              }
            }
          }
        });
      } else if (event == AuthChangeEvent.tokenRefreshed && session != null) {

        // Check if user is now signed in
        Future.delayed(const Duration(milliseconds: 1000), () {
          final currentUser = Supabase.instance.client.auth.currentUser;
          if (currentUser != null && currentUser.email != null) {

            final context = MainScreen.globalKey.currentContext;
            if (context != null) {
              final mainState = MainScreen.globalKey.currentState;
              if (mainState != null) {
                // Only navigate to events if we're not already on a valid tab
                // This prevents jumping away from screens during token refresh
                final currentTab = MainScreen.currentTabName;
                if (currentTab == 'events' || currentTab == 'messages' || currentTab == 'friends' || currentTab == 'profile') {
                  // Already on a valid tab, don't navigate
                  return;
                }
                mainState.navigateToScreen('events');
              }
            }
          }
        });
      }
    });

    await _ensureServicesInitialized();

    // Initialize unread messages provider
    final unreadMessagesProvider = UnreadMessagesProvider();
    await unreadMessagesProvider.refreshUnreadCount();

    // FCM SETUP
    final FirebaseMessaging messaging = FirebaseMessaging.instance;
    
    // Request permission and configure FCM
    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    // Request location permission at startup
    LocationPermission locationPermission = await Geolocator.checkPermission();
    if (locationPermission == LocationPermission.denied) {
      await Geolocator.requestPermission();
    }

    // Configure FCM to use system notifications for background/terminated state
    await messaging.setForegroundNotificationPresentationOptions(
      alert: false,  // Don't show system notification in foreground
      badge: true,   // Still update badge
      sound: false,  // Don't play sound in foreground
    );

    // Try to get the FCM token, but don't crash if APNS isn't ready
    String? fcmToken;
    try {
      // iOS 18 workaround: call getAPNSToken() before getToken()
      final apnsToken = await messaging.getAPNSToken();
      print('APNs Token: $apnsToken');
      
      // Only proceed with FCM token if APNS token is available
      if (apnsToken != null) {
        fcmToken = await messaging.getToken();
        print('FCM Token: $fcmToken');
        if (fcmToken != null) {
          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            await Supabase.instance.client
                .from('device_tokens')
                .upsert({'user_id': user.id, 'token': fcmToken});
          }
        }
      } else {
        print('APNS token not available yet, will retry later');
      }
    } catch (e) {
      print('FCM token not available yet, will wait for refresh event. Error: $e');
    }

    // Listen for FCM token refresh (handles APNS token becoming available)
    messaging.onTokenRefresh.listen((newToken) async {
      print('FCM Token refreshed: $newToken');
      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null) {
          await Supabase.instance.client
              .from('device_tokens')
              .upsert({'user_id': user.id, 'token': newToken});
          print('Updated device token in database');
        }
      } catch (e) {
        print('Error updating device token: $e');
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.data['type'] == 'friend_request') {
        // Suppress if user is on Friends tab
        final isOnFriendsTab = MainScreen.isFriendsTab;
        print('[NOTIF LOG] isOnFriendsTab: $isOnFriendsTab');
        if (isOnFriendsTab) {
          print('[NOTIF LOG] Suppressing friend request notification: on Friends tab');
          return;
        }
        
        // Set flag to suppress real-time notifications
        showCustomNotification(
          title: message.notification?.title ?? 'Friend Request',
          subtitle: message.notification?.body,
          onTap: () {
            print('🔔 Friend request custom notification tapped - navigating to Friends tab');
            // Refresh friend data immediately
            final context = MainScreen.globalKey.currentContext;
            if (context != null) {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              authProvider.refreshFriendData();
            }
            // Set flag for FriendsScreen to handle navigation
            FriendsScreen.shouldNavigateToAddFriends = true;
            // Navigate to Friends tab
            MainScreen.globalKey.currentState?.navigateToScreen('friends');
            // Use static method to trigger navigation after a delay with multiple attempts
            Future.delayed(const Duration(milliseconds: 300), () {
              FriendsScreen.triggerAddFriendsNavigation();
            });
            // Additional backup trigger with longer delay
            Future.delayed(const Duration(milliseconds: 800), () {
              if (FriendsScreen.shouldNavigateToAddFriends) {
                print('🔔 Friend request: Backup navigation trigger');
                FriendsScreen.triggerAddFriendsNavigation();
              }
            });
            print('🔔 Navigation to Friends tab completed - FriendsScreen will handle tab switching');
          },
          duration: const Duration(seconds: 4),
        );
        // Update badge with combined count
        if (MainScreen.globalKey.currentContext != null) {
          BadgeManager.updateAppBadge(MainScreen.globalKey.currentContext!);
        }
      } else if (message.data['type'] == 'friend_request_accepted') {
        // Handle accepted friend request notifications
        final isOnFriendsTab = MainScreen.isFriendsTab;
        print('[NOTIF LOG] Friend request accepted notification received, isOnFriendsTab: $isOnFriendsTab');
        
        // Suppress if user is on Friends tab
        if (isOnFriendsTab) {
          print('[NOTIF LOG] Suppressing friend request accepted notification: on Friends tab');
          return;
        }
        
        showCustomNotification(
          title: message.notification?.title ?? 'Friend Request Accepted',
          subtitle: message.notification?.body ?? 'Your friend request was accepted!',
          onTap: () {
            print('🔔 Friend request accepted notification tapped - navigating to Friends tab');
            // Refresh friend data immediately
            final context = MainScreen.globalKey.currentContext;
            if (context != null) {
              final authProvider = Provider.of<AuthProvider>(context, listen: false);
              authProvider.refreshFriendData();
            }
            // Navigate to Friends tab
            MainScreen.globalKey.currentState?.navigateToScreen('friends');
          },
          duration: const Duration(seconds: 4),
        );
        // Update badge with combined count
        if (MainScreen.globalKey.currentContext != null) {
          BadgeManager.updateAppBadge(MainScreen.globalKey.currentContext!);
        }
      } else if (message.data['type'] == 'message') {
        // Message notification
        final isOnConversations = MainScreen.isMessagesTab;
        final isOnConversationsUpdated = MainScreen.isMessagesTab;
        final isOnNewMessage = NewMessageScreen.isActive;
        final activeChatId = ChatScreen.activeConversationId;
        final thisConvId = message.data['conversation_id'];
        
        print('[NOTIF LOG] isOnConversations: $isOnConversations, isOnNewMessage: $isOnNewMessage, activeChatId: $activeChatId, thisConvId: $thisConvId');
        
        // Suppress if on Conversations tab (not in New Message, not in a chat)
        if (isOnConversationsUpdated && !isOnNewMessage && activeChatId == null) {
          print('[NOTIF LOG] Suppressing notification: on ConversationsScreen (not NewMessage, not in chat)');
          return;
        }
        // Suppress if in a chat and the message is for the open chat
        if (activeChatId == thisConvId) {
          print('[NOTIF LOG] Suppressing notification: on ChatScreen with active conversation');
          return;
        }
        print('[NOTIF LOG] Showing notification: not on ConversationsScreen or active ChatScreen');
        showCustomNotification(
          title: message.notification?.title ?? 'New Message',
          subtitle: message.notification?.body,
          onTap: () async {
            MainScreen.globalKey.currentState?.navigateToScreen('messages');
            Future.delayed(const Duration(milliseconds: 350), () async {
              final context = MainScreen.globalKey.currentContext;
              if (context != null) {
                // Check if the same conversation is already open
                if (ChatScreen.activeConversationId == thisConvId) {
                  // If already open, just pop to it (no need to push again)
                  Navigator.of(context).popUntil((route) {
                    return route.settings.name == '/chat' || route.isFirst;
                  });
                } else {
                  // Push new chat screen
                  // Mark messages as read immediately before navigating
                  await MessagingService.instance.markConversationAsRead(thisConvId);
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        conversationId: thisConvId,
                        otherParticipantName: null, // Will be fetched in ChatScreen
                      ),
                    ),
                    (route) => route.isFirst, // Pop until root, so back button goes to conversations list
                  ).then((_) {
                    // Force MessagesScreen rebuild after returning from chat
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      MainScreen.forceMessagesScreenRebuildGlobal();
                    });
                  });
                }
              }
            });
          },
          duration: const Duration(seconds: 4),
        );
        // Update badge with combined count
        if (MainScreen.globalKey.currentContext != null) {
          BadgeManager.updateAppBadge(MainScreen.globalKey.currentContext!);
        }
      } else if (message.notification != null) {
        showCustomNotification(
          title: message.notification!.title ?? 'Notification',
          subtitle: message.notification!.body,
          duration: const Duration(seconds: 4),
        );
      }
    });

    // Set up auth state listener to handle device token saving
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final event = data.event;
      final session = data.session;
      
      if (event == AuthChangeEvent.signedIn && session != null) {
        print('User signed in, saving device token...');
        // Get the FCM token and save it to the database
        try {
          final messaging = FirebaseMessaging.instance;
          final fcmToken = await messaging.getToken();
          
          if (fcmToken != null) {
            // Check if this token already exists for this user
            final existingToken = await Supabase.instance.client
                .from('device_tokens')
                .select('*')
                .eq('user_id', session.user.id)
                .eq('token', fcmToken)
                .maybeSingle();
            
            if (existingToken == null) {
              // Token doesn't exist, insert it
              await Supabase.instance.client
                  .from('device_tokens')
                  .insert({
                    'user_id': session.user.id,
                    'token': fcmToken,
                  });
              print('Device token saved for signed-in user: ${session.user.id}');
            } else {
              print('Device token already exists for user: ${session.user.id}');
            }
          }
        } catch (e) {
          // Handle duplicate key errors gracefully
          if (e.toString().contains('duplicate key value violates unique constraint')) {
            print('Device token already exists for user: ${session.user.id}');
          } else {
            print('Error saving device token on auth state change: $e');
          }
        }
      } else if (event == AuthChangeEvent.signedOut) {
        print('User signed out, removing device token...');
        // Remove the device token from the database
        try {
          final messaging = FirebaseMessaging.instance;
          final fcmToken = await messaging.getToken();
          
          if (fcmToken != null) {
            await Supabase.instance.client
                .from('device_tokens')
                .delete()
                .eq('token', fcmToken);
            print('Device token removed for signed-out user');
          }
        } catch (e) {
          print('Error removing device token on auth state change: $e');
        }
      }
    });

    // Handle notification taps (background/terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      print('[NOTIF LOG] onMessageOpenedApp: Notification tapped, type:  [36m${message.data['type']} [0m, conversation_id:  [36m${message.data['conversation_id']} [0m');
      print('[NOTIF LOG] Ensuring services are initialized before navigation');
      await _ensureServicesInitialized();
      
      if (message.data['type'] == 'friend_request') {
        print('🔔 Friend request notification tapped - navigating to Friends tab');
        // Refresh friend data immediately
        final context = MainScreen.globalKey.currentContext;
        if (context != null) {
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          authProvider.refreshFriendData();
        }
        // Set flag for FriendsScreen to handle navigation
        FriendsScreen.shouldNavigateToAddFriends = true;
        // Navigate to Friends tab
        MainScreen.globalKey.currentState?.navigateToScreen('friends');
        // Use static method to trigger navigation after a delay with multiple attempts
        Future.delayed(const Duration(milliseconds: 300), () {
          FriendsScreen.triggerAddFriendsNavigation();
        });
        // Additional backup trigger with longer delay
        Future.delayed(const Duration(milliseconds: 800), () {
          if (FriendsScreen.shouldNavigateToAddFriends) {
            print('🔔 Friend request: Backup navigation trigger');
            FriendsScreen.triggerAddFriendsNavigation();
          }
        });
        print('🔔 Navigation to Friends tab completed - FriendsScreen will handle tab switching');
        return; // Add return to prevent further execution
      } else if (message.data['type'] == 'friend_request_accepted') {
        print('🔔 Friend request accepted notification tapped - navigating to Friends tab');
        // Refresh friend data immediately
        final context = MainScreen.globalKey.currentContext;
        if (context != null) {
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          authProvider.refreshFriendData();
        }
        // Navigate to Friends tab
        MainScreen.globalKey.currentState?.navigateToScreen('friends');
        return; // Add return to prevent further execution
      } else if (message.data['type'] == 'message' && message.data['conversation_id'] != null) {
        // No need for tab index variables since we're using screen names
        final thisConvId = message.data['conversation_id'];
        print('[NOTIF LOG] Navigating to Messages tab and chat $thisConvId');
        MainScreen.globalKey.currentState?.navigateToScreen('messages');
        Future.delayed(const Duration(milliseconds: 800), () async {
          await _ensureServicesInitialized();
          final context = MainScreen.globalKey.currentContext;
          if (context != null) {
            if (ChatScreen.activeConversationId == thisConvId) {
              print('[NOTIF LOG] Already in the correct conversation, no navigation needed');
              return;
            }
            print('[NOTIF LOG] Pushing ChatScreen for conversation $thisConvId');
            // Mark messages as read immediately before navigating
            await MessagingService.instance.markConversationAsRead(thisConvId);
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (context) => ChatScreen(
                  conversationId: thisConvId,
                  otherParticipantName: null,
                ),
              ),
              (route) => route.isFirst, // Pop until root, so back button goes to conversations list
            ).then((_) {
              print('[NOTIF LOG] Returned from ChatScreen (notification navigation), forcing MessagesScreen rebuild');
              WidgetsBinding.instance.addPostFrameCallback((_) {
                MainScreen.forceMessagesScreenRebuildGlobal();
              });
            });
          }
        });
      }
    });

    // Handle notification tap if app was launched from terminated state
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      print('[NOTIF LOG] getInitialMessage: App launched from notification, type:  [36m${initialMessage.data['type']} [0m, conversation_id:  [36m${initialMessage.data['conversation_id']} [0m');
      print('[NOTIF LOG] Ensuring services are initialized before navigation (app launch)');
      await _ensureServicesInitialized();
      
      if (initialMessage.data['type'] == 'friend_request') {
        print('🔔 Friend request notification tapped (app launch) - navigating to Friends tab');
        // Refresh friend data immediately
        // Use the context after the app is built
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // Double-check services are initialized
          await _ensureServicesInitialized();
          
          final context = MainScreen.globalKey.currentContext;
          if (context != null) {
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            authProvider.refreshFriendData();
          }
          // Set flag for FriendsScreen to handle navigation
          FriendsScreen.shouldNavigateToAddFriends = true;
          // Navigate to Friends tab
          MainScreen.globalKey.currentState?.navigateToScreen('friends');
          // Use static method to trigger navigation after a delay with multiple attempts
          Future.delayed(const Duration(milliseconds: 500), () {
            FriendsScreen.triggerAddFriendsNavigation();
          });
          // Additional backup trigger with longer delay
          Future.delayed(const Duration(milliseconds: 1000), () {
            if (FriendsScreen.shouldNavigateToAddFriends) {
              print('🔔 Friend request (app launch): Backup navigation trigger');
              FriendsScreen.triggerAddFriendsNavigation();
            }
          });
          print('🔔 Navigation to Friends tab completed (app launch) - FriendsScreen will handle tab switching');
        });
        return; // Add return to prevent further execution
      } else if (initialMessage.data['type'] == 'friend_request_accepted') {
        print('🔔 Friend request accepted notification tapped (app launch) - navigating to Friends tab');
        // Refresh friend data immediately
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          // Double-check services are initialized
          await _ensureServicesInitialized();
          
          final context = MainScreen.globalKey.currentContext;
          if (context != null) {
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            authProvider.refreshFriendData();
          }
          // Navigate to Friends tab
          MainScreen.globalKey.currentState?.navigateToScreen('friends');
          print('🔔 Navigation to Friends tab completed (app launch)');
        });
        return; // Add return to prevent further execution
      } else if (initialMessage.data['type'] == 'message' && initialMessage.data['conversation_id'] != null) {
        // No need for tab index variables since we're using screen names
        final thisConvId = initialMessage.data['conversation_id'];
        print('[NOTIF LOG] Navigating to Messages tab and chat $thisConvId (app launch)');
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _ensureServicesInitialized();
          MainScreen.globalKey.currentState?.navigateToScreen('messages');
          Future.delayed(const Duration(milliseconds: 1200), () async {
            await _ensureServicesInitialized();
            final context = MainScreen.globalKey.currentContext;
            if (context != null) {
              if (ChatScreen.activeConversationId == thisConvId) {
                print('[NOTIF LOG] Already in the correct conversation, no navigation needed (app launch)');
                return;
              }
              print('[NOTIF LOG] Pushing ChatScreen for conversation $thisConvId (app launch)');
              // Mark messages as read immediately before navigating
              await MessagingService.instance.markConversationAsRead(thisConvId);
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    conversationId: thisConvId,
                    otherParticipantName: null,
                  ),
                ),
                (route) => route.isFirst, // Pop until root, so back button goes to conversations list
              ).then((_) {
                print('[NOTIF LOG] Returned from ChatScreen (notification navigation, app launch), forcing MessagesScreen rebuild');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  MainScreen.forceMessagesScreenRebuildGlobal();
                });
              });
            }
          });
        });
      }
    }

    runApp(
      OverlaySupport.global(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (context) {
              final provider = AuthProvider();
              
              // Set up callback for friend request accepted notifications
              provider.onFriendRequestAccepted = (String receiverName) {
                // Suppress if user is on Friends tab
                final isOnFriendsTab = MainScreen.isFriendsTab;
                print('[NOTIF LOG] Real-time friend request accepted, isOnFriendsTab: $isOnFriendsTab');
                
                if (isOnFriendsTab) {
                  print('[NOTIF LOG] Suppressing real-time friend request accepted notification: on Friends tab');
                  return;
                }
                
                showCustomNotification(
                  title: 'Friend Request Accepted',
                  subtitle: '$receiverName accepted your friend request!',
                  onTap: () {
                    print('🔔 Real-time friend request accepted notification tapped - navigating to Friends tab');
                    // Refresh friend data immediately
                    final context = MainScreen.globalKey.currentContext;
                    if (context != null) {
                      final authProvider = Provider.of<AuthProvider>(context, listen: false);
                      authProvider.refreshFriendData();
                    }
                    // Navigate to Friends tab
                    MainScreen.globalKey.currentState?.navigateToScreen('friends');
                  },
                  duration: const Duration(seconds: 4),
                );
                // Update badge with combined count
                if (MainScreen.globalKey.currentContext != null) {
                  BadgeManager.updateAppBadge(MainScreen.globalKey.currentContext!);
                }
              };
              
              return provider;
            }),
            ChangeNotifierProvider<UnreadMessagesProvider>.value(value: unreadMessagesProvider),
    
          ],
          child: AppLifecycleReactor(
            child: const MyApp(),
          ),
        ),
      ),
    );
    _displayAllUsers();
    _checkDeviceTokens();
  } catch (e, stack) {
    print('Error during app initialization: $e');
    print(stack);
    // Optionally, show a fallback error screen here
  }
}

// Temporary function to display all users
void _displayAllUsers() async {
  // Debug function removed
}

// Debug function to check device tokens
void _checkDeviceTokens() async {
  // Debug function removed
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Maps App',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0065FF),
          primary: const Color(0xFF0065FF),
          secondary: const Color(0xFF6C63FF),
          tertiary: const Color(0xFFFF6584),
          surface: Colors.white,
          background: const Color(0xFFF8F9FA),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -1.0,
          ),
          displayMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            letterSpacing: 0.1,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            letterSpacing: 0.1,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF0065FF),
          titleTextStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0065FF),
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          selectedItemColor: AppColours.buttonPrimary,
          unselectedItemColor: Color(0xFF9E9E9E),
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF0065FF), width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
              // Disable all page transitions for seamless loading
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: NoTransitionsBuilder(),
          TargetPlatform.android: NoTransitionsBuilder(),
        },
      ),
      ),
      navigatorObservers: [routeObserver],
              builder: (context, child) {
          return GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            behavior: HitTestBehavior.translucent,
            child: child ?? const SizedBox.shrink(),
          );
        },
      home: MainScreen(key: MainScreen.globalKey),
    );
  }
}

// Custom page transition builder that shows no animation
class NoTransitionsBuilder extends PageTransitionsBuilder {
  const NoTransitionsBuilder();

  @override
  Widget buildTransitions<T extends Object?>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  
  // Create a static global key to access the state
  static final GlobalKey<_MainScreenState> globalKey = GlobalKey<_MainScreenState>();
  
  // Static method to navigate to a tab
  static void navigateToTab(BuildContext context, int index) {
    final state = globalKey.currentState;
    if (state != null) {
      state.navigateToTab(index);
    }
  }

  // Static method to navigate to a screen by name
  static void navigateToScreen(BuildContext context, String screenName) {
    final state = globalKey.currentState;
    if (state != null) {
      state.navigateToScreen(screenName);
    }
  }

  // Static getter for current tab index
  static int? get currentTabIndex => globalKey.currentState?._selectedIndex;

  // Static getter for showAllNavItems
  static bool get showAllNavItems => globalKey.currentState?._showAllNavItems ?? false;

  // Helper methods to check which tab is currently active
  static bool get isEventsTab => currentTabIndex == 0;
  static bool get isMessagesTab => currentTabIndex == 1;
  static bool get isFriendsTab => currentTabIndex == 2;
  static bool get isProfileTab => currentTabIndex == 3;

  // Get current tab name
  static String get currentTabName {
    switch (currentTabIndex) {
      case 0: return 'events';
      case 1: return 'messages';
      case 2: return 'friends';
      case 3: return 'profile';
      default: return 'events';
    }
  }

  // Check if a tab index requires authentication
  static bool isProtectedTab(int index) {
    // Events tab (0) is public, others require authentication
    return index != 0;
  }

  // Get tab name from index
  static String getTabName(int index) {
    switch (index) {
      case 0: return 'events';
      case 1: return 'messages';
      case 2: return 'friends';
      case 3: return 'profile';
      default: return 'events';
    }
  }

  // Get tab index from name
  static int? getTabIndex(String tabName) {
    switch (tabName.toLowerCase()) {
      case 'events': return 0;
      case 'messages': return 1;
      case 'friends': return 2;
      case 'profile': return 3;
      default: return null;
    }
  }

  // Add this static method directly to the class:
  static void forceMessagesScreenRebuildGlobal() {
    globalKey.currentState?.forceMessagesScreenRebuild();
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

// Helper widget to add red square overlay
class TabIconOverlay extends StatelessWidget {
  final Widget icon;

  TabIconOverlay({super.key, required this.icon});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Use a fixed value since this is a const widget
    const numberOfTabs = 4;
    final tabWidth = screenWidth / numberOfTabs;

    return SizedBox(
      width: tabWidth,
      height: 72,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.0),
              ),
            ),
          ),
          Positioned.fill(
            top: 16, // Standard material bottom nav item top padding
            child: Align(
              alignment: Alignment.topCenter,
              child: icon,
            ),
          ),
        ],
      ),
    );
  }
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  
  // Flag to control which navigation items are visible
  final bool _showAllNavItems = false; // Set to false to hide Home, Groups, and Map
  
  // Updated titles for all screens
  final List<String> _titles = ['Events', 'Messages', 'Friends', 'Profile'];
  
  // Add a key for MessagesScreen to force rebuild
  Key _messagesScreenKey = UniqueKey();
  late List<Widget> _screens = _buildScreens();

  // Add state for hiding bottom nav bar
  bool _hideBottomNavBar = false;
  
  // Get profile navigation item - handle both authenticated and unauthenticated users
  BottomNavigationBarItem _getProfileNavItem(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    if (authProvider.isAuthenticated && authProvider.currentUser != null) {
      final user = authProvider.currentUser!;
      
      // Get user initials for the avatar with null safety
      String initials;
      if (user.firstName != null && user.lastName != null && 
          user.firstName!.isNotEmpty && user.lastName!.isNotEmpty) {
        initials = '${user.firstName![0]}${user.lastName![0]}'.toUpperCase();
      } else if (user.username.isNotEmpty) {
        initials = user.username[0].toUpperCase();
      } else {
        initials = 'U';
      }

      return BottomNavigationBarItem(
        icon: TabIconOverlay(
          icon: CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).bottomNavigationBarTheme.unselectedItemColor,
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        activeIcon: TabIconOverlay(
          icon: CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ),
        label: user.username.isNotEmpty ? user.username : 'Profile',
      );
    } else {
      // Show generic profile icon for unauthenticated users
      return BottomNavigationBarItem(
        icon: TabIconOverlay(
          icon: CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).bottomNavigationBarTheme.unselectedItemColor,
            child: const Icon(
              Icons.person_outline,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
        activeIcon: TabIconOverlay(
          icon: CircleAvatar(
            radius: 12,
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: const Icon(
              Icons.person_outline,
              size: 16,
              color: Colors.white,
            ),
          ),
        ),
        label: 'Profile',
      );
    }
  }
  
  List<Widget> _buildScreens() {
    return [
      EventScreen(key: EventScreen.globalKey),
      MessagesScreen(key: _messagesScreenKey),
      FriendsScreen(key: FriendsScreen.globalKey),
      ProfileScreen(),
    ];
  }



  @override
  void initState() {
    super.initState();
    _selectedIndex = _showAllNavItems ? 0 : 0;
    WidgetsBinding.instance.addObserver(this);
    // Remove realtime subscription since FCM handles notifications
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Remove channel unsubscribe since we no longer have a channel
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {

      final context = this.context;
      // Only refresh if user is authenticated
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated) {
        authProvider.refreshFriendData();
      }
      
      // Also check and clear any SSO loading states immediately
      // But only if we're not in the middle of an OAuth flow
      if (!authProvider.isOAuthFlowInProgress) {
        // Only check SSO loading state if we're not currently in an OAuth flow
        // This prevents interference with ongoing OAuth flows
        authProvider.checkAndClearSSOLoadingState();
      } else {
        print('🔐 App resumed during OAuth flow, skipping SSO loading state check');
      }
    }
  }
  
  // Method to allow other classes to navigate to a specific tab
  void navigateToTab(int index) {

    setState(() {
      _selectedIndex = index;
    });
    // Navigation completed
  }

  // Method to navigate to specific screens by name
  void navigateToScreen(String screenName) {
    final index = MainScreen.getTabIndex(screenName);
    if (index == null) {
      // Unknown screen name
      return;
    }
    // Navigating to screen
    setState(() {
      _selectedIndex = index;
    });
    // Navigation completed
  }
  
  // Getter for the current selected index
  int get selectedIndex => _selectedIndex;

  // Method to force a rebuild of the MessagesScreen
  void forceMessagesScreenRebuild() {
    setState(() {
      _messagesScreenKey = UniqueKey();
      _screens = _buildScreens();

    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedIndex,
            children: _screens,
          ),
          const FeedbackButton(),
        ],
      ),
      bottomNavigationBar: AnimatedSlide(
        offset: _hideBottomNavBar ? const Offset(0, 1) : Offset.zero,
        duration: const Duration(milliseconds: 180),
        curve: Curves.fastOutSlowIn,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: _hideBottomNavBar ? 0 : 72,
          curve: Curves.fastOutSlowIn,
          child: Theme(
            data: Theme.of(context).copyWith(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
            ),
            child: Wrap(
              children: [
                Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 2,
                        offset: const Offset(0, -1),
                      ),
                    ],
                  ),
                  child: Consumer<AuthProvider>(
                    builder: (context, authProvider, child) {
                      return BottomNavigationBar(
                        currentIndex: _selectedIndex,
                        onTap: (index) {
                          // Check if user is authenticated for protected tabs
                          final authProvider = Provider.of<AuthProvider>(context, listen: false);
                          final isAuthenticated = authProvider.isAuthenticated;
                          
                          // Check if the selected tab requires authentication
                          if (!isAuthenticated && MainScreen.isProtectedTab(index)) {
                            // Show auth popup for unauthenticated users trying to access protected tabs
                            AuthFlowScreen.push(context);
                            return;
                          }
                          
                          // If tapping the Events tab and it's already selected, reset to event list
                          if (index == 0 && MainScreen.isEventsTab) {
                                  final eventsState = EventScreen.globalKey.currentState;
      if (eventsState != null) {
        eventsState.resetToEventList();
      }
                          }
                          setState(() {
                            _selectedIndex = index;
                          });
                        },
                        iconSize: 24.0,
                        selectedLabelStyle: const TextStyle(fontSize: 0.0),
                        unselectedLabelStyle: const TextStyle(fontSize: 0.0),
                        elevation: 0,
                        type: BottomNavigationBarType.fixed,
                        items: [
                              BottomNavigationBarItem(
                                icon: TabIconOverlay(icon: const Icon(Icons.event)),
                                label: 'Events',
                              ),
                                                            BottomNavigationBarItem(
                                icon: Consumer<UnreadMessagesProvider>(
                                  builder: (context, unreadProvider, _) {
                                    final count = unreadProvider.unreadCount;
                                    return TabIconOverlay(
                                      icon: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          const Icon(Icons.message),
                                          if (count > 0)
                                            Positioned(
                                              right: -4,
                                              top: -6,
                                              child: Container(
                                                width: 16,
                                                height: 16,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF0065FF),
                                                  shape: BoxShape.circle,
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  count.toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                label: 'Messages',
                              ),
                              // Map tab removed
                              BottomNavigationBarItem(
                                icon: Consumer<AuthProvider>(
                                  builder: (context, authProvider, _) {
                                    final count = authProvider.pendingFriendRequests.length;
                                    return TabIconOverlay(
                                      icon: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          const Icon(Icons.people),
                                          if (count > 0)
                                            Positioned(
                                              right: -4,
                                              top: -6,
                                              child: Container(
                                                width: 16,
                                                height: 16,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF0065FF),
                                                  shape: BoxShape.circle,
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  count.toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                label: 'Friends',
                              ),
                              _getProfileNavItem(context),
                            ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Add this widget to handle app lifecycle events


class AppLifecycleReactor extends StatefulWidget {
  final Widget child;
  const AppLifecycleReactor({required this.child, super.key});

  @override
  State<AppLifecycleReactor> createState() => _AppLifecycleReactorState();
}

class _AppLifecycleReactorState extends State<AppLifecycleReactor> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {

      final context = this.context;
      // Only refresh if user is authenticated
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (authProvider.isAuthenticated) {
        authProvider.refreshFriendData();
      }
      
      // Also check and clear any SSO loading states immediately
      // But only if we're not in the middle of an OAuth flow
      if (!authProvider.isOAuthFlowInProgress) {
        // Only check SSO loading state if we're not currently in an OAuth flow
        // This prevents interference with ongoing OAuth flows
        authProvider.checkAndClearSSOLoadingState();
      } else {
        print('🔐 App resumed during OAuth flow, skipping SSO loading state check');
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}


