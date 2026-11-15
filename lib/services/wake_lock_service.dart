import 'dart:ffi';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Prevents the host OS (Linux / Windows) from entering sleep or hibernation
/// while the POS application is running.
///
/// Android screen/device wake-lock is handled natively via
/// `WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON` in `MainActivity.kt`.
class WakeLockService {
  WakeLockService._();
  static final WakeLockService instance = WakeLockService._();

  bool _enabled = false;
  Process? _linuxInhibitProcess;

  static const int _esSystemRequired = 0x00000001;
  static const int _esDisplayRequired = 0x00000002;
  static const int _esContinuous = 0x80000000;

  /// Enables sleep/hibernation prevention for the current platform.
  Future<void> enable() async {
    if (kIsWeb || _enabled) return;
    _enabled = true;

    try {
      if (Platform.isWindows) {
        _setWindowsExecutionState(
          _esContinuous | _esSystemRequired | _esDisplayRequired,
        );
      } else if (Platform.isLinux) {
        await _enableLinuxInhibit();
      }
    } catch (e) {
      debugPrint('WakeLockService.enable error: $e');
    }
  }

  /// Releases any active sleep/hibernation lock.
  Future<void> disable() async {
    if (kIsWeb || !_enabled) return;
    _enabled = false;

    try {
      if (Platform.isWindows) {
        _setWindowsExecutionState(_esContinuous);
      } else if (Platform.isLinux) {
        _linuxInhibitProcess?.kill();
        _linuxInhibitProcess = null;
      }
    } catch (e) {
      debugPrint('WakeLockService.disable error: $e');
    }
  }

  void _setWindowsExecutionState(int flags) {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setThreadExecutionState = kernel32.lookupFunction<
        Uint32 Function(Uint32 esFlags),
        int Function(int esFlags)>('SetThreadExecutionState');
    setThreadExecutionState(flags);
  }

  Future<void> _enableLinuxInhibit() async {
    // 1. Inhibit idle/sleep via systemd-inhibit for the lifetime of the app
    try {
      _linuxInhibitProcess?.kill();
      _linuxInhibitProcess = await Process.start(
        'systemd-inhibit',
        [
          '--what=idle:sleep',
          '--who=BelekaPOS',
          '--why=Beleka POS terminal is active',
          '--mode=block',
          'sleep',
          'infinity',
        ],
      );
    } catch (e) {
      debugPrint('WakeLockService systemd-inhibit unavailable: $e');
    }

    // 2. Best-effort X11 screensaver / DPMS disable
    try {
      await Process.run('xset', ['s', 'off', '-dpms']);
    } catch (_) {
      // Ignore if running on Wayland or xset is absent
    }
  }
}

