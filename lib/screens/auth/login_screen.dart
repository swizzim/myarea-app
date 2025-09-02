import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/screens/auth/forgot_password_screen.dart';
import 'package:myarea_app/screens/auth/signup_screen.dart';
import 'package:myarea_app/screens/legal/terms_of_use_screen.dart';
import 'package:myarea_app/screens/legal/privacy_policy_screen.dart';
import 'package:myarea_app/screens/auth/set_username_screen.dart';
import 'package:myarea_app/screens/auth/email_verification_screen.dart';

class LoginScreen extends StatefulWidget {
  final String? prefillEmail;
  final VoidCallback? onSuccess;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final VoidCallback? onForgotPassword;
  final VoidCallback? onSwitchToSignup;
  final Function(String email, String password)? onEmailNotVerified;
  
  const LoginScreen({
    super.key,
    this.prefillEmail,
    this.onSuccess,
    this.onBack,
    this.onClose,
    this.onForgotPassword,
    this.onSwitchToSignup,
    this.onEmailNotVerified,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoggingIn = false; // Local loading state for standard login

  // Vibrant blue color
  final Color vibrantBlue = const Color(0xFF0065FF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Prefill email if provided
    if (widget.prefillEmail != null) {
      _emailController.text = widget.prefillEmail!;
      _passwordController.clear();
    }
    // Remove provider-based prefill logic
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Check authentication status when app is resumed
      _checkAuthStatusOnResume();
    }
  }

  Future<void> _checkAuthStatusOnResume() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isAuthenticated = await authProvider.checkAuthenticationStatus();
      if (isAuthenticated && mounted) {
        // User is authenticated, navigate to main app
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      print('Error checking auth status on resume: $e');
    }
  }

  Future<void> _handleLogin() async {
    Provider.of<AuthProvider>(context, listen: false).clearError();
    
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoggingIn = true;
      });
      
      final result = await Provider.of<AuthProvider>(context, listen: false)
        .login(_emailController.text.trim(), _passwordController.text);
      
      print('Login result: $result');
        
      if (mounted) {
        if (result['success']) {
          // Keep loading state active during navigation to prevent flash
          if (widget.onSuccess != null) {
            widget.onSuccess!();
          } else {
            Navigator.of(context).pop();
          }
        } else if (result['error'] == 'email_not_verified') {
          // Handle email not verified case
          setState(() {
            _isLoggingIn = false;
          });
          
          if (widget.onEmailNotVerified != null) {
            // Use the callback to handle email verification within auth flow
            widget.onEmailNotVerified!(result['email'], result['password']);
          } else {
            // Fallback: navigate to email verification screen directly
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => EmailVerificationScreen(
                  authData: {
                    'email': result['email'],
                    'password': result['password'],
                  },
                  onNext: (data) {
                    print('Login screen onNext callback called');
                    // After verification, proceed to app directly
                    if (widget.onSuccess != null) {
                      print('Calling widget.onSuccess callback...');
                      widget.onSuccess!();
                      print('widget.onSuccess callback completed');
                    } else {
                      print('No onSuccess callback, popping navigator');
                      Navigator.of(context).pop();
                    }
                  },
                  onBack: () {
                    // User closed verification screen, go back to login
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => LoginScreen(
                          prefillEmail: result['email'],
                          onSuccess: widget.onSuccess,
                          onBack: widget.onBack,
                          onClose: widget.onClose,
                          onForgotPassword: widget.onForgotPassword,
                          onSwitchToSignup: widget.onSwitchToSignup,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          }
        } else {
          setState(() {
            _isLoggingIn = false;
            _passwordController.text = '';
            _obscurePassword = true;
          });
        }
      }
    }
  }



  void _handleBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.pop(context);
    }
  }

  void _handleClose() {
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                  // Back arrow at the left
                  Positioned(
                    left: 0,
                    child: IconButton(
                      icon: Icon(
                        Icons.arrow_back,
                        color: _isLoggingIn ? Colors.grey[400] : const Color(0xFF0065FF),
                      ),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onPressed: _isLoggingIn ? null : _handleBack,
                    ),
                  ),
                  // X button at the right
                  Positioned(
                    right: 0,
                    child: IconButton(
                      icon: Icon(
                        Icons.close,
                        color: _isLoggingIn ? Colors.grey[400] : Colors.grey,
                      ),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      onPressed: _isLoggingIn ? null : _handleClose,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Add spacing between logo and welcome message to match previous design
          const SizedBox(height: 18),
          // Main content with horizontal padding
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0.0),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Welcome Text
                    const Text(
                      'Welcome Back',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.25,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    // Login Form
                    AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Email/Username Field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.username, AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            decoration: InputDecoration(
                              labelText: 'Email or Username',
                              labelStyle: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                                fontSize: 14,
                              ),
                              floatingLabelStyle: MaterialStateTextStyle.resolveWith(
                                (Set<MaterialState> states) {
                                  if (states.contains(MaterialState.error)) {
                                    return TextStyle(
                                      color: Theme.of(context).colorScheme.error,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                    );
                                  }
                                  if (states.contains(MaterialState.focused)) {
                                    return TextStyle(
                                      color: vibrantBlue,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    );
                                  }
                                  return TextStyle(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  );
                                },
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.grey, width: 1),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: Colors.grey, width: 1),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: vibrantBlue, width: 2),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                              floatingLabelBehavior: FloatingLabelBehavior.auto,
                            ),
                            cursorColor: vibrantBlue,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email or username';
                              }
                              if (value.contains('@') && !RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(value)) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          // Password Field
                          Consumer<AuthProvider>(
                            builder: (context, auth, child) {
                              return TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  labelStyle: TextStyle(
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                  floatingLabelStyle: MaterialStateTextStyle.resolveWith(
                                    (Set<MaterialState> states) {
                                      if (states.contains(MaterialState.error)) {
                                        return TextStyle(
                                          color: Theme.of(context).colorScheme.error,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 14,
                                        );
                                      }
                                      if (states.contains(MaterialState.focused)) {
                                        return TextStyle(
                                          color: vibrantBlue,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        );
                                      }
                                      return TextStyle(
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w500,
                                        fontSize: 14,
                                      );
                                    },
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                                      color: Colors.grey,
                                      size: 18,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.grey, width: 1),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(color: Colors.grey, width: 1),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(color: vibrantBlue, width: 2),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                                ),
                                cursorColor: vibrantBlue,
                                onFieldSubmitted: (_) => _handleLogin(),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              );
                            },
                          ),
                          // Error message (styled like field errors) below password field
                          Consumer<AuthProvider>(
                            builder: (context, auth, child) {
                              if (auth.errorMessage.isNotEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 2.0, bottom: 2.0, left: 12.0),
                                  child: Text(
                                    auth.errorMessage,
                                    style: TextStyle(
                                      color: Theme.of(context).colorScheme.error,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w400,
                                    ),
                                    textAlign: TextAlign.left,
                                  ),
                                );
                              } else {
                                return const SizedBox.shrink();
                              }
                            },
                          ),
                          // No spacing above Forgot Password
                          const SizedBox(height: 0),
                          // Forgot Password
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                if (widget.onForgotPassword != null) {
                                  widget.onForgotPassword!();
                                }
                              },
                              style: ButtonStyle(
                                splashFactory: NoSplash.splashFactory,
                                overlayColor: MaterialStateProperty.all(Colors.transparent),
                              ),
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          // Decreased spacing below Forgot Password
                          const SizedBox(height: 8),
                          // Login Button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: ElevatedButton(
                              onPressed: _isLoggingIn ? () {} : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: vibrantBlue,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                                minimumSize: const Size(double.infinity, 45),
                                splashFactory: NoSplash.splashFactory,
                              ),
                              child: _isLoggingIn
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.login, size: 22),
                                      const SizedBox(width: 10),
                                      const Text(
                                        'Sign In',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          // Switch to Sign Up (inline text)
                          GestureDetector(
                            onTap: () {
                              if (widget.onSwitchToSignup != null) {
                                widget.onSwitchToSignup!();
                              }
                            },
                            child: Center(
                              child: RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 14),
                                  children: [
                                    const TextSpan(
                                      text: "Don't have an account? ",
                                      style: TextStyle(
                                        color: Colors.black87,
                                      ),
                                    ),
                                    TextSpan(
                                      text: "Sign Up",
                                      style: TextStyle(
                                        color: vibrantBlue,
                                        fontWeight: FontWeight.bold,
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
                  ),
                    const SizedBox(height: 24),
                    // Legal disclaimer
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                            children: [
                              const TextSpan(
                                text: 'By continuing, you agree to our\n',
                              ),
                              TextSpan(
                                text: 'Terms of Use',
                                style: TextStyle(
                                  color: vibrantBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation, secondaryAnimation) => const TermsOfUseScreen(),
                                        transitionDuration: Duration.zero,
                                        reverseTransitionDuration: Duration.zero,
                                      ),
                                    );
                                  },
                              ),
                              const TextSpan(
                                text: ' and ',
                              ),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: TextStyle(
                                  color: vibrantBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    Navigator.push(
                                      context,
                                      PageRouteBuilder(
                                        pageBuilder: (context, animation, secondaryAnimation) => const PrivacyPolicyScreen(),
                                        transitionDuration: Duration.zero,
                                        reverseTransitionDuration: Duration.zero,
                                      ),
                                    );
                                  },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


} 