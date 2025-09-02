import 'package:flutter/material.dart';
import 'package:myarea_app/styles/app_colours.dart';
import 'package:myarea_app/screens/feedback/feedback_screen.dart';

class FeedbackButton extends StatelessWidget {
  const FeedbackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 12, // Position just above the bottom navigation bar (which is 72px high + some padding)
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColours.buttonPrimary,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
                  child: InkWell(
            onTap: () {
              showGeneralDialog(
                context: context,
                barrierDismissible: true,
                barrierColor: Colors.transparent,
                barrierLabel: '',
                transitionDuration: Duration.zero,
                pageBuilder: (context, animation, secondaryAnimation) => FeedbackScreen(
                  onBack: () => Navigator.of(context).pop(),
                ),
              );
            },
          borderRadius: BorderRadius.circular(24),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.feedback_outlined,
                size: 14,
                color: Colors.white,
              ),
              SizedBox(width: 4),
              Text(
                'Give Feedback',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
