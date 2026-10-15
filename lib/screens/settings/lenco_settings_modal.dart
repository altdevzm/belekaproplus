import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/lenco_payment_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

class LencoSettingsModal extends ConsumerStatefulWidget {
  const LencoSettingsModal({super.key});

  @override
  ConsumerState<LencoSettingsModal> createState() => _LencoSettingsModalState();
}

class _LencoSettingsModalState extends ConsumerState<LencoSettingsModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _apiKeyController;
  late TextEditingController _bankNameController;
  late TextEditingController _accountNumberController;
  late TextEditingController _accountNameController;

  bool _lencoEnabled = true;
  String _environment = 'sandbox';
  bool _obscureApiKey = true;
  bool _isTesting = false;
  bool _isSaving = false;
  String? _testStatusMessage;
  bool? _testSuccess;
  StoreConfig? _config;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _bankNameController = TextEditingController();
    _accountNumberController = TextEditingController();
    _accountNameController = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final isar = ref.read(isarProvider);
    _config = await isar.storeConfigs.where().findFirst();
    if (_config != null && mounted) {
      setState(() {
        _lencoEnabled = _config!.lencoEnabled;
        _apiKeyController.text = _config!.lencoApiKey ?? '';
        _environment = _config!.lencoEnvironment.isNotEmpty ? _config!.lencoEnvironment : 'sandbox';
        _bankNameController.text = _config!.lencoBankName ?? '';
        _accountNumberController.text = _config!.lencoAccountNumber ?? '';
        _accountNameController.text = _config!.lencoAccountName ?? '';
      });
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _bankNameController.dispose();
    _accountNumberController.dispose();
    _accountNameController.dispose();
    super.dispose();
  }

  String get _webhookUrl {
    final cloudUrl = _config?.cloudApiUrl?.trim();
    final base = (cloudUrl != null && cloudUrl.isNotEmpty) ? cloudUrl : 'https://api.belekapos.com';
    final sanitized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return '$sanitized/api/v1/lenco/webhook';
  }

  Future<void> _testConnection() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Lenco API Token first.')),
      );
      return;
    }

    setState(() {
      _isTesting = true;
      _testStatusMessage = null;
      _testSuccess = null;
    });

    final lencoService = ref.read(lencoPaymentServiceProvider);
    final res = await lencoService.testCredentials(
      apiKey: key,
      environment: _environment,
    );

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testSuccess = res['status'] == true;
      _testStatusMessage = res['message'] ?? 'Connection test completed';
    });
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final isar = ref.read(isarProvider);
    final config = _config ?? StoreConfig()
      ..terminalName = 'POS-Main';

    config.lencoEnabled = _lencoEnabled;
    config.lencoApiKey = _apiKeyController.text.trim();
    config.lencoEnvironment = _environment;
    config.lencoBankName = _bankNameController.text.trim();
    config.lencoAccountNumber = _accountNumberController.text.trim();
    config.lencoAccountName = _accountNameController.text.trim();

    await isar.writeTxn(() async {
      await isar.storeConfigs.put(config);
    });

    // Sync to Cloud DB
    try {
      await ref.read(postgresSyncServiceProvider).syncStoreConfigToCloud(config);
    } catch (e) {
      debugPrint('Lenco config cloud sync notice: $e');
    }

    if (!mounted) return;
    setState(() => _isSaving = false);
    ref.invalidate(storeConfigProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Lenco payment settings saved and synced successfully!'),
        backgroundColor: Color(0xFF10B981),
      ),
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 650,
        constraints: const BoxConstraints(maxHeight: 760),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Modal Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Color(0xFF0284C7),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lenco Payment Gateway & Banking',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'Configure Mobile Money, Card & Bank Transfer payment processing',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Modal Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gateway Enable Switch
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _lencoEnabled
                              ? const Color(0xFF0284C7).withValues(alpha: 0.06)
                              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _lencoEnabled
                                ? const Color(0xFF0284C7).withValues(alpha: 0.3)
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Enable Lenco Payment Gateway',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Allows customers to pay via Mobile Money (Airtel/MTN/Zamtel), Card, and Bank Transfer at POS',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _lencoEnabled,
                              activeTrackColor: const Color(0xFF0284C7),
                              onChanged: (val) => setState(() => _lencoEnabled = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Environment Selector
                      Text(
                        'Gateway Environment',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildEnvOption(
                              'Sandbox (Testing)',
                              'sandbox',
                              Icons.science_rounded,
                              const Color(0xFFD97706),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildEnvOption(
                              'Production (Live)',
                              'production',
                              Icons.verified_rounded,
                              const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // API Token Input
                      Text(
                        'Lenco API Token / Secret Key',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _apiKeyController,
                        obscureText: _obscureApiKey,
                        decoration: InputDecoration(
                          hintText: 'e.g. xo+CAiijrIy9XvZCYyhjrv0fpSAL6CfU8CgA+up1NXqK',
                          hintStyle: GoogleFonts.inter(fontSize: 12),
                          prefixIcon: const Icon(Icons.key_rounded, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureApiKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscureApiKey = !_obscureApiKey),
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Universal Webhook URL Box (1-Click Copy)
                      Text(
                        'Universal Multi-Tenant Webhook URL',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                _webhookUrl,
                                style: GoogleFonts.firaCode(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy Webhook URL',
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: _webhookUrl));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Webhook URL copied to clipboard! Paste in Lenco Dashboard.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Copy and register this URL in your Lenco Pay Dashboard under Webhooks to receive instant transaction confirmations.',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Store Receiving Bank Details (for Bank Transfers)
                      Text(
                        'Store Bank Account Details (for Customer Bank Transfers)',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Shown to customers paying in bulk or large purchases via direct bank transfer',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _bankNameController,
                              decoration: InputDecoration(
                                labelText: 'Bank Name',
                                hintText: 'e.g. Absa Bank Zambia',
                                filled: true,
                                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _accountNumberController,
                              decoration: InputDecoration(
                                labelText: 'Account Number',
                                hintText: 'e.g. 9130001234567',
                                filled: true,
                                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _accountNameController,
                        decoration: InputDecoration(
                          labelText: 'Account Holder Name',
                          hintText: 'e.g. Beleka Retail Limited',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Test Connection Section
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.sync_rounded, size: 18),
                            label: Text(
                              _isTesting ? 'Verifying...' : 'Test Connection',
                              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (_testStatusMessage != null)
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _testSuccess == true
                                      ? const Color(0xFFECFDF5)
                                      : const Color(0xFFFEF2F2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _testSuccess == true
                                        ? const Color(0xFFA7F3D0)
                                        : const Color(0xFFFECACA),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _testSuccess == true
                                          ? Icons.check_circle_rounded
                                          : Icons.error_rounded,
                                      size: 16,
                                      color: _testSuccess == true
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _testStatusMessage!,
                                        style: GoogleFonts.inter(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: _testSuccess == true
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFDC2626),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Modal Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveConfig,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      _isSaving ? 'Saving...' : 'Save & Sync Settings',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvOption(String title, String val, IconData icon, Color color) {
    final isSelected = _environment == val;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () => setState(() => _environment = val),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? color : Colors.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? color : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
