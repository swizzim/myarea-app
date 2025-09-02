import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/services/supabase_database.dart';

class EmailVerificationScreen extends StatefulWidget {
  final Map<String, dynamic>? authData;
  final Function(Map<String, dynamic>)? onNext;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const EmailVerificationScreen({
    super.key,
    this.authData,
    this.onNext,
    this.onBack,
    this.onClose,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> with WidgetsBindingObserver {
  bool _isResending = false;
  bool _isCheckingVerification = false;
  String? _resendMessage;
  String? _errorMessage;
  bool _disposed = false;
  bool _hasNavigated = false;

  // Vibrant blue color
  final Color vibrantBlue = const Color(0xFF0065FF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When user returns to the app from background/browser after verifying,
    // automatically attempt to check verification once.
    if (state == AppLifecycleState.resumed) {
      if (!_disposed && !_hasNavigated && !_isCheckingVerification) {
        _checkEmailVerification();
      }
    }
  }

  void _resendVerificationEmail() async {
    if (!mounted || _disposed) return;
    
    setState(() {
      _isResending = true;
      _resendMessage = null;
      _errorMessage = null;
    });

    try {
      final email = widget.authData?['email'] ?? '';
      final password = widget.authData?['password'] ?? '';
      
      // First, check if the user is already verified
      try {
        final response = await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        
        if (response.user != null && response.user!.emailConfirmedAt != null) {
          // User is already verified! Proceed as if they clicked "I've Verified My Email"
          print('User already verified, proceeding to next screen');
          
          // Update auth provider and proceed
          if (widget.onNext != null) {
            _hasNavigated = true;
            
            final authProvider = Provider.of<AuthProvider>(context, listen: false);
            final success = await authProvider.handlePostVerificationLogin(email);
            
            if (success) {
              if (mounted && !_disposed) {
                setState(() {
                  _isResending = false;
                });
              }
              
              // Small delay for smoother transition
              await Future.delayed(const Duration(milliseconds: 300));
              
              // Pass success message to next screen, preloading categories first
              final updatedAuthData = Map<String, dynamic>.from(widget.authData ?? {});
              updatedAuthData['emailAlreadyVerified'] = true;
              try {
                final categories = await SupabaseDatabase.instance.getAllEventCategories();
                updatedAuthData['preloadedCategories'] = categories.map((c) => c.name).toList();
              } catch (_) {}
              widget.onNext!(updatedAuthData);
              return;
            }
          }
        }
      } catch (e) {
        // User is not verified, continue with resending email
        print('User not verified, proceeding with resend: $e');
      }
      
      // User is not verified, resend the verification email
      await Supabase.instance.client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      
      // Check mounted and disposed before setState
      if (mounted && !_disposed && !_hasNavigated) {
        setState(() {
          _isResending = false;
          _resendMessage = 'Verification email sent successfully!';
        });
      }
    } catch (e) {
      // Check mounted and disposed before setState
      if (mounted && !_disposed && !_hasNavigated) {
        setState(() {
          _isResending = false;
          _errorMessage = 'Failed to resend verification email. Please try again.';
        });
      }
    }
  }

  void _checkEmailVerification() async {
    if (!mounted || _disposed) return;
    
    setState(() {
      _isCheckingVerification = true;
      _errorMessage = null;
    });

    try {
      // Add a small delay to give user time to verify email
      await Future.delayed(const Duration(seconds: 1));
      
      // Check mounted and disposed again after delay
      if (!mounted || _disposed) return;
      
      final email = widget.authData?['email'] ?? '';
      final password = widget.authData?['password'] ?? '';
      
      // Try to sign in again to get a fresh session with verification status
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      // Check if widget is still mounted and not disposed before proceeding
      if (!mounted || _disposed) return;
      
      if (response.user != null && response.user!.emailConfirmedAt != null) {
        print('Email verification successful for: $email');
        // Email is verified, update auth provider state and proceed to next screen
        if (widget.onNext != null) {
          _hasNavigated = true;
          
          // Update the auth provider state to reflect successful login
          // This ensures the main app recognizes the user as logged in
          final authProvider = Provider.of<AuthProvider>(context, listen: false);
          final success = await authProvider.handlePostVerificationLogin(email);
          
          print('Auth provider update result: $success');
          
          if (success) {
            print('Auth provider updated successfully, proceeding to next screen');
            
            // Both signup and login flows continue to voluntary info screen
            print('Email verification successful, continuing to voluntary info screen');
            if (widget.onNext != null) {
              // Preload categories before navigating
              final updatedAuthData = Map<String, dynamic>.from(widget.authData ?? {});
              try {
                final categories = await SupabaseDatabase.instance.getAllEventCategories();
                updatedAuthData['preloadedCategories'] = categories.map((c) => c.name).toList();
              } catch (_) {}
              widget.onNext!(updatedAuthData);
            }
            
            return; // Prevent further code execution after navigation
          } else {
            print('Failed to update auth provider state');
            // If failed to update auth state, show error
            if (mounted && !_disposed && !_hasNavigated) {
              setState(() {
                _errorMessage = 'Error updating login state. Please try again.';
              });
            }
          }
        }
      } else {
        // Check mounted and disposed again before setState
        if (mounted && !_disposed && !_hasNavigated) {
          setState(() {
            _errorMessage = 'Email not yet verified. Please check your email and click the verification link.';
          });
        }
      }
    } catch (e) {
      // Check mounted and disposed before any setState calls
      if (mounted && !_disposed && !_hasNavigated) {
        print('Error checking email verification: $e');
        
        // Check if it's an email not confirmed error
        if (e.toString().contains('Email not confirmed') || 
            e.toString().contains('email_not_confirmed')) {
          setState(() {
            _errorMessage = 'Email not yet verified. Please check your email and click the verification link.';
          });
        } else {
          setState(() {
            _errorMessage = 'Error checking verification status. Please try again.';
          });
        }
      }
    } finally {
      // Only reset loading state if we haven't navigated away (i.e., on error)
      if (mounted && !_disposed && !_hasNavigated) {
        setState(() {
          _isCheckingVerification = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.authData?['email'] ?? 'your email';
    
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top row: back arrow, logo, and X, spaced and padded
            Padding(
              padding: const EdgeInsets.only(top: 4.0, left: 8.0, right: 8.0),
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

                  ],
                ),
              ),
            ),
            // Add spacing between logo and title
            const SizedBox(height: 0),
            // Main content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Email verification icon
                      Center(
                        child: Icon(
                          Icons.email_outlined,
                          size: 70,
                          color: vibrantBlue,
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Title
                      const Text(
                        'Verify Your Email',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.25,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Subtitle
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'We\'ve sent a verification link to\n$email\n\nPlease check your email and click the verification link to continue.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Error message
                      if (_errorMessage != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.withOpacity(0.3)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Check verification button
                      ElevatedButton(
                        onPressed: _isCheckingVerification ? () {} : _checkEmailVerification,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: vibrantBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 1,
                          shadowColor: vibrantBlue.withOpacity(0.5),
                          minimumSize: const Size(double.infinity, 45),
                          splashFactory: NoSplash.splashFactory,
                        ),
                        child: _isCheckingVerification
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'I\'ve Verified My Email',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Resend message
                      if (_resendMessage != null) ...[
                        Text(
                          _resendMessage!,
                          style: TextStyle(
                            color: Colors.green[600],
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // Resend email button
                      TextButton(
                        onPressed: _isResending ? () {} : _resendVerificationEmail,
                        style: TextButton.styleFrom(
                          foregroundColor: vibrantBlue,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          splashFactory: NoSplash.splashFactory,
                        ),
                        child: _isResending
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0065FF)),
                                ),
                              )
                            : const Text(
                                'Resend verification email',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Help text
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          'Check your email inbox and spam folder for the verification link. The email may take a few minutes to arrive. After clicking the verification link, return here and tap "I\'ve Verified My Email".',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 