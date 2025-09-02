import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:io' show Platform;
import 'package:provider/provider.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/screens/auth/set_username_screen.dart';
import 'package:myarea_app/screens/auth/login_screen.dart';
import 'package:myarea_app/screens/legal/terms_of_use_screen.dart';
import 'package:myarea_app/screens/legal/privacy_policy_screen.dart';


class SignupScreen extends StatefulWidget {
  final String? prefillEmail;
  final Function(Map<String, dynamic>)? onNext;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final VoidCallback? onSwitchToLogin;
  
  const SignupScreen({
    super.key,
    this.prefillEmail,
    this.onNext,
    this.onBack,
    this.onClose,
    this.onSwitchToLogin,
  });

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isCheckingEmail = false; // Add local loading state

  // Vibrant blue color matching login screen
  final Color vibrantBlue = const Color(0xFF0065FF);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Initialize email controller with prefilled email if provided
    _emailController = TextEditingController(text: widget.prefillEmail);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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
        // Since SignupScreen doesn't have onSuccess, just pop to go back
        Navigator.of(context).pop();
      }
    } catch (e) {
      print('Error checking auth status on resume: $e');
    }
  }

  void _signUp() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isCheckingEmail = true; // Set loading state
      });
      
      final firstName = _firstNameController.text.trim();
      final lastName = _lastNameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      
      // Check if email already exists in the database
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final isEmailTaken = await authProvider.checkEmailExists(email);
      
      if (mounted) {
        setState(() {
          _isCheckingEmail = false; // Clear loading state
        });
      }
      
      if (isEmailTaken) {
        // Show dialog to prompt user to login instead
        if (mounted) {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Account Already Exists'),
                content: const Text('An account with this email already exists. Would you like to sign in instead?'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Close the dialog
                    },
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Close the dialog
                      // Navigate to login with the email
                      Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => LoginScreen(prefillEmail: email),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    },
                    child: Text(
                      'Sign In',
                      style: TextStyle(
                        color: vibrantBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }
        return;
      }
      
      // Navigate to the second sign-up screen
      if (mounted) {
        if (widget.onNext != null) {
          widget.onNext!({
            'firstName': firstName,
            'lastName': lastName,
            'email': email,
            'password': password,
          });
        } else {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => SetUsernameScreen(
                firstName: firstName,
                lastName: lastName,
                email: email,
                password: password,
              ),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    // Back arrow at the left
                    Positioned(
                      left: 0,
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: _isCheckingEmail ? Colors.grey[400] : const Color(0xFF0065FF),
                        ),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onPressed: _isCheckingEmail ? null : () {
                          if (widget.onBack != null) {
                            widget.onBack!();
                          } else {
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                    // X button at the right
                    Positioned(
                      right: 0,
                      child: IconButton(
                        icon: Icon(
                          Icons.close,
                          color: _isCheckingEmail ? Colors.grey[400] : Colors.grey,
                        ),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onPressed: _isCheckingEmail ? null : () {
                          if (widget.onClose != null) {
                            widget.onClose!();
                          } else {
                            Navigator.of(context).maybePop();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Add spacing between logo and title to match other screens
            const SizedBox(height: 18),
            // Main content with horizontal padding
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 0.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Create Account Title
                      const Text(
                        'Create Your Account',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.25,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Sign Up Form
                      AutofillGroup(
                        child: Form(
                          key: _formKey,
                          child: Column(
                          children: [
                            // First Name and Last Name Fields in a Row
                            Row(
                              children: [
                                // First Name Field
                                Expanded(
                                  child: TextFormField(
                                    controller: _firstNameController,
                                    textCapitalization: TextCapitalization.words,
                                    keyboardType: TextInputType.name,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    autofillHints: const [AutofillHints.givenName],
                                    decoration: InputDecoration(
                                      labelText: 'First Name',
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
                                        return 'First name required';
                                      }
                                      // Check for letters only (allowing spaces and hyphens for compound names)
                                      if (!RegExp(r'^[a-zA-Z\s\-]+$').hasMatch(value)) {
                                        return 'Letters only';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                
                                const SizedBox(width: 12),
                                
                                // Last Name Field
                                Expanded(
                                  child: TextFormField(
                                    controller: _lastNameController,
                                    textCapitalization: TextCapitalization.words,
                                    keyboardType: TextInputType.name,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    autofillHints: const [AutofillHints.familyName],
                                    decoration: InputDecoration(
                                      labelText: 'Last Name',
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
                                        return 'Last name required';
                                      }
                                      // Check for letters only (allowing spaces and hyphens for compound names)
                                      if (!RegExp(r'^[a-zA-Z\s\-]+$').hasMatch(value)) {
                                        return 'Letters only';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Email Field
                            TextFormField(
                              controller: _emailController,
                              autofillHints: const [AutofillHints.email, AutofillHints.username],
                              decoration: InputDecoration(
                                labelText: 'Email',
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
                              keyboardType: TextInputType.emailAddress,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Email required';
                                }
                                if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(value)) {
                                  return 'Invalid email format';
                                }
                                return null;
                              },
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Password Field
                            TextFormField(
                              controller: _passwordController,
                              obscureText: !_isPasswordVisible,
                              autofillHints: const [AutofillHints.newPassword],
                              keyboardType: TextInputType.visiblePassword,
                              enableSuggestions: false,
                              autocorrect: false,
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
                                    _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isPasswordVisible = !_isPasswordVisible;
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
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Password required';
                                }
                                if (value.length < 8) {
                                  return 'Min 8 characters';
                                }
                                if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value)) {
                                  return 'Add a special character';
                                }
                                return null;
                              },
                            ),
                            
                            const SizedBox(height: 16),
                            
                            // Confirm Password Field
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: !_isConfirmPasswordVisible,
                              autofillHints: const [AutofillHints.newPassword],
                              keyboardType: TextInputType.visiblePassword,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: 'Confirm Password',
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
                                    _isConfirmPasswordVisible ? Icons.visibility : Icons.visibility_off,
                                    color: Colors.grey,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _isConfirmPasswordVisible = !_isConfirmPasswordVisible;
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
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Confirmation required';
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords don\'t match';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                      
                      const SizedBox(height: 24),
                      
                      // Sign Up Button
                      ElevatedButton(
                        onPressed: _isCheckingEmail ? () {} : _signUp,
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
                        child: _isCheckingEmail
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Sign In Link
                      GestureDetector(
                        onTap: () {
                          if (widget.onSwitchToLogin != null) {
                            widget.onSwitchToLogin!();
                          }
                        },
                        child: Center(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(fontSize: 14),
                              children: [
                                const TextSpan(
                                  text: "Already have an account? ",
                                  style: TextStyle(
                                    color: Colors.black87,
                                  ),
                                ),
                                TextSpan(
                                  text: "Sign In",
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
                      
                      // Legal disclaimer
                      const SizedBox(height: 24),
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
      ),
    );
  }
} 