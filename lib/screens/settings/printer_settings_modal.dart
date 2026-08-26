import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:flutter_star_prnt/flutter_star_prnt.dart' as star;
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/barcode_service.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/models/models.dart';

class PrinterSettingsModal extends ConsumerStatefulWidget {
  const PrinterSettingsModal({super.key});

  @override
  ConsumerState<PrinterSettingsModal> createState() => _PrinterSettingsModalState();
}

class _PrinterSettingsModalState extends ConsumerState<PrinterSettingsModal> {
  List<PrinterDevice> _devices = [];
  bool _isScanning = false;
  PrinterType _selectedType = PrinterType.usb;
  PrinterModel _selectedModel = PrinterModel.generic;
  final star.StarEmulation _selectedEmulation = star.StarEmulation.StarPRNT;
  int _paperWidthMm = 80;
  String _lastScanned = 'Waiting for scan...';
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.100:9100');
  final TextEditingController _searchController = TextEditingController();
  String _filterQuery = '';

  // Cash Drawer Driver State
  bool _autoOpenCashDrawer = true;
  bool _openDrawerCashOnly = false;
  int _cashDrawerPin = 2;
  int _cashDrawerPulseOnMs = 50;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadConfig();
      _scan();
    });
  }

  @override
  void dispose() {
    _ipController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final db = ref.read(databaseServiceProvider);
    final config = await db.getStoreConfig();
    if (config != null && mounted) {
      setState(() {
        _paperWidthMm = config.paperWidthMm;
        _autoOpenCashDrawer = config.autoOpenCashDrawer;
        _openDrawerCashOnly = config.openDrawerCashOnly;
        _cashDrawerPin = config.cashDrawerPin;
        _cashDrawerPulseOnMs = config.cashDrawerPulseOnMs;
        if (config.defaultPrinterAddress != null) {
          _ipController.text = config.defaultPrinterAddress!;
        }
        if (config.defaultPrinterType != null) {
          _selectedType = _parsePrinterType(config.defaultPrinterType);
        }
        if (config.defaultPrinterModel != null) {
          _selectedModel = _parsePrinterModel(config.defaultPrinterModel);
        }
      });
    }
  }

  Future<void> _saveCashDrawerSettings() async {
    final db = ref.read(databaseServiceProvider);
    final config = await db.getStoreConfig();
    if (config != null) {
      config.autoOpenCashDrawer = _autoOpenCashDrawer;
      config.openDrawerCashOnly = _openDrawerCashOnly;
      config.cashDrawerPin = _cashDrawerPin;
      config.cashDrawerPulseOnMs = _cashDrawerPulseOnMs;
      await db.saveStoreConfig(config);
      ref.invalidate(storeConfigProvider);
    }
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

  Future<void> _scan() async {
    if (!mounted) return;
    setState(() => _isScanning = true);
    try {
      final devices = await ref.read(printerServiceProvider).scanPrinters(
        _selectedType, 
        model: _selectedModel,
      );
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan notice: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _selectPrinter(PrinterDevice device) async {
    final printerConfig = PrinterConfig(
      device: device, 
      type: _selectedType,
      model: _selectedModel,
      starEmulation: _selectedEmulation,
      paperWidthMm: _paperWidthMm,
    );

    ref.read(selectedPrinterProvider.notifier).state = printerConfig;

    // Connect immediately
    final printerService = ref.read(printerServiceProvider);
    await printerService.connect(
      device, 
      _selectedType, 
      model: _selectedModel, 
      starEmulation: _selectedEmulation,
      paperWidth: _paperWidthMm,
    );

    // Save to StoreConfig database
    try {
      final db = ref.read(databaseServiceProvider);
      final config = await db.getStoreConfig() ?? (StoreConfig()..businessName = 'Beleka Store'..terminalName = 'POS-01');
      config.defaultPrinterName = device.name;
      config.defaultPrinterAddress = device.address;
      config.defaultPrinterType = _selectedType.name;
      config.defaultPrinterModel = _selectedModel.name;
      config.paperWidthMm = _paperWidthMm;
      await db.saveStoreConfig(config);
    } catch (e) {
      debugPrint('Save printer config note: $e');
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.black, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Active printer set to: ${device.name}',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFC1F11D),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedPrinter = ref.watch(selectedPrinterProvider);

    // Listen for global barcode scans
    ref.listen(barcodeStreamProvider, (previous, next) {
      next.whenData((barcode) {
        if (mounted) setState(() => _lastScanned = barcode);
      });
    });

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 640,
        height: 780,
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 40,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.print_rounded, color: Color(0xFFC1F11D), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HARDWARE & PERIPHERALS',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'AUTO-LOAD PRINTER DRIVERS & BARCODE SCANNERS',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFC1F11D),
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Driver Model & Paper Size Selector
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PRINTER DRIVER ENGINE',
                            style: GoogleFonts.ibmPlexMono(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 1),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildModelChip('ESC/POS', PrinterModel.generic),
                              const SizedBox(width: 8),
                              _buildModelChip('STAR', PrinterModel.star),
                              const SizedBox(width: 8),
                              _buildModelChip('CUPS / OS', PrinterModel.system),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'THERMAL PAPER ROLL WIDTH (PRINT SIZE)',
                          style: GoogleFonts.ibmPlexMono(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 1),
                        ),
                        Text(
                          '${_paperWidthMm}MM ACTIVE',
                          style: GoogleFonts.ibmPlexMono(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFC1F11D), letterSpacing: 1),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ThermalPaperPreset.presets.map((preset) {
                        return _buildWidthChip(preset.label, preset.widthMm, preset.description);
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFC1F11D), size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${ThermalPaperPreset.fromWidth(_paperWidthMm).label}: ${ThermalPaperPreset.fromWidth(_paperWidthMm).description} (${ThermalPaperPreset.fromWidth(_paperWidthMm).columnCount} cols)',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 18),
            // Interface Selector
            if (_selectedModel != PrinterModel.system) ...[
              Text(
                'CONNECTION INTERFACE',
                style: GoogleFonts.ibmPlexMono(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildTypeChip('USB / DIRECT', PrinterType.usb),
                  const SizedBox(width: 8),
                  _buildTypeChip('NETWORK TCP/IP', PrinterType.network),
                  const SizedBox(width: 8),
                  _buildTypeChip('BLUETOOTH', PrinterType.bluetooth),
                  const Spacer(),
                  _buildRefreshButton(),
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SYSTEM OS / CUPS PRINTERS',
                    style: GoogleFonts.ibmPlexMono(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.4), letterSpacing: 1),
                  ),
                  _buildRefreshButton(),
                ],
              ),
            ],

            // Direct Network IP Input for Network Printers
            if (_selectedType == PrinterType.network && _selectedModel != PrinterModel.system) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: TextField(
                        controller: _ipController,
                        style: GoogleFonts.ibmPlexMono(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'e.g. 192.168.1.100:9100',
                          hintStyle: GoogleFonts.ibmPlexMono(color: Colors.white24, fontSize: 12),
                          border: InputBorder.none,
                          prefixIcon: const Icon(Icons.router, size: 16, color: Color(0xFFC1F11D)),
                          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final ip = _ipController.text.trim();
                      if (ip.isNotEmpty) {
                        _selectPrinter(PrinterDevice(name: 'Network Thermal POS ($ip)', address: ip));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC1F11D),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    child: Text('ATTACH IP', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 14),
            
            // Search / Filter Bar for long lists
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: TextField(
                controller: _searchController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                onChanged: (val) => setState(() => _filterQuery = val.trim()),
                decoration: InputDecoration(
                  hintText: 'Filter printers by name or address...',
                  hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
                  border: InputBorder.none,
                  prefixIcon: const Icon(Icons.search_rounded, size: 16, color: Colors.white38),
                  prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  suffixIcon: _filterQuery.isNotEmpty 
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 14, color: Colors.white38),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filterQuery = '');
                          },
                        ) 
                      : null,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Discovered Devices List
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                ),
                child: Builder(
                  builder: (context) {
                    final filteredDevices = _devices.where((d) {
                      if (_filterQuery.isEmpty) return true;
                      final q = _filterQuery.toLowerCase();
                      return d.name.toLowerCase().contains(q) || (d.address?.toLowerCase().contains(q) ?? false);
                    }).toList();

                    if (_devices.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isScanning ? Icons.sync_rounded : Icons.print_disabled_outlined, 
                              size: 40, 
                              color: _isScanning ? const Color(0xFFC1F11D) : Colors.white24,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _isScanning ? 'Scanning hardware interfaces...' : 'No printer devices found. Click REFRESH or enter Network IP above.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                            ),
                          ],
                        ),
                      );
                    }

                    if (filteredDevices.isEmpty) {
                      return Center(
                        child: Text(
                          'No printer matching "$_filterQuery"',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filteredDevices.length,
                      itemBuilder: (context, index) {
                        final device = filteredDevices[index];
                        final isSelected = selectedPrinter?.device.address == device.address;
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () => _selectPrinter(device),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFFC1F11D).withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.05),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _selectedModel == PrinterModel.system ? Icons.desktop_windows_rounded :
                                    _selectedType == PrinterType.usb ? Icons.usb_rounded : 
                                    _selectedType == PrinterType.network ? Icons.router_rounded : Icons.bluetooth_rounded,
                                    color: isSelected ? const Color(0xFFC1F11D) : Colors.white38,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          device.name,
                                          style: GoogleFonts.manrope(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: isSelected ? const Color(0xFFC1F11D) : Colors.white,
                                          ),
                                        ),
                                        Text(
                                          device.address ?? 'Direct port',
                                          style: GoogleFonts.ibmPlexMono(
                                            fontSize: 10,
                                            color: Colors.white38,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isSelected ? Icons.check_circle_rounded : Icons.touch_app_rounded,
                                          color: isSelected ? Colors.black : Colors.white38,
                                          size: 12,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isSelected ? 'ACTIVE' : 'SELECT',
                                          style: GoogleFonts.ibmPlexMono(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isSelected ? Colors.black : Colors.white60,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 18),
            
            // Barcode Scanner Live Hardware Test
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFC1F11D), size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'HARDWARE SCANNER (USB / BLUETOOTH)',
                          style: GoogleFonts.ibmPlexMono(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white30),
                        ),
                        Text(
                          _lastScanned,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: _lastScanned == 'Waiting for scan...' ? Colors.white24 : const Color(0xFFC1F11D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_lastScanned != 'Waiting for scan...')
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16, color: Colors.white38),
                      onPressed: () => setState(() => _lastScanned = 'Waiting for scan...'),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 18),
            
            // CASH DRAWER DRIVER & HARDWARE KICK SECTION
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.point_of_sale_rounded, color: Color(0xFFC1F11D), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'CASH DRAWER HARDWARE DRIVER (RJ11 / RJ12)',
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFC1F11D),
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _autoOpenCashDrawer,
                        onChanged: (v) {
                          setState(() => _autoOpenCashDrawer = v);
                          _saveCashDrawerSettings();
                        },
                        activeThumbColor: const Color(0xFFC1F11D),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Automatically trigger the electric kick pulse to pop open the cash drawer when a transaction is completed.',
                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                  ),
                  if (_autoOpenCashDrawer) ...[
                    const SizedBox(height: 14),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Only Kick for Cash / Split Payments',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            Text(
                              'Do not kick drawer on pure card/digital payments',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                            ),
                          ],
                        ),
                        Switch(
                          value: _openDrawerCashOnly,
                          onChanged: (v) {
                            setState(() => _openDrawerCashOnly = v);
                            _saveCashDrawerSettings();
                          },
                          activeThumbColor: const Color(0xFFC1F11D),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Connector Pin: ',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text('Pin 2 (Standard ESC/POS)', style: GoogleFonts.ibmPlexMono(fontSize: 10)),
                          selected: _cashDrawerPin == 2,
                          onSelected: (_) {
                            setState(() => _cashDrawerPin = 2);
                            _saveCashDrawerSettings();
                          },
                          selectedColor: const Color(0xFFC1F11D).withValues(alpha: 0.2),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: Text('Pin 5 (Alternative)', style: GoogleFonts.ibmPlexMono(fontSize: 10)),
                          selected: _cashDrawerPin == 5,
                          onSelected: (_) {
                            setState(() => _cashDrawerPin = 5);
                            _saveCashDrawerSettings();
                          },
                          selectedColor: const Color(0xFFC1F11D).withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Test Drawer Kick Button
                    SizedBox(
                      height: 42,
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final printerService = ref.read(printerServiceProvider);
                          final db = ref.read(databaseServiceProvider);
                          final config = await db.getStoreConfig();
                          
                          final ok = await printerService.openCashDrawer(
                            config: config,
                            pin: _cashDrawerPin,
                            pulseOnMs: _cashDrawerPulseOnMs,
                          );

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(
                                      ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                      color: ok ? const Color(0xFFC1F11D) : Colors.orangeAccent,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        ok 
                                          ? '✓ Kick pulse sent! Cash drawer should open.'
                                          : '⚠️ Kick pulse sent to hardware driver. Ensure printer cable is connected to cash drawer.',
                                      ),
                                    ),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF1A1A1F),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.bolt_rounded, color: Color(0xFFC1F11D), size: 18),
                        label: Text(
                          '⚡ TEST CASH DRAWER (KICK NOW)',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5, color: const Color(0xFFC1F11D)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFFC1F11D).withValues(alpha: 0.4)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 18),
            
            // Test Print Action Button
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  final printerService = ref.read(printerServiceProvider);
                  final db = ref.read(databaseServiceProvider);
                  final config = await db.getStoreConfig();

                  final sampleTransaction = SaleTransaction(
                    totalAmount: 45.0,
                    paymentMethod: 'Cash',
                    subtotal: 38.79,
                    taxAmount: 6.21,
                    tenderedAmount: 50.0,
                    changeAmount: 5.0,
                    cashierName: 'Admin',
                  );

                  final sampleItems = [
                    SaleItem(productId: 1, productName: 'Sample Retail Item A', priceAtSale: 25.0, quantity: 1),
                    SaleItem(productId: 2, productName: 'Mineral Water 500ml', priceAtSale: 10.0, quantity: 2),
                  ];
                  
                  final success = await printerService.printReceipt(sampleTransaction, sampleItems, config: config);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(success ? '✓ Receipt sent to thermal printer successfully!' : '✗ Printing failed - please check connection.'),
                        backgroundColor: success ? const Color(0xFFC1F11D) : Colors.redAccent,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC1F11D),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.receipt_long_rounded, size: 18, color: Colors.black),
                    const SizedBox(width: 8),
                    Text(
                      'TEST PRINT THERMAL RECEIPT', 
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900, letterSpacing: 1, color: Colors.black),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, PrinterType type) {
    final isSelected = _selectedType == type;
    return InkWell(
      onTap: () {
        setState(() => _selectedType = type);
        _scan();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC1F11D).withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFC1F11D).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexMono(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isSelected ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }

  Widget _buildModelChip(String label, PrinterModel model) {
    final isSelected = _selectedModel == model;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedModel = model;
          _devices = [];
        });
        _scan();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC1F11D).withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFFC1F11D).withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.ibmPlexMono(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: isSelected ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }

  Future<void> _selectPaperWidth(int width) async {
    setState(() => _paperWidthMm = width);
    ref.read(printerServiceProvider).setPaperWidth(width);

    final current = ref.read(selectedPrinterProvider);
    if (current != null) {
      ref.read(selectedPrinterProvider.notifier).state = PrinterConfig(
        device: current.device,
        type: current.type,
        model: current.model,
        starEmulation: current.starEmulation,
        paperWidthMm: width,
      );
    }

    try {
      final db = ref.read(databaseServiceProvider);
      final config = await db.getStoreConfig() ?? (StoreConfig()..businessName = 'Beleka Store'..terminalName = 'POS-01');
      config.paperWidthMm = width;
      await db.saveStoreConfig(config);
    } catch (e) {
      debugPrint('Save paper width notice: $e');
    }
  }

  Widget _buildWidthChip(String label, int width, String description) {
    final isSelected = _paperWidthMm == width;
    return InkWell(
      onTap: () => _selectPaperWidth(width),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC1F11D).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.crop_portrait_rounded,
              color: isSelected ? const Color(0xFFC1F11D) : Colors.white24,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? const Color(0xFFC1F11D) : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRefreshButton() {
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: _isScanning ? null : _scan,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFC1F11D),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        child: _isScanning 
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.refresh, size: 14, color: Colors.black),
                const SizedBox(width: 4),
                Text('REFRESH', style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 10)),
              ],
            ),
      ),
    );
  }
}
