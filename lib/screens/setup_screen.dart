import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math' as math;
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/cloud_database_service.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/screens/auth/backup_restore_modal.dart';
import 'package:beleka_pos/main.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int _activeTab = 0; // 0 = Create New Store, 1 = Connect Cloud Branch / Log in

  // Tab 0: New Store Setup
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _adminIdController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _serverIpController = TextEditingController();
  bool _isManagerMode = true;

  // Tab 1: Connect Existing Cloud Branch / Log in
  final _cloudFormKey = GlobalKey<FormState>();
  final _cloudUrlController = TextEditingController(text: 'http://23.139.36.20:8003');
  final _cloudStaffIdController = TextEditingController();
  final _cloudPinController = TextEditingController();
  final _cloudStoreCodeController = TextEditingController(text: 'STORE-001');

  bool _isLoading = false;
  String? _errorMessage;
  String? _statusMessage;

  @override
  void dispose() {
    _businessNameController.dispose();
    _adminIdController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _serverIpController.dispose();
    _cloudUrlController.dispose();
    _cloudStaffIdController.dispose();
    _cloudPinController.dispose();
    _cloudStoreCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleSetup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Initializing local database...';
    });

    try {
      final db = ref.read(databaseServiceProvider);
      
      // 0. Generate Recovery Code
      final recoveryCode = _generateRecoveryCode();

      // 1. Create Business Config
      final config = StoreConfig()
        ..businessName = _businessNameController.text.trim()
        ..terminalName = _isManagerMode ? 'MANAGER-01' : 'CASHIER-01'
        ..currencySymbol = 'ZK'
        ..isManagerMode = _isManagerMode
        ..serverIp = _isManagerMode ? '' : _serverIpController.text.trim()
        ..isCloudSyncEnabled = true
        ..cloudApiUrl = 'http://23.139.36.20:8003'
        ..cloudStoreId = 1
        ..cloudStoreCode = 'STORE-001'
        ..recoveryCodeHash = hashPin(recoveryCode);
      
      await db.saveStoreConfig(config);

      // 2. Create Initial Admin with hashed PIN
      final admin = User()
        ..numericId = _adminIdController.text.trim()
        ..passwordHash = hashPin(_pinController.text.trim())
        ..role = 'manager'
        ..name = 'Owner';
      
      await db.saveUser(admin);

      // 3. Create Pre-defined Multi-purpose Categories
      final defaultCategories = [
        Category(name: 'Pharmaceuticals', iconPath: 'assets/icons/pharmacy.png'),
        Category(name: 'Stationery', iconPath: 'assets/icons/stationery.png'),
        Category(name: 'Groceries', iconPath: 'assets/icons/groceries.png'),
        Category(name: 'Food & Beverage', iconPath: 'assets/icons/food.png'),
        Category(name: 'Restaurant', iconPath: 'assets/icons/restaurant.png'),
        Category(name: 'Hardware', iconPath: 'assets/icons/hardware.png'),
      ];
      await db.saveCategories(defaultCategories);

      // 4. Show Recovery Code Dialog and wait for dismissal
      if (mounted) {
        await _showRecoveryDialog(recoveryCode);
      }

      // 5. Auto-login & Navigate
      ref.read(authProvider.notifier).login(admin);
      ref.invalidate(hasUsersProvider);
      ref.invalidate(appStartupProvider);
      
    } catch (e) {
      setState(() => _errorMessage = 'Failed to initialize terminal: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  Future<void> _handleCloudLogin() async {
    if (!_cloudFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Connecting to Beleka Cloud Server...';
    });

    try {
      final db = ref.read(databaseServiceProvider);
      final cloudService = CloudDatabaseService();
      final baseUrl = _cloudUrlController.text.trim();
      final userId = _cloudStaffIdController.text.trim();
      final pin = _cloudPinController.text.trim();
      final storeCode = _cloudStoreCodeController.text.trim();

      // 1. Verify connection to Cloud Server
      final isConnected = await cloudService.checkConnection(baseUrl);
      if (!isConnected) {
        throw Exception('Cannot reach Cloud Server at $baseUrl. Verify internet connection.');
      }

      setState(() => _statusMessage = 'Fetching store branches & credentials...');

      // 2. Fetch available store branches from Cloud DB
      final stores = await cloudService.getStores(baseUrl);
      Map<String, dynamic>? targetStore;
      if (stores.isNotEmpty) {
        if (storeCode.isNotEmpty) {
          for (final s in stores) {
            final sCode = (s['store_code'] ?? '').toString().toUpperCase();
            final sName = (s['name'] ?? '').toString().toUpperCase();
            if (sCode == storeCode.toUpperCase() || sName == storeCode.toUpperCase()) {
              targetStore = s;
              break;
            }
          }
        }
        targetStore ??= stores.first;
      }

      final storeId = targetStore != null ? (targetStore['id'] as int? ?? 1) : 1;
      final storeName = targetStore != null ? (targetStore['name'] as String? ?? 'Beleka Branch') : 'Branch Store';
      final branchName = targetStore != null ? (targetStore['branch_name'] as String? ?? 'Main Branch') : 'Branch 01';
      final bhfId = targetStore != null ? (targetStore['bhf_id'] as String? ?? '00') : '00';
      final rawTpin = targetStore != null ? (targetStore['tpin'] as String?) : null;
      final tpin = (rawTpin != null && rawTpin.trim().isNotEmpty) ? rawTpin.trim() : '1234567890';
      final finalStoreCode = targetStore != null ? (targetStore['store_code'] as String? ?? storeCode) : storeCode;
      final businessTaxType = targetStore != null ? (targetStore['business_tax_type'] as String? ?? 'VAT_STANDARD') : 'VAT_STANDARD';
      final digitaxApiKey = targetStore != null ? (targetStore['digitax_api_key'] as String? ?? '') : '';
      final digitaxEnv = targetStore != null ? (targetStore['digitax_environment'] as String? ?? 'sandbox') : 'sandbox';
      final currency = targetStore != null ? (targetStore['currency_symbol'] as String? ?? 'ZK') : 'ZK';

      setState(() => _statusMessage = 'Authenticating staff user on Cloud DB...');

      // 3. Fetch cloud users for this store
      final cloudUsers = await cloudService.getUsers(baseUrl, storeId: storeId);
      Map<String, dynamic>? matchedUser;
      
      for (final u in cloudUsers) {
        if ((u['numeric_id'] ?? '').toString() == userId) {
          matchedUser = u;
          break;
        }
      }

      // 4. Save Store Config with full headquarters data
      final recoveryCode = _generateRecoveryCode();
      final config = StoreConfig()
        ..businessName = storeName
        ..branchName = branchName
        ..terminalName = 'BRANCH-TERMINAL'
        ..currencySymbol = currency
        ..isManagerMode = true
        ..isCloudSyncEnabled = true
        ..cloudApiUrl = baseUrl
        ..cloudStoreId = storeId
        ..cloudStoreCode = finalStoreCode
        ..bhfId = bhfId
        ..tpin = tpin
        ..businessTaxType = businessTaxType
        ..digitaxApiKey = digitaxApiKey
        ..digitaxEnvironment = digitaxEnv
        ..taxRate = businessTaxType == 'TURNOVER_TAX' ? 3.0 : (businessTaxType == 'EXEMPT' ? 0.0 : 16.0)
        ..recoveryCodeHash = hashPin(recoveryCode);

      await db.saveStoreConfig(config);

      // 5. Populate users from Cloud DB into local offline Isar DB
      User? activeUser;
      if (cloudUsers.isNotEmpty) {
        for (final u in cloudUsers) {
          final uNumId = (u['numeric_id'] ?? '').toString();
          final userObj = User()
            ..numericId = uNumId
            ..name = (u['name'] ?? 'Staff').toString()
            ..role = (u['role'] ?? 'cashier').toString()
            ..passwordHash = (uNumId == userId) ? hashPin(pin) : (u['password_hash'] ?? hashPin('1234'))
            ..branchName = (u['branch_name'] ?? storeName).toString()
            ..phone = u['phone']?.toString();
          
          await db.saveUser(userObj);
          if (uNumId == userId) {
            activeUser = userObj;
          }
        }
      }

      if (activeUser == null) {
        activeUser = User()
          ..numericId = userId
          ..passwordHash = hashPin(pin)
          ..name = matchedUser != null ? (matchedUser['name'] ?? 'Branch Manager') : 'Branch Manager'
          ..role = 'manager'
          ..branchName = storeName;
        await db.saveUser(activeUser);

        // Also push manager user to Cloud DB for future terminal syncs
        try {
          await cloudService.syncUser(
            baseUrl: baseUrl,
            storeId: storeId,
            user: activeUser,
            plainPin: pin,
          );
        } catch (_) {}
      }

      setState(() => _statusMessage = 'Syncing cloud catalog & products...');

      // 6. Pull products & categories from Cloud DB
      try {
        final cloudProducts = await cloudService.getProducts(baseUrl, storeId: storeId);
        if (cloudProducts.isNotEmpty) {
          final Set<String> catNames = {};
          for (final p in cloudProducts) {
            final catName = (p['category'] as String?) ?? 'General';
            catNames.add(catName);
          }
          if (catNames.isNotEmpty) {
            final catList = catNames.map((name) => Category(name: name)).toList();
            await db.saveCategories(catList);
          }

          final savedCategories = await db.getAllCategories();
          final Map<String, int> catMap = {
            for (final c in savedCategories) c.name: c.id,
          };

          for (final p in cloudProducts) {
            final catName = (p['category'] as String?) ?? 'General';
            final catId = catMap[catName] ?? 1;
            final prod = Product(
              name: (p['name'] as String?) ?? 'Product',
              sku: (p['sku'] as String?) ?? (p['barcode'] as String?) ?? 'SKU-${DateTime.now().millisecondsSinceEpoch}',
              price: (p['price'] as num?)?.toDouble() ?? 0.0,
              unitCost: (p['cost_price'] as num?)?.toDouble() ?? 0.0,
              stockLevel: (p['stock_quantity'] as num?)?.toInt() ?? 0,
              categoryId: catId,
              branchCode: bhfId,
              branchName: storeName,
            );
            await db.saveProduct(prod);
          }
        }
      } catch (e) {
        debugPrint('Cloud product pull warning: $e');
      }

      // 7. Auto-login & Navigate to POS
      ref.read(authProvider.notifier).login(activeUser);
      ref.invalidate(hasUsersProvider);
      ref.invalidate(appStartupProvider);

    } catch (e) {
      setState(() => _errorMessage = 'Cloud Login & Setup Failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
  }

  String _generateRecoveryCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = math.Random();
    String code = '';
    for (var i = 0; i < 8; i++) {
      if (i == 4) code += '-';
      code += chars[rnd.nextInt(chars.length)];
    }
    return code;
  }

  Future<void> _showRecoveryDialog(String code) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFC1F11D), size: 28),
            const SizedBox(width: 16),
            Text('SAVE RECOVERY CODE', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This code is the ONLY way to reset your Admin PIN if you forget it. Store it safely - it will not be shown again.',
              style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.2)),
              ),
              child: Center(
                child: SelectableText(
                  code,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 4,
                    color: const Color(0xFFC1F11D),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Long-press code to copy',
                style: GoogleFonts.inter(color: Colors.white24, fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC1F11D),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('I HAVE SAVED IT', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141418),
      body: Center(
        child: Container(
          width: 540,
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 40,
                offset: const Offset(0, 20),
              )
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.security_rounded, color: Color(0xFFC1F11D), size: 30),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TERMINAL INITIALIZATION',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFC1F11D),
                          ),
                        ),
                        Text(
                          'BELEKA PRO POS',
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Mode Tabs (Create New vs Cloud Branch Login)
                _buildTabSwitcher(),
                const SizedBox(height: 24),

                // Form based on active tab
                if (_activeTab == 0) _buildNewStoreForm() else _buildCloudLoginForm(),

                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (context) => const BackupRestoreModal(),
                    ),
                    icon: const Icon(Icons.settings_backup_restore_rounded, size: 16, color: Color(0xFFC1F11D)),
                    label: Text(
                      'OR RESTORE AN EXISTING BACKUP',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFC1F11D),
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabSwitcher() {
    const accentColor = Color(0xFFC1F11D);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                _activeTab = 0;
                _errorMessage = null;
              }),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _activeTab == 0 ? accentColor.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _activeTab == 0 ? accentColor.withValues(alpha: 0.4) : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      size: 16,
                      color: _activeTab == 0 ? accentColor : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'CREATE NEW STORE',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: _activeTab == 0 ? Colors.white : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: InkWell(
              onTap: () => setState(() {
                _activeTab = 1;
                _errorMessage = null;
              }),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _activeTab == 1 ? accentColor.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _activeTab == 1 ? accentColor.withValues(alpha: 0.4) : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_sync_rounded,
                      size: 16,
                      color: _activeTab == 1 ? accentColor : Colors.white38,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'CONNECT CLOUD / BRANCH',
                      style: GoogleFonts.manrope(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: _activeTab == 1 ? Colors.white : Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewStoreForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildField(
            label: 'BUSINESS NAME',
            controller: _businessNameController,
            hint: 'e.g. Beleka Boutique',
            validator: (v) => v!.isEmpty ? 'Enter business name' : null,
          ),
          const SizedBox(height: 16),
          _buildField(
            label: 'ADMIN STAFF ID (MAX 4 DIGITS)',
            controller: _adminIdController,
            hint: 'e.g. 1001',
            isStaffId: true,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Enter admin ID';
              if (v.length > 4) return 'Admin ID cannot exceed 4 digits';
              return null;
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildField(
                  label: 'SECURITY PIN (4-6 DIGITS)',
                  controller: _pinController,
                  hint: '****',
                  isPin: true,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 4) return 'Min 4 digits';
                    if (v.length > 6) return 'Max 6 digits';
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildField(
                  label: 'CONFIRM PIN',
                  controller: _confirmPinController,
                  hint: '****',
                  isPin: true,
                  validator: (v) => v != _pinController.text ? 'PINs do not match' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildSectionHeader('NETWORK TERMINAL ROLE'),
          const SizedBox(height: 12),
          _buildRoleSwitcher(),
          if (!_isManagerMode) ...[
            const SizedBox(height: 16),
            _buildField(
              label: 'MANAGER SERVER IP ADDRESS',
              controller: _serverIpController,
              hint: 'e.g. 192.168.1.100',
              validator: (v) => v!.isEmpty ? 'Manager IP is required for cashier terminals' : null,
            ),
          ],
          const SizedBox(height: 28),
          if (_errorMessage != null) _buildErrorMessage(),
          if (_statusMessage != null) _buildStatusMessage(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC1F11D),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                    )
                  : Text(
                      'INITIALIZE STORE & ADMIN',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudLoginForm() {
    return Form(
      key: _cloudFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFC1F11D).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFFC1F11D), size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Log in with your existing Branch Manager credentials to download store settings & inventory.',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          _buildField(
            label: 'CLOUD API SERVER URL',
            controller: _cloudUrlController,
            hint: 'http://23.139.36.20:8003',
            validator: (v) => v!.isEmpty ? 'Cloud Server URL is required' : null,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildField(
                  label: 'BRANCH CODE',
                  controller: _cloudStoreCodeController,
                  hint: 'STORE-001',
                  validator: (v) => v!.isEmpty ? 'Enter branch code' : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 3,
                child: _buildField(
                  label: 'STAFF / USER ID',
                  controller: _cloudStaffIdController,
                  hint: 'e.g. 1001',
                  isStaffId: true,
                  validator: (v) => v!.isEmpty ? 'Enter ID' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildField(
            label: 'PASSWORD / PIN',
            controller: _cloudPinController,
            hint: '****',
            isPin: true,
            validator: (v) => (v == null || v.isEmpty) ? 'Enter password or PIN' : null,
          ),
          const SizedBox(height: 28),
          if (_errorMessage != null) _buildErrorMessage(),
          if (_statusMessage != null) _buildStatusMessage(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleCloudLogin,
              icon: _isLoading
                  ? const SizedBox.shrink()
                  : const Icon(Icons.cloud_download_rounded, color: Colors.black, size: 20),
              label: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5),
                    )
                  : Text(
                      'CONNECT & LOG IN TO BRANCH',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC1F11D),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFC1F11D).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC1F11D)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _statusMessage!,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: 0.3),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.05))),
      ],
    );
  }

  Widget _buildRoleSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildRoleButton(
              title: 'STANDALONE / MANAGER',
              subtitle: 'Main Terminal',
              icon: Icons.store_rounded,
              isSelected: _isManagerMode,
              onTap: () => setState(() => _isManagerMode = true),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildRoleButton(
              title: 'CASHIER',
              subtitle: 'Terminal',
              icon: Icons.point_of_sale_rounded,
              isSelected: !_isManagerMode,
              onTap: () => setState(() => _isManagerMode = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final accentColor = const Color(0xFFC1F11D);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? accentColor.withValues(alpha: 0.3) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? accentColor : Colors.white24, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? Colors.white : Colors.white38,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: isSelected ? accentColor.withValues(alpha: 0.7) : Colors.white24,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
    bool isPin = false,
    bool isStaffId = false,
    String? Function(String?)? validator,
  }) {
    final int? maxDigits = isStaffId ? 4 : (isPin ? 6 : null);
    final String errorLabel = isStaffId ? "Staff ID cannot exceed 4 digits" : "PIN cannot exceed 6 digits";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 1,
              ),
            ),
            if (maxDigits != null)
              Text(
                'MAX $maxDigits DIGITS',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.25),
                  letterSpacing: 1,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isPin,
          maxLength: maxDigits,
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          keyboardType: (isPin || isStaffId) ? TextInputType.number : TextInputType.text,
          inputFormatters: [
            if (isPin || isStaffId) FilteringTextInputFormatter.digitsOnly,
            if (maxDigits != null)
              _MaxLengthFormatter(maxDigits, () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorLabel),
                    backgroundColor: Colors.orange,
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }),
          ],
          validator: (v) {
            if (isPin && v != null && v.length > 6) return 'Maximum 6 digits allowed';
            if (isStaffId && v != null && v.length > 4) return 'Maximum 4 digits allowed';
            return validator?.call(v);
          },
          style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.1), fontSize: 15),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFC1F11D), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _MaxLengthFormatter extends TextInputFormatter {
  final int maxLength;
  final VoidCallback onLimitReached;

  _MaxLengthFormatter(this.maxLength, this.onLimitReached);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length > maxLength) {
      onLimitReached();
      return oldValue;
    }
    return newValue;
  }
}
