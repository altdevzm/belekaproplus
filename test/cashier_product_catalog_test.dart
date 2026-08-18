import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/screens/sales_screen.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/barcode_service.dart';

class MockCashierAuthNotifier extends AuthNotifier {
  @override
  User? build() => User()
    ..name = 'Jane Cashier'
    ..numericId = '1002'
    ..passwordHash = 'dummy'
    ..role = 'cashier'
    ..isActive = true;
}

void main() {
  testWidgets('Cashier SalesScreen renders Product Catalog and Category Ribbon', (WidgetTester tester) async {
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
          categoriesProvider.overrideWith((ref) => Stream.value(mockCategories)),
          storeConfigProvider.overrideWith((ref) => Stream.value(StoreConfig()..currencySymbol = 'ZK')),
          barcodeStreamProvider.overrideWith((ref) => const Stream.empty()),
        ],
        child: const MaterialApp(
          home: SalesScreen(),
        ),
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
  });
}
