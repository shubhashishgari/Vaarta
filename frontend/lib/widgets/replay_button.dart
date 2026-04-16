// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// replay_button.dart - Replay Last Translation Audio

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';

class ReplayButton extends StatefulWidget {
  const ReplayButton({super.key});

  @override
  State<ReplayButton> createState() => _ReplayButtonState();
}

class _ReplayButtonState extends State<ReplayButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTap() {
    if (_isPlaying) return;

    final state = context.read<VaartaState>();
    state.replay();

    setState(() => _isPlaying = true);
    _controller.forward().then((_) {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _controller.reverse();
          setState(() => _isPlaying = false);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _isPlaying ? const Color(0xFF333333) : const Color(0xFF1A1A1A),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          _isPlaying ? Icons.volume_up : Icons.replay,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}
