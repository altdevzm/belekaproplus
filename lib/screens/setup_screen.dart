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
import 'package:beleka_pos/services/network_client.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/services/hwid_service.dart';
import 'package:beleka_pos/main.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  int _activeTab =
      0; // 0 = Owner Cloud Login, 1 = Create New Store, 2 = Connect Cloud Branch, 3 = Link LAN Client Till

  // Tab 0: Owner Cloud Login (Restore / HQ Master Setup)
  final _ownerFormKey = GlobalKey<FormState>();
  final _ownerUrlController = TextEditingController(
    text: 'http://23.139.36.20:8003',
  );
  final _ownerIdController = TextEditingController();
  final _ownerPinController = TextEditingController();
  final _ownerTpinController = TextEditingController();
  final _ownerStoreCodeController = TextEditingController();

  // Tab 1: New Store Setup (Offline Blank)
  final _formKey = GlobalKey<FormState>();
  final _businessNameController = TextEditingController();
  final _businessTpinController = TextEditingController();
  final _adminIdController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _serverIpController = TextEditingController();
  bool _isManagerMode = true;

  // Tab 2: Connect Existing Cloud Branch / Log in
  final _cloudFormKey = GlobalKey<FormState>();
  final _cloudUrlController = TextEditingController(
    text: 'http://23.139.36.20:8003',
  );
  final _cloudStaffIdController = TextEditingController();
  final _cloudPinController = TextEditingController();
  final _cloudTpinController = TextEditingController();
  final _cloudStoreCodeController = TextEditingController(text: 'STORE-001');

  // Tab 3: Link Client Till (LAN Till Mode)
  final _tillFormKey = GlobalKey<FormState>();
  final _tillServerIpController = TextEditingController();
  final _tillNameController = TextEditingController(text: 'TILL-01');
  bool _isTestingTillLink = false;
  String? _tillTestMessage;
  bool? _tillTestSuccess;
  Map<String, dynamic>? _detectedServerInfo;

  bool _isLoading = false;
  String? _errorMessage;
  String? _statusMessage;

  @override
  void dispose() {
    _ownerUrlController.dispose();
    _ownerIdController.dispose();
    _ownerPinController.dispose();
    _ownerTpinController.dispose();
    _ownerStoreCodeController.dispose();
    _businessNameController.dispose();
    _businessTpinController.dispose();
    _adminIdController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    _serverIpController.dispose();
    _cloudUrlController.dispose();
    _cloudStaffIdController.dispose();
    _cloudPinController.dispose();
    _cloudTpinController.dispose();
    _cloudStoreCodeController.dispose();
    _tillServerIpController.dispose();
    _tillNameController.dispose();
    super.dispose();
  }

  Future<void> _handleOwnerLogin() async {
    if (!_ownerFormKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Connecting to Beleka Cloud Server...';
    });

    try {
      final db = ref.read(databaseServiceProvider);
      final cloudService = CloudDatabaseService();
      final baseUrl = _ownerUrlController.text.trim();
      final userId = _ownerIdController.text.trim();
      final pin = _ownerPinController.text.trim();
      final ownerTpin = _ownerTpinController.text.trim();
      final storeCodeInput = _ownerStoreCodeController.text.trim();

      // 1. Verify connection to Cloud Server
      final isConnected = await cloudService.checkConnection(baseUrl);
      if (!isConnected) {
        throw Exception(
          'Cannot reach Cloud Server at $baseUrl. Verify internet connection.',
        );
      }

      setState(() => _statusMessage = 'Authenticating Owner account...');

      final login = await cloudService.authenticateUser(
        baseUrl: baseUrl,
        numericId: userId,
        pin: pin,
        tpin: ownerTpin,
        branchCode: storeCodeInput,
        terminalName: 'MANAGER-01',
      );
      final authToken = login?['token']?.toString();
      if (authToken == null || authToken.isEmpty) {
        throw const CloudAuthException(
          'Cloud login did not return a session token.',
        );
      }

      setState(
        () => _statusMessage =
            'Fetching Headquarters store profile & fiscal configs...',
      );

      // 2. Fetch available store branches from Cloud DB
      final stores = await cloudService.getStores(
        baseUrl,
        authToken: authToken,
      );
      if (stores.isEmpty) {
        throw Exception(
          'No store records found on the cloud server. Please create a new store or verify server URL.',
        );
      }

      Map<String, dynamic>? targetStore;
      if (storeCodeInput.isNotEmpty) {
        final query = storeCodeInput.trim().toUpperCase();
        for (final s in stores) {
          final sCode = (s['store_code'] ?? '').toString().toUpperCase();
          final sName = (s['name'] ?? '').toString().toUpperCase();
          final sBranch = (s['branch_name'] ?? '').toString().toUpperCase();
          final sBhf = (s['bhf_id'] ?? '').toString().toUpperCase();
          if (sCode == query ||
              sName == query ||
              sBranch == query ||
              sBhf == query) {
            targetStore = s;
            break;
          }
        }
      }

      // Default to Headquarters (bhf_id == '00') or first store
      targetStore ??= stores.firstWhere(
        (s) => (s['bhf_id'] ?? '').toString() == '00',
        orElse: () => stores.first,
      );

      final storeId = targetStore['id'] as int? ?? 1;
      final storeName =
          (targetStore['name'] as String?) ?? 'Beleka Master Store';
      final branchName =
          (targetStore['branch_name'] as String?) ?? 'Headquarters (HQ)';
      final bhfId = (targetStore['bhf_id'] as String?) ?? '00';
      final rawTpin = targetStore['tpin'] as String?;
      final tpin = (rawTpin != null && rawTpin.trim().isNotEmpty)
          ? rawTpin.trim()
          : ownerTpin;
      final finalStoreCode =
          (targetStore['store_code'] as String?) ?? 'STORE-001';
      final businessTaxType =
          (targetStore['business_tax_type'] as String?) ?? 'VAT_STANDARD';
      final digitaxApiKey = (targetStore['digitax_api_key'] as String?) ?? '';
      final digitaxEnv =
          (targetStore['digitax_environment'] as String?) ?? 'sandbox';
      final currency = (targetStore['currency_symbol'] as String?) ?? 'ZK';

      // 3. Fetch cloud users for this store
      final cloudUsers = await cloudService.getUsers(
        baseUrl,
        storeId: storeId,
        authToken: authToken,
      );
      Map<String, dynamic>? matchedUser;

      for (final u in cloudUsers) {
        final uNumId = (u['numeric_id'] ?? '').toString();
        if (uNumId == userId) {
          matchedUser = u;
          break;
        }
      }

      // 4. Save Store Config with full HQ master data
      final recoveryCode = _generateRecoveryCode();
      final config = StoreConfig()
        ..businessName = storeName
        ..branchName = branchName
        ..terminalName = 'MANAGER-01'
        ..currencySymbol = currency
        ..isManagerMode = true
        ..isCloudSyncEnabled = true
        ..cloudApiUrl = baseUrl
        ..cloudStoreId = storeId
        ..cloudStoreCode = finalStoreCode
        ..cloudAuthToken = authToken
        ..cloudAuthUserId = userId
        ..cloudAuthPin = pin
        ..bhfId = bhfId
        ..tpin = tpin
        ..businessTaxType = businessTaxType
        ..digitaxApiKey = digitaxApiKey
        ..digitaxEnvironment = digitaxEnv
        ..taxRate = businessTaxType == 'TURNOVER_TAX'
            ? 3.0
            : (businessTaxType == 'EXEMPT' ? 0.0 : 16.0)
        ..recoveryCodeHash = hashPin(recoveryCode);

      await db.saveStoreConfig(config);

      // 5. Populate users from Cloud DB into local offline Isar DB
      User? activeOwner;
      if (cloudUsers.isNotEmpty) {
        for (final u in cloudUsers) {
          final uNumId = (u['numeric_id'] ?? '').toString();
          final isTarget = (uNumId == userId);
          final userObj = User()
            ..numericId = uNumId
            ..name = (u['name'] ?? (isTarget ? 'Owner' : 'Staff')).toString()
            ..role = (isTarget ? 'owner' : (u['role'] ?? 'cashier').toString())
            ..passwordHash = isTarget
                ? hashPin(pin)
                : (u['password_hash'] ?? hashPin('1234'))
            ..branchName = (u['branch_name'] ?? branchName).toString()
            ..branchCode = bhfId
            ..phone = u['phone']?.toString();

          await db.saveUser(userObj);
          if (isTarget) {
            activeOwner = userObj;
          }
        }
      }

      if (activeOwner == null) {
        activeOwner = User()
          ..numericId = userId
          ..passwordHash = hashPin(pin)
          ..name = matchedUser != null
              ? (matchedUser['name'] ?? 'Store Owner')
              : 'Store Owner'
          ..role = 'owner'
          ..branchName = branchName
          ..branchCode = bhfId;
        await db.saveUser(activeOwner);

        // Also push owner user to Cloud DB
        try {
          await cloudService.syncUser(
            baseUrl: baseUrl,
            storeId: storeId,
            user: activeOwner,
            plainPin: pin,
            authToken: authToken,
          );
        } catch (_) {}
      }

      // 6. Pull products & categories from Cloud DB into local database
      setState(
        () => _statusMessage =
            'Downloading master product catalog and inventory...',
      );
      try {
        final cloudProducts = await cloudService.getProducts(
          baseUrl,
          storeId: storeId,
          authToken: authToken,
        );
        if (cloudProducts.isNotEmpty) {
          final Set<String> catNames = {};
          for (final p in cloudProducts) {
            final catName = (p['category'] as String?) ?? 'General';
            catNames.add(catName);
          }
          if (catNames.isNotEmpty) {
            final catList = catNames
                .map((name) => Category(name: name))
                .toList();
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
              sku:
                  (p['sku'] as String?) ??
                  (p['barcode'] as String?) ??
                  'SKU-${DateTime.now().millisecondsSinceEpoch}',
              price: (p['price'] as num?)?.toDouble() ?? 0.0,
              unitCost: (p['cost_price'] as num?)?.toDouble() ?? 0.0,
              stockLevel: (p['stock_quantity'] as num?)?.toInt() ?? 0,
              categoryId: catId,
              branchCode: bhfId,
              branchName: branchName,
            );
            await db.saveProduct(prod);
          }
        }
      } catch (e) {
        debugPrint('Cloud product pull notice: $e');
      }

      // 7. Show Recovery Dialog
      if (mounted) {
        await _showRecoveryDialog(recoveryCode);
      }

      // 8. Auto-login & Navigate to POS Shell
      ref.read(authProvider.notifier).login(activeOwner);
      ref.invalidate(hasUsersProvider);
      ref.invalidate(appStartupProvider);
      ref.invalidate(storeConfigProvider);
    } catch (e) {
      setState(() => _errorMessage = 'Owner Login Failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = null;
        });
      }
    }
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
      final cloudService = CloudDatabaseService();
      final businessName = _businessNameController.text.trim();
      final tpin = _businessTpinController.text.trim();
      final adminId = _adminIdController.text.trim();
      final pin = _pinController.text.trim();

      setState(() => _statusMessage = 'Registering organization securely...');
      final registration = await cloudService.registerOrganization(
        baseUrl: _ownerUrlController.text.trim(),
        businessName: businessName,
        tpin: tpin,
        numericId: adminId,
        pin: pin,
      );
      if (registration == null) {
        throw const CloudAuthException('Cloud registration returned no account.');
      }
      final registeredUser = Map<String, dynamic>.from(registration['user'] as Map);
      final registeredStore = Map<String, dynamic>.from(registration['store'] as Map);
      final authToken = registration['token']?.toString() ?? '';

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
        ..cloudApiUrl = _ownerUrlController.text.trim()
        ..cloudStoreId = (registeredStore['id'] as num?)?.toInt()
        ..cloudStoreCode = registeredStore['store_code']?.toString() ?? 'HQ-00'
        ..digitaxApiKey = null
        ..tpin = registeredStore['tpin']?.toString() ?? tpin
        ..bhfId = registeredStore['bhf_id']?.toString() ?? '00'
        ..cloudAuthToken = authToken
        ..cloudAuthUserId = registeredUser['numeric_id']?.toString() ?? adminId
        ..cloudAuthPin = pin
        ..recoveryCodeHash = hashPin(recoveryCode);

      await db.saveStoreConfig(config);

      // 2. Create Initial Admin with hashed PIN
      final admin = User()
        ..numericId = registeredUser['numeric_id']?.toString() ?? adminId
        ..passwordHash = hashPin(pin)
        ..role = registeredUser['role']?.toString() ?? 'owner'
        ..name = registeredUser['name']?.toString() ?? 'Owner'
        ..branchCode = '00'
        ..branchName = 'Headquarters (HQ)';

      await db.saveUser(admin);

      // 3. Create Pre-defined Multi-purpose Categories
      final defaultCategories = [
        Category(
          name: 'Pharmaceuticals',
          iconPath: 'assets/icons/pharmacy.png',
        ),
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
      final loginTpin = _cloudTpinController.text.trim();
      final storeCode = _cloudStoreCodeController.text.trim();

      // 1. Verify connection to Cloud Server
      final isConnected = await cloudService.checkConnection(baseUrl);
      if (!isConnected) {
        throw Exception(
          'Cannot reach Cloud Server at $baseUrl. Verify internet connection.',
        );
      }

      setState(
        () => _statusMessage = 'Authenticating staff user on Cloud DB...',
      );

      final login = await cloudService.authenticateUser(
        baseUrl: baseUrl,
        numericId: userId,
        pin: pin,
        tpin: loginTpin,
        branchCode: _cloudStoreCodeController.text.trim(),
        terminalName: 'BRANCH-TERMINAL',
      );
      final authToken = login?['token']?.toString();
      if (authToken == null || authToken.isEmpty) {
        throw Exception(
          'Cloud login rejected. Verify the organization TPIN, user ID, and PIN.',
        );
      }

      setState(
        () => _statusMessage = 'Fetching store branches & credentials...',
      );

      // 2. Fetch available store branches from Cloud DB
      final stores = await cloudService.getStores(
        baseUrl,
        authToken: authToken,
      );
      Map<String, dynamic>? targetStore;
      if (stores.isNotEmpty) {
        if (storeCode.isNotEmpty) {
          final query = storeCode.trim().toUpperCase();
          for (final s in stores) {
            final sCode = (s['store_code'] ?? '').toString().toUpperCase();
            final sName = (s['name'] ?? '').toString().toUpperCase();
            final sBranch = (s['branch_name'] ?? '').toString().toUpperCase();
            final sBhf = (s['bhf_id'] ?? '').toString().toUpperCase();
            if (sCode == query ||
                sName == query ||
                sBranch == query ||
                sBhf == query) {
              targetStore = s;
              break;
            }
          }
        }
        targetStore ??= stores.first;
      }

      final storeId = targetStore != null
          ? (targetStore['id'] as int? ?? 1)
          : 1;
      final storeName = targetStore != null
          ? (targetStore['name'] as String? ?? 'Beleka Branch')
          : 'Branch Store';
      final branchName = targetStore != null
          ? (targetStore['branch_name'] as String? ?? 'Main Branch')
          : 'Branch 01';
      final bhfId = targetStore != null
          ? (targetStore['bhf_id'] as String? ?? '00')
          : '00';
      final rawTpin = targetStore != null
          ? (targetStore['tpin'] as String?)
          : null;
      final tpin = (rawTpin != null && rawTpin.trim().isNotEmpty)
          ? rawTpin.trim()
          : loginTpin;
      final finalStoreCode = targetStore != null
          ? (targetStore['store_code'] as String? ?? storeCode)
          : storeCode;
      final businessTaxType = targetStore != null
          ? (targetStore['business_tax_type'] as String? ?? 'VAT_STANDARD')
          : 'VAT_STANDARD';
      final digitaxApiKey = targetStore != null
          ? (targetStore['digitax_api_key'] as String? ?? '')
          : '';
      final digitaxEnv = targetStore != null
          ? (targetStore['digitax_environment'] as String? ?? 'sandbox')
          : 'sandbox';
      final currency = targetStore != null
          ? (targetStore['currency_symbol'] as String? ?? 'ZK')
          : 'ZK';

      setState(
        () => _statusMessage = 'Authenticating staff user on Cloud DB...',
      );

      // 3. Fetch cloud users for this store
      final cloudUsers = await cloudService.getUsers(
        baseUrl,
        storeId: storeId,
        authToken: authToken,
      );
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
        ..cloudAuthToken = authToken
        ..cloudAuthUserId = userId
        ..cloudAuthPin = pin
        ..bhfId = bhfId
        ..tpin = tpin
        ..businessTaxType = businessTaxType
        ..digitaxApiKey = digitaxApiKey
        ..digitaxEnvironment = digitaxEnv
        ..taxRate = businessTaxType == 'TURNOVER_TAX'
            ? 3.0
            : (businessTaxType == 'EXEMPT' ? 0.0 : 16.0)
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
            ..passwordHash = (uNumId == userId)
                ? hashPin(pin)
                : (u['password_hash'] ?? hashPin('1234'))
            ..branchName = (u['branch_name'] ?? storeName).toString()
            ..branchCode = bhfId
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
          ..name = matchedUser != null
              ? (matchedUser['name'] ?? 'Branch Manager')
              : 'Branch Manager'
          ..role = 'manager'
          ..branchName = storeName
          ..branchCode = bhfId;
        await db.saveUser(activeUser);

        // Also push manager user to Cloud DB for future terminal syncs
        try {
          await cloudService.syncUser(
            baseUrl: baseUrl,
            storeId: storeId,
            user: activeUser,
            plainPin: pin,
            authToken: authToken,
          );
        } catch (_) {}
      }

      // 6. Pull products & categories from Cloud DB ONLY IF HEADQUARTERS ('00')
      // Branch terminals ('01', '02', etc.) maintain their own isolated local stock.
      if (bhfId == '00') {
        setState(() => _statusMessage = 'Syncing master catalog & products...');
        try {
          final cloudProducts = await cloudService.getProducts(
            baseUrl,
            storeId: storeId,
            authToken: authToken,
          );
          if (cloudProducts.isNotEmpty) {
            final Set<String> catNames = {};
            for (final p in cloudProducts) {
              final catName = (p['category'] as String?) ?? 'General';
              catNames.add(catName);
            }
            if (catNames.isNotEmpty) {
              final catList = catNames
                  .map((name) => Category(name: name))
                  .toList();
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
                sku:
                    (p['sku'] as String?) ??
                    (p['barcode'] as String?) ??
                    'SKU-${DateTime.now().millisecondsSinceEpoch}',
                price: (p['price'] as num?)?.toDouble() ?? 0.0,
                unitCost: (p['cost_price'] as num?)?.toDouble() ?? 0.0,
                stockLevel: (p['stock_quantity'] as num?)?.toInt() ?? 0,
                categoryId: catId,
                branchCode: '00',
                branchName: storeName,
              );
              await db.saveProduct(prod);
            }
          }
        } catch (e) {
          debugPrint('Cloud product pull warning: $e');
        }
      } else {
        debugPrint(
          'Branch setup initialized with isolated stock (bhfId: $bhfId). HQ products skipped.',
        );
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

  Future<void> _handleTestTillLink() async {
    final ip = _tillServerIpController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _tillTestMessage = 'Please enter the Master POS IP address.';
        _tillTestSuccess = false;
      });
      return;
    }

    setState(() {
      _isTestingTillLink = true;
      _tillTestMessage = null;
      _tillTestSuccess = null;
      _detectedServerInfo = null;
    });

    try {
      final client = NetworkClient(serverUrl: 'http://$ip:8080');
      final info = await client.getServerInfo(ip);
      if (info != null) {
        final bName =
            info['businessName'] ?? info['serverName'] ?? 'Master POS';
        final branch = info['branchName'] ?? 'Branch ${info['bhfId'] ?? '00'}';
        final bhfId = info['bhfId'] ?? '00';
        setState(() {
          _isTestingTillLink = false;
          _tillTestSuccess = true;
          _detectedServerInfo = info;
          _tillTestMessage =
              'Connected to $bName ($branch • ZRA bhfId: $bhfId)';
        });
      } else {
        setState(() {
          _isTestingTillLink = false;
          _tillTestSuccess = false;
          _tillTestMessage =
              'Could not reach Master POS on $ip:8080. Ensure Master POS is running on the same network.';
        });
      }
    } catch (e) {
      setState(() {
        _isTestingTillLink = false;
        _tillTestSuccess = false;
        _tillTestMessage = 'Connection failed: $e';
      });
    }
  }

  Future<void> _handleLinkClientTill() async {
    if (!_tillFormKey.currentState!.validate()) return;

    final ip = _tillServerIpController.text.trim();
    final tillName = _tillNameController.text.trim().toUpperCase();

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _statusMessage = 'Connecting to Master Branch POS ($ip:8080)...';
    });

    try {
      final client = NetworkClient(serverUrl: 'http://$ip:8080');
      final info = _detectedServerInfo ?? await client.getServerInfo(ip);

      if (info == null) {
        throw Exception(
          'Unable to reach Master POS at $ip:8080. Check Wi-Fi and IP address.',
        );
      }

      final db = ref.read(databaseServiceProvider);
      final isar = ref.read(isarProvider);

      setState(() => _statusMessage = 'Configuring local till profile...');

      final bName =
          (info['businessName'] ?? info['serverName'] ?? 'Beleka POS Store')
              .toString();
      final branch = (info['branchName'] ?? 'Main Branch').toString();
      final bhfId = (info['bhfId'] ?? info['branchCode'] ?? '00').toString();
      final currency = (info['currencySymbol'] ?? 'ZK').toString();
      final tpin = (info['tpin'] ?? '').toString();
      final taxType = (info['businessTaxType'] ?? 'TURNOVER_TAX').toString();

      final config = StoreConfig()
        ..businessName = bName
        ..branchName = branch
        ..bhfId = bhfId
        ..currencySymbol = currency
        ..tpin = tpin
        ..businessTaxType = taxType
        ..terminalName = tillName
        ..isManagerMode = false
        ..serverIp = ip
        ..port = 8080
        ..isCloudSyncEnabled = false;

      await db.saveStoreConfig(config);

      // Perform handshake registration on Master POS server so it immediately shows up on Master dashboard
      setState(
        () => _statusMessage = 'Registering till with Master POS server...',
      );
      try {
        final hwid = await HwidService().getHardwareId();
        await client.registerTerminal(
          terminalCode: tillName,
          name: 'Cashier Till ($tillName)',
          hardwareId: hwid,
          branchCode: bhfId,
        );
      } catch (e) {
        debugPrint('Till registration handshake notice: $e');
      }

      setState(
        () => _statusMessage =
            'Downloading catalog & categories from Master POS...',
      );
      try {
        final categories = await client.fetchCategories();
        if (categories.isNotEmpty) {
          await isar.writeTxn(() async {
            await isar.categorys.putAll(categories);
          });
        }
      } catch (e) {
        debugPrint('Till categories pull warning: $e');
      }

      try {
        final products = await client.fetchProducts();
        if (products.isNotEmpty) {
          await isar.writeTxn(() async {
            await isar.products.putAll(products);
          });
        }
      } catch (e) {
        debugPrint('Till products pull warning: $e');
      }

      setState(
        () =>
            _statusMessage = 'Downloading staff & cashiers from Master POS...',
      );
      try {
        final users = await client.fetchUsers();
        if (users.isNotEmpty) {
          await isar.writeTxn(() async {
            for (final uMap in users) {
              final numericId = (uMap['numericId'] ?? '').toString();
              if (numericId.isEmpty) continue;
              final existing = await isar.users
                  .filter()
                  .numericIdEqualTo(numericId)
                  .findFirst();
              final u = existing ?? User();
              u.numericId = numericId;
              u.name = (uMap['name'] ?? 'Staff $numericId').toString();
              u.role = (uMap['role'] ?? 'cashier').toString();
              u.branchCode = bhfId;
              u.branchName = branch;
              u.isActive = uMap['isActive'] == true;
              if (uMap['passwordHash'] != null &&
                  uMap['passwordHash'].toString().isNotEmpty) {
                u.passwordHash = uMap['passwordHash'].toString();
              } else if (u.passwordHash.isEmpty) {
                u.passwordHash = hashPin('1234');
              }
              await isar.users.put(u);
            }
          });
        }
      } catch (e) {
        debugPrint('Till users pull warning: $e');
      }

      // If no users were downloaded, create a fallback cashier user
      final hasLocalUsers = await db.hasUsers();
      if (!hasLocalUsers) {
        final fallbackCashier = User()
          ..numericId = '1001'
          ..name = 'Cashier 1'
          ..role = 'cashier'
          ..passwordHash = hashPin('1234')
          ..branchCode = bhfId
          ..branchName = branch
          ..isActive = true;
        await db.saveUser(fallbackCashier);
      }

      // Invalidate providers to transition to LoginScreen
      ref.invalidate(hasUsersProvider);
      ref.invalidate(appStartupProvider);
      ref.invalidate(storeConfigProvider);
    } catch (e) {
      setState(() => _errorMessage = 'Till Link Failed: $e');
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const primaryAccent = Color(0xFF1D4ED8);

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Color(0xFFD97706),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'SAVE RECOVERY CODE',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
                fontSize: 16,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This code is the ONLY way to reset your Admin PIN if you forget it. Store it safely - it will not be shown again.',
              style: GoogleFonts.inter(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12.5,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0B1220)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryAccent.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: SelectableText(
                  code,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: isDark
                        ? const Color(0xFF60A5FA)
                        : const Color(0xFF1D4ED8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Long-press code to copy',
                style: GoogleFonts.inter(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'I HAVE SAVED IT',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    final bgColor = isDark ? const Color(0xFF0B1220) : const Color(0xFFF5F7FA);
    final cardBg = isDark ? const Color(0xFF151F32) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryAccent = Color(0xFF1D4ED8);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: Container(
          width: 640,
          margin: EdgeInsets.symmetric(
            vertical: isMobile ? 8 : 24,
            horizontal: isMobile ? 8 : 16,
          ),
          padding: EdgeInsets.all(isMobile ? 16 : 32),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.06),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
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
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.security_rounded,
                        color: primaryAccent,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TERMINAL INITIALIZATION',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w800,
                            color: primaryAccent,
                          ),
                        ),
                        Text(
                          'BELEKA POS',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Mode Tabs (Owner Login vs New Store vs Cloud Branch vs LAN Till)
                _buildTabSwitcher(context),
                const SizedBox(height: 20),

                // Form based on active tab
                if (_activeTab == 0)
                  _buildOwnerLoginForm(context)
                else if (_activeTab == 1)
                  _buildNewStoreForm(context)
                else if (_activeTab == 2)
                  _buildCloudLoginForm(context)
                else
                  _buildLanTillForm(context),

                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (context) => const BackupRestoreModal(),
                    ),
                    icon: const Icon(
                      Icons.settings_backup_restore_rounded,
                      size: 15,
                      color: primaryAccent,
                    ),
                    label: Text(
                      'OR RESTORE AN EXISTING BACKUP',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: primaryAccent,
                        letterSpacing: 0.5,
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

  Widget _buildTabSwitcher(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tabBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryAccent = Color(0xFF1D4ED8);
    final isMobile = MediaQuery.of(context).size.width < 520;

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: tabBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    context,
                    0,
                    'OWNER LOGIN',
                    Icons.admin_panel_settings_rounded,
                    primaryAccent,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildTabButton(
                    context,
                    1,
                    'NEW STORE',
                    Icons.storefront_rounded,
                    primaryAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    context,
                    2,
                    'BRANCH',
                    Icons.cloud_sync_rounded,
                    primaryAccent,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildTabButton(
                    context,
                    3,
                    'LINK TILL',
                    Icons.lan_rounded,
                    primaryAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: tabBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              context,
              0,
              'OWNER LOGIN',
              Icons.admin_panel_settings_rounded,
              primaryAccent,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _buildTabButton(
              context,
              1,
              'NEW STORE',
              Icons.storefront_rounded,
              primaryAccent,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _buildTabButton(
              context,
              2,
              'BRANCH',
              Icons.cloud_sync_rounded,
              primaryAccent,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _buildTabButton(
              context,
              3,
              'LINK TILL',
              Icons.lan_rounded,
              primaryAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton(
    BuildContext context,
    int index,
    String label,
    IconData icon,
    Color primaryAccent,
  ) {
    final theme = Theme.of(context);
    final isSelected = _activeTab == index;

    return InkWell(
      onTap: () => setState(() {
        _activeTab = index;
        _errorMessage = null;
      }),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? primaryAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? Colors.white
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? Colors.white
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanTillForm(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final infoBg = isDark ? const Color(0xFF1E283D) : const Color(0xFFF0F9FF);
    final infoBorder = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFBAE6FD);
    const primaryAccent = Color(0xFF1D4ED8);

    return Form(
      key: _tillFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: infoBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: infoBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF0284C7),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Link this computer as a Cashier Till to the Master POS terminal running in your branch.',
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurface,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          _buildField(
            context: context,
            label: 'TILL CODE / IDENTIFIER',
            controller: _tillNameController,
            hint: 'e.g. TILL-01, CHECKOUT-2',
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter till identifier' : null,
          ),
          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _buildField(
                  context: context,
                  label: 'MASTER POS IP ADDRESS',
                  controller: _tillServerIpController,
                  hint: 'e.g. 192.168.1.100',
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter Master POS IP' : null,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _isTestingTillLink ? null : _handleTestTillLink,
                  icon: _isTestingTillLink
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.network_check_rounded, size: 16),
                  label: Text(
                    'TEST LINK',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? const Color(0xFF1C283D)
                        : const Color(0xFFE2E8F0),
                    foregroundColor: theme.colorScheme.onSurface,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_tillTestMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _tillTestSuccess == true
                    ? const Color(0xFFECFDF5)
                    : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _tillTestSuccess == true
                      ? const Color(0xFFA7F3D0)
                      : const Color(0xFFFECACA),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _tillTestSuccess == true
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    color: _tillTestSuccess == true
                        ? const Color(0xFF059669)
                        : const Color(0xFFDC2626),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _tillTestMessage!,
                      style: GoogleFonts.inter(
                        color: _tillTestSuccess == true
                            ? const Color(0xFF047857)
                            : const Color(0xFFB91C1C),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          if (_statusMessage != null) ...[
            _buildStatusMessage(context),
            const SizedBox(height: 14),
          ],

          if (_errorMessage != null) ...[
            _buildErrorMessage(context),
            const SizedBox(height: 14),
          ],

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLinkClientTill,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.link_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'LINK THIS TILL & LAUNCH POS',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerLoginForm(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final infoBg = isDark ? const Color(0xFF1E283D) : const Color(0xFFF0F9FF);
    final infoBorder = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFBAE6FD);
    const primaryAccent = Color(0xFF1D4ED8);

    return Form(
      key: _ownerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: infoBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: infoBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFF0284C7),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Log in with your existing Owner / Master account to restore your store profile, DigiTax ZRA settings, staff users, and product catalog.',
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurface,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildField(
            context: context,
            label: 'CLOUD API SERVER URL',
            controller: _ownerUrlController,
            hint: 'http://23.139.36.20:8003',
            validator: (v) => (v == null || v.isEmpty)
                ? 'Cloud Server URL is required'
                : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildField(
                  context: context,
                  label: 'OWNER USER / STAFF ID',
                  controller: _ownerIdController,
                  hint: 'e.g. 1001 or admin',
                  isStaffId: true,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Enter Owner ID' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildField(
                  context: context,
                  label: 'STORE CODE (OPTIONAL)',
                  controller: _ownerStoreCodeController,
                  hint: 'Auto-detects HQ',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildField(
            context: context,
            label: 'ORGANIZATION TPIN',
            controller: _ownerTpinController,
            hint: 'Your organization TPIN',
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter organization TPIN'
                : null,
          ),
          const SizedBox(height: 14),
          _buildField(
            context: context,
            label: 'OWNER PASSWORD / PIN',
            controller: _ownerPinController,
            hint: '****',
            isPin: true,
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter Owner Password or PIN' : null,
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null) _buildErrorMessage(context),
          if (_statusMessage != null) _buildStatusMessage(context),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleOwnerLogin,
              icon: _isLoading
                  ? const SizedBox.shrink()
                  : const Icon(
                      Icons.cloud_download_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
              label: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      'RESTORE & LOG IN AS OWNER',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewStoreForm(BuildContext context) {
    const primaryAccent = Color(0xFF1D4ED8);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildField(
            context: context,
            label: 'CLOUD API SERVER URL',
            controller: _ownerUrlController,
            hint: 'http://23.139.36.20:8003',
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Cloud Server URL is required'
                : null,
          ),
          const SizedBox(height: 14),
          _buildField(
            context: context,
            label: 'BUSINESS NAME',
            controller: _businessNameController,
            hint: 'e.g. Beleka Boutique',
            validator: (v) => v!.isEmpty ? 'Enter business name' : null,
          ),
          const SizedBox(height: 14),
          _buildField(
            context: context,
            label: 'ORGANIZATION TPIN',
            controller: _businessTpinController,
            hint: '10-digit organization TPIN',
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter organization TPIN'
                : null,
          ),
          const SizedBox(height: 14),
          _buildField(
            context: context,
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildField(
                  context: context,
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
              const SizedBox(width: 12),
              Expanded(
                child: _buildField(
                  context: context,
                  label: 'CONFIRM PIN',
                  controller: _confirmPinController,
                  hint: '****',
                  isPin: true,
                  validator: (v) =>
                      v != _pinController.text ? 'PINs do not match' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildSectionHeader(context, 'NETWORK TERMINAL ROLE'),
          const SizedBox(height: 10),
          _buildRoleSwitcher(context),
          if (!_isManagerMode) ...[
            const SizedBox(height: 14),
            _buildField(
              context: context,
              label: 'MANAGER SERVER IP ADDRESS',
              controller: _serverIpController,
              hint: 'e.g. 192.168.1.100',
              validator: (v) => v!.isEmpty
                  ? 'Manager IP is required for cashier terminals'
                  : null,
            ),
          ],
          const SizedBox(height: 20),
          if (_errorMessage != null) _buildErrorMessage(context),
          if (_statusMessage != null) _buildStatusMessage(context),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSetup,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      'INITIALIZE STORE & ADMIN',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCloudLoginForm(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final infoBg = isDark ? const Color(0xFF1E283D) : const Color(0xFFF0F9FF);
    final infoBorder = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFBAE6FD);
    const primaryAccent = Color(0xFF1D4ED8);

    return Form(
      key: _cloudFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: infoBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: infoBorder),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF0284C7),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Log in with your existing Branch Manager credentials to download store settings & inventory.',
                    style: GoogleFonts.inter(
                      color: theme.colorScheme.onSurface,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildField(
            context: context,
            label: 'CLOUD API SERVER URL',
            controller: _cloudUrlController,
            hint: 'http://23.139.36.20:8003',
            validator: (v) =>
                v!.isEmpty ? 'Cloud Server URL is required' : null,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _buildField(
                  context: context,
                  label: 'BRANCH CODE',
                  controller: _cloudStoreCodeController,
                  hint: 'STORE-001',
                  validator: (v) => v!.isEmpty ? 'Enter branch code' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: _buildField(
                  context: context,
                  label: 'STAFF / USER ID',
                  controller: _cloudStaffIdController,
                  hint: 'e.g. 1001',
                  isStaffId: true,
                  validator: (v) => v!.isEmpty ? 'Enter ID' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildField(
            context: context,
            label: 'ORGANIZATION TPIN',
            controller: _cloudTpinController,
            hint: 'Your organization TPIN',
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter organization TPIN'
                : null,
          ),
          const SizedBox(height: 14),
          _buildField(
            context: context,
            label: 'PASSWORD / PIN',
            controller: _cloudPinController,
            hint: '****',
            isPin: true,
            validator: (v) =>
                (v == null || v.isEmpty) ? 'Enter password or PIN' : null,
          ),
          const SizedBox(height: 20),
          if (_errorMessage != null) _buildErrorMessage(context),
          if (_statusMessage != null) _buildStatusMessage(context),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _handleCloudLogin,
              icon: _isLoading
                  ? const SizedBox.shrink()
                  : const Icon(
                      Icons.cloud_download_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
              label: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      'CONNECT & LOG IN TO BRANCH',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.5,
                      ),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFDC2626),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.inter(
                color: const Color(0xFFB91C1C),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessage(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final infoBg = isDark ? const Color(0xFF1E283D) : const Color(0xFFF0F9FF);
    final infoBorder = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFBAE6FD);
    const primaryAccent = Color(0xFF1D4ED8);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: infoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: infoBorder),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primaryAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _statusMessage!,
              style: GoogleFonts.inter(
                color: theme.colorScheme.onSurface,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dividerColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);

    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Divider(color: dividerColor)),
      ],
    );
  }

  Widget _buildRoleSwitcher(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    final isMobile = MediaQuery.of(context).size.width < 500;

    if (isMobile) {
      return Column(
        children: [
          _buildRoleButton(
            context: context,
            title: 'STANDALONE / MANAGER',
            subtitle: 'Main Master Terminal',
            icon: Icons.store_rounded,
            isSelected: _isManagerMode,
            onTap: () => setState(() => _isManagerMode = true),
          ),
          const SizedBox(height: 8),
          _buildRoleButton(
            context: context,
            title: 'CASHIER TERMINAL',
            subtitle: 'Client LAN Till',
            icon: Icons.point_of_sale_rounded,
            isSelected: !_isManagerMode,
            onTap: () => setState(() => _isManagerMode = false),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildRoleButton(
              context: context,
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
              context: context,
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
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const primaryAccent = Color(0xFF1D4ED8);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryAccent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? primaryAccent
                : (isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(
              icon,
              color: isSelected
                  ? primaryAccent
                  : theme.colorScheme.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: isSelected
                          ? primaryAccent
                          : theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      color: isSelected
                          ? primaryAccent.withValues(alpha: 0.8)
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    required String hint,
    bool isPin = false,
    bool isStaffId = false,
    String? Function(String?)? validator,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final int? maxDigits = isStaffId ? 4 : (isPin ? 6 : null);
    final String errorLabel = isStaffId
        ? "Staff ID cannot exceed 4 digits"
        : "PIN cannot exceed 6 digits";

    final fieldBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    const primaryAccent = Color(0xFF1D4ED8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
            if (maxDigits != null)
              Text(
                'MAX $maxDigits DIGITS',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                  letterSpacing: 0.5,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: isPin,
          maxLength: maxDigits,
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
          keyboardType: (isPin || isStaffId)
              ? TextInputType.number
              : TextInputType.text,
          inputFormatters: [
            if (isPin || isStaffId) FilteringTextInputFormatter.digitsOnly,
            if (maxDigits != null)
              _MaxLengthFormatter(maxDigits, () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(errorLabel),
                    backgroundColor: const Color(0xFFD97706),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }),
          ],
          validator: (v) {
            if (isPin && v != null && v.length > 6)
              return 'Maximum 6 digits allowed';
            if (isStaffId && v != null && v.length > 4)
              return 'Maximum 4 digits allowed';
            return validator?.call(v);
          },
          style: GoogleFonts.inter(
            color: theme.colorScheme.onSurface,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              fontSize: 14,
            ),
            filled: true,
            fillColor: fieldBg,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: primaryAccent, width: 1.5),
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
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length > maxLength) {
      onLimitReached();
      return oldValue;
    }
    return newValue;
  }
}
