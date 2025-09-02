import 'package:flutter/material.dart';
import 'package:myarea_app/screens/auth/login_screen.dart';
import 'package:myarea_app/screens/auth/signup_screen.dart';
import 'package:myarea_app/widgets/sso_buttons.dart';

class WelcomeScreen extends StatefulWidget {
  final Function(Map<String, dynamic>?)? onGetStarted;
  final VoidCallback? onLogin;
  
  const WelcomeScreen({super.key, this.onGetStarted, this.onLogin});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isSSOLoading = false;

  @override
  Widget build(BuildContext context) {
    final vibrantBlue = const Color(0xFF0065FF);
    
    void _handleClose() {
      Navigator.of(context).maybePop();
    }
    
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Centered logo with X button at the top
          Padding(
            padding: const EdgeInsets.only(top: 4.0, right: 8.0, left: 8.0),
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Centered logo
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.map, size: 28, color: vibrantBlue),
                      const SizedBox(width: 8),
                      Text(
                        'MyArea',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: vibrantBlue,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  // X button at the right
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.grey,
                        size: 24,
                      ),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _isSSOLoading ? null : _handleClose,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Add spacing between logo and welcome message to match sign in screen
          const SizedBox(height: 18),
          // Main content with horizontal padding
          Expanded(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 0.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  const Text(
                    'Welcome to MyArea!',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  
                  // Subtitle
                  Text(
                    'Sign in to access your profile, save events and connect with your friends.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey[700],
                      height: 1.35,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  
                  // Benefits list
                  Column(
                    children: [
                      _buildBenefitItem(
                        icon: Icons.event,
                        title: 'Save Events',
                        description: 'Save and track events you want to attend',
                      ),
                      const SizedBox(height: 12),
                      _buildBenefitItem(
                        icon: Icons.share,
                        title: 'Share Events',
                        description: 'Share events with friends and family',
                      ),
                      const SizedBox(height: 12),
                      _buildBenefitItem(
                        icon: Icons.message,
                        title: 'Message Friends',
                        description: 'Chat with friends and coordinate plans',
                      ),
                      const SizedBox(height: 12),
                      _buildBenefitItem(
                        icon: Icons.group,
                        title: 'Event Group Chats',
                        description: 'Create group chats for events',
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  
                  // Sign In Button
                  ElevatedButton(
                    onPressed: _isSSOLoading ? null : () {
                      if (widget.onLogin != null) {
                        widget.onLogin!();
                      } else {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vibrantBlue,
                      disabledBackgroundColor: vibrantBlue,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      minimumSize: const Size(double.infinity, 45),
                      splashFactory: NoSplash.splashFactory,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.login, 
                          size: 22,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Sign In',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Create Account Button
                  OutlinedButton(
                    onPressed: _isSSOLoading ? null : () {
                      if (widget.onGetStarted != null) {
                        widget.onGetStarted!(null); // No data for regular signup
                      } else {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => const SignupScreen(),
                            transitionDuration: Duration.zero,
                            reverseTransitionDuration: Duration.zero,
                          ),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: vibrantBlue, 
                        width: 1
                      ),
                      foregroundColor: vibrantBlue,
                      disabledForegroundColor: vibrantBlue,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      minimumSize: const Size(double.infinity, 45),
                      splashFactory: NoSplash.splashFactory,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_add_outlined, 
                          size: 22,
                          color: vibrantBlue,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: vibrantBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // SSO Buttons
                  SSOButtons(
                    onResult: (result) {
                      if (result['success'] == true) {
                        if (result['needsUsername'] == true) {
                          // Navigate to auth flow modal for username setup
                          if (widget.onGetStarted != null) {
                            // Pass SSO data to auth flow
                            widget.onGetStarted!({
                              'email': result['email'] ?? '',
                              'firstName': result['firstName'],
                              'lastName': result['lastName'],
                              'provider': result['provider'],
                            });
                          }
                        } else {
                          // User already has username, close auth flow
                          _handleClose();
                        }
                      }
                    },
                    onLoadingStateChanged: (isLoading) {
                      setState(() {
                        _isSSOLoading = isLoading;
                      });
                    },
                  ),

                  // Additional info
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      'Join thousands of users discovering their local area!',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper widget for benefit items
  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
    final vibrantBlue = const Color(0xFF0065FF);
    
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: vibrantBlue,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(
            icon,
            size: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
} 