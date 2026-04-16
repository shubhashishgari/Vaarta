// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// clarify_prompt.dart - Proactive Clarification Prompt Widget

import 'package:flutter/material.dart';

class ClarifyPrompt extends StatefulWidget {
  final String text;
  final String reason;
  final VoidCallback onAccept;
  final void Function(String correction) onCorrect;
  final VoidCallback onDismiss;

  const ClarifyPrompt({
    super.key,
    required this.text,
    required this.reason,
    required this.onAccept,
    required this.onCorrect,
    required this.onDismiss,
  });

  @override
  State<ClarifyPrompt> createState() => _ClarifyPromptState();
}

class _ClarifyPromptState extends State<ClarifyPrompt>
    with SingleTickerProviderStateMixin {
  final TextEditingController _correctionController = TextEditingController();
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _correctionController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _submitCorrection() {
    final correction = _correctionController.text.trim();
    if (correction.isNotEmpty) {
      widget.onCorrect(correction);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        color: Colors.black.withValues(alpha: 0.3),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Icon(Icons.help_outline, color: Colors.amber[700], size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Did you say:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: Icon(Icons.close, size: 18, color: Colors.grey[400]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // The flagged text
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F7F4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '"${widget.text}"',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Correction text field
                TextField(
                  controller: _correctionController,
                  decoration: InputDecoration(
                    hintText: 'Type correction here...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send, size: 20),
                      onPressed: _submitCorrection,
                    ),
                  ),
                  onSubmitted: (_) => _submitCorrection(),
                ),
                const SizedBox(height: 16),

                // Accept button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Yes, that\'s correct',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
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
