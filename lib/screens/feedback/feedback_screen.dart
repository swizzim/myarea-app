import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:myarea_app/providers/auth_provider.dart';
import 'package:myarea_app/styles/app_colours.dart';
import 'package:myarea_app/services/feedback_service.dart';

class FeedbackScreen extends StatefulWidget {
  final VoidCallback onBack;

  const FeedbackScreen({
    super.key,
    required this.onBack,
  });

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source, imageQuality: 85);
      if (image != null && mounted) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendFeedback() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;
      
      // Send feedback directly via the service
      final result = await FeedbackService.instance.sendFeedback(
        message: _messageController.text,
        user: user,
        imageFile: _selectedImage != null ? File(_selectedImage!.path) : null,
      );

      if (mounted) {
        if (result['success'] == true) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: AppColours.buttonPrimary,
              duration: const Duration(seconds: 3),
            ),
          );
          
          // Clear form and go back
          _messageController.clear();
          setState(() {
            _selectedImage = null;
          });
          Navigator.of(context).pop();
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Failed to send feedback'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending feedback: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    
    return Material(
      color: AppColours.background,
      child: SafeArea(
        child: Column(
          children: [
            // App bar - exactly like event details screen
            PreferredSize(
              preferredSize: Size.fromHeight(40.0 + topPadding),
              child: Container(
                child: AppBar(
                  backgroundColor: AppColours.background,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  toolbarHeight: 40.0,
                  scrolledUnderElevation: 0,
                  surfaceTintColor: Colors.transparent,
                  leading: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 2),
                    width: 48,
                    child: IconButton(
                      icon: Icon(Icons.arrow_back, color: AppColours.buttonPrimary),
                      onPressed: widget.onBack,
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      hoverColor: Colors.transparent,
                    ),
                  ),
                  leadingWidth: 48,
                  titleSpacing: 0,
                  title: Text(
                    'We value your feedback!',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  centerTitle: false,
                ),
              ),
            ),
            
            // Content with keyboard handling
            Expanded(
              child: CustomScrollView(
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Description text
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 20.0),
                            child: Text(
                              'Help us improve MyArea by sharing your thoughts, suggestions, or reporting any issues. Your feedback will be sent directly to our team.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            ),
                          ),
                          
                          // Image attachment section
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Attach Image (optional)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton.icon(
                                  onPressed: () => _pickImage(ImageSource.gallery),
                                  icon: Icon(Icons.photo_library, color: AppColours.buttonPrimary),
                                  label: Text(
                                    'Upload Image',
                                    style: TextStyle(
                                      color: AppColours.buttonPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    backgroundColor: Colors.grey[50],
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: BorderSide(color: Colors.grey[300]!),
                                    ),
                                    splashFactory: NoSplash.splashFactory,
                                    overlayColor: Colors.transparent,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (_selectedImage != null) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12.0),
                              child: Stack(
                                children: [
                                  Container(
                                    width: 120,
                                    height: 160,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        File(_selectedImage!.path),
                                        fit: BoxFit.cover,
                                        alignment: Alignment.topCenter,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 8,
                                    top: 8,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          _selectedImage = null;
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          
                          const SizedBox(height: 24),
                          
                          // Message field
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: Form(
                              key: _formKey,
                              child: TextFormField(
                                controller: _messageController,
                                decoration: const InputDecoration(
                                  labelText: 'Your Feedback *',
                                  border: OutlineInputBorder(),
                                  alignLabelWithHint: true,
                                ),
                                maxLines: 6,
                                maxLength: 1000,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your feedback';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Submit button
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _sendFeedback,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColours.buttonPrimary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  splashFactory: NoSplash.splashFactory,
                                  animationDuration: Duration.zero,
                                ),
                                child: _isLoading
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      )
                                    : const Text(
                                        'Send Feedback',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
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
}
