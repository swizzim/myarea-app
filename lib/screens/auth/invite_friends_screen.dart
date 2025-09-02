import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/services/deep_link_service.dart';

class InviteFriendsScreen extends StatefulWidget {
  final Map<String, dynamic>? authData;
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;
  final VoidCallback? onBack;

  const InviteFriendsScreen({
    super.key,
    this.authData,
    this.onComplete,
    this.onSkip,
    this.onBack,
  });

  @override
  State<InviteFriendsScreen> createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<InviteFriendsScreen> {
  bool _isInviting = false;
  final Color vibrantBlue = const Color(0xFF0065FF);

  void _inviteFriends() async {
    setState(() {
      _isInviting = true;
    });
    // Build personalized referral link using current user's username
    final auth = context.read<AuthProvider>();
    final username = auth.currentUser?.username;
    final referralLink = (username != null && username.isNotEmpty)
        ? DeepLinkService.generateReferralLink(username)
        : 'https://myarea.com.au';

    final shareMessage = 'Join me on MyArea! Discover local events, share tips, and explore together.\n\nUse my link to sign up and we\'ll be connected automatically: $referralLink';
    await Share.share(shareMessage);
    if (!mounted) return;
    setState(() {
      _isInviting = false;
    });
    
    // No redundant modal – native share sheet is sufficient feedback
  }

  

  void _skipInvite() {
    // Use the onSkip callback to properly close the auth flow with animation
    if (widget.onSkip != null) {
      widget.onSkip!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top row: logo and skip button, spaced and padded
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
                        onTap: _isInviting
                            ? null
                            : () {
                                // Use the onSkip callback to properly close the auth flow with animation
                                if (widget.onSkip != null) {
                                  widget.onSkip!();
                                }
                              },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Text(
                            'Skip',
                            style: TextStyle(
                              color: _isInviting ? Colors.grey[400] : Colors.grey,
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
            // Add spacing between logo and content to match other screens
            const SizedBox(height: 20),
            // Main content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 0.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Illustration/icon (medium)
                    Center(
                      child: Icon(
                        Icons.people_alt_outlined,
                        size: 70,
                        color: vibrantBlue,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Title
                    const Text(
                      'Invite Your Friends!',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    // Subtitle (medium)
                    Text(
                      'Connect with friends and family to discover local events, share recommendations, and explore together.',
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
                          icon: Icons.event_available,
                          title: 'Local Events',
                          description: 'Get notified about events',
                        ),
                        const SizedBox(height: 12),
                        _buildBenefitItem(
                          icon: Icons.recommend,
                          title: 'Share Tips',
                          description: 'Recommend local spots',
                        ),
                        const SizedBox(height: 12),
                        _buildBenefitItem(
                          icon: Icons.explore,
                          title: 'Explore Together',
                          description: 'Plan & explore as a group',
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    // Invite Friends Button (disabled for TestFlight)
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: null, // Disabled for TestFlight
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[300],
                          foregroundColor: Colors.grey[600],
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                          minimumSize: const Size(double.infinity, 50),
                          splashFactory: NoSplash.splashFactory,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.share, size: 22, color: Colors.grey[600]),
                            const SizedBox(width: 10),
                            Text(
                              'Invite Friends',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // TestFlight notice
                    Text(
                      'Not available during TestFlight testing',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    // Skip Button (medium)
                    TextButton(
                      onPressed: _isInviting ? null : _skipInvite,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(double.infinity, 36),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        splashFactory: NoSplash.splashFactory,
                        overlayColor: Colors.transparent,
                      ),
                      child: Text(
                        'Skip for now',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    // Additional info (medium)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        'You can always invite friends later from your profile.',
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
      ),
    );
  }

  Widget _buildBenefitItem({
    required IconData icon,
    required String title,
    required String description,
  }) {
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