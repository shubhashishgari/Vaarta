// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// main.dart - App Entry Point

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'services/websocket_service.dart';
import 'services/audio_service.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const VaartaApp());
}

class VaartaApp extends StatelessWidget {
  const VaartaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => VaartaState()),
      ],
      child: MaterialApp(
        title: 'Vaarta',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          scaffoldBackgroundColor: const Color(0xFFF8F7F4),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1A1A1A),
            surface: const Color(0xFFF8F7F4),
          ),
          fontFamily: 'Roboto',
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF8F7F4),
            foregroundColor: Color(0xFF1A1A1A),
            elevation: 0,
          ),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
        routes: {
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}

/// Conversation phase for push-to-talk flow.
enum ConversationPhase {
  idle,       // Waiting for user to tap mic
  listening,  // Recording audio
  processing, // Waiting for STT/translation/TTS
  playing,    // TTS audio is playing
}

/// Central app state — manages WebSocket, audio, transcriptions, and domain.
class VaartaState extends ChangeNotifier {
  final WebSocketService _wsService = WebSocketService();
  final AudioService _audioService = AudioService();

  // Connection state
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  // Conversation phase
  ConversationPhase _phase = ConversationPhase.idle;
  ConversationPhase get phase => _phase;

  // Active domain
  String _activeDomain = 'general';
  String get activeDomain => _activeDomain;

  // Active speaker
  String _activeSpeaker = 'A';
  String get activeSpeaker => _activeSpeaker;

  // Transcription bubbles
  final List<TranscriptEntry> _transcripts = [];
  List<TranscriptEntry> get transcripts => List.unmodifiable(_transcripts);

  // Live transcription text (shown while processing)
  String _liveTranscription = '';
  String get liveTranscription => _liveTranscription;

  // Clarification state
  bool _showClarification = false;
  bool get showClarification => _showClarification;
  String _clarificationText = '';
  String get clarificationText => _clarificationText;
  String _clarificationReason = '';
  String get clarificationReason => _clarificationReason;

  // Audio levels for waveform
  double _speakerALevel = 0.0;
  double get speakerALevel => _speakerALevel;
  double _speakerBLevel = 0.0;
  double get speakerBLevel => _speakerBLevel;

  // Vocabulary
  Map<String, String> _personalVocab = {};
  Map<String, String> get personalVocab => Map.unmodifiable(_personalVocab);

  // Server URL
  String _serverUrl = '192.168.1.15:8000';
  String get serverUrl => _serverUrl;

  // Safety timer — revert to idle if processing hangs (backend crash, drop, etc.)
  Timer? _processingTimeout;

  VaartaState() {
    _wsService.onMessage = _handleMessage;
    _wsService.onConnectionChanged = _handleConnectionChanged;
    _audioService.onPlaybackComplete = _onPlaybackComplete;
  }

  void _clearProcessingTimeout() {
    _processingTimeout?.cancel();
    _processingTimeout = null;
  }

  void _startProcessingTimeout() {
    _clearProcessingTimeout();
    _processingTimeout = Timer(const Duration(seconds: 30), () {
      if (_phase == ConversationPhase.processing) {
        debugPrint('[Vaarta] Processing timeout — reverting to idle');
        _phase = ConversationPhase.idle;
        _liveTranscription = '';
        notifyListeners();
      }
    });
  }

  // ------------------------------------------------------------------
  // Connection
  // ------------------------------------------------------------------

  Future<void> connect({String? serverUrl}) async {
    if (serverUrl != null) _serverUrl = serverUrl;
    await _wsService.connect('ws://$_serverUrl/ws/session');
    await _audioService.initialize();
    // Do NOT auto-start recording — user taps mic button
  }

  void disconnect() {
    _audioService.stopRecording();
    _wsService.disconnect();
    _isConnected = false;
    _phase = ConversationPhase.idle;
    notifyListeners();
  }

  void _handleConnectionChanged(bool connected) {
    _isConnected = connected;
    // If the connection drops while we're mid-processing, reset the UI to idle
    // so the user isn't stuck on "Translating…" forever. They can retry once
    // reconnected.
    if (!connected &&
        (_phase == ConversationPhase.processing ||
            _phase == ConversationPhase.listening)) {
      _audioService.stopRecording();
      _phase = ConversationPhase.idle;
      _liveTranscription = '';
      _clearProcessingTimeout();
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Push-to-Talk
  // ------------------------------------------------------------------

  void startListening() {
    if (!_isConnected || _phase != ConversationPhase.idle) return;

    _phase = ConversationPhase.listening;
    _liveTranscription = '';
    notifyListeners();

    _audioService.startRecording((audioBytes) {
      if (_isConnected) {
        _wsService.sendAudioBytes(audioBytes);
      }
    });
  }

  void stopListening() {
    if (_phase != ConversationPhase.listening) return;

    _audioService.stopRecording();
    _phase = ConversationPhase.processing;
    notifyListeners();

    // Tell backend to flush remaining audio buffer
    _wsService.sendJson({'type': 'stop_speaking'});

    // Safety net — if backend doesn't respond in 30s, unblock the UI
    _startProcessingTimeout();
  }

  /// Manually switch active speaker — used when the user taps the inactive
  /// zone. Safe only outside of listening/processing so we don't abort a
  /// turn mid-flight.
  void switchSpeakerManually() {
    if (!_isConnected) return;
    if (_phase == ConversationPhase.listening ||
        _phase == ConversationPhase.processing) return;
    _phase = ConversationPhase.idle;
    _liveTranscription = '';
    _wsService.sendJson({'type': 'switch_speaker'});
    notifyListeners();
  }

  void _onPlaybackComplete() {
    if (_phase != ConversationPhase.playing) return;

    // Auto-switch to other speaker
    _phase = ConversationPhase.idle;
    _liveTranscription = '';
    _wsService.sendJson({'type': 'switch_speaker'});
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Message Handling
  // ------------------------------------------------------------------

  void _handleMessage(Map<String, dynamic> message) {
    final type = message['type'] as String? ?? '';

    switch (type) {
      case 'transcription':
        _handleTranscription(message);
        break;
      case 'translation':
        _handleTranslation(message);
        break;
      case 'audio':
        _handleAudio(message);
        break;
      case 'clarification_request':
        _handleClarificationRequest(message);
        break;
      case 'speaker_switched':
        _activeSpeaker = message['active_speaker'] ?? 'A';
        notifyListeners();
        break;
      case 'domain_changed':
        _activeDomain = message['domain'] ?? 'general';
        notifyListeners();
        break;
      case 'processing_complete':
        // Backend finished processing — if no transcription/translation came,
        // go back to idle
        if (_phase == ConversationPhase.processing && _liveTranscription.isEmpty) {
          _phase = ConversationPhase.idle;
          _clearProcessingTimeout();
          notifyListeners();
        }
        break;
      case 'error':
        debugPrint('[Vaarta] Error: ${message['message']}');
        break;
    }
  }

  void _handleTranscription(Map<String, dynamic> msg) {
    final speaker = msg['speaker'] ?? 'A';
    final level = (msg['confidence'] as num?)?.toDouble() ?? 0.5;
    final text = msg['text'] as String? ?? '';

    if (speaker == 'A') {
      _speakerALevel = level;
    } else {
      _speakerBLevel = level;
    }

    // Show live transcription text
    _liveTranscription = text;
    notifyListeners();
  }

  void _handleTranslation(Map<String, dynamic> msg) {
    final entry = TranscriptEntry(
      speaker: msg['speaker'] ?? 'A',
      originalText: msg['original_text'] ?? '',
      translatedText: msg['translated_text'] ?? '',
      sourceLanguage: msg['source_language_name'] ?? '',
      targetLanguage: msg['target_language_name'] ?? '',
      timestamp: DateTime.now(),
    );
    _transcripts.add(entry);

    // Reset audio level
    if (entry.speaker == 'A') {
      _speakerALevel = 0.0;
    } else {
      _speakerBLevel = 0.0;
    }
    notifyListeners();
  }

  void _handleAudio(Map<String, dynamic> msg) {
    final audioBase64 = msg['audio'] as String?;
    if (audioBase64 != null && audioBase64.isNotEmpty) {
      try {
        final audioBytes = Uint8List.fromList(base64Decode(audioBase64));
        _phase = ConversationPhase.playing;
        _clearProcessingTimeout();
        notifyListeners();
        _audioService.playAudioBytes(audioBytes);
      } catch (e) {
        debugPrint('[Vaarta] Audio decode error: $e');
      }
    }
  }

  void _handleClarificationRequest(Map<String, dynamic> msg) {
    _showClarification = true;
    _clarificationText = msg['text'] ?? '';
    _clarificationReason = msg['reason'] ?? '';
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Actions
  // ------------------------------------------------------------------

  void switchSpeaker() {
    _wsService.sendJson({'type': 'switch_speaker'});
  }

  void setDomain(String domain) {
    _activeDomain = domain;
    _wsService.sendJson({'type': 'set_domain', 'domain': domain});
    notifyListeners();
  }

  void acceptClarification() {
    _wsService.sendJson({
      'type': 'clarification_response',
      'original_text': _clarificationText,
      'accepted': true,
    });
    _showClarification = false;
    notifyListeners();
  }

  void correctClarification(String correction) {
    _wsService.sendJson({
      'type': 'clarification_response',
      'original_text': _clarificationText,
      'corrected_text': correction,
      'accepted': false,
    });
    _showClarification = false;
    notifyListeners();
  }

  void dismissClarification() {
    _showClarification = false;
    // If the user dismisses without responding, the backend is no longer
    // going to send a translation — we must return to idle so the next
    // turn can start. Otherwise the UI is stuck on "Translating…" forever.
    if (_phase == ConversationPhase.processing) {
      _phase = ConversationPhase.idle;
      _liveTranscription = '';
      _clearProcessingTimeout();
    }
    notifyListeners();
  }

  void replay() {
    _wsService.sendJson({'type': 'replay'});
  }

  void deleteVocabWord(String word) {
    _personalVocab.remove(word);
    _wsService.sendJson({'type': 'delete_vocab', 'word': word});
    notifyListeners();
  }

  void setPersonalVocab(Map<String, String> vocab) {
    _personalVocab = vocab;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    _audioService.dispose();
    super.dispose();
  }
}

/// A single transcript entry in the conversation.
class TranscriptEntry {
  final String speaker;
  final String originalText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final DateTime timestamp;

  TranscriptEntry({
    required this.speaker,
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.timestamp,
  });
}
