import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

class ZraTaxConfigModal extends ConsumerStatefulWidget {
  const ZraTaxConfigModal({super.key});

  @override
  ConsumerState<ZraTaxConfigModal> createState() => _ZraTaxConfigModalState();
}

class _ZraTaxConfigModalState extends ConsumerState<ZraTaxConfigModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _tpinController;
  late TextEditingController _apiKeyController;
  late TextEditingController _bhfIdController;

  bool _obscureApiKey = true;
  String _businessTaxType = 'VAT_STANDARD';
  String _digitaxEnv = 'sandbox';
  StoreConfig? _config;

  bool _isLoadingRates = false;
  bool _ratesFetched = false;
  String? _connectionStatusMessage;
  bool _isConnectionSuccess = false;

  List<Map<String, dynamic>> _taxRates = [
    {
      'code': 'A',
      'tax_type': 'Standard Rate VAT',
      'rate': 16.0,
      'category': 'VAT_STANDARD',
      'description': 'General taxable goods & services in Zambia (16.0% VAT)',
    },
    {
      'code': 'B',
      'tax_type': 'Zero-Rated Supplies',
      'rate': 0.0,
      'category': 'VAT_ZERO',
      'description': 'Basic commodities, agricultural & exported supplies (0% VAT)',
    },
    {
      'code': 'C',
      'tax_type': 'Exempt Supplies',
      'rate': 0.0,
      'category': 'EXEMPT',
      'description': 'Health, education & statutory financial services (0% Exempt)',
    },
    {
      'code': 'D',
      'tax_type': 'Special Excise / Tourism',
      'rate': 10.0,
      'category': 'SPECIAL_LEVY',
      'description': 'Tourism levy & designated excisable services (10.0%)',
    },
    {
      'code': 'E',
      'tax_type': 'Export Goods',
      'rate': 0.0,
      'category': 'EXPORT',
      'description': 'International cross-border exports (0% VAT)',
    },
    {
      'code': 'TOT',
      'tax_type': 'Turnover Tax (TOT)',
      'rate': 3.0,
      'category': 'TURNOVER_TAX',
      'description': 'ZRA Turnover Tax for micro & small enterprises (3.0% Flat)',
    },
  ];

  @override
  void initState() {
    super.initState();
    _tpinController = TextEditingController();
    _apiKeyController = TextEditingController();
    _bhfIdController = TextEditingController(text: '00');
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final isar = ref.read(isarProvider);
    _config = await isar.storeConfigs.where().findFirst();
    if (_config != null) {
      setState(() {
        _tpinController.text = _config!.tpin ?? '';
        _apiKeyController.text = _config!.digitaxApiKey ?? '';
        _bhfIdController.text = (_config!.bhfId.isNotEmpty) ? _config!.bhfId : '00';
        
        const validTaxTypes = ['VAT_STANDARD', 'TURNOVER_TAX', 'EXEMPT', 'COMPOSITE'];
        _businessTaxType = validTaxTypes.contains(_config!.businessTaxType) ? _config!.businessTaxType : 'VAT_STANDARD';
        
        const validEnvs = ['sandbox', 'production'];
        _digitaxEnv = validEnvs.contains(_config!.digitaxEnvironment) ? _config!.digitaxEnvironment : 'sandbox';
      });

      if (_apiKeyController.text.trim().isNotEmpty) {
        _fetchLiveTaxRates(silent: true);
      }
    }
  }

  Future<void> _fetchLiveTaxRates({bool silent = false}) async {
    setState(() {
      _isLoadingRates = true;
      _connectionStatusMessage = null;
    });
    final apiKey = _apiKeyController.text.trim();
    final env = _digitaxEnv;

    try {
      final syncService = ref.read(digitaxInventoryServiceProvider);
      final result = await syncService.testApiKeyConnection(apiKey: apiKey, environment: env);

      setState(() {
        _ratesFetched = result.success;
        _isConnectionSuccess = result.success;
        _connectionStatusMessage = result.message;
        if (result.taxRates != null && result.taxRates!.isNotEmpty) {
          _taxRates = result.taxRates!;
        }
      });

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success ? const Color(0xFF10B981) : Colors.redAccent,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _ratesFetched = false;
        _isConnectionSuccess = false;
        _connectionStatusMessage = 'Error connecting to DigiTax: $e';
      });
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRates = false);
    }
  }

  @override
  void dispose() {
    _tpinController.dispose();
    _apiKeyController.dispose();
    _bhfIdController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      final config = _config ?? StoreConfig()
        ..businessName = 'Beleka POS Store'
        ..terminalName = 'POS-Main';

      config.tpin = _tpinController.text.trim();
      config.bhfId = _bhfIdController.text.trim().isEmpty ? '00' : _bhfIdController.text.trim();
      config.digitaxApiKey = _apiKeyController.text.trim();
      config.businessTaxType = _businessTaxType;
      config.digitaxEnvironment = _digitaxEnv;

      if (_businessTaxType == 'VAT_STANDARD') {
        config.taxRate = 16.0;
      } else if (_businessTaxType == 'TURNOVER_TAX') {
        config.taxRate = 3.0;
      } else if (_businessTaxType == 'EXEMPT') {
        config.taxRate = 0.0;
      }

      await isar.storeConfigs.put(config);
      
      // Auto-sync updated TPIN and DigiTax credentials up to Cloud PostgreSQL DB
      try {
        await ref.read(postgresSyncServiceProvider).syncStoreConfigToCloud(config);
      } catch (e) {
        debugPrint('Notice: Cloud store config sync: $e');
      }
    });

    ref.invalidate(storeConfigProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('DigiTax & ZRA Smart Invoice configuration saved successfully!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBranchManager = ref.watch(isBranchManagerProvider);

    return Dialog(
      backgroundColor: const Color(0xFF16161A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 780),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.receipt_long_rounded, color: Color(0xFF10B981), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ZRA Smart Invoice & DigiTax API',
                          style: GoogleFonts.manrope(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Zambia Revenue Authority VSDC Gateway & Dynamic Tax Setup',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),

              if (isBranchManager)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Colors.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Centrally Configured at Headquarters: DigiTax API credentials, live ZRA environment, and company TPIN are managed by the Corporate Owner at Headquarters. These settings are read-only for this branch.',
                          style: GoogleFonts.inter(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section 1: Business Tax Category Provision
                      Text(
                        'BUSINESS TAX CATEGORY PROVISION',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF10B981),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select the tax regime under which this store operates for POS sales & fiscalization.',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                      ),
                      const SizedBox(height: 10),

                      DropdownButtonFormField<String>(
                        initialValue: _businessTaxType,
                        dropdownColor: const Color(0xFF222228),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Company Tax Classification',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.account_balance_rounded, color: Colors.white60),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'VAT_STANDARD',
                            child: Text('Standard VAT Registered (16.0% VAT Rate)'),
                          ),
                          DropdownMenuItem(
                            value: 'TURNOVER_TAX',
                            child: Text('Turnover Tax Registered (3.0% Flat Rate)'),
                          ),
                          DropdownMenuItem(
                            value: 'EXEMPT',
                            child: Text('Tax Exempt Organization (0% - Healthcare/Education)'),
                          ),
                          DropdownMenuItem(
                            value: 'COMPOSITE',
                            child: Text('Composite / Mixed Tax (Per-Product Categorization)'),
                          ),
                        ],
                        onChanged: isBranchManager
                            ? null
                            : (val) {
                                if (val != null) setState(() => _businessTaxType = val);
                              },
                      ),
                      const SizedBox(height: 20),

                      // Section 2: Store Tax Credentials & Environment
                      Text(
                        'DIGITAX API CREDENTIALS & STORE IDENTIFIERS',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF10B981),
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _tpinController,
                              readOnly: isBranchManager,
                              style: const TextStyle(color: Colors.white),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'ZRA TPIN (Taxpayer ID)',
                                labelStyle: const TextStyle(color: Colors.white70),
                                hintText: '1000123456',
                                hintStyle: const TextStyle(color: Colors.white30),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                prefixIcon: const Icon(Icons.badge_rounded, color: Colors.white60),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter 10-digit ZRA TPIN';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _bhfIdController,
                              readOnly: isBranchManager,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Branch Code (bhfId)',
                                labelStyle: const TextStyle(color: Colors.white70),
                                hintText: '00',
                                helperText: '00 = HQ, 01 = Branch 1',
                                helperStyle: const TextStyle(color: Colors.white38, fontSize: 10),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                prefixIcon: const Icon(Icons.storefront_rounded, color: Colors.white60),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: _digitaxEnv,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF222228),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'DigiTax Environment',
                                labelStyle: const TextStyle(color: Colors.white70),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                prefixIcon: const Icon(Icons.cloud_queue_rounded, color: Colors.white60),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'sandbox', child: Text('Sandbox (Test Mode)')),
                                DropdownMenuItem(value: 'production', child: Text('Production (Live ZRA)')),
                              ],
                              onChanged: isBranchManager
                                  ? null
                                  : (val) {
                                      if (val != null) setState(() => _digitaxEnv = val);
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      TextFormField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey,
                        readOnly: isBranchManager,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'DigiTax Secret API Key',
                          labelStyle: const TextStyle(color: Colors.white70),
                          hintText: 'B_TEST_api_key_...',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFF10B981)),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, color: Colors.white60),
                            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Enter your DigiTax Secret API Key';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),

                      // Test Connection Button Row
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isLoadingRates ? null : () => _fetchLiveTaxRates(),
                            icon: _isLoadingRates
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                : const Icon(Icons.bolt_rounded, size: 16),
                            label: Text(
                              _isLoadingRates ? 'Testing Connection...' : 'Test Connection',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),

                      if (_connectionStatusMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isConnectionSuccess 
                                ? const Color(0xFF10B981).withValues(alpha: 0.1) 
                                : Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isConnectionSuccess 
                                  ? const Color(0xFF10B981).withValues(alpha: 0.3) 
                                  : Colors.amber.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _isConnectionSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                size: 16,
                                color: _isConnectionSuccess ? const Color(0xFF10B981) : Colors.amber,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _connectionStatusMessage!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _isConnectionSuccess ? const Color(0xFF10B981) : Colors.amber,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Section 3: Virtual SDC Notice Card
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_done_rounded, color: Colors.lightBlueAccent, size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cloud Virtual SDC (VSDC) Enabled',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.lightBlueAccent),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'DigiTax automatically manages your SDC Device ID and Machine Registration Code (MRC) in the cloud. No manual hardware SDC entry is required.',
                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Section 4: Live Tax Rates Pulled from DigiTax
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'OFFICIAL ZRA TAX RATES & CLASSIFICATIONS',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF10B981),
                              letterSpacing: 1,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (_ratesFetched ? const Color(0xFF10B981) : Colors.amber).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: (_ratesFetched ? const Color(0xFF10B981) : Colors.amber).withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_ratesFetched ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded, size: 12, color: _ratesFetched ? const Color(0xFF10B981) : Colors.amber),
                                const SizedBox(width: 4),
                                Text(
                                  _ratesFetched ? 'DIGITAX VSDC SYNCED' : 'STANDARD ZRA CODES',
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _ratesFetched ? const Color(0xFF10B981) : Colors.amber,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Tax Rates Grid / Cards
                      Column(
                        children: _taxRates.map((rate) {
                          final code = rate['code'] ?? '';
                          final name = rate['tax_type'] ?? rate['name'] ?? 'Tax';
                          final num percentage = rate['rate'] ?? 0;
                          final desc = rate['description'] ?? '';

                          final isSelected = (_businessTaxType == 'VAT_STANDARD' && code == 'A') ||
                              (_businessTaxType == 'TURNOVER_TAX' && code == 'TOT') ||
                              (_businessTaxType == 'EXEMPT' && code == 'C') ||
                              (_businessTaxType == 'COMPOSITE');

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF10B981).withValues(alpha: 0.08)
                                  : Colors.white.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF10B981).withValues(alpha: 0.35)
                                    : Colors.white.withValues(alpha: 0.05),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    code,
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        name,
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Text(
                                        desc,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${percentage.toStringAsFixed(1)}%',
                                    style: GoogleFonts.jetBrainsMono(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    child: Text(isBranchManager ? 'Close' : 'Cancel'),
                  ),
                  if (!isBranchManager) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _saveConfig,
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text('Save ZRA Settings'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.black,
                        textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
