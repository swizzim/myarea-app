import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'dart:io' show Platform;

class SSOButtons extends StatefulWidget {
  final Function(Map<String, dynamic>)? onResult;
  final bool showDivider;
  final Function(bool)? onLoadingStateChanged;

  const SSOButtons({
    super.key,
    this.onResult,
    this.showDivider = true,
    this.onLoadingStateChanged,
  });

  @override
  State<SSOButtons> createState() => _SSOButtonsState();
}

class _SSOButtonsState extends State<SSOButtons> {
  bool _isGoogleLoading = false;
  bool _isAppleLoading = false;
  String _lastErrorMessage = '';

  void _updateLoadingState() {
    final isLoading = _isGoogleLoading || _isAppleLoading;
    widget.onLoadingStateChanged?.call(isLoading);
  }

  void _showErrorSnackBar(String message) {
    if (message.isNotEmpty && message != _lastErrorMessage) {
      _lastErrorMessage = message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Only show SSO-specific errors here to confine them to welcome screen
        if (authProvider.ssoErrorMessage.isNotEmpty && authProvider.ssoErrorMessage != _lastErrorMessage) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showErrorSnackBar(authProvider.ssoErrorMessage);
            // Consume the error so it doesn't re-trigger when returning to this screen
            authProvider.clearSSOErrorMessage();
          });
        }

        return Column(
          children: [
            if (widget.showDivider) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey[300])),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.grey[300])),
                ],
              ),
              const SizedBox(height: 16),
            ],
            
            // Google Sign In Button
            OutlinedButton.icon(
              onPressed: _isGoogleLoading || _isAppleLoading ? null : () async {
                print('🔐 Google SSO button pressed');
                
                // Clear any previous error messages when starting new SSO attempt
                _lastErrorMessage = '';
                final auth = Provider.of<AuthProvider>(context, listen: false);
                auth.clearSSOErrorMessage();
                
                print('🔐 Setting local loading state to true');
                setState(() {
                  _isGoogleLoading = true;
                });
                _updateLoadingState();
                
                print('🔐 Calling auth.signInWithGoogle()');
                try {
                  final result = await auth.signInWithGoogle();
                  print('🔐 signInWithGoogle completed with result: $result');
                  
                  if (result['success'] == true) {
                    if (result['needsUsername'] == true) {
                      // User needs to set up username
                      if (widget.onResult != null) {
                        widget.onResult!({
                          'success': true,
                          'needsUsername': true,
                          'email': result['email'],
                          'firstName': result['firstName'],
                          'lastName': result['lastName'],
                          'provider': 'google',
                        });
                      }
                    } else {
                      // User exists and has username
                      if (widget.onResult != null) {
                        widget.onResult!({
                          'success': true,
                          'needsUsername': false,
                        });
                      }
                    }
                  }
                  // Note: Error messages are now handled by the AuthProvider listener above
                  // No need to manually show snackbars here
                } catch (e) {
                  print('🔐 Error in signInWithGoogle: $e');
                } finally {
                  print('🔐 Finally block - clearing loading state');
                  if (mounted) {
                    setState(() {
                      _isGoogleLoading = false;
                    });
                    _updateLoadingState();
                  }
                }
              },
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.grey[300]!),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                minimumSize: const Size(double.infinity, 45),
                backgroundColor: Colors.white,
                disabledBackgroundColor: Colors.white,
                splashFactory: NoSplash.splashFactory,
              ),
              icon: _isGoogleLoading 
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
                      ),
                    )
                  : Image.asset(
                      'assets/images/google_logo.png',
                      width: 24,
                      height: 24,
                    ),
              label: _isGoogleLoading
                  ? Text(
                      'Signing in...',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[600],
                        letterSpacing: 0.3,
                      ),
                    )
                  : const Text(
                      'Continue with Google',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                        letterSpacing: 0.3,
                      ),
                    ),
            ),
            
            if (Platform.isIOS) ...[
              const SizedBox(height: 10),
              // Apple Sign In Button
              OutlinedButton.icon(
                onPressed: _isGoogleLoading || _isAppleLoading ? null : () async {
                  // Clear any previous error messages when starting new SSO attempt
                  _lastErrorMessage = '';
                  final auth = Provider.of<AuthProvider>(context, listen: false);
                  auth.clearSSOErrorMessage();
                  
                  setState(() {
                    _isAppleLoading = true;
                  });
                  _updateLoadingState();
                  
                  try {
                    final result = await auth.signInWithApple();
                    
                    if (result['success'] == true) {
                      if (result['needsUsername'] == true) {
                        // User needs to set up username
                        if (widget.onResult != null) {
                          widget.onResult!({
                            'success': true,
                            'needsUsername': true,
                            'email': result['email'],
                            'firstName': result['firstName'],
                            'lastName': result['lastName'],
                            'appleUserId': result['appleUserId'],
                            'provider': 'apple',
                          });
                        }
                      } else {
                        // User exists and has username
                        if (widget.onResult != null) {
                          widget.onResult!({
                            'success': true,
                            'needsUsername': false,
                          });
                        }
                      }
                    } else if (result['error'] == 'canceled') {
                      // User canceled Apple Sign In - do nothing
                      return;
                    }
                    // Note: Error messages are now handled by the AuthProvider listener above
                    // No need to manually show snackbars here
                  } finally {
                    if (mounted) {
                      setState(() {
                        _isAppleLoading = false;
                      });
                      _updateLoadingState();
                    }
                  }
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[300]!),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: const Size(double.infinity, 45),
                  backgroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white,
                  splashFactory: NoSplash.splashFactory,
                ),
                icon: _isAppleLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
                        ),
                      )
                    : const Icon(
                        Icons.apple,
                        size: 24,
                        color: Colors.black87,
                      ),
                label: _isAppleLoading
                    ? Text(
                        'Signing in...',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                          letterSpacing: 0.3,
                        ),
                      )
                    : const Text(
                        'Continue with Apple',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                          letterSpacing: 0.3,
                        ),
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}