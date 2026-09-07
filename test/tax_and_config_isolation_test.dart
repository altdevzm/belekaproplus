import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/cart_provider.dart';
import 'package:beleka_pos/utils/formatters.dart';

void main() {
  group('Tax Calculation and Digitax/ZRA Precision Tests', () {
    test('K22 tax-inclusive item correctly produces K18.97 subtotal and K3.03 tax matching Digitax', () {
      final product = Product(
        name: 'Test Product',
        sku: 'TEST-22',
        price: 22.0,
        stockLevel: 100,
        categoryId: 1,
        taxRate: 16.0,
        isTaxInclusive: true,
      );

      final cartItem = CartItem(product: product, quantity: 1);

      expect(cartItem.unitPrice, 22.0);
      expect(cartItem.baseUnitPrice, 18.97);
      expect(cartItem.taxAmountPerUnit, 3.03);
      expect(cartItem.subtotal, 18.97);
      expect(cartItem.totalTax, 3.03);
      expect(cartItem.total, 22.0);

      // Verify formatting matches DigiTax/ZRA format (3.0300)
      final formattedTax = CurrencyFormatter.formatTaxPrecision(cartItem.totalTax, 'ZK');
      expect(formattedTax, 'ZK 3.0300');
    });

    test('StoreConfig default configuration is offline-isolated and does not prefill test cloud server', () {
      final config = StoreConfig();
      expect(config.isCloudSyncEnabled, isFalse);
      expect(config.cloudApiUrl, isNull);
      expect(config.cloudStoreId, isNull);
      expect(config.cloudStoreCode, isNull);
      expect(config.digitaxApiKey, isNull);
    });
  });
}
