import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/network_client.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

class StoreConfigModal extends ConsumerStatefulWidget {
  const StoreConfigModal({super.key});

  @override
  ConsumerState<StoreConfigModal> createState() => _StoreConfigModalState();
}

class _StoreConfigModalState extends ConsumerState<StoreConfigModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _branchController;
  late TextEditingController _addressController;
  late TextEditingController _contactController;
  late TextEditingController _emailController;
  late TextEditingController _websiteController;
  late TextEditingController _taxController;
  late TextEditingController _taxIdController;
  late TextEditingController _tpinController;
  late TextEditingController _sdcIdController;
  late TextEditingController _mrcNoController;
  late TextEditingController _currencyController;
  late TextEditingController _terminalController;
  late TextEditingController _serviceChargeRateController;
  late TextEditingController _serverIpController;
  late TextEditingController _brandColorHexController;
  
  String? _logoPath;
  String _selectedBrandColorHex = '#C1F11D';
  CategorySector _selectedSector = CategorySector.other;
  bool _serviceChargeEnabled = false;
  bool _isManagerMode = true;
  
  bool _isLoading = true;
  StoreConfig? _currentConfig;

  static const List<Map<String, String>> _brandColorPresets = [
    {'name': 'Lime', 'hex': '#C1F11D'},
    {'name': 'Sapphire', 'hex': '#1A73E8'},
    {'name': 'Indigo', 'hex': '#6366F1'},
    {'name': 'Emerald', 'hex': '#059669'},
    {'name': 'Crimson', 'hex': '#DC2626'},
    {'name': 'Amber', 'hex': '#D97706'},
    {'name': 'Magenta', 'hex': '#EC4899'},
    {'name': 'Violet', 'hex': '#8B5CF6'},
    {'name': 'Teal', 'hex': '#06B6D4'},
    {'name': 'Slate', 'hex': '#475569'},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _branchController = TextEditingController();
    _addressController = TextEditingController();
    _contactController = TextEditingController();
    _emailController = TextEditingController();
    _websiteController = TextEditingController();
    _taxController = TextEditingController();
    _taxIdController = TextEditingController();
    _tpinController = TextEditingController();
    _sdcIdController = TextEditingController();
    _mrcNoController = TextEditingController();
    _currencyController = TextEditingController();
    _terminalController = TextEditingController();
    _serviceChargeRateController = TextEditingController(text: '10.0');
    _serverIpController = TextEditingController();
    _brandColorHexController = TextEditingController(text: '#C1F11D');
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final db = ref.read(databaseServiceProvider);
    _currentConfig = await db.getStoreConfig();
    
    if (_currentConfig != null) {
      _nameController.text = _currentConfig!.businessName;
      _branchController.text = _currentConfig!.branchName ?? '';
      _addressController.text = _currentConfig!.address ?? '';
      _contactController.text = _currentConfig!.contactNumber ?? '';
      _emailController.text = _currentConfig!.email ?? '';
      _websiteController.text = _currentConfig!.website ?? '';
      _taxController.text = _currentConfig!.taxRate.toString();
      _taxIdController.text = _currentConfig!.taxId ?? '';
      _tpinController.text = _currentConfig!.tpin ?? '';
      _sdcIdController.text = _currentConfig!.sdcId ?? '';
      _mrcNoController.text = _currentConfig!.mrcNo ?? '';
      _currencyController.text = _currentConfig!.currencySymbol ?? 'ZK';
      _terminalController.text = _currentConfig!.terminalName;
      _logoPath = _currentConfig!.logoPath;
      _selectedSector = _currentConfig!.primarySector;
      _serviceChargeEnabled = _currentConfig!.serviceChargeEnabled;
      _serviceChargeRateController.text = _currentConfig!.defaultServiceChargeRate > 0 
          ? _currentConfig!.defaultServiceChargeRate.toString() 
          : '10.0';
      _isManagerMode = _currentConfig!.isManagerMode;
      _serverIpController.text = _currentConfig!.serverIp ?? '';
      
      final colorHex = _currentConfig!.brandColorHex;
      if (colorHex != null && colorHex.isNotEmpty) {
        _selectedBrandColorHex = colorHex.startsWith('#') ? colorHex : '#$colorHex';
        _brandColorHexController.text = _selectedBrandColorHex;
      }
    } else {
      _currencyController.text = 'ZK';
      _taxController.text = '16.0';
      _terminalController.text = 'TERMINAL-01';
      _serviceChargeRateController.text = '10.0';
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _branchController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _websiteController.dispose();
    _taxController.dispose();
    _taxIdController.dispose();
    _tpinController.dispose();
    _sdcIdController.dispose();
    _mrcNoController.dispose();
    _currencyController.dispose();
    _terminalController.dispose();
    _serviceChargeRateController.dispose();
    _serverIpController.dispose();
    _brandColorHexController.dispose();
    super.dispose();
  }

  Color _parseHexColor(String hex) {
    try {
      String clean = hex.replaceAll('#', '').trim();
      if (clean.length == 6) clean = 'FF$clean';
      return Color(int.parse(clean, radix: 16));
    } catch (_) {
      return const Color(0xFFC1F11D);
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    final db = ref.read(databaseServiceProvider);
    final config = _currentConfig ?? StoreConfig();
    
    config.businessName = _nameController.text;
    config.branchName = _branchController.text.trim().isEmpty ? null : _branchController.text.trim();
    config.address = _addressController.text;
    config.contactNumber = _contactController.text;
    config.email = _emailController.text.trim().isEmpty ? null : _emailController.text.trim();
    config.website = _websiteController.text.trim().isEmpty ? null : _websiteController.text.trim();
    config.taxRate = double.tryParse(_taxController.text) ?? 16.0;
    config.taxId = _taxIdController.text;
    config.tpin = _tpinController.text.trim().isEmpty ? null : _tpinController.text.trim();
    config.sdcId = _sdcIdController.text;
    config.mrcNo = _mrcNoController.text;
    config.currencySymbol = _currencyController.text;
    config.terminalName = _terminalController.text.isEmpty ? 'TERMINAL-01' : _terminalController.text;
    config.logoPath = _logoPath;
    config.brandColorHex = _selectedBrandColorHex;
    config.primarySector = _selectedSector;
    config.loyaltyEnabled = false;
    config.serviceChargeEnabled = _serviceChargeEnabled;
    config.defaultServiceChargeRate = double.tryParse(_serviceChargeRateController.text) ?? 0.0;
    config.isManagerMode = _isManagerMode;
    config.serverIp = _serverIpController.text;

    await db.saveStoreConfig(config);
    ref.invalidate(storeConfigProvider);
    
    // Auto-sync store profile up to Cloud PostgreSQL DB
    try {
      await ref.read(postgresSyncServiceProvider).syncStoreConfigToCloud(config);
    } catch (e) {
      debugPrint('Cloud store config push notice: $e');
    }
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Store profile and document branding saved!'),
          backgroundColor: _parseHexColor(_selectedBrandColorHex),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final activeBrandColor = _parseHexColor(_selectedBrandColorHex);

    return Dialog(
      backgroundColor: const Color(0xFF141418),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Container(
        width: 800,
        height: 850,
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: activeBrandColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.storefront_rounded, color: activeBrandColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'STORE & DOCUMENT BRANDING',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Customize company logo, TPIN, contacts & export colors',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.4),
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
              if (_isLoading)
                Center(child: CircularProgressIndicator(color: activeBrandColor))
              else ...[
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Section 1: Business Identity & Logo
                        _buildSectionHeader('BUSINESS IDENTITY & LOGO', activeBrandColor),
                        const SizedBox(height: 16),
                        _buildLogoPicker(activeBrandColor),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildTextField(
                                label: 'STORE / COMPANY NAME', 
                                hint: 'e.g. Beleka Retail Ltd',
                                controller: _nameController,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: _buildTextField(
                                label: 'BRANCH / OUTLET', 
                                hint: 'e.g. Main Mall Branch',
                                controller: _branchController,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          label: 'PHYSICAL STORE ADDRESS', 
                          hint: 'e.g. Plot 1024, Cairo Road, Lusaka',
                          controller: _addressController,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                label: 'CONTACT PHONE NUMBER', 
                                hint: 'e.g. +260 977 123456',
                                controller: _contactController,
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                label: 'EMAIL ADDRESS', 
                                hint: 'e.g. info@belekaretail.com',
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                isOptional: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          label: 'WEBSITE URL', 
                          hint: 'e.g. https://belekaretail.com',
                          controller: _websiteController,
                          isOptional: true,
                        ),

                        const SizedBox(height: 32),
                        // Section 2: Industry Sector & POS Workflow Specialization
                        _buildSectionHeader('INDUSTRY SECTOR & WORKFLOW', activeBrandColor),
                        const SizedBox(height: 16),
                        _buildSectorDropdown(),

                        const SizedBox(height: 32),
                        // Section 3: Document Export & Branding Color
                        _buildSectionHeader('DOCUMENT EXPORT BRANDING COLOR', activeBrandColor),
                        const SizedBox(height: 16),
                        _buildColorPickerSection(activeBrandColor),
                        const SizedBox(height: 16),
                        _buildDocumentPreviewCard(activeBrandColor),

                        const SizedBox(height: 32),
                        // Section 4: Tax & Fiscal Compliance
                        _buildSectionHeader('TAX & FISCAL COMPLIANCE', activeBrandColor),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                label: 'ZRA TPIN / TAX PIN', 
                                hint: '1234567890',
                                controller: _tpinController,
                                isOptional: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                label: 'VAT / TAX ID', 
                                hint: '1234567890',
                                controller: _taxIdController,
                                isOptional: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                label: 'DEFAULT VAT (%)', 
                                hint: '16.0',
                                controller: _taxController,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                label: 'CURRENCY SYMBOL', 
                                hint: 'ZK',
                                controller: _currencyController,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTextField(
                                label: 'SDC ID', 
                                hint: 'SDC00300000014',
                                controller: _sdcIdController,
                                isOptional: true,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildTextField(
                                label: 'MRC NUMBER', 
                                hint: 'WIS00013845',
                                controller: _mrcNoController,
                                isOptional: true,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildTextField(
                          label: 'TERMINAL IDENTIFIER', 
                          hint: 'TERMINAL-01',
                          controller: _terminalController,
                        ),

                        const SizedBox(height: 32),

                        // Section: Hospitality & Restaurant Service Charge
                        _buildSectionHeader('HOSPITALITY / RESTAURANT SERVICE CHARGE', activeBrandColor),
                        const SizedBox(height: 16),
                        _buildServiceChargeToggle(activeBrandColor),
                        if (_serviceChargeEnabled) ...[
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'DEFAULT SERVICE CHARGE RATE (%)',
                            hint: '10.0',
                            controller: _serviceChargeRateController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Non-taxable (0% VAT). Printed on customer receipts, but excluded from DigiTax fiscal payloads.',
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                          ),
                        ],
                        
                        const SizedBox(height: 32),
                        // Section 6: Network Multi-Terminal
                        _buildSectionHeader('NETWORK & MULTI-TERMINAL', activeBrandColor),
                        const SizedBox(height: 16),
                        _buildNetworkRoleToggle(activeBrandColor),
                        if (!_isManagerMode) ...[
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'CENTRAL SERVER IP', 
                            hint: 'e.g. 192.168.1.100',
                            controller: _serverIpController,
                          ),
                          const SizedBox(height: 8),
                          _buildTestConnectionButton(),
                        ] else ...[
                          const SizedBox(height: 32),
                          _buildSectionHeader('TERMINAL SECURITY', activeBrandColor),
                          const SizedBox(height: 16),
                          _buildSecuritySection(activeBrandColor),
                        ],
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saveConfig,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: activeBrandColor,
                      foregroundColor: activeBrandColor.computeLuminance() > 0.6 ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      'SAVE BRANDING & CONFIGURATION',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorPickerSection(Color activeBrandColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SELECT DOCUMENT ACCENT COLOR',
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _brandColorPresets.map((preset) {
            final hex = preset['hex']!;
            final color = _parseHexColor(hex);
            final isSelected = _selectedBrandColorHex.toUpperCase() == hex.toUpperCase();

            return InkWell(
              onTap: () {
                setState(() {
                  _selectedBrandColorHex = hex;
                  _brandColorHexController.text = hex;
                });
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? color : Colors.white.withValues(alpha: 0.08),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)] : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      preset['name']!,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isSelected ? Colors.white : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: TextField(
                  controller: _brandColorHexController,
                  style: GoogleFonts.ibmPlexMono(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.tag_rounded, size: 16, color: Colors.white38),
                    hintText: '#1A73E8',
                    hintStyle: const TextStyle(color: Colors.white24),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: InputBorder.none,
                  ),
                  onChanged: (val) {
                    if (val.startsWith('#') && (val.length == 7 || val.length == 9)) {
                      setState(() => _selectedBrandColorHex = val);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: activeBrandColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDocumentPreviewCard(Color activeBrandColor) {
    final companyName = _nameController.text.isNotEmpty ? _nameController.text : 'BELEKA PRO POS';
    final branch = _branchController.text.isNotEmpty ? _branchController.text : 'Headquarters';
    final tpin = _tpinController.text.isNotEmpty ? _tpinController.text : '1001646043';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: activeBrandColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE DOCUMENT EXPORT PREVIEW',
                style: GoogleFonts.manrope(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: activeBrandColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: activeBrandColor,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'PDF / EXCEL / CSV',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: activeBrandColor.computeLuminance() > 0.6 ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_logoPath != null && File(_logoPath!).existsSync())
                Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: activeBrandColor, width: 1),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Image.file(File(_logoPath!), fit: BoxFit.contain),
                  ),
                )
              else
                Container(
                  width: 38,
                  height: 38,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: activeBrandColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: activeBrandColor, width: 1),
                  ),
                  child: Icon(Icons.storefront_rounded, color: activeBrandColor, size: 20),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      companyName.toUpperCase(),
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: activeBrandColor,
                      ),
                    ),
                    Text(
                      'Branch: $branch   |   TPIN: $tpin',
                      style: GoogleFonts.inter(fontSize: 9.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 2,
            decoration: BoxDecoration(
              color: activeBrandColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLogo() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _logoPath = result.files.single.path;
      });
    }
  }

  Widget _buildLogoPicker(Color activeBrandColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'STORE LOGO',
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickLogo,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 110,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _logoPath != null 
                    ? activeBrandColor.withValues(alpha: 0.4)
                    : Colors.white.withValues(alpha: 0.05),
              ),
            ),
            child: _logoPath != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_logoPath!),
                          height: 110,
                          width: double.infinity,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: () => setState(() => _logoPath = null),
                          icon: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.black87,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, 
                          color: Colors.white.withValues(alpha: 0.25), size: 30),
                      const SizedBox(height: 6),
                      Text(
                        'Tap to upload company logo (PNG / JPEG)',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, Color accentColor) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: accentColor.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ],
    );
  }

  Widget _buildSectorDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BUSINESS SECTOR',
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CategorySector>(
              value: _selectedSector,
              isExpanded: true,
              dropdownColor: const Color(0xFF1A1A20),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              onChanged: (CategorySector? newValue) {
                if (newValue != null) {
                  setState(() => _selectedSector = newValue);
                }
              },
              items: CategorySector.values.map((CategorySector sector) {
                return DropdownMenuItem<CategorySector>(
                  value: sector,
                  child: Text(sector.name.toUpperCase()),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceChargeToggle(Color activeBrandColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _serviceChargeEnabled 
            ? activeBrandColor.withValues(alpha: 0.05) 
            : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _serviceChargeEnabled 
              ? activeBrandColor.withValues(alpha: 0.2) 
              : Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ENABLE RESTAURANT SERVICE CHARGE',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Add service charge to bills/receipts (Non-taxable / 0% VAT)',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          Switch(
            value: _serviceChargeEnabled,
            onChanged: (v) => setState(() => _serviceChargeEnabled = v),
            activeThumbColor: activeBrandColor,
            activeTrackColor: activeBrandColor.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkRoleToggle(Color activeBrandColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MANAGER SERVER MODE',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _isManagerMode 
                    ? 'Main hub for subordinate cashier terminals' 
                    : 'Connects to remote master server IP',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          Switch(
            value: _isManagerMode,
            onChanged: (v) => setState(() => _isManagerMode = v),
            activeThumbColor: activeBrandColor,
            activeTrackColor: activeBrandColor.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildTestConnectionButton() {
    return InkWell(
      onTap: () async {
        final client = ref.read(networkClientProvider);
        if (client == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Network Client not initialized.')),
          );
          return;
        }

        final success = await client.testConnection(_serverIpController.text);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Connection Successful!' : 'Connection Failed! Check Manager IP.'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      },
      child: Container(
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                'TEST CONNECTION',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label, 
    required String hint, 
    TextEditingController? controller,
    TextInputType? keyboardType,
    bool isOptional = false,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            if (isOptional) ...[
              const SizedBox(width: 6),
              Text(
                '(OPTIONAL)',
                style: GoogleFonts.inter(fontSize: 8.5, color: Colors.white24),
              ),
            ],
            if (readOnly) ...[
              const SizedBox(width: 6),
              Text(
                '(LOCKED / HQ)',
                style: GoogleFonts.inter(fontSize: 8.5, color: Colors.amberAccent, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: readOnly ? Colors.white.withValues(alpha: 0.01) : Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: readOnly ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.05)),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            readOnly: readOnly,
            style: GoogleFonts.inter(
              color: readOnly ? Colors.white60 : Colors.white,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.15)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: InputBorder.none,
            ),
            validator: (value) {
              if (!isOptional && (value == null || value.trim().isEmpty)) {
                return 'This field is required';
              }
              return null;
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSecuritySection(Color activeBrandColor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: activeBrandColor, size: 18),
              const SizedBox(width: 10),
              Text(
                'ADMIN RECOVERY CODE',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Emergency recovery code allows owner to reset credentials.',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildSecurityAction(
                  label: 'VIEW NOTICE',
                  icon: Icons.visibility_outlined,
                  onTap: _viewRecoveryCode,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSecurityAction(
                  label: 'ROTATE CODE',
                  icon: Icons.refresh_rounded,
                  onTap: _rotateRecoveryCode,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityAction({required String label, required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: Colors.white60),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _viewRecoveryCode() async {
    final verified = await _verifyManagerPin();
    if (!verified) return;

    _showInformationDialog(
      'RECOVERY CODE SECURITY',
      'For security, the recovery code is stored as a one-way cryptographic hash and cannot be viewed in plain text.\n\nUse "ROTATE CODE" to issue a new 8-character recovery code.'
    );
  }

  void _rotateRecoveryCode() async {
    final verified = await _verifyManagerPin();
    if (!verified) return;

    final db = ref.read(databaseServiceProvider);
    final recoveryCode = _generateNewCode();
    
    if (_currentConfig != null) {
      _currentConfig!.recoveryCodeHash = hashPin(recoveryCode);
      await db.saveStoreConfig(_currentConfig!);
      
      if (mounted) {
        _showRecoveryCodeDialog(recoveryCode);
      }
    }
  }

  String _generateNewCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = math.Random();
    String code = '';
    for (var i = 0; i < 8; i++) {
      if (i == 4) code += '-';
      code += chars[rnd.nextInt(chars.length)];
    }
    return code;
  }

  Future<bool> _verifyManagerPin() async {
    final pinController = TextEditingController();
    bool verified = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        title: Text('SECURITY VERIFICATION', style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFFC1F11D), letterSpacing: 2)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Please enter your Manager PIN to authorize this sensitive action.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 20),
            TextField(
              controller: pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: GoogleFonts.ibmPlexMono(color: Colors.white, letterSpacing: 8, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: '****',
                hintStyle: GoogleFonts.ibmPlexMono(color: Colors.white10),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.02),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL', style: GoogleFonts.manrope(color: Colors.white24, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          ElevatedButton(
            onPressed: () async {
              final db = ref.read(databaseServiceProvider);
              final admin = await db.getAdminUser();
              if (admin != null && admin.passwordHash == hashPin(pinController.text.trim())) {
                verified = true;
                if (context.mounted) Navigator.pop(context);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid PIN'), backgroundColor: Colors.redAccent));
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC1F11D), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('VERIFY', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 13)),
          ),
        ],
      ),
    );
    return verified;
  }

  void _showInformationDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        title: Text(title, style: GoogleFonts.manrope(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFFC1F11D), letterSpacing: 1)),
        content: Text(message, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('DISMISS', style: GoogleFonts.manrope(color: const Color(0xFFC1F11D), fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showRecoveryCodeDialog(String code) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
        title: Text('NEW RECOVERY CODE', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D), fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The previous code is now invalid. Please save this new code securely.', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.2))),
              child: Center(
                child: SelectableText(code, style: GoogleFonts.ibmPlexMono(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4, color: const Color(0xFFC1F11D))),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC1F11D), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('DONE', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
