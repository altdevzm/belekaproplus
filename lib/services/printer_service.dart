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
import 'package:pdf/pdf.dart';
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

  Future<void> openCashDrawer() async {
    if (!_isConnected) return;

    if (_activeModel == PrinterModel.star) {
      try {
        star.PrintCommands commands = star.PrintCommands();
        commands.openCashDrawer(1);
        await star.StarPrnt.sendCommands(
          portName: _activeDevice!.address!,
          emulation: _starEmulation.text,
          printCommands: commands,
        );
      } catch (e) {
        debugPrint('Star cash drawer error: $e');
      }
      return;
    }

    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(_paperWidthMm == 58 ? PaperSize.mm58 : PaperSize.mm80, profile);
      List<int> bytes = generator.drawer();
      await _sendBytes(bytes);
    } catch (e) {
      debugPrint('Cash drawer kick error: $e');
    }
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
      final profile = await CapabilityProfile.load();
      final generator = Generator(preset.escPosSize, profile);
      List<int> bytes = [];

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
          : 'MAIN BRANCH').toUpperCase();

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

      bytes += generator.feed(1);
      bytes += generator.text(preset.singleDivider);
      bytes += generator.text(
        'TAX INVOICE / OFFICIAL RECEIPT',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(preset.singleDivider);

      // 3. Receipt Metadata & Attended By
      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(transaction.timestamp);
      final receiptNo = '#${transaction.id.toString().padLeft(8, '0')}';
      final cashier = transaction.cashierName.isNotEmpty ? transaction.cashierName : 'Staff';
      
      bytes += generator.row([
        PosColumn(text: 'RECEIPT: $receiptNo', width: is58 ? 6 : 6, styles: const PosStyles(bold: true)),
        PosColumn(text: dateStr, width: is58 ? 6 : 6, styles: const PosStyles(align: PosAlign.right)),
      ]);
      
      bytes += generator.row([
        PosColumn(text: 'Attended by: $cashier', width: is58 ? 6 : 6, styles: const PosStyles(bold: true)),
        PosColumn(text: 'Terminal: ${transaction.terminalName ?? config?.terminalName ?? "POS-01"}', width: is58 ? 6 : 6, styles: const PosStyles(align: PosAlign.right)),
      ]);

      if (customer != null) {
        bytes += generator.row([
          PosColumn(text: 'Customer: ${customer.name}', width: is58 ? 6 : 6),
          PosColumn(text: customer.phoneNumber, width: is58 ? 6 : 6, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.text(preset.singleDivider);

      // 4. Line Items Table Header
      if (is58) {
        bytes += generator.row([
          PosColumn(text: 'ITEM', width: 6, styles: const PosStyles(bold: true)),
          PosColumn(text: 'QTY', width: 2, styles: const PosStyles(align: PosAlign.center, bold: true)),
          PosColumn(text: 'TOTAL', width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
      } else if (preset.widthMm <= 76) {
        bytes += generator.row([
          PosColumn(text: 'ITEM', width: 5, styles: const PosStyles(bold: true)),
          PosColumn(text: 'QTY', width: 2, styles: const PosStyles(align: PosAlign.center, bold: true)),
          PosColumn(text: 'PRICE', width: 2, styles: const PosStyles(align: PosAlign.right, bold: true)),
          PosColumn(text: 'TOTAL', width: 3, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
      } else {
        bytes += generator.row([
          PosColumn(text: 'ITEM DESCRIPTION', width: 6, styles: const PosStyles(bold: true)),
          PosColumn(text: 'QTY', width: 2, styles: const PosStyles(align: PosAlign.center, bold: true)),
          PosColumn(text: 'PRICE', width: 2, styles: const PosStyles(align: PosAlign.right, bold: true)),
          PosColumn(text: 'TOTAL', width: 2, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
      }
      bytes += generator.text(preset.singleDivider);

      // 5. Line Items Rows
      for (var item in items) {
        final taxLetter = _getTaxLetter(item.taxRateAtSale);
        final itemTotal = item.priceAtSale * item.quantity;
        final totalFormatted = CurrencyFormatter.format(itemTotal, currency);

        if (is58) {
          bytes += generator.text(item.productName.toUpperCase(), styles: const PosStyles(bold: true));
          bytes += generator.row([
            PosColumn(text: '  @ ${CurrencyFormatter.format(item.priceAtSale, currency)}', width: 6),
            PosColumn(text: '${item.quantity}x', width: 2, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(text: '$totalFormatted $taxLetter', width: 4, styles: const PosStyles(align: PosAlign.right)),
          ]);
        } else if (preset.widthMm <= 76) {
          bytes += generator.row([
            PosColumn(text: item.productName.toUpperCase(), width: 5),
            PosColumn(text: '${item.quantity}', width: 2, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(text: CurrencyFormatter.format(item.priceAtSale, currency), width: 2, styles: const PosStyles(align: PosAlign.right)),
            PosColumn(text: '$totalFormatted $taxLetter', width: 3, styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);
        } else {
          bytes += generator.row([
            PosColumn(text: item.productName.toUpperCase(), width: 6),
            PosColumn(text: '${item.quantity}', width: 2, styles: const PosStyles(align: PosAlign.center)),
            PosColumn(text: CurrencyFormatter.format(item.priceAtSale, currency), width: 2, styles: const PosStyles(align: PosAlign.right)),
            PosColumn(text: '$totalFormatted $taxLetter', width: 2, styles: const PosStyles(align: PosAlign.right, bold: true)),
          ]);
        }
      }

      bytes += generator.text(preset.singleDivider);

      // 6. Financial Summary
      bytes += generator.row([
        PosColumn(text: 'SUBTOTAL', width: 6),
        PosColumn(text: CurrencyFormatter.format(transaction.subtotal, currency), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]);

      if (transaction.discountAmount > 0) {
        bytes += generator.row([
          PosColumn(text: 'DISCOUNT', width: 6),
          PosColumn(text: '-${CurrencyFormatter.format(transaction.discountAmount, currency)}', width: 6, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      if (transaction.taxAmount > 0) {
        bytes += generator.row([
          PosColumn(text: 'TOTAL VAT (INCLUDED)', width: 6),
          PosColumn(text: CurrencyFormatter.format(transaction.taxAmount, currency), width: 6, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }

      bytes += generator.feed(1);
      bytes += generator.text(preset.doubleDivider);

      // Grand Total Highlight
      bytes += generator.row([
        PosColumn(
          text: 'TOTAL DUE', 
          width: 5, 
          styles: const PosStyles(bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
        ),
        PosColumn(
          text: CurrencyFormatter.format(transaction.totalAmount, currency), 
          width: 7, 
          styles: const PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
        ),
      ]);

      bytes += generator.text(preset.doubleDivider);

      // 7. Payment Tender Details
      bytes += generator.row([
        PosColumn(text: 'PAYMENT METHOD', width: 6, styles: const PosStyles(bold: true)),
        PosColumn(text: transaction.paymentMethod.toUpperCase(), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);

      if (transaction.paymentMethod.toUpperCase() == 'CASH') {
        bytes += generator.row([
          PosColumn(text: 'Cash Tendered', width: 6),
          PosColumn(text: CurrencyFormatter.format(transaction.tenderedAmount, currency), width: 6, styles: const PosStyles(align: PosAlign.right)),
        ]);
        bytes += generator.row([
          PosColumn(text: 'Change Returned', width: 6, styles: const PosStyles(bold: true)),
          PosColumn(text: CurrencyFormatter.format(transaction.changeAmount, currency), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]);
      }

      // 8. Tax Summary Table
      bytes += generator.feed(1);
      bytes += generator.text('TAX SUMMARY BREAKDOWN', styles: const PosStyles(bold: true));
      bytes += generator.row([
        PosColumn(text: 'CODE / RATE', width: 4, styles: const PosStyles(bold: true)),
        PosColumn(text: 'VAT', width: 4, styles: const PosStyles(bold: true, align: PosAlign.center)),
        PosColumn(text: 'TOTAL', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);

      final breakdown = _getTaxBreakdown(items);
      breakdown.forEach((rate, values) {
        final letter = _getTaxLetter(rate);
        bytes += generator.row([
          PosColumn(text: '$letter (${rate.toStringAsFixed(0)}%)', width: 4),
          PosColumn(text: CurrencyFormatter.format(values['vat']!, currency), width: 4, styles: const PosStyles(align: PosAlign.center)),
          PosColumn(text: CurrencyFormatter.format(values['total']!, currency), width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]);
      });

      // 9. SDC / ZRA Smart Invoice Compliance
      bytes += generator.feed(1);
      bytes += generator.text('SDC FISCAL CONTROL DATA', styles: const PosStyles(bold: true));
      bytes += generator.row([
        PosColumn(text: 'SDC InvNo:', width: 4),
        PosColumn(text: 'INV${transaction.id.toString().padLeft(10, '0')}', width: 8, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: 'SDC Device ID:', width: 5),
        PosColumn(text: config?.sdcId ?? 'SDC00300000014', width: 7, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: 'MRC No:', width: 4),
        PosColumn(text: config?.mrcNo ?? 'WIS00013845', width: 8, styles: const PosStyles(align: PosAlign.right)),
      ]);

      // 10. QR Code Verification
      bytes += generator.feed(1);
      final qrPayload = 'https://zra.org.zm/verify?inv=${transaction.id}&amt=${transaction.totalAmount}&tpin=${config?.tpin ?? ""}';
      bytes += generator.qrcode(qrPayload, size: preset.qrSize, align: PosAlign.center);
      bytes += generator.text('SCAN TO VERIFY OFFICIAL RECEIPT', styles: const PosStyles(align: PosAlign.center, height: PosTextSize.size1));

      // 11. Customer Friendly Footer
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
    if (config?.tpin != null && config!.tpin!.isNotEmpty) commands.append('TPIN: ${config.tpin!}\n');
    commands.append('\n${preset.singleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('TAX INVOICE / OFFICIAL RECEIPT\n');
    commands.appendEmphasis(false);
    commands.append('${preset.singleDivider}\n');

    commands.appendAlignment(star.StarAlignmentPosition.Left);
    commands.append('RECEIPT: #${transaction.id.toString().padLeft(8, '0')}\n');
    commands.append('Date: ${DateFormat('yyyy-MM-dd HH:mm').format(transaction.timestamp)}\n');
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
    commands.append('${"SUBTOTAL".padRight(18)}${CurrencyFormatter.format(transaction.subtotal, currency).padLeft(14)}\n');

    if (transaction.taxAmount > 0) {
      commands.append('${"TOTAL VAT".padRight(18)}${CurrencyFormatter.format(transaction.taxAmount, currency).padLeft(14)}\n');
    }

    commands.append('${preset.doubleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('${"TOTAL".padRight(16)}${CurrencyFormatter.format(transaction.totalAmount, currency).padLeft(16)}\n');
    commands.appendEmphasis(false);
    commands.append('${preset.doubleDivider}\n');

    commands.append('Payment: ${transaction.paymentMethod.toUpperCase()}\n');
    if (transaction.paymentMethod.toUpperCase() == 'CASH') {
      commands.append('${"Cash Tendered".padRight(18)}${CurrencyFormatter.format(transaction.tenderedAmount, currency).padLeft(14)}\n');
      commands.append('${"Change".padRight(18)}${CurrencyFormatter.format(transaction.changeAmount, currency).padLeft(14)}\n');
    }

    commands.append('\n');
    commands.appendAlignment(star.StarAlignmentPosition.Center);
    commands.append('${preset.doubleDivider}\n');
    commands.appendEmphasis(true);
    commands.append('THANK YOU FOR SHOPPING WITH US!\n');
    commands.appendEmphasis(false);
    commands.append('PLEASE VISIT US AGAIN\n');
    commands.append('Goods returnable within 7 days with receipt\n');
    if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) {
      commands.append('Helpline: ${config.contactNumber!}\n');
    }
    commands.append('powered by Beleka POS Retail OS\n');
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

      final rollFormat = PdfPageFormat(
        _paperWidthMm * PdfPageFormat.mm,
        double.infinity,
        marginAll: (_paperWidthMm <= 58 ? 3 : 4) * PdfPageFormat.mm,
      );
      final companyName = (config?.businessName != null && config!.businessName.isNotEmpty 
          ? config.businessName 
          : 'BELEKA POS').toUpperCase();
      final branchName = (config?.terminalName != null && config!.terminalName.isNotEmpty 
          ? config.terminalName 
          : 'MAIN BRANCH').toUpperCase();
      final cashier = transaction.cashierName.isNotEmpty ? transaction.cashierName : 'Staff';

      doc.addPage(
        pw.Page(
          pageFormat: rollFormat,
          margin: const pw.EdgeInsets.all(4 * PdfPageFormat.mm),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImage != null)
                  pw.Container(
                    height: 25 * PdfPageFormat.mm,
                    child: pw.Image(logoImage),
                  ),
                pw.SizedBox(height: 2 * PdfPageFormat.mm),
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
                pw.SizedBox(height: 2 * PdfPageFormat.mm),
                pw.Text('--------------------------------'),
                pw.Text('TAX INVOICE / OFFICIAL RECEIPT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('--------------------------------'),
                
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('RECEIPT: #${transaction.id.toString().padLeft(8, '0')}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text(DateFormat('yyyy-MM-dd HH:mm').format(transaction.timestamp), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Attended by: $cashier', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                    pw.Text('Terminal: ${transaction.terminalName ?? config?.terminalName ?? "POS-01"}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (customer != null)
                  pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('Customer: ${customer.name}', style: const pw.TextStyle(fontSize: 8))),
                pw.SizedBox(height: 2 * PdfPageFormat.mm),
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
                    pw.Text('SUBTOTAL', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text(CurrencyFormatter.format(transaction.subtotal, currency), style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                if (transaction.taxAmount > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL VAT', style: const pw.TextStyle(fontSize: 8)),
                      pw.Text(CurrencyFormatter.format(transaction.taxAmount, currency), style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                pw.Divider(thickness: 1),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
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

                pw.SizedBox(height: 3 * PdfPageFormat.mm),
                pw.Container(
                  height: 20 * PdfPageFormat.mm,
                  width: 20 * PdfPageFormat.mm,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: 'https://zra.org.zm/verify?inv=${transaction.id}',
                  ),
                ),
                pw.SizedBox(height: 2 * PdfPageFormat.mm),
                pw.Text('--------------------------------'),
                pw.Text('THANK YOU FOR SHOPPING WITH US!', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text('PLEASE VISIT US AGAIN', style: const pw.TextStyle(fontSize: 7)),
                if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) 
                  pw.Text('Helpline: ${config.contactNumber!}', style: const pw.TextStyle(fontSize: 6)),
                pw.Text('Powered by Beleka POS Retail OS', style: const pw.TextStyle(fontSize: 6)),
                pw.Text('--------------------------------'),
              ],
            );
          },
        ),
      );

      if (_activeSystemPrinter != null) {
        return await pnt.Printing.directPrintPdf(
          printer: _activeSystemPrinter!,
          onLayout: (PdfPageFormat format) async => doc.save(),
          name: 'Receipt_${transaction.id}',
        );
      } else {
        return await pnt.Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => doc.save(),
          name: 'Receipt_${transaction.id}',
        );
      }
    } catch (e) {
      debugPrint('System print error: $e');
      return false;
    }
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
      final profile = await CapabilityProfile.load();
      final generator = Generator(_paperWidthMm == 58 ? PaperSize.mm58 : PaperSize.mm80, profile);
      List<int> bytes = [];

      final currency = config?.currencySymbol ?? 'K';

      bytes += generator.setStyles(const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2));
      bytes += generator.text('DAILY X-REPORT');
      bytes += generator.setStyles(const PosStyles(align: PosAlign.center));
      bytes += generator.text(config?.businessName ?? 'BELEKA POS');
      if (config?.address != null) bytes += generator.text(config!.address!);
      if (config?.taxId != null) bytes += generator.text('VAT ID: ${config!.taxId!}');
      bytes += generator.text(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()));
      bytes += generator.feed(1);
      bytes += generator.text('================================', styles: const PosStyles(bold: true));

      final todayCount = (stats['todayCount'] ?? 0).isNaN ? 0 : (stats['todayCount'] ?? 0).toInt();
      final todayRevenue = (stats['todayRevenue'] ?? 0).isNaN ? 0.0 : stats['todayRevenue']!;
      final todayTax = (stats['todayTax'] ?? 0).isNaN ? 0.0 : stats['todayTax']!;
      final netSales = todayRevenue - todayTax;

      bytes += generator.row([
        PosColumn(text: 'Transactions', width: 8),
        PosColumn(text: '$todayCount', width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Gross Revenue', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text: CurrencyFormatter.format(todayRevenue, currency), width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Total VAT', width: 8),
        PosColumn(text: CurrencyFormatter.format(todayTax, currency), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Net Sales', width: 8),
        PosColumn(text: CurrencyFormatter.format(netSales, currency), width: 4, styles: const PosStyles(align: PosAlign.right)),
      ]);
      
      bytes += generator.feed(1);
      bytes += generator.text('PAYMENT METHODS', styles: const PosStyles(bold: true));
      double grandTotal = 0.0;
      paymentDist.forEach((method, amount) {
        final val = amount.isNaN ? 0.0 : amount;
        grandTotal += val;
        bytes += generator.row([
          PosColumn(text: method.toUpperCase(), width: 8),
          PosColumn(text: CurrencyFormatter.format(val, currency), width: 4, styles: const PosStyles(align: PosAlign.right)),
        ]);
      });
      bytes += generator.text('--------------------------------');
      bytes += generator.row([
        PosColumn(text: 'TOTAL COLLECTED', width: 8, styles: const PosStyles(bold: true)),
        PosColumn(text: CurrencyFormatter.format(grandTotal, currency), width: 4, styles: const PosStyles(align: PosAlign.right, bold: true)),
      ]);

      bytes += generator.feed(1);
      bytes += generator.text('TOP PRODUCTS', styles: const PosStyles(bold: true));
      for (var p in topProducts.take(5)) {
        bytes += generator.row([
          PosColumn(text: p['name'].toString(), width: 9),
          PosColumn(text: p['quantity'].toString(), width: 3, styles: const PosStyles(align: PosAlign.right)),
        ]);
      }
      
      bytes += generator.text('================================', styles: const PosStyles(bold: true));
      bytes += generator.feed(3);
      bytes += generator.cut();

      return await _sendBytes(bytes);
    } catch (e) {
      debugPrint('Summary printing error: $e');
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
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(5 * PdfPageFormat.mm),
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
                pw.SizedBox(height: 3 * PdfPageFormat.mm),
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
                
                pw.SizedBox(height: 3 * PdfPageFormat.mm),
                pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('PAYMENT METHODS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                ...paymentDist.entries.map((e) => pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text(e.key.toUpperCase()), pw.Text(CurrencyFormatter.format(e.value, currency))],
                )),

                pw.SizedBox(height: 3 * PdfPageFormat.mm),
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
          onLayout: (PdfPageFormat format) async => doc.save(),
          name: 'Daily_Summary',
        );
      } else {
        return await pnt.Printing.layoutPdf(
          onLayout: (PdfPageFormat format) async => doc.save(),
          name: 'Daily_Summary',
        );
      }
    } catch (e) {
      debugPrint('Summary print error: $e');
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
}

