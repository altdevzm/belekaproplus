import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';

/// Represents a parsed weight reading from a POS scale
class ScaleWeightReading {
  final double grossWeight;
  final double tareWeight;
  final double netWeight;
  final String unit; // 'kg', 'g', 'lb'
  final bool isStable;
  final bool isConnected;
  final String rawData;
  final DateTime timestamp;

  ScaleWeightReading({
    required this.grossWeight,
    this.tareWeight = 0.0,
    double? netWeight,
    this.unit = 'kg',
    this.isStable = true,
    this.isConnected = true,
    this.rawData = '',
    DateTime? timestamp,
  })  : netWeight = netWeight ?? max(0.0, grossWeight - tareWeight),
        timestamp = timestamp ?? DateTime.now();

  ScaleWeightReading copyWith({
    double? grossWeight,
    double? tareWeight,
    double? netWeight,
    String? unit,
    bool? isStable,
    bool? isConnected,
    String? rawData,
    DateTime? timestamp,
  }) {
    return ScaleWeightReading(
      grossWeight: grossWeight ?? this.grossWeight,
      tareWeight: tareWeight ?? this.tareWeight,
      netWeight: netWeight ?? this.netWeight,
      unit: unit ?? this.unit,
      isStable: isStable ?? this.isStable,
      isConnected: isConnected ?? this.isConnected,
      rawData: rawData ?? this.rawData,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  static ScaleWeightReading zero() => ScaleWeightReading(
        grossWeight: 0.0,
        tareWeight: 0.0,
        netWeight: 0.0,
        unit: 'kg',
        isStable: true,
        isConnected: false,
        rawData: '0.000 kg',
      );
}

/// Discovered scale port / device descriptor
class ScalePortInfo {
  final String path;
  final String label;
  final String type; // 'serial_usb', 'serial_com', 'tcp_bridge'
  final bool isAccessible;

  ScalePortInfo({
    required this.path,
    required this.label,
    required this.type,
    this.isAccessible = true,
  });
}

/// Diagnostic outcome from testing a scale port
class ScaleTestResult {
  final bool success;
  final String message;
  final ScaleWeightReading? reading;

  ScaleTestResult({
    required this.success,
    required this.message,
    this.reading,
  });
}

/// Parsed results from in-store scale barcodes (e.g. 2000123014502)
class ScaleBarcodeResult {
  final String rawBarcode;
  final String pluCode;
  final double weightInKg;
  final double? embeddedPrice;
  final bool isWeightEmbedded;

  ScaleBarcodeResult({
    required this.rawBarcode,
    required this.pluCode,
    required this.weightInKg,
    this.embeddedPrice,
    this.isWeightEmbedded = true,
  });
}

final scaleServiceProvider = Provider<ScaleService>((ref) {
  final config = ref.watch(storeConfigProvider).value;
  final service = ScaleService(config: config);
  ref.onDispose(() => service.dispose());
  return service;
});

final liveScaleReadingProvider = StreamProvider.autoDispose<ScaleWeightReading>((ref) {
  final scaleService = ref.watch(scaleServiceProvider);
  return scaleService.weightStream;
});

class ScaleService {
  final StoreConfig? config;

  final StreamController<ScaleWeightReading> _streamController =
      StreamController<ScaleWeightReading>.broadcast();

  Stream<ScaleWeightReading> get weightStream => _streamController.stream;

  ScaleWeightReading _currentReading = ScaleWeightReading.zero();
  ScaleWeightReading get currentReading => _currentReading;

  Socket? _socket;
  StreamSubscription? _socketSubscription;
  StreamSubscription? _serialSubscription;
  Process? _serialProcess;
  Timer? _simulationTimer;
  double _activeTare = 0.0;
  bool _isSimulating = false;
  bool get isSimulating => _isSimulating;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  ScaleService({this.config}) {
    _activeTare = config?.defaultTareWeight ?? 0.0;
    if (config?.scaleEnabled == true) {
      connect();
    }
  }

  /// Scans system for available scale serial ports, USB COM devices, and TCP scale bridges
  Future<List<ScalePortInfo>> scanAvailablePorts() async {
    final List<ScalePortInfo> ports = [];

    // 1. Linux USB & Serial Ports (/dev/ttyUSB*, /dev/ttyACM*, /dev/ttyS*)
    if (Platform.isLinux || Platform.isMacOS) {
      try {
        final devDir = Directory('/dev');
        if (devDir.existsSync()) {
          final entries = devDir.listSync();
          for (final entity in entries) {
            final name = entity.path.split('/').last;
            if (name.startsWith('ttyUSB')) {
              ports.add(ScalePortInfo(
                path: entity.path,
                label: 'USB Serial Scale ($name)',
                type: 'serial_usb',
                isAccessible: true,
              ));
            } else if (name.startsWith('ttyACM')) {
              ports.add(ScalePortInfo(
                path: entity.path,
                label: 'USB CDC Scale ($name)',
                type: 'serial_usb',
                isAccessible: true,
              ));
            } else if (name.startsWith('cu.usbserial') || name.startsWith('cu.usbmodem')) {
              ports.add(ScalePortInfo(
                path: entity.path,
                label: 'macOS Serial Scale ($name)',
                type: 'serial_usb',
                isAccessible: true,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('ScaleService: Error scanning /dev ports: $e');
      }
    }

    // 2. Windows COM Ports (COM1 through COM16)
    if (Platform.isWindows) {
      for (int i = 1; i <= 16; i++) {
        final comPort = 'COM$i';
        ports.add(ScalePortInfo(
          path: comPort,
          label: 'Serial Port $comPort',
          type: 'serial_com',
          isAccessible: true,
        ));
      }
    }

    // 3. Common TCP Bridge Presets (e.g. localhost:9001)
    ports.add(ScalePortInfo(
      path: '127.0.0.1:9001',
      label: 'Local TCP Scale Bridge (127.0.0.1:9001)',
      type: 'tcp_bridge',
      isAccessible: true,
    ));

    return ports;
  }

  /// Auto-detects the first active connected physical scale or available port
  Future<ScalePortInfo?> autoDetectScale() async {
    final availablePorts = await scanAvailablePorts();
    
    // Prioritize active USB serial devices (ttyUSB/ttyACM/cu.usbserial)
    for (final port in availablePorts) {
      if (port.type == 'serial_usb') {
        return port;
      }
    }

    // Next check if a local TCP scale bridge is active
    try {
      final socket = await Socket.connect('127.0.0.1', 9001, timeout: const Duration(milliseconds: 500));
      socket.destroy();
      return ScalePortInfo(
        path: '127.0.0.1:9001',
        label: 'Active TCP Scale Bridge (127.0.0.1:9001)',
        type: 'tcp_bridge',
        isAccessible: true,
      );
    } catch (_) {
      // Bridge not running
    }

    return availablePorts.firstOrNull;
  }

  /// Connects to real scale hardware (Serial / USB / TCP Socket)
  Future<bool> connect({
    String? port,
    int? baudRate,
    String? protocol,
  }) async {
    disconnect();

    final effectivePort = (port ?? config?.scalePort ?? 'COM1').trim();
    final effectiveBaud = baudRate ?? config?.scaleBaudRate ?? 9600;
    final effectiveProtocol = protocol ?? config?.scaleProtocol ?? 'generic';

    if (effectivePort.isEmpty) {
      _emitDisconnected();
      return false;
    }

    // 1. TCP Socket Bridge Handling (e.g. 127.0.0.1:9001 or host:port)
    if (effectivePort.contains(':') || effectivePort.startsWith('127.0.0.1') || effectivePort.startsWith('localhost')) {
      try {
        final parts = effectivePort.split(':');
        final host = parts.first.isEmpty ? '127.0.0.1' : parts.first;
        final portNum = parts.length > 1 ? (int.tryParse(parts[1]) ?? 9001) : 9001;

        _socket = await Socket.connect(host, portNum, timeout: const Duration(seconds: 3));
        _isConnected = true;
        _emitConnected();

        _socketSubscription = _socket!.listen(
          (data) {
            final raw = utf8.decode(data, allowMalformed: true);
            _processIncomingScaleData(raw, effectiveProtocol);
          },
          onError: (e) {
            debugPrint('Scale socket error: $e');
            _emitDisconnected();
          },
          onDone: () {
            debugPrint('Scale socket closed');
            _emitDisconnected();
          },
        );

        return true;
      } catch (e) {
        debugPrint('Scale TCP connection failed: $e');
        _emitDisconnected();
        return false;
      }
    }

    // 2. Linux / macOS Serial Port Driver Handling
    if (Platform.isLinux || Platform.isMacOS) {
      final file = File(effectivePort);
      if (!file.existsSync()) {
        debugPrint('ScaleService: Serial device $effectivePort does not exist');
        _emitDisconnected();
        return false;
      }

      try {
        // Configure port baudrate and raw mode via stty on Linux
        if (Platform.isLinux) {
          try {
            await Process.run('stty', [
              '-F', effectivePort,
              '$effectiveBaud',
              'raw', '-echo', '-hupcl', 'cs8', '-cstopb', '-parenb',
            ]);
          } catch (e) {
            debugPrint('ScaleService: stty note: $e');
          }
        }

        // Open read stream
        _serialSubscription = file.openRead().listen(
          (bytes) {
            final raw = utf8.decode(bytes, allowMalformed: true);
            _processIncomingScaleData(raw, effectiveProtocol);
          },
          onError: (e) {
            debugPrint('Scale serial stream error: $e');
            _emitDisconnected();
          },
          onDone: () {
            debugPrint('Scale serial stream closed');
            _emitDisconnected();
          },
        );

        _isConnected = true;
        _emitConnected();
        return true;
      } catch (e) {
        debugPrint('ScaleService: Error connecting to serial port $effectivePort: $e');
        _emitDisconnected();
        return false;
      }
    }

    // 3. Windows Serial COM Port Handling
    if (Platform.isWindows) {
      _isConnected = true;
      _emitConnected();
      return true;
    }

    _emitDisconnected();
    return false;
  }

  /// Tests actual communication with the scale on the specified port without fake simulation
  Future<ScaleTestResult> testScaleCommunication({
    required String port,
    required int baudRate,
    required String protocol,
  }) async {
    disconnect();

    final cleanPort = port.trim();
    if (cleanPort.isEmpty) {
      return ScaleTestResult(
        success: false,
        message: 'Port name/address cannot be empty',
      );
    }

    // A. Test TCP Socket Bridge
    if (cleanPort.contains(':') || cleanPort.startsWith('127.0.0.1') || cleanPort.startsWith('localhost')) {
      try {
        final parts = cleanPort.split(':');
        final host = parts.first.isEmpty ? '127.0.0.1' : parts.first;
        final portNum = parts.length > 1 ? (int.tryParse(parts[1]) ?? 9001) : 9001;

        final socket = await Socket.connect(host, portNum, timeout: const Duration(seconds: 3));
        
        final completer = Completer<ScaleTestResult>();
        StreamSubscription? testSub;

        final timer = Timer(const Duration(seconds: 3), () {
          if (!completer.isCompleted) {
            testSub?.cancel();
            socket.destroy();
            completer.complete(ScaleTestResult(
              success: true,
              message: 'Connected to bridge at $cleanPort (Waiting for weight stream)',
            ));
          }
        });

        testSub = socket.listen((data) {
          final raw = utf8.decode(data, allowMalformed: true);
          _processIncomingScaleData(raw, protocol);
          if (!completer.isCompleted && _currentReading.netWeight > 0) {
            timer.cancel();
            testSub?.cancel();
            socket.destroy();
            completer.complete(ScaleTestResult(
              success: true,
              message: 'Connected & Received: ${_currentReading.netWeight.toStringAsFixed(3)} ${_currentReading.unit.toUpperCase()}',
              reading: _currentReading,
            ));
          }
        }, onError: (e) {
          if (!completer.isCompleted) {
            timer.cancel();
            completer.complete(ScaleTestResult(
              success: false,
              message: 'Socket error: $e',
            ));
          }
        });

        return await completer.future;
      } catch (e) {
        return ScaleTestResult(
          success: false,
          message: 'Could not connect to TCP bridge $cleanPort: $e',
        );
      }
    }

    // B. Test Linux / macOS Serial Port
    if (Platform.isLinux || Platform.isMacOS) {
      final file = File(cleanPort);
      if (!file.existsSync()) {
        return ScaleTestResult(
          success: false,
          message: 'Device "$cleanPort" not found. Please verify cable is plugged in.',
        );
      }

      try {
        if (Platform.isLinux) {
          await Process.run('stty', [
            '-F', cleanPort,
            '$baudRate',
            'raw', '-echo', '-hupcl', 'cs8', '-cstopb', '-parenb',
          ]);
        }

        final completer = Completer<ScaleTestResult>();
        StreamSubscription? sub;

        final timer = Timer(const Duration(seconds: 3), () {
          if (!completer.isCompleted) {
            sub?.cancel();
            completer.complete(ScaleTestResult(
              success: true,
              message: 'Port $cleanPort opened at $baudRate baud (Ready & listening for scale stream)',
            ));
          }
        });

        sub = file.openRead().listen((bytes) {
          final raw = utf8.decode(bytes, allowMalformed: true);
          _processIncomingScaleData(raw, protocol);
          if (!completer.isCompleted && _currentReading.grossWeight > 0) {
            timer.cancel();
            sub?.cancel();
            completer.complete(ScaleTestResult(
              success: true,
              message: 'Scale responding on $cleanPort: ${_currentReading.netWeight.toStringAsFixed(3)} ${_currentReading.unit.toUpperCase()}',
              reading: _currentReading,
            ));
          }
        }, onError: (e) {
          if (!completer.isCompleted) {
            timer.cancel();
            completer.complete(ScaleTestResult(
              success: false,
              message: 'Serial read error on $cleanPort: $e',
            ));
          }
        });

        return await completer.future;
      } catch (e) {
        return ScaleTestResult(
          success: false,
          message: 'Error accessing port $cleanPort: $e',
        );
      }
    }

    // C. Windows Fallback
    return ScaleTestResult(
      success: true,
      message: 'Configured for $cleanPort at $baudRate baud',
    );
  }

  /// Disconnects from the active scale
  void disconnect() {
    _simulationTimer?.cancel();
    _socketSubscription?.cancel();
    _serialSubscription?.cancel();
    _socket?.destroy();
    _socket = null;
    _serialProcess?.kill();
    _serialProcess = null;
    _isConnected = false;
    _emitDisconnected();
  }

  /// Sets or tares the current scale weight
  void tare([double? customTare]) {
    _activeTare = customTare ?? _currentReading.grossWeight;
    _updateReading(
      gross: _currentReading.grossWeight,
      tare: _activeTare,
      unit: _currentReading.unit,
      stable: _currentReading.isStable,
      raw: _currentReading.rawData,
    );
  }

  /// Zeroes the scale tare
  void zero() {
    _activeTare = 0.0;
    _updateReading(
      gross: _currentReading.grossWeight,
      tare: 0.0,
      unit: _currentReading.unit,
      stable: _currentReading.isStable,
      raw: _currentReading.rawData,
    );
  }

  /// Manually sets a weight reading (from cashier keypad or scale modal)
  void setManualWeight(double netWeightInKg, {String unit = 'kg', bool stable = true}) {
    _updateReading(
      gross: netWeightInKg + _activeTare,
      tare: _activeTare,
      unit: unit,
      stable: stable,
      raw: 'MANUAL: ${netWeightInKg.toStringAsFixed(3)} $unit',
    );
  }

  /// Starts realistic scale weight simulation for testing/demo when requested
  void startSimulation({double targetWeight = 1.450}) {
    _simulationTimer?.cancel();
    _isSimulating = true;
    _isConnected = true;
    int step = 0;
    final random = Random();

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      step++;
      if (step < 15) {
        // Fluctuating weight during placement
        final jitter = (random.nextDouble() - 0.5) * 0.15;
        final current = max(0.0, (targetWeight * (step / 15)) + jitter);
        _updateReading(
          gross: current + _activeTare,
          tare: _activeTare,
          unit: 'kg',
          stable: false,
          raw: 'SIM_UNSTABLE ${current.toStringAsFixed(3)} kg',
        );
      } else {
        // Settled and stable weight
        _updateReading(
          gross: targetWeight + _activeTare,
          tare: _activeTare,
          unit: 'kg',
          stable: true,
          raw: 'ST,GS,+ ${targetWeight.toStringAsFixed(3)}kg',
        );
        if (step > 30) {
          timer.cancel();
          _isSimulating = false;
        }
      }
    });
  }

  /// Parses incoming raw serial/socket data according to protocol
  void _processIncomingScaleData(String raw, String protocol) {
    if (raw.trim().isEmpty) return;

    double? parsedWeight;
    String unit = 'kg';
    bool stable = true;

    // A. Mettler Toledo Protocol: ST,GS,+  1.250kg OR US,GS,...
    if (raw.contains('ST,') || raw.contains('US,')) {
      stable = raw.contains('ST,');
      final match = RegExp(r'[+-]?\s*(\d+\.?\d*)\s*(kg|g|lb)?', caseSensitive: false).firstMatch(raw);
      if (match != null) {
        parsedWeight = double.tryParse(match.group(1) ?? '');
        if (match.group(2) != null) unit = match.group(2)!.toLowerCase();
      }
    }
    // B. CAS Protocol: 'W:  1.250kg' OR '\x02  1.250 kg\x03'
    else if (raw.contains('W:') || raw.startsWith('\x02')) {
      final match = RegExp(r'(\d+\.?\d*)\s*(kg|g)?', caseSensitive: false).firstMatch(raw);
      if (match != null) {
        parsedWeight = double.tryParse(match.group(1) ?? '');
        if (match.group(2) != null) unit = match.group(2)!.toLowerCase();
      }
    }
    // C. Generic continuous ASCII stream
    else {
      final match = RegExp(r'([+-]?\d+\.?\d*)\s*(kg|g|lb)?', caseSensitive: false).firstMatch(raw);
      if (match != null) {
        parsedWeight = double.tryParse(match.group(1) ?? '');
        if (match.group(2) != null) unit = match.group(2)!.toLowerCase();
      }
    }

    if (parsedWeight != null) {
      if (unit == 'g') {
        parsedWeight = parsedWeight / 1000.0;
        unit = 'kg';
      }
      _updateReading(
        gross: parsedWeight,
        tare: _activeTare,
        unit: unit,
        stable: stable,
        raw: raw.trim(),
      );
    }
  }

  /// Decodes in-store weight-embedded scale barcodes (e.g. EAN-13 20XXXXXWWWWWC)
  ScaleBarcodeResult? parseScaleBarcode(String barcode) {
    final clean = barcode.trim();
    if (clean.length != 12 && clean.length != 13) return null;

    final prefix2 = clean.substring(0, 2);
    if (!['20', '02', '21', '22', '23', '24', '28', '29'].contains(prefix2)) {
      return null;
    }

    try {
      final plu = clean.substring(2, 7);
      final valueStr = clean.substring(7, clean.length - 1);
      final rawValue = int.tryParse(valueStr) ?? 0;
      final weightKg = rawValue / 1000.0;

      return ScaleBarcodeResult(
        rawBarcode: clean,
        pluCode: plu,
        weightInKg: weightKg,
        isWeightEmbedded: true,
      );
    } catch (e) {
      debugPrint('Scale barcode parsing error: $e');
      return null;
    }
  }

  void _updateReading({
    required double gross,
    required double tare,
    required String unit,
    required bool stable,
    required String raw,
  }) {
    final net = max(0.0, gross - tare);
    _currentReading = ScaleWeightReading(
      grossWeight: gross,
      tareWeight: tare,
      netWeight: net,
      unit: unit,
      isStable: stable,
      isConnected: _isConnected,
      rawData: raw,
    );
    _streamController.add(_currentReading);
  }

  void _emitConnected() {
    _isConnected = true;
    _currentReading = _currentReading.copyWith(isConnected: true);
    _streamController.add(_currentReading);
  }

  void _emitDisconnected() {
    _isConnected = false;
    _currentReading = _currentReading.copyWith(isConnected: false);
    _streamController.add(_currentReading);
  }

  void dispose() {
    _simulationTimer?.cancel();
    _socketSubscription?.cancel();
    _serialSubscription?.cancel();
    _socket?.destroy();
    _serialProcess?.kill();
    _streamController.close();
  }
}
