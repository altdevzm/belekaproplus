import 'dart:io';
import 'package:flutter/material.dart' show DateTimeRange, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/local_sql_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/utils/formatters.dart';

/// Returned item condition assessment per Section D (Inventory Handling)
enum ReturnedItemCondition {
  resalable('RESALABLE', 'Resalable (Return to Stock)'),
  damaged('DAMAGED', 'Damaged (Quarantine / Non-Sellable)'),
  defective('DEFECTIVE', 'Defective (Supplier Claim / Write-off)');

  final String code;
  final String label;
  const ReturnedItemCondition(this.code, this.label);

  static ReturnedItemCondition fromCode(String raw) {
    final upper = raw.trim().toUpperCase();
    for (final c in ReturnedItemCondition.values) {
      if (c.code == upper) {
        return c;
      }
    }
    return ReturnedItemCondition.resalable;
  }
}

/// Line item being returned from the original sales invoice
class ExchangeReturnLine {
  final int originalSaleItemId;
  final int productId;
  final String productName;
  final String sku;
  final int originalPurchasedQty;
  final int alreadyReturnedOrExchangedQty;
  final int returnQuantity;
  final double unitPriceAtSale;
  final double discountPerUnitAtSale;
  final double unitCostAtSale;
  final double taxRateAtSale;
  final bool isTaxInclusiveAtSale;
  final bool isDigitaxExempt;
  final ReturnedItemCondition condition;

  const ExchangeReturnLine({
    required this.originalSaleItemId,
    required this.productId,
    required this.productName,
    required this.sku,
    required this.originalPurchasedQty,
    required this.alreadyReturnedOrExchangedQty,
    required this.returnQuantity,
    required this.unitPriceAtSale,
    this.discountPerUnitAtSale = 0.0,
    this.unitCostAtSale = 0.0,
    this.taxRateAtSale = 16.0,
    this.isTaxInclusiveAtSale = true,
    this.isDigitaxExempt = false,
    this.condition = ReturnedItemCondition.resalable,
  });

  int get maxReturnableQty =>
      (originalPurchasedQty - alreadyReturnedOrExchangedQty).clamp(0, 999999);

  double get effectiveUnitPrice =>
      (unitPriceAtSale - discountPerUnitAtSale).clamp(0.0, double.infinity);

  double get lineTotal =>
      double.parse((effectiveUnitPrice * returnQuantity).toStringAsFixed(2));

  double get lineTaxAmount {
    if (taxRateAtSale <= 0) {
      return 0.0;
    }
    if (isTaxInclusiveAtSale) {
      final net = lineTotal / (1 + (taxRateAtSale / 100.0));
      return double.parse((lineTotal - net).toStringAsFixed(2));
    }
    return double.parse(
      (lineTotal * (taxRateAtSale / 100.0)).toStringAsFixed(2),
    );
  }

  ExchangeReturnLine copyWith({
    int? returnQuantity,
    ReturnedItemCondition? condition,
  }) {
    return ExchangeReturnLine(
      originalSaleItemId: originalSaleItemId,
      productId: productId,
      productName: productName,
      sku: sku,
      originalPurchasedQty: originalPurchasedQty,
      alreadyReturnedOrExchangedQty: alreadyReturnedOrExchangedQty,
      returnQuantity: returnQuantity ?? this.returnQuantity,
      unitPriceAtSale: unitPriceAtSale,
      discountPerUnitAtSale: discountPerUnitAtSale,
      unitCostAtSale: unitCostAtSale,
      taxRateAtSale: taxRateAtSale,
      isTaxInclusiveAtSale: isTaxInclusiveAtSale,
      isDigitaxExempt: isDigitaxExempt,
      condition: condition ?? this.condition,
    );
  }
}

/// Replacement product selected from the current catalogue
class ExchangeReplacementLine {
  final Product product;
  final int quantity;
  final double unitPrice;
  final double discountAmount; // Line discount (requires manager approval if > 0)

  const ExchangeReplacementLine({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.discountAmount = 0.0,
  });

  double get grossLineTotal => unitPrice * quantity;

  double get lineTotal =>
      double.parse((grossLineTotal - discountAmount).clamp(0.0, double.infinity).toStringAsFixed(2));

  double get lineTaxAmount {
    if (product.taxRate <= 0) {
      return 0.0;
    }
    if (product.isTaxInclusive) {
      final net = lineTotal / (1 + (product.taxRate / 100.0));
      return double.parse((lineTotal - net).toStringAsFixed(2));
    }
    return double.parse(
      (lineTotal * (product.taxRate / 100.0)).toStringAsFixed(2),
    );
  }

  ExchangeReplacementLine copyWith({
    int? quantity,
    double? unitPrice,
    double? discountAmount,
  }) {
    return ExchangeReplacementLine(
      product: product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discountAmount: discountAmount ?? this.discountAmount,
    );
  }
}

/// Completed Exchange Record with all linked items & references
class ProductExchangeRecord {
  final int id;
  final String exchangeNumber;
  final int originalSaleId;
  final String originalInvoiceNo;
  final int? creditNoteSaleId;
  final int? replacementSaleId;
  final int? customerId;
  final String customerName;
  final String customerPhone;
  final String? customerTpin;
  final String branchCode;
  final String branchName;
  final double returnedValue;
  final double returnedTax;
  final double replacementValue;
  final double replacementDiscount;
  final double replacementTax;
  final double differenceAmount;
  final String scenarioType; // 'TOP_UP', 'REFUND_OR_CREDIT', 'EQUAL_VALUE'
  final String settlementMode; // 'ADDITIONAL_PAYMENT', 'CASH_REFUND', 'CUSTOMER_CREDIT', 'EVEN_EXCHANGE'
  final String paymentMethod;
  final double additionalPaid;
  final double refundedAmount;
  final double creditRetained;
  final String reason;
  final String cashierName;
  final String approvingManagerName;
  final DateTime createdAt;
  final List<Map<String, dynamic>> returnedItems;
  final List<Map<String, dynamic>> replacementItems;

  const ProductExchangeRecord({
    required this.id,
    required this.exchangeNumber,
    required this.originalSaleId,
    required this.originalInvoiceNo,
    this.creditNoteSaleId,
    this.replacementSaleId,
    this.customerId,
    required this.customerName,
    required this.customerPhone,
    this.customerTpin,
    required this.branchCode,
    required this.branchName,
    required this.returnedValue,
    required this.returnedTax,
    required this.replacementValue,
    required this.replacementDiscount,
    required this.replacementTax,
    required this.differenceAmount,
    required this.scenarioType,
    required this.settlementMode,
    required this.paymentMethod,
    required this.additionalPaid,
    required this.refundedAmount,
    required this.creditRetained,
    required this.reason,
    required this.cashierName,
    required this.approvingManagerName,
    required this.createdAt,
    required this.returnedItems,
    required this.replacementItems,
  });
}

/// Analytics & Reporting model for Section F
class ProductExchangeReportSummary {
  final int totalExchanges;
  final double totalReturnedValue;
  final double totalReplacementValue;
  final double totalAdditionalPaymentsCollected;
  final double totalRefundsFromExchanges;
  final double totalOutstandingCustomerCredit;
  final List<Map<String, dynamic>> mostFrequentlyExchangedProducts;
  final List<Map<String, dynamic>> exchangeValueByBranch;
  final List<Map<String, dynamic>> customerCreditBalances;
  final List<ProductExchangeRecord> recentExchanges;

  const ProductExchangeReportSummary({
    required this.totalExchanges,
    required this.totalReturnedValue,
    required this.totalReplacementValue,
    required this.totalAdditionalPaymentsCollected,
    required this.totalRefundsFromExchanges,
    required this.totalOutstandingCustomerCredit,
    required this.mostFrequentlyExchangedProducts,
    required this.exchangeValueByBranch,
    required this.customerCreditBalances,
    required this.recentExchanges,
  });
}

final productExchangeServiceProvider = Provider<ProductExchangeService>((ref) {
  return ProductExchangeService(ref);
});

final exchangeReportProvider =
    FutureProvider.family<ProductExchangeReportSummary, DateTimeRange>((
      ref,
      range,
    ) async {
      final svc = ref.watch(productExchangeServiceProvider);
      return svc.getExchangeReportSummary(range.start, range.end);
    });

class ProductExchangeService {
  final Ref ref;

  ProductExchangeService(this.ref);

  /// Search eligible sales invoices by invoice ID, ZRA receipt no, customer name/TPIN, or cashier
  Future<List<SaleTransaction>> searchEligibleSalesInvoices(String query) async {
    final db = ref.read(databaseServiceProvider);
    final all = await db.isar.saleTransactions
        .where()
        .sortByTimestampDesc()
        .limit(200)
        .findAll();

    final cleanQuery = query
        .trim()
        .toLowerCase()
        .replaceAll('#', '')
        .replaceAll('inv-', '');

    final List<SaleTransaction> results = [];
    for (final tx in all) {
      if (tx.isCreditNote) {
        continue;
      }
      if (cleanQuery.isEmpty) {
        await tx.items.load();
        results.add(tx);
        if (results.length >= 40) {
          break;
        }
        continue;
      }

      final idStr = tx.id.toString();
      final paddedId = idStr.padLeft(6, '0');
      final zraRec = (tx.zraReceiptNumber ?? '').toLowerCase();
      final custName = (tx.customerBusinessName ?? '').toLowerCase();
      final custTpin = (tx.customerTpin ?? '').toLowerCase();
      final cashier = tx.cashierName.toLowerCase();
      final txUuid = (tx.transactionId ?? '').toLowerCase();

      if (idStr.contains(cleanQuery) ||
          paddedId.contains(cleanQuery) ||
          zraRec.contains(cleanQuery) ||
          custName.contains(cleanQuery) ||
          custTpin.contains(cleanQuery) ||
          cashier.contains(cleanQuery) ||
          txUuid.contains(cleanQuery)) {
        await tx.items.load();
        results.add(tx);
        if (results.length >= 40) {
          break;
        }
      }
    }
    return results;
  }

  /// Returns a map of `originalSaleItemId -> alreadyExchangedOrReturnedQuantity`
  /// so we prevent exchanging quantities greater than those originally purchased less already returned/exchanged.
  Future<Map<int, int>> getAlreadyReturnedQuantitiesForInvoice(
    int originalSaleId,
  ) async {
    final localSql = ref.read(localSqlServiceProvider);
    final db = ref.read(databaseServiceProvider);
    final Map<int, int> map = {};

    try {
      final rows = await localSql.query(
        'SELECT original_sale_item_id, SUM(quantity) as total_qty '
        'FROM product_exchange_items '
        'WHERE original_sale_id = ? AND direction = ? '
        'GROUP BY original_sale_item_id',
        [originalSaleId, 'RETURNED'],
      );
      for (final row in rows) {
        final itemId = row['original_sale_item_id'] as int?;
        final qty = (row['total_qty'] as num?)?.toInt() ?? 0;
        if (itemId != null) {
          map[itemId] = qty;
        }
      }
    } catch (e) {
      debugPrint('EXCHANGE_RETURNED_QTY_LOOKUP_NOTE: $e');
    }

    // Also check if any item on the original invoice was directly refunded via normal Refund
    final items = await db.getTransactionItems(originalSaleId);
    for (final item in items) {
      if (item.isRefunded) {
        final origQty = (item.isWeighted && item.weight > 0)
            ? item.weight.ceil()
            : item.quantity;
        final tracked = map[item.id] ?? 0;
        if (tracked < origQty) {
          map[item.id] = origQty;
        }
      }
    }

    return map;
  }

  /// Builds initial returnable lines for a selected invoice
  Future<List<ExchangeReturnLine>> buildReturnLinesForInvoice(
    SaleTransaction invoice,
  ) async {
    final db = ref.read(databaseServiceProvider);
    final items = await db.getTransactionItems(invoice.id);
    final alreadyReturnedMap = await getAlreadyReturnedQuantitiesForInvoice(
      invoice.id,
    );

    final List<ExchangeReturnLine> lines = [];
    for (final item in items) {
      final origQty = (item.isWeighted && item.weight > 0)
          ? item.weight.ceil()
          : item.quantity;
      final alreadyRet = (alreadyReturnedMap[item.id] ?? 0).clamp(0, origQty);
      final discountPerUnit = origQty > 0
          ? (item.discountAmountAtSale / origQty)
          : 0.0;

      lines.add(
        ExchangeReturnLine(
          originalSaleItemId: item.id,
          productId: item.productId,
          productName: item.productName,
          sku: item.productSkuAtSale ?? 'SKU-${item.productId}',
          originalPurchasedQty: origQty,
          alreadyReturnedOrExchangedQty: alreadyRet,
          returnQuantity: 0,
          unitPriceAtSale: item.priceAtSale,
          discountPerUnitAtSale: discountPerUnit,
          unitCostAtSale: item.unitCostAtSale,
          taxRateAtSale: item.taxRateAtSale > 0 ? item.taxRateAtSale : 16.0,
          isTaxInclusiveAtSale: item.isTaxInclusiveAtSale,
          isDigitaxExempt: item.isDigitaxExempt,
          condition: ReturnedItemCondition.resalable,
        ),
      );
    }
    return lines;
  }

  /// Process and execute a complete Product Exchange transaction as linked financial records:
  /// 1. Credit Note (`SaleTransaction` with `isCreditNote: true`) for returned products
  /// 2. Stock condition assessment & stock movements for returned products
  /// 3. New Sale (`SaleTransaction` with `isCreditNote: false`) for replacement products
  /// 4. Stock deduction & stock movements for replacement products
  /// 5. Net settlement (Top-up payment, Refund,Customer Credit, or Equal Value)
  Future<ProductExchangeRecord> processProductExchange({
    required SaleTransaction originalInvoice,
    required List<ExchangeReturnLine> returnedLines,
    required List<ExchangeReplacementLine> replacementLines,
    required String reason,
    required String settlementMode, // 'ADDITIONAL_PAYMENT', 'CASH_REFUND', 'CUSTOMER_CREDIT', 'EVEN_EXCHANGE'
    required String paymentMethod, // 'CASH', 'CARD / BANK', 'AIRTEL MONEY', 'MTN MONEY', 'CUSTOMER CREDIT', 'EVEN EXCHANGE'
    required String cashierName,
    String? cashierId,
    required String approvingManagerName,
    String? approvingManagerId,
    int? customerId,
    String? customerName,
    String? customerPhone,
    String? customerTpin,
  }) async {
    final activeReturns = returnedLines
        .where((l) => l.returnQuantity > 0)
        .toList();
    final activeReplacements = replacementLines
        .where((l) => l.quantity > 0)
        .toList();

    if (activeReturns.isEmpty) {
      throw ArgumentError(
        'Please select at least one product from the original invoice to return.',
      );
    }
    if (activeReplacements.isEmpty) {
      throw ArgumentError(
        'Please select at least one replacement product from the catalogue.',
      );
    }

    final db = ref.read(databaseServiceProvider);
    final localSql = ref.read(localSqlServiceProvider);
    final config = await db.isar.storeConfigs.where().findFirst();
    final branchCode = config?.bhfId.trim().isNotEmpty == true
        ? config!.bhfId.trim()
        : '00';
    final branchName = config?.branchName?.trim().isNotEmpty == true
        ? config!.branchName!.trim()
        : 'Main Branch (HQ)';

    // 1. Validate return quantities against original invoice less already returned
    final alreadyReturnedMap = await getAlreadyReturnedQuantitiesForInvoice(
      originalInvoice.id,
    );
    for (final ret in activeReturns) {
      final alreadyRet = alreadyReturnedMap[ret.originalSaleItemId] ?? 0;
      final remainingAllowed = ret.originalPurchasedQty - alreadyRet;
      if (ret.returnQuantity > remainingAllowed) {
        throw StateError(
          'Cannot return ${ret.returnQuantity} of "${ret.productName}". '
          'Only $remainingAllowed unit(s) remain eligible on Invoice #${originalInvoice.id.toString().padLeft(6, '0')}.',
        );
      }
    }

    // 2. Validate replacement product stock availability
    // Note: If the same product is returned as RESALABLE and also chosen as a replacement,
    // account for the resalable return quantity before checking stock.
    final Map<int, int> resalableReturnByProduct = {};
    for (final ret in activeReturns) {
      if (ret.condition == ReturnedItemCondition.resalable) {
        resalableReturnByProduct[ret.productId] =
            (resalableReturnByProduct[ret.productId] ?? 0) + ret.returnQuantity;
      }
    }
    for (final rep in activeReplacements) {
      final freshProd = await db.isar.products.get(rep.product.id);
      if (freshProd == null) {
        throw StateError('Replacement product "${rep.product.name}" not found.');
      }
      final availableWithResalable =
          freshProd.stockLevel + (resalableReturnByProduct[freshProd.id] ?? 0);
      if (availableWithResalable < rep.quantity) {
        throw StateError(
          'Insufficient stock for replacement "${freshProd.name}" '
          '(Available: $availableWithResalable, Required: ${rep.quantity}).',
        );
      }
    }

    // 3. Compute financial values
    final double returnedValue = double.parse(
      activeReturns.fold(0.0, (s, l) => s + l.lineTotal).toStringAsFixed(2),
    );
    final double returnedTax = double.parse(
      activeReturns.fold(0.0, (s, l) => s + l.lineTaxAmount).toStringAsFixed(2),
    );
    final double returnedCost = double.parse(
      activeReturns
          .fold(0.0, (s, l) => s + (l.unitCostAtSale * l.returnQuantity))
          .toStringAsFixed(2),
    );
    final double returnedSubtotal = double.parse(
      (returnedValue - returnedTax).toStringAsFixed(2),
    );

    final double replacementGross = double.parse(
      activeReplacements
          .fold(0.0, (s, l) => s + l.grossLineTotal)
          .toStringAsFixed(2),
    );
    final double replacementDiscount = double.parse(
      activeReplacements
          .fold(0.0, (s, l) => s + l.discountAmount)
          .toStringAsFixed(2),
    );
    final double replacementValue = double.parse(
      activeReplacements.fold(0.0, (s, l) => s + l.lineTotal).toStringAsFixed(2),
    );
    final double replacementTax = double.parse(
      activeReplacements
          .fold(0.0, (s, l) => s + l.lineTaxAmount)
          .toStringAsFixed(2),
    );
    final double replacementCost = double.parse(
      activeReplacements
          .fold(0.0, (s, l) => s + (l.product.unitCost * l.quantity))
          .toStringAsFixed(2),
    );
    final double replacementSubtotal = double.parse(
      (replacementGross - replacementTax).toStringAsFixed(2),
    );

    final double differenceAmount = double.parse(
      (replacementValue - returnedValue).toStringAsFixed(2),
    );

    final String scenarioType;
    if (differenceAmount > 0.009) {
      scenarioType = 'TOP_UP';
    } else if (differenceAmount < -0.009) {
      scenarioType = 'REFUND_OR_CREDIT';
    } else {
      scenarioType = 'EQUAL_VALUE';
    }

    final double additionalPaid = differenceAmount > 0.009
        ? differenceAmount
        : 0.0;
    final double excessReturnCredit = differenceAmount < -0.009
        ? differenceAmount.abs()
        : 0.0;
    final double refundedAmount =
        (scenarioType == 'REFUND_OR_CREDIT' && settlementMode == 'CASH_REFUND')
        ? excessReturnCredit
        : 0.0;
    final double creditRetained =
        (scenarioType == 'REFUND_OR_CREDIT' &&
            settlementMode == 'CUSTOMER_CREDIT')
        ? excessReturnCredit
        : 0.0;

    final now = DateTime.now();
    final exchangeNumber =
        'EXG-${DateFormat('yyyyMMdd').format(now)}-${now.millisecondsSinceEpoch.toString().substring(8)}';
    final origInvoiceNo = originalInvoice.zraReceiptNumber?.isNotEmpty == true
        ? originalInvoice.zraReceiptNumber!
        : 'INV-${originalInvoice.id.toString().padLeft(6, '0')}';

    final resolvedCustomerName = (customerName != null && customerName.trim().isNotEmpty)
        ? customerName.trim()
        : (originalInvoice.customerBusinessName?.trim().isNotEmpty == true
              ? originalInvoice.customerBusinessName!.trim()
              : 'Walk-in Customer');
    final resolvedCustomerPhone = (customerPhone != null && customerPhone.trim().isNotEmpty)
        ? customerPhone.trim()
        : '';
    final resolvedCustomerTpin = (customerTpin != null && customerTpin.trim().isNotEmpty)
        ? customerTpin.trim()
        : originalInvoice.customerTpin;

    // Prepare Credit Note SaleItems & Transaction
    final List<SaleItem> creditNoteItems = activeReturns
        .map(
          (ret) => SaleItem(
            productId: ret.productId,
            productName: ret.productName,
            productSkuAtSale: ret.sku,
            priceAtSale: ret.effectiveUnitPrice,
            discountAmountAtSale: 0.0,
            unitCostAtSale: ret.unitCostAtSale,
            quantity: ret.returnQuantity,
            unitOfMeasure: 'pcs',
            isRefunded: true,
            isDigitaxExempt: ret.isDigitaxExempt,
            taxRateAtSale: ret.taxRateAtSale,
            isTaxInclusiveAtSale: ret.isTaxInclusiveAtSale,
          ),
        )
        .toList();

    final creditNoteTx = SaleTransaction(
      totalAmount: returnedValue,
      subtotal: returnedSubtotal,
      taxAmount: returnedTax,
      discountAmount: 0.0,
      totalCost: returnedCost,
      grossProfit: -(returnedValue - returnedCost),
      paymentMethod: 'EXCHANGE CREDIT NOTE',
      cashierName: cashierName,
      cashierId: cashierId,
      terminalName: originalInvoice.terminalName,
      status: 'refunded',
      isCreditNote: true,
      orgInvoiceNo: origInvoiceNo,
      creditNoteReason: 'EXCHANGE ($exchangeNumber): $reason',
      customerId: customerId ?? originalInvoice.customerId,
      customerTpin: resolvedCustomerTpin,
      customerBusinessName: resolvedCustomerName,
      externalPaymentReference: '$exchangeNumber-CN',
      externalPaymentConfirmedBy: approvingManagerName,
      externalPaymentConfirmedAt: now,
    );

    // Prepare Replacement SaleItems & Transaction
    final List<SaleItem> replacementSaleItems = activeReplacements
        .map(
          (rep) => SaleItem(
            productId: rep.product.id,
            productName: rep.product.name,
            productSkuAtSale: rep.product.sku,
            priceAtSale: rep.unitPrice,
            discountAmountAtSale: rep.discountAmount,
            unitCostAtSale: rep.product.unitCost,
            quantity: rep.quantity,
            unitOfMeasure: rep.product.displayUnitOfMeasure,
            isRefunded: false,
            isDigitaxExempt: !rep.product.isDigitaxSyncEnabled,
            taxRateAtSale: rep.product.taxRate,
            isTaxInclusiveAtSale: rep.product.isTaxInclusive,
          ),
        )
        .toList();

    final replacementTx = SaleTransaction(
      totalAmount: replacementValue,
      subtotal: replacementSubtotal,
      taxAmount: replacementTax,
      discountAmount: replacementDiscount,
      totalCost: replacementCost,
      grossProfit: (replacementValue - replacementTax) - replacementCost,
      tenderedAmount: additionalPaid > 0 ? replacementValue : returnedValue,
      changeAmount: refundedAmount,
      paymentMethod: additionalPaid > 0
          ? paymentMethod
          : 'EXCHANGE ($origInvoiceNo)',
      cashierName: cashierName,
      cashierId: cashierId,
      terminalName: originalInvoice.terminalName,
      status: 'completed',
      isCreditNote: false,
      orgInvoiceNo: origInvoiceNo,
      customerId: customerId ?? originalInvoice.customerId,
      customerTpin: resolvedCustomerTpin,
      customerBusinessName: resolvedCustomerName,
      externalPaymentReference: '$exchangeNumber-SALE',
      externalPaymentConfirmedBy: approvingManagerName,
      externalPaymentConfirmedAt: now,
    );

    final Map<int, int> returnStockMovementIds = {};
    final Map<int, int> replacementStockMovementIds = {};
    Customer? ensuredCustomer;

    // 4. Execute atomic Isar transaction for stock, linked sales, shift, and accounts
    await db.isar.writeTxn(() async {
      // 4a. Ensure Customer record if retaining customer credit
      if (creditRetained > 0) {
        if (customerId != null) {
          ensuredCustomer = await db.isar.customers.get(customerId);
        }
        if (ensuredCustomer == null && resolvedCustomerPhone.isNotEmpty) {
          ensuredCustomer = await db.isar.customers
              .filter()
              .phoneNumberEqualTo(resolvedCustomerPhone)
              .findFirst();
        }
        if (ensuredCustomer == null) {
          final fallbackPhone = resolvedCustomerPhone.isNotEmpty
              ? resolvedCustomerPhone
              : 'EXG-${now.millisecondsSinceEpoch.toString().substring(6)}';
          ensuredCustomer = Customer(
            name: resolvedCustomerName,
            phoneNumber: fallbackPhone,
            createdAt: now,
          );
          await db.isar.customers.put(ensuredCustomer!);
        }
      }

      // 4b. Process Returned Products Inventory & Stock Movements (Section D)
      for (final ret in activeReturns) {
        final product = await db.isar.products.get(ret.productId);
        if (product != null) {
          final prevStock = product.stockLevel;
          final bool shouldRestock =
              ret.condition == ReturnedItemCondition.resalable;
          if (shouldRestock) {
            product.stockLevel += ret.returnQuantity;
            await db.isar.products.put(product);
          }

          final movement = StockMovement(
            productId: product.id,
            productName: product.name,
            sku: product.sku,
            branchCode: product.branchCode.isNotEmpty
                ? product.branchCode
                : branchCode,
            branchName: product.branchName ?? branchName,
            movementType: shouldRestock ? '11' : '06',
            actionType: shouldRestock ? 'ADD' : 'DEDUCT',
            previousStock: prevStock,
            quantityChanged: ret.returnQuantity,
            newStock: product.stockLevel,
            unitCost: product.unitCost,
            totalCostImpact: ret.returnQuantity * product.unitCost,
            reasonCategory: shouldRestock
                ? 'Exchange Return (Resalable)'
                : 'Exchange Return (${ret.condition.code} - Non-Sellable)',
            reasonNotes:
                'Exchange $exchangeNumber • Orig Inv $origInvoiceNo • Condition: ${ret.condition.code} • Reason: $reason • Approved by $approvingManagerName',
            userId: cashierId,
            userName: cashierName,
          );
          await db.isar.stockMovements.put(movement);
          returnStockMovementIds[ret.originalSaleItemId] = movement.id;
        }
      }

      // 4c. Mark original SaleItems & original SaleTransaction status
      await originalInvoice.items.load();
      final origItems = originalInvoice.items.toList();
      bool allOrigFullyReturned = true;
      for (final origItem in origItems) {
        final origQty = (origItem.isWeighted && origItem.weight > 0)
            ? origItem.weight.ceil()
            : origItem.quantity;
        final prevRet = alreadyReturnedMap[origItem.id] ?? 0;
        final currentRet = activeReturns
            .where((r) => r.originalSaleItemId == origItem.id)
            .fold(0, (s, r) => s + r.returnQuantity);
        if (prevRet + currentRet >= origQty) {
          origItem.isRefunded = true;
          await db.isar.saleItems.put(origItem);
        } else {
          allOrigFullyReturned = false;
        }
      }
      originalInvoice.status = allOrigFullyReturned
          ? 'refunded'
          : 'partially_refunded';
      await db.isar.saleTransactions.put(originalInvoice);

      // 4d. Save Credit Note Transaction & Items
      await db.isar.saleItems.putAll(creditNoteItems);
      creditNoteTx.items.addAll(creditNoteItems);
      await db.isar.saleTransactions.put(creditNoteTx);
      await creditNoteTx.items.save();

      // 4e. Process Replacement Products Inventory Deduction & Stock Movements (Section D)
      for (final rep in activeReplacements) {
        final product = await db.isar.products.get(rep.product.id);
        if (product != null) {
          final prevStock = product.stockLevel;
          product.stockLevel = (product.stockLevel - rep.quantity).clamp(
            0,
            9999999,
          );
          await db.isar.products.put(product);

          final movement = StockMovement(
            productId: product.id,
            productName: product.name,
            sku: product.sku,
            branchCode: product.branchCode.isNotEmpty
                ? product.branchCode
                : branchCode,
            branchName: product.branchName ?? branchName,
            movementType: '11',
            actionType: 'DEDUCT',
            previousStock: prevStock,
            quantityChanged: rep.quantity,
            newStock: product.stockLevel,
            unitCost: product.unitCost,
            totalCostImpact: rep.quantity * product.unitCost,
            reasonCategory: 'Exchange Replacement Sale',
            reasonNotes:
                'Exchange $exchangeNumber • Linked to Orig Inv $origInvoiceNo • Approved by $approvingManagerName',
            userId: cashierId,
            userName: cashierName,
          );
          await db.isar.stockMovements.put(movement);
          replacementStockMovementIds[product.id] = movement.id;
        }
      }

      // 4f. Save Replacement Sale Transaction & Items
      await db.isar.saleItems.putAll(replacementSaleItems);
      replacementTx.items.addAll(replacementSaleItems);
      await db.isar.saleTransactions.put(replacementTx);
      await replacementTx.items.save();

      // 4g. Net Treasury / Payment Account & Shift Settlement (No Double-Posting!)
      final activeShift = await db.isar.cashShifts
          .filter()
          .statusEqualTo('OPEN')
          .findFirst();

      if (additionalPaid > 0) {
        // Customer paid the top-up difference
        final pUpper = paymentMethod.toUpperCase();
        final accType = pUpper.contains('CASH')
            ? 'CASH'
            : (pUpper.contains('AIRTEL')
                  ? 'AIRTEL_MONEY'
                  : (pUpper.contains('MTN') ? 'MTN_MOMO' : 'BANK'));
        final account = await db.isar.paymentAccounts
            .filter()
            .accountTypeEqualTo(accType)
            .findFirst();
        if (account != null) {
          account.balance += additionalPaid;
          await db.isar.paymentAccounts.put(account);
        }
        if (pUpper.contains('CASH') && activeShift != null) {
          activeShift.cashSales += additionalPaid;
          await db.isar.cashShifts.put(activeShift);
        }
      } else if (refundedAmount > 0) {
        // Customer was refunded the excess difference
        final refundRecord = RefundTransaction()
          ..refundNumber =
              'REF-EXG-${now.millisecondsSinceEpoch.toString().substring(6)}'
          ..saleTransactionUuid = originalInvoice.transactionId
          ..refundType = paymentMethod.toUpperCase()
          ..amount = refundedAmount
          ..reason = 'Exchange Difference Refund ($exchangeNumber)'
          ..authorizedBy = approvingManagerName
          ..refundDate = now
          ..createdAt = now;
        await db.isar.refundTransactions.put(refundRecord);

        final pUpper = paymentMethod.toUpperCase();
        final accType = pUpper.contains('CASH')
            ? 'CASH'
            : (pUpper.contains('AIRTEL')
                  ? 'AIRTEL_MONEY'
                  : (pUpper.contains('MTN') ? 'MTN_MOMO' : 'BANK'));
        final account = await db.isar.paymentAccounts
            .filter()
            .accountTypeEqualTo(accType)
            .findFirst();
        if (account != null) {
          account.balance -= refundedAmount;
          await db.isar.paymentAccounts.put(account);
        }
        if (pUpper.contains('CASH') && activeShift != null) {
          activeShift.cashRefunds += refundedAmount;
          await db.isar.cashShifts.put(activeShift);
        }
      }
    });

    // 5. Persist Exchange Header, Line Items, and Customer Credit in SQLite
    final exchangeId = await localSql.insert('product_exchanges', {
      'exchange_number': exchangeNumber,
      'original_sale_id': originalInvoice.id,
      'original_invoice_no': origInvoiceNo,
      'credit_note_sale_id': creditNoteTx.id,
      'replacement_sale_id': replacementTx.id,
      'customer_id': ensuredCustomer?.id ?? customerId ?? originalInvoice.customerId,
      'customer_name': resolvedCustomerName,
      'customer_phone': resolvedCustomerPhone,
      'customer_tpin': resolvedCustomerTpin,
      'branch_code': branchCode,
      'branch_name': branchName,
      'returned_value': returnedValue,
      'returned_tax': returnedTax,
      'replacement_value': replacementValue,
      'replacement_discount': replacementDiscount,
      'replacement_tax': replacementTax,
      'difference_amount': differenceAmount,
      'scenario_type': scenarioType,
      'settlement_mode': settlementMode,
      'payment_method': paymentMethod,
      'additional_paid': additionalPaid,
      'refunded_amount': refundedAmount,
      'credit_retained': creditRetained,
      'reason': reason,
      'cashier_id': cashierId,
      'cashier_name': cashierName,
      'approving_manager_id': approvingManagerId,
      'approving_manager_name': approvingManagerName,
      'created_at': now.toIso8601String(),
    });

    final List<Map<String, dynamic>> savedReturnMaps = [];
    for (final ret in activeReturns) {
      final row = {
        'exchange_id': exchangeId,
        'exchange_number': exchangeNumber,
        'original_sale_id': originalInvoice.id,
        'original_sale_item_id': ret.originalSaleItemId,
        'direction': 'RETURNED',
        'product_id': ret.productId,
        'product_name': ret.productName,
        'sku': ret.sku,
        'quantity': ret.returnQuantity,
        'unit_price': ret.effectiveUnitPrice,
        'discount_amount': 0.0,
        'tax_rate': ret.taxRateAtSale,
        'line_total': ret.lineTotal,
        'condition_status': ret.condition.code,
        'restocked': ret.condition == ReturnedItemCondition.resalable ? 1 : 0,
        'stock_movement_id': returnStockMovementIds[ret.originalSaleItemId],
      };
      await localSql.insert('product_exchange_items', row);
      savedReturnMaps.add(row);
    }

    final List<Map<String, dynamic>> savedReplacementMaps = [];
    for (final rep in activeReplacements) {
      final row = {
        'exchange_id': exchangeId,
        'exchange_number': exchangeNumber,
        'original_sale_id': originalInvoice.id,
        'original_sale_item_id': null,
        'direction': 'REPLACEMENT',
        'product_id': rep.product.id,
        'product_name': rep.product.name,
        'sku': rep.product.sku,
        'quantity': rep.quantity,
        'unit_price': rep.unitPrice,
        'discount_amount': rep.discountAmount,
        'tax_rate': rep.product.taxRate,
        'line_total': rep.lineTotal,
        'condition_status': 'NEW_SALE',
        'restocked': 0,
        'stock_movement_id': replacementStockMovementIds[rep.product.id],
      };
      await localSql.insert('product_exchange_items', row);
      savedReplacementMaps.add(row);
    }

    if (creditRetained > 0) {
      await localSql.insert('customer_credit_ledger', {
        'customer_id': ensuredCustomer?.id ?? customerId ?? originalInvoice.customerId,
        'customer_name': resolvedCustomerName,
        'customer_phone': resolvedCustomerPhone,
        'exchange_number': exchangeNumber,
        'credit_type': 'ISSUED',
        'amount': creditRetained,
        'remaining_balance': creditRetained,
        'branch_code': branchCode,
        'notes':
            'Exchange credit retained from $exchangeNumber (Orig Inv: $origInvoiceNo)',
        'created_at': now.toIso8601String(),
      });
    }

    // 6. Submit linked Credit Note & Replacement Sale to ZRA DigiTax in background
    final digitax = ref.read(digitaxInventoryServiceProvider);
    Future(() async {
      try {
        await digitax.submitCreditNoteToDigitax(
          creditNoteTx,
          items: creditNoteItems,
          originalSdcInvoiceNo: origInvoiceNo,
          reason: reason,
        );
      } catch (e) {
        debugPrint('EXCHANGE_DIGITAX_CN_NOTE: $e');
      }
      try {
        await digitax.fiscalizeSaleTransaction(
          replacementTx,
          replacementSaleItems,
        );
      } catch (e) {
        debugPrint('EXCHANGE_DIGITAX_SALE_NOTE: $e');
      }
    });

    return ProductExchangeRecord(
      id: exchangeId,
      exchangeNumber: exchangeNumber,
      originalSaleId: originalInvoice.id,
      originalInvoiceNo: origInvoiceNo,
      creditNoteSaleId: creditNoteTx.id,
      replacementSaleId: replacementTx.id,
      customerId: ensuredCustomer?.id ?? customerId ?? originalInvoice.customerId,
      customerName: resolvedCustomerName,
      customerPhone: resolvedCustomerPhone,
      customerTpin: resolvedCustomerTpin,
      branchCode: branchCode,
      branchName: branchName,
      returnedValue: returnedValue,
      returnedTax: returnedTax,
      replacementValue: replacementValue,
      replacementDiscount: replacementDiscount,
      replacementTax: replacementTax,
      differenceAmount: differenceAmount,
      scenarioType: scenarioType,
      settlementMode: settlementMode,
      paymentMethod: paymentMethod,
      additionalPaid: additionalPaid,
      refundedAmount: refundedAmount,
      creditRetained: creditRetained,
      reason: reason,
      cashierName: cashierName,
      approvingManagerName: approvingManagerName,
      createdAt: now,
      returnedItems: savedReturnMaps,
      replacementItems: savedReplacementMaps,
    );
  }

  /// Generates and prints/exports the official Exchange Receipt (Section E)
  Future<void> printOrExportExchangeReceipt(
    ProductExchangeRecord record, {
    bool printDirectly = true,
  }) async {
    final config = ref.read(storeConfigProvider).value;
    final currency = config?.currencySymbol ?? 'K';
    final companyName = (config != null && config.businessName.isNotEmpty)
        ? config.businessName.toUpperCase()
        : 'BELEKA PRO POS';
    final branch = record.branchName;
    final address = config?.address ?? '';
    final phone = config?.contactNumber ?? '';
    final tpin = config?.tpin ?? config?.taxId ?? '';
    final df = DateFormat('dd MMM yyyy • HH:mm');

    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Center(
                child: pw.Text(
                  companyName,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              if (branch.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    branch,
                    style: const pw.TextStyle(fontSize: 8.5),
                  ),
                ),
              if (address.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    address,
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              if (phone.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'Tel: $phone',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              if (tpin.isNotEmpty)
                pw.Center(
                  child: pw.Text(
                    'TPIN: $tpin',
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1),
              pw.Center(
                child: pw.Text(
                  'OFFICIAL PRODUCT EXCHANGE RECEIPT',
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.Divider(thickness: 1),
              _pdfMetaRow('Exchange No:', record.exchangeNumber),
              _pdfMetaRow('Original Invoice:', record.originalInvoiceNo),
              if (record.creditNoteSaleId != null)
                _pdfMetaRow(
                  'Credit Note Ref:',
                  'CN-#${record.creditNoteSaleId.toString().padLeft(6, '0')}',
                ),
              if (record.replacementSaleId != null)
                _pdfMetaRow(
                  'New Sale Ref:',
                  'INV-#${record.replacementSaleId.toString().padLeft(6, '0')}',
                ),
              _pdfMetaRow('Date & Time:', df.format(record.createdAt)),
              _pdfMetaRow('Customer:', record.customerName),
              if (record.customerPhone.isNotEmpty)
                _pdfMetaRow('Customer Tel:', record.customerPhone),
              if (record.customerTpin != null &&
                  record.customerTpin!.isNotEmpty)
                _pdfMetaRow('Buyer TPIN:', record.customerTpin!),
              _pdfMetaRow('Exchange Reason:', record.reason),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              pw.Text(
                'RETURNED PRODUCTS (CREDIT NOTE)',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              ...record.returnedItems.map((item) {
                final name = item['product_name']?.toString() ?? '';
                final qty = item['quantity'] ?? 1;
                final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                final total = (item['line_total'] as num?)?.toDouble() ?? 0.0;
                final cond = item['condition_status']?.toString() ?? 'RESALABLE';
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              '$name [$cond]',
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ),
                          pw.Text(
                            '-${CurrencyFormatter.format(total, currency)}',
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.Text(
                        '  $qty x ${CurrencyFormatter.format(price, currency)}',
                        style: const pw.TextStyle(fontSize: 7.5),
                      ),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 0.5),
              pw.Text(
                'REPLACEMENT PRODUCTS (NEW SALE)',
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              ...record.replacementItems.map((item) {
                final name = item['product_name']?.toString() ?? '';
                final qty = item['quantity'] ?? 1;
                final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
                final total = (item['line_total'] as num?)?.toDouble() ?? 0.0;
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Expanded(
                            child: pw.Text(
                              name,
                              style: const pw.TextStyle(fontSize: 8),
                            ),
                          ),
                          pw.Text(
                            CurrencyFormatter.format(total, currency),
                            style: pw.TextStyle(
                              fontSize: 8,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.Text(
                        '  $qty x ${CurrencyFormatter.format(price, currency)}',
                        style: const pw.TextStyle(fontSize: 7.5),
                      ),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 1),
              _pdfMetaRow(
                'Returned Product Value:',
                CurrencyFormatter.format(record.returnedValue, currency),
              ),
              _pdfMetaRow(
                'Replacement Product Value:',
                CurrencyFormatter.format(record.replacementValue, currency),
              ),
              if (record.replacementDiscount > 0)
                _pdfMetaRow(
                  'Replacement Discount:',
                  '-${CurrencyFormatter.format(record.replacementDiscount, currency)}',
                ),
              pw.SizedBox(height: 3),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    record.differenceAmount > 0.009
                        ? 'ADDITIONAL PAYABLE:'
                        : (record.differenceAmount < -0.009
                              ? (record.settlementMode == 'CUSTOMER_CREDIT'
                                    ? 'CUSTOMER CREDIT RETAINED:'
                                    : 'DIFFERENCE REFUNDABLE:')
                              : 'NET DIFFERENCE (EQUAL):'),
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    CurrencyFormatter.format(
                      record.differenceAmount.abs(),
                      currency,
                    ),
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              _pdfMetaRow('Settlement / Payment:', record.paymentMethod),
              _pdfMetaRow('Cashier:', record.cashierName),
              _pdfMetaRow('Approved By Manager:', record.approvingManagerName),
              pw.Divider(thickness: 0.5),
              pw.Center(
                child: pw.Text(
                  'Thank you for shopping with us!',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ],
          );
        },
      ),
    );

    final bytes = await doc.save();
    if (printDirectly) {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Exchange_Receipt_${record.exchangeNumber}',
      );
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/${record.exchangeNumber}.pdf');
      await file.writeAsBytes(bytes);
    }
  }

  pw.Widget _pdfMetaRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
          pw.Flexible(
            child: pw.Text(
              value,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Fetch comprehensive Exchange Reports for Section F
  Future<ProductExchangeReportSummary> getExchangeReportSummary(
    DateTime start,
    DateTime end,
  ) async {
    final localSql = ref.read(localSqlServiceProvider);
    final startIso = start.toIso8601String();
    final endIso = end.toIso8601String();

    try {
      final exchangeRows = await localSql.query(
        'SELECT * FROM product_exchanges '
        'WHERE created_at >= ? AND created_at <= ? '
        'ORDER BY created_at DESC',
        [startIso, endIso],
      );

      double totalReturnedValue = 0.0;
      double totalReplacementValue = 0.0;
      double totalAdditionalPayments = 0.0;
      double totalRefundsFromExchanges = 0.0;
      final Map<String, Map<String, dynamic>> branchAgg = {};
      final List<ProductExchangeRecord> records = [];

      for (final row in exchangeRows) {
        final exId = row['id'] as int;
        final retVal = (row['returned_value'] as num?)?.toDouble() ?? 0.0;
        final repVal = (row['replacement_value'] as num?)?.toDouble() ?? 0.0;
        final addPaid = (row['additional_paid'] as num?)?.toDouble() ?? 0.0;
        final refAmt = (row['refunded_amount'] as num?)?.toDouble() ?? 0.0;
        final credRet = (row['credit_retained'] as num?)?.toDouble() ?? 0.0;
        final bCode = row['branch_code']?.toString() ?? '00';
        final bName = row['branch_name']?.toString() ?? 'Main Branch (HQ)';

        totalReturnedValue += retVal;
        totalReplacementValue += repVal;
        totalAdditionalPayments += addPaid;
        totalRefundsFromExchanges += refAmt;

        final bEntry = branchAgg.putIfAbsent(
          bCode,
          () => {
            'branchCode': bCode,
            'branchName': bName,
            'exchangeCount': 0,
            'returnedValue': 0.0,
            'replacementValue': 0.0,
            'additionalCollected': 0.0,
            'refundedAmount': 0.0,
            'creditRetained': 0.0,
          },
        );
        bEntry['exchangeCount'] = (bEntry['exchangeCount'] as int) + 1;
        bEntry['returnedValue'] =
            (bEntry['returnedValue'] as double) + retVal;
        bEntry['replacementValue'] =
            (bEntry['replacementValue'] as double) + repVal;
        bEntry['additionalCollected'] =
            (bEntry['additionalCollected'] as double) + addPaid;
        bEntry['refundedAmount'] =
            (bEntry['refundedAmount'] as double) + refAmt;
        bEntry['creditRetained'] =
            (bEntry['creditRetained'] as double) + credRet;

        final itemRows = await localSql.query(
          'SELECT * FROM product_exchange_items WHERE exchange_id = ?',
          [exId],
        );
        final retItems = itemRows
            .where((i) => i['direction'] == 'RETURNED')
            .toList();
        final repItems = itemRows
            .where((i) => i['direction'] == 'REPLACEMENT')
            .toList();

        records.add(
          ProductExchangeRecord(
            id: exId,
            exchangeNumber: row['exchange_number']?.toString() ?? '',
            originalSaleId: (row['original_sale_id'] as num?)?.toInt() ?? 0,
            originalInvoiceNo: row['original_invoice_no']?.toString() ?? '',
            creditNoteSaleId: (row['credit_note_sale_id'] as num?)?.toInt(),
            replacementSaleId: (row['replacement_sale_id'] as num?)?.toInt(),
            customerId: (row['customer_id'] as num?)?.toInt(),
            customerName:
                row['customer_name']?.toString() ?? 'Walk-in Customer',
            customerPhone: row['customer_phone']?.toString() ?? '',
            customerTpin: row['customer_tpin']?.toString(),
            branchCode: bCode,
            branchName: bName,
            returnedValue: retVal,
            returnedTax: (row['returned_tax'] as num?)?.toDouble() ?? 0.0,
            replacementValue: repVal,
            replacementDiscount:
                (row['replacement_discount'] as num?)?.toDouble() ?? 0.0,
            replacementTax:
                (row['replacement_tax'] as num?)?.toDouble() ?? 0.0,
            differenceAmount:
                (row['difference_amount'] as num?)?.toDouble() ?? 0.0,
            scenarioType: row['scenario_type']?.toString() ?? 'EQUAL_VALUE',
            settlementMode:
                row['settlement_mode']?.toString() ?? 'EVEN_EXCHANGE',
            paymentMethod: row['payment_method']?.toString() ?? 'EVEN EXCHANGE',
            additionalPaid: addPaid,
            refundedAmount: refAmt,
            creditRetained: credRet,
            reason: row['reason']?.toString() ?? '',
            cashierName: row['cashier_name']?.toString() ?? '',
            approvingManagerName:
                row['approving_manager_name']?.toString() ?? '',
            createdAt:
                DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.now(),
            returnedItems: retItems,
            replacementItems: repItems,
          ),
        );
      }

      // Most frequently exchanged products
      final freqRows = await localSql.query(
        'SELECT i.product_id, i.product_name, i.sku, i.direction, '
        'SUM(i.quantity) as total_qty, COUNT(DISTINCT i.exchange_id) as exchange_count, '
        'SUM(i.line_total) as total_value '
        'FROM product_exchange_items i '
        'JOIN product_exchanges e ON e.id = i.exchange_id '
        'WHERE e.created_at >= ? AND e.created_at <= ? AND i.direction = ? '
        'GROUP BY i.product_id, i.product_name, i.sku, i.direction '
        'ORDER BY total_qty DESC LIMIT 15',
        [startIso, endIso, 'RETURNED'],
      );

      // Outstanding customer credit from exchanges (all-time active balances)
      final creditRows = await localSql.query(
        'SELECT * FROM customer_credit_ledger '
        'WHERE remaining_balance > 0.009 '
        'ORDER BY created_at DESC',
      );
      final double totalOutstandingCredit = creditRows.fold(
        0.0,
        (s, r) => s + ((r['remaining_balance'] as num?)?.toDouble() ?? 0.0),
      );

      return ProductExchangeReportSummary(
        totalExchanges: exchangeRows.length,
        totalReturnedValue: totalReturnedValue,
        totalReplacementValue: totalReplacementValue,
        totalAdditionalPaymentsCollected: totalAdditionalPayments,
        totalRefundsFromExchanges: totalRefundsFromExchanges,
        totalOutstandingCustomerCredit: totalOutstandingCredit,
        mostFrequentlyExchangedProducts: freqRows,
        exchangeValueByBranch: branchAgg.values.toList(),
        customerCreditBalances: creditRows,
        recentExchanges: records,
      );
    } catch (e) {
      debugPrint('EXCHANGE_REPORT_SUMMARY_ERROR: $e');
      return const ProductExchangeReportSummary(
        totalExchanges: 0,
        totalReturnedValue: 0.0,
        totalReplacementValue: 0.0,
        totalAdditionalPaymentsCollected: 0.0,
        totalRefundsFromExchanges: 0.0,
        totalOutstandingCustomerCredit: 0.0,
        mostFrequentlyExchangedProducts: [],
        exchangeValueByBranch: [],
        customerCreditBalances: [],
        recentExchanges: [],
      );
    }
  }
}
