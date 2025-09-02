import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ForgotPasswordScreen extends StatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onBack;
  const ForgotPasswordScreen({super.key, this.onClose, this.onBack});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  bool _resetSent = false;

  // Vibrant blue color matching login screen
  final Color vibrantBlue = const Color(0xFF0065FF);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _sendResetLink() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final email = _emailController.text.trim();
      try {
        await Supabase.instance.client.auth.resetPasswordForEmail(
          email,
          redirectTo: 'https://myarea.com.au/reset-password',
        );
        setState(() {
          _isLoading = false;
          _resetSent = true;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send reset link: '
              '${e is AuthException ? e.message : e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Color(0xFF0065FF),
                        ),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onPressed: () {
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
                        icon: const Icon(
                          Icons.close,
                          color: Colors.grey,
                        ),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onPressed: () {
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
            // Add spacing between logo and content to match other screens
            const SizedBox(height: 0),
            // Main content with horizontal padding
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Icon
                      Center(
                        child: Icon(
                          Icons.lock_reset,
                          size: 70,
                          color: vibrantBlue,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Title
                      const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.25,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      
                      // Subtitle
                      const Text(
                        'Enter your email and we\'ll send you a link to reset your password.',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey,
                          height: 1.35,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      
                      if (!_resetSent)
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Email Field
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
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
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(value)) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              
                              // Send Reset Link Button
                              ElevatedButton(
                                onPressed: _isLoading ? () {} : _sendResetLink,
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
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Send Reset Link',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        )
                      else
                        Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 48,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Reset link sent!',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'We\'ve sent an email to ${_emailController.text} with instructions to reset your password.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                            GestureDetector(
                              onTap: () {
                                if (widget.onBack != null) {
                                  widget.onBack!();
                                } else {
                                  Navigator.pop(context);
                                }
                              },
                              child: Center(
                                child: Text(
                                  'Back to Login',
                                  style: TextStyle(
                                    color: vibrantBlue,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ],
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