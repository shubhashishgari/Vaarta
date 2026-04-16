// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// waveform.dart - Smooth Animated Audio Waveform

import 'dart:math';
import 'package:flutter/material.dart';

class WaveformWidget extends StatefulWidget {
  final double level; // 0.0 to 1.0
  final bool isActive;
  final double height;

  const WaveformWidget({
    super.key,
    required this.level,
    this.isActive = false,
    this.height = 40,
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _displayedLevel = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant WaveformWidget old) {
    super.didUpdateWidget(old);
    // Smoothly interpolate toward the target level so changes aren't jarring
    _displayedLevel = _displayedLevel + (widget.level - _displayedLevel) * 0.35;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _WaveformPainter(
            level: widget.isActive ? max(_displayedLevel, 0.22) : _displayedLevel,
            animationValue: _controller.value,
            isActive: widget.isActive,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double level;
  final double animationValue;
  final bool isActive;

  _WaveformPainter({
    required this.level,
    required this.animationValue,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    if (isActive) {
      paint.color = const Color(0xFF1A1A1A).withValues(alpha: 0.75);
    } else {
      paint.color = const Color(0xFFBDBDBD).withValues(alpha: 0.3);
    }

    const barCount = 44;
    final spacing = size.width / barCount;
    final centerY = size.height / 2;
    final maxHeight = size.height * 0.85;

    for (int i = 0; i < barCount; i++) {
      final x = spacing * i + spacing / 2;

      // Multiple overlaid sine waves give an organic, flowing look
      final phase1 = (i / barCount * pi * 2) + (animationValue * pi * 2);
      final phase2 = (i / barCount * pi * 3) - (animationValue * pi * 2.5);
      final phase3 = (i / barCount * pi * 4) + (animationValue * pi * 1.3);
      final combined =
          (sin(phase1) * 0.55 + sin(phase2) * 0.3 + sin(phase3) * 0.15);

      // Envelope damps bars near the edges for a softer silhouette
      final t = i / (barCount - 1);
      final envelope = sin(t * pi);

      double amplitude;
      if (isActive) {
        amplitude = 0.12 + (combined.abs() * 0.55 + 0.15) * level * envelope;
      } else {
        amplitude = 0.04 + combined.abs() * 0.04 * envelope;
      }

      final barHeight = (amplitude * maxHeight).clamp(3.0, maxHeight);

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.level != level ||
        oldDelegate.animationValue != animationValue ||
        oldDelegate.isActive != isActive;
  }
}
