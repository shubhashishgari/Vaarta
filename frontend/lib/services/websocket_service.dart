// Vaarta by Neer Dwivedi, Shubhashish Garimella & Avichal Trivedi
// websocket_service.dart - WebSocket Communication Layer

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;

  String _url = '';
  bool _isConnected = false;
  bool _shouldReconnect = true;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  // Exponential backoff (per Vaarta report): 1s, 2s, 4s, 8s ... capped at 30s
  static const Duration _baseReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  Duration _nextBackoff() {
    // 2^attempts * base, capped
    final expSeconds =
        _baseReconnectDelay.inSeconds * (1 << _reconnectAttempts.clamp(0, 5));
    final capped = expSeconds > _maxReconnectDelay.inSeconds
        ? _maxReconnectDelay.inSeconds
        : expSeconds;
    return Duration(seconds: capped);
  }

  // Callbacks
  void Function(Map<String, dynamic>)? onMessage;
  void Function(bool)? onConnectionChanged;

  bool get isConnected => _isConnected;

  // ------------------------------------------------------------------
  // Connection Management
  // ------------------------------------------------------------------

  Future<void> connect(String url) async {
    _url = url;
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    await _connect();
  }

  Future<void> _connect() async {
    try {
      debugPrint('[Vaarta WS] Connecting to $_url...');
      _channel = WebSocketChannel.connect(Uri.parse(_url));

      // Wait for connection to be ready
      await _channel!.ready;

      _isConnected = true;
      _reconnectAttempts = 0;
      onConnectionChanged?.call(true);
      debugPrint('[Vaarta WS] Connected.');

      _subscription = _channel!.stream.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );
    } catch (e) {
      debugPrint('[Vaarta WS] Connection failed: $e');
      _isConnected = false;
      onConnectionChanged?.call(false);
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
    onConnectionChanged?.call(false);
    debugPrint('[Vaarta WS] Disconnected.');
  }

  // ------------------------------------------------------------------
  // Data Handling
  // ------------------------------------------------------------------

  void _onData(dynamic data) {
    if (data is String) {
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        onMessage?.call(json);
      } catch (e) {
        debugPrint('[Vaarta WS] JSON parse error: $e');
      }
    } else if (data is Uint8List) {
      // Binary audio data from server — handle as audio playback
      onMessage?.call({
        'type': 'audio_data',
        'bytes': data,
      });
    }
  }

  void _onError(dynamic error) {
    debugPrint('[Vaarta WS] Error: $error');
    _isConnected = false;
    onConnectionChanged?.call(false);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('[Vaarta WS] Connection closed.');
    _isConnected = false;
    onConnectionChanged?.call(false);
    _scheduleReconnect();
  }

  // ------------------------------------------------------------------
  // Sending
  // ------------------------------------------------------------------

  void sendJson(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('[Vaarta WS] Send error: $e');
    }
  }

  void sendAudioBytes(Uint8List bytes) {
    if (!_isConnected || _channel == null) return;
    try {
      _channel!.sink.add(bytes);
    } catch (e) {
      debugPrint('[Vaarta WS] Send audio error: $e');
    }
  }

  // ------------------------------------------------------------------
  // Reconnection
  // ------------------------------------------------------------------

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      debugPrint('[Vaarta WS] Max reconnect attempts reached.');
      return;
    }

    _reconnectTimer?.cancel();
    final delay = _nextBackoff();
    debugPrint(
      '[Vaarta WS] Reconnect scheduled in ${delay.inSeconds}s '
      '(attempt ${_reconnectAttempts + 1}/$_maxReconnectAttempts)',
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectAttempts++;
      debugPrint('[Vaarta WS] Reconnecting (attempt $_reconnectAttempts)...');
      _connect();
    });
  }

  void dispose() {
    disconnect();
  }
}
