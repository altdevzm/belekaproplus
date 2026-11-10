import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/screens/sales_screen.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/barcode_service.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/services/lenco_payment_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';
import 'package:beleka_pos/services/sync_service.dart';

class MockCashierAuthNotifier extends AuthNotifier {
  @override
  User? build() => User()
    ..name = 'Jane Cashier'
    ..numericId = '1002'
    ..passwordHash = 'dummy'
    ..role = 'cashier'
    ..isActive = true;
}

class _NoNetworkLencoService extends Fake implements LencoPaymentService {
  @override
  Future<List<Map<String, dynamic>>> getBanks({String country = 'zm'}) async =>
      [];
}

class _RecordingDatabaseService extends Fake implements DatabaseService {
  SaleTransaction? savedSale;
  List<SaleItem> savedItems = [];

  @override
  Future<void> saveTransaction(
    SaleTransaction transaction,
    List<SaleItem> items,
  ) async {
    savedSale = transaction;
    savedItems = List.of(items);
  }
}

class _NoFiscalDigiTaxService extends Fake implements DigiTaxInventoryService {
  int resolveCalls = 0;
  int fiscalizeCalls = 0;

  @override
  Future<String?> resolveBranchApiKey(String? branchCode) async {
    resolveCalls++;
    return null;
  }

  @override
  Future<bool> fiscalizeSaleTransaction(
    SaleTransaction transaction,
    List<SaleItem> items, {
    bool forcePush = false,
  }) async {
    fiscalizeCalls++;
    return false;
  }

  @override
  void dispose() {}
}

class _NoNetworkPostgresSyncService extends Fake
    implements PostgresSyncService {
  @override
  Future<int> syncPendingTransactions() async => 0;
}

class _OfflineSyncService extends Fake implements SyncService {
  @override
  Future<bool> trySyncTransaction(
    SaleTransaction transaction,
    List<SaleItem> items,
  ) async => false;
}

void main() {
  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  test(
    'local database persists a cash sale and deducts the seeded stock',
    () async {
      final testDirectory = await Directory.systemTemp.createTemp(
        'beleka-sale-database-test-',
      );
      final isar = await Isar.open(
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
          StockMovementSchema,
        ],
        directory: testDirectory.path,
        name: 'local_sale_database_test',
      );

      try {
        final product = Product(
          name: 'Database Test Product',
          sku: 'TEST-SALE-DB-001',
          price: 37,
          unitCost: 20,
          stockLevel: 5,
          categoryId: 1,
        );
        await isar.writeTxn(() async => isar.products.put(product));

        final transaction = SaleTransaction(
          totalAmount: 37,
          paymentMethod: 'CASH',
          cashierName: 'Test Cashier',
          cashierId: '1002',
          terminalName: 'TEST-TILL',
          subtotal: 31.9,
          taxAmount: 5.1,
          tenderedAmount: 40,
          changeAmount: 3,
        );
        final item = SaleItem(
          productId: product.id,
          productName: product.name,
          productSkuAtSale: product.sku,
          priceAtSale: 37,
          unitCostAtSale: 20,
          taxRateAtSale: 16,
        );

        await DatabaseService(isar).saveTransaction(transaction, [item]);

        final savedTransaction = await isar.saleTransactions
            .where()
            .findFirst();
        final savedItem = await isar.saleItems.where().findFirst();
        final savedProduct = await isar.products.get(product.id);
        expect(savedTransaction?.totalAmount, 37);
        expect(savedTransaction?.paymentMethod, 'CASH');
        expect(savedTransaction?.tenderedAmount, 40);
        expect(savedTransaction?.changeAmount, 3);
        expect(savedItem?.productSkuAtSale, 'TEST-SALE-DB-001');
        expect(savedProduct?.stockLevel, 4);
      } finally {
        await isar.close(deleteFromDisk: true);
        await testDirectory.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'Cashier SalesScreen renders Product Catalog and Category Ribbon',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockProducts = [
        Product(
          name: 'Coca Cola 500ml',
          sku: '5449000000996',
          price: 15.0,
          stockLevel: 45,
          categoryId: 1,
        ),
        Product(
          name: 'Lays Salted Chips 125g',
          sku: '6001087361234',
          price: 25.0,
          stockLevel: 20,
          categoryId: 2,
        ),
        Product(
          name: 'White Sliced Bread',
          sku: '6009876543210',
          price: 18.0,
          stockLevel: 3,
          categoryId: 3,
        ),
      ];

      final mockCategories = [
        Category(name: 'Beverages')..id = 1,
        Category(name: 'Snacks')..id = 2,
        Category(name: 'Bakery')..id = 3,
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(MockCashierAuthNotifier.new),
            isManagerProvider.overrideWith((ref) => false),
            productsProvider.overrideWith((ref) => Stream.value(mockProducts)),
            categoriesProvider.overrideWith(
              (ref) => Stream.value(mockCategories),
            ),
            storeConfigProvider.overrideWith(
              (ref) => Stream.value(StoreConfig()..currencySymbol = 'ZK'),
            ),
            barcodeStreamProvider.overrideWith((ref) => const Stream.empty()),
            lencoPaymentServiceProvider.overrideWithValue(
              _NoNetworkLencoService(),
            ),
          ],
          child: const MaterialApp(home: SalesScreen()),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Product Catalog Header and Categories
      expect(find.text('PRODUCT CATALOG'), findsOneWidget);
      expect(find.text('ALL ITEMS'), findsOneWidget);
      expect(find.text('BEVERAGES'), findsOneWidget);
      expect(find.text('SNACKS'), findsOneWidget);
      expect(find.text('BAKERY'), findsOneWidget);

      // Verify Product Cards in Catalog
      expect(find.text('Coca Cola 500ml'), findsOneWidget);
      expect(find.text('Lays Salted Chips 125g'), findsOneWidget);
      expect(find.text('White Sliced Bread'), findsOneWidget);

      // Tap a product card to add to cart
      await tester.tap(find.text('Coca Cola 500ml'));
      await tester.pump();

      // Verify it appeared in Order Review panel on the right
      expect(find.text('ORDER REVIEW'), findsOneWidget);
      expect(find.text('1 items'), findsOneWidget);
    },
  );

  testWidgets('cash checkout creates a sale with external systems disabled', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final product = Product(
      name: 'Isolated Test Product',
      sku: 'TEST-SALE-001',
      price: 37,
      unitCost: 20,
      stockLevel: 5,
      categoryId: 1,
    );
    final databaseService = _RecordingDatabaseService();
    final digitaxService = _NoFiscalDigiTaxService();
    final container = ProviderContainer(
      overrides: [
        databaseServiceProvider.overrideWithValue(databaseService),
        authProvider.overrideWith(MockCashierAuthNotifier.new),
        isManagerProvider.overrideWith((ref) => false),
        productsProvider.overrideWith((ref) => Stream.value([product])),
        categoriesProvider.overrideWith(
          (ref) => Stream.value([Category(name: 'Test')..id = 1]),
        ),
        storeConfigProvider.overrideWith(
          (ref) => Stream.value(
            StoreConfig()
              ..currencySymbol = 'ZK'
              ..terminalName = 'TEST-TILL'
              ..autoPrintReceipt = false
              ..autoOpenCashDrawer = false,
          ),
        ),
        barcodeStreamProvider.overrideWith((ref) => const Stream.empty()),
        lencoPaymentServiceProvider.overrideWithValue(_NoNetworkLencoService()),
        syncServiceProvider.overrideWithValue(_OfflineSyncService()),
        postgresSyncServiceProvider.overrideWithValue(
          _NoNetworkPostgresSyncService(),
        ),
        digitaxInventoryServiceProvider.overrideWith((ref) => digitaxService),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SalesScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 150));

    await tester.tap(find.text('Isolated Test Product'));
    await tester.pump();
    await tester.tap(find.text('CASH').first);
    await tester.pump();
    await tester.tap(find.text('EXACT'));
    await tester.pump();
    await tester.tap(find.text('COMPLETE SALE'));
    await tester.pumpAndSettle();

    expect(find.text('Sale Complete'), findsOneWidget);
    expect(digitaxService.resolveCalls, 1);
    expect(digitaxService.fiscalizeCalls, 0);
    expect(databaseService.savedSale?.totalAmount, 37);
    expect(databaseService.savedSale?.paymentMethod, 'CASH');
    expect(databaseService.savedSale?.tenderedAmount, 37);
    expect(databaseService.savedSale?.changeAmount, 0);
    expect(databaseService.savedSale?.zraReceiptNumber, isNull);
    expect(databaseService.savedSale?.zraStatus, 'pending');
    expect(databaseService.savedItems, hasLength(1));
    expect(databaseService.savedItems.single.productName, product.name);
    expect(databaseService.savedItems.single.productSkuAtSale, product.sku);
  });
}
