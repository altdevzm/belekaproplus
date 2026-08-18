import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final hwidServiceProvider = Provider<HwidService>((ref) {
  return HwidService();
});

class HwidService {
  static const String _hwidSalt = 'BELEKA_POS_HARDWARE_FINGERPRINT_V1_SECURE_SALT';
  String? _cachedHwid;

  /// Retrieves the immutable, deterministic Hardware ID (HWID) for this machine.
  /// Format: BP-XXXX-XXXX-XXXX-XXXX
  Future<String> getHardwareId() async {
    if (_cachedHwid != null) return _cachedHwid!;

    final components = await _collectHardwareComponents();
    final rawEntropy = components.entries
        .map((e) => '${e.key}=${e.value}')
        .join('|');

    // SHA-256 HMAC with salt
    final key = utf8.encode(_hwidSalt);
    final bytes = utf8.encode(rawEntropy);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    final hexString = digest.toString().toUpperCase();

    // Format into 4 chunks of 4 characters: BP-XXXX-XXXX-XXXX-XXXX
    final chunk1 = hexString.substring(0, 4);
    final chunk2 = hexString.substring(4, 8);
    final chunk3 = hexString.substring(8, 12);
    final chunk4 = hexString.substring(12, 16);

    final hwid = 'BP-$chunk1-$chunk2-$chunk3-$chunk4';
    _cachedHwid = hwid;
    return hwid;
  }

  /// Collects immutable system and hardware characteristics
  Future<Map<String, String>> _collectHardwareComponents() async {
    final Map<String, String> data = {};
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isLinux) {
      // 1. Linux Machine ID
      data['machine_id'] = _readFirstAvailableFile([
        '/etc/machine-id',
        '/var/lib/dbus/machine-id',
      ]);

      // 2. Motherboard / Product UUID
      data['product_uuid'] = _readFirstAvailableFile([
        '/sys/class/dmi/id/product_uuid',
        '/sys/devices/virtual/dmi/id/product_uuid',
      ]);

      // 3. Board Serial
      data['board_serial'] = _readFirstAvailableFile([
        '/sys/class/dmi/id/board_serial',
        '/sys/class/dmi/id/product_serial',
      ]);

      // 4. CPU Information
      data['cpu_model'] = _extractCpuModel();

      // 5. Linux Device Info Plugin
      try {
        final linuxInfo = await deviceInfo.linuxInfo;
        data['linux_machine_id'] = linuxInfo.machineId ?? '';
        data['linux_name'] = linuxInfo.name;
      } catch (_) {}
    } else if (Platform.isWindows) {
      try {
        final winInfo = await deviceInfo.windowsInfo;
        data['win_device_id'] = winInfo.deviceId;
        data['win_computer_name'] = winInfo.computerName;
        data['win_registered_owner'] = winInfo.registeredOwner;
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        final macInfo = await deviceInfo.macOsInfo;
        data['mac_system_guid'] = macInfo.systemGUID ?? '';
        data['mac_model'] = macInfo.model;
        data['mac_computer_name'] = macInfo.computerName;
      } catch (_) {}
    }

    // Host fallback
    data['hostname'] = Platform.localHostname;
    data['os_version'] = Platform.operatingSystemVersion;

    return data;
  }

  /// Helper to read the first existing file from a list of paths
  String _readFirstAvailableFile(List<String> paths) {
    for (final p in paths) {
      try {
        final file = File(p);
        if (file.existsSync()) {
          final content = file.readAsStringSync().trim();
          if (content.isNotEmpty) {
            return content;
          }
        }
      } catch (_) {}
    }
    return '';
  }

  /// Extracts CPU model name from /proc/cpuinfo
  String _extractCpuModel() {
    try {
      final file = File('/proc/cpuinfo');
      if (file.existsSync()) {
        final lines = file.readAsLinesSync();
        for (final line in lines) {
          if (line.startsWith('model name')) {
            final parts = line.split(':');
            if (parts.length > 1) {
              return parts[1].trim();
            }
          }
        }
      }
    } catch (_) {}
    return '';
  }

  /// Returns diagnostic info for troubleshooting
  Future<Map<String, String>> getHardwareDiagnostics() async {
    final components = await _collectHardwareComponents();
    final hwid = await getHardwareId();
    return {
      'Generated HWID': hwid,
      ...components,
    };
  }
}
