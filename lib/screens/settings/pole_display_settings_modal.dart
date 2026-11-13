import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/services/pole_display_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';

class PoleDisplaySettingsModal extends ConsumerStatefulWidget {
  const PoleDisplaySettingsModal({super.key});

  @override
  ConsumerState<PoleDisplaySettingsModal> createState() =>
      _PoleDisplaySettingsModalState();
}

class _PoleDisplaySettingsModalState
    extends ConsumerState<PoleDisplaySettingsModal> {
  late bool _enabled;
  late bool _showOnScreenPreview;
  late TextEditingController _portController;
  late TextEditingController _baudRateController;
  late TextEditingController _welcomeLine1Controller;
  late TextEditingController _welcomeLine2Controller;
  late TextEditingController _thankYouLine1Controller;
  late String _protocol;
  late int _columns;
  bool _isScanning = false;
  bool _isTesting = false;
  PoleDisplayTestResult? _testResult;
  List<PoleDisplayPortInfo> _discoveredPorts = [];

  final List<String> _commonPorts = const [
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    '/dev/ttyUSB0',
    '/dev/ttyACM0',
    '127.0.0.1:9002',
  ];

  final List<Map<String, String>> _protocols = const [
    {
      'id': 'esc_pos',
      'name': 'EPSON ESC/POS Standard VFD (DM-D110 / DM-D210 / USB-Serial)',
    },
    {
      'id': 'cd5220',
      'name': 'Partner Tech CD-5220 / Posiflex VFD Standard',
    },
    {
      'id': 'logic_controls',
      'name': 'Logic Controls / Bematech LD9000 / PD3000',
    },
    {
      'id': 'aedex',
      'name': 'AEDEX / Emax Serial Pole Display (!#1 / !#2)',
    },
    {
      'id': 'led8',
      'name': '8-Digit LED Numeric Display (ESC Q A — Price/Total/Change)',
    },
    {
      'id': 'raw_ascii',
      'name': 'Generic Raw ASCII 2-Line Stream (CR/LF)',
    },
  ];

  @override
  void initState() {
    super.initState();
    final service = ref.read(poleDisplayServiceProvider);
    final cfg = service.config;
    _enabled = cfg.enabled;
    _showOnScreenPreview = cfg.showOnScreenPreview;
    _portController = TextEditingController(text: cfg.port);
    _baudRateController = TextEditingController(text: cfg.baudRate.toString());
    _welcomeLine1Controller = TextEditingController(text: cfg.welcomeLine1);
    _welcomeLine2Controller = TextEditingController(text: cfg.welcomeLine2);
    _thankYouLine1Controller = TextEditingController(text: cfg.thankYouLine1);
    _protocol = _protocols.any((p) => p['id'] == cfg.protocol)
        ? cfg.protocol
        : 'esc_pos';
    _columns = (cfg.columns == 16 || cfg.columns == 8) ? cfg.columns : 20;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scanPorts();
    });
  }

  @override
  void dispose() {
    _portController.dispose();
    _baudRateController.dispose();
    _welcomeLine1Controller.dispose();
    _welcomeLine2Controller.dispose();
    _thankYouLine1Controller.dispose();
    super.dispose();
  }

  PoleDisplayConfig _buildDraftConfig() {
    return PoleDisplayConfig(
      enabled: _enabled,
      showOnScreenPreview: _showOnScreenPreview,
      port: _portController.text.trim(),
      baudRate: int.tryParse(_baudRateController.text.trim()) ?? 9600,
      protocol: _protocol,
      columns: _columns,
      rows: _columns == 8 ? 1 : 2,
      welcomeLine1: _welcomeLine1Controller.text.trim().isNotEmpty
          ? _welcomeLine1Controller.text.trim()
          : 'WELCOME TO OUR STORE',
      welcomeLine2: _welcomeLine2Controller.text.trim().isNotEmpty
          ? _welcomeLine2Controller.text.trim()
          : 'NEXT CUSTOMER PLEASE',
      thankYouLine1: _thankYouLine1Controller.text.trim().isNotEmpty
          ? _thankYouLine1Controller.text.trim()
          : 'THANK YOU!',
    );
  }

  Future<void> _scanPorts() async {
    if (!mounted) {
      return;
    }
    setState(() => _isScanning = true);
    try {
      final ports = await ref
          .read(poleDisplayServiceProvider)
          .scanAvailablePorts();
      if (mounted) {
        setState(() {
          _discoveredPorts = ports;
          _isScanning = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  Future<void> _autoDetectPort() async {
    setState(() => _isScanning = true);
    final detected = await ref
        .read(poleDisplayServiceProvider)
        .autoDetectPort();
    if (!mounted) {
      return;
    }
    setState(() => _isScanning = false);
    if (detected != null) {
      setState(() => _portController.text = detected.path);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Detected pole display port: ${detected.label} (${detected.path})',
          ),
          backgroundColor: const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _runTestFrame({
    required String line1,
    required String line2,
    required double numericValue,
    required int ledMode,
  }) async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final service = ref.read(poleDisplayServiceProvider);
    final res = await service.testDisplayConnection(
      testConfig: _buildDraftConfig(),
      line1: line1,
      line2: line2,
      numericValue: numericValue,
      ledMode: ledMode,
    );

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testResult = res;
      });
    }
  }

  Future<void> _save() async {
    final service = ref.read(poleDisplayServiceProvider);
    final newConfig = _buildDraftConfig();
    await service.saveConfig(newConfig);

    if (mounted) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Customer Pole Display configuration saved successfully!',
          ),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final storeConfig = ref.watch(storeConfigProvider).value;
    final cur = storeConfig?.currencySymbol ?? 'K';
    final service = ref.watch(poleDisplayServiceProvider);
    final liveFrame =
        ref.watch(livePoleDisplayFrameProvider).value ?? service.currentFrame;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Container(
        width: 640,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Modal Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark
                                ? primaryColor.withValues(alpha: 0.15)
                                : primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.tv_rounded,
                            color: primaryColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Customer Display (Pole Display)',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                'Shows customer total payable, amount tendered, change & item details',
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Divider(
                color: isDark
                    ? const Color(0xFF293548)
                    : const Color(0xFFE2E8F0),
                height: 1,
              ),
              const SizedBox(height: 16),

              // LIVE VFD POLE DISPLAY MONITOR PREVIEW
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF071318),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E5FF).withValues(alpha: 0.08),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _enabled
                                    ? const Color(0xFF00E676)
                                    : const Color(0xFFF59E0B),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'LIVE POLE DISPLAY READOUT (${_columns}x2 VFD MATRIX)',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF64FFDA),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'PORT: ${_portController.text.trim().isEmpty ? "SOFTWARE ONLY" : _portController.text.trim()}',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF030A0D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              liveFrame.line1.padRight(_columns),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF00F5D4),
                                letterSpacing: 2.0,
                                shadows: const [
                                  Shadow(
                                    color: Color(0xFF00E5FF),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              liveFrame.line2.padRight(_columns),
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF00F5D4),
                                letterSpacing: 2.0,
                                shadows: const [
                                  Shadow(
                                    color: Color(0xFF00E5FF),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Interactive Test Buttons
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildTestChip(
                          label: 'Test Welcome',
                          icon: Icons.waving_hand_rounded,
                          onTap: _isTesting
                              ? null
                              : () => _runTestFrame(
                                  line1: _welcomeLine1Controller.text.trim(),
                                  line2: _welcomeLine2Controller.text.trim(),
                                  numericValue: 0.0,
                                  ledMode: 0,
                                ),
                        ),
                        _buildTestChip(
                          label: 'Test Item & Total',
                          icon: Icons.shopping_basket_rounded,
                          onTap: _isTesting
                              ? null
                              : () => _runTestFrame(
                                  line1: '2x SUGAR 2KG   ${cur}145.00',
                                  line2: 'TOTAL DUE:     ${cur}145.00',
                                  numericValue: 145.00,
                                  ledMode: 2,
                                ),
                        ),
                        _buildTestChip(
                          label: 'Test Tender & Change',
                          icon: Icons.payments_rounded,
                          onTap: _isTesting
                              ? null
                              : () => _runTestFrame(
                                  line1: 'TENDERED:      ${cur}200.00',
                                  line2: 'CHANGE DUE:     ${cur}55.00',
                                  numericValue: 55.00,
                                  ledMode: 4,
                                ),
                        ),
                        _buildTestChip(
                          label: 'Clear',
                          icon: Icons.clear_all_rounded,
                          onTap: _isTesting
                              ? null
                              : () => ref
                                    .read(poleDisplayServiceProvider)
                                    .clearDisplay(),
                        ),
                      ],
                    ),
                    if (_testResult != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _testResult!.message,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _testResult!.success
                              ? const Color(0xFF34D399)
                              : const Color(0xFFFBBF24),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Enable Pole Display Switch
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1C283D)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF293548)
                        : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Enable Customer Pole Display',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Stream item prices, total payable, amount tendered & change due live during checkout',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _enabled,
                          activeThumbColor: primaryColor,
                          onChanged: (val) => setState(() => _enabled = val),
                        ),
                      ],
                    ),
                    Divider(
                      color: isDark
                          ? const Color(0xFF293548)
                          : const Color(0xFFE2E8F0),
                      height: 16,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Show Live Pole Display Readout on Cashier Screen',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Displays a live digital VFD readout banner on the POS terminal screen',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _showOnScreenPreview,
                          activeThumbColor: primaryColor,
                          onChanged: (val) =>
                              setState(() => _showOnScreenPreview = val),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Auto-Detect Hardware Port Banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF1A2234)
                      : const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isDark
                        ? const Color(0xFF25334D)
                        : const Color(0xFFBFDBFE),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.usb_rounded, color: primaryColor, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Auto-Detect Pole Display Port',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Scan RS232 COM ports and USB-Serial VFD adapters',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isScanning ? null : _autoDetectPort,
                      icon: _isScanning
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.refresh_rounded, size: 14),
                      label: Text(
                        _isScanning ? 'Scanning...' : 'Auto-Detect',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Port, Baud Rate, and Columns Row
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildTextField(
                      context: context,
                      controller: _portController,
                      label: 'SERIAL COM / USB PORT',
                      hint: 'e.g. COM2, /dev/ttyUSB0',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      context: context,
                      controller: _baudRateController,
                      label: 'BAUD RATE',
                      hint: '9600',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Port Presets
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._discoveredPorts.map((p) {
                      final isSelected = _portController.text.trim() == p.path;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () =>
                              setState(() => _portController.text = p.path),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? primaryColor.withValues(alpha: 0.2)
                                  : (isDark
                                        ? const Color(0xFF1C283D)
                                        : const Color(0xFFF8FAFC)),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : (isDark
                                          ? const Color(0xFF293548)
                                          : const Color(0xFFE2E8F0)),
                              ),
                            ),
                            child: Text(
                              p.label,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: isSelected
                                    ? primaryColor
                                    : theme.colorScheme.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    ..._commonPorts
                        .where(
                          (p) => !_discoveredPorts.any((dp) => dp.path == p),
                        )
                        .map((p) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: () =>
                                  setState(() => _portController.text = p),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1C283D)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF293548)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Text(
                                  p,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Protocol & Character Width Row
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'POLE DISPLAY COMMAND PROTOCOL',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1C283D)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF293548)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _protocol,
                              isExpanded: true,
                              dropdownColor: isDark
                                  ? const Color(0xFF151F32)
                                  : Colors.white,
                              items: _protocols.map((p) {
                                return DropdownMenuItem<String>(
                                  value: p['id'],
                                  child: Text(
                                    p['name']!,
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _protocol = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DISPLAY FORMAT',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1C283D)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF293548)
                                  : const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _columns,
                              isExpanded: true,
                              dropdownColor: isDark
                                  ? const Color(0xFF151F32)
                                  : Colors.white,
                              items: const [
                                DropdownMenuItem(
                                  value: 20,
                                  child: Text('20 Chars × 2 Lines (VFD)'),
                                ),
                                DropdownMenuItem(
                                  value: 16,
                                  child: Text('16 Chars × 2 Lines (LCD)'),
                                ),
                                DropdownMenuItem(
                                  value: 8,
                                  child: Text('8-Digit LED Numeric'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _columns = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Welcome & Thank You Messages
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      context: context,
                      controller: _welcomeLine1Controller,
                      label: 'WELCOME LINE 1 (IDLE TOP)',
                      hint: 'WELCOME TO OUR STORE',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      context: context,
                      controller: _welcomeLine2Controller,
                      label: 'WELCOME LINE 2 (IDLE BOTTOM)',
                      hint: 'NEXT CUSTOMER PLEASE',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'SAVE CUSTOMER DISPLAY CONFIGURATION',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTestChip({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0F2933),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: const Color(0xFF00F5D4)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFE2E8F0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDark
                  ? const Color(0xFF293548)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: GoogleFonts.inter(
              color: theme.colorScheme.onSurface,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.5,
                ),
                fontSize: 13,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}

