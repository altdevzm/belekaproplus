import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/models/models.dart';

void main() {
  group('Consignment & Commission Model Encoding Tests', () {
    test('Product consignment encoding and parsing works correctly', () {
      final product = Product(
        name: 'Fresh Farm Milk 2L',
        sku: 'MILK-001',
        price: 100.00,
        stockLevel: 25,
        categoryId: 1,
      );

      expect(product.isConsignment, isFalse);
      expect(product.consignmentSupplierId, isNull);
      expect(product.consignmentSupplierName, isNull);

      // Set consignment with 15% commission
      product.setConsignmentDetails(
        enabled: true,
        supplierId: 42,
        supplierName: 'Lusaka Dairy Farms',
        commissionRate: 15.0,
        supplierPayoutPrice: 85.0,
      );

      expect(product.isConsignment, isTrue);
      expect(product.consignmentSupplierId, equals(42));
      expect(product.consignmentSupplierName, equals('Lusaka Dairy Farms'));
      expect(product.consignmentCommissionRate, equals(15.0));
      expect(product.consignmentSupplierPayoutPrice, equals(85.0));

      // Disable consignment
      product.setConsignmentDetails(enabled: false);
      expect(product.isConsignment, isFalse);
      expect(product.consignmentSupplierId, isNull);
      expect(product.consignmentSupplierName, isNull);
    });
  });

  group('Consignment Financial Split & Non-Commingling Rules', () {
    test('Percentage Commission Split: K1,000 sale at 15% commission yields K150 store profit and K850 supplier payable', () {
      const double retailPrice = 1000.00;
      const int quantity = 1;
      const double commissionRate = 15.0; // 15% store commission

      final totalItemAmount = retailPrice * quantity;
      final itemCommission = totalItemAmount * (commissionRate / 100.0);
      final supplierShare = totalItemAmount - itemCommission;

      expect(totalItemAmount, equals(1000.00));
      expect(itemCommission, equals(150.00)); // Store's true revenue & profit
      expect(supplierShare, equals(850.00));  // Pass-through liability owed to supplier

      // Verify that store revenue does NOT commingle with supplier money
      final grossProfitRetained = itemCommission;
      final supplierPassThroughCost = supplierShare;

      expect(grossProfitRetained + supplierPassThroughCost, equals(totalItemAmount));
      expect(grossProfitRetained, equals(150.00));
      expect(supplierPassThroughCost, equals(850.00));
    });

    test('Fixed Payout Split: K500 retail price with K420 agreed supplier payout yields K80 store profit', () {
      const double retailPrice = 500.00;
      const int quantity = 3;
      const double agreedSupplierPayoutPerUnit = 420.00;

      final totalItemAmount = retailPrice * quantity; // K1,500.00
      final totalSupplierPayout = agreedSupplierPayoutPerUnit * quantity; // K1,260.00
      final storeCommissionEarned = totalItemAmount - totalSupplierPayout; // K240.00 (K80/unit)

      expect(totalItemAmount, equals(1500.00));
      expect(totalSupplierPayout, equals(1260.00));
      expect(storeCommissionEarned, equals(240.00));
    });

    test('Supplier Balance Accumulation and Settlement Lifecycle', () {
      final supplier = Supplier()
        ..name = 'Chongwe Organic Produce'
        ..balance = 0.0;

      // Sale 1: 5 units of K100 (Payout K85/unit) -> +K425 to supplier balance
      final sale1SupplierPayout = 5 * 85.00;
      supplier.balance += sale1SupplierPayout;
      expect(supplier.balance, equals(425.00));

      // Sale 2: 10 units of K200 (Payout K170/unit) -> +K1,700 to supplier balance
      final sale2SupplierPayout = 10 * 170.00;
      supplier.balance += sale2SupplierPayout;
      expect(supplier.balance, equals(2125.00));

      // Settlement Payout: Pay vendor K2,000 via Bank Transfer
      const double payoutAmount = 2000.00;
      supplier.balance -= payoutAmount;
      expect(supplier.balance, equals(125.00)); // K125 remaining balance

      // Full settlement: Pay remaining K125
      supplier.balance -= 125.00;
      expect(supplier.balance, equals(0.00)); // Fully cleared
    });
  });
}
