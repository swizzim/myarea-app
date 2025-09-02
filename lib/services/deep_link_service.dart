import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/services/auth_storage_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myarea_app/main.dart';
import 'package:myarea_app/screens/events/events_screen.dart';
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/providers/auth_provider.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  bool _isInitialized = false;
  String? _pendingEventId;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Handle app links while app is running
      _appLinks.uriLinkStream.listen((Uri? uri) async {
        if (uri != null) {
          await _handleDeepLink(uri);
        }
      });

      // Handle app links when app is opened from a link
      final Uri? initialUri = await _appLinks.getInitialAppLink();
      if (initialUri != null) {
        await _handleDeepLink(initialUri);
      }

      _isInitialized = true;
    } catch (e) {
      print('Error initializing deep link service: $e');
    }
  }

  Future<void> _handleDeepLink(Uri uri) async {
    print('Handling deep link: $uri');
    
    // Handle OAuth callback from app scheme
    if (uri.scheme == 'io.supabase.myareaapp' && uri.host == 'login-callback') {
      print('OAuth callback received from app scheme, handling authentication...');
      
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];
      
      if (error != null) {
        print('OAuth error received: $error');
        // Notify auth provider of OAuth failure
        _notifyOAuthCompletion(false);
        return;
      }
      
      if (code != null) {
        print('OAuth success - code received: $code');
        
        try {
          print('Attempting to manually complete OAuth flow for internal browser...');
          
          // Get stored PKCE verifier from auth storage service
          final authStorage = AuthStorageService();
          final verifier = await authStorage.getVerifier();
          
          if (verifier != null) {
            try {
              // Exchange code for session
              await Supabase.instance.client.auth.exchangeCodeForSession(code);
              print('OAuth flow completed successfully');
              
              // Clear the verifier after successful exchange
              await authStorage.clearVerifier();
              
              // External browser will close automatically after redirect
              
              // Notify auth provider of OAuth success
              _notifyOAuthCompletion(true);
            } catch (e) {
              print('Error exchanging code: $e');
              
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
                    _notifyOAuthCompletion(true);
                  }
                } catch (retryError) {
                  print('🔐 Failed to retry code exchange: $retryError');
                  await authStorage.clearVerifier();
                  _notifyOAuthCompletion(false);
                }
              } else {
                // Clear verifier on other errors to prevent future issues
                await authStorage.clearVerifier();
                _notifyOAuthCompletion(false);
              }
              
              // External browser will close automatically
            }
          } else {
            print('No PKCE verifier found for code exchange');
            _notifyOAuthCompletion(false);
            // External browser will close automatically
          }
        } catch (e) {
          print('Manual OAuth completion failed: $e');
          _notifyOAuthCompletion(false);
          // External browser will close automatically
        }
        
        // Navigation is now handled in the session confirmation block
      }
    }
    
    // Handle website links
    if (uri.host == 'myarea.com.au') {
      // Event links: https://myarea.com.au/event/:id
      if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'event') {
        final eventId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
        if (eventId != null) {
          _navigateToEvent(eventId);
        }
        return;
      }

      // Referral links: https://myarea.com.au/r/:code or any url with ?ref=:code
      String? referralCode;
      if (uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'r') {
        referralCode = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
      }
      referralCode ??= uri.queryParameters['ref'];

      if (referralCode != null && referralCode.isNotEmpty) {
        try {
          final authStorage = AuthStorageService();
          await authStorage.setPendingReferrer(referralCode);
          print('🔗 Captured referral code from deep link: $referralCode');
          
          // If user is already logged in, process referral immediately
          final currentUser = Supabase.instance.client.auth.currentUser;
          if (currentUser != null && currentUser.id != null) {
            print('🔗 User is logged in, processing referral immediately');
            // Try to process the referral immediately if context is available
            try {
              final context = MainScreen.globalKey.currentContext;
              if (context != null) {
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
                await authProvider.processPendingReferral();
              }
            } catch (e) {
              print('🔗 Error processing referral immediately: $e');
              // Fallback: referral will be processed on next auth lifecycle
            }
          }
        } catch (e) {
          print('🔗 Error capturing referral code: $e');
        }
      }
    }
  }

  Future<void> _navigateToMainApp() async {
    print('Attempting to navigate to main app...');
    
    // Try multiple times with a delay to wait for MainScreen to be ready
    for (int i = 0; i < 5; i++) {
      final mainState = MainScreen.globalKey.currentState;
      if (mainState != null) {
        print('MainScreen state found, navigating to Events tab');
        mainState.navigateToScreen('events');
        return;
      }
      print('MainScreen state is null, waiting for initialization...');
      await Future.delayed(Duration(milliseconds: 200));
    }
    
    print('Failed to navigate after retries - MainScreen not available');
  }

  void _navigateToEvent(String eventId) {
    final mainState = MainScreen.globalKey.currentState;
    if (mainState != null) {
      mainState.navigateToScreen('events');
      
      final eventsState = EventScreen.globalKey.currentState;
      if (eventsState != null) {
        eventsState.navigateToEventById(eventId);
      } else {
        _pendingEventId = eventId;
      }
    } else {
      _pendingEventId = eventId;
    }
  }

  void onEventScreenReady(EventScreenState eventsState) {
    if (_pendingEventId != null) {
      eventsState.navigateToEventById(_pendingEventId!);
      _pendingEventId = null;
    }
  }

  static String generateEventLink(String eventId) {
    return 'https://myarea.com.au/event/$eventId';
  }

  static String generateCustomSchemeLink(String eventId) {
    return 'io.supabase.myareaapp://event/$eventId';
  }

  static String generateOAuthCallbackUrl() {
    return 'io.supabase.myareaapp://login-callback';
  }

  // Referral link generator
  static String generateReferralLink(String referralCode) {
    return 'https://myarea.com.au/r/$referralCode';
  }

  // Helper method to notify auth provider of OAuth completion
  void _notifyOAuthCompletion(bool success) {
    try {
      final context = MainScreen.globalKey.currentContext;
      if (context != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        authProvider.handleOAuthCompletion(success);
      } else {
        print('🔐 No context available to notify auth provider');
      }
    } catch (e) {
      print('🔐 Error notifying auth provider: $e');
    }
  }
}