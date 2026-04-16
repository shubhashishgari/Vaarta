// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// audio_service.dart - Microphone Capture & Audio Playback

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<Uint8List>? _recordingSubscription;
  StreamSubscription? _playerStateSubscription;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isInitialized = false;

  // Callbacks
  void Function()? onPlaybackComplete;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;

  // ------------------------------------------------------------------
  // Initialization
  // ------------------------------------------------------------------

  Future<void> initialize() async {
    if (_isInitialized) return;

    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      debugPrint('[Vaarta Audio] Microphone permission denied.');
      return;
    }

    // Listen for playback state changes
    _playerStateSubscription = _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _isPlaying = false;
        onPlaybackComplete?.call();
      }
    });

    _isInitialized = true;
    debugPrint('[Vaarta Audio] Audio service initialized.');
  }

  // ------------------------------------------------------------------
  // Recording (Microphone → WebSocket)
  // ------------------------------------------------------------------

  Future<void> startRecording(void Function(Uint8List) onAudioData) async {
    if (!_isInitialized || _isRecording) return;

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        debugPrint('[Vaarta Audio] No recording permission.');
        return;
      }

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 256000,
        ),
      );

      _isRecording = true;
      debugPrint('[Vaarta Audio] Recording started.');

      _recordingSubscription = stream.listen(
        (data) {
          onAudioData(data);
        },
        onError: (error) {
          debugPrint('[Vaarta Audio] Recording error: $error');
        },
      );
    } catch (e) {
      debugPrint('[Vaarta Audio] Failed to start recording: $e');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    _recordingSubscription?.cancel();
    _recordingSubscription = null;
    await _recorder.stop();
    _isRecording = false;
    debugPrint('[Vaarta Audio] Recording stopped.');
  }

  // ------------------------------------------------------------------
  // Playback (Server MP3 Audio → Speaker)
  // ------------------------------------------------------------------

  Future<void> playAudioBytes(Uint8List audioBytes) async {
    try {
      _isPlaying = true;
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/vaarta_tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await file.writeAsBytes(audioBytes);
      await _player.setFilePath(file.path);
      await _player.play();

      // Clean up temp file after a delay (ignore errors — file may already
      // be gone or locked; doesn't affect the app).
      Future.delayed(const Duration(seconds: 30), () async {
        try {
          await file.delete();
        } catch (_) {}
      });
    } catch (e) {
      // If playback fails for any reason (bad MP3, audio session issue, etc.)
      // we must still advance the state machine — otherwise the UI is stuck
      // in the "playing" phase with no way to continue the conversation.
      _isPlaying = false;
      debugPrint('[Vaarta Audio] Playback error: $e');
      onPlaybackComplete?.call();
    }
  }

  // ------------------------------------------------------------------
  // Cleanup
  // ------------------------------------------------------------------

  void dispose() {
    stopRecording();
    _playerStateSubscription?.cancel();
    _recorder.dispose();
    _player.dispose();
  }
}
