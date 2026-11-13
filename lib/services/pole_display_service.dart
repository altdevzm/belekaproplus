import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';

/// Configuration model for the Customer Display (Pole Display)
class PoleDisplayConfig {
  final bool enabled;
  final String port; // e.g. 'COM2', '/dev/ttyUSB0', '127.0.0.1:9002'
  final int baudRate; // e.g. 9600, 2400, 19200
  final String protocol; // 'esc_pos', 'cd5220', 'logic_controls', 'aedex', 'led8', 'raw_ascii'
  final int columns; // 20 (standard VFD), 16 (LCD), or 8 (LED numeric)
  final int rows; // 2 (standard VFD/LCD) or 1 (LED numeric)
  final String welcomeLine1;
  final String welcomeLine2;
  final String thankYouLine1;
  final String thankYouLine2;
  final bool showOnScreenPreview; // Show floating/header mini VFD readout in POS

  const PoleDisplayConfig({
    this.enabled = false,
    this.port = 'COM2',
    this.baudRate = 9600,
    this.protocol = 'esc_pos',
    this.columns = 20,
    this.rows = 2,
    this.welcomeLine1 = 'WELCOME TO OUR STORE',
    this.welcomeLine2 = 'NEXT CUSTOMER PLEASE',
    this.thankYouLine1 = 'THANK YOU!',
    this.thankYouLine2 = 'PLEASE COME AGAIN',
    this.showOnScreenPreview = true,
  });

  PoleDisplayConfig copyWith({
    bool? enabled,
    String? port,
    int? baudRate,
    String? protocol,
    int? columns,
    int? rows,
    String? welcomeLine1,
    String? welcomeLine2,
    String? thankYouLine1,
    String? thankYouLine2,
    bool? showOnScreenPreview,
  }) {
    return PoleDisplayConfig(
      enabled: enabled ?? this.enabled,
      port: port ?? this.port,
      baudRate: baudRate ?? this.baudRate,
      protocol: protocol ?? this.protocol,
      columns: columns ?? this.columns,
      rows: rows ?? this.rows,
      welcomeLine1: welcomeLine1 ?? this.welcomeLine1,
      welcomeLine2: welcomeLine2 ?? this.welcomeLine2,
      thankYouLine1: thankYouLine1 ?? this.thankYouLine1,
      thankYouLine2: thankYouLine2 ?? this.thankYouLine2,
      showOnScreenPreview: showOnScreenPreview ?? this.showOnScreenPreview,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'port': port,
    'baudRate': baudRate,
    'protocol': protocol,
    'columns': columns,
    'rows': rows,
    'welcomeLine1': welcomeLine1,
    'welcomeLine2': welcomeLine2,
    'thankYouLine1': thankYouLine1,
    'thankYouLine2': thankYouLine2,
    'showOnScreenPreview': showOnScreenPreview,
  };

  factory PoleDisplayConfig.fromJson(Map<String, dynamic> json) {
    return PoleDisplayConfig(
      enabled: json['enabled'] as bool? ?? false,
      port: json['port'] as String? ?? 'COM2',
      baudRate: (json['baudRate'] as num?)?.toInt() ?? 9600,
      protocol: json['protocol'] as String? ?? 'esc_pos',
      columns: (json['columns'] as num?)?.toInt() ?? 20,
      rows: (json['rows'] as num?)?.toInt() ?? 2,
      welcomeLine1: json['welcomeLine1'] as String? ?? 'WELCOME TO OUR STORE',
      welcomeLine2: json['welcomeLine2'] as String? ?? 'NEXT CUSTOMER PLEASE',
      thankYouLine1: json['thankYouLine1'] as String? ?? 'THANK YOU!',
      thankYouLine2: json['thankYouLine2'] as String? ?? 'PLEASE COME AGAIN',
      showOnScreenPreview: json['showOnScreenPreview'] as bool? ?? true,
    );
  }
}

/// Live state currently shown on the Customer Pole Display
class PoleDisplayFrame {
  final String line1;
  final String line2;
  final String mode; // 'IDLE', 'ITEM', 'TENDER', 'COMPLETE'
  final double totalPayable;
  final double amountTendered;
  final double changeDue;
  final String? lastItemName;
  final int? lastItemQty;
  final double? lastItemPrice;
  final bool isHardwareConnected;
  final DateTime timestamp;

  PoleDisplayFrame({
    required this.line1,
    required this.line2,
    this.mode = 'IDLE',
    this.totalPayable = 0.0,
    this.amountTendered = 0.0,
    this.changeDue = 0.0,
    this.lastItemName,
    this.lastItemQty,
    this.lastItemPrice,
    this.isHardwareConnected = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Discovered serial/USB/TCP port info for Pole Display
class PoleDisplayPortInfo {
  final String path;
  final String label;
  final String type; // 'serial_usb', 'serial_com', 'tcp_bridge'

  const PoleDisplayPortInfo({
    required this.path,
    required this.label,
    required this.type,
  });
}

/// Result of testing a Pole Display connection
class PoleDisplayTestResult {
  final bool success;
  final String message;

  const PoleDisplayTestResult({
    required this.success,
    required this.message,
  });
}

final poleDisplayServiceProvider = Provider<PoleDisplayService>((ref) {
  final storeConfig = ref.watch(storeConfigProvider).value;
  final service = PoleDisplayService(
    storeBusinessName: storeConfig?.businessName,
    currencySymbol: storeConfig?.currencySymbol ?? 'K',
  );
  ref.onDispose(service.dispose);
  return service;
});

final livePoleDisplayFrameProvider =
    StreamProvider.autoDispose<PoleDisplayFrame>((ref) {
      final service = ref.watch(poleDisplayServiceProvider);
      return service.frameStream;
    });

class PoleDisplayService {
  final String? storeBusinessName;
  final String currencySymbol;

  PoleDisplayConfig _config = const PoleDisplayConfig();
  PoleDisplayConfig get config => _config;

  final StreamController<PoleDisplayFrame> _frameController =
      StreamController<PoleDisplayFrame>.broadcast();

  Stream<PoleDisplayFrame> get frameStream => _frameController.stream;

  late PoleDisplayFrame _currentFrame;
  PoleDisplayFrame get currentFrame => _currentFrame;

  Socket? _tcpSocket;
  Timer? _resetToIdleTimer;
  bool _isHardwareConnected = false;
  bool get isHardwareConnected => _isHardwareConnected;

  PoleDisplayService({
    this.storeBusinessName,
    this.currencySymbol = 'K',
  }) {
    final defaultLine1 =
        (storeBusinessName != null && storeBusinessName!.trim().isNotEmpty)
        ? 'WELCOME TO ${storeBusinessName!.trim().toUpperCase()}'
        : 'WELCOME TO OUR STORE';
    _config = PoleDisplayConfig(welcomeLine1: defaultLine1);
    _currentFrame = PoleDisplayFrame(
      line1: _padOrTrim(defaultLine1, 20),
      line2: _padOrTrim(_config.welcomeLine2, 20),
      mode: 'IDLE',
    );
    _loadPersistedConfig();
  }

  Future<File> _getConfigFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/pole_display_config.json');
  }

  Future<PoleDisplayConfig> _loadPersistedConfig() async {
    try {
      final file = await _getConfigFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        _config = PoleDisplayConfig.fromJson(map);
        if (_config.enabled) {
          await showIdle();
        } else {
          _emitFrame(
            line1: _padOrTrim(_config.welcomeLine1, _config.columns),
            line2: _padOrTrim(_config.welcomeLine2, _config.columns),
            mode: 'IDLE',
          );
        }
      }
    } catch (e) {
      debugPrint('PoleDisplayService: Load config notice: $e');
    }
    return _config;
  }

  Future<void> saveConfig(PoleDisplayConfig newConfig) async {
    _config = newConfig;
    try {
      final file = await _getConfigFile();
      await file.writeAsString(jsonEncode(newConfig.toJson()));
    } catch (e) {
      debugPrint('PoleDisplayService: Save config error: $e');
    }
    if (_config.enabled) {
      await showIdle();
    } else {
      await _closeSocket();
      _isHardwareConnected = false;
      _emitFrame(
        line1: _padOrTrim(_config.welcomeLine1, _config.columns),
        line2: _padOrTrim(_config.welcomeLine2, _config.columns),
        mode: 'IDLE',
      );
    }
  }

  /// Scans available serial/USB/COM/TCP ports for a customer pole display
  Future<List<PoleDisplayPortInfo>> scanAvailablePorts() async {
    final List<PoleDisplayPortInfo> ports = [];

    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final devDir = Directory('/dev');
        if (devDir.existsSync()) {
          for (final entity in devDir.listSync()) {
            final name = entity.path.split('/').last;
            if (name.startsWith('ttyUSB')) {
              ports.add(
                PoleDisplayPortInfo(
                  path: entity.path,
                  label: 'USB VFD Pole Display ($name)',
                  type: 'serial_usb',
                ),
              );
            } else if (name.startsWith('ttyACM')) {
              ports.add(
                PoleDisplayPortInfo(
                  path: entity.path,
                  label: 'USB CDC Pole Display ($name)',
                  type: 'serial_usb',
                ),
              );
            } else if (name.startsWith('ttyS')) {
              final idx = int.tryParse(name.replaceFirst('ttyS', ''));
              if (idx != null && idx <= 3) {
                ports.add(
                  PoleDisplayPortInfo(
                    path: entity.path,
                    label: 'RS232 Serial Port ($name)',
                    type: 'serial_com',
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        debugPrint('PoleDisplayService: Error scanning /dev: $e');
      }
    }

    if (Platform.isWindows) {
      try {
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          '[System.IO.Ports.SerialPort]::GetPortNames()',
        ]);
        if (res.exitCode == 0) {
          final lines = res.stdout
              .toString()
              .split(RegExp(r'[\r\n]+'))
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          for (final com in lines) {
            ports.add(
              PoleDisplayPortInfo(
                path: com,
                label: 'Active Serial Port ($com)',
                type: 'serial_com',
              ),
            );
          }
        }
      } catch (_) {}

      for (int i = 1; i <= 8; i++) {
        final com = 'COM$i';
        if (!ports.any((p) => p.path.toUpperCase() == com)) {
          ports.add(
            PoleDisplayPortInfo(
              path: com,
              label: 'Serial Port $com',
              type: 'serial_com',
            ),
          );
        }
      }
    }

    ports.add(
      const PoleDisplayPortInfo(
        path: '127.0.0.1:9002',
        label: 'TCP Pole Display Bridge (127.0.0.1:9002)',
        type: 'tcp_bridge',
      ),
    );

    return ports;
  }

  /// Auto-detects the first connected USB/Serial/TCP pole display port
  Future<PoleDisplayPortInfo?> autoDetectPort() async {
    final ports = await scanAvailablePorts();
    for (final p in ports) {
      if (p.type == 'serial_usb') {
        return p;
      }
    }
    for (final p in ports) {
      if (p.label.startsWith('Active Serial Port')) {
        return p;
      }
    }
    return ports.firstOrNull;
  }

  /// Formats a two-column key/value row to exact `cols` width (e.g. `TOTAL:       K145.00`)
  String _formatKeyValueLine(String left, String right, int cols) {
    final cleanLeft = left.trim();
    final cleanRight = right.trim();
    if (cleanRight.length >= cols) {
      return cleanRight.substring(0, cols);
    }
    final maxLeftLen = cols - cleanRight.length - 1;
    final truncatedLeft = cleanLeft.length > maxLeftLen
        ? cleanLeft.substring(0, maxLeftLen > 0 ? maxLeftLen : 0)
        : cleanLeft;
    final spaces = cols - truncatedLeft.length - cleanRight.length;
    return '$truncatedLeft${' ' * (spaces > 0 ? spaces : 1)}$cleanRight';
  }

  String _padOrTrim(String text, int cols) {
    final clean = text.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    if (clean.length > cols) {
      return clean.substring(0, cols);
    }
    return clean.padRight(cols, ' ');
  }

  String _centerText(String text, int cols) {
    final clean = text.replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    if (clean.length >= cols) {
      return clean.substring(0, cols);
    }
    final leftPad = ((cols - clean.length) / 2).floor();
    return clean.padLeft(clean.length + leftPad, ' ').padRight(cols, ' ');
  }

  void _emitFrame({
    required String line1,
    required String line2,
    required String mode,
    double totalPayable = 0.0,
    double amountTendered = 0.0,
    double changeDue = 0.0,
    String? lastItemName,
    int? lastItemQty,
    double? lastItemPrice,
  }) {
    _currentFrame = PoleDisplayFrame(
      line1: line1,
      line2: line2,
      mode: mode,
      totalPayable: totalPayable,
      amountTendered: amountTendered,
      changeDue: changeDue,
      lastItemName: lastItemName,
      lastItemQty: lastItemQty,
      lastItemPrice: lastItemPrice,
      isHardwareConnected: _isHardwareConnected,
    );
    if (!_frameController.isClosed) {
      _frameController.add(_currentFrame);
    }
  }

  /// 1. IDLE / WELCOME STATE
  Future<void> showIdle() async {
    _resetToIdleTimer?.cancel();
    final cols = _config.columns;
    final line1 = _centerText(_config.welcomeLine1, cols);
    final line2 = _centerText(_config.welcomeLine2, cols);

    _emitFrame(line1: line1, line2: line2, mode: 'IDLE');
    if (_config.enabled) {
      await _writeToHardware(line1, line2, ledMode: 0, numericValue: 0.0);
    }
  }

  /// 2. ITEM ADDED / CART UPDATED STATE
  /// Shows the scanned/selected item details on Line 1 and Total Amount Payable on Line 2
  Future<void> showItemAndTotal({
    required String itemName,
    required double itemUnitPrice,
    int quantity = 1,
    required double totalPayable,
    String? currency,
  }) async {
    _resetToIdleTimer?.cancel();
    final cur = currency ?? currencySymbol;
    final cols = _config.columns;

    final itemTotal = itemUnitPrice * quantity;
    final priceStr = '$cur${itemTotal.toStringAsFixed(2)}';
    final qtyPrefix = quantity > 1 ? '${quantity}x ' : '';
    final line1 = _formatKeyValueLine('$qtyPrefix$itemName', priceStr, cols);
    final line2 = _formatKeyValueLine(
      'TOTAL DUE:',
      '$cur${totalPayable.toStringAsFixed(2)}',
      cols,
    );

    _emitFrame(
      line1: line1,
      line2: line2,
      mode: 'ITEM',
      totalPayable: totalPayable,
      lastItemName: itemName,
      lastItemQty: quantity,
      lastItemPrice: itemUnitPrice,
    );

    if (_config.enabled) {
      await _writeToHardware(
        line1,
        line2,
        ledMode: 2, // 2 = Total / Price
        numericValue: totalPayable,
      );
    }
  }

  /// Updates running total when cart quantities or discounts change
  Future<void> showTotalPayable({
    required double totalPayable,
    int itemCount = 0,
    String? currency,
  }) async {
    _resetToIdleTimer?.cancel();
    if (totalPayable <= 0 && itemCount == 0) {
      await showIdle();
      return;
    }
    final cur = currency ?? currencySymbol;
    final cols = _config.columns;
    final line1 = _formatKeyValueLine(
      'ITEMS IN CART:',
      '$itemCount',
      cols,
    );
    final line2 = _formatKeyValueLine(
      'TOTAL DUE:',
      '$cur${totalPayable.toStringAsFixed(2)}',
      cols,
    );

    _emitFrame(
      line1: line1,
      line2: line2,
      mode: 'ITEM',
      totalPayable: totalPayable,
    );

    if (_config.enabled) {
      await _writeToHardware(
        line1,
        line2,
        ledMode: 2,
        numericValue: totalPayable,
      );
    }
  }

  /// 3. TENDERED & CHANGE STATE (Live as Cashier keys in amount tendered)
  Future<void> showTenderAndChange({
    required double totalPayable,
    required double amountTendered,
    String? currency,
  }) async {
    _resetToIdleTimer?.cancel();
    final cur = currency ?? currencySymbol;
    final cols = _config.columns;
    final change = amountTendered >= totalPayable
        ? (amountTendered - totalPayable)
        : 0.0;
    final balanceDue = totalPayable > amountTendered
        ? (totalPayable - amountTendered)
        : 0.0;

    final String line1;
    final String line2;
    if (amountTendered <= 0) {
      line1 = _formatKeyValueLine(
        'AMOUNT DUE:',
        '$cur${totalPayable.toStringAsFixed(2)}',
        cols,
      );
      line2 = _formatKeyValueLine('TENDERED:', '${cur}0.00', cols);
    } else if (balanceDue > 0.009) {
      line1 = _formatKeyValueLine(
        'TENDERED:',
        '$cur${amountTendered.toStringAsFixed(2)}',
        cols,
      );
      line2 = _formatKeyValueLine(
        'BALANCE DUE:',
        '$cur${balanceDue.toStringAsFixed(2)}',
        cols,
      );
    } else {
      line1 = _formatKeyValueLine(
        'TENDERED:',
        '$cur${amountTendered.toStringAsFixed(2)}',
        cols,
      );
      line2 = _formatKeyValueLine(
        'CHANGE DUE:',
        '$cur${change.toStringAsFixed(2)}',
        cols,
      );
    }

    _emitFrame(
      line1: line1,
      line2: line2,
      mode: 'TENDER',
      totalPayable: totalPayable,
      amountTendered: amountTendered,
      changeDue: change,
    );

    if (_config.enabled) {
      await _writeToHardware(
        line1,
        line2,
        ledMode: change > 0 ? 4 : 3, // 3 = Collect/Tender, 4 = Change
        numericValue: change > 0 ? change : totalPayable,
      );
    }
  }

  /// 4. TRANSACTION COMPLETED STATE (Shows Change & Thank You, then resets to Welcome)
  Future<void> showTransactionComplete({
    required double totalPayable,
    required double amountTendered,
    required double changeDue,
    String? currency,
  }) async {
    _resetToIdleTimer?.cancel();
    final cur = currency ?? currencySymbol;
    final cols = _config.columns;

    final line1 = _formatKeyValueLine(
      'PAID: $cur${amountTendered.toStringAsFixed(2)}',
      _config.thankYouLine1,
      cols,
    );
    final line2 = _formatKeyValueLine(
      'CHANGE:',
      '$cur${changeDue.toStringAsFixed(2)}',
      cols,
    );

    _emitFrame(
      line1: line1,
      line2: line2,
      mode: 'COMPLETE',
      totalPayable: totalPayable,
      amountTendered: amountTendered,
      changeDue: changeDue,
    );

    if (_config.enabled) {
      await _writeToHardware(
        line1,
        line2,
        ledMode: 4, // 4 = Change LED
        numericValue: changeDue,
      );
    }

    // Automatically return to Welcome screen after 8 seconds
    _resetToIdleTimer = Timer(const Duration(seconds: 8), () {
      showIdle();
    });
  }

  /// Clear physical and virtual pole display
  Future<void> clearDisplay() async {
    _resetToIdleTimer?.cancel();
    final cols = _config.columns;
    final empty = ' ' * cols;
    _emitFrame(line1: empty, line2: empty, mode: 'IDLE');
    if (_config.enabled) {
      await _sendBytesToPort(
        const <int>[0x0C],
        port: _config.port,
        baudRate: _config.baudRate,
      );
    }
  }

  /// Tests communication with the configured port and updates live preview
  Future<PoleDisplayTestResult> testDisplayConnection({
    required PoleDisplayConfig testConfig,
    required String line1,
    required String line2,
    double numericValue = 145.00,
    int ledMode = 2,
  }) async {
    final cols = testConfig.columns;
    final formatted1 = _padOrTrim(line1, cols);
    final formatted2 = _padOrTrim(line2, cols);

    _emitFrame(
      line1: formatted1,
      line2: formatted2,
      mode: 'TENDER',
      totalPayable: numericValue,
    );

    final cleanPort = testConfig.port.trim();
    if (cleanPort.isEmpty) {
      return const PoleDisplayTestResult(
        success: false,
        message: 'Port is empty. Preview updated in software display only.',
      );
    }

    final payload = _buildProtocolPayload(
      formatted1,
      formatted2,
      protocol: testConfig.protocol,
      columns: cols,
      ledMode: ledMode,
      numericValue: numericValue,
    );

    final sent = await _sendBytesToPort(
      payload,
      port: cleanPort,
      baudRate: testConfig.baudRate,
    );

    if (sent) {
      _isHardwareConnected = true;
      return PoleDisplayTestResult(
        success: true,
        message:
            'Sent 2×$cols frame to $cleanPort @ ${testConfig.baudRate} baud (${testConfig.protocol.toUpperCase()}).',
      );
    } else {
      _isHardwareConnected = false;
      return PoleDisplayTestResult(
        success: false,
        message:
            'Software preview updated. Physical port "$cleanPort" was not reachable (check USB/COM cable or port number).',
      );
    }
  }

  /// Encodes Line 1 and Line 2 into the selected Pole Display hardware protocol
  List<int> _buildProtocolPayload(
    String line1,
    String line2, {
    required String protocol,
    required int columns,
    int ledMode = 2,
    double numericValue = 0.0,
  }) {
    final l1 = _padOrTrim(line1, columns);
    final l2 = _padOrTrim(line2, columns);
    final bytes = <int>[];

    switch (protocol) {
      case 'led8':
        // Standard 8-Digit LED Customer Display (ESC Q A <digits> CR + ESC s <mode>)
        // Mode: '1' = Unit Price, '2' = Total, '3' = Collect/Tender, '4' = Change
        bytes.addAll([0x0C]); // Clear
        bytes.addAll([0x1B, 0x73, (0x30 + ledMode.clamp(0, 4))]); // ESC s n
        final numStr = numericValue.toStringAsFixed(2);
        bytes.addAll([0x1B, 0x51, 0x41]); // ESC Q A
        bytes.addAll(ascii.encode(numStr));
        bytes.add(0x0D); // CR
        break;

      case 'cd5220':
        // Partner Tech CD-5220 / Posiflex standard
        bytes.addAll([0x1B, 0x40]); // Initialize
        bytes.add(0x0C); // Clear display
        bytes.addAll([0x1B, 0x51, 0x41]); // ESC Q A (Upper line)
        bytes.addAll(ascii.encode(l1));
        bytes.add(0x0D);
        bytes.addAll([0x1B, 0x51, 0x42]); // ESC Q B (Lower line)
        bytes.addAll(ascii.encode(l2));
        bytes.add(0x0D);
        break;

      case 'logic_controls':
        // Logic Controls / Bematech LD9000 / PD3000
        bytes.add(0x1F); // Clear display
        bytes.addAll([0x10, 0x00]); // Cursor to start of Line 1
        bytes.addAll(ascii.encode(l1));
        bytes.addAll([0x10, columns]); // Cursor to start of Line 2
        bytes.addAll(ascii.encode(l2));
        break;

      case 'aedex':
        // AEDEX / Emax frame protocol: !#1<20 chars>\r !#2<20 chars>\r
        bytes.addAll(ascii.encode('!#1$l1\r!#2$l2\r'));
        break;

      case 'raw_ascii':
        bytes.addAll(ascii.encode('$l1\r\n$l2\r\n'));
        break;

      case 'esc_pos':
      default:
        // EPSON ESC/POS Standard VFD (DM-D110 / DM-D210 / Generic USB-Serial VFD)
        bytes.addAll([0x1B, 0x40]); // ESC @ Initialize
        bytes.add(0x0C); // FF Clear screen and home cursor
        bytes.addAll(ascii.encode(l1));
        bytes.addAll(ascii.encode(l2));
        break;
    }
    return bytes;
  }

  Future<void> _writeToHardware(
    String line1,
    String line2, {
    int ledMode = 2,
    double numericValue = 0.0,
  }) async {
    final payload = _buildProtocolPayload(
      line1,
      line2,
      protocol: _config.protocol,
      columns: _config.columns,
      ledMode: ledMode,
      numericValue: numericValue,
    );
    final ok = await _sendBytesToPort(
      payload,
      port: _config.port,
      baudRate: _config.baudRate,
    );
    _isHardwareConnected = ok;
  }

  Future<bool> _sendBytesToPort(
    List<int> bytes, {
    required String port,
    required int baudRate,
  }) async {
    final cleanPort = port.trim();
    if (cleanPort.isEmpty) {
      return false;
    }

    // 1. TCP / Network Socket Bridge (e.g. 127.0.0.1:9002)
    if (cleanPort.contains(':') ||
        cleanPort.startsWith('127.0.0.1') ||
        cleanPort.startsWith('localhost')) {
      try {
        final parts = cleanPort.split(':');
        final host = parts.first.isEmpty ? '127.0.0.1' : parts.first;
        final portNum = parts.length > 1
            ? (int.tryParse(parts[1]) ?? 9002)
            : 9002;

        _tcpSocket ??= await Socket.connect(
          host,
          portNum,
          timeout: const Duration(seconds: 2),
        );
        _tcpSocket!.add(bytes);
        await _tcpSocket!.flush();
        return true;
      } catch (e) {
        await _closeSocket();
        debugPrint('PoleDisplayService TCP write note: $e');
        return false;
      }
    }

    // 2. Linux / macOS Serial Device (/dev/ttyUSB*, /dev/ttyACM*, /dev/ttyS*)
    if (Platform.isLinux || Platform.isMacOS) {
      final devFile = File(cleanPort);
      if (!devFile.existsSync()) {
        return false;
      }
      try {
        if (Platform.isLinux) {
          try {
            await Process.run('stty', [
              '-F',
              cleanPort,
              '$baudRate',
              'raw',
              '-echo',
              'cs8',
              '-cstopb',
              '-parenb',
            ]);
          } catch (_) {}
        }
        await devFile.writeAsBytes(bytes, mode: FileMode.writeOnlyAppend);
        return true;
      } catch (e) {
        debugPrint('PoleDisplayService Linux serial write note: $e');
        return false;
      }
    }

    // 3. Windows COM Port (COM1..COM16)
    if (Platform.isWindows) {
      try {
        final b64 = base64Encode(bytes);
        final script =
            "\$port = New-Object System.IO.Ports.SerialPort '$cleanPort',$baudRate,'None',8,'One'; "
            "\$port.Open(); "
            "\$bytes = [Convert]::FromBase64String('$b64'); "
            "\$port.Write(\$bytes, 0, \$bytes.Length); "
            "\$port.Close();";
        final res = await Process.run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-WindowStyle',
          'Hidden',
          '-Command',
          script,
        ]).timeout(const Duration(seconds: 3));
        return res.exitCode == 0;
      } catch (e) {
        debugPrint('PoleDisplayService Windows COM write note: $e');
        return false;
      }
    }

    return false;
  }

  Future<void> _closeSocket() async {
    try {
      await _tcpSocket?.close();
    } catch (_) {}
    _tcpSocket = null;
  }

  void dispose() {
    _resetToIdleTimer?.cancel();
    _closeSocket();
    _frameController.close();
  }
}
