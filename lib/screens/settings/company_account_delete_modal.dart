import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/main.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

class CompanyAccountDeleteModal extends ConsumerStatefulWidget {
  const CompanyAccountDeleteModal({super.key});

  @override
  ConsumerState<CompanyAccountDeleteModal> createState() => _CompanyAccountDeleteModalState();
}

class _CompanyAccountDeleteModalState extends ConsumerState<CompanyAccountDeleteModal> {
  final _pinController = TextEditingController();
  final _confirmationController = TextEditingController();
  
  bool _obscurePin = true;
  bool _purgeCloudVps = true;
  bool _isProcessing = false;
  String? _errorMessage;

  StoreConfig? _storeConfig;
  int _productsCount = 0;
  int _salesCount = 0;
  int _usersCount = 0;
  bool _isLoadingSummary = true;

  @override
  void initState() {
    super.initState();
    _loadStoreSummary();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _loadStoreSummary() async {
    try {
      final db = ref.read(databaseServiceProvider);
      final config = await db.isar.storeConfigs.where().findFirst();
      final products = await db.isar.products.count();
      final sales = await db.isar.saleTransactions.count();
      final users = await db.isar.users.count();

      if (mounted) {
        setState(() {
          _storeConfig = config;
          _productsCount = products;
          _salesCount = sales;
          _usersCount = users;
          _isLoadingSummary = false;
          // Only offer cloud purge if cloud is actually configured
          _purgeCloudVps = config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingSummary = false;
        });
      }
    }
  }

  bool get _isConfirmationValid {
    final phrase = _confirmationController.text.trim().toUpperCase();
    return (phrase == 'DELETE' || phrase == 'DELETE COMPANY') && _pinController.text.trim().isNotEmpty;
  }

  Future<void> _handleDeleteCompany() async {
    final enteredPin = _pinController.text.trim();
    final phrase = _confirmationController.text.trim().toUpperCase();

    if (!_isConfirmationValid) {
      setState(() {
        _errorMessage = 'Please type "DELETE COMPANY" and enter your owner PIN.';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final db = ref.read(databaseServiceProvider);
      final currentUser = ref.read(authProvider);

      if (currentUser == null) {
        throw Exception('No active owner session found. Please log in first.');
      }

      // Verify owner PIN locally
      final hashedInput = hashPin(enteredPin);
      if (currentUser.passwordHash != hashedInput) {
        throw Exception('Invalid Owner Passcode / PIN. Authentication failed.');
      }

      // 1. If Cloud VPS purge is requested and cloud is configured, purge remote PostgreSQL
      final cloudUrl = _storeConfig?.cloudApiUrl?.trim();
      final authToken = _storeConfig?.cloudAuthToken?.trim();

      if (_purgeCloudVps && cloudUrl != null && cloudUrl.isNotEmpty) {
        try {
          final cloudService = ref.read(cloudDatabaseServiceProvider);
          await cloudService.purgeCompanyAccount(
            baseUrl: cloudUrl,
            authToken: authToken ?? '',
            confirmPhrase: phrase,
            password: enteredPin,
          );
        } catch (cloudErr) {
          debugPrint('[CompanyDelete] Cloud purge error: $cloudErr');
          if (!mounted) return;
          // If cloud fails, notify user but allow them to decide or report error
          final continueLocal = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  const Icon(Icons.cloud_off_rounded, color: Color(0xFFF59E0B), size: 24),
                  const SizedBox(width: 10),
                  Text('Cloud Purge Warning', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ],
              ),
              content: Text(
                'Cloud VPS response: $cloudErr\n\nDo you still want to proceed with wiping the local POS terminal data completely?',
                style: GoogleFonts.inter(color: const Color(0xFFCBD5E1), fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                  child: Text('Proceed Local Wipe', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          );

          if (continueLocal != true) {
            if (mounted) {
              setState(() {
                _isProcessing = false;
                _errorMessage = 'Cloud purge was aborted: $cloudErr';
              });
            }
            return;
          }
        }
      }

      // 2. Perform local database complete wipe
      await db.purgeEntireCompanyAccount();

      // 3. Clear auth state and notify system
      await ref.read(authProvider.notifier).logout(ref);
      ref.invalidate(hasUsersProvider);
      ref.invalidate(appStartupProvider);

      if (mounted) {
        // Pop all modals/dialogs
        Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Company account has been completely deleted. System reset to factory state.',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMessage = e.toString().replaceAll('Exception:', '').trim();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
        child: Column(
          children: [
            // Danger Header Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xFF7F1D1D),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DANGER ZONE: DELETE COMPANY ACCOUNT',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Permanent Organization & POS Factory Reset',
                          style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.8), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),

            // Modal Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Critical Impact Explainer
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'THIS ACTION IS PERMANENT AND IRREVERSIBLE',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF991B1B),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Deleting the company account will permanently erase:\n'
                            '• All branch stores and company profiles under this TPIN.\n'
                            '• All sales history, refunds, and ZRA fiscal transaction logs.\n'
                            '• Complete product inventory catalog, categories, and stock movements.\n'
                            '• All supplier balances, consignment split records, and customer profiles.\n'
                            '• All staff logins ($_usersCount registered user${_usersCount == 1 ? '' : 's'}).',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF7F1D1D),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Store Stats Preview Card
                    if (_isLoadingSummary)
                      const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Target Company Account',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white60 : Colors.black54,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _storeConfig?.businessName ?? 'Beleka POS Company',
                                        style: GoogleFonts.inter(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        'TPIN: ${_storeConfig?.tpin ?? 'N/A'} • Branch: ${_storeConfig?.bhfId ?? '00'} (${_storeConfig?.branchName ?? 'Main'})',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          color: isDark ? Colors.white70 : Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    '$_salesCount Sales • $_productsCount Items',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFDC2626),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),

                    // Cloud Purge Toggle (if cloud is connected)
                    if (_storeConfig?.cloudApiUrl != null && _storeConfig!.cloudApiUrl!.trim().isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _purgeCloudVps,
                              activeColor: const Color(0xFFDC2626),
                              onChanged: _isProcessing
                                  ? null
                                  : (val) {
                                      setState(() {
                                        _purgeCloudVps = val ?? false;
                                      });
                                    },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Purge Cloud VPS Database Account',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    'Deletes all remote PostgreSQL branches and sync records on ${_storeConfig!.cloudApiUrl}',
                                    style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 18),

                    // Owner PIN Verification Input
                    Text(
                      '1. Enter Owner Passcode / PIN to Authorize',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _pinController,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      enabled: !_isProcessing,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.inter(color: isDark ? Colors.white : Colors.black),
                      decoration: InputDecoration(
                        hintText: 'Enter Owner PIN',
                        hintStyle: GoogleFonts.inter(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.lock_rounded, size: 18, color: Color(0xFF94A3B8)),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePin ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18, color: const Color(0xFF94A3B8)),
                          onPressed: () => setState(() => _obscurePin = !_obscurePin),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Confirmation Phrase Input
                    Text(
                      '2. Type "DELETE COMPANY" to confirm',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _confirmationController,
                      enabled: !_isProcessing,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.inter(
                        color: const Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                      decoration: InputDecoration(
                        hintText: 'DELETE COMPANY',
                        hintStyle: GoogleFonts.inter(color: isDark ? Colors.white24 : Colors.black26, fontSize: 13),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        prefixIcon: const Icon(Icons.delete_forever_rounded, size: 18, color: Color(0xFFDC2626)),
                      ),
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDC2626)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.inter(color: const Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Modal Action Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
                border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        'Cancel / Keep Account',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white70 : Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isConfirmationValid && !_isProcessing) ? _handleDeleteCompany : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDC2626),
                        disabledBackgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: isDark ? Colors.white30 : Colors.black26,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.delete_forever_rounded, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'PURGE COMPANY',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ],
                            ),
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
}
