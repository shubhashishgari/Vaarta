// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// transcript_bubble.dart - Conversation Transcript Display

import 'package:flutter/material.dart';
import '../main.dart';

class TranscriptBubble extends StatefulWidget {
  final TranscriptEntry entry;

  const TranscriptBubble({super.key, required this.entry});

  @override
  State<TranscriptBubble> createState() => _TranscriptBubbleState();
}

class _TranscriptBubbleState extends State<TranscriptBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.entry.originalText,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  height: 1.35,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.entry.translatedText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1A1A),
                  height: 1.4,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    widget.entry.sourceLanguage,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded,
                      size: 10, color: Colors.grey[400]),
                  const SizedBox(width: 4),
                  Text(
                    widget.entry.targetLanguage,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
