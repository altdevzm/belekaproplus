import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';

void main() {
  test('new products default to DigiTax-enabled status', () {
    final product = Product(
      name: 'Local product',
      sku: 'LOCAL-1',
      price: 10,
      stockLevel: 5,
      categoryId: 0,
    );

    // v3.0.13: isDigitaxSyncEnabled now defaults to true so ALL retail
    // products are fiscalized with ZRA DigiTax unless explicitly opted out.
    expect(product.isDigitaxSyncEnabled, isTrue);
    expect(product.isDigitaxSyncEligible, isTrue);
  });

  test('local-only products skip DigiTax product and stock uploads', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final digitax = container.read(digitaxInventoryServiceProvider);
    final product = Product(
      name: 'Local product',
      sku: 'LOCAL-1',
      price: 10,
      stockLevel: 5,
      categoryId: 0,
      isDigitaxSyncEnabled: false,
    );

    expect(
      await digitax.syncSingleProductToDigitax(product, throwOnError: true),
      isTrue,
    );
    expect(
      await digitax.pushStockMovementAdjustment(
        product: product,
        action: 'ADD',
        movementType: '06',
        quantity: 5,
      ),
      isTrue,
    );
  });
}
