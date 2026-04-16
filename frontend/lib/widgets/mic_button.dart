// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// mic_button.dart - Animated Mic/Stop Button

import 'package:flutter/material.dart';

/// A large circular button that smoothly animates between mic and stop states,
/// with an optional pulse ring when active.
class MicButton extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap;

  const MicButton({
    super.key,
    required this.isRecording,
    required this.onTap,
  });

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _tapController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.0,
      upperBound: 0.08,
    );
    if (widget.isRecording) _pulseController.repeat();
  }

  @override
  void didUpdateWidget(covariant MicButton old) {
    super.didUpdateWidget(old);
    if (widget.isRecording && !_pulseController.isAnimating) {
      _pulseController.repeat();
    } else if (!widget.isRecording && _pulseController.isAnimating) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _onTapDown(_) => _tapController.forward();
  void _onTapUp(_) {
    _tapController.reverse();
    widget.onTap();
  }
  void _onTapCancel() => _tapController.reverse();

  @override
  Widget build(BuildContext context) {
    final color = widget.isRecording
        ? const Color(0xFFE53935)
        : const Color(0xFF1A1A1A);

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseController, _tapController]),
        builder: (context, child) {
          final scale = 1.0 - _tapController.value;
          return SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Pulse ring (only when recording)
                if (widget.isRecording)
                  ..._buildPulseRings(color),

                // Main circle
                Transform.scale(
                  scale: scale,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.25),
                          blurRadius: widget.isRecording ? 20 : 14,
                          spreadRadius: widget.isRecording ? 2 : 0,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (child, anim) => ScaleTransition(
                        scale: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                      child: Icon(
                        widget.isRecording
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                        key: ValueKey(widget.isRecording),
                        color: Colors.white,
                        size: widget.isRecording ? 38 : 34,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildPulseRings(Color color) {
    return List.generate(2, (i) {
      final phase = (_pulseController.value + i * 0.5) % 1.0;
      final size = 80 + (phase * 40);
      final opacity = (1.0 - phase) * 0.35;
      return IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: opacity),
              width: 2,
            ),
          ),
        ),
      );
    });
  }
}
