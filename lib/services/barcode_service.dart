import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';

final barcodeServiceProvider = Provider((ref) => BarcodeService());

final barcodeStreamProvider = StreamProvider<String>((ref) {
  final service = ref.watch(barcodeServiceProvider);
  service.init();
  ref.onDispose(() => service.dispose());
  return service.onBarcodeScanned;
});

class BarcodeService {
  final _controller = StreamController<String>.broadcast();
  Stream<String> get onBarcodeScanned => _controller.stream;
  
  String _buffer = '';
  DateTime _lastTime = DateTime.now();
  final AudioPlayer _player = AudioPlayer();
  bool _isInitialized = false;

  BarcodeService() {
    // Pre-load audio to reduce latency
    _player.setSource(AssetSource('audio/beep.wav')).catchError((e) => debugPrint('Error loading beep: $e'));
  }

  void init() {
    if (_isInitialized) return;
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _isInitialized = true;
    debugPrint('BarcodeService: Global hardware listener initialized.');
  }

  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _isInitialized = false;
    _controller.close();
    _player.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final now = DateTime.now();
      final diff = now.difference(_lastTime).inMilliseconds;
      _lastTime = now;

      // Typical scanner speed is < 50ms between characters, but some HID scanners or OS event loops
      // introduce 100-200ms inter-character latency.
      if (diff > 250 && _buffer.isNotEmpty) {
        _buffer = '';
      }

      final isEnter = event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter ||
          event.character == '\n' ||
          event.character == '\r';

      if (isEnter) {
        final cleanBuffer = _buffer.trim();
        if (cleanBuffer.length >= 2) {
          _buffer = '';
          _controller.add(cleanBuffer);
          _playBeep();
          debugPrint('BarcodeService: Scanned barcode detected: $cleanBuffer');
          return true; // Consumed the enter key
        }
        _buffer = '';
      } else {
        // Extract character from event.character or keyLabel
        String? char = event.character;
        if (char == null || char.isEmpty) {
          final label = event.logicalKey.keyLabel;
          if (label.length == 1 && _isValidBarcodeChar(label)) {
            char = label;
          }
        }

        if (char != null && _isValidBarcodeChar(char)) {
          // Guard against stale buffer accumulation (barcodes rarely exceed 48 chars)
          if (_buffer.length >= 48) {
            _buffer = '';
            debugPrint('BarcodeService: Buffer overflow reset (exceeded 48 chars).');
          }
          _buffer += char;
        }
      }
    }
    return false;
  }

  bool _isValidBarcodeChar(String char) {
    // Alphanumeric, hyphen, slash, etc.
    final regex = RegExp(r'[a-zA-Z0-9\-\./]');
    return regex.hasMatch(char);
  }

  /// Clears the internal scan buffer and resets the inter-character timer.
  /// Call this after a successful product lookup, a failed lookup, or after a
  /// sale is completed to ensure the next scan is treated as an independent input.
  void clearBuffer() {
    _buffer = '';
    _lastTime = DateTime(1970); // Reset timer so the next char is never treated as a continuation
    debugPrint('BarcodeService: Buffer cleared.');
  }

  Future<void> _playBeep() async {
    try {
      if (_player.state == PlayerState.playing) {
        await _player.stop();
      }
      await _player.resume();
    } catch (e) {
      debugPrint('Error playing scanner beep: $e');
    }
  }
}
