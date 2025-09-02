import 'package:flutter/material.dart';
import 'dart:math';

class HeartCelebration extends StatefulWidget {
  final bool show;
  final int iconCount;
  final IconData icon;
  final Color color;
  final VoidCallback? onEnd;
  final bool originFromBottomNav;
  
  const HeartCelebration({
    Key? key, 
    required this.show, 
    required this.icon, 
    required this.color, 
    this.iconCount = 32, 
    this.onEnd, 
    this.originFromBottomNav = false
  }) : super(key: key);

  @override
  State<HeartCelebration> createState() => _HeartCelebrationState();
}

class _HeartCelebrationState extends State<HeartCelebration> with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;
  late final List<Animation<double>> _rotationAnimations;
  late final List<Animation<double>> _scaleAnimations;
  late final List<Animation<double>> _opacityAnimations;
  late final List<Offset> _randomOffsets;
  late final List<double> _randomSizes;
  late final List<double> _randomRotations;
  bool _ended = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    if (widget.show) _start();
  }

  void _initializeAnimations() {
    final random = Random();
    
    // Generate random properties for each icon
    _randomSizes = List.generate(widget.iconCount, (_) => 0.5 + random.nextDouble() * 1.0);
    _randomRotations = List.generate(widget.iconCount, (_) => (random.nextDouble() - 0.5) * 720);
    _randomOffsets = List.generate(widget.iconCount, (i) {
      // Create a more vertical spread
      final angle = (random.nextDouble() - 0.5) * pi * 0.8;
      final distance = 100 + random.nextDouble() * 200;
      
      // Apply vertical bias
      final verticalBias = 1.5;
      final dx = sin(angle) * distance * 0.7;
      final dy = -cos(angle) * distance * verticalBias;
      
      // Add some randomness to make it look more natural
      final randomFactor = 0.3;
      final randomDx = (random.nextDouble() - 0.5) * distance * randomFactor;
      final randomDy = (random.nextDouble() - 0.5) * distance * randomFactor;
      
      return Offset(dx + randomDx, dy + randomDy);
    });

    // Create controllers with varying durations
    _controllers = List.generate(widget.iconCount, (i) {
      final duration = 800 + random.nextInt(1200);
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: duration),
      );
    });

    // Create animations with custom curves
    _animations = _controllers.map((c) {
      return CurvedAnimation(
        parent: c,
        curve: Curves.easeOutCubic,
      );
    }).toList();

    // Create rotation animations
    _rotationAnimations = _controllers.map((c) {
      return Tween<double>(
        begin: 0,
        end: _randomRotations[_controllers.indexOf(c)],
      ).animate(CurvedAnimation(
        parent: c,
        curve: Curves.easeOutCubic,
      ));
    }).toList();

    // Create scale animations
    _scaleAnimations = _controllers.map((c) {
      return Tween<double>(
        begin: 0.8,
        end: _randomSizes[_controllers.indexOf(c)],
      ).animate(CurvedAnimation(
        parent: c,
        curve: Curves.easeOutCubic,
      ));
    }).toList();

    // Create opacity animations with delayed fade out
    _opacityAnimations = _controllers.map((c) {
      return TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween<double>(begin: 0, end: 1),
          weight: 20,
        ),
        TweenSequenceItem(
          tween: Tween<double>(begin: 1, end: 0),
          weight: 80,
        ),
      ]).animate(CurvedAnimation(
        parent: c,
        curve: Curves.easeInOut,
      ));
    }).toList();
  }

  @override
  void didUpdateWidget(covariant HeartCelebration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.show && !oldWidget.show && !_ended) {
      // Only restart animation if show changed from false to true
      _reset();
      _start();
    }
  }

  void _reset() {
    _ended = false;
    for (var c in _controllers) {
      c.reset();
    }
  }

  void _start() {
    for (var c in _controllers) {
      c.forward();
    }
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted && !_ended) {
        setState(() => _ended = true);
        widget.onEnd?.call();
      }
    });
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show || _ended) return const SizedBox.shrink();
    
    final screenSize = MediaQuery.of(context).size;
    
    // Calculate origin position based on whether it should come from bottom nav
    double originX, originY;
    
    // Center horizontally, but start from just above bottom navigation bar
    originX = screenSize.width / 2;
    originY = screenSize.height * 0.92; // Start from 92% down the screen (just above bottom nav)
    
    return IgnorePointer(
      child: Container(
        color: Colors.transparent,
        child: Stack(
          children: List.generate(widget.iconCount, (i) {
            return AnimatedBuilder(
              animation: _animations[i],
              builder: (context, child) {
                final anim = _animations[i].value;
                final offset = Offset(0, 0) + _randomOffsets[i] * anim;
                final opacity = _opacityAnimations[i].value;
                final scale = _scaleAnimations[i].value;
                final rotation = _rotationAnimations[i].value;
                
                return Positioned(
                  left: originX - 16 + offset.dx,
                  top: originY - 16 + offset.dy,
                  child: Opacity(
                    opacity: opacity,
                    child: Transform.rotate(
                      angle: rotation * (pi / 180),
                      child: Transform.scale(
                        scale: scale,
                        child: Icon(
                          widget.icon,
                          color: widget.color,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
