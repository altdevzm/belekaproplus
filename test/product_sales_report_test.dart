import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/utils/product_sales_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('product sales report', () {
    test('reports item prices, discounts, tax and returned quantities', () {
      final sale =
          SaleTransaction(
              totalAmount: 59,
              paymentMethod: 'CASH',
              cashierName: 'Cashier A',
              cashierId: 'cashier-a',
              cashShiftNumber: 'SHIFT-1',
              terminalName: 'TILL-1',
              subtotal: 50.86,
              taxAmount: 8.14,
              discountAmount: 6,
            )
            ..reportItems.addAll([
              SaleItem(
                productId: 1,
                productName: 'Coca-Cola 500ml',
                productSkuAtSale: 'COKE-500',
                priceAtSale: 15,
                quantity: 3,
                discountAmountAtSale: 3,
                taxRateAtSale: 16,
                isTaxInclusiveAtSale: true,
              ),
              SaleItem(
                productId: 2,
                productName: 'Fanta 500ml',
                productSkuAtSale: 'FANTA-500',
                priceAtSale: 10,
                quantity: 2,
                taxRateAtSale: 16,
                isTaxInclusiveAtSale: true,
              ),
            ]);
      final refund =
          SaleTransaction(
              totalAmount: 15,
              paymentMethod: 'CASH',
              cashierName: 'Cashier A',
              cashierId: 'cashier-a',
              cashShiftNumber: 'SHIFT-1',
              terminalName: 'TILL-1',
              subtotal: 12.93,
              taxAmount: 2.07,
              isCreditNote: true,
              status: 'refunded',
            )
            ..reportItems.add(
              SaleItem(
                productId: 1,
                productName: 'Coca-Cola 500ml',
                productSkuAtSale: 'COKE-500',
                priceAtSale: 15,
                quantity: 1,
                taxRateAtSale: 16,
                isTaxInclusiveAtSale: true,
              ),
            );

      final rows = buildProductSalesReport([sale, refund]);
      final coke = rows.singleWhere((row) => row.productId == 1);
      final fanta = rows.singleWhere((row) => row.productId == 2);

      expect(coke.sku, 'COKE-500');
      expect(coke.quantitySold, 3);
      expect(coke.quantityReturned, 1);
      expect(coke.unitPrice, 15);
      expect(coke.discountAmount, 7.15);
      expect(coke.refundAmount, 15);
      expect(coke.netSales, 25.85);
      expect(coke.netTax, 4.14);
      expect(fanta.quantitySold, 2);
      expect(fanta.discountAmount, 1.85);
      expect(fanta.netSales, 18.15);
      expect(rows.fold<double>(0, (sum, row) => sum + row.netSales), 44);
    });

    test('filters product lines by cashier, shift, till and payment', () {
      final cashSale =
          SaleTransaction(
              totalAmount: 20,
              paymentMethod: 'CASH',
              cashierName: 'Cashier A',
              cashierId: 'cashier-a',
              cashShiftNumber: 'SHIFT-1',
              terminalName: 'TILL-1',
            )
            ..reportItems.add(
              SaleItem(
                productId: 7,
                productName: 'Water',
                productSkuAtSale: 'WATER',
                priceAtSale: 10,
                quantity: 2,
              ),
            );
      final cardSale =
          SaleTransaction(
              totalAmount: 10,
              paymentMethod: 'CARD',
              cashierName: 'Cashier B',
              cashierId: 'cashier-b',
              cashShiftNumber: 'SHIFT-2',
              terminalName: 'TILL-2',
            )
            ..reportItems.add(
              SaleItem(
                productId: 7,
                productName: 'Water',
                productSkuAtSale: 'WATER',
                priceAtSale: 10,
                quantity: 1,
              ),
            );

      final rows = buildProductSalesReport(
        [cashSale, cardSale],
        filters: const ProductSalesReportFilters(
          cashierId: 'cashier-a',
          shiftNumber: 'SHIFT-1',
          terminalName: 'TILL-1',
          productId: 7,
          paymentMethod: 'CASH',
        ),
      );

      expect(rows, hasLength(1));
      expect(rows.single.quantitySold, 2);
      expect(rows.single.netSales, 20);
    });

    test('keeps different unit prices as separate report rows', () {
      final first = SaleTransaction(totalAmount: 15, paymentMethod: 'CASH')
        ..reportItems.add(
          SaleItem(productId: 1, productName: 'Soda', priceAtSale: 15),
        );
      final second = SaleTransaction(totalAmount: 18, paymentMethod: 'CASH')
        ..reportItems.add(
          SaleItem(productId: 1, productName: 'Soda', priceAtSale: 18),
        );

      final rows = buildProductSalesReport([first, second]);

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.unitPrice), containsAll([15, 18]));
    });
  });
}
