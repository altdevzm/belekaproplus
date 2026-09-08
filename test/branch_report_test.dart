import 'package:flutter_test/flutter_test.dart';
import 'package:beleka_pos/models/models.dart';

void main() {
  group('Branch Report Metric Calculations', () {
    test('Calculates Sales Performance metrics correctly', () {
      final tx1 = SaleTransaction(
        totalAmount: 500.0,
        paymentMethod: 'Cash',
        discountAmount: 20.0,
        totalCost: 300.0,
        grossProfit: 200.0,
      );
      final tx2 = SaleTransaction(
        totalAmount: 300.0,
        paymentMethod: 'Airtel Money',
        discountAmount: 0.0,
        totalCost: 180.0,
        grossProfit: 120.0,
      );
      final refundTx = SaleTransaction(
        totalAmount: 100.0,
        paymentMethod: 'Cash',
        status: 'refunded',
      );

      final transactions = [tx1, tx2, refundTx];

      double grossSales = 0.0;
      double refunds = 0.0;
      double discounts = 0.0;
      double cogs = 0.0;
      double cashSales = 0.0;
      double momoSales = 0.0;
      int completed = 0;

      for (final tx in transactions) {
        if (tx.status == 'refunded' || tx.isCreditNote) {
          refunds += tx.totalAmount.abs();
        } else {
          completed++;
          grossSales += tx.totalAmount;
          discounts += tx.discountAmount;
          cogs += tx.totalCost;

          if (tx.paymentMethod.toLowerCase().contains('cash')) {
            cashSales += tx.totalAmount;
          } else if (tx.paymentMethod.toLowerCase().contains('airtel')) {
            momoSales += tx.totalAmount;
          }
        }
      }

      final netSales = grossSales - refunds;
      final grossProfit = netSales - cogs;
      final grossMargin = netSales > 0 ? (grossProfit / netSales * 100) : 0.0;
      final avgTicket = completed > 0 ? (netSales / completed) : 0.0;

      expect(grossSales, equals(800.0));
      expect(refunds, equals(100.0));
      expect(netSales, equals(700.0));
      expect(discounts, equals(20.0));
      expect(cogs, equals(480.0));
      expect(grossProfit, equals(220.0));
      expect(grossMargin, closeTo(31.42, 0.01));
      expect(completed, equals(2));
      expect(avgTicket, equals(350.0));
      expect(cashSales, equals(500.0));
      expect(momoSales, equals(300.0));
    });

    test('Calculates Profitability and Net Profit Estimate correctly', () {
      const netSales = 1000.0;
      const cogs = 600.0;
      const grossProfit = netSales - cogs; // 400.0

      final expenses = [
        Expense()..amount = 150.0..category = 'Rent',
        Expense()..amount = 50.0..category = 'Utilities',
      ];

      final totalExpenses = expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
      final netProfit = grossProfit - totalExpenses;
      final netMargin = (netProfit / netSales) * 100;

      expect(grossProfit, equals(400.0));
      expect(totalExpenses, equals(200.0));
      expect(netProfit, equals(200.0));
      expect(netMargin, equals(20.0));
    });

    test('Calculates Inventory Stock Flow correctly', () {
      final prod1 = Product(name: 'Item A', sku: 'SKU1', price: 100.0, stockLevel: 25, categoryId: 1, unitCost: 60.0);
      final prod2 = Product(name: 'Item B', sku: 'SKU2', price: 50.0, stockLevel: 0, categoryId: 1, unitCost: 30.0);
      final prod3 = Product(name: 'Item C', sku: 'SKU3', price: 80.0, stockLevel: 5, categoryId: 1, unitCost: 40.0);

      final products = [prod1, prod2, prod3];

      double stockCostVal = 0.0;
      double stockRetailVal = 0.0;
      int lowStockCount = 0;
      int outOfStockCount = 0;

      for (final p in products) {
        stockCostVal += p.stockLevel * p.unitCost;
        stockRetailVal += p.stockLevel * p.price;
        if (p.stockLevel <= 0) {
          outOfStockCount++;
        } else if (p.stockLevel < 10) {
          lowStockCount++;
        }
      }

      expect(stockCostVal, equals((25 * 60.0) + (5 * 40.0))); // 1500 + 200 = 1700
      expect(stockRetailVal, equals((25 * 100.0) + (5 * 80.0))); // 2500 + 400 = 2900
      expect(outOfStockCount, equals(1));
      expect(lowStockCount, equals(1));
    });
  });
}
