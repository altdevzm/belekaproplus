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
      // 1. Model Name (Vendor + Product Name)
      final vendor = _readFirstAvailableFile(['/sys/class/dmi/id/sys_vendor']);
      final product = _readFirstAvailableFile(['/sys/class/dmi/id/product_name']);
      final family = _readFirstAvailableFile(['/sys/class/dmi/id/product_family']);
      final modelStr = [vendor, product].where((s) => s.isNotEmpty).join(' ');
      data['model_name'] = modelStr.isNotEmpty ? modelStr : (family.isNotEmpty ? family : 'Generic POS Hardware');

      // 2. Serial Number
      final productSerial = _readFirstAvailableFile([
        '/sys/class/dmi/id/product_serial',
        '/sys/class/dmi/id/board_serial',
        '/sys/class/dmi/id/chassis_serial',
      ]);
      final machineId = _readFirstAvailableFile([
        '/etc/machine-id',
        '/var/lib/dbus/machine-id',
      ]);
      data['serial_number'] = productSerial.isNotEmpty ? productSerial : (machineId.isNotEmpty ? machineId : 'N/A');

      // 3. Motherboard & BIOS
      final boardName = _readFirstAvailableFile(['/sys/class/dmi/id/board_name']);
      final biosVer = _readFirstAvailableFile(['/sys/class/dmi/id/bios_version']);
      if (boardName.isNotEmpty) data['board_name'] = boardName;
      if (biosVer.isNotEmpty) data['bios_version'] = biosVer;

      // 4. Linux Machine ID & UUID
      data['machine_id'] = machineId;
      data['product_uuid'] = _readFirstAvailableFile([
        '/sys/class/dmi/id/product_uuid',
        '/sys/devices/virtual/dmi/id/product_uuid',
      ]);

      // 5. CPU Information
      data['cpu_model'] = _extractCpuModel();

      // 6. Linux Device Info Plugin
      try {
        final linuxInfo = await deviceInfo.linuxInfo;
        data['linux_machine_id'] = linuxInfo.machineId ?? '';
        data['linux_name'] = linuxInfo.name;
        if (data['model_name'] == 'Generic POS Hardware' && linuxInfo.prettyName.isNotEmpty) {
          data['model_name'] = linuxInfo.prettyName;
        }
      } catch (_) {}
    } else if (Platform.isWindows) {
      try {
        final winInfo = await deviceInfo.windowsInfo;
        data['model_name'] = '${winInfo.productName} (${winInfo.computerName})';
        data['serial_number'] = winInfo.deviceId;
        data['win_device_id'] = winInfo.deviceId;
        data['win_computer_name'] = winInfo.computerName;
        data['win_registered_owner'] = winInfo.registeredOwner;
        data['cpu_model'] = Platform.environment['PROCESSOR_IDENTIFIER'] ?? 'x86_64 Processor';
      } catch (_) {}
    } else if (Platform.isAndroid) {
      try {
        final androidInfo = await deviceInfo.androidInfo;
        data['model_name'] = '${androidInfo.brand.toUpperCase()} ${androidInfo.model}';
        final uniqueId = androidInfo.id.isNotEmpty
            ? androidInfo.id
            : androidInfo.fingerprint;
        data['serial_number'] = uniqueId;
        data['android_id'] = androidInfo.id;
        data['android_brand'] = androidInfo.brand;
        data['android_model'] = androidInfo.model;
        data['android_hardware'] = androidInfo.hardware;
        data['android_device'] = androidInfo.device;
        data['android_fingerprint'] = androidInfo.fingerprint;
        data['android_board'] = androidInfo.board;
        data['cpu_model'] = androidInfo.supportedAbis.isNotEmpty ? androidInfo.supportedAbis.join(', ') : 'ARM Architecture';
      } catch (_) {}
    } else if (Platform.isMacOS) {
      try {
        final macInfo = await deviceInfo.macOsInfo;
        data['model_name'] = macInfo.model;
        data['serial_number'] = macInfo.systemGUID ?? 'N/A';
        data['mac_system_guid'] = macInfo.systemGUID ?? '';
        data['mac_model'] = macInfo.model;
        data['mac_computer_name'] = macInfo.computerName;
        data['cpu_model'] = macInfo.kernelVersion;
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
          if (content.isNotEmpty && !content.toLowerCase().contains('none') && !content.toLowerCase().contains('to be filled')) {
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

  /// Returns diagnostic info for troubleshooting with human-friendly labels
  Future<Map<String, String>> getHardwareDiagnostics() async {
    final components = await _collectHardwareComponents();
    final hwid = await getHardwareId();
    
    final Map<String, String> diagnostics = {};
    
    // 1. Primary Identifiers
    if (components['model_name'] != null) {
      diagnostics['Model Name'] = components['model_name']!;
    }
    if (components['serial_number'] != null) {
      diagnostics['Serial / Hardware ID'] = components['serial_number']!;
    }
    if (components['cpu_model'] != null && components['cpu_model']!.isNotEmpty) {
      diagnostics['Processor (CPU)'] = components['cpu_model']!;
    }
    if (components['board_name'] != null && components['board_name']!.isNotEmpty) {
      diagnostics['Motherboard'] = components['board_name']!;
    }
    if (components['bios_version'] != null && components['bios_version']!.isNotEmpty) {
      diagnostics['BIOS Version'] = components['bios_version']!;
    }
    
    // 2. Machine Fingerprint & OS
    diagnostics['Hardware HWID'] = hwid;
    diagnostics['Hostname'] = components['hostname'] ?? Platform.localHostname;
    diagnostics['Operating System'] = Platform.operatingSystem;

    return diagnostics;
  }
}
