import 'package:beleka_pos/models/models.dart';

class ProductSalesReportFilters {
  final String? cashierId;
  final String? shiftNumber;
  final String? terminalName;
  final int? productId;
  final String? paymentMethod;

  const ProductSalesReportFilters({
    this.cashierId,
    this.shiftNumber,
    this.terminalName,
    this.productId,
    this.paymentMethod,
  });

  bool get isEmpty =>
      cashierId == null &&
      shiftNumber == null &&
      terminalName == null &&
      productId == null &&
      paymentMethod == null;
}

class ProductSalesReportRow {
  final int productId;
  final String productName;
  final String? sku;
  final double unitPrice;
  final double taxRate;
  final double quantitySold;
  final double quantityReturned;
  final double grossSales;
  final double discountAmount;
  final double taxAmount;
  final double refundAmount;
  final double refundTaxAmount;

  const ProductSalesReportRow({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.unitPrice,
    required this.taxRate,
    required this.quantitySold,
    required this.quantityReturned,
    required this.grossSales,
    required this.discountAmount,
    required this.taxAmount,
    required this.refundAmount,
    required this.refundTaxAmount,
  });

  double get netQuantity => quantitySold - quantityReturned;
  double get netSales => double.parse(
    (grossSales - discountAmount - refundAmount).toStringAsFixed(2),
  );
  double get netTax =>
      double.parse((taxAmount - refundTaxAmount).toStringAsFixed(2));
}

class _ProductSalesAccumulator {
  final int productId;
  final String productName;
  final String? sku;
  final double unitPrice;
  final double taxRate;
  double quantitySold = 0;
  double quantityReturned = 0;
  double grossSales = 0;
  double discountAmount = 0;
  double taxAmount = 0;
  double refundAmount = 0;
  double refundTaxAmount = 0;

  _ProductSalesAccumulator(SaleItem item)
    : productId = item.productId,
      productName = item.productName,
      sku = item.productSkuAtSale,
      unitPrice = item.priceAtSale,
      taxRate = item.taxRateAtSale;

  ProductSalesReportRow toRow() {
    double money(double value) => double.parse(value.toStringAsFixed(2));

    return ProductSalesReportRow(
      productId: productId,
      productName: productName,
      sku: sku,
      unitPrice: unitPrice,
      taxRate: taxRate,
      quantitySold: quantitySold,
      quantityReturned: quantityReturned,
      grossSales: money(grossSales),
      discountAmount: money(discountAmount),
      taxAmount: money(taxAmount),
      refundAmount: money(refundAmount),
      refundTaxAmount: money(refundTaxAmount),
    );
  }
}

List<ProductSalesReportRow> buildProductSalesReport(
  List<SaleTransaction> transactions, {
  ProductSalesReportFilters filters = const ProductSalesReportFilters(),
}) {
  final rows = <String, _ProductSalesAccumulator>{};

  List<SaleItem> itemsFor(SaleTransaction transaction) =>
      transaction.reportItems.isNotEmpty
      ? List<SaleItem>.of(transaction.reportItems)
      : transaction.items.toList();

  bool matchesTransaction(SaleTransaction transaction) =>
      (filters.cashierId == null ||
          (transaction.cashierId ?? transaction.cashierName) ==
              filters.cashierId) &&
      (filters.shiftNumber == null ||
          transaction.cashShiftNumber == filters.shiftNumber) &&
      (filters.terminalName == null ||
          transaction.terminalName == filters.terminalName) &&
      (filters.paymentMethod == null ||
          transaction.paymentMethod == filters.paymentMethod);

  double quantityOf(SaleItem item) => item.isWeighted && item.weight > 0
      ? item.weight
      : item.quantity.toDouble();

  double lineValue(SaleItem item) =>
      double.parse((item.priceAtSale * quantityOf(item)).toStringAsFixed(2));

  double taxFor(SaleItem item, double amount) {
    if (item.taxRateAtSale <= 0) return 0;
    if (item.isTaxInclusiveAtSale) {
      final net = double.parse(
        (amount / (1 + item.taxRateAtSale / 100)).toStringAsFixed(2),
      );
      return double.parse((amount - net).toStringAsFixed(2));
    }
    return double.parse((amount * item.taxRateAtSale / 100).toStringAsFixed(2));
  }

  String keyFor(SaleItem item) =>
      '${item.productId}|${item.productSkuAtSale ?? ''}|'
      '${item.priceAtSale.toStringAsFixed(4)}|'
      '${item.taxRateAtSale.toStringAsFixed(4)}|${item.productName}';

  _ProductSalesAccumulator accumulatorFor(SaleItem item) =>
      rows.putIfAbsent(keyFor(item), () => _ProductSalesAccumulator(item));

  for (final transaction in transactions) {
    if (!matchesTransaction(transaction)) continue;

    final items = itemsFor(transaction);
    if (items.isEmpty) continue;

    final values = items.map(lineValue).toList();
    final totalLineValue = values.fold<double>(0, (sum, value) => sum + value);
    if (totalLineValue <= 0) continue;

    if (transaction.isCreditNote) {
      var remainingRefund = transaction.totalAmount;
      var remainingTax = transaction.taxAmount;
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        final value = values[index];
        final isLast = index == items.length - 1;
        final refund = isLast
            ? remainingRefund
            : double.parse(
                (transaction.totalAmount * value / totalLineValue)
                    .toStringAsFixed(2),
              );
        final refundedTax = isLast
            ? remainingTax
            : double.parse(
                (transaction.taxAmount * value / totalLineValue)
                    .toStringAsFixed(2),
              );
        remainingRefund -= refund;
        remainingTax -= refundedTax;

        if (filters.productId != null && item.productId != filters.productId) {
          continue;
        }
        final row = accumulatorFor(item);
        row.quantityReturned += quantityOf(item);
        row.refundAmount += refund;
        row.refundTaxAmount += refundedTax;
      }
      continue;
    }

    final cartDiscountTotal = transaction.discountAmount
        .clamp(0.0, totalLineValue)
        .toDouble();
    var remainingCartDiscount = cartDiscountTotal;
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final value = values[index];
      final isLast = index == items.length - 1;
      final cartDiscount = isLast
          ? remainingCartDiscount
          : double.parse(
              (cartDiscountTotal * value / totalLineValue).toStringAsFixed(2),
            ).clamp(0.0, remainingCartDiscount).toDouble();
      remainingCartDiscount -= cartDiscount;

      if (filters.productId != null && item.productId != filters.productId) {
        continue;
      }
      final row = accumulatorFor(item);
      final itemDiscount = item.discountAmountAtSale
          .clamp(0.0, double.infinity)
          .toDouble();
      row.quantitySold += quantityOf(item);
      row.grossSales += value + itemDiscount;
      row.discountAmount += itemDiscount + cartDiscount;
      row.taxAmount += taxFor(item, value);
    }
  }

  final reportRows = rows.values.map((row) => row.toRow()).toList()
    ..sort((a, b) {
      final nameOrder = a.productName.toLowerCase().compareTo(
        b.productName.toLowerCase(),
      );
      return nameOrder != 0 ? nameOrder : a.unitPrice.compareTo(b.unitPrice);
    });
  return reportRows;
}
