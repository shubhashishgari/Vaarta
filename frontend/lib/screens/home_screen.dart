// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// home_screen.dart - Main Conversation Screen

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../main.dart';
import '../widgets/waveform.dart';
import '../widgets/transcript_bubble.dart';
import '../widgets/clarify_prompt.dart';
import '../widgets/replay_button.dart';
import '../widgets/mic_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _serverController = TextEditingController(
    text: '192.168.1.15:8000',
  );
  bool _showServerInput = true;
  bool _isConnecting = false;
  bool _connectionFailed = false;

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  void _connect() async {
    setState(() {
      _isConnecting = true;
      _connectionFailed = false;
    });
    final state = context.read<VaartaState>();
    await state.connect(serverUrl: _serverController.text.trim());

    // Give the WebSocket a moment to establish or fail
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    setState(() {
      _isConnecting = false;
      if (state.isConnected) {
        // Success — move to main screen
        _showServerInput = false;
      } else {
        // Failed — stay on server input so the user can fix the address
        _connectionFailed = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VaartaState>(
      builder: (context, state, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          child: (_showServerInput && !state.isConnected)
              ? _buildConnectionScreen(state)
              : _buildMainScreen(state),
        );
      },
    );
  }

  Widget _buildMainScreen(VaartaState state) {
    return Scaffold(
      key: const ValueKey('main'),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(state),
                Expanded(
                  child: _buildSpeakerZone(state, 'A'),
                ),
                _buildDivider(),
                Expanded(
                  child: _buildSpeakerZone(state, 'B'),
                ),
              ],
            ),

            if (state.showClarification)
              ClarifyPrompt(
                text: state.clarificationText,
                reason: state.clarificationReason,
                onAccept: () => state.acceptClarification(),
                onCorrect: (correction) =>
                    state.correctClarification(correction),
                onDismiss: () => state.dismissClarification(),
              ),

            const Positioned(
              bottom: 24,
              right: 24,
              child: ReplayButton(),
            ),

            if (!state.isConnected)
              Positioned(
                bottom: 88,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: state.isConnected ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: Colors.red[400],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Reconnecting...',
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Connection Screen
  // ------------------------------------------------------------------

  Widget _buildConnectionScreen(VaartaState state) {
    return Scaffold(
      key: const ValueKey('connect'),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) => Transform.scale(
                    scale: value,
                    child: child,
                  ),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1A1A1A).withValues(alpha: 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'V',
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'VAARTA',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 6,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Real-Time Voice Translation',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    '11 Languages  ·  110 Pairs',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(height: 52),
                TextField(
                  controller: _serverController,
                  cursorColor: const Color(0xFF1A1A1A),
                  decoration: InputDecoration(
                    labelText: 'Server Address',
                    labelStyle: TextStyle(color: Colors.grey[500], fontSize: 13),
                    hintText: '192.168.x.x:8000',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: Color(0xFF1A1A1A), width: 1.5),
                    ),
                    prefixIcon:
                        Icon(Icons.dns_outlined, color: Colors.grey[500], size: 20),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                  ),
                ),
                const SizedBox(height: 12),
                // Connection error — only shown after a failed attempt
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: _connectionFailed && !_isConnecting
                      ? Container(
                          key: const ValueKey('err'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red[50],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.red[200]!),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  size: 16, color: Colors.red[600]),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  "Couldn't reach server. Check IP, Wi-Fi, and that backend is running.",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.red[700],
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : const SizedBox(key: ValueKey('noerr'), height: 0),
                ),
                const SizedBox(height: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isConnecting ? null : _connect,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A1A1A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[400],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isConnecting
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Connect',
                              key: ValueKey('connect'),
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 56),
                Text(
                  'by Neer, Shubhashish & Avichal',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[400],
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'CHRIST (Deemed to be University)',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[400],
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Top Bar
  // ------------------------------------------------------------------

  Widget _buildTopBar(VaartaState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F7F4),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'V',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Row(
              children: [
                _DomainChip(
                  label: 'General',
                  isActive: state.activeDomain == 'general',
                  onTap: () => state.setDomain('general'),
                ),
                const SizedBox(width: 6),
                _DomainChip(
                  label: 'Medical',
                  icon: Icons.local_hospital_outlined,
                  isActive: state.activeDomain == 'medical',
                  onTap: () => state.setDomain('medical'),
                ),
                const SizedBox(width: 6),
                _DomainChip(
                  label: 'Transport',
                  icon: Icons.directions_bus_outlined,
                  isActive: state.activeDomain == 'transport',
                  onTap: () => state.setDomain('transport'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            color: Colors.grey[500],
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Speaker Zone
  // ------------------------------------------------------------------

  Widget _buildSpeakerZone(VaartaState state, String speaker) {
    final isActive = state.activeSpeaker == speaker;
    final level = speaker == 'A' ? state.speakerALevel : state.speakerBLevel;
    final phase = state.phase;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      color: isActive ? const Color(0xFFF0EDE8) : const Color(0xFFF8F7F4),
      child: Column(
        children: [
          const SizedBox(height: 14),
          _buildSpeakerHeader(speaker, isActive, phase),
          const SizedBox(height: 6),

          if (isActive)
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(phase),
                  child: _buildActiveContent(state, speaker, level, phase),
                ),
              ),
            )
          else
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => state.switchSpeakerManually(),
                child: _buildInactiveContent(state, speaker),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpeakerHeader(
      String speaker, bool isActive, ConversationPhase phase) {
    final dotColor = isActive
        ? (phase == ConversationPhase.listening
            ? const Color(0xFFE53935)
            : phase == ConversationPhase.playing
                ? const Color(0xFF2196F3)
                : const Color(0xFF4CAF50))
        : Colors.grey[400]!;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isActive ? const Color(0xFF1A1A1A) : Colors.grey[500],
            letterSpacing: 1.4,
          ),
          child: Text('SPEAKER $speaker'),
        ),
      ],
    );
  }

  Widget _buildInactiveContent(VaartaState state, String speaker) {
    final transcripts =
        state.transcripts.where((t) => t.speaker == speaker).toList();
    if (transcripts.isEmpty) {
      return Center(
        child: Text(
          'Tap to take turn',
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 12,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
      );
    }
    return _buildTranscriptList(state, speaker, dimmed: true);
  }

  Widget _buildActiveContent(
      VaartaState state, String speaker, double level, ConversationPhase phase) {
    switch (phase) {
      case ConversationPhase.idle:
        final hasTranscripts =
            state.transcripts.any((t) => t.speaker == speaker);
        return Column(
          key: const ValueKey('idle'),
          children: [
            if (hasTranscripts)
              Expanded(child: _buildTranscriptList(state, speaker))
            else
              const Spacer(),
            MicButton(
              isRecording: false,
              onTap: () => state.startListening(),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to speak',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w400,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 20),
          ],
        );

      case ConversationPhase.listening:
        return Column(
          key: const ValueKey('listening'),
          children: [
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: WaveformWidget(level: level, isActive: true, height: 70),
            ),
            const SizedBox(height: 12),
            Text(
              'Listening…',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            Expanded(child: _buildTranscriptList(state, speaker)),
            MicButton(
              isRecording: true,
              onTap: () => state.stopListening(),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to stop',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 20),
          ],
        );

      case ConversationPhase.processing:
        return Column(
          key: const ValueKey('processing'),
          children: [
            const SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 18),
            if (state.liveTranscription.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    state.liveTranscription,
                    key: ValueKey(state.liveTranscription),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1A1A),
                      fontStyle: FontStyle.italic,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Text(
              'Translating…',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                letterSpacing: 0.3,
              ),
            ),
            Expanded(child: _buildTranscriptList(state, speaker)),
          ],
        );

      case ConversationPhase.playing:
        return Column(
          key: const ValueKey('playing'),
          children: [
            const SizedBox(height: 24),
            _PlayingIndicator(),
            const SizedBox(height: 14),
            Text(
              'Speaking…',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
            Expanded(child: _buildTranscriptList(state, speaker)),
          ],
        );
    }
  }

  // ------------------------------------------------------------------
  // Divider
  // ------------------------------------------------------------------

  Widget _buildDivider() {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 40),
      color: Colors.grey[300],
    );
  }

  // ------------------------------------------------------------------
  // Transcript List
  // ------------------------------------------------------------------

  Widget _buildTranscriptList(VaartaState state, String speaker,
      {bool dimmed = false}) {
    final speakerTranscripts =
        state.transcripts.where((t) => t.speaker == speaker).toList();

    if (speakerTranscripts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Opacity(
      opacity: dimmed ? 0.55 : 1.0,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        reverse: true,
        itemCount: speakerTranscripts.length,
        itemBuilder: (context, index) {
          final entry =
              speakerTranscripts[speakerTranscripts.length - 1 - index];
          return TranscriptBubble(entry: entry);
        },
      ),
    );
  }
}

// ------------------------------------------------------------------
// Playing Indicator — three animated bars
// ------------------------------------------------------------------

class _PlayingIndicator extends StatefulWidget {
  @override
  State<_PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<_PlayingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 28,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(3, (i) {
              final phase = (_c.value + i * 0.33) % 1.0;
              final h = 8 + (phase < 0.5 ? phase * 36 : (1 - phase) * 36);
              return Container(
                width: 4,
                height: h.clamp(6, 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------------
// Domain Chip
// ------------------------------------------------------------------

class _DomainChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isActive;
  final VoidCallback onTap;

  const _DomainChip({
    required this.label,
    this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF1A1A1A) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF1A1A1A)
                : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                child: Icon(
                  icon,
                  size: 12,
                  color: isActive ? Colors.white : Colors.grey[500],
                ),
              ),
              const SizedBox(width: 4),
            ],
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontSize: 11,
                color: isActive ? Colors.white : Colors.grey[600],
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
