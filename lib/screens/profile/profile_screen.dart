import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/screens/settings/settings_screen.dart';
import 'package:myarea_app/screens/legal/terms_of_use_screen.dart';
import 'package:myarea_app/screens/legal/privacy_policy_screen.dart';
import 'package:myarea_app/models/user_model.dart' as app;
import 'package:myarea_app/screens/auth/auth_flow_screen.dart';
import 'package:myarea_app/main.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  // Vibrant blue color
  final Color vibrantBlue = const Color(0xFF0065FF);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        // Only show profile if user is authenticated
        if (!authProvider.isAuthenticated) {
          // Don't show anything for unauthenticated users - the auth state change listener
          // in main.dart will handle navigation to events screen
          return const Scaffold(
            backgroundColor: Color(0xFF0065FF),
            body: Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          );
        }
        
        return _buildAuthenticatedView(context, authProvider);
      },
    );
  }

  // View when user is logged in
  Widget _buildAuthenticatedView(BuildContext context, AuthProvider authProvider) {
    final user = authProvider.currentUser!;
    final theme = Theme.of(context);
    
    // Get user initials for the avatar
    String getInitials() {
      // First try to use first and last name
      if (user.firstName != null && user.lastName != null && 
          user.firstName!.isNotEmpty && user.lastName!.isNotEmpty) {
        return '${user.firstName![0]}${user.lastName![0]}'.toUpperCase();
      } 
      // Then try to use username
      else if (user.username.isNotEmpty && user.username.length > 0) {
        return user.username[0].toUpperCase();
      } 
      // Default fallback
      else {
        return 'U';
      }
    }
    
    final initials = getInitials();
    
    // Get display name
    final displayName = user.firstName != null && user.lastName != null
        ? '${user.firstName} ${user.lastName}'
        : (user.username.isNotEmpty ? user.username : 'User');

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: SafeArea(
        child: Column(
          children: [
            // Profile header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.username.isNotEmpty ? '@${user.username}' : 'No username set',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white, size: 20),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            
            // Content area
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(25),
                    topRight: Radius.circular(25),
                  ),
                ),
                child: _buildProfileContent(context, authProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Profile content
  Widget _buildProfileContent(BuildContext context, AuthProvider authProvider) {
    final user = authProvider.currentUser!;
    final theme = Theme.of(context);
    
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            
            // User information section
            const Text(
              'Account Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // Email
            _buildInfoCard(
              icon: Icons.email_outlined,
              title: 'Email',
              subtitle: user.email,
              theme: theme,
            ),
            
            // Additional user information
            const SizedBox(height: 8),
            _buildInfoCard(
              icon: Icons.location_on_outlined,
              title: 'Postcode',
              subtitle: user.postcode != null && user.postcode!.isNotEmpty 
                  ? user.postcode! 
                  : 'Not provided',
              theme: theme,
            ),
            
            const SizedBox(height: 8),
            _buildInfoCard(
              icon: Icons.person_outline,
              title: 'Age Group',
              subtitle: user.ageGroup != null && user.ageGroup!.isNotEmpty 
                  ? user.ageGroup! 
                  : 'Not specified',
              theme: theme,
            ),
            
            const SizedBox(height: 8),
            _buildInterestsCard(
              interests: user.interests ?? [],
              theme: theme,
            ),
            
            const SizedBox(height: 24),
            
            // Legal links section
            const Text(
              'Legal',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            
            // Terms of Use link
            _buildLegalLinkCard(
              icon: Icons.description_outlined,
              title: 'Terms of Use',
              subtitle: 'Read our terms and conditions',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TermsOfUseScreen(),
                  ),
                );
              },
              theme: theme,
            ),
            
            const SizedBox(height: 8),
            
            // Privacy Policy link
            _buildLegalLinkCard(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              subtitle: 'Learn about how we protect your data',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PrivacyPolicyScreen(),
                  ),
                );
              },
              theme: theme,
            ),
            
            const SizedBox(height: 24),
            
            // Logout button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: authProvider.isLoading
                    ? null
                    : () async {
                        // Clear unread messages count before logout
                        final unreadProvider = Provider.of<UnreadMessagesProvider>(context, listen: false);
                        unreadProvider.setUnreadCount(0);
                        
                        await authProvider.logout();
                      },
                icon: authProvider.isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.logout, color: Colors.white, size: 18),
                label: authProvider.isLoading
                    ? const Text(
                        'Logging out...',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      )
                    : const Text(
                        'Logout',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Helper widget for user information cards
  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: vibrantBlue,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                icon,
                size: 16,
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
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget for interests display
  Widget _buildInterestsCard({
    required List<String> interests,
    required ThemeData theme,
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: vibrantBlue,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.favorite_outline,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Interests',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (interests.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: interests.map((interest) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: vibrantBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: vibrantBlue.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      interest,
                      style: TextStyle(
                        color: vibrantBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ] else ...[
              Text(
                'No interests selected',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Helper widget for legal link cards
  Widget _buildLegalLinkCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.grey.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: vibrantBlue,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 16,
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
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey.shade400,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 