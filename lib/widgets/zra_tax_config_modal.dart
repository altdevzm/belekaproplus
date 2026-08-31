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

    await isar.writeTxn(() async {
      await isar.storeConfigs.put(config);
    });

    // Auto-sync updated TPIN and DigiTax credentials up to Cloud PostgreSQL DB
    try {
      await ref.read(postgresSyncServiceProvider).syncStoreConfigToCloud(config);
    } catch (e) {
      debugPrint('Notice: Cloud store config sync: $e');
    }

    ref.invalidate(storeConfigProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('DigiTax & ZRA Smart Invoice configuration saved and synced to Cloud!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final isBranchManager = ref.watch(isBranchManagerProvider);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
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
                      color: isDark ? primaryColor.withValues(alpha: 0.15) : primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_long_rounded, color: primaryColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ZRA Smart Invoice & DigiTax API',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Zambia Revenue Authority VSDC Gateway & Dynamic Tax Setup',
                          style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 1),
              const SizedBox(height: 16),

              if (isBranchManager)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_rounded, color: Color(0xFFD97706), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Centrally Configured at Headquarters: DigiTax API credentials, live ZRA environment, and company TPIN are managed by the Corporate Owner at Headquarters. These settings are read-only for this branch.',
                          style: GoogleFonts.inter(color: const Color(0xFFD97706), fontSize: 12, fontWeight: FontWeight.w600),
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
                          color: primaryColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select the tax regime under which this store operates for POS sales & fiscalization.',
                        style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        initialValue: const ['VAT_STANDARD', 'TURNOVER_TAX', 'EXEMPT', 'COMPOSITE'].contains(_businessTaxType)
                            ? _businessTaxType
                            : 'VAT_STANDARD',
                        dropdownColor: isDark ? const Color(0xFF151F32) : Colors.white,
                        style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                        decoration: InputDecoration(
                          labelText: 'Company Tax Classification',
                          labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: primaryColor),
                          ),
                          prefixIcon: Icon(Icons.account_balance_rounded, color: theme.colorScheme.onSurfaceVariant),
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
                          color: primaryColor,
                          letterSpacing: 0.5,
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
                              style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'ZRA TPIN (Taxpayer ID)',
                                labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                hintText: '1000123456',
                                hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: primaryColor),
                                ),
                                prefixIcon: Icon(Icons.badge_rounded, color: theme.colorScheme.onSurfaceVariant),
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
                              style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Branch Code (bhfId)',
                                labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                hintText: '00',
                                helperText: '00 = HQ, 01 = Branch 1',
                                helperStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 10),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: primaryColor),
                                ),
                                prefixIcon: Icon(Icons.storefront_rounded, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              initialValue: (_digitaxEnv.toLowerCase() == 'production') ? 'production' : 'sandbox',
                              isExpanded: true,
                              dropdownColor: isDark ? const Color(0xFF151F32) : Colors.white,
                              style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
                              decoration: InputDecoration(
                                labelText: 'DigiTax Environment',
                                labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                                filled: true,
                                fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: primaryColor),
                                ),
                                prefixIcon: Icon(Icons.cloud_queue_rounded, color: theme.colorScheme.onSurfaceVariant),
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
                        style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'DigiTax Secret API Key',
                          labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                          hintText: 'B_TEST_api_key_...',
                          hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: primaryColor),
                          ),
                          prefixIcon: Icon(Icons.key_rounded, color: primaryColor),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureApiKey ? Icons.visibility_off : Icons.visibility, color: theme.colorScheme.onSurfaceVariant),
                            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'DigiTax Secret API Key is required for fiscalization';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Test Connection Button Row
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isLoadingRates ? null : () => _fetchLiveTaxRates(),
                            icon: _isLoadingRates
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.bolt_rounded, size: 16),
                            label: Text(
                              _isLoadingRates ? 'Testing Connection...' : 'Test Connection',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 0,
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
                                ? const Color(0xFFECFDF5) 
                                : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _isConnectionSuccess 
                                  ? const Color(0xFFA7F3D0) 
                                  : const Color(0xFFFDE68A),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _isConnectionSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                size: 16,
                                color: _isConnectionSuccess ? const Color(0xFF059669) : const Color(0xFFD97706),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _connectionStatusMessage!,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: _isConnectionSuccess ? const Color(0xFF059669) : const Color(0xFFD97706),
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
                          color: const Color(0xFFF0F9FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBAE6FD)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_done_rounded, color: Color(0xFF0284C7), size: 22),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Cloud Virtual SDC (VSDC) Enabled',
                                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF0284C7)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'DigiTax automatically manages your SDC Device ID and Machine Registration Code (MRC) in the cloud. No manual hardware SDC entry is required.',
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF0369A1)),
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
                              color: primaryColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _ratesFetched ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: _ratesFetched ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(_ratesFetched ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded, size: 12, color: _ratesFetched ? const Color(0xFF059669) : const Color(0xFFD97706)),
                                const SizedBox(width: 4),
                                Text(
                                  _ratesFetched ? 'DIGITAX VSDC SYNCED' : 'STANDARD ZRA CODES',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: _ratesFetched ? const Color(0xFF059669) : const Color(0xFFD97706),
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
                                  ? (isDark ? const Color(0xFF1C283D) : const Color(0xFFEFF6FF))
                                  : (isDark ? const Color(0xFF151F32) : Colors.white),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? primaryColor
                                    : (isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 32,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isDark ? primaryColor.withValues(alpha: 0.2) : primaryColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    code,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: primaryColor,
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
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        desc,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${percentage.toStringAsFixed(1)}%',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: primaryColor,
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
              Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 1),
              const SizedBox(height: 16),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurface,
                      side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
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
