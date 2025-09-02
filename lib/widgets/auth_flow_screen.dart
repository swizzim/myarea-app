import 'package:flutter/material.dart';
import 'package:myarea_app/screens/auth/welcome_screen.dart';
import 'package:myarea_app/screens/auth/signup_screen.dart';
import 'package:myarea_app/screens/auth/login_screen.dart';
import 'package:myarea_app/screens/auth/set_username_screen.dart';
import 'package:myarea_app/screens/auth/email_verification_screen.dart';
import 'package:myarea_app/screens/auth/voluntary_info_screen.dart';
import 'package:myarea_app/screens/auth/invite_friends_screen.dart';
import 'package:myarea_app/screens/auth/forgot_password_screen.dart';

class AuthFlowScreen extends StatefulWidget {
  final VoidCallback? onClose;
  const AuthFlowScreen({super.key, this.onClose});

  static void push(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const AuthFlowScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final offsetAnimation = Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));
          return SlideTransition(
            position: offsetAnimation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        opaque: true,
        barrierDismissible: false,
      ),
    );
  }

  @override
  State<AuthFlowScreen> createState() => _AuthFlowScreenState();
}

class _AuthFlowScreenState extends State<AuthFlowScreen> {
  String _currentScreen = 'welcome';
  Map<String, dynamic> _authData = {};

  void _close() {
    print('Auth flow _close called');
    // Use pop() instead of maybePop() for more reliable navigation
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      print('Cannot pop navigator, trying alternative approach');
      // Try to pop until we can't pop anymore
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    widget.onClose?.call();
  }

  void _navigateToScreen(String screen, {Map<String, dynamic>? data}) {
    // Handle SSO data if coming from welcome screen
    if (screen == 'signup2' && data != null && data['provider'] != null) {
      // This is SSO data, update auth data accordingly
      _authData = {
        'email': data['email'] ?? '',
        'firstName': data['firstName'],
        'lastName': data['lastName'],
        'appleUserId': data['appleUserId'],
        'provider': data['provider'],
      };
    } else if (data != null) {
      // For regular flows, add to existing auth data
      _authData.addAll(data);
    }
    
    setState(() {
      _currentScreen = screen;
    });
  }

  void _onAuthSuccess() {
    print('Auth flow _onAuthSuccess called');
    _close();
  }

  Widget _buildCurrentScreen() {
    switch (_currentScreen) {
      case 'welcome':
        return WelcomeScreen(
          onGetStarted: (data) {
            // Check if this is SSO data from OAuth
            if (data != null && data['provider'] != null) {
              // This is SSO data, navigate directly to signup2
              _navigateToScreen('signup2', data: data);
            } else {
              // Regular signup flow - no data needed
              _navigateToScreen('signup');
            }
          },
          onLogin: () => _navigateToScreen('login'),
        );
      case 'signup':
        return SignupScreen(
          onNext: (data) => _navigateToScreen('signup2', data: data),
          onBack: () => _navigateToScreen('welcome'),
          onClose: () => _close(),
          onSwitchToLogin: () => _navigateToScreen('login'),
        );
      case 'signup2':
        return SetUsernameScreen(
          authData: _authData,
          onNext: (data) {
            // For SSO users, skip email verification and go straight to voluntary info
            if (_authData['provider'] != null) {
              _navigateToScreen('voluntary', data: data);
            } else {
              _navigateToScreen('emailVerification', data: data);
            }
          },
          onBack: () => _navigateToScreen(_authData['provider'] != null ? 'welcome' : 'signup'),
        );
      case 'emailVerification':
        return EmailVerificationScreen(
          authData: _authData,
          onNext: (data) => _navigateToScreen('voluntary', data: data),
          onBack: () {
            // Determine where to go back based on the flow
            if (_authData.containsKey('email') && _authData.containsKey('password')) {
              // This is likely from login flow, go back to login
              _navigateToScreen('login');
            } else {
              // This is from signup flow, go back to signup2
              _navigateToScreen('signup2');
            }
          },
          onClose: () => _close(),
        );
      case 'voluntary':
        return VoluntaryInfoScreen(
          authData: _authData,
          initialCategories: (_authData['preloadedCategories'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
          onNext: (data) => _navigateToScreen('invite', data: data),
          onSkip: () => _onAuthSuccess(),
          onBack: () => _navigateToScreen(_authData['provider'] != null ? 'signup2' : 'emailVerification'),
        );
      case 'invite':
        return InviteFriendsScreen(
          authData: _authData,
          onComplete: () => _onAuthSuccess(),
          onSkip: () => _onAuthSuccess(),
          onBack: () => _navigateToScreen('voluntary'),
        );
      case 'login':
        return LoginScreen(
          onSuccess: () => _onAuthSuccess(),
          onBack: () => _navigateToScreen('welcome'),
          onClose: () => _close(),
          onForgotPassword: () => _navigateToScreen('forgotPassword'),
          onSwitchToSignup: () => _navigateToScreen('signup'),
          onEmailNotVerified: (email, password) {
            // Handle email not verified case by going to email verification
            _authData = {
              'email': email,
              'password': password,
            };
            _navigateToScreen('emailVerification');
          },
        );
      case 'forgotPassword':
        return ForgotPasswordScreen(
          onClose: _close,
          onBack: () => _navigateToScreen('login'),
        );
      default:
        return WelcomeScreen(
          onGetStarted: (data) {
            // Check if this is SSO data from OAuth
            if (data != null && data['provider'] != null) {
              // This is SSO data, navigate directly to signup2
              _navigateToScreen('signup2', data: data);
            } else {
              // Regular signup flow - no data needed
              _navigateToScreen('signup');
            }
          },
          onLogin: () => _navigateToScreen('login'),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _buildCurrentScreen(),
    );
  }
} 