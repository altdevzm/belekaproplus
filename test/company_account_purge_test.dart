import 'package:flutter_test/flutter_test.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';

void main() {
  late Isar isar;
  late DatabaseService dbService;

  setUpAll(() async {
    await Isar.initializeIsarCore(download: true);
  });

  setUp(() async {
    isar = await Isar.open(
      [
        UserSchema,
        ProductSchema,
        CategorySchema,
        SaleTransactionSchema,
        SaleItemSchema,
        CustomerSchema,
        SupplierSchema,
        StoreConfigSchema,
        AttendanceLogSchema,
        StockMovementSchema,
      ],
      directory: '.',
      name: 'test_company_purge_db_${DateTime.now().millisecondsSinceEpoch}',
    );
    dbService = DatabaseService(isar);
  });

  tearDown(() async {
    await isar.close(deleteFromDisk: true);
  });

  test('purgeEntireCompanyAccount wipes all collections from the local database', () async {
    // 1. Seed some mock company data
    final user = User()
      ..numericId = '1001'
      ..name = 'Store Owner'
      ..passwordHash = hashPin('1234')
      ..role = 'owner';

    final product = Product(
      name: 'Sample Item',
      price: 50.0,
      sku: 'SKU-001',
      unitCost: 30.0,
      stockLevel: 10,
      categoryId: 1,
    );

    final supplier = Supplier()
      ..name = 'Main Supplier Ltd'
      ..balance = 500.0;

    final storeConfig = StoreConfig()
      ..businessName = 'Test Supermarket'
      ..tpin = '1002345678'
      ..terminalName = 'POS-01';

    await isar.writeTxn(() async {
      await isar.users.put(user);
      await isar.products.put(product);
      await isar.suppliers.put(supplier);
      await isar.storeConfigs.put(storeConfig);
    });

    // Verify seeded counts
    expect(await isar.users.count(), equals(1));
    expect(await isar.products.count(), equals(1));
    expect(await isar.suppliers.count(), equals(1));
    expect(await isar.storeConfigs.count(), equals(1));
    expect(await dbService.hasUsers(), isTrue);

    // 2. Perform company account purge
    await dbService.purgeEntireCompanyAccount();

    // 3. Verify all collections are completely wiped
    expect(await isar.users.count(), equals(0));
    expect(await isar.products.count(), equals(0));
    expect(await isar.suppliers.count(), equals(0));
    expect(await isar.storeConfigs.count(), equals(0));
    expect(await dbService.hasUsers(), isFalse);
  });
}
