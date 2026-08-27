import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils.dart';
import 'package:flutter_star_prnt/flutter_star_prnt.dart' as star;
import 'package:beleka_pos/models/models.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
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
      widthMm: 58,
      label: '58 mm',
      description: 'Small POS, kiosks, mobile/small receipts',
      columnCount: 32,
      logoPixelWidth: 240,
      escPosSize: PaperSize.mm58,
      qrSize: QRSize.Size3,
    ),
    ThermalPaperPreset(
      widthMm: 76,
      label: '76 mm',
      description: 'Less common, some older/business POS',
      columnCount: 40,
      logoPixelWidth: 300,
      escPosSize: PaperSize.mm80,
      qrSize: QRSize.Size3,
    ),
    ThermalPaperPreset(
      widthMm: 80,
      label: '80 mm',
      description: 'Standard retail POS, supermarkets, restaurants',
      columnCount: 48,
      logoPixelWidth: 384,
      escPosSize: PaperSize.mm80,
      qrSize: QRSize.Size4,
    ),
    ThermalPaperPreset(
      widthMm: 110,
      label: '110 mm',
      description: 'Specialized thermal printing',
      columnCount: 64,
      logoPixelWidth: 512,
      escPosSize: PaperSize.mm80,
      qrSize: QRSize.Size5,
    ),
    ThermalPaperPreset(
      widthMm: 112,
      label: '112 mm',
      description: 'Larger receipts/labels, specialized POS',
      columnCount: 68,
      logoPixelWidth: 540,
      escPosSize: PaperSize.mm80,
      qrSize: QRSize.Size5,
    ),
  ];

  static ThermalPaperPreset fromWidth(int mm) {
    return presets.firstWhere(
      (p) => p.widthMm == mm,
      orElse: () => presets[2], // 80mm default
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
        success = await _printerManager.connect(
          type: type,
          model: BluetoothPrinterInput(
            name: device.name,
            address: device.address!,
            isBle: true, 
          ),
        );
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

  /// Master Method to Print High-Fidelity Designed Thermal Receipt
  Future<bool> printReceipt(
    SaleTransaction transaction, 
    List<SaleItem> items, {
    StoreConfig? config,
    Customer? customer,
  }) async {
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
      final is58 = preset.widthMm <= 58;
      final colCount = preset.columnCount;
      final profile = await CapabilityProfile.load();
      final generator = Generator(preset.escPosSize, profile);
      List<int> bytes = [];

      // 0. Hardware Reset Init Command (ESC @)
      bytes += generator.reset();

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

      // 1. Dithered Store Logo
      String? logoToPrint = config?.logoPath;
      if (logoToPrint == null || !File(logoToPrint).existsSync()) {
        logoToPrint = 'assets/images/logo.png';
      }

      try {
        late Uint8List logoBytes;
        if (logoToPrint == 'assets/images/logo.png') {
          final byteData = await rootBundle.load('assets/images/logo.png');
          logoBytes = byteData.buffer.asUint8List();
        } else {
          logoBytes = await File(logoToPrint).readAsBytes();
        }

        final img.Image? baseImage = img.decodeImage(logoBytes);
        if (baseImage != null) {
          final int targetWidth = preset.logoPixelWidth;
          final img.Image resized = img.copyResize(baseImage, width: targetWidth);
          final img.Image monochrome = img.grayscale(resized);
          bytes += generator.image(monochrome, align: PosAlign.center);
          bytes += generator.feed(1);
        }
      } catch (e) {
        debugPrint('Thermal logo print notice: $e');
      }

      // 2. Company Name & Branch Header
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
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

      bytes += generator.text(
        'BRANCH: $branchName',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
        ),
      );

      if (config?.address != null && config!.address!.isNotEmpty) {
        bytes += generator.text(config.address!, styles: const PosStyles(align: PosAlign.center));
      }
      if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) {
        bytes += generator.text('Tel: ${config.contactNumber!}', styles: const PosStyles(align: PosAlign.center));
      }
      if (config?.tpin != null && config!.tpin!.isNotEmpty) {
        bytes += generator.text('TPIN: ${config.tpin!}', styles: const PosStyles(align: PosAlign.center, bold: true));
      }

      final isFiscalApproved = transaction.zraStatus == 'APPROVED' &&
                               transaction.zraMarkId != null &&
                               transaction.zraMarkId!.isNotEmpty &&
                               transaction.zraMarkId != 'PENDING';

      final receiptTitle = transaction.isCreditNote
          ? 'ZRA FISCAL CREDIT NOTE'
          : (isFiscalApproved ? 'TAX INVOICE / OFFICIAL RECEIPT' : 'CUSTOMER SALES SLIP');

      bytes += generator.feed(1);
      bytes += generator.text(preset.doubleDivider);
      bytes += generator.text(
        receiptTitle,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      if (transaction.isCreditNote && transaction.orgInvoiceNo != null) {
        bytes += generator.text('ORIGINAL SDC INV: ${transaction.orgInvoiceNo}', styles: const PosStyles(align: PosAlign.center, bold: true));
        if (transaction.creditNoteReason != null) {
          bytes += generator.text('REASON: ${transaction.creditNoteReason}', styles: const PosStyles(align: PosAlign.center));
        }
      }
      bytes += generator.text(preset.doubleDivider);

      // 3. Receipt Metadata & Attended By
      final dateOnlyStr = DateFormat('dd/MM/yyyy').format(transaction.timestamp);
      final timeOnlyStr = DateFormat('HH:mm:ss').format(transaction.timestamp);
      final receiptNo = transaction.isCreditNote ? 'CN-#${transaction.id.toString().padLeft(8, '0')}' : '#${transaction.id.toString().padLeft(8, '0')}';
      final cashier = transaction.cashierName.isNotEmpty ? transaction.cashierName : 'Staff';
      
      bytes += generator.text(_formatRow2('RECEIPT: $receiptNo', '$dateOnlyStr $timeOnlyStr', colCount), styles: const PosStyles(bold: true));
      bytes += generator.text(_formatRow2('Cashier: $cashier', 'Terminal: ${transaction.terminalName ?? config?.terminalName ?? "POS-01"}', colCount));

      if (transaction.customerTpin != null && transaction.customerTpin!.isNotEmpty) {
        bytes += generator.text(_formatRow2('BUYER TPIN: ${transaction.customerTpin}', '', colCount), styles: const PosStyles(bold: true));
        if (transaction.customerBusinessName != null && transaction.customerBusinessName!.isNotEmpty) {
          bytes += generator.text(_formatRow2('BUYER NAME: ${transaction.customerBusinessName}', '', colCount));
        }
      } else if (customer != null) {
        bytes += generator.text(_formatRow2('Customer: ${customer.name}', customer.phoneNumber, colCount));
      }

      bytes += generator.text(preset.singleDivider);

      // 4. Line Items Table Header
      if (is58) {
        bytes += generator.text(_formatRow3('ITEM', 'QTY', 'TOTAL', colCount), styles: const PosStyles(bold: true));
      } else {
        bytes += generator.text(_formatRow4('ITEM DESCRIPTION', 'QTY', 'PRICE', 'TOTAL', colCount), styles: const PosStyles(bold: true));
      }
      bytes += generator.text(preset.singleDivider);

      // 5. Line Items Rows
      for (var item in items) {
        final taxLetter = _getTaxLetter(item.taxRateAtSale);
        final itemTotal = item.priceAtSale * item.quantity;
        final totalFormatted = CurrencyFormatter.format(itemTotal, currency);

        if (is58) {
          bytes += generator.text(item.productName.toUpperCase(), styles: const PosStyles(bold: true));
          bytes += generator.text(_formatRow3(
            '  @ ${CurrencyFormatter.format(item.priceAtSale, currency)}',
            '${item.quantity}x',
            '$totalFormatted $taxLetter',
            colCount,
          ));
        } else {
          bytes += generator.text(_formatRow4(
            item.productName.toUpperCase(),
            '${item.quantity}',
            CurrencyFormatter.format(item.priceAtSale, currency),
            '$totalFormatted $taxLetter',
            colCount,
          ));
        }
      }

      bytes += generator.text(preset.singleDivider);

      // 6. Financial Summary
      bytes += generator.text(_formatRow2('SUBTOTAL (NET)', CurrencyFormatter.format(transaction.subtotal, currency), colCount));

      if (transaction.discountAmount > 0) {
        bytes += generator.text(_formatRow2('DISCOUNT', '-${CurrencyFormatter.format(transaction.discountAmount, currency)}', colCount));
      }

      if (transaction.taxAmount > 0) {
        final taxLabel = (config?.businessTaxType == 'TURNOVER_TAX') ? 'TURNOVER TAX (INCL)' : 'TOTAL VAT (INCLUDED)';
        bytes += generator.text(_formatRow2(taxLabel, CurrencyFormatter.format(transaction.taxAmount, currency), colCount));
      }

      bytes += generator.feed(1);
      bytes += generator.text(preset.doubleDivider);

      // Grand Total Highlight
      bytes += generator.text(
        _formatRow2('TOTAL DUE', CurrencyFormatter.format(transaction.totalAmount, currency), (colCount / 2).floor()),
        styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
      );

      bytes += generator.text(preset.doubleDivider);

      // 7. Payment Tender Details
      bytes += generator.text(_formatRow2('PAYMENT METHOD', transaction.paymentMethod.toUpperCase(), colCount), styles: const PosStyles(bold: true));

      if (transaction.paymentMethod.toUpperCase() == 'CASH') {
        bytes += generator.text(_formatRow2('Cash Tendered', CurrencyFormatter.format(transaction.tenderedAmount > 0 ? transaction.tenderedAmount : transaction.totalAmount, currency), colCount));
        bytes += generator.text(_formatRow2('Change Returned', CurrencyFormatter.format(transaction.changeAmount, currency), colCount), styles: const PosStyles(bold: true));
      }

      // 8. Tax Summary Table
      bytes += generator.feed(1);
      bytes += generator.text('TAX SUMMARY BREAKDOWN', styles: const PosStyles(bold: true));
      bytes += generator.text(_formatRow3('CODE / RATE', 'TAX AMT', 'TOTAL', colCount), styles: const PosStyles(bold: true));

      final breakdown = _getTaxBreakdown(items);
      breakdown.forEach((rate, values) {
        final letter = _getTaxLetter(rate);
        bytes += generator.text(_formatRow3(
          '$letter (${rate.toStringAsFixed(0)}%)',
          CurrencyFormatter.formatTaxPrecision(values['vat']!, currency),
          CurrencyFormatter.format(values['total']!, currency),
          colCount,
        ));
      });

      // 9. SDC / ZRA Smart Invoice Compliance Block
      final dateFormatted = DateFormat('dd/MM/yyyy').format(transaction.timestamp);
      final timeFormatted = DateFormat('HH:mm:ss').format(transaction.timestamp);
      final sdcIdStr = (transaction.zraSdcId != null && transaction.zraSdcId!.isNotEmpty)
          ? transaction.zraSdcId!
          : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : 'PENDING');
      final sdcInvNoStr = _formatZraSdcInvoiceNo(transaction.zraReceiptNumber);
      final signatureStr = (transaction.zraMarkId != null && transaction.zraMarkId!.isNotEmpty)
          ? transaction.zraMarkId!
          : 'PENDING';
      final internalDataStr = (transaction.zraInternalData != null && transaction.zraInternalData!.isNotEmpty)
          ? transaction.zraInternalData!
          : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');

      bytes += generator.feed(1);
      bytes += generator.text(preset.singleDivider);

      if (isFiscalApproved) {
        bytes += generator.text(
          '*** ZRA FISCAL CONTROL DATA ***',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        bytes += generator.text(preset.singleDivider);
        bytes += generator.text(_formatRow2('Date:', dateFormatted, colCount));
        bytes += generator.text(_formatRow2('Time:', timeFormatted, colCount));
        bytes += generator.text(_formatRow2('SDC Id:', sdcIdStr, colCount));
        bytes += generator.text(_formatRow2('SDC Invoice No:', sdcInvNoStr, colCount));
        bytes += generator.text(_formatRow2('Signature:', signatureStr, colCount));
        bytes += generator.text(_formatRow2('Internal Data:', internalDataStr, colCount));
        bytes += generator.text(_formatRow2('Invoice Type:', transaction.zraInvoiceType ?? 'Normal Sale', colCount));
        bytes += generator.text(preset.singleDivider);

        // Print Live ZRA Smart Invoice Verification QR Code
        final zraQrData = (transaction.zraQrCode != null && transaction.zraQrCode!.isNotEmpty)
            ? transaction.zraQrCode!
            : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcIdStr&rcpt=$sdcInvNoStr';
        bytes += generator.feed(1);
        bytes += generator.qrcode(
          zraQrData,
          size: preset.qrSize,
        );
        bytes += generator.feed(1);
        bytes += generator.text(
          'Scan QR Code to Verify on ZRA Portal',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
      } else {
        bytes += generator.text(
          '*** OFFLINE TRANSACTION - FISCAL PENDING ***',
          styles: const PosStyles(align: PosAlign.center, bold: true),
        );
        bytes += generator.text(
          'Official ZRA Smart Invoice will sync automatically',
          styles: const PosStyles(align: PosAlign.center),
        );
        bytes += generator.text(preset.singleDivider);
      }

      // 10. Customer Friendly Footer
      bytes += generator.feed(1);
      bytes += generator.text(preset.doubleDivider);
      bytes += generator.text(
        'THANK YOU FOR SHOPPING WITH US!',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        'PLEASE VISIT US AGAIN',
        styles: const PosStyles(align: PosAlign.center),
      );
      bytes += generator.text('Goods sold are returnable within 7 days with valid receipt.', styles: const PosStyles(align: PosAlign.center));
      if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) {
        bytes += generator.text('Helpline: ${config.contactNumber!}', styles: const PosStyles(align: PosAlign.center));
      }
      bytes += generator.text('*** BELEKA POS RETAIL OS ***', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(preset.doubleDivider);
      
      bytes += generator.feed(3);
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
    final currentPreset = preset ?? activePreset;
    final currency = config?.currencySymbol ?? 'K';
    final paperSize = currentPreset.escPosSize;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];

    final colCount = currentPreset.columnCount;
    final date = (reportData['date'] is DateTime) ? reportData['date'] as DateTime : DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(date);

    try {
      bytes += generator.reset();
      bytes += generator.feed(1);

      // Store Header
      bytes += generator.text(
        config?.businessName ?? 'BELEKA RETAIL STORE',
        styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
      );
      if (config?.tpin != null) {
        bytes += generator.text('TPIN: ${config!.tpin!}', styles: const PosStyles(align: PosAlign.center, bold: true));
      }
      bytes += generator.text('SDC ID: ${config?.sdcId ?? "SDC00300000014"}', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text('BRANCH CODE (bhfId): ${config?.bhfId ?? "00"}', styles: const PosStyles(align: PosAlign.center));

      bytes += generator.feed(1);
      bytes += generator.text(currentPreset.doubleDivider);
      bytes += generator.text('ZRA FISCAL DAY SUMMARY (Z-REPORT)', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('REPORT DATE: $dateStr', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.text(currentPreset.doubleDivider);

      // SDC Invoices Count and Range
      bytes += generator.text(_formatRow2('TOTAL TRANSACTIONS', '${reportData["totalTransactions"] ?? 0}', colCount));
      bytes += generator.text(_formatRow2('NORMAL INVOICES', '${reportData["normalInvoicesCount"] ?? 0}', colCount));
      bytes += generator.text(_formatRow2('CREDIT NOTES (REFUNDS)', '${reportData["creditNotesCount"] ?? 0}', colCount));
      bytes += generator.text(_formatRow2('FIRST SDC INVOICE', '${reportData["firstSdcReceipt"] ?? "N/A"}', colCount));
      bytes += generator.text(_formatRow2('LAST SDC INVOICE', '${reportData["lastSdcReceipt"] ?? "N/A"}', colCount));

      bytes += generator.text(currentPreset.singleDivider);
      bytes += generator.text('TAX CATEGORIZATION BREAKDOWN', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text(currentPreset.singleDivider);

      // Tax A (16% VAT)
      final taxATaxable = (reportData['taxA16Taxable'] as num?)?.toDouble() ?? 0.0;
      final taxAVat = (reportData['taxA16Vat'] as num?)?.toDouble() ?? 0.0;
      bytes += generator.text(_formatRow2('TAX A (16.0% VAT) TAXABLE', CurrencyFormatter.format(taxATaxable, currency), colCount));
      bytes += generator.text(_formatRow2('TAX A (16.0% VAT) TAX AMOUNT', CurrencyFormatter.format(taxAVat, currency), colCount), styles: const PosStyles(bold: true));

      // Tax B (0.0% Zero-Rated)
      final taxBTaxable = (reportData['taxB0Taxable'] as num?)?.toDouble() ?? 0.0;
      bytes += generator.text(_formatRow2('TAX B (0.0% ZERO-RATED)', CurrencyFormatter.format(taxBTaxable, currency), colCount));

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

      bytes += generator.text(_formatRow2('NET TAXABLE SALES', CurrencyFormatter.format(netSales, currency), colCount));
      bytes += generator.text(_formatRow2('TOTAL TAX COLLECTED', CurrencyFormatter.format(totalTax, currency), colCount), styles: const PosStyles(bold: true));
      bytes += generator.text(
        _formatRow2('GROSS SALES (INCL)', CurrencyFormatter.format(grossSales, currency), (colCount / 2).floor()),
        styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
      );

      bytes += generator.text(currentPreset.doubleDivider);
      bytes += generator.feed(1);
      bytes += generator.text('*** END OF ZRA FISCAL Z-REPORT ***', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.feed(3);
      bytes += generator.cut();

      return await _sendBytes(bytes);
    } catch (e) {
      debugPrint('ZRA Fiscal Z-Report print error: $e');
      return false;
    }
  }

  String _formatRow2(String left, String right, int totalWidth) {
    if (left.length + right.length + 1 > totalWidth) {
      final maxLeft = totalWidth - right.length - 1;
      if (maxLeft > 0) {
        left = left.substring(0, maxLeft);
      }
    }
    final spaces = totalWidth - left.length - right.length;
    return left + (' ' * (spaces > 0 ? spaces : 1)) + right;
  }

  String _formatRow3(String col1, String col2, String col3, int totalWidth) {
    int w1 = (totalWidth * 0.45).floor();
    int w2 = (totalWidth * 0.20).floor();
    int w3 = totalWidth - w1 - w2;

    String c1 = col1.length > w1 ? col1.substring(0, w1) : col1.padRight(w1);
    String c2 = col2.padLeft(w2);
    String c3 = col3.padLeft(w3);
    return '$c1$c2$c3';
  }

  String _formatRow4(String col1, String col2, String col3, String col4, int totalWidth) {
    int w1 = (totalWidth * 0.40).floor();
    int w2 = (totalWidth * 0.14).floor();
    int w3 = (totalWidth * 0.22).floor();
    int w4 = totalWidth - w1 - w2 - w3;

    String c1 = col1.length > w1 ? col1.substring(0, w1) : col1.padRight(w1);
    String c2 = col2.padLeft(w2);
    String c3 = col3.padLeft(w3);
    String c4 = col4.padLeft(w4);
    return '$c1$c2$c3$c4';
  }

  Future<bool> printDailySummary({
    required Map<String, double> stats,
    required List<Map<String, dynamic>> topProducts,
    required Map<String, double> paymentDist,
    StoreConfig? config,
  }) async {
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

      final currency = config?.currencySymbol ?? 'K';

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text('DAILY X-REPORT');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.text(config?.businessName ?? 'BELEKA POS');
      if (config?.address != null) bytes += generator.text(config!.address!);
      if (config?.taxId != null) bytes += generator.text('VAT ID: ${config!.taxId!}');
      bytes += generator.text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
      bytes += generator.feed(1);
      bytes += generator.text(preset.doubleDivider);

      final todayCount = (stats['todayCount'] ?? 0).isNaN ? 0 : (stats['todayCount'] ?? 0).toInt();
      final todayRevenue = (stats['todayRevenue'] ?? 0).isNaN ? 0.0 : stats['todayRevenue']!;
      final todayTax = (stats['todayTax'] ?? 0).isNaN ? 0.0 : stats['todayTax']!;
      final netSales = todayRevenue - todayTax;

      bytes += generator.text(_formatRow2('Transactions', '$todayCount', colCount));
      bytes += generator.text(_formatRow2('Gross Revenue', CurrencyFormatter.format(todayRevenue, currency), colCount), styles: const PosStyles(bold: true));
      bytes += generator.text(_formatRow2('Total VAT', CurrencyFormatter.format(todayTax, currency), colCount));
      bytes += generator.text(_formatRow2('Net Sales', CurrencyFormatter.format(netSales, currency), colCount));
      
      bytes += generator.feed(1);
      bytes += generator.text('PAYMENT METHODS', styles: const PosStyles(bold: true));
      double grandTotal = 0.0;
      paymentDist.forEach((method, amount) {
        final val = amount.isNaN ? 0.0 : amount;
        grandTotal += val;
        bytes += generator.text(_formatRow2(method.toUpperCase(), CurrencyFormatter.format(val, currency), colCount));
      });
      bytes += generator.text(preset.singleDivider);
      bytes += generator.text(_formatRow2('TOTAL COLLECTED', CurrencyFormatter.format(grandTotal, currency), colCount), styles: const PosStyles(bold: true));

      bytes += generator.feed(1);
      bytes += generator.text('TOP PRODUCTS', styles: const PosStyles(bold: true));
      for (var p in topProducts.take(5)) {
        bytes += generator.text(_formatRow2(p['name'].toString(), p['quantity'].toString(), colCount));
      }
      
      bytes += generator.text(preset.doubleDivider);
      bytes += generator.feed(3);
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

      // Header
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text(periodTitle.toUpperCase());
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.text(config?.businessName ?? 'BELEKA POS');
      if (config?.address != null && config!.address!.isNotEmpty) bytes += generator.text(config.address!);
      if (config?.tpin != null && config!.tpin!.isNotEmpty) bytes += generator.text('TPIN: ${config.tpin}');
      bytes += generator.text('Period: $dateRangeLabel');
      bytes += generator.text('Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      bytes += generator.feed(1);
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
      if (cash > 0) bytes += generator.text(_formatRow2('Cash', CurrencyFormatter.format(cash, currency), colCount));
      if (card > 0) bytes += generator.text(_formatRow2('Card', CurrencyFormatter.format(card, currency), colCount));
      if (mobileMoney > 0) bytes += generator.text(_formatRow2('Mobile Money', CurrencyFormatter.format(mobileMoney, currency), colCount));
      bytes += generator.text(preset.singleDivider);
      bytes += generator.text(_formatRow2('TOTAL COLLECTED', CurrencyFormatter.format(revenue, currency), colCount), styles: const PosStyles(bold: true));

      bytes += generator.text(preset.doubleDivider);
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.text('*** END OF SUMMARY SLIP ***');
      bytes += generator.feed(3);
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
        return await _printerManager.send(type: _activeType!, bytes: bytes);
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
    final currency = config?.currencySymbol ?? 'K';
    var commands = star.PrintCommands();

    final preset = activePreset;

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
      } else {
        final byteData = await rootBundle.load('assets/images/logo.png');
        baseImage = img.decodeImage(byteData.buffer.asUint8List());
      }
      if (baseImage != null) {
        final img.Image resized = img.copyResize(baseImage, width: preset.logoPixelWidth);
        final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));
        commands.appendBitmapByte(byteData: pngBytes, diffusion: true, width: preset.logoPixelWidth);
      }
    } catch (e) {
      debugPrint('Star logo error: $e');
    }
    commands.append('\n');

    final companyName = (config?.businessName != null && config!.businessName.isNotEmpty 
        ? config.businessName 
        : 'BELEKA POS').toUpperCase();
    final branchName = (config?.terminalName != null && config!.terminalName.isNotEmpty 
        ? config.terminalName 
        : 'MAIN BRANCH').toUpperCase();
    final cashier = transaction.cashierName.isNotEmpty ? transaction.cashierName : 'Staff';

    commands.appendMultiple('$companyName\n', 1, 1);
    commands.appendEmphasis(true);
    commands.append('BRANCH: $branchName\n');
    commands.appendEmphasis(false);
    if (config?.address != null && config!.address!.isNotEmpty) commands.append('${config.address!}\n');
    if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) commands.append('Tel: ${config.contactNumber!}\n');
    final isFiscalApproved = transaction.zraStatus == 'APPROVED' &&
                             transaction.zraMarkId != null &&
                             transaction.zraMarkId!.isNotEmpty &&
                             transaction.zraMarkId != 'PENDING';

    final receiptTitle = transaction.isCreditNote
        ? 'ZRA FISCAL CREDIT NOTE'
        : (isFiscalApproved ? 'TAX INVOICE / OFFICIAL RECEIPT' : 'CUSTOMER SALES SLIP');

    commands.append('\n${preset.singleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('$receiptTitle\n');
    commands.appendEmphasis(false);
    commands.append('${preset.singleDivider}\n');

    commands.appendAlignment(star.StarAlignmentPosition.Left);
    final dateOnlyStr = DateFormat('dd/MM/yyyy').format(transaction.timestamp);
    final timeOnlyStr = DateFormat('HH:mm:ss').format(transaction.timestamp);
    commands.append('RECEIPT: #${transaction.id.toString().padLeft(8, '0')}\n');
    commands.append('Date: $dateOnlyStr $timeOnlyStr\n');
    commands.append('Attended by: $cashier\n');
    commands.append('Terminal: ${transaction.terminalName ?? config?.terminalName ?? "POS-01"}\n');
    if (customer != null) commands.append('Customer: ${customer.name} (${customer.phoneNumber})\n');
    commands.append('${preset.singleDivider}\n');
    
    for (var item in items) {
      final letter = _getTaxLetter(item.taxRateAtSale);
      String name = item.productName.toUpperCase();
      if (name.length > 18) name = '${name.substring(0, 15)}...';
      String price = CurrencyFormatter.format(item.priceAtSale * item.quantity, currency);
      commands.append('${name.padRight(19)} ${price.padLeft(10)} $letter\n');
    }

    commands.append('${preset.singleDivider}\n');
    commands.append('${"SUBTOTAL (NET)".padRight(18)}${CurrencyFormatter.format(transaction.subtotal, currency).padLeft(14)}\n');

    if (transaction.discountAmount > 0) {
      commands.append('${"DISCOUNT".padRight(18)}${"-${CurrencyFormatter.format(transaction.discountAmount, currency)}".padLeft(14)}\n');
    }

    if (transaction.taxAmount > 0) {
      final taxLabel = (config?.businessTaxType == 'TURNOVER_TAX') ? 'TURNOVER TAX' : 'TOTAL VAT';
      commands.append('${taxLabel.padRight(18)}${CurrencyFormatter.format(transaction.taxAmount, currency).padLeft(14)}\n');
    }

    commands.append('${preset.doubleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('${"TOTAL DUE".padRight(16)}${CurrencyFormatter.format(transaction.totalAmount, currency).padLeft(16)}\n');
    commands.appendEmphasis(false);
    commands.append('${preset.doubleDivider}\n');

    commands.append('Payment: ${transaction.paymentMethod.toUpperCase()}\n');
    if (transaction.paymentMethod.toUpperCase() == 'CASH') {
      commands.append('${"Cash Tendered".padRight(18)}${CurrencyFormatter.format(transaction.tenderedAmount > 0 ? transaction.tenderedAmount : transaction.totalAmount, currency).padLeft(14)}\n');
      commands.append('${"Change".padRight(18)}${CurrencyFormatter.format(transaction.changeAmount, currency).padLeft(14)}\n');
    }

    // Tax Summary Breakdown for Star
    commands.append('\nTAX SUMMARY BREAKDOWN\n');
    commands.append('${"CODE/RATE".padRight(12)}${"TAX AMT".padLeft(11)}${"TOTAL".padLeft(9)}\n');
    final starBreakdown = _getTaxBreakdown(items);
    starBreakdown.forEach((rate, values) {
      final letter = _getTaxLetter(rate);
      final rateStr = '$letter (${rate.toStringAsFixed(0)}%)'.padRight(12);
      final taxStr = CurrencyFormatter.formatTaxPrecision(values['vat']!, currency).padLeft(11);
      final totStr = CurrencyFormatter.format(values['total']!, currency).padLeft(9);
      commands.append('$rateStr$taxStr$totStr\n');
    });

    // ZRA Fiscal Control Block for Star
    final sdcIdStr = (transaction.zraSdcId != null && transaction.zraSdcId!.isNotEmpty)
        ? transaction.zraSdcId!
        : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : 'PENDING');
    final sdcInvNoStr = _formatZraSdcInvoiceNo(transaction.zraReceiptNumber);
    final signatureStr = (transaction.zraMarkId != null && transaction.zraMarkId!.isNotEmpty)
        ? transaction.zraMarkId!
        : 'PENDING';
    final internalDataStr = (transaction.zraInternalData != null && transaction.zraInternalData!.isNotEmpty)
        ? transaction.zraInternalData!
        : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');

    commands.append('\n${preset.singleDivider}\n');
    if (isFiscalApproved) {
      commands.appendEmphasis(true);
      commands.append('*** ZRA FISCAL CONTROL DATA ***\n');
      commands.appendEmphasis(false);
      commands.append('${preset.singleDivider}\n');
      commands.append('Date: $dateOnlyStr\n');
      commands.append('Time: $timeOnlyStr\n');
      commands.append('SDC Id: $sdcIdStr\n');
      commands.append('SDC Invoice No: $sdcInvNoStr\n');
      commands.append('Signature: $signatureStr\n');
      commands.append('Internal Data: $internalDataStr\n');
      commands.append('Invoice Type: ${transaction.zraInvoiceType ?? "Normal Sale"}\n');
      commands.append('${preset.singleDivider}\n');

      final zraQrData = (transaction.zraQrCode != null && transaction.zraQrCode!.isNotEmpty)
          ? transaction.zraQrCode!
          : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcIdStr&rcpt=$sdcInvNoStr';

      commands.appendAlignment(star.StarAlignmentPosition.Center);
      commands.append('Scan QR Code to Verify on ZRA Portal\n');
      commands.append('$zraQrData\n\n');
    } else {
      commands.appendEmphasis(true);
      commands.append('*** OFFLINE TRANSACTION - FISCAL PENDING ***\n');
      commands.appendEmphasis(false);
      commands.append('Official ZRA Smart Invoice will sync automatically\n');
      commands.append('${preset.singleDivider}\n\n');
    }

    commands.append('${preset.doubleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('THANK YOU FOR SHOPPING WITH US!\n');
    commands.appendEmphasis(false);
    commands.append('PLEASE VISIT US AGAIN\n');
    commands.append('Goods returnable within 7 days with receipt\n');
    if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) {
      commands.append('Helpline: ${config.contactNumber!}\n');
    }
    commands.append('*** BELEKA POS RETAIL OS ***\n');
    commands.append('${preset.doubleDivider}\n\n');
    
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

  Future<bool> _printWithSystem(
    SaleTransaction transaction, 
    List<SaleItem> items, {
    StoreConfig? config,
    Customer? customer,
  }) async {
    try {
      final doc = pw.Document();
      final currency = config?.currencySymbol ?? 'K';

      pw.ImageProvider? logoImage;
      String? logoPath = config?.logoPath;
      if (logoPath == null || !File(logoPath).existsSync()) {
        logoPath = 'assets/images/logo.png';
      }

      try {
        if (logoPath == 'assets/images/logo.png') {
          final byteData = await rootBundle.load('assets/images/logo.png');
          logoImage = pw.MemoryImage(byteData.buffer.asUint8List());
        } else {
          logoImage = pw.MemoryImage(await File(logoPath).readAsBytes());
        }
      } catch (e) {
        debugPrint('Logo load error for PDF: $e');
      }

      final rollFormat = pdf.PdfPageFormat(
        _paperWidthMm * pdf.PdfPageFormat.mm,
        double.infinity,
        marginAll: (_paperWidthMm <= 58 ? 3 : 4) * pdf.PdfPageFormat.mm,
      );
      final companyName = (config?.businessName != null && config!.businessName.isNotEmpty 
          ? config.businessName 
          : 'BELEKA POS').toUpperCase();
      final branchName = (config?.terminalName != null && config!.terminalName.isNotEmpty 
          ? config.terminalName 
          : (config?.branchName ?? 'MAIN BRANCH')).toUpperCase();
      final cashier = transaction.cashierName.isNotEmpty ? transaction.cashierName : 'Staff';

      final dateFormatted = DateFormat('dd/MM/yyyy').format(transaction.timestamp);
      final timeFormatted = DateFormat('HH:mm:ss').format(transaction.timestamp);
      final sdcIdStr = (transaction.zraSdcId != null && transaction.zraSdcId!.isNotEmpty)
          ? transaction.zraSdcId!
          : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : 'PENDING');
      final sdcInvNoStr = _formatZraSdcInvoiceNo(transaction.zraReceiptNumber);
      final signatureStr = (transaction.zraMarkId != null && transaction.zraMarkId!.isNotEmpty)
          ? transaction.zraMarkId!
          : 'PENDING';
      final internalDataStr = (transaction.zraInternalData != null && transaction.zraInternalData!.isNotEmpty)
          ? transaction.zraInternalData!
          : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');
      final zraQrData = (transaction.zraQrCode != null && transaction.zraQrCode!.isNotEmpty)
          ? transaction.zraQrCode!
          : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcIdStr&rcpt=$sdcInvNoStr';

      final isFiscalApproved = transaction.zraStatus == 'APPROVED' &&
                               transaction.zraMarkId != null &&
                               transaction.zraMarkId!.isNotEmpty &&
                               transaction.zraMarkId != 'PENDING';
      final receiptTitle = transaction.isCreditNote
          ? 'ZRA FISCAL CREDIT NOTE'
          : (isFiscalApproved ? 'TAX INVOICE / OFFICIAL RECEIPT' : 'CUSTOMER SALES SLIP');

      doc.addPage(
        pw.Page(
          pageFormat: rollFormat,
          margin: const pw.EdgeInsets.all(4 * pdf.PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Container(
                    height: 25 * pdf.PdfPageFormat.mm,
                    child: pw.Image(logoImage),
                  ),
                pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                pw.Text(
                  companyName, 
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
                ),
                pw.Text(
                  'BRANCH: $branchName', 
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
                ),
                if (config?.address != null && config!.address!.isNotEmpty) pw.Text(config.address!, style: const pw.TextStyle(fontSize: 8)),
                if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) pw.Text('Tel: ${config.contactNumber!}', style: const pw.TextStyle(fontSize: 8)),
                if (config?.tpin != null && config!.tpin!.isNotEmpty) pw.Text('TPIN: ${config.tpin!}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                pw.Text('================================'),
                pw.Text(receiptTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('================================'),
                
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('RECEIPT: #${transaction.id.toString().padLeft(8, '0')}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text('$dateFormatted $timeFormatted', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Cashier: $cashier', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text('Terminal: ${transaction.terminalName ?? config?.terminalName ?? "POS-01"}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (customer != null)
                  pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('Customer: ${customer.name} (${customer.phoneNumber})', style: const pw.TextStyle(fontSize: 8))),
                pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                pw.Divider(thickness: 0.5),

                ...items.map((item) {
                  final letter = _getTaxLetter(item.taxRateAtSale);
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1),
                    child: pw.Row(
                      children: [
                        pw.Expanded(flex: 6, child: pw.Text(item.productName.toUpperCase(), style: const pw.TextStyle(fontSize: 8))),
                        pw.Expanded(flex: 2, child: pw.Text('${item.quantity.toStringAsFixed(0)}x', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center)),
                        pw.Expanded(flex: 4, child: pw.Text('${CurrencyFormatter.format(item.priceAtSale * item.quantity, currency)} $letter', style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                  );
                }),

                pw.Divider(thickness: 0.5),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SUBTOTAL (NET)', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(CurrencyFormatter.format(transaction.subtotal, currency), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (transaction.discountAmount > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('DISCOUNT', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text('-${CurrencyFormatter.format(transaction.discountAmount, currency)}', style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                if (transaction.taxAmount > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text((config?.businessTaxType == 'TURNOVER_TAX') ? 'TURNOVER TAX' : 'TOTAL VAT', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(CurrencyFormatter.format(transaction.taxAmount, currency), style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                pw.Divider(thickness: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL DUE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text(CurrencyFormatter.format(transaction.totalAmount, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  ],
                ),
                pw.Divider(thickness: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Payment (${transaction.paymentMethod.toUpperCase()})', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(CurrencyFormatter.format(transaction.tenderedAmount > 0 ? transaction.tenderedAmount : transaction.totalAmount, currency), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (transaction.changeAmount > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('CHANGE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                      pw.Text(CurrencyFormatter.format(transaction.changeAmount, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    ],
                  ),

                pw.SizedBox(height: 1.5 * pdf.PdfPageFormat.mm),
                pw.Text('TAX SUMMARY BREAKDOWN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('CODE / RATE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    pw.Text('TAX AMT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  ],
                ),
                ...(() {
                  final pdfBreakdown = _getTaxBreakdown(items);
                  return pdfBreakdown.entries.map((entry) {
                    final letter = _getTaxLetter(entry.key);
                    return pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('$letter (${entry.key.toStringAsFixed(0)}%)', style: const pw.TextStyle(fontSize: 7)),
                        pw.Text(CurrencyFormatter.formatTaxPrecision(entry.value['vat']!, currency), style: const pw.TextStyle(fontSize: 7)),
                        pw.Text(CurrencyFormatter.format(entry.value['total']!, currency), style: const pw.TextStyle(fontSize: 7)),
                      ],
                    );
                  }).toList();
                })(),

                pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                pw.Text('--------------------------------'),
                if (isFiscalApproved) ...[
                  pw.Text('*** ZRA FISCAL CONTROL DATA ***', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('--------------------------------'),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Date:', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(dateFormatted, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Time:', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(timeFormatted, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('SDC Id:', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(sdcIdStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('SDC Invoice No:', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(sdcInvNoStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Signature:', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(signatureStr, style: const pw.TextStyle(fontSize: 6.5)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Internal Data:', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(internalDataStr, style: const pw.TextStyle(fontSize: 6.5)),
                    ],
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Invoice Type:', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(transaction.zraInvoiceType ?? 'Normal Sale', style: const pw.TextStyle(fontSize: 6.5)),
                    ],
                  ),
                  pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: zraQrData,
                    width: 58,
                    height: 58,
                  ),
                  pw.SizedBox(height: 1 * pdf.PdfPageFormat.mm),
                  pw.Text('Scan QR Code to Verify on ZRA Portal', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.5)),
                ] else ...[
                  pw.Text('*** OFFLINE TRANSACTION - FISCAL PENDING ***', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
                  pw.Text('Official ZRA Smart Invoice will sync automatically', style: const pw.TextStyle(fontSize: 6.5)),
                  pw.Text('--------------------------------'),
                ],

                pw.SizedBox(height: 2 * pdf.PdfPageFormat.mm),
                pw.Text('================================'),
                pw.Text('THANK YOU FOR SHOPPING WITH US!', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('PLEASE VISIT US AGAIN', style: const pw.TextStyle(fontSize: 7)),
                if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) 
                  pw.Text('Helpline: ${config.contactNumber!}', style: const pw.TextStyle(fontSize: 6)),
                pw.Text('*** BELEKA POS RETAIL OS ***', style: const pw.TextStyle(fontSize: 6)),
                pw.Text('================================'),
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
      final total = item.priceAtSale * item.quantity;
      
      double vat = 0;
      if (item.isTaxInclusiveAtSale) {
        vat = total - (total / (1 + (rate / 100)));
      } else {
        vat = total * (rate / 100);
      }
      
      if (!breakdown.containsKey(rate)) {
        breakdown[rate] = {'vat': 0.0, 'total': 0.0};
      }
      
      breakdown[rate]!['vat'] = breakdown[rate]!['vat']! + vat;
      breakdown[rate]!['total'] = breakdown[rate]!['total']! + total;
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

  String _formatZraSdcInvoiceNo(String? raw) {
    if (raw == null || raw.trim().isEmpty || raw.trim() == 'PENDING' || raw.trim() == 'null') {
      return 'PENDING';
    }
    final trimmed = raw.trim();
    if (trimmed.toUpperCase().startsWith('INV1/') || trimmed.toUpperCase().startsWith('INV/') || trimmed.toUpperCase().startsWith('CN')) {
      return trimmed;
    }
    final clean = trimmed.replaceFirst(RegExp(r'^(INV|CN)-0*'), '').replaceFirst(RegExp(r'^(INV|CN)-'), '');
    return 'INV1/$clean';
  }
}

