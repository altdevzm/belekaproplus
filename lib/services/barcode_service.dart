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

      // Typical scanner speed is < 50ms between characters. 
      // If a gap is too large, it may be human typing unless the buffer is empty.
      if (diff > 80 && _buffer.isNotEmpty) {
        _buffer = '';
      }

      if (event.logicalKey == LogicalKeyboardKey.enter) {
        if (_buffer.isNotEmpty && _buffer.length >= 3) {
          final code = _buffer;
          _buffer = '';
          _controller.add(code);
          _playBeep();
          debugPrint('Barcode Detected: $code');
          return true; // We consumed the Enter key if it capped a barcode
        }
        _buffer = '';
      } else {
        // Only accept alphanumeric and basic symbols for barcodes
        final char = event.character;
        if (char != null && _isValidBarcodeChar(char)) {
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
