import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:myarea_app/models/user_model.dart' as app;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';

class FeedbackService {
  static final FeedbackService instance = FeedbackService._();
  FeedbackService._();

  late final SupabaseClient _supabase;

  Future<void> initialize() async {
    _supabase = Supabase.instance.client;
  }

  /// Send feedback using backend API for email
  Future<Map<String, dynamic>> sendFeedback({
    String subject = 'App Feedback',
    required String message,
    app.User? user,
    File? imageFile,
  }) async {
    try {
      // Prepare user info
      String userInfo = 'Anonymous User';
      String? userEmail;
      
      if (user != null) {
        userInfo = 'User: ${user.username}';
        userEmail = user.email;
        if (user.firstName != null && user.lastName != null) {
          userInfo += '\nName: ${user.firstName} ${user.lastName}';
        }
      }

      String? uploadedImageUrl;

      // If image provided, upload to Supabase Storage
      if (imageFile != null) {
        try {
          final String bucket = 'feedback';
          final String path = 'images/${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';
          final storage = _supabase.storage.from(bucket);
          await storage.upload(path, imageFile);
          uploadedImageUrl = storage.getPublicUrl(path);
        } catch (e) {
          print('Warning: Image upload failed: $e');
        }
      }

      // Create email content
      final emailBody = '''
User Information:
$userInfo

Feedback Message:
$message

${uploadedImageUrl != null ? 'Image: $uploadedImageUrl\n\n' : ''}
---
Sent from MyArea App
''';

      // Call backend API to send email
      print('Sending feedback to: https://myarea.com.au/api/send-feedback-email');
      print('Payload: ${jsonEncode({
        'to': 'support@myarea.com.au',
        'subject': subject,
        'body': emailBody,
        'user_email': userEmail,
        'user_info': userInfo,
      })}');
      
      final response = await http.post(
        Uri.parse('https://myarea.com.au/api/send-feedback-email'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'to': 'support@myarea.com.au',
          'subject': subject,
          'body': emailBody,
          'user_email': userEmail,
          'user_info': userInfo,
          'image_url': uploadedImageUrl,
        }),
      );
      
      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        // Also store feedback in database for record keeping
        try {
          await _supabase.from('feedback').insert({
            'subject': subject,
            'message': message,
            'user_info': userInfo,
            'user_email': userEmail,
            'user_id': user?.id,
            'created_at': DateTime.now().toIso8601String(),
            'email_sent': true,
            'email_sent_at': DateTime.now().toIso8601String(),
            'image_url': uploadedImageUrl,
          });
        } catch (dbError) {
          print('Warning: Could not store feedback in database: $dbError');
        }

        return {
          'success': true,
          'message': 'Feedback sent successfully!',
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to send feedback. Please try again.',
        };
      }
    } catch (e) {
      print('Error sending feedback: $e');
      return {
        'success': false,
        'error': 'Failed to send feedback. Please try again.',
      };
    }
  }
}
