import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'package:provider/provider.dart';
import 'package:myarea_app/screens/friends/friends_screen.dart';
import 'package:myarea_app/main.dart';
import 'package:myarea_app/providers/auth_provider.dart';

class CustomNotification extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color backgroundColor;
  final Color textColor;
  final Duration duration;
  final VoidCallback? onTap;

  const CustomNotification({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.backgroundColor = const Color(0xFF0065FF),
    this.textColor = Colors.white,
    this.duration = const Duration(seconds: 3),
    this.onTap,
  });

  @override
  State<CustomNotification> createState() => _CustomNotificationState();
}

class _CustomNotificationState extends State<CustomNotification> with SingleTickerProviderStateMixin {
  double _dragOffset = 0.0;
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _animation = Tween<double>(begin: 0, end: 0).animate(_controller)
      ..addListener(() {
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    setState(() {
      _dragOffset += details.delta.dy;
      if (_dragOffset > 0) _dragOffset = 0; // Only allow upward drag
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    if (_dragOffset < -60 || (details.primaryVelocity != null && details.primaryVelocity! < -500)) {
      // Dismiss if dragged up far enough or with enough velocity
      setState(() => _isDismissing = true);
      _controller.reset();
      _animation = Tween<double>(begin: _dragOffset, end: -200).animate(_controller)
        ..addListener(() {
          setState(() {});
        })
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            OverlaySupportEntry.of(context)?.dismiss();
          }
        });
      _controller.forward();
    } else {
      // Animate back to original position
      _controller.reset();
      _animation = Tween<double>(begin: _dragOffset, end: 0).animate(_controller)
        ..addListener(() {
          setState(() {
            _dragOffset = _animation.value;
          });
        });
      _controller.forward().then((_) {
        setState(() {
          _dragOffset = 0;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final offset = _isDismissing ? _animation.value : _dragOffset;
    return GestureDetector(
      onTap: () {
        // Always dismiss the notification when tapped
        OverlaySupportEntry.of(context)?.dismiss();
        if (widget.onTap != null) {
          widget.onTap!();
        }
      },
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Transform.translate(
        offset: Offset(0, offset),
        child: Container(
          margin: EdgeInsets.only(
            top: topPadding + 8,
            left: 12,
            right: 12,
            bottom: 16,
          ),
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: const Color(0xFF0065FF),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.person_add_rounded,
                  color: const Color(0xFF0065FF),
                  size: 28,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Helper function to show custom notification
void showCustomNotification({
  required String title,
  String? subtitle,
  Duration duration = const Duration(seconds: 3),
  VoidCallback? onTap,
}) {
  showOverlayNotification(
    (context) => CustomNotification(
      title: title,
      subtitle: subtitle,
      duration: duration,
      onTap: onTap,
    ),
    duration: duration,
  );
} 