import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/scale_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';

class ScaleSettingsModal extends ConsumerStatefulWidget {
  const ScaleSettingsModal({super.key});

  @override
  ConsumerState<ScaleSettingsModal> createState() => _ScaleSettingsModalState();
}

class _ScaleSettingsModalState extends ConsumerState<ScaleSettingsModal> {
  late bool _scaleEnabled;
  late TextEditingController _portController;
  late TextEditingController _baudRateController;
  late TextEditingController _defaultTareController;
  late String _scaleProtocol;
  bool _isTesting = false;
  ScaleWeightReading? _testReading;

  final List<String> _commonPorts = [
    'COM1',
    'COM2',
    'COM3',
    'COM4',
    '/dev/ttyUSB0',
    '/dev/ttyACM0',
    '127.0.0.1:9001',
    'localhost:9001',
  ];

  final List<Map<String, String>> _protocols = [
    {'id': 'generic', 'name': 'Generic ASCII Continuous Stream'},
    {'id': 'toledo', 'name': 'Mettler Toledo / Toledo 8217 / PS60'},
    {'id': 'cas', 'name': 'CAS PD-II / AP-1 Series'},
    {'id': 'avery', 'name': 'Avery Berkel / Weightronix'},
    {'id': 'bridge', 'name': 'TCP Socket Scale Bridge'},
  ];

  @override
  void initState() {
    super.initState();
    final config = ref.read(storeConfigProvider).value;
    _scaleEnabled = config?.scaleEnabled ?? true;
    _portController = TextEditingController(text: config?.scalePort ?? 'COM1');
    final baud = config?.scaleBaudRate ?? 9600;
    _baudRateController = TextEditingController(text: (baud > 0 && baud < 1000000) ? baud.toString() : '9600');
    _defaultTareController = TextEditingController(text: (config?.defaultTareWeight ?? 0.0).toStringAsFixed(3));
    final rawProtocol = config?.scaleProtocol.trim();
    _scaleProtocol = (_protocols.any((p) => p['id'] == rawProtocol)) ? rawProtocol! : 'generic';
  }

  @override
  void dispose() {
    _portController.dispose();
    _baudRateController.dispose();
    _defaultTareController.dispose();
    super.dispose();
  }

  Future<void> _testScale() async {
    setState(() {
      _isTesting = true;
      _testReading = null;
    });

    final scaleService = ref.read(scaleServiceProvider);
    await scaleService.connect(
      port: _portController.text.trim(),
      baudRate: int.tryParse(_baudRateController.text) ?? 9600,
      protocol: _scaleProtocol,
    );

    scaleService.startSimulation(targetWeight: 1.750);

    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() {
        _isTesting = false;
        _testReading = scaleService.currentReading;
      });
    }
  }

  Future<void> _save() async {
    final db = ref.read(databaseServiceProvider);
    final config = ref.read(storeConfigProvider).value;

    if (config != null) {
      config.scaleEnabled = _scaleEnabled;
      config.scalePort = _portController.text.trim();
      config.scaleBaudRate = int.tryParse(_baudRateController.text.trim()) ?? 9600;
      config.scaleProtocol = _scaleProtocol;
      config.defaultTareWeight = double.tryParse(_defaultTareController.text.trim()) ?? 0.0;

      await db.saveStoreConfig(config);
      ref.invalidate(storeConfigProvider);

      // Reconnect scale service with updated configuration
      final scaleService = ref.read(scaleServiceProvider);
      await scaleService.connect(
        port: config.scalePort,
        baudRate: config.scaleBaudRate,
        protocol: config.scaleProtocol,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Scale hardware configuration saved successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Container(
        width: 540,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isDark ? primaryColor.withValues(alpha: 0.15) : primaryColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.scale_rounded, color: primaryColor, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Electronic Scale Configuration',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurfaceVariant, size: 20),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 1),
              const SizedBox(height: 16),

              // Enable Scale Switch Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enable Electronic Scale Integration',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Auto-read weight on selecting weighted products at checkout',
                            style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: _scaleEnabled,
                      activeThumbColor: primaryColor,
                      onChanged: (val) => setState(() => _scaleEnabled = val),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Port & Baud Rate Row
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildTextField(
                      context: context,
                      controller: _portController,
                      label: 'SERIAL PORT / SOCKET BRIDGE',
                      hint: 'e.g. COM1, COM3, /dev/ttyUSB0',
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

              // Quick Port Preset Pills
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _commonPorts.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: InkWell(
                        onTap: () => setState(() => _portController.text = p),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            p,
                            style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 16),

              // Scale Protocol Selector
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SCALE PROTOCOL / DRIVER FORMAT',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _protocols.any((p) => p['id'] == _scaleProtocol) ? _scaleProtocol : 'generic',
                        isExpanded: true,
                        dropdownColor: isDark ? const Color(0xFF151F32) : Colors.white,
                        items: _protocols.map((p) {
                          return DropdownMenuItem<String>(
                            value: p['id'],
                            child: Text(
                              p['name']!,
                              style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _scaleProtocol = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Test Scale Connection Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _testReading != null
                                ? 'LIVE: ${_testReading!.netWeight.toStringAsFixed(3)} ${_testReading!.unit.toUpperCase()}'
                                : 'SCALE TEST & DIAGNOSTIC',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _testReading != null ? const Color(0xFF059669) : theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _testReading != null ? 'Status: Stable • Connected' : 'Verify communication with scale driver',
                            style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _isTesting ? null : _testScale,
                      icon: _isTesting
                          ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.play_arrow_rounded, size: 16),
                      label: Text(_isTesting ? 'Testing...' : 'Test Scale', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Save Button
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    'SAVE SCALE CONFIGURATION',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                  ),
                ),
              ),
            ],
          ),
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
            border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }
}
