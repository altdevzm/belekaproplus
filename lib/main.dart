import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/theme/app_theme.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/license_service.dart';
import 'package:beleka_pos/screens/auth/activation_screen.dart';
import 'package:beleka_pos/screens/setup_screen.dart';
import 'package:beleka_pos/screens/login_screen.dart';
import 'package:beleka_pos/screens/shell_screen.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:beleka_pos/services/network_manager.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/barcode_service.dart';

import 'package:beleka_pos/services/local_sql_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
  
  try {
    LocalSqlService? localSqlService;
    try {
      // Initialize Local SQLite SQL Database
      localSqlService = await LocalSqlService.init();
    } catch (e) {
      debugPrint('LocalSqlService init notice: $e');
    }

    final dir = await getApplicationDocumentsDirectory();
    final isar = Isar.getInstance() ?? await Isar.open(
      [
        UserSchema,
        CategorySchema,
        ProductSchema,
        SaleTransactionSchema,
        SaleItemSchema,
        AttendanceLogSchema,
        StoreConfigSchema,
        CustomerSchema,
        SupplierSchema,
        PurchaseOrderSchema,
        PurchaseOrderItemSchema,
        GoodsReceivedNoteSchema,
        PurchaseInvoiceSchema,
        PurchaseReturnSchema,
        PaymentAccountSchema,
        ExpenseSchema,
        AccountTransferSchema,
        CashShiftSchema,
        RefundTransactionSchema,
        StoreBranchSchema,
        PosTerminalSchema,
      ],
      directory: dir.path,
    );

    // Purge any legacy dummy mock seed branches from earlier development versions
    try {
      final legacyMockBranches = await isar.storeBranchs.filter().codeEqualTo('KT-002').or().codeEqualTo('ND-003').or().codeEqualTo('HQ-001').findAll();
      if (legacyMockBranches.isNotEmpty) {
        await isar.writeTxn(() async {
          for (final b in legacyMockBranches) {
            await isar.storeBranchs.delete(b.id);
          }
        });
      }

      // Automatic product deduplication purge (strictly branch isolated)
      final allProducts = await isar.products.where().findAll();
      final Map<String, Product> uniqueMap = {};
      final List<Id> duplicateProductIds = [];
      for (final p in allProducts) {
        final key = '${p.branchCode}_${p.name.trim().toLowerCase()}';
        if (p.name.trim().isEmpty) continue;
        if (uniqueMap.containsKey(key)) {
          final existing = uniqueMap[key]!;
          if (p.stockLevel > existing.stockLevel) existing.stockLevel = p.stockLevel;
          duplicateProductIds.add(p.id);
        } else {
          uniqueMap[key] = p;
        }
      }
      if (duplicateProductIds.isNotEmpty) {
        await isar.writeTxn(() async {
          for (final id in duplicateProductIds) {
            await isar.products.delete(id);
          }
        });
      }
    } catch (e) {
      debugPrint('Isar cleanups notice: $e');
    }

    runApp(
      ProviderScope(
        overrides: [
          isarProvider.overrideWithValue(isar),
          if (localSqlService != null)
            localSqlServiceProvider.overrideWithValue(localSqlService),
        ],
        child: const BelekaApp(),
      ),
    );
  } catch (e, stack) {
    debugPrint('Fatal initialization error: $e\n$stack');
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: Scaffold(
          backgroundColor: const Color(0xFF141418),
          body: Center(
            child: Container(
              width: 520,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'SYSTEM INITIALIZATION ERROR',
                    style: GoogleFonts.manrope(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    e.toString(),
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => main(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFC1F11D),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('RETRY STARTUP', style: GoogleFonts.manrope(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final hasUsersProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseServiceProvider);
  return await db.hasUsers();
});

final appStartupProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final db = ref.watch(databaseServiceProvider);
  final licenseService = ref.watch(licenseServiceProvider);

  // 1. Verify Cryptographic Hardware-Locked License for this Machine
  final licenseResult = await licenseService.verifyCurrentMachineLicense();

  final hasUsers = await db.hasUsers();
  
  // Auto-initialize Hardware Drivers (Barcode Scanner + Auto-detect Printer)
  ref.read(barcodeServiceProvider).init();
  final config = await db.getStoreConfig();
  ref.read(printerServiceProvider).autoConnect(
    config: config,
    stateNotifier: ref.read(selectedPrinterProvider.notifier),
  );

  return {
    'hasUsers': hasUsers,
    'isActivated': licenseResult.isValid,
    'licenseResult': licenseResult,
  };
});

class BelekaApp extends ConsumerWidget {
  const BelekaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Initialize the network manager once the app starts
    ref.read(networkManagerProvider).initialize();
    ref.read(barcodeServiceProvider).init();

    final authState = ref.watch(authProvider);
    final startupAsync = ref.watch(appStartupProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Beleka POS',
      theme: AppTheme.darkTheme,
      home: startupAsync.when(
        data: (startup) {
          final isActivated = startup['isActivated'] as bool;
          
          // If machine is not activated or HWID mismatch, lock to Activation Screen
          if (!isActivated) {
            return ActivationScreen(
              onActivated: () {
                ref.invalidate(appStartupProvider);
              },
            );
          }

          final hasUsers = startup['hasUsers'] as bool;

          if (!hasUsers) return const SetupScreen();
          return authState == null ? const LoginScreen() : const ShellScreen();
        },
        loading: () => Scaffold(
          backgroundColor: const Color(0xFF141418),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSplashLogo(),
                const SizedBox(height: 40),
                const SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(color: Color(0xFFC1F11D), strokeWidth: 3),
                ),
                const SizedBox(height: 24),
                Text(
                  'INITIALIZING SYSTEM...',
                  style: GoogleFonts.ibmPlexMono(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        error: (e, s) => Scaffold(
          body: Center(child: Text('Error: $e')),
        ),
      ),
      routes: {
        '/activation': (context) => const ActivationScreen(),
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const ShellScreen(),
        '/setup': (context) => const SetupScreen(),
      },
    );
  }

  Widget _buildSplashLogo() {
    final searchPaths = [
      'assets/images/logo.png',
      'beleka logo icon.png',
      '${Directory.current.path}/assets/images/logo.png',
      '${Directory.current.path}/beleka logo icon.png',
      '/home/mrm/Documents/programs/beleka-pos-main/beleka logo icon.png',
      '/home/mrm/Documents/programs/beleka-pos-main/assets/images/logo.png',
    ];

    for (final path in searchPaths) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          return Image.file(
            f,
            height: 140,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Icon(
              Icons.bolt_rounded, 
              color: Color(0xFFC1F11D), 
              size: 64,
            ),
          );
        }
      } catch (_) {}
    }

    return Image.asset(
      'assets/images/logo.png',
      height: 140,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => const Icon(
        Icons.bolt_rounded, 
        color: Color(0xFFC1F11D), 
        size: 64,
      ),
    );
  }
}
