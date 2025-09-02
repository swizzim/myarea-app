import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/screens/auth/invite_friends_screen.dart';
import 'package:myarea_app/services/supabase_database.dart';
import 'package:myarea_app/models/event_category_model.dart';

class VoluntaryInfoScreen extends StatefulWidget {
  final String? userId;
  final Map<String, dynamic>? authData;
  final Function(Map<String, dynamic>)? onNext;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;
  final List<String>? initialCategories;

  const VoluntaryInfoScreen({
    super.key,
    this.userId,
    this.authData,
    this.onNext,
    this.onSkip,
    this.onBack,
    this.initialCategories,
  });

  @override
  State<VoluntaryInfoScreen> createState() => _VoluntaryInfoScreenState();
}

class _VoluntaryInfoScreenState extends State<VoluntaryInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _postcodeController = TextEditingController();
  String? _selectedAgeGroup;
  bool _isSaving = false;
  Set<String> _selectedCategories = {};
  List<String> _categories = [];
  bool _isLoadingCategories = true;

  // Vibrant blue color
  final Color vibrantBlue = const Color(0xFF0065FF);

  // Age group options
  final List<String> _ageGroups = [
    'Under 18',
    '18-24',
    '25-34',
    '35-44',
    '45-54',
    '55-64',
    '65+'
  ];

  // Australian postcode validation
  String? _validateAustralianPostcode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return null; // Allow empty as it's optional
    }
    
    final postcode = value.trim();
    
    // Check if it's exactly 4 digits
    if (!RegExp(r'^\d{4}$').hasMatch(postcode)) {
      return 'Please enter a 4-digit postcode';
    }
    
    // Convert to integer for range validation
    final postcodeNum = int.tryParse(postcode);
    if (postcodeNum == null) {
      return 'Please enter a valid postcode';
    }
    
    // Check if within Australian postcode range (0200 to 9944)
    if (postcodeNum < 200 || postcodeNum > 9944) {
      return 'Please enter a valid Australian postcode (0200-9944)';
    }
    
    return null;
  }

  void _toggleCategory(String category) {
    setState(() {
      if (_selectedCategories.contains(category)) {
        _selectedCategories.remove(category);
      } else {
        _selectedCategories.add(category);
      }
    });
  }

  @override
  void dispose() {
    _postcodeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialCategories != null && widget.initialCategories!.isNotEmpty) {
      _categories = List<String>.from(widget.initialCategories!);
      _isLoadingCategories = false;
    } else {
      _fetchCategories();
    }
    
    // Show snackbar if user came from already verified email
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.authData?['emailAlreadyVerified'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Great! Your email was already verified. Welcome to MyArea!',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green[600],
            duration: Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    });
  }

  Future<void> _fetchCategories() async {
    try {
      final categories = await SupabaseDatabase.instance.getAllEventCategories();
      setState(() {
        _categories = categories.map((cat) => cat.name).toList();
        _isLoadingCategories = false;
      });
    } catch (e) {
      setState(() {
        _categories = [
          'Music',
          'Nightlife',
          'Performing & Visual Arts',
          'Holidays',
          'Dating',
          'Hobbies',
          'Business',
          'Food & Drink',
        ];
        _isLoadingCategories = false;
      });
    }
  }

  // Get icon for category
  IconData? _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'music':
        return Icons.music_note;
      case 'nightlife':
        return Icons.nightlife;
      case 'exhibitions':
        return Icons.palette;
      case 'performing & visual arts':
        return Icons.palette;
      case 'theatre, dance & film':
        return Icons.theater_comedy;
      case 'tours':
        return Icons.directions_walk;
      case 'markets':
        return Icons.shopping_basket;
      case 'food & drink':
        return Icons.restaurant;
      case 'dating':
        return Icons.favorite;
      case 'comedy':
        return Icons.emoji_emotions;
      case 'talks, courses & workshops':
        return Icons.record_voice_over;
      case 'holidays':
        return Icons.beach_access;
      case 'hobbies':
        return Icons.sports_esports;
      case 'business':
        return Icons.business;
      default:
        return null;
    }
  }

  void _saveAndContinue() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isSaving = true;
      });

      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final userId = widget.userId ?? authProvider.currentUser?.id;
        
        if (userId != null) {
          await authProvider.updateUserInfo(
            userId: userId,
            postcode: _postcodeController.text.trim(),
            ageGroup: _selectedAgeGroup,
            interests: _selectedCategories.toList(),
          );
        }

        if (!mounted) return;
        
        // Add voluntary info to auth data
        final updatedAuthData = Map<String, dynamic>.from(widget.authData ?? {});
        updatedAuthData['postcode'] = _postcodeController.text.trim();
        updatedAuthData['ageGroup'] = _selectedAgeGroup;
        updatedAuthData['categories'] = _selectedCategories.toList();
        
        if (widget.onNext != null) {
          widget.onNext!(updatedAuthData);
        } else {
          // Navigate to invite friends screen instead of main screen
          Navigator.of(context).pushReplacement(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => InviteFriendsScreen(
                authData: updatedAuthData,
                onComplete: () {
                  // Close the auth flow modal to return to main app
                  Navigator.of(context).pop();
                },
                onSkip: () {
                  // Close the auth flow modal to return to main app
                  Navigator.of(context).pop();
                },
              ),
              transitionDuration: Duration.zero,
              reverseTransitionDuration: Duration.zero,
            ),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      } finally {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
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
            // Top row: logo and X, spaced and padded
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
                    // Skip button at the right
                    Positioned(
                      right: 0,
                      child: GestureDetector(
                        onTap: _isSaving
                            ? null
                            : () {
                                // Navigate to invite friends screen using AuthFlowScreen navigation
                                if (widget.onNext != null) {
                                  widget.onNext!(widget.authData ?? {});
                                }
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: _isSaving ? Colors.grey[400] : Colors.grey,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Title
                        const Text(
                          'Tell Us More About You',
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
                            'This information helps us provide a better experience (optional)',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Postcode and Age Group Row
                        Row(
                          children: [
                            // Postcode Field
                            Expanded(
                              child: TextFormField(
                                controller: _postcodeController,
                                keyboardType: TextInputType.number,
                                maxLength: 4,
                                decoration: InputDecoration(
                                  labelText: 'Home Postcode',
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
                                  counterText: '', // Hide character counter
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
                                validator: _validateAustralianPostcode,
                              ),
                            ),

                            const SizedBox(width: 16),

                            // Age Group Dropdown
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedAgeGroup,
                                decoration: InputDecoration(
                                  labelText: 'Age Group',
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
                                items: _ageGroups.map((String ageGroup) {
                                  return DropdownMenuItem<String>(
                                    value: ageGroup,
                                    child: Text(ageGroup),
                                  );
                                }).toList(),
                                onChanged: (String? newValue) {
                                  setState(() {
                                    _selectedAgeGroup = newValue;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Categories Section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Categories',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Select event categories that interest you',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_isLoadingCategories)
                              const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(20.0),
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: _categories.map((category) {
                                  final isSelected = _selectedCategories.contains(category);
                                  final icon = _getCategoryIcon(category);
                                  return Material(
                                    elevation: 0.7,
                                    shadowColor: Colors.black12,
                                    color: Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                    child: GestureDetector(
                                      onTap: () => _toggleCategory(category),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                                        margin: EdgeInsets.zero,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? vibrantBlue.withOpacity(0.15)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(
                                            color: isSelected
                                                ? vibrantBlue.withOpacity(0.25)
                                                : Colors.grey[300]!,
                                            width: 1.1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (icon != null) ...[
                                              Icon(
                                                icon,
                                                size: 16,
                                                color: isSelected ? vibrantBlue : Colors.grey[600],
                                              ),
                                              const SizedBox(width: 5),
                                            ],
                                            Text(
                                              category,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: isSelected
                                                    ? vibrantBlue
                                                    : Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Icon(
                                              isSelected ? Icons.check : Icons.add,
                                              size: 16,
                                              color: isSelected
                                                  ? vibrantBlue
                                                  : Colors.grey[500],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Continue Button
                        ElevatedButton(
                          onPressed: _isSaving ? null : _saveAndContinue,
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
                          child: _isSaving
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
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

                        const SizedBox(height: 8),

                        // Skip Button
                        GestureDetector(
                          onTap: _isSaving
                              ? null
                                                              : () {
                                  // Navigate to invite friends screen using AuthFlowScreen navigation
                                  if (widget.onNext != null) {
                                    widget.onNext!(widget.authData ?? {});
                                  }
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Skip for now',
                              style: TextStyle(
                                color: _isSaving ? Colors.grey[400] : Colors.grey[600],
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
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