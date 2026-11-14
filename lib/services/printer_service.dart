import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils.dart';
import 'package:flutter_star_prnt/flutter_star_prnt.dart' as star;
import 'package:beleka_pos/models/models.dart';
import 'package:intl/intl.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'package:printing/printing.dart' as pnt;
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:beleka_pos/utils/formatters.dart';

enum PrinterModel { generic, star, system, directSocket }

final printerServiceProvider = Provider((ref) => PrinterService());

/// Hardware presets for all standard and specialized thermal paper roll widths
class ThermalPaperPreset {
  final int widthMm;
  final String label;
  final String description;
  final int columnCount;
  final int logoPixelWidth;
  final PaperSize escPosSize;
  final QRSize qrSize;

  const ThermalPaperPreset({
    required this.widthMm,
    required this.label,
    required this.description,
    required this.columnCount,
    required this.logoPixelWidth,
    required this.escPosSize,
    required this.qrSize,
  });

  String get singleDivider => '-' * columnCount;
  String get doubleDivider => '=' * columnCount;

  static const List<ThermalPaperPreset> presets = [
    ThermalPaperPreset(
      widthMm: 55,
      label: '55 mm',
      description: 'Compact mini POS, handheld & mobile thermal rolls',
      columnCount: 28,
      logoPixelWidth: 180,
      escPosSize: PaperSize.mm58,
      qrSize: QRSize.Size3,
    ),
    ThermalPaperPreset(
      widthMm: 58,
      label: '58 mm',
      description: 'Small POS, kiosks, mobile/small receipts',
      columnCount: 30,
      logoPixelWidth: 200,
      escPosSize: PaperSize.mm58,
      qrSize: QRSize.Size3,
    ),
    ThermalPaperPreset(
      widthMm: 76,
      label: '76 mm',
      description: 'Medium business POS thermal rolls',
      columnCount: 38,
      logoPixelWidth: 260,
      escPosSize: PaperSize.mm80,
      qrSize: QRSize.Size3,
    ),
    ThermalPaperPreset(
      widthMm: 80,
      label: '80 mm',
      description: 'Standard retail POS, supermarkets, restaurants',
      columnCount: 42,
      logoPixelWidth: 300,
      escPosSize: PaperSize.mm80,
      qrSize: QRSize.Size4,
    ),
    ThermalPaperPreset(
      widthMm: 110,
      label: '110 mm',
      description: 'Wide thermal printing',
      columnCount: 56,
      logoPixelWidth: 400,
      escPosSize: PaperSize.mm80,
      qrSize: QRSize.Size4,
    ),
    ThermalPaperPreset(
      widthMm: 112,
      label: '112 mm',
      description: 'Extra-wide receipts/labels, specialized POS',
      columnCount: 60,
      logoPixelWidth: 420,
      escPosSize: PaperSize.mm80,
      qrSize: QRSize.Size4,
    ),
  ];

  static ThermalPaperPreset fromWidth(int mm) {
    if (mm <= 55) {
      return presets[0]; // 55mm
    }
    if (mm <= 58) {
      return presets[1]; // 58mm
    }
    if (mm <= 76) {
      return presets[2]; // 76mm
    }
    return presets.firstWhere(
      (p) => p.widthMm == mm,
      orElse: () => presets[3], // 80mm default
    );
  }
}

class PrinterConfig {
  final PrinterDevice device;
  final PrinterType type;
  final PrinterModel model;
  final star.StarEmulation? starEmulation;
  final int paperWidthMm;

  PrinterConfig({
    required this.device, 
    required this.type, 
    this.model = PrinterModel.generic,
    this.starEmulation,
    this.paperWidthMm = 80,
  });
}

final selectedPrinterProvider = StateProvider<PrinterConfig?>((ref) => null);

class PrinterService {
  final PrinterManager _printerManager = PrinterManager.instance;
  bool _isConnected = false;
  PrinterDevice? _activeDevice;
  PrinterType? _activeType;
  PrinterModel _activeModel = PrinterModel.generic;
  star.StarEmulation _starEmulation = star.StarEmulation.StarPRNT;
  pnt.Printer? _activeSystemPrinter;
  int _paperWidthMm = 80;

  bool get isConnected => _isConnected;
  PrinterDevice? get activeDevice => _activeDevice;
  PrinterType? get activeType => _activeType;
  PrinterModel get activeModel => _activeModel;
  pnt.Printer? get activeSystemPrinter => _activeSystemPrinter;
  int get paperWidthMm => _paperWidthMm;

  ThermalPaperPreset get activePreset => ThermalPaperPreset.fromWidth(_paperWidthMm);

  void setPaperWidth(int width) {
    _paperWidthMm = width;
  }

  /// Auto-connects to saved or discovered hardware printer on application startup
  Future<bool> autoConnect({StoreConfig? config, StateController<PrinterConfig?>? stateNotifier}) async {
    debugPrint('PrinterService: Initiating automatic driver discovery & hardware loading...');

    _paperWidthMm = config?.paperWidthMm ?? 80;

    // 1. Try saved printer from StoreConfig if available
    if (config?.defaultPrinterAddress != null && config!.defaultPrinterAddress!.isNotEmpty) {
      final savedType = _parsePrinterType(config.defaultPrinterType);
      final savedModel = _parsePrinterModel(config.defaultPrinterModel);

      final device = PrinterDevice(
        name: config.defaultPrinterName ?? 'Default POS Printer',
        address: config.defaultPrinterAddress,
      );

      final ok = await connect(device, savedType, model: savedModel);
      if (ok) {
        debugPrint('PrinterService: Auto-connected to saved printer: ${device.name} (${device.address})');
        stateNotifier?.state = PrinterConfig(
          device: device,
          type: savedType,
          model: savedModel,
          paperWidthMm: _paperWidthMm,
        );
        return true;
      }
    }

    // 2. Probe for USB Thermal Printers
    try {
      final usbDevices = await scanPrinters(PrinterType.usb, model: PrinterModel.generic);
      if (usbDevices.isNotEmpty) {
        final usbPrinter = usbDevices.first;
        final ok = await connect(usbPrinter, PrinterType.usb, model: PrinterModel.generic);
        if (ok) {
          debugPrint('PrinterService: Auto-detected & connected USB printer: ${usbPrinter.name}');
          stateNotifier?.state = PrinterConfig(
            device: usbPrinter,
            type: PrinterType.usb,
            model: PrinterModel.generic,
            paperWidthMm: _paperWidthMm,
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint('PrinterService: USB auto-probe skipped: $e');
    }

    // 3. Probe for Linux Raw USB Device (/dev/usb/lp0)
    if (Platform.isLinux && File('/dev/usb/lp0').existsSync()) {
      final rawDevice = PrinterDevice(name: 'Linux Direct USB (lp0)', address: '/dev/usb/lp0');
      _activeDevice = rawDevice;
      _activeType = PrinterType.usb;
      _activeModel = PrinterModel.generic;
      _isConnected = true;
      stateNotifier?.state = PrinterConfig(
        device: rawDevice,
        type: PrinterType.usb,
        model: PrinterModel.generic,
        paperWidthMm: _paperWidthMm,
      );
      debugPrint('PrinterService: Attached to Linux Direct USB /dev/usb/lp0');
      return true;
    }

    // 4. Probe for Bluetooth Printers
    try {
      final btDevices = await scanPrinters(PrinterType.bluetooth, model: PrinterModel.generic);
      if (btDevices.isNotEmpty) {
        final btPrinter = btDevices.first;
        final ok = await connect(btPrinter, PrinterType.bluetooth, model: PrinterModel.generic);
        if (ok) {
          debugPrint('PrinterService: Auto-connected to Bluetooth printer: ${btPrinter.name}');
          stateNotifier?.state = PrinterConfig(
            device: btPrinter,
            type: PrinterType.bluetooth,
            model: PrinterModel.generic,
            paperWidthMm: _paperWidthMm,
          );
          return true;
        }
      }
    } catch (e) {
      debugPrint('PrinterService: Bluetooth auto-probe skipped: $e');
    }

    // 5. Fallback to Default System CUPS / OS Printer
    try {
      final sysPrinters = await pnt.Printing.listPrinters();
      if (sysPrinters.isNotEmpty) {
        final defSys = sysPrinters.firstWhere((p) => p.isDefault, orElse: () => sysPrinters.first);
        final sysDevice = PrinterDevice(name: defSys.name, address: defSys.url);
        _activeSystemPrinter = defSys;
        _activeDevice = sysDevice;
        _activeType = PrinterType.usb;
        _activeModel = PrinterModel.system;
        _isConnected = true;
        stateNotifier?.state = PrinterConfig(
          device: sysDevice,
          type: PrinterType.usb,
          model: PrinterModel.system,
          paperWidthMm: _paperWidthMm,
        );
        debugPrint('PrinterService: Ready with System Printer: ${defSys.name}');
        return true;
      }
    } catch (e) {
      debugPrint('PrinterService: System printer probe note: $e');
    }

    return false;
  }

  Future<List<PrinterDevice>> scanPrinters(PrinterType type, {PrinterModel model = PrinterModel.generic}) async {
    if (model == PrinterModel.system) {
      try {
        final systemPrinters = await pnt.Printing.listPrinters();
        return systemPrinters.map((p) => PrinterDevice(
          name: p.name,
          address: p.url,
          productId: p.model,
        )).toList();
      } catch (e) {
        debugPrint('System printer list error: $e');
        return [];
      }
    }

    if (model == PrinterModel.star) {
      star.StarPortType portType;
      switch (type) {
        case PrinterType.usb:
          portType = star.StarPortType.USB;
          break;
        case PrinterType.network:
          portType = star.StarPortType.LAN;
          break;
        case PrinterType.bluetooth:
          portType = star.StarPortType.Bluetooth;
          break;
      }
      
      try {
        final ports = await star.StarPrnt.portDiscovery(portType);
        return ports.map((p) => PrinterDevice(
          name: p.modelName ?? 'Star Printer',
          address: p.portName,
          productId: p.macAddress,
        )).toList();
      } catch (e) {
        debugPrint('Star discovery error: $e');
        return [];
      }
    }

    List<PrinterDevice> devices = [];
    try {
      final sub = _printerManager.discovery(type: type).listen((device) {
        if (!devices.any((d) => d.address == device.address && d.name == device.name)) {
          devices.add(device);
        }
      });
      await Future.delayed(const Duration(seconds: 2));
      await sub.cancel();
    } catch (e) {
      debugPrint('PrinterManager discovery error: $e');
    }

    // Direct Linux raw ports check
    if (Platform.isLinux && type == PrinterType.usb) {
      for (final port in ['/dev/usb/lp0', '/dev/usb/lp1', '/dev/usb/lp2']) {
        if (File(port).existsSync() && !devices.any((d) => d.address == port)) {
          devices.add(PrinterDevice(name: 'Direct POS USB (${port.split('/').last})', address: port));
        }
      }
    }

    return devices;
  }

  Future<bool> connect(
    PrinterDevice device, 
    PrinterType type, {
    PrinterModel model = PrinterModel.generic, 
    star.StarEmulation? starEmulation,
    int paperWidth = 80,
  }) async {
    _paperWidthMm = paperWidth;

    if (model == PrinterModel.star) {
      _activeDevice = device;
      _activeType = type;
      _activeModel = model;
      _starEmulation = starEmulation ?? star.StarEmulation.StarPRNT;
      _isConnected = true;
      return true;
    }

    if (model == PrinterModel.system) {
      try {
        final systemPrinters = await pnt.Printing.listPrinters();
        final p = systemPrinters.firstWhere(
          (p) => p.url == device.address || p.name == device.name,
          orElse: () => systemPrinters.isNotEmpty ? systemPrinters.first : throw Exception('No system printer'),
        );
        _activeSystemPrinter = p;
        _activeDevice = device;
        _activeType = type;
        _activeModel = model;
        _isConnected = true;
        return true;
      } catch (e) {
        debugPrint('System printer connect error: $e');
        return false;
      }
    }

    if (model == PrinterModel.directSocket || (type == PrinterType.network && device.address != null)) {
      try {
        final host = device.address!.contains(':') ? device.address!.split(':').first : device.address!;
        final port = device.address!.contains(':') ? int.tryParse(device.address!.split(':').last) ?? 9100 : 9100;
        final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
        await socket.close();
        _activeDevice = device;
        _activeType = type;
        _activeModel = PrinterModel.directSocket;
        _isConnected = true;
        return true;
      } catch (e) {
        debugPrint('Direct socket test failed, falling back to manager: $e');
      }
    }

    // Direct Linux raw device
    if (Platform.isLinux && device.address != null && device.address!.startsWith('/dev/usb/lp')) {
      if (File(device.address!).existsSync()) {
        _activeDevice = device;
        _activeType = type;
        _activeModel = PrinterModel.generic;
        _isConnected = true;
        return true;
      }
    }

    try {
      bool success = false;
      if (type == PrinterType.usb) {
        success = await _printerManager.connect(
          type: type,
          model: UsbPrinterInput(
            name: device.name,
            productId: device.productId,
            vendorId: device.vendorId,
          ),
        );
      } else if (type == PrinterType.network) {
        success = await _printerManager.connect(
          type: type,
          model: TcpPrinterInput(ipAddress: device.address!),
        );
      } else if (type == PrinterType.bluetooth) {
        // Dual-mode Bluetooth: Try Bluetooth Classic SPP first (used by 95% of ESC/POS mini printers), then BLE
        try {
          success = await _printerManager.connect(
            type: type,
            model: BluetoothPrinterInput(
              name: device.name,
              address: device.address!,
              isBle: false, 
            ),
          );
        } catch (_) {
          success = false;
        }

        if (!success) {
          try {
            success = await _printerManager.connect(
              type: type,
              model: BluetoothPrinterInput(
                name: device.name,
                address: device.address!,
                isBle: true, 
              ),
            );
          } catch (_) {
            success = false;
          }
        }
      }
      
      if (success) {
        _isConnected = true;
        _activeDevice = device;
        _activeType = type;
        _activeModel = model;
      }
      return success;
    } catch (e) {
      debugPrint('Connection error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_activeModel == PrinterModel.generic && _activeType != null) {
      try {
        await _printerManager.disconnect(type: _activeType!);
      } catch (_) {}
    }
    _isConnected = false;
    _activeDevice = null;
    _activeType = null;
    _activeSystemPrinter = null;
  }

  /// Returns complete universal ESC/POS and Star drawer kick pulse sequences
  List<int> getCashDrawerBytes({
    int pin = 2,
    int pulseOnMs = 50,
    int pulseOffMs = 250,
  }) {
    final int pinByte = (pin == 5) ? 0x01 : 0x00;
    final int onTime = (pulseOnMs / 2).clamp(1, 255).toInt();
    final int offTime = (pulseOffMs / 2).clamp(1, 255).toInt();

    return [
      // 1. Standard ESC/POS kick command: ESC p m t1 t2
      0x1B, 0x70, pinByte, onTime, offTime,
      // 2. Real-Time DLE DC4 drawer kick command
      0x10, 0x14, 0x01, 0x00, 0x01,
      // 3. Alternative standard kick pulse for Xprinter / Rongta / Epson / Sunmi
      0x1B, 0x70, (pinByte == 0 ? 1 : 0), onTime, offTime,
      // 4. Star Line Mode BEL pulse (for Star printers operating in line mode)
      0x07,
    ];
  }

  /// Master method to trigger cash drawer kick pulse across all POS hardware connection types
  Future<bool> openCashDrawer({
    StoreConfig? config,
    int? pin,
    int? pulseOnMs,
    int? pulseOffMs,
  }) async {
    final targetPin = pin ?? config?.cashDrawerPin ?? 2;
    final onMs = pulseOnMs ?? config?.cashDrawerPulseOnMs ?? 50;
    final offMs = pulseOffMs ?? config?.cashDrawerPulseOffMs ?? 250;

    debugPrint('CashDrawerDriver: Triggering kick pulse (Pin $targetPin, ON: ${onMs}ms, OFF: ${offMs}ms)...');

    // 1. Star Micronics Driver
    if (_activeModel == PrinterModel.star && _activeDevice?.address != null) {
      try {
        star.PrintCommands commands = star.PrintCommands();
        commands.openCashDrawer(targetPin == 5 ? 2 : 1);
        await star.StarPrnt.sendCommands(
          portName: _activeDevice!.address!,
          emulation: _starEmulation.text,
          printCommands: commands,
        );
        debugPrint('CashDrawerDriver: Star drawer kick command transmitted.');
        return true;
      } catch (e) {
        debugPrint('CashDrawerDriver: Star cash drawer error: $e');
      }
    }

    final bytes = getCashDrawerBytes(pin: targetPin, pulseOnMs: onMs, pulseOffMs: offMs);

    // 2. Active Driver Connection (USB / Bluetooth / Direct Socket / Network / Linux Raw lp*)
    if (_isConnected) {
      try {
        final ok = await _sendBytes(bytes);
        if (ok) {
          debugPrint('CashDrawerDriver: Kick pulse transmitted via active printer driver.');
          return true;
        }
      } catch (e) {
        debugPrint('CashDrawerDriver: Active connection kick error: $e');
      }
    }

    // 3. Auto-fallback: Connect & transmit if disconnected
    if (!_isConnected) {
      try {
        final connected = await autoConnect(config: config);
        if (connected) {
          final ok = await _sendBytes(bytes);
          if (ok) {
            debugPrint('CashDrawerDriver: Kick pulse transmitted via auto-connected driver.');
            return true;
          }
        }
      } catch (e) {
        debugPrint('CashDrawerDriver: Auto-connect fallback error: $e');
      }
    }

    return false;
  }

  /// Converts an img.Image into universal ESC/POS 1-bit raster bit image bytes (GS v 0).
  /// Properly handles transparency (treats transparent alpha pixels as white paper background)
  /// and binarizes dark pixels into printable black dots.
  List<int> _imageToRasterEscPos(
    img.Image baseImage, {
    int targetWidth = 384,
    PosAlign align = PosAlign.center,
  }) {
    try {
      final img.Image resized = img.copyResize(baseImage, width: targetWidth);
      final int widthPx = resized.width;
      final int heightPx = resized.height;
      final int widthBytes = (widthPx + 7) ~/ 8;

      final List<int> bytes = [];

      // Alignment: ESC a n (0: Left, 1: Center, 2: Right)
      int alignCode = 1;
      if (align == PosAlign.left) alignCode = 0;
      if (align == PosAlign.right) alignCode = 2;
      bytes.addAll([0x1B, 0x61, alignCode]);

      // GS v 0 0 xL xH yL yH
      final int xL = widthBytes % 256;
      final int xH = widthBytes ~/ 256;
      final int yL = heightPx % 256;
      final int yH = heightPx ~/ 256;
      bytes.addAll([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]);

      for (int y = 0; y < heightPx; y++) {
        for (int byteX = 0; byteX < widthBytes; byteX++) {
          int currentByte = 0;
          for (int bit = 0; bit < 8; bit++) {
            final int x = byteX * 8 + bit;
            if (x < widthPx) {
              final pixel = resized.getPixel(x, y);
              final a = pixel.a;
              final r = pixel.r;
              final g = pixel.g;
              final b = pixel.b;

              // Transparent or semi-transparent pixels are treated as white paper (no dot)
              if (a > 32) {
                final luminance = (0.299 * r + 0.587 * g + 0.114 * b);
                // If dark pixel on light background -> print dot (1)
                if (luminance < 140) {
                  currentByte |= (0x80 >> bit);
                }
              }
            }
          }
          bytes.add(currentByte);
        }
      }

      // Reset alignment to left
      bytes.addAll([0x1B, 0x61, 0x00]);
      return bytes;
    } catch (e) {
      debugPrint('ESC/POS Image rasterization notice: $e');
      return [];
    }
  }

  /// Converts any string data into a 100% universal ESC/POS 1-bit raster QR code (GS v 0).
  /// Guaranteed to print cleanly on all generic ESC/POS thermal printers regardless of hardware QR support.
  List<int> _qrToRasterEscPos(
    String data, {
    int scale = 3,
    PosAlign align = PosAlign.center,
  }) {
    try {
      final qrCode = QrCode.fromData(
        data: data,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      );
      final qrImage = QrImage(qrCode);
      final int moduleCount = qrImage.moduleCount;

      // Add compact quiet zone margin (1 module on each side)
      const int margin = 1;
      final int totalModules = moduleCount + (margin * 2);
      final int widthPx = totalModules * scale;
      final int heightPx = widthPx;
      final int widthBytes = (widthPx + 7) ~/ 8;

      final List<int> bytes = [];

      // Alignment: ESC a n (0: Left, 1: Center, 2: Right)
      int alignCode = 1;
      if (align == PosAlign.left) alignCode = 0;
      if (align == PosAlign.right) alignCode = 2;
      bytes.addAll([0x1B, 0x61, alignCode]);

      // GS v 0 0 xL xH yL yH
      final int xL = widthBytes % 256;
      final int xH = widthBytes ~/ 256;
      final int yL = heightPx % 256;
      final int yH = heightPx ~/ 256;
      bytes.addAll([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]);

      // Optimized raster generator: generate each module row once, then repeat scale times
      for (int mY = 0; mY < totalModules; mY++) {
        final int moduleY = mY - margin;
        final List<int> rowBytes = List<int>.filled(widthBytes, 0);
        for (int byteX = 0; byteX < widthBytes; byteX++) {
          int currentByte = 0;
          for (int bit = 0; bit < 8; bit++) {
            final int x = byteX * 8 + bit;
            if (x < widthPx) {
              final int moduleX = (x ~/ scale) - margin;
              if (moduleY >= 0 && moduleY < moduleCount && moduleX >= 0 && moduleX < moduleCount) {
                if (qrImage.isDark(moduleY, moduleX)) {
                  currentByte |= (0x80 >> bit);
                }
              }
            }
          }
          rowBytes[byteX] = currentByte;
        }
        for (int s = 0; s < scale; s++) {
          bytes.addAll(rowBytes);
        }
      }

      // Reset alignment to left
      bytes.addAll([0x1B, 0x61, 0x00]);
      return bytes;
    } catch (e) {
      debugPrint('ESC/POS QR rasterization notice: $e');
      return [];
    }
  }

  /// Unified check to determine if a transaction should print the ZRA Fiscal Control block & QR Code.
  /// Both COMPLETED (Approved) and PENDING sales print the QR code; FAILED and LOCAL_EXEMPT do not.
  bool isFiscalApproved(SaleTransaction transaction) {
    final statusUpper = transaction.zraStatus.toUpperCase();
    if (statusUpper.startsWith('FAILED') ||
        statusUpper == 'LOCAL_EXEMPT' ||
        statusUpper == 'OFFLINE_EXEMPT') {
      return false;
    }

    // 1. If live or generated ZRA QR Code is present and non-empty, fiscal verification data exists
    final hasQr = transaction.zraQrCode != null &&
        transaction.zraQrCode!.trim().isNotEmpty &&
        transaction.zraQrCode!.trim() != 'PENDING';
    if (hasQr) {
      return true;
    }

    if (statusUpper == 'APPROVED' ||
        statusUpper == 'COMPLETED' ||
        statusUpper == 'FISCALIZED' ||
        statusUpper == 'PENDING') {
      return true;
    }

    final hasReceiptNo = transaction.zraReceiptNumber != null &&
        transaction.zraReceiptNumber!.trim().isNotEmpty &&
        transaction.zraReceiptNumber!.trim() != 'PENDING';

    final hasSignature = transaction.zraMarkId != null &&
        transaction.zraMarkId!.trim().isNotEmpty &&
        transaction.zraMarkId!.trim() != 'PENDING' &&
        !transaction.zraMarkId!.startsWith('sale_') &&
        !transaction.zraMarkId!.startsWith('SALE_');

    if (hasReceiptNo && hasSignature) {
      return true;
    }

    return false;
  }

  /// Master Method to Print High-Fidelity Compact Thermal Receipt (55mm, 58mm, 76mm, 80mm, 110mm, 112mm)
  Future<bool> printReceipt(
    SaleTransaction transaction, 
    List<SaleItem> items, {
    StoreConfig? config,
    Customer? customer,
  }) async {
    if (config?.paperWidthMm != null && config!.paperWidthMm > 0) {
      _paperWidthMm = config.paperWidthMm;
    }

    if (!_isConnected) {
      // Auto-fallback: attempt quick connection to system printer
      final ok = await autoConnect(config: config);
      if (!ok && _activeSystemPrinter == null) {
        return await _printWithSystem(transaction, items, config: config, customer: customer);
      }
    }

    if (_activeModel == PrinterModel.system) {
      return await _printWithSystem(transaction, items, config: config, customer: customer);
    }

    if (_activeModel == PrinterModel.star) {
      return await _printWithStar(transaction, items, config: config, customer: customer);
    }

    try {
      final preset = activePreset;
      final isNarrow = preset.widthMm <= 58;
      final colCount = preset.columnCount;
      final profile = await CapabilityProfile.load();
      final generator = Generator(preset.escPosSize, profile);
      List<int> bytes = [];

      // 0. Hardware Reset Init Command (ESC @) + Compact Line Spacing (ESC 3 20)
      bytes += generator.reset();
      bytes += [0x1B, 0x33, 20];

      // Hardware Drawer Kick Pulse (if auto-kick is enabled in config)
      if (config?.autoOpenCashDrawer != false) {
        final isCashOrSplit = transaction.paymentMethod.toLowerCase() == 'cash' || 
                             transaction.paymentMethod.toLowerCase() == 'split';
        if (config?.openDrawerCashOnly != true || isCashOrSplit) {
          bytes += getCashDrawerBytes(
            pin: config?.cashDrawerPin ?? 2,
            pulseOnMs: config?.cashDrawerPulseOnMs ?? 50,
            pulseOffMs: config?.cashDrawerPulseOffMs ?? 250,
          );
        }
      }

      final currency = config?.currencySymbol ?? 'K';

      // 1. Store Logo — Rendered via compact universal 1-bit ESC/POS GS v 0 raster
      final String? customLogoPath = config?.logoPath;
      if (customLogoPath != null && File(customLogoPath).existsSync()) {
        try {
          final logoBytes = await File(customLogoPath).readAsBytes();
          final img.Image? baseImage = img.decodeImage(logoBytes);
          if (baseImage != null) {
            final rasterLogo = _imageToRasterEscPos(
              baseImage,
              targetWidth: (preset.logoPixelWidth * 0.75).round(),
              align: PosAlign.center,
            );
            if (rasterLogo.isNotEmpty) {
              bytes += rasterLogo;
            }
          }
        } catch (e) {
          debugPrint('Thermal logo print notice: $e');
        }
      }

      // 2. Compact Company Name & Branch Header (normal size bold so it never wraps into giant multi-line blocks)
      final companyName = (config?.businessName != null && config!.businessName.isNotEmpty 
          ? config.businessName 
          : 'BELEKA POS').toUpperCase();
      final branchName = (config?.terminalName != null && config!.terminalName.isNotEmpty 
          ? config.terminalName 
          : (config?.branchName ?? 'MAIN BRANCH')).toUpperCase();

      bytes += generator.text(
        companyName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
        ),
      );

      final headerMetaParts = <String>['BRANCH: $branchName'];
      if (config?.tpin != null && config!.tpin!.isNotEmpty) {
        headerMetaParts.add('TPIN: ${config.tpin!}');
      }
      for (final part in headerMetaParts) {
        bytes += generator.text(
          part,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
      }
      if (config?.address != null && config!.address!.isNotEmpty) {
        bytes += generator.text(
          config.address!,
          styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
        );
      }
      if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) {
        bytes += generator.text(
          'Tel: ${config.contactNumber!}',
          styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
        );
      }

      final isFiscalApproved = this.isFiscalApproved(transaction);

      final receiptTitle = transaction.isCreditNote
          ? 'ZRA FISCAL CREDIT NOTE'
          : (isFiscalApproved ? 'TAX INVOICE / RECEIPT' : 'CUSTOMER SALES SLIP');

      bytes += generator.text(preset.doubleDivider);
      bytes += generator.text(
        receiptTitle,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      if (transaction.isCreditNote && transaction.orgInvoiceNo != null) {
        bytes += generator.text(
          _formatRow2('ORIG INV:', transaction.orgInvoiceNo!, colCount),
          styles: const PosStyles(bold: true),
        );
        if (transaction.creditNoteReason != null && transaction.creditNoteReason!.isNotEmpty) {
          bytes += generator.text(
            _formatRow2('REASON:', transaction.creditNoteReason!, colCount),
          );
        }
      }
      bytes += generator.text(preset.singleDivider);

      // 3. Compact Receipt Metadata (fits strictly within colCount on 55mm/58mm/80mm)
      final shortDateTimeStr = DateFormat('dd/MM/yy HH:mm').format(transaction.timestamp);
      final receiptNo = transaction.isCreditNote
          ? 'CN#${transaction.id.toString().padLeft(6, '0')}'
          : '#${transaction.id.toString().padLeft(6, '0')}';
      final cashier = transaction.cashierName.isNotEmpty ? transaction.cashierName : 'Staff';
      final termName = transaction.terminalName ?? config?.terminalName ?? 'POS-01';

      bytes += generator.text(
        _formatRow2('RCPT $receiptNo', shortDateTimeStr, colCount),
        styles: const PosStyles(bold: true),
      );
      bytes += generator.text(
        _formatRow2('Staff: $cashier', termName, colCount),
      );
      if (transaction.isCreditNote &&
          transaction.externalPaymentConfirmedBy != null &&
          transaction.externalPaymentConfirmedBy!.trim().isNotEmpty) {
        bytes += generator.text(
          _formatRow2('Appr By:', transaction.externalPaymentConfirmedBy!.trim(), colCount),
          styles: const PosStyles(bold: true),
        );
      }

      if (transaction.customerTpin != null && transaction.customerTpin!.isNotEmpty) {
        bytes += generator.text(
          _formatRow2('BUYER TPIN:', transaction.customerTpin!, colCount),
          styles: const PosStyles(bold: true),
        );
        if (transaction.customerBusinessName != null && transaction.customerBusinessName!.isNotEmpty) {
          bytes += generator.text(
            _formatRow2('BUYER:', transaction.customerBusinessName!, colCount),
          );
        }
      } else if (customer != null) {
        bytes += generator.text(
          _formatRow2('Cust: ${customer.name}', customer.phoneNumber, colCount),
        );
      }

      bytes += generator.text(preset.singleDivider);

      // 4. Line Items Table Header & Compact Single-Line Rows
      if (isNarrow) {
        bytes += generator.text(
          _formatRow3('ITEM', 'QTY', 'TOTAL', colCount),
          styles: const PosStyles(bold: true),
        );
      } else {
        bytes += generator.text(
          _formatRow4('ITEM', 'QTY', 'PRICE', 'TOTAL', colCount),
          styles: const PosStyles(bold: true),
        );
      }
      bytes += generator.text(preset.singleDivider);

      // 5. Line Items Rows (1 clean aligned line per item across all paper sizes)
      final isTot = config?.businessTaxType == 'TURNOVER_TAX';
      for (var item in items) {
        final taxLetter = isTot ? 'E' : _getTaxLetter(item.taxRateAtSale);
        final effectiveQty = (item.isWeighted && item.weight > 0)
            ? item.weight
            : item.quantity.toDouble();
        final qtyStr = (item.isWeighted && item.weight > 0)
            ? '${item.weight.toStringAsFixed(2)}${item.unitOfMeasure.isNotEmpty ? item.unitOfMeasure : "kg"}'
            : '${item.quantity}x';
        final itemTotal = item.priceAtSale * effectiveQty;
        final totalFormatted = CurrencyFormatter.format(itemTotal, currency);

        if (isNarrow) {
          bytes += generator.text(
            _formatRow3(
              item.productName.toUpperCase(),
              qtyStr,
              '$totalFormatted$taxLetter',
              colCount,
            ),
          );
        } else {
          bytes += generator.text(
            _formatRow4(
              item.productName.toUpperCase(),
              qtyStr,
              CurrencyFormatter.format(item.priceAtSale, currency),
              '$totalFormatted$taxLetter',
              colCount,
            ),
          );
        }
      }

      bytes += generator.text(preset.singleDivider);

      // 6. Compact Financial Summary
      bytes += generator.text(
        _formatRow2('SUBTOTAL', CurrencyFormatter.format(transaction.subtotal, currency), colCount),
      );

      if (transaction.discountAmount > 0) {
        bytes += generator.text(
          _formatRow2('DISCOUNT', '-${CurrencyFormatter.format(transaction.discountAmount, currency)}', colCount),
        );
      }

      if (transaction.taxAmount > 0 && !isTot) {
        bytes += generator.text(
          _formatRow2('VAT (INCL)', CurrencyFormatter.format(transaction.taxAmount, currency), colCount),
        );
      }

      if (transaction.serviceChargeAmount > 0) {
        final scLabel = 'SVC CHG (${transaction.serviceChargeRate.toStringAsFixed(0)}%)';
        bytes += generator.text(
          _formatRow2(scLabel, CurrencyFormatter.format(transaction.serviceChargeAmount, currency), colCount),
        );
      }

      bytes += generator.text(preset.doubleDivider);

      // Grand Total Highlight (normal width bold so it never overflows or wraps)
      bytes += generator.text(
        _formatRow2('TOTAL DUE', CurrencyFormatter.format(transaction.totalAmount, currency), colCount),
        styles: const PosStyles(bold: true),
      );

      bytes += generator.text(preset.doubleDivider);

      // 7. Payment Tender Details
      bytes += generator.text(
        _formatRow2('PAID VIA', transaction.paymentMethod.toUpperCase(), colCount),
        styles: const PosStyles(bold: true),
      );

      if (transaction.paymentMethod.toUpperCase() == 'CASH') {
        bytes += generator.text(
          _formatRow2(
            'Tendered',
            CurrencyFormatter.format(
              transaction.tenderedAmount > 0 ? transaction.tenderedAmount : transaction.totalAmount,
              currency,
            ),
            colCount,
          ),
        );
        bytes += generator.text(
          _formatRow2('Change', CurrencyFormatter.format(transaction.changeAmount, currency), colCount),
          styles: const PosStyles(bold: true),
        );
      }

      if (transaction.paymentMethod.toUpperCase().contains('EXTERNAL MOBILE MONEY')) {
        if (transaction.externalPaymentReference != null &&
            transaction.externalPaymentReference!.trim().isNotEmpty) {
          bytes += generator.text(
            _formatRow2('Ref No:', transaction.externalPaymentReference!.trim(), colCount),
          );
        }
        if (transaction.externalPaymentConfirmedBy != null &&
            transaction.externalPaymentConfirmedBy!.trim().isNotEmpty) {
          bytes += generator.text(
            _formatRow2('Conf By:', transaction.externalPaymentConfirmedBy!.trim(), colCount),
          );
        }
      }

      // 8. Compact Tax Summary
      if (isTot) {
        bytes += generator.text(
          _formatRow2('TURNOVER TAX (5%):', 'EXEMPT', colCount),
        );
      } else {
        final breakdown = _getTaxBreakdown(items);
        breakdown.forEach((rate, values) {
          final letter = _getTaxLetter(rate);
          bytes += generator.text(
            _formatRow3(
              'TAX $letter (${rate.toStringAsFixed(0)}%)',
              CurrencyFormatter.formatTaxPrecision(values['vat']!, currency),
              CurrencyFormatter.format(values['total']!, currency),
              colCount,
            ),
          );
        });
      }

      // 9. SDC / ZRA Smart Invoice Compliance Block
      final dateTimeFiscal = DateFormat('dd/MM/yy HH:mm:ss').format(transaction.timestamp);
      String sdcIdStr = (transaction.zraSdcId != null && transaction.zraSdcId!.isNotEmpty && transaction.zraSdcId != 'PENDING')
          ? transaction.zraSdcId!
          : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : '');
      if (sdcIdStr.isEmpty && transaction.zraReceiptNumber != null) {
        final match = RegExp(r'INV(\d+)/', caseSensitive: false).firstMatch(transaction.zraReceiptNumber!);
        if (match != null && match.group(1) != null && match.group(1) != '1') {
          sdcIdStr = 'SDC${match.group(1)}';
        }
      }
      if (sdcIdStr.isEmpty) {
        sdcIdStr = 'PENDING';
      }
      final sdcInvNoStr = _formatZraSdcInvoiceNo(transaction.zraReceiptNumber, sdcId: sdcIdStr);
      final signatureStr = (transaction.zraMarkId != null &&
              transaction.zraMarkId!.isNotEmpty &&
              !transaction.zraMarkId!.startsWith('sale_'))
          ? transaction.zraMarkId!
          : 'PENDING';
      final internalDataStr = (transaction.zraInternalData != null &&
              transaction.zraInternalData!.isNotEmpty &&
              transaction.zraInternalData != 'PENDING')
          ? transaction.zraInternalData!
          : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');

      bytes += generator.text(preset.singleDivider);

      if (isFiscalApproved) {
        bytes += generator.text(
          'ZRA FISCAL CONTROL DATA',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        bytes += generator.text(_formatRow2('Date/Time:', dateTimeFiscal, colCount));
        bytes += generator.text(_formatRow2('SDC ID:', sdcIdStr, colCount));
        bytes += generator.text(_formatRow2('SDC Inv:', sdcInvNoStr, colCount));
        bytes += generator.text(_formatRow2('Sig:', signatureStr, colCount));
        bytes += generator.text(_formatRow2('Int Data:', internalDataStr, colCount));
        bytes += generator.text(_formatRow2('Type:', transaction.zraInvoiceType ?? 'Normal Sale', colCount));

        // Print Live ZRA Smart Invoice Verification QR Code via compact 1-bit ESC/POS raster
        final zraQrData = (transaction.zraQrCode != null && transaction.zraQrCode!.isNotEmpty)
            ? transaction.zraQrCode!
            : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcIdStr&rcpt=$sdcInvNoStr';
        try {
          final qrRasterBytes = _qrToRasterEscPos(
            zraQrData,
            scale: isNarrow ? 2 : 3,
            align: PosAlign.center,
          );
          if (qrRasterBytes.isNotEmpty) {
            bytes += qrRasterBytes;
            bytes += generator.text(
              'Scan QR to Verify on ZRA Portal',
              styles: const PosStyles(align: PosAlign.center, bold: true, fontType: PosFontType.fontB),
            );
          } else {
            bytes += generator.text(
              'VERIFY: $zraQrData',
              styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
            );
          }
        } catch (e) {
          debugPrint('QR code generation notice: $e');
          bytes += generator.text(
            'VERIFY: $zraQrData',
            styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
          );
        }
      } else {
        final isLocalOnly = transaction.zraStatus == 'LOCAL_EXEMPT' ||
            transaction.zraStatus == 'OFFLINE_EXEMPT';
        if (!isLocalOnly) {
          bytes += generator.text(
            'OFFLINE - ZRA FISCAL PENDING',
            styles: const PosStyles(align: PosAlign.center, bold: true),
          );
        }
      }

      // 10. Compact Customer Footer
      bytes += generator.text(preset.doubleDivider);
      bytes += generator.text(
        'THANK YOU FOR SHOPPING WITH US!',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        'Goods returnable within 7 days with receipt',
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
      );
      bytes += generator.text(preset.doubleDivider);
      
      // generator.cut() already prepends blank lines internally.
      bytes += generator.cut();

      // Send to active driver
      return await _sendBytes(bytes);
    } catch (e) {
      debugPrint('Thermal receipt print error: $e');
      return false;
    }
  }

  /// Print official ZRA End-of-Day Fiscal Z-Report
  Future<bool> printZraFiscalZReport({
    required Map<String, dynamic> reportData,
    required StoreConfig? config,
    ThermalPaperPreset? preset,
  }) async {
    if (config?.paperWidthMm != null && config!.paperWidthMm > 0) {
      _paperWidthMm = config.paperWidthMm;
    }
    if (!_isConnected) {
      await autoConnect(config: config);
    }

    if (_activeModel == PrinterModel.system) {
      return await _printZraFiscalZReportWithSystem(reportData: reportData, config: config);
    }

    final currentPreset = preset ?? activePreset;
    final currency = config?.currencySymbol ?? 'K';
    final paperSize = currentPreset.escPosSize;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    final colCount = currentPreset.columnCount;
    final date = (reportData['date'] is DateTime) ? reportData['date'] as DateTime : DateTime.now();
    final dateStr = DateFormat('dd/MM/yy HH:mm').format(date);

    try {
      bytes += generator.reset();
      bytes += [0x1B, 0x33, 20];

      // Store Header
      bytes += generator.text(
        config?.businessName ?? 'BELEKA RETAIL STORE',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      if (config?.tpin != null) {
        bytes += generator.text('TPIN: ${config!.tpin!}', styles: const PosStyles(align: PosAlign.center, bold: true));
      }
      bytes += generator.text('SDC ID: ${config?.sdcId ?? "SDC00300000014"}', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('BRANCH (bhfId): ${config?.bhfId ?? "00"}', styles: const PosStyles(align: PosAlign.center));

      bytes += generator.text(currentPreset.doubleDivider);
      bytes += generator.text('ZRA FISCAL Z-REPORT', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('DATE: $dateStr', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(currentPreset.doubleDivider);

      // SDC Invoices Count and Range
      bytes += generator.text(_formatRow2('TOTAL TXNS', '${reportData["totalTransactions"] ?? 0}', colCount));
      bytes += generator.text(_formatRow2('NORMAL INVOICES', '${reportData["normalInvoicesCount"] ?? 0}', colCount));
      bytes += generator.text(_formatRow2('CREDIT NOTES', '${reportData["creditNotesCount"] ?? 0}', colCount));
      bytes += generator.text(_formatRow2('FIRST SDC INV', '${reportData["firstSdcReceipt"] ?? "N/A"}', colCount));
      bytes += generator.text(_formatRow2('LAST SDC INV', '${reportData["lastSdcReceipt"] ?? "N/A"}', colCount));

      bytes += generator.text(currentPreset.singleDivider);
      bytes += generator.text('TAX BREAKDOWN', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text(currentPreset.singleDivider);

      // Tax A (16% VAT)
      final taxATaxable = (reportData['taxA16Taxable'] as num?)?.toDouble() ?? 0.0;
      final taxAVat = (reportData['taxA16Vat'] as num?)?.toDouble() ?? 0.0;
      bytes += generator.text(_formatRow2('TAX A (16%) TAXABLE', CurrencyFormatter.format(taxATaxable, currency), colCount));
      bytes += generator.text(_formatRow2('TAX A (16%) VAT', CurrencyFormatter.format(taxAVat, currency), colCount), styles: const PosStyles(bold: true));

      // Tax B (0.0% Zero-Rated)
      final taxBTaxable = (reportData['taxB0Taxable'] as num?)?.toDouble() ?? 0.0;
      bytes += generator.text(_formatRow2('TAX B (0% ZERO)', CurrencyFormatter.format(taxBTaxable, currency), colCount));

      // Tax C (Export)
      final taxCTaxable = (reportData['taxCExportTaxable'] as num?)?.toDouble() ?? 0.0;
      if (taxCTaxable != 0) {
        bytes += generator.text(_formatRow2('TAX C (EXPORT)', CurrencyFormatter.format(taxCTaxable, currency), colCount));
      }

      // Tax D (Exempt)
      final taxDTaxable = (reportData['taxDExemptTaxable'] as num?)?.toDouble() ?? 0.0;
      if (taxDTaxable != 0) {
        bytes += generator.text(_formatRow2('TAX D (EXEMPT)', CurrencyFormatter.format(taxDTaxable, currency), colCount));
      }

      bytes += generator.text(currentPreset.doubleDivider);

      // Financial Totals
      final grossSales = (reportData['grossSales'] as num?)?.toDouble() ?? 0.0;
      final totalTax = (reportData['totalTax'] as num?)?.toDouble() ?? 0.0;
      final netSales = (reportData['netSales'] as num?)?.toDouble() ?? 0.0;

      bytes += generator.text(_formatRow2('NET SALES', CurrencyFormatter.format(netSales, currency), colCount));
      bytes += generator.text(_formatRow2('TOTAL TAX', CurrencyFormatter.format(totalTax, currency), colCount), styles: const PosStyles(bold: true));
      bytes += generator.text(
        _formatRow2('GROSS SALES', CurrencyFormatter.format(grossSales, currency), colCount),
        styles: const PosStyles(bold: true),
      );

      bytes += generator.text(currentPreset.doubleDivider);
      bytes += generator.text('*** END OF ZRA Z-REPORT ***', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.cut();

      return await _sendBytes(bytes);
    } catch (e) {
      debugPrint('ZRA Fiscal Z-Report print error: $e');
      return false;
    }
  }

  Future<bool> _printZraFiscalZReportWithSystem({
    required Map<String, dynamic> reportData,
    required StoreConfig? config,
  }) async {
    try {
      final doc = pw.Document();
      final currency = config?.currencySymbol ?? 'ZK';
      final date = (reportData['date'] is DateTime) ? reportData['date'] as DateTime : DateTime.now();
      final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(date);

      final taxATaxable = (reportData['taxA16Taxable'] as num?)?.toDouble() ?? 0.0;
      final taxAVat = (reportData['taxA16Vat'] as num?)?.toDouble() ?? 0.0;
      final taxBTaxable = (reportData['taxB0Taxable'] as num?)?.toDouble() ?? 0.0;
      final taxCTaxable = (reportData['taxCExportTaxable'] as num?)?.toDouble() ?? 0.0;
      final taxDTaxable = (reportData['taxDExemptTaxable'] as num?)?.toDouble() ?? 0.0;
      
      final grossSales = (reportData['grossSales'] as num?)?.toDouble() ?? 0.0;
      final totalTax = (reportData['totalTax'] as num?)?.toDouble() ?? 0.0;
      final netSales = (reportData['netSales'] as num?)?.toDouble() ?? 0.0;

      doc.addPage(
        pw.Page(
          pageFormat: pdf.PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(5 * pdf.PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(config?.businessName ?? 'BELEKA RETAIL STORE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                if (config?.tpin != null && config!.tpin!.isNotEmpty)
                  pw.Text('TPIN: ${config.tpin}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('SDC ID: ${config?.sdcId ?? "SDC00300000014"}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('BRANCH CODE (bhfId): ${config?.bhfId ?? "00"}', style: const pw.TextStyle(fontSize: 8)),
                pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                pw.Divider(thickness: 1),
                pw.Text('ZRA FISCAL DAY SUMMARY (Z-REPORT)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('REPORT DATE: $dateStr', style: const pw.TextStyle(fontSize: 7.5)),
                pw.Divider(thickness: 1),

                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('TOTAL TRANSACTIONS', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["totalTransactions"] ?? 0}', style: const pw.TextStyle(fontSize: 8))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('NORMAL INVOICES', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["normalInvoicesCount"] ?? 0}', style: const pw.TextStyle(fontSize: 8))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('CREDIT NOTES (REFUNDS)', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["creditNotesCount"] ?? 0}', style: const pw.TextStyle(fontSize: 8))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('FIRST SDC INVOICE', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["firstSdcReceipt"] ?? "N/A"}', style: const pw.TextStyle(fontSize: 8))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('LAST SDC INVOICE', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["lastSdcReceipt"] ?? "N/A"}', style: const pw.TextStyle(fontSize: 8))],
                ),

                pw.Divider(thickness: 0.5),
                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('TAX CATEGORIZATION BREAKDOWN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
                pw.SizedBox(height: 1 * pdf.PdfPageFormat.mm),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('TAX A (16.0%) TAXABLE', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(taxATaxable, currency), style: const pw.TextStyle(fontSize: 7.5))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('TAX A (16.0%) TAX AMT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)), pw.Text(CurrencyFormatter.formatTaxPrecision(taxAVat, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('TAX B (0.0% ZERO-RATED)', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(taxBTaxable, currency), style: const pw.TextStyle(fontSize: 7.5))],
                ),
                if (taxCTaxable > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [pw.Text('TAX C (EXPORT)', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(taxCTaxable, currency), style: const pw.TextStyle(fontSize: 7.5))],
                  ),
                if (taxDTaxable > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [pw.Text('TAX D (EXEMPT)', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(taxDTaxable, currency), style: const pw.TextStyle(fontSize: 7.5))],
                  ),

                pw.Divider(thickness: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('NET TAXABLE SALES', style: const pw.TextStyle(fontSize: 8)), pw.Text(CurrencyFormatter.format(netSales, currency), style: const pw.TextStyle(fontSize: 8))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('TOTAL TAX COLLECTED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)), pw.Text(CurrencyFormatter.formatTaxPrecision(totalTax, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('GROSS SALES (INCL)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)), pw.Text(CurrencyFormatter.format(grossSales, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))],
                ),

                pw.SizedBox(height: 3 * pdf.PdfPageFormat.mm),
                pw.Text('*** END OF ZRA FISCAL Z-REPORT ***', style: const pw.TextStyle(fontSize: 7.5)),
              ],
            );
          },
        ),
      );

      final slipName = 'ZRA_Fiscal_Z_Report_${DateFormat('yyyyMMdd').format(date)}';
      if (_activeSystemPrinter != null) {
        return await pnt.Printing.directPrintPdf(
          printer: _activeSystemPrinter!,
          onLayout: (pdf.PdfPageFormat format) async => doc.save(),
          name: slipName,
        );
      } else {
        return await pnt.Printing.layoutPdf(
          onLayout: (pdf.PdfPageFormat format) async => doc.save(),
          name: slipName,
        );
      }
    } catch (e) {
      debugPrint('ZRA Fiscal Z-Report system print error: $e');
      return false;
    }
  }

  String _formatRow2(String left, String right, int totalWidth) {
    left = left.trim();
    right = right.trim();
    if (right.isEmpty) {
      return left.length > totalWidth ? left.substring(0, totalWidth) : left;
    }
    if (right.length >= totalWidth - 4) {
      final maxRight = (totalWidth * 0.65).floor();
      if (right.length > maxRight) {
        right = right.substring(0, maxRight);
      }
    }
    if (left.length + right.length + 1 > totalWidth) {
      final maxLeft = totalWidth - right.length - 1;
      if (maxLeft > 0) {
        left = left.substring(0, maxLeft);
      } else {
        left = '';
      }
    }
    final spaces = totalWidth - left.length - right.length;
    return left + (' ' * (spaces > 0 ? spaces : 1)) + right;
  }

  String _formatRow3(String col1, String col2, String col3, int totalWidth) {
    col1 = col1.trim();
    col2 = col2.trim();
    col3 = col3.trim();
    int w3 = (totalWidth * 0.34).floor().clamp(8, 16);
    int w2 = (totalWidth * 0.18).floor().clamp(4, 9);
    int w1 = totalWidth - w2 - w3 - 2; // 2 spaces separator
    if (w1 < 6) {
      w1 = 6;
    }

    String c1 = col1.length > w1 ? col1.substring(0, w1) : col1.padRight(w1);
    String c2 = col2.length > w2 ? col2.substring(0, w2) : col2.padLeft(w2);
    String c3 = col3.length > w3 ? col3.substring(0, w3) : col3.padLeft(w3);
    final line = '$c1 $c2 $c3';
    return line.length > totalWidth ? line.substring(0, totalWidth) : line;
  }

  String _formatRow4(String col1, String col2, String col3, String col4, int totalWidth) {
    col1 = col1.trim();
    col2 = col2.trim();
    col3 = col3.trim();
    col4 = col4.trim();
    int w4 = (totalWidth * 0.25).floor().clamp(8, 14);
    int w3 = (totalWidth * 0.20).floor().clamp(6, 12);
    int w2 = (totalWidth * 0.12).floor().clamp(4, 7);
    int w1 = totalWidth - w2 - w3 - w4 - 3; // 3 spaces separator
    if (w1 < 8) {
      w1 = 8;
    }

    String c1 = col1.length > w1 ? col1.substring(0, w1) : col1.padRight(w1);
    String c2 = col2.length > w2 ? col2.substring(0, w2) : col2.padLeft(w2);
    String c3 = col3.length > w3 ? col3.substring(0, w3) : col3.padLeft(w3);
    String c4 = col4.length > w4 ? col4.substring(0, w4) : col4.padLeft(w4);
    final line = '$c1 $c2 $c3 $c4';
    return line.length > totalWidth ? line.substring(0, totalWidth) : line;
  }

  Future<bool> printDailySummary({
    required Map<String, double> stats,
    required List<Map<String, dynamic>> topProducts,
    required Map<String, double> paymentDist,
    StoreConfig? config,
  }) async {
    if (config?.paperWidthMm != null && config!.paperWidthMm > 0) {
      _paperWidthMm = config.paperWidthMm;
    }
    if (!_isConnected) {
      await autoConnect(config: config);
    }

    if (_activeModel == PrinterModel.system) {
      return await _printSummaryWithSystem(stats, topProducts, paymentDist, config: config);
    }

    try {
      final preset = activePreset;
      final colCount = preset.columnCount;
      final profile = await CapabilityProfile.load();
      final generator = Generator(preset.escPosSize, profile);
      List<int> bytes = [];

      bytes += generator.reset();
      bytes += [0x1B, 0x33, 20];

      final currency = config?.currencySymbol ?? 'K';

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('DAILY X-REPORT');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.text(config?.businessName ?? 'BELEKA POS');
      if (config?.address != null) {
        bytes += generator.text(config!.address!);
      }
      if (config?.taxId != null) {
        bytes += generator.text('VAT ID: ${config!.taxId!}');
      }
      bytes += generator.text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
      bytes += generator.text(preset.doubleDivider);

      final todayCount = (stats['todayCount'] ?? 0).isNaN ? 0 : (stats['todayCount'] ?? 0).toInt();
      final todayRevenue = (stats['todayRevenue'] ?? 0).isNaN ? 0.0 : stats['todayRevenue']!;
      final todayTax = (stats['todayTax'] ?? 0).isNaN ? 0.0 : stats['todayTax']!;
      final netSales = todayRevenue - todayTax;

      bytes += generator.text(_formatRow2('Transactions', '$todayCount', colCount));
      bytes += generator.text(_formatRow2('Gross Revenue', CurrencyFormatter.format(todayRevenue, currency), colCount), styles: const PosStyles(bold: true));
      bytes += generator.text(_formatRow2('Total VAT', CurrencyFormatter.format(todayTax, currency), colCount));
      bytes += generator.text(_formatRow2('Net Sales', CurrencyFormatter.format(netSales, currency), colCount));
      
      bytes += generator.text(preset.singleDivider);
      bytes += generator.text('PAYMENT METHODS', styles: const PosStyles(bold: true));
      double grandTotal = 0.0;
      paymentDist.forEach((method, amount) {
        final val = amount.isNaN ? 0.0 : amount;
        grandTotal += val;
        bytes += generator.text(_formatRow2(method.toUpperCase(), CurrencyFormatter.format(val, currency), colCount));
      });
      bytes += generator.text(preset.singleDivider);
      bytes += generator.text(_formatRow2('TOTAL COLLECTED', CurrencyFormatter.format(grandTotal, currency), colCount), styles: const PosStyles(bold: true));

      bytes += generator.text(preset.singleDivider);
      bytes += generator.text('TOP PRODUCTS', styles: const PosStyles(bold: true));
      for (var p in topProducts.take(5)) {
        bytes += generator.text(_formatRow2(p['name'].toString(), p['quantity'].toString(), colCount));
      }
      
      bytes += generator.text(preset.doubleDivider);
      bytes += generator.cut();

      return await _sendBytes(bytes);
    } catch (e) {
      debugPrint('Summary printing error: $e');
      return false;
    }
  }

  /// Prints a dedicated Financial Summary Slip (Revenue, Profit, Tax/VAT, Transactions, Payment Breakdown)
  /// for Daily, Weekly, Monthly, Yearly, or Custom date ranges.
  Future<bool> printFinancialSummarySlip({
    required String periodTitle,
    required String dateRangeLabel,
    required Map<String, double> stats,
    StoreConfig? config,
  }) async {
    if (config?.paperWidthMm != null && config!.paperWidthMm > 0) {
      _paperWidthMm = config.paperWidthMm;
    }
    if (!_isConnected) {
      await autoConnect(config: config);
    }

    final currency = config?.currencySymbol ?? 'K';
    final revenue = stats['revenue'] ?? 0.0;
    final profit = stats['profit'] ?? 0.0;
    final tax = stats['tax'] ?? 0.0;
    final count = (stats['count'] ?? 0.0).toInt();
    final cash = stats['cash'] ?? 0.0;
    final card = stats['card'] ?? 0.0;
    final mobileMoney = stats['mobile_money'] ?? 0.0;
    final profitMargin = revenue > 0 ? ((profit / revenue) * 100).toStringAsFixed(1) : '0.0';

    if (_activeModel == PrinterModel.system) {
      return await _printFinancialSummaryWithSystem(
        periodTitle: periodTitle,
        dateRangeLabel: dateRangeLabel,
        revenue: revenue,
        profit: profit,
        tax: tax,
        count: count,
        cash: cash,
        card: card,
        mobileMoney: mobileMoney,
        profitMargin: profitMargin,
        currency: currency,
        config: config,
      );
    }

    if (_activeModel == PrinterModel.star) {
      return await _printFinancialSummaryWithStar(
        periodTitle: periodTitle,
        dateRangeLabel: dateRangeLabel,
        revenue: revenue,
        profit: profit,
        tax: tax,
        count: count,
        cash: cash,
        card: card,
        mobileMoney: mobileMoney,
        profitMargin: profitMargin,
        currency: currency,
        config: config,
      );
    }

    // ESC/POS Driver
    try {
      final preset = activePreset;
      final colCount = preset.columnCount;
      final profile = await CapabilityProfile.load();
      final generator = Generator(preset.escPosSize, profile);
      List<int> bytes = [];

      bytes += generator.reset();
      bytes += [0x1B, 0x33, 20];

      // Header
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text(periodTitle.toUpperCase());
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.text(config?.businessName ?? 'BELEKA POS');
      if (config?.address != null && config!.address!.isNotEmpty) {
        bytes += generator.text(config.address!);
      }
      if (config?.tpin != null && config!.tpin!.isNotEmpty) {
        bytes += generator.text('TPIN: ${config.tpin}');
      }
      bytes += generator.text('Period: $dateRangeLabel');
      bytes += generator.text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
      bytes += generator.text(preset.doubleDivider);

      // Core Financial Metrics
      bytes += generator.setStyles(const PosStyles(bold: true));
      bytes += generator.text('FINANCIAL TOTALS');
      bytes += generator.setStyles(const PosStyles());
      bytes += generator.text(_formatRow2('Transactions', '$count sales', colCount));
      bytes += generator.text(_formatRow2('Total Revenue', CurrencyFormatter.format(revenue, currency), colCount), styles: const PosStyles(bold: true));
      bytes += generator.text(_formatRow2('Gross Profit', CurrencyFormatter.format(profit, currency), colCount), styles: const PosStyles(bold: true));
      bytes += generator.text(_formatRow2('Profit Margin', '$profitMargin%', colCount));
      bytes += generator.text(_formatRow2('Total Tax / VAT', CurrencyFormatter.formatTaxPrecision(tax, currency), colCount));
      bytes += generator.text(preset.singleDivider);

      // Payment Tender Breakdown
      bytes += generator.setStyles(const PosStyles(bold: true));
      bytes += generator.text('PAYMENT BREAKDOWN');
      bytes += generator.setStyles(const PosStyles());
      if (cash > 0) {
        bytes += generator.text(_formatRow2('Cash', CurrencyFormatter.format(cash, currency), colCount));
      }
      if (card > 0) {
        bytes += generator.text(_formatRow2('Card', CurrencyFormatter.format(card, currency), colCount));
      }
      if (mobileMoney > 0) {
        bytes += generator.text(_formatRow2('Mobile Money', CurrencyFormatter.format(mobileMoney, currency), colCount));
      }
      bytes += generator.text(preset.singleDivider);
      bytes += generator.text(_formatRow2('TOTAL COLLECTED', CurrencyFormatter.format(revenue, currency), colCount), styles: const PosStyles(bold: true));

      bytes += generator.text(preset.doubleDivider);
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.text('*** END OF SUMMARY SLIP ***');
      bytes += generator.cut();

      return await _sendBytes(bytes);
    } catch (e) {
      debugPrint('Financial summary print error: $e');
      return false;
    }
  }

  /// Sends raw ESC/POS byte sequence over the active driver pipeline
  Future<bool> _sendBytes(List<int> bytes) async {
    // 1. Direct TCP Socket Driver
    if (_activeModel == PrinterModel.directSocket && _activeDevice?.address != null) {
      try {
        final host = _activeDevice!.address!.contains(':') ? _activeDevice!.address!.split(':').first : _activeDevice!.address!;
        final port = _activeDevice!.address!.contains(':') ? int.tryParse(_activeDevice!.address!.split(':').last) ?? 9100 : 9100;
        final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 4));
        socket.add(bytes);
        await socket.flush();
        await socket.close();
        return true;
      } catch (e) {
        debugPrint('Direct socket write failed: $e');
      }
    }

    // 2. Linux Raw USB File Stream (/dev/usb/lp*)
    if (Platform.isLinux && _activeDevice?.address != null && _activeDevice!.address!.startsWith('/dev/usb/lp')) {
      try {
        final file = File(_activeDevice!.address!);
        if (file.existsSync()) {
          final sink = file.openWrite();
          sink.add(bytes);
          await sink.flush();
          await sink.close();
          return true;
        }
      } catch (e) {
        debugPrint('Linux raw USB write error: $e');
      }
    }

    // 3. PrinterManager Platform Channel Driver (USB/Bluetooth/Network)
    if (_activeType != null) {
      try {
        return await _printerManager
            .send(type: _activeType!, bytes: bytes)
            .timeout(const Duration(seconds: 10), onTimeout: () {
          debugPrint('PrinterManager Bluetooth/USB send timed out after 10 seconds.');
          return false;
        });
      } catch (e) {
        debugPrint('PrinterManager send error: $e');
      }
    }

    return false;
  }

  Future<bool> _printWithStar(
    SaleTransaction transaction, 
    List<SaleItem> items, {
    StoreConfig? config,
    Customer? customer,
  }) async {
    if (config?.paperWidthMm != null && config!.paperWidthMm > 0) {
      _paperWidthMm = config.paperWidthMm;
    }
    final currency = config?.currencySymbol ?? 'K';
    var commands = star.PrintCommands();

    final preset = activePreset;
    final colCount = preset.columnCount;

    // Hardware Drawer Kick Pulse (if auto-kick is enabled in config)
    if (config?.autoOpenCashDrawer != false) {
      final isCashOrSplit = transaction.paymentMethod.toLowerCase() == 'cash' || 
                           transaction.paymentMethod.toLowerCase() == 'split';
      if (config?.openDrawerCashOnly != true || isCashOrSplit) {
        commands.openCashDrawer(config?.cashDrawerPin == 5 ? 2 : 1);
      }
    }

    commands.appendAlignment(star.StarAlignmentPosition.Center);
    try {
      img.Image? baseImage;
      String? logoPath = config?.logoPath;
      if (logoPath != null && File(logoPath).existsSync()) {
        baseImage = img.decodeImage(await File(logoPath).readAsBytes());
      }
      if (baseImage != null) {
        final targetW = (preset.logoPixelWidth * 0.75).round();
        final img.Image resized = img.copyResize(baseImage, width: targetW);
        final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));
        commands.appendBitmapByte(byteData: pngBytes, diffusion: true, width: targetW);
      }
    } catch (e) {
      debugPrint('Star logo error: $e');
    }

    final companyName = (config?.businessName != null && config!.businessName.isNotEmpty 
        ? config.businessName 
        : 'BELEKA POS').toUpperCase();
    final branchName = (config?.terminalName != null && config!.terminalName.isNotEmpty 
        ? config.terminalName 
        : 'MAIN BRANCH').toUpperCase();
    final cashier = transaction.cashierName.isNotEmpty ? transaction.cashierName : 'Staff';

    commands.appendEmphasis(true);
    commands.append('$companyName\n');
    commands.append('BRANCH: $branchName\n');
    if (config?.tpin != null && config!.tpin!.isNotEmpty) {
      commands.append('TPIN: ${config.tpin!}\n');
    }
    commands.appendEmphasis(false);
    if (config?.address != null && config!.address!.isNotEmpty) {
      commands.append('${config.address!}\n');
    }
    if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) {
      commands.append('Tel: ${config.contactNumber!}\n');
    }
    final isFiscalApproved = this.isFiscalApproved(transaction);

    final receiptTitle = transaction.isCreditNote
        ? 'ZRA FISCAL CREDIT NOTE'
        : (isFiscalApproved ? 'TAX INVOICE / RECEIPT' : 'CUSTOMER SALES SLIP');

    commands.append('${preset.doubleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('$receiptTitle\n');
    commands.appendEmphasis(false);
    commands.append('${preset.singleDivider}\n');

    commands.appendAlignment(star.StarAlignmentPosition.Left);
    final shortDateTime = DateFormat('dd/MM/yy HH:mm').format(transaction.timestamp);
    final rcptNo = '#${transaction.id.toString().padLeft(6, '0')}';
    final termName = transaction.terminalName ?? config?.terminalName ?? 'POS-01';
    commands.append('${_formatRow2('RCPT $rcptNo', shortDateTime, colCount)}\n');
    commands.append('${_formatRow2('Staff: $cashier', termName, colCount)}\n');
    if (transaction.isCreditNote &&
        transaction.externalPaymentConfirmedBy != null &&
        transaction.externalPaymentConfirmedBy!.trim().isNotEmpty) {
      commands.append(
        '${_formatRow2('Appr By:', transaction.externalPaymentConfirmedBy!.trim(), colCount)}\n',
      );
    }
    if (customer != null) {
      commands.append('${_formatRow2('Cust: ${customer.name}', customer.phoneNumber, colCount)}\n');
    }
    commands.append('${preset.singleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('${_formatRow3('ITEM', 'QTY', 'TOTAL', colCount)}\n');
    commands.appendEmphasis(false);
    commands.append('${preset.singleDivider}\n');
    
    for (var item in items) {
      final letter = _getTaxLetter(item.taxRateAtSale);
      final effectiveQty = (item.isWeighted && item.weight > 0)
          ? item.weight
          : item.quantity.toDouble();
      final qtyStr = (item.isWeighted && item.weight > 0)
          ? '${item.weight.toStringAsFixed(2)}${item.unitOfMeasure.isNotEmpty ? item.unitOfMeasure : "kg"}'
          : '${item.quantity}x';
      final price = CurrencyFormatter.format(item.priceAtSale * effectiveQty, currency);
      commands.append(
        '${_formatRow3(item.productName.toUpperCase(), qtyStr, '$price$letter', colCount)}\n',
      );
    }

    commands.append('${preset.singleDivider}\n');
    commands.append('${_formatRow2('SUBTOTAL', CurrencyFormatter.format(transaction.subtotal, currency), colCount)}\n');

    if (transaction.discountAmount > 0) {
      commands.append('${_formatRow2('DISCOUNT', '-${CurrencyFormatter.format(transaction.discountAmount, currency)}', colCount)}\n');
    }

    if (transaction.taxAmount > 0) {
      final taxLabel = (config?.businessTaxType == 'TURNOVER_TAX') ? 'TURNOVER TAX' : 'VAT (INCL)';
      commands.append('${_formatRow2(taxLabel, CurrencyFormatter.format(transaction.taxAmount, currency), colCount)}\n');
    }

    if (transaction.serviceChargeAmount > 0) {
      final scLabel = 'SVC CHG (${transaction.serviceChargeRate.toStringAsFixed(0)}%)';
      commands.append('${_formatRow2(scLabel, CurrencyFormatter.format(transaction.serviceChargeAmount, currency), colCount)}\n');
    }

    commands.append('${preset.doubleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('${_formatRow2('TOTAL DUE', CurrencyFormatter.format(transaction.totalAmount, currency), colCount)}\n');
    commands.appendEmphasis(false);
    commands.append('${preset.doubleDivider}\n');

    commands.append('${_formatRow2('PAID VIA', transaction.paymentMethod.toUpperCase(), colCount)}\n');
    if (transaction.paymentMethod.toUpperCase() == 'CASH') {
      commands.append('${_formatRow2('Tendered', CurrencyFormatter.format(transaction.tenderedAmount > 0 ? transaction.tenderedAmount : transaction.totalAmount, currency), colCount)}\n');
      commands.append('${_formatRow2('Change', CurrencyFormatter.format(transaction.changeAmount, currency), colCount)}\n');
    }

    // Tax Summary Breakdown for Star
    final starBreakdown = _getTaxBreakdown(items);
    starBreakdown.forEach((rate, values) {
      final letter = _getTaxLetter(rate);
      commands.append(
        '${_formatRow3('TAX $letter (${rate.toStringAsFixed(0)}%)', CurrencyFormatter.formatTaxPrecision(values['vat']!, currency), CurrencyFormatter.format(values['total']!, currency), colCount)}\n',
      );
    });

    // ZRA Fiscal Control Block for Star
    String sdcIdStr = (transaction.zraSdcId != null && transaction.zraSdcId!.isNotEmpty && transaction.zraSdcId != 'PENDING')
        ? transaction.zraSdcId!
        : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : '');
    if (sdcIdStr.isEmpty && transaction.zraReceiptNumber != null) {
      final match = RegExp(r'INV(\d+)/', caseSensitive: false).firstMatch(transaction.zraReceiptNumber!);
      if (match != null && match.group(1) != null && match.group(1) != '1') {
        sdcIdStr = 'SDC${match.group(1)}';
      }
    }
    if (sdcIdStr.isEmpty) {
      sdcIdStr = 'PENDING';
    }
    final sdcInvNoStr = _formatZraSdcInvoiceNo(transaction.zraReceiptNumber, sdcId: sdcIdStr);
    final signatureStr = (transaction.zraMarkId != null &&
            transaction.zraMarkId!.isNotEmpty &&
            !transaction.zraMarkId!.startsWith('sale_'))
        ? transaction.zraMarkId!
        : 'PENDING';
    final internalDataStr = (transaction.zraInternalData != null &&
            transaction.zraInternalData!.isNotEmpty &&
            transaction.zraInternalData != 'PENDING')
        ? transaction.zraInternalData!
        : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');

    commands.append('${preset.singleDivider}\n');
    if (isFiscalApproved) {
      commands.appendAlignment(star.StarAlignmentPosition.Center);
      commands.appendEmphasis(true);
      commands.append('ZRA FISCAL CONTROL DATA\n');
      commands.appendEmphasis(false);
      commands.appendAlignment(star.StarAlignmentPosition.Left);
      commands.append('${_formatRow2('Date/Time:', shortDateTime, colCount)}\n');
      commands.append('${_formatRow2('SDC ID:', sdcIdStr, colCount)}\n');
      commands.append('${_formatRow2('SDC Inv:', sdcInvNoStr, colCount)}\n');
      commands.append('${_formatRow2('Sig:', signatureStr, colCount)}\n');
      commands.append('${_formatRow2('Int Data:', internalDataStr, colCount)}\n');
      commands.append('${_formatRow2('Type:', transaction.zraInvoiceType ?? "Normal Sale", colCount)}\n');

      final zraQrData = (transaction.zraQrCode != null && transaction.zraQrCode!.isNotEmpty)
          ? transaction.zraQrCode!
          : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcIdStr&rcpt=$sdcInvNoStr';

      try {
        final qrCode = QrCode.fromData(
          data: zraQrData,
          errorCorrectLevel: QrErrorCorrectLevel.M,
        );
        final qrImage = QrImage(qrCode);
        final int moduleCount = qrImage.moduleCount;
        const int margin = 1;
        final int totalModules = moduleCount + (margin * 2);
        const int scale = 2;
        final int sizePx = totalModules * scale;
        final img.Image qrBitmap = img.Image(width: sizePx, height: sizePx);
        img.fill(qrBitmap, color: img.ColorRgb8(255, 255, 255));
        for (int mY = 0; mY < moduleCount; mY++) {
          for (int mX = 0; mX < moduleCount; mX++) {
            if (qrImage.isDark(mY, mX)) {
              for (int dy = 0; dy < scale; dy++) {
                for (int dx = 0; dx < scale; dx++) {
                  qrBitmap.setPixelRgb((mX + margin) * scale + dx, (mY + margin) * scale + dy, 0, 0, 0);
                }
              }
            }
          }
        }
        final Uint8List qrPngBytes = Uint8List.fromList(img.encodePng(qrBitmap));
        commands.appendAlignment(star.StarAlignmentPosition.Center);
        commands.appendBitmapByte(byteData: qrPngBytes, diffusion: false, width: sizePx);
        commands.append('Scan QR to Verify on ZRA Portal\n');
      } catch (e) {
        debugPrint('Star QR print notice: $e');
        commands.appendAlignment(star.StarAlignmentPosition.Center);
        commands.append('VERIFY: $zraQrData\n');
      }
    } else {
      final isLocalOnly = transaction.zraStatus == 'LOCAL_EXEMPT' ||
          transaction.zraStatus == 'OFFLINE_EXEMPT';
      if (!isLocalOnly) {
        commands.appendAlignment(star.StarAlignmentPosition.Center);
        commands.appendEmphasis(true);
        commands.append('OFFLINE - ZRA FISCAL PENDING\n');
        commands.appendEmphasis(false);
      }
    }

    commands.appendAlignment(star.StarAlignmentPosition.Center);
    commands.append('${preset.doubleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('THANK YOU FOR SHOPPING WITH US!\n');
    commands.appendEmphasis(false);
    commands.append('Goods returnable within 7 days with receipt\n');
    commands.append('${preset.doubleDivider}\n');
    
    commands.appendCutPaper(star.StarCutPaperAction.PartialCutWithFeed);

    try {
      final result = await star.StarPrnt.sendCommands(
        portName: _activeDevice!.address!,
        emulation: _starEmulation.text,
        printCommands: commands,
      );
      return result.toString().contains('Success');
    } catch (e) {
      debugPrint('Star print execution error: $e');
      return false;
    }
  }

  pw.Widget _pdfRow2(
    String left,
    String right, {
    required double fontSize,
    bool boldLeft = false,
    bool boldRight = false,
    int leftFlex = 5,
    int rightFlex = 5,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 0.4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: leftFlex,
            child: pw.Text(
              left,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: boldLeft ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          pw.SizedBox(width: 3),
          pw.Expanded(
            flex: rightFlex,
            child: pw.Text(
              right,
              textAlign: pw.TextAlign.right,
              maxLines: 1,
              overflow: pw.TextOverflow.clip,
              style: pw.TextStyle(
                fontSize: fontSize,
                fontWeight: boldRight ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _printWithSystem(
    SaleTransaction transaction, 
    List<SaleItem> items, {
    StoreConfig? config,
    Customer? customer,
  }) async {
    try {
      if (config?.paperWidthMm != null && config!.paperWidthMm > 0) {
        _paperWidthMm = config.paperWidthMm;
      }
      final doc = pw.Document();
      final currency = config?.currencySymbol ?? 'K';

      pw.ImageProvider? logoImage;
      String? logoPath = config?.logoPath;
      if (logoPath != null && File(logoPath).existsSync()) {
        try {
          logoImage = pw.MemoryImage(await File(logoPath).readAsBytes());
        } catch (e) {
          debugPrint('Logo load error for PDF: $e');
        }
      }

      final isNarrow = _paperWidthMm <= 58;
      final isWide = _paperWidthMm >= 110;
      final double titleFont = isNarrow ? 8.5 : (isWide ? 10.5 : 9.5);
      final double subHeaderFont = isNarrow ? 7.0 : (isWide ? 8.5 : 7.5);
      final double bodyFont = isNarrow ? 6.5 : (isWide ? 8.0 : 7.0);
      final double smallFont = isNarrow ? 5.8 : (isWide ? 7.0 : 6.2);
      final double marginMm = _paperWidthMm <= 55 ? 2.0 : (isNarrow ? 2.5 : 3.5);

      final rollFormat = pdf.PdfPageFormat(
        _paperWidthMm * pdf.PdfPageFormat.mm,
        double.infinity,
        marginAll: marginMm * pdf.PdfPageFormat.mm,
      );
      final companyName = (config?.businessName != null && config!.businessName.isNotEmpty 
          ? config.businessName 
          : 'BELEKA POS').toUpperCase();
      final branchName = (config?.terminalName != null && config!.terminalName.isNotEmpty 
          ? config.terminalName 
          : (config?.branchName ?? 'MAIN BRANCH')).toUpperCase();
      final cashier = transaction.cashierName.isNotEmpty ? transaction.cashierName : 'Staff';

      final shortDateTime = DateFormat('dd/MM/yy HH:mm').format(transaction.timestamp);
      final sdcIdStr = (transaction.zraSdcId != null && transaction.zraSdcId!.isNotEmpty)
          ? transaction.zraSdcId!
          : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : 'PENDING');
      final sdcInvNoStr = _formatZraSdcInvoiceNo(transaction.zraReceiptNumber, sdcId: sdcIdStr);
      final signatureStr = (transaction.zraMarkId != null &&
              transaction.zraMarkId!.isNotEmpty &&
              !transaction.zraMarkId!.startsWith('sale_'))
          ? transaction.zraMarkId!
          : 'PENDING';
      final internalDataStr = (transaction.zraInternalData != null && transaction.zraInternalData!.isNotEmpty)
          ? transaction.zraInternalData!
          : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');
      final zraQrData = (transaction.zraQrCode != null && transaction.zraQrCode!.isNotEmpty)
          ? transaction.zraQrCode!
          : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcIdStr&rcpt=$sdcInvNoStr';

      final isFiscalApproved = this.isFiscalApproved(transaction);
      final receiptTitle = transaction.isCreditNote
          ? 'ZRA FISCAL CREDIT NOTE'
          : (isFiscalApproved ? 'TAX INVOICE / RECEIPT' : 'CUSTOMER SALES SLIP');
      final rcptNo = transaction.isCreditNote
          ? 'CN#${transaction.id.toString().padLeft(6, '0')}'
          : '#${transaction.id.toString().padLeft(6, '0')}';

      doc.addPage(
        pw.Page(
          pageFormat: rollFormat,
          margin: pw.EdgeInsets.all(marginMm * pdf.PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Container(
                    height: (isNarrow ? 10 : 13) * pdf.PdfPageFormat.mm,
                    child: pw.Image(logoImage),
                  ),
                pw.Text(
                  companyName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: titleFont),
                ),
                pw.Text(
                  'BRANCH: $branchName',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: bodyFont),
                ),
                if (config?.address != null && config!.address!.isNotEmpty)
                  pw.Text(config.address!, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: smallFont)),
                if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty)
                  pw.Text('Tel: ${config.contactNumber!}', style: pw.TextStyle(fontSize: smallFont)),
                if (config?.tpin != null && config!.tpin!.isNotEmpty)
                  pw.Text('TPIN: ${config.tpin!}', style: pw.TextStyle(fontSize: bodyFont, fontWeight: pw.FontWeight.bold)),
                pw.Divider(thickness: 0.7, height: 4),
                pw.Text(receiptTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: subHeaderFont)),
                pw.Divider(thickness: 0.5, height: 4),

                _pdfRow2(
                  'RCPT $rcptNo',
                  shortDateTime,
                  fontSize: bodyFont,
                  boldLeft: true,
                ),
                _pdfRow2(
                  'Staff: $cashier',
                  transaction.terminalName ?? config?.terminalName ?? 'POS-01',
                  fontSize: bodyFont,
                ),
                if (transaction.isCreditNote &&
                    transaction.externalPaymentConfirmedBy != null &&
                    transaction.externalPaymentConfirmedBy!.trim().isNotEmpty)
                  _pdfRow2(
                    'Appr By:',
                    transaction.externalPaymentConfirmedBy!.trim(),
                    fontSize: bodyFont,
                    boldLeft: true,
                    boldRight: true,
                  ),
                if (transaction.customerTpin != null && transaction.customerTpin!.isNotEmpty) ...[
                  _pdfRow2('BUYER TPIN:', transaction.customerTpin!, fontSize: bodyFont, boldLeft: true, boldRight: true),
                  if (transaction.customerBusinessName != null && transaction.customerBusinessName!.isNotEmpty)
                    _pdfRow2('BUYER:', transaction.customerBusinessName!, fontSize: bodyFont, leftFlex: 3, rightFlex: 7),
                ] else if (customer != null)
                  _pdfRow2('Cust: ${customer.name}', customer.phoneNumber, fontSize: bodyFont),

                pw.Divider(thickness: 0.5, height: 4),
                pw.Row(
                  children: [
                    pw.Expanded(flex: 6, child: pw.Text('ITEM', style: pw.TextStyle(fontSize: smallFont, fontWeight: pw.FontWeight.bold))),
                    pw.Expanded(flex: 2, child: pw.Text('QTY', style: pw.TextStyle(fontSize: smallFont, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                    pw.Expanded(flex: 4, child: pw.Text('TOTAL', style: pw.TextStyle(fontSize: smallFont, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                  ],
                ),
                pw.Divider(thickness: 0.4, height: 3),

                ...items.map((item) {
                  final letter = _getTaxLetter(item.taxRateAtSale);
                  final effectiveQty = (item.isWeighted && item.weight > 0)
                      ? item.weight
                      : item.quantity.toDouble();
                  final qtyStr = (item.isWeighted && item.weight > 0)
                      ? '${item.weight.toStringAsFixed(2)}${item.unitOfMeasure.isNotEmpty ? item.unitOfMeasure : "kg"}'
                      : '${item.quantity.toStringAsFixed(0)}x';
                  final itemTotal = item.priceAtSale * effectiveQty;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 0.5),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 6,
                          child: pw.Text(
                            item.productName.toUpperCase(),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                            style: pw.TextStyle(fontSize: bodyFont),
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(
                            qtyStr,
                            maxLines: 1,
                            style: pw.TextStyle(fontSize: bodyFont),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Expanded(
                          flex: 4,
                          child: pw.Text(
                            '${CurrencyFormatter.format(itemTotal, currency)}$letter',
                            maxLines: 1,
                            style: pw.TextStyle(fontSize: bodyFont),
                            textAlign: pw.TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                pw.Divider(thickness: 0.5, height: 4),
                _pdfRow2('SUBTOTAL', CurrencyFormatter.format(transaction.subtotal, currency), fontSize: bodyFont),
                if (transaction.discountAmount > 0)
                  _pdfRow2('DISCOUNT', '-${CurrencyFormatter.format(transaction.discountAmount, currency)}', fontSize: bodyFont),
                if (transaction.taxAmount > 0)
                  _pdfRow2(
                    (config?.businessTaxType == 'TURNOVER_TAX') ? 'TURNOVER TAX' : 'VAT (INCL)',
                    CurrencyFormatter.format(transaction.taxAmount, currency),
                    fontSize: bodyFont,
                  ),
                if (transaction.serviceChargeAmount > 0)
                  _pdfRow2(
                    'SVC CHG (${transaction.serviceChargeRate.toStringAsFixed(0)}%)',
                    CurrencyFormatter.format(transaction.serviceChargeAmount, currency),
                    fontSize: bodyFont,
                  ),
                pw.Divider(thickness: 0.8, height: 4),
                _pdfRow2(
                  'TOTAL DUE',
                  CurrencyFormatter.format(transaction.totalAmount, currency),
                  fontSize: subHeaderFont + 0.5,
                  boldLeft: true,
                  boldRight: true,
                ),
                pw.Divider(thickness: 0.8, height: 4),
                _pdfRow2(
                  'Paid (${transaction.paymentMethod.toUpperCase()})',
                  CurrencyFormatter.format(transaction.tenderedAmount > 0 ? transaction.tenderedAmount : transaction.totalAmount, currency),
                  fontSize: bodyFont,
                ),
                if (transaction.changeAmount > 0)
                  _pdfRow2(
                    'CHANGE',
                    CurrencyFormatter.format(transaction.changeAmount, currency),
                    fontSize: bodyFont,
                    boldLeft: true,
                    boldRight: true,
                  ),
                if (transaction.paymentMethod.toUpperCase().contains('EXTERNAL MOBILE MONEY')) ...[
                  if (transaction.externalPaymentReference != null &&
                      transaction.externalPaymentReference!.trim().isNotEmpty)
                    _pdfRow2('Ref No:', transaction.externalPaymentReference!.trim(), fontSize: smallFont),
                  if (transaction.externalPaymentConfirmedBy != null &&
                      transaction.externalPaymentConfirmedBy!.trim().isNotEmpty)
                    _pdfRow2('Conf By:', transaction.externalPaymentConfirmedBy!.trim(), fontSize: smallFont),
                ],

                ...(() {
                  final pdfBreakdown = _getTaxBreakdown(items);
                  return pdfBreakdown.entries.map((entry) {
                    final letter = _getTaxLetter(entry.key);
                    return pw.Row(
                      children: [
                        pw.Expanded(flex: 4, child: pw.Text('TAX $letter (${entry.key.toStringAsFixed(0)}%)', style: pw.TextStyle(fontSize: smallFont))),
                        pw.Expanded(flex: 4, child: pw.Text(CurrencyFormatter.formatTaxPrecision(entry.value['vat']!, currency), style: pw.TextStyle(fontSize: smallFont), textAlign: pw.TextAlign.center)),
                        pw.Expanded(flex: 4, child: pw.Text(CurrencyFormatter.format(entry.value['total']!, currency), style: pw.TextStyle(fontSize: smallFont), textAlign: pw.TextAlign.right)),
                      ],
                    );
                  }).toList();
                })(),

                pw.Divider(thickness: 0.5, height: 4),
                if (isFiscalApproved) ...[
                  pw.Text('ZRA FISCAL CONTROL DATA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: bodyFont)),
                  _pdfRow2('Date/Time:', shortDateTime, fontSize: smallFont, boldRight: true, leftFlex: 4, rightFlex: 6),
                  _pdfRow2('SDC ID:', sdcIdStr, fontSize: smallFont, boldRight: true, leftFlex: 3, rightFlex: 7),
                  _pdfRow2('SDC Inv:', sdcInvNoStr, fontSize: smallFont, boldRight: true, leftFlex: 3, rightFlex: 7),
                  _pdfRow2('Sig:', signatureStr, fontSize: smallFont, leftFlex: 3, rightFlex: 7),
                  _pdfRow2('Int Data:', internalDataStr, fontSize: smallFont, leftFlex: 3, rightFlex: 7),
                  _pdfRow2('Type:', transaction.zraInvoiceType ?? 'Normal Sale', fontSize: smallFont, leftFlex: 4, rightFlex: 6),
                  pw.SizedBox(height: 1 * pdf.PdfPageFormat.mm),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: zraQrData,
                    width: isNarrow ? 38 : 46,
                    height: isNarrow ? 38 : 46,
                    drawText: false,
                  ),
                  pw.SizedBox(height: 0.5 * pdf.PdfPageFormat.mm),
                  pw.Text('Scan QR to Verify on ZRA Portal', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: smallFont)),
                ] else if (transaction.zraStatus != 'LOCAL_EXEMPT' && transaction.zraStatus != 'OFFLINE_EXEMPT') ...[
                  pw.Text('OFFLINE - ZRA FISCAL PENDING', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: bodyFont)),
                ],

                pw.Divider(thickness: 0.7, height: 4),
                pw.Text('THANK YOU FOR SHOPPING WITH US!', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: bodyFont)),
                pw.Text('Goods returnable within 7 days with receipt', style: pw.TextStyle(fontSize: smallFont)),
              ],
            );
          },
        ),
      );

      if (_activeSystemPrinter != null) {
        return await pnt.Printing.directPrintPdf(
          printer: _activeSystemPrinter!,
          onLayout: (pdf.PdfPageFormat format) async => doc.save(),
          name: 'Receipt_${transaction.id}',
        );
      } else {
        return await pnt.Printing.layoutPdf(
          onLayout: (pdf.PdfPageFormat format) async => doc.save(),
          name: 'Receipt_${transaction.id}',
        );
      }
    } catch (e) {
      debugPrint('System print error: $e');
      return false;
    }
  }

  Future<bool> _printSummaryWithSystem(
    Map<String, double> stats,
    List<Map<String, dynamic>> topProducts,
    Map<String, double> paymentDist, {
    StoreConfig? config,
  }) async {
    try {
      final doc = pw.Document();
      final currency = config?.currencySymbol ?? 'K';

      doc.addPage(
        pw.Page(
          pageFormat: pdf.PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(5 * pdf.PdfPageFormat.mm),
          build: (pw.Context context) {
            final todayCount = (stats['todayCount'] ?? 0).isNaN ? 0 : (stats['todayCount'] ?? 0).toInt();
            final todayRevenue = (stats['todayRevenue'] ?? 0).isNaN ? 0.0 : stats['todayRevenue']!;
            final todayTax = (stats['todayTax'] ?? 0).isNaN ? 0.0 : stats['todayTax']!;
            final netSales = todayRevenue - todayTax;

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text('DAILY X-REPORT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                pw.Text(config?.businessName ?? 'BELEKA POS'),
                pw.Text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())),
                pw.SizedBox(height: 3 * pdf.PdfPageFormat.mm),
                pw.Divider(),
                
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Transactions'), pw.Text('$todayCount')],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Gross Revenue', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    pw.Text(CurrencyFormatter.format(todayRevenue, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Total VAT'), pw.Text(CurrencyFormatter.format(todayTax, currency))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Net Sales'), pw.Text(CurrencyFormatter.format(netSales, currency))],
                ),
                
                pw.SizedBox(height: 3 * pdf.PdfPageFormat.mm),
                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('PAYMENT METHODS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                ...paymentDist.entries.map((e) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text(e.key.toUpperCase()), pw.Text(CurrencyFormatter.format(e.value, currency))],
                )),

                pw.SizedBox(height: 3 * pdf.PdfPageFormat.mm),
                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('TOP PRODUCTS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                ...topProducts.take(5).map((p) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(child: pw.Text(p['name'].toString(), style: const pw.TextStyle(fontSize: 8))),
                    pw.Text(p['quantity'].toString()),
                  ],
                )),
              ],
            );
          },
        ),
      );

      if (_activeSystemPrinter != null) {
        return await pnt.Printing.directPrintPdf(
          printer: _activeSystemPrinter!,
          onLayout: (pdf.PdfPageFormat format) async => doc.save(),
          name: 'Daily_Summary',
        );
      } else {
        return await pnt.Printing.layoutPdf(
          onLayout: (pdf.PdfPageFormat format) async => doc.save(),
          name: 'Daily_Summary',
        );
      }
    } catch (e) {
      debugPrint('Summary print error: $e');
      return false;
    }
  }

  Future<bool> _printFinancialSummaryWithSystem({
    required String periodTitle,
    required String dateRangeLabel,
    required double revenue,
    required double profit,
    required double tax,
    required int count,
    required double cash,
    required double card,
    required double mobileMoney,
    required String profitMargin,
    required String currency,
    StoreConfig? config,
  }) async {
    try {
      final doc = pw.Document();

      doc.addPage(
        pw.Page(
          pageFormat: pdf.PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(5 * pdf.PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(periodTitle.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text(config?.businessName ?? 'BELEKA POS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                if (config?.address != null && config!.address!.isNotEmpty)
                  pw.Text(config.address!, style: const pw.TextStyle(fontSize: 8)),
                if (config?.tpin != null && config!.tpin!.isNotEmpty)
                  pw.Text('TPIN: ${config.tpin}', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Period: $dateRangeLabel', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7.5)),
                pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                pw.Divider(thickness: 1),

                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('FINANCIAL TOTALS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                pw.SizedBox(height: 1 * pdf.PdfPageFormat.mm),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Transactions', style: const pw.TextStyle(fontSize: 8)), pw.Text('$count sales', style: const pw.TextStyle(fontSize: 8))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Revenue', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                    pw.Text(CurrencyFormatter.format(revenue, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Gross Profit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                    pw.Text(CurrencyFormatter.format(profit, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Profit Margin', style: const pw.TextStyle(fontSize: 8)), pw.Text('$profitMargin%', style: const pw.TextStyle(fontSize: 8))],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Total Tax / VAT', style: const pw.TextStyle(fontSize: 8)), pw.Text(CurrencyFormatter.formatTaxPrecision(tax, currency), style: const pw.TextStyle(fontSize: 8))],
                ),

                pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                pw.Divider(thickness: 0.5),
                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('PAYMENT BREAKDOWN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                pw.SizedBox(height: 1 * pdf.PdfPageFormat.mm),
                if (cash > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [pw.Text('Cash', style: const pw.TextStyle(fontSize: 8)), pw.Text(CurrencyFormatter.format(cash, currency), style: const pw.TextStyle(fontSize: 8))],
                  ),
                if (card > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [pw.Text('Card', style: const pw.TextStyle(fontSize: 8)), pw.Text(CurrencyFormatter.format(card, currency), style: const pw.TextStyle(fontSize: 8))],
                  ),
                if (mobileMoney > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [pw.Text('Mobile Money', style: const pw.TextStyle(fontSize: 8)), pw.Text(CurrencyFormatter.format(mobileMoney, currency), style: const pw.TextStyle(fontSize: 8))],
                  ),
                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL COLLECTED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                    pw.Text(CurrencyFormatter.format(revenue, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)),
                  ],
                ),
                pw.SizedBox(height: 3 * pdf.PdfPageFormat.mm),
                pw.Text('*** END OF SUMMARY SLIP ***', style: const pw.TextStyle(fontSize: 7.5)),
              ],
            );
          },
        ),
      );

      final slipName = '${periodTitle.replaceAll(' ', '_')}_Slip';
      if (_activeSystemPrinter != null) {
        return await pnt.Printing.directPrintPdf(
          printer: _activeSystemPrinter!,
          onLayout: (pdf.PdfPageFormat format) async => doc.save(),
          name: slipName,
        );
      } else {
        return await pnt.Printing.layoutPdf(
          onLayout: (pdf.PdfPageFormat format) async => doc.save(),
          name: slipName,
        );
      }
    } catch (e) {
      debugPrint('Financial summary system print error: $e');
      return false;
    }
  }

  Future<bool> _printFinancialSummaryWithStar({
    required String periodTitle,
    required String dateRangeLabel,
    required double revenue,
    required double profit,
    required double tax,
    required int count,
    required double cash,
    required double card,
    required double mobileMoney,
    required String profitMargin,
    required String currency,
    StoreConfig? config,
  }) async {
    try {
      var commands = star.PrintCommands();

      commands.appendAlignment(star.StarAlignmentPosition.Center);
      commands.appendEmphasis(true);
      commands.append('$periodTitle\n');
      commands.append('${config?.businessName ?? 'BELEKA POS'}\n');
      commands.appendEmphasis(false);
      if (config?.address != null && config!.address!.isNotEmpty) commands.append('${config.address!}\n');
      if (config?.tpin != null && config!.tpin!.isNotEmpty) commands.append('TPIN: ${config.tpin}\n');
      commands.append('Period: $dateRangeLabel\n');
      commands.append('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}\n');
      commands.append('--------------------------------\n');
      commands.appendAlignment(star.StarAlignmentPosition.Left);

      commands.appendEmphasis(true);
      commands.append('FINANCIAL TOTALS\n');
      commands.appendEmphasis(false);
      commands.append('${"Transactions".padRight(18)}${"$count sales".padLeft(14)}\n');
      commands.append('${"Total Revenue".padRight(18)}${CurrencyFormatter.format(revenue, currency).padLeft(14)}\n');
      commands.append('${"Gross Profit".padRight(18)}${CurrencyFormatter.format(profit, currency).padLeft(14)}\n');
      commands.append('${"Profit Margin".padRight(18)}${"$profitMargin%".padLeft(14)}\n');
      commands.append('${"Total Tax/VAT".padRight(18)}${CurrencyFormatter.formatTaxPrecision(tax, currency).padLeft(14)}\n');
      commands.append('--------------------------------\n');

      commands.appendEmphasis(true);
      commands.append('PAYMENT BREAKDOWN\n');
      commands.appendEmphasis(false);
      if (cash > 0) commands.append('${"Cash".padRight(18)}${CurrencyFormatter.format(cash, currency).padLeft(14)}\n');
      if (card > 0) commands.append('${"Card".padRight(18)}${CurrencyFormatter.format(card, currency).padLeft(14)}\n');
      if (mobileMoney > 0) commands.append('${"Mobile Money".padRight(18)}${CurrencyFormatter.format(mobileMoney, currency).padLeft(14)}\n');
      commands.append('--------------------------------\n');
      commands.append('${"TOTAL COLLECTED".padRight(18)}${CurrencyFormatter.format(revenue, currency).padLeft(14)}\n');
      commands.append('================================\n');
      commands.appendAlignment(star.StarAlignmentPosition.Center);
      commands.append('*** END OF SUMMARY SLIP ***\n\n\n');
      commands.appendCutPaper(star.StarCutPaperAction.PartialCutWithFeed);

      if (_activeDevice?.address == null) return false;
      final result = await star.StarPrnt.sendCommands(
        portName: _activeDevice!.address!,
        emulation: _starEmulation.text,
        printCommands: commands,
      );
      return result.toString().contains('Success');
    } catch (e) {
      debugPrint('Star financial summary print error: $e');
      return false;
    }
  }

  String _getTaxLetter(double rate) {
    if (rate >= 16.0) return 'A';
    if (rate > 0) return 'B';
    return 'C'; // Exempt
  }

  Map<double, Map<String, double>> _getTaxBreakdown(List<SaleItem> items) {
    final Map<double, Map<String, double>> breakdown = {};
    
    for (var item in items) {
      final rate = item.taxRateAtSale;
      final effectiveQty = (item.isWeighted && item.weight > 0)
          ? item.weight
          : item.quantity.toDouble();
      final total = double.parse((item.priceAtSale * effectiveQty).toStringAsFixed(2));
      
      double vat = 0;
      if (item.isTaxInclusiveAtSale) {
        if (rate > 0) {
          final taxable = double.parse((total / (1 + (rate / 100))).toStringAsFixed(2));
          vat = double.parse((total - taxable).toStringAsFixed(2));
        } else {
          vat = 0.0;
        }
      } else {
        vat = double.parse((total * (rate / 100)).toStringAsFixed(2));
      }
      
      if (!breakdown.containsKey(rate)) {
        breakdown[rate] = {'vat': 0.0, 'total': 0.0};
      }
      
      breakdown[rate]!['vat'] = double.parse((breakdown[rate]!['vat']! + vat).toStringAsFixed(2));
      breakdown[rate]!['total'] = double.parse((breakdown[rate]!['total']! + total).toStringAsFixed(2));
    }
    
    return breakdown;
  }

  PrinterType _parsePrinterType(String? typeStr) {
    switch (typeStr?.toLowerCase()) {
      case 'network':
        return PrinterType.network;
      case 'bluetooth':
        return PrinterType.bluetooth;
      case 'usb':
      default:
        return PrinterType.usb;
    }
  }

  PrinterModel _parsePrinterModel(String? modelStr) {
    switch (modelStr?.toLowerCase()) {
      case 'star':
        return PrinterModel.star;
      case 'system':
        return PrinterModel.system;
      case 'directsocket':
        return PrinterModel.directSocket;
      case 'generic':
      default:
        return PrinterModel.generic;
    }
  }

  String _formatZraSdcInvoiceNo(String? raw, {String? sdcId}) {
    if (raw == null || raw.trim().isEmpty || raw.trim() == 'PENDING' || raw.trim() == 'null') {
      return 'PENDING';
    }
    final trimmed = raw.trim();
    if (trimmed.contains('/') && (trimmed.toUpperCase().startsWith('INV') || trimmed.toUpperCase().startsWith('CN'))) {
      return trimmed;
    }
    if (trimmed.toUpperCase().startsWith('INV0') || trimmed.toUpperCase().startsWith('INV1/') || trimmed.toUpperCase().startsWith('INV/') || trimmed.toUpperCase().startsWith('CN')) {
      return trimmed;
    }
    final clean = trimmed.replaceFirst(RegExp(r'^(INV|CN)-0*'), '').replaceFirst(RegExp(r'^(INV|CN)-'), '');
    final sdcClean = (sdcId ?? '').replaceAll(RegExp(r'^SDC', caseSensitive: false), '');
    if (sdcClean.isNotEmpty) {
      return 'INV$sdcClean/$clean';
    }
    return 'INV1/$clean';
  }
}

