import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vibrantBlue = const Color(0xFF0065FF);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: vibrantBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Privacy Policy',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Last updated: ${DateTime.now().toString().split(' ')[0]}',
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'MyArea ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how your personal information is collected, used, and disclosed by MyArea.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              const Text(
                '1. Information We Collect',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We may collect the following types of information:\n\n'
                '• Personal Information: When you create an account, we collect your name, email address, password, and profile information.\n\n'
                '• Location Information: With your permission, we collect precise location information from your device to provide location-based services.\n\n'
                '• Usage Information: We collect information about how you use our app, including your interactions, preferences, and settings.\n\n'
                '• Device Information: We collect information about your device, including device model, operating system, unique device identifiers, and mobile network information.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '2. How We Use Your Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We use the information we collect to:\n\n'
                '• Provide, maintain, and improve our services\n'
                '• Process and complete transactions\n'
                '• Send you technical notices, updates, security alerts, and support messages\n'
                '• Respond to your comments, questions, and requests\n'
                '• Develop new products and services\n'
                '• Monitor and analyze trends, usage, and activities\n'
                '• Personalize your experience',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '3. Sharing of Information',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We may share your information with:\n\n'
                '• Service providers who perform services on our behalf\n'
                '• Partners with whom we offer co-branded services or products\n'
                '• In response to a request for information if we believe disclosure is in accordance with any applicable law, regulation, or legal process\n'
                '• If we believe your actions are inconsistent with our user agreements or policies, or to protect the rights, property, and safety of MyArea or others',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '4. Your Choices',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Account Information: You may update, correct, or delete your account information at any time by logging into your account settings.\n\n'
                'Location Information: You can enable or disable location services when you use our app through your device settings.\n\n'
                'Push Notifications: You can opt out of receiving push notifications through your device settings.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '5. Data Security',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We take reasonable measures to help protect information about you from loss, theft, misuse, unauthorized access, disclosure, alteration, and destruction.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '6. Changes to This Policy',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We may change this Privacy Policy from time to time. If we make changes, we will notify you by revising the date at the top of the policy and, in some cases, we may provide you with additional notice.',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              const Text(
                '7. Contact Us',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'If you have any questions about this Privacy Policy, please contact us at:\nsupport@myarea.com',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
} 