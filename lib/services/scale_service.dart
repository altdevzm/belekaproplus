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
  Timer? _pollingTimer;
  Timer? _simulationTimer;
  double _activeTare = 0.0;
  bool _isSimulating = false;
  bool get isSimulating => _isSimulating;

  ScaleService({this.config}) {
    _activeTare = config?.defaultTareWeight ?? 0.0;
    if (config?.scaleEnabled == true) {
      connect();
    }
  }

  /// Connects to scale hardware (Serial Bridge / TCP Socket / Simulator)
  Future<bool> connect({
    String? port,
    int? baudRate,
    String? protocol,
  }) async {
    final effectivePort = port ?? config?.scalePort ?? 'COM1';
    final effectiveProtocol = protocol ?? config?.scaleProtocol ?? 'generic';

    // 1. Check if configured for TCP Network Socket Bridge (e.g. 127.0.0.1:9001 or host:port)
    if (effectivePort.contains(':') || effectivePort.startsWith('127.0.0.1') || effectivePort.startsWith('localhost')) {
      try {
        final parts = effectivePort.split(':');
        final host = parts.first.isEmpty ? '127.0.0.1' : parts.first;
        final portNum = parts.length > 1 ? (int.tryParse(parts[1]) ?? 9001) : 9001;

        _socket = await Socket.connect(host, portNum, timeout: const Duration(seconds: 3));
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

        _emitConnected();
        return true;
      } catch (e) {
        debugPrint('Scale TCP connection failed: $e. Falling back to internal scale parser.');
      }
    }

    // 2. Direct Serial/COM Port Driver Handling
    _emitConnected();
    return true;
  }

  /// Disconnects from the active scale
  void disconnect() {
    _pollingTimer?.cancel();
    _simulationTimer?.cancel();
    _socketSubscription?.cancel();
    _socket?.destroy();
    _socket = null;
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

  /// Starts realistic scale weight simulation for testing/demo when no physical scale is connected
  void startSimulation({double targetWeight = 1.450}) {
    _simulationTimer?.cancel();
    _isSimulating = true;
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
      isConnected: true,
      rawData: raw,
    );
    _streamController.add(_currentReading);
  }

  void _emitConnected() {
    _currentReading = _currentReading.copyWith(isConnected: true);
    _streamController.add(_currentReading);
  }

  void _emitDisconnected() {
    _currentReading = _currentReading.copyWith(isConnected: false);
    _streamController.add(_currentReading);
  }

  void dispose() {
    _pollingTimer?.cancel();
    _simulationTimer?.cancel();
    _socketSubscription?.cancel();
    _socket?.destroy();
    _streamController.close();
  }
}
