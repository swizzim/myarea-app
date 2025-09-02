import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:profanity_filter/profanity_filter.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/screens/auth/voluntary_info_screen.dart';

class SetUsernameScreen extends StatefulWidget {
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? password;
  final Map<String, dynamic>? authData;
  final Function(Map<String, dynamic>)? onNext;
  final VoidCallback? onBack;

  const SetUsernameScreen({
    super.key,
    this.firstName,
    this.lastName,
    this.email,
    this.password,
    this.authData,
    this.onNext,
    this.onBack,
  });

  @override
  State<SetUsernameScreen> createState() => _SetUsernameScreenState();
}

class _SetUsernameScreenState extends State<SetUsernameScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final ProfanityFilter _profanityFilter = ProfanityFilter();
  bool _isCheckingUsername = false;
  bool _usernameAvailable = true;
  String _usernameError = '';
  bool _isRegistering = false;
  String? _registrationError;

  // Vibrant blue color
  final Color vibrantBlue = const Color(0xFF0065FF);

  bool _usernameContainsProfanity(String input) {
    final String raw = input.toLowerCase();
    final String withSpaces = raw.replaceAll(RegExp(r'[_.]'), ' ');
    final String collapsed = raw.replaceAll(RegExp(r'[_.]'), '');
    if (_profanityFilter.hasProfanity(raw)) return true;
    if (_profanityFilter.hasProfanity(withSpaces)) return true;
    if (_profanityFilter.hasProfanity(collapsed)) return true;
    // Additional collapsed phrase bans
    const Set<String> bannedCollapsedSubstrings = {
      'ballgravy',
    };
    if (bannedCollapsedSubstrings.any((p) => collapsed.contains(p))) return true;
    return false;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  // Check if username is available
  Future<bool> _checkUsernameAvailability(String username) async {
    setState(() {
      _isCheckingUsername = true;
      _usernameAvailable = false;
      _usernameError = '';
    });
    
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      // First check profanity and format validation
      if (_usernameContainsProfanity(username)) {
        if (mounted) {
          setState(() {
            _isCheckingUsername = false;
            _usernameAvailable = false;
            _usernameError = 'Please choose a different username';
          });
        }
        return false;
      }

      // Then check format validation
      final usernameValidationError = authProvider.validateUsernameFormat(username);
      if (usernameValidationError != null) {
        if (mounted) {
          setState(() {
            _isCheckingUsername = false;
            _usernameAvailable = false;
            _usernameError = usernameValidationError;
          });
        }
        return false;
      }
      
      // Then check if username exists
      final exists = await authProvider.checkUsernameExists(username);
      
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _usernameAvailable = !exists;
          if (exists) {
            _usernameError = 'Username already taken';
          }
        });
      }
      
      return !exists;
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _usernameAvailable = false;
          _usernameError = 'Error checking username availability';
        });
      }
      return false;
    }
  }

  void _completeSignUp() async {
    FocusScope.of(context).unfocus();
    if (_formKey.currentState!.validate()) {
      final username = _usernameController.text.trim();
      
      // Check username availability
      final isAvailable = await _checkUsernameAvailability(username);
      if (!isAvailable) {
        setState(() {
          _usernameAvailable = false;
          _usernameError = 'Username already taken';
        });
        return;
      }
      
      // All checks passed, proceed with registration
      if (!mounted) return;
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      
      setState(() {
        _isRegistering = true;
      });
      
      try {
        // Get data from either authData or individual parameters
        final email = widget.authData?['email'] ?? widget.email ?? '';
        final password = widget.authData?['password'] ?? widget.password ?? '';
        final firstName = widget.authData?['firstName'] ?? widget.firstName ?? '';
        final lastName = widget.authData?['lastName'] ?? widget.lastName ?? '';
        final provider = widget.authData?['provider'];
        final appleUserId = widget.authData?['appleUserId'];
        
        bool success;
        
        if (provider == 'apple') {
          // Handle Apple Sign In user
          print('🍎 Creating Apple user with username: $username');
          success = await authProvider.createAppleUserWithUsername(
            email: email,
            username: username,
            firstName: firstName,
            lastName: lastName,
            appleUserId: appleUserId,
          );
        } else if (provider == 'google') {
          // Handle Google Sign In user
          print('🔐 Creating Google user with username: $username');
          success = await authProvider.createUserWithUsername(
            email: email,
            username: username,
            firstName: firstName,
            lastName: lastName,
          );
        } else {
          // Handle regular registration
          success = await authProvider.register(
            email, 
            username, 
            password,
            firstName: firstName,
            lastName: lastName,
          );
        }
        
        if (!mounted) return;
        
        if (success) {
          // Add username to auth data
          final updatedAuthData = Map<String, dynamic>.from(widget.authData ?? {});
          updatedAuthData['username'] = username;
          
          if (widget.onNext != null) {
            widget.onNext!(updatedAuthData);
          } else {
            // Navigate to voluntary info screen; categories will be preloaded after email verification
            FocusScope.of(context).unfocus();
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => VoluntaryInfoScreen(
                  userId: authProvider.currentUser!.id!,
                  authData: updatedAuthData,
                ),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          }
        } else {
          setState(() {
            _registrationError = authProvider.errorMessage ?? 'Registration failed. Please try again.';
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _registrationError = e.toString();
        });
      } finally {
        if (mounted) {
          setState(() {
            _isRegistering = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
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
                          color: (_isCheckingUsername || _isRegistering) ? Colors.grey[400] : const Color(0xFF0065FF),
                        ),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onPressed: (_isCheckingUsername || _isRegistering) ? null : () {
                          FocusScope.of(context).unfocus();
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
                          color: (_isCheckingUsername || _isRegistering) ? Colors.grey[400] : Colors.grey,
                        ),
                        splashColor: Colors.transparent,
                        highlightColor: Colors.transparent,
                        onPressed: (_isCheckingUsername || _isRegistering) ? null : () {
                          FocusScope.of(context).unfocus();
                          Navigator.of(context).maybePop();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Add spacing between logo and title to match other screens
            const SizedBox(height: 18),
            // Main content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Choose Username Title
                      const Text(
                        'Choose Your Username',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.25,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Subtitle
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Text(
                          'Your username is how other users will see you on MyArea',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      
                      const SizedBox(height: 24),
                      
                      // Username Form
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: _usernameController,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.newUsername, AutofillHints.username],
                              decoration: InputDecoration(
                                hintText: 'Choose a username',
                                prefixIcon: const Icon(Icons.person_outline, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Colors.grey, width: 1),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _usernameError.isNotEmpty ? Colors.red : Colors.grey,
                                    width: 1
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: _usernameError.isNotEmpty ? Colors.red : vibrantBlue,
                                    width: 2
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Colors.red, width: 1),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(color: Colors.red, width: 2),
                                ),
                                errorText: _usernameError.isNotEmpty ? _usernameError : null,
                                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter a username';
                                }
                                if (value.length < 3) {
                                  return 'Username must be at least 3 characters';
                                }
                                if (value.length > 20) {
                                  return 'Username must be 20 characters or less';
                                }
                                if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(value)) {
                                  return 'Username can only contain letters, numbers, underscores, and dots';
                                }
                                if (_usernameContainsProfanity(value)) {
                                  return 'Please choose a different username';
                                }
                                return null;
                              },
                            ),
                            
                            const SizedBox(height: 8),
                            
                            // Username guidelines
                            Text(
                              'Username should be 3-20 characters',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 32),
                      
                      // Complete Sign Up Button
                      Consumer<AuthProvider>(
                        builder: (context, auth, child) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_registrationError != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Text(
                                    _registrationError!,
                                    style: const TextStyle(
                                      color: Colors.red,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ElevatedButton(
                                onPressed: _isRegistering ? () {} : _completeSignUp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: vibrantBlue,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: vibrantBlue,
                                  disabledForegroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 1,
                                  shadowColor: vibrantBlue.withOpacity(0.5),
                                  minimumSize: const Size(double.infinity, 45),
                                  splashFactory: NoSplash.splashFactory,
                                ),
                                child: _isRegistering
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : Text(
                                        'Complete Sign Up',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ],
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
    );
  }
}


