import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart' show debugPrint;
import 'package:isar/isar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:intl/intl.dart';

/// Hashes a plain-text PIN using SHA-256.
String hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}

final isarProvider = Provider<Isar>((ref) => throw UnimplementedError());

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  final isar = ref.watch(isarProvider);
  return DatabaseService(isar);
});

class DatabaseService {
  final Isar isar;

  DatabaseService(this.isar);

  Future<bool> hasUsers() async {
    final count = await isar.users.count();
    return count > 0;
  }

  Future<User?> getUserByNumericId(String numericId) async {
    return await isar.users.filter().numericIdEqualTo(numericId).findFirst();
  }

  Future<User?> getAdminUser() async {
    return await isar.users.where().filter().roleEqualTo('manager').or().roleEqualTo('admin').findFirst();
  }


  // User methods
  Future<User?> login(String numericId, String pin) async {
    final hashedPin = hashPin(pin);
    return await isar.users
        .filter()
        .numericIdEqualTo(numericId)
        .passwordHashEqualTo(hashedPin)
        .findFirst();
  }

  Future<List<User>> getAllUsers() async {
    return await isar.users.where().findAll();
  }

  Future<void> saveUser(User user) async {
    await isar.writeTxn(() async {
      await isar.users.put(user);
    });
  }

  Future<void> deleteUser(Id id) async {
    await isar.writeTxn(() async {
      await isar.users.delete(id);
    });
  }

  // Attendance logic
  Future<void> logAttendance(User user, String type) async {
    final log = AttendanceLog()
      ..userId = user.id
      ..username = user.name
      ..timestamp = DateTime.now()
      ..type = type;

    await isar.writeTxn(() => isar.attendanceLogs.put(log));
  }

  Future<AttendanceLog?> getLastAttendance(int userId) async {
    return await isar.attendanceLogs
        .filter()
        .userIdEqualTo(userId)
        .sortByTimestampDesc()
        .findFirst();
  }

  // Product methods
  Future<List<Product>> getAllProducts({bool includeArchived = false}) async {
    if (includeArchived) {
      return await isar.products.where().findAll();
    }
    return await isar.products.filter().isArchivedEqualTo(false).findAll();
  }

  Stream<List<Product>> watchAllProducts({bool includeArchived = false}) {
    if (includeArchived) {
      return isar.products.where().build().watch(fireImmediately: true);
    }
    return isar.products.filter().isArchivedEqualTo(false).build().watch(fireImmediately: true);
  }

  Future<Product?> getProductBySku(String sku) async {
    return await isar.products.filter().isArchivedEqualTo(false).skuEqualTo(sku).findFirst();
  }

  Future<List<Product>> searchProducts(String query, {bool includeArchived = false}) async {
    var queryBuilder = isar.products.filter();
    
    if (!includeArchived) {
      queryBuilder = queryBuilder.isArchivedEqualTo(false).and();
    }
    
    return await queryBuilder
      .group((q) => q.nameContains(query, caseSensitive: false).or().skuContains(query, caseSensitive: false))
      .findAll();
  }

  Future<List<Product>> getProductsByCategory(int categoryId) async {
    return await isar.products.filter().categoryIdEqualTo(categoryId).findAll();
  }

  Future<void> saveProduct(Product product) async {
    await isar.writeTxn(() async {
      await isar.products.put(product);
    });
  }

  Future<void> archiveProduct(Id id) async {
    await isar.writeTxn(() async {
      final product = await isar.products.get(id);
      if (product != null) {
        product.isArchived = true;
        await isar.products.put(product);
      }
    });
  }

  Future<void> unarchiveProduct(Id id) async {
    await isar.writeTxn(() async {
      final product = await isar.products.get(id);
      if (product != null) {
        product.isArchived = false;
        await isar.products.put(product);
      }
    });
  }

  // --- Customer Methods ---
  Future<List<Customer>> getAllCustomers() async {
    return await isar.customers.where().findAll();
  }

  Stream<List<Customer>> watchAllCustomers() {
    return isar.customers.where().watch(fireImmediately: true);
  }

  Future<List<Customer>> searchCustomers(String query) async {
    return await isar.customers.filter()
      .phoneNumberContains(query, caseSensitive: false)
      .or()
      .nameContains(query, caseSensitive: false)
      .findAll();
  }
  
  Future<Customer?> getCustomerById(int id) async {
    return await isar.customers.get(id);
  }

  Future<void> saveCustomer(Customer customer) async {
    await isar.writeTxn(() async {
      await isar.customers.put(customer);
    });
  }

  Future<void> deleteCustomer(Id id) async {
    await isar.writeTxn(() async {
      await isar.customers.delete(id);
    });
  }

  // Category methods
  Future<List<Category>> getAllCategories() async {
    return await isar.categorys.where().findAll();
  }

  Stream<List<Category>> watchAllCategories() {
    return isar.categorys.where().watch(fireImmediately: true);
  }

  Future<void> saveCategories(List<Category> categories) async {
    await isar.writeTxn(() async {
      await isar.categorys.putAll(categories);
    });
  }

  // Store Config methods
  Future<StoreConfig?> getStoreConfig() async {
    return await isar.storeConfigs.where().findFirst();
  }

  Future<void> saveStoreConfig(StoreConfig config) async {
    await isar.writeTxn(() async {
      await isar.storeConfigs.put(config);
    });
  }

  // Transaction methods
  Future<void> saveTransaction(SaleTransaction transaction, List<SaleItem> items) async {
    // 0. Pre-check stock levels for all items
    for (final item in items) {
      final product = await isar.products.get(item.productId);
      if (product == null) {
        throw Exception('Product Not Found: Internal database error.');
      }
      if (product.stockLevel < item.quantity) {
        throw Exception('INSUFFICIENT_STOCK: ${product.name} (Only ${product.stockLevel} left)');
      }
    }

    await isar.writeTxn(() async {
      // 1. Save all SaleItems first
      await isar.saleItems.putAll(items);
      
      // 2. Link items to the transaction
      transaction.items.addAll(items);
      
      // 3. Save the transaction and the links
      await isar.saleTransactions.put(transaction);
      await transaction.items.save();

      // 4. Update product stock levels
      double totalCost = 0.0;

      for (final item in items) {
        final product = await isar.products.get(item.productId);
        if (product != null) {
          final oldStock = product.stockLevel;
          product.stockLevel -= item.quantity;
          await isar.products.put(product);
          
          debugPrint('STOCK_DEDUCTION: Product ${product.name} (ID: ${product.id}) | Before: $oldStock | Deducted: ${item.quantity} | After: ${product.stockLevel}');
          
          totalCost += (item.unitCostAtSale) * item.quantity;
        }
      }

      // 5. Update transaction totals with the calculated costs
      transaction.totalCost = totalCost;
      
      // Calculate profit: (Subtotal after discount) - Cost of goods
      // This correctly accounts for discounts and ignores tax
      transaction.grossProfit = (transaction.subtotal - transaction.discountAmount) - totalCost;
      
      await isar.saleTransactions.put(transaction);

      // 5. Update customer loyalty points if applicable
      if (transaction.customerId != null) {
        final config = await isar.storeConfigs.where().findFirst();
        final loyaltyActive = config?.loyaltyEnabled ?? false;
        
        final customer = await isar.customers.get(transaction.customerId!);
        if (customer != null) {
          if (loyaltyActive) {
            // Centralized point calculation: Accumulated + Earned - Redeemed
            final earned = transaction.pointsEarned;
            final redeemed = transaction.pointsRedeemed;
            customer.accumulatedPoints = (customer.accumulatedPoints + earned - redeemed).clamp(0, 999999);
          }
          customer.totalSpend += transaction.totalAmount;
          await isar.customers.put(customer);
        }
      }
    });
  }

  // Refund methods
  Future<void> refundItems(Id transactionId, List<Id> itemIds) async {
    final transaction = await isar.saleTransactions.get(transactionId);
    if (transaction == null) return;

    await isar.writeTxn(() async {
      await transaction.items.load();
      final allItems = transaction.items.toList();
      final itemsToRefund = allItems.where((item) => itemIds.contains(item.id) && !item.isRefunded).toList();

      if (itemsToRefund.isEmpty) return;

      double refundedAmount = 0;
      double refundedCost = 0;

      for (var item in itemsToRefund) {
        item.isRefunded = true;
        await isar.saleItems.put(item);

        // Restore stock
        final product = await isar.products.get(item.productId);
        if (product != null) {
          product.stockLevel += item.quantity;
          await isar.products.put(product);
        }

        refundedAmount += item.priceAtSale * item.quantity;
        refundedCost += item.unitCostAtSale * item.quantity;
      }

      // Update transaction status
      final alreadyRefundedCount = allItems.where((i) => i.isRefunded).length;
      if (alreadyRefundedCount == allItems.length) {
        transaction.status = 'refunded';
      } else {
        transaction.status = 'partially_refunded';
      }

      // Proportional reduction in customer loyalty points/spend
      if (transaction.customerId != null) {
        final customer = await isar.customers.get(transaction.customerId!);
        if (customer != null) {
          final config = await isar.storeConfigs.where().findFirst();
          if (config?.loyaltyEnabled ?? false) {
            final pointsToRemove = (refundedAmount * config!.loyaltyEarnRate).floor();
            customer.accumulatedPoints = (customer.accumulatedPoints - pointsToRemove).clamp(0, 999999);
          }
          customer.totalSpend = (customer.totalSpend - refundedAmount).clamp(0.0, 999999999.0);
          await isar.customers.put(customer);
        }
      }

      // Update transaction profit
      transaction.grossProfit -= (refundedAmount - refundedCost);
      
      await isar.saleTransactions.put(transaction);
    });
  }

  Future<void> refundTransaction(Id transactionId) async {
    final items = await getTransactionItems(transactionId);
    await refundItems(transactionId, items.map((i) => i.id).toList());
  }


  Stream<List<SaleTransaction>> watchRecentTransactions({int limit = 10, String query = ''}) {
    if (query.isEmpty) {
      return isar.saleTransactions.where().sortByTimestampDesc().limit(limit).watch(fireImmediately: true);
    }
    return isar.saleTransactions
        .filter()
        .transactionIdContains(query, caseSensitive: false)
        .or()
        .cashierNameContains(query, caseSensitive: false)
        .sortByTimestampDesc()
        .limit(limit)
        .watch(fireImmediately: true);
  }

  Stream<List<SaleTransaction>> watchCashierRecentTransactions(String cashierName, {int limit = 10, String query = ''}) {
    var q = isar.saleTransactions
        .filter()
        .cashierNameEqualTo(cashierName, caseSensitive: false);
    
    if (query.isNotEmpty) {
      q = q.and().transactionIdContains(query, caseSensitive: false);
    }
    
    return q.sortByTimestampDesc().limit(limit).watch(fireImmediately: true);
  }

  Future<List<SaleTransaction>> getRecentTransactions({int limit = 50, String? query}) async {
    final queryBuilder = (query != null && query.isNotEmpty)
        ? isar.saleTransactions.filter()
            .transactionIdContains(query, caseSensitive: false)
            .or()
            .cashierNameContains(query, caseSensitive: false)
            .or()
            .terminalNameContains(query, caseSensitive: false)
            .sortByTimestampDesc()
        : isar.saleTransactions.where().sortByTimestampDesc();

    final transactions = await queryBuilder.limit(limit).findAll();
    for (var tx in transactions) {
      await tx.items.load();
    }
    return transactions;
  }



  Future<List<SaleItem>> getTransactionItems(Id transactionId) async {
    final transaction = await isar.saleTransactions.get(transactionId);
    if (transaction != null) {
      await transaction.items.load();
      return transaction.items.toList();
    }
    return [];
  }

  Future<Map<String, double>> getDashboardStats() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));

    final todaySales = await isar.saleTransactions
        .filter()
        .timestampBetween(startOfToday, endOfToday)
        .findAll();

    final yesterdaySales = await isar.saleTransactions
        .filter()
        .timestampBetween(startOfYesterday, startOfToday)
        .findAll();

    double todayRevenue = todaySales.fold(0.0, (sum, t) {
      if (t.totalAmount.isNaN) return sum;
      return sum + t.totalAmount;
    });
    double yesterdayRevenue = yesterdaySales.fold(0.0, (sum, t) {
      if (t.totalAmount.isNaN) return sum;
      return sum + t.totalAmount;
    });
    double todayProfit = todaySales.fold(0.0, (sum, t) {
      if (t.grossProfit.isNaN) return sum;
      return sum + t.grossProfit;
    });
    double yesterdayProfit = yesterdaySales.fold(0.0, (sum, t) {
      if (t.grossProfit.isNaN) return sum;
      return sum + t.grossProfit;
    });

    double todayTax = todaySales.fold(0.0, (sum, t) {
      if (t.taxAmount.isNaN) return sum;
      return sum + t.taxAmount;
    });
    double yesterdayTax = yesterdaySales.fold(0.0, (sum, t) {
      if (t.taxAmount.isNaN) return sum;
      return sum + t.taxAmount;
    });

    return {
      'todayRevenue': todayRevenue,
      'yesterdayRevenue': yesterdayRevenue,
      'todayProfit': todayProfit,
      'yesterdayProfit': yesterdayProfit,
      'todayTax': todayTax,
      'yesterdayTax': yesterdayTax,
      'todayCount': todaySales.length.toDouble(),
    };
  }

  Stream<Map<String, double>> watchDashboardStats() async* {
    yield await getDashboardStats();
    await for (final _ in isar.saleTransactions.watchLazy()) {
      yield await getDashboardStats();
    }
  }

  Future<Map<String, double>> getCashierDashboardStats(String cashierName) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final startOfYesterday = startOfToday.subtract(const Duration(days: 1));

    final todaySales = await isar.saleTransactions
        .filter()
        .cashierNameEqualTo(cashierName, caseSensitive: false)
        .timestampBetween(startOfToday, endOfToday)
        .findAll();

    final yesterdaySales = await isar.saleTransactions
        .filter()
        .cashierNameEqualTo(cashierName, caseSensitive: false)
        .timestampBetween(startOfYesterday, startOfToday)
        .findAll();

    double todayRevenue = todaySales.fold(0.0, (sum, t) => sum + (t.totalAmount.isNaN ? 0.0 : t.totalAmount));
    double yesterdayRevenue = yesterdaySales.fold(0.0, (sum, t) => sum + (t.totalAmount.isNaN ? 0.0 : t.totalAmount));

    int totalItems = 0;
    for (var t in todaySales) {
      await t.items.load();
      totalItems += t.items.fold(0, (sum, item) => sum + item.quantity);
    }

    return {
      'todayRevenue': todayRevenue,
      'yesterdayRevenue': yesterdayRevenue,
      'todayCount': todaySales.length.toDouble(),
      'todayItems': totalItems.toDouble(),
    };
  }

  Stream<Map<String, double>> watchCashierDashboardStats(String cashierName) async* {
    yield await getCashierDashboardStats(cashierName);
    await for (final _ in isar.saleTransactions.watchLazy()) {
      yield await getCashierDashboardStats(cashierName);
    }
  }

  Future<List<Map<String, dynamic>>> getSalesVelocityData() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    final transactions = await isar.saleTransactions
        .filter()
        .timestampBetween(startOfToday, endOfToday)
        .sortByTimestamp()
        .findAll();

    // Group by hour
    final hourlyData = List.generate(24, (index) => 0.0);
    for (var t in transactions) {
      final amt = t.totalAmount.isNaN ? 0.0 : t.totalAmount;
      hourlyData[t.timestamp.hour] += amt;
    }

    return List.generate(24, (i) {
      return {'hour': i, 'revenue': hourlyData[i]};
    });
  }

  Stream<List<Map<String, dynamic>>> watchSalesVelocityData() async* {
    yield await getSalesVelocityData();
    await for (final _ in isar.saleTransactions.watchLazy()) {
      yield await getSalesVelocityData();
    }
  }

  Future<List<Map<String, dynamic>>> getCashierSalesVelocityData(String cashierName) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    final transactions = await isar.saleTransactions
        .filter()
        .cashierNameEqualTo(cashierName, caseSensitive: false)
        .timestampBetween(startOfToday, endOfToday)
        .sortByTimestamp()
        .findAll();

    final hourlyData = List.generate(24, (index) => 0.0);
    for (var t in transactions) {
      hourlyData[t.timestamp.hour] += (t.totalAmount.isNaN ? 0.0 : t.totalAmount);
    }

    return List.generate(24, (i) => {'hour': i, 'revenue': hourlyData[i]});
  }

  Stream<List<Map<String, dynamic>>> watchCashierSalesVelocityData(String cashierName) async* {
    yield await getCashierSalesVelocityData(cashierName);
    await for (final _ in isar.saleTransactions.watchLazy()) {
      yield await getCashierSalesVelocityData(cashierName);
    }
  }

  Future<List<Map<String, dynamic>>> getTopSellingProducts({int limit = 5}) async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    final transactions = await isar.saleTransactions
        .filter()
        .timestampBetween(startOfToday, endOfToday)
        .findAll();

    final Map<int, int> productQuantities = {};
    final Map<int, String> productNames = {};

    for (var t in transactions) {
      await t.items.load();
      for (var item in t.items) {
        productQuantities[item.productId] = (productQuantities[item.productId] ?? 0) + item.quantity;
        productNames[item.productId] = item.productName;
      }
    }

    final sortedProducts = productQuantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedProducts.take(limit).map((e) => {
      'productId': e.key,
      'name': productNames[e.key],
      'quantity': e.value,
    }).toList();
  }

  Stream<List<Map<String, dynamic>>> watchTopSellingProducts({int limit = 5}) async* {
    yield await getTopSellingProducts(limit: limit);
    await for (final _ in isar.saleTransactions.watchLazy()) {
      yield await getTopSellingProducts(limit: limit);
    }
  }

  Future<List<Product>> getLowStockProducts({int threshold = 10, bool includeArchived = false}) async {
    var queryBuilder = isar.products.filter();
    if (!includeArchived) {
      queryBuilder = queryBuilder.isArchivedEqualTo(false).and();
    }
    return await queryBuilder
        .stockLevelLessThan(threshold)
        .findAll();
  }

  Stream<List<Product>> watchLowStockProducts({int threshold = 10, bool includeArchived = false}) {
    var queryBuilder = isar.products.filter();
    if (!includeArchived) {
      queryBuilder = queryBuilder.isArchivedEqualTo(false).and();
    }
    return queryBuilder
        .stockLevelLessThan(threshold)
        .watch(fireImmediately: true);
  }

  Future<Map<String, double>> getPaymentMethodDistribution() async {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));

    final todaySales = await isar.saleTransactions
        .filter()
        .timestampBetween(startOfToday, endOfToday)
        .findAll();

    final distribution = <String, double>{};
    for (var t in todaySales) {
      final amount = t.totalAmount.isNaN ? 0.0 : t.totalAmount;
      final method = t.paymentMethod.toLowerCase().replaceAll(' ', '_');
      distribution[method] = (distribution[method] ?? 0) + amount;
    }
    return distribution;
  }

  Stream<Map<String, double>> watchPaymentMethodDistribution() async* {
    yield await getPaymentMethodDistribution();
    await for (final _ in isar.saleTransactions.watchLazy()) {
      yield await getPaymentMethodDistribution();
    }
  }

  // --- Range Reporting Methods ---

  Future<List<SaleTransaction>> getTransactionsInRange(DateTime start, DateTime end) async {
    final transactions = await isar.saleTransactions
        .filter()
        .timestampBetween(start, end)
        .sortByTimestampDesc()
        .findAll();

    for (var tx in transactions) {
      await tx.items.load();
    }
    
    return transactions;
  }

  Stream<List<SaleTransaction>> watchTransactionsInRange(DateTime start, DateTime end) async* {
    yield await getTransactionsInRange(start, end);
    await for (final _ in isar.saleTransactions.watchLazy()) {
      yield await getTransactionsInRange(start, end);
    }
  }

  Future<Map<String, double>> getRangeStats(DateTime start, DateTime end) async {
    final transactions = await getTransactionsInRange(start, end);

    double revenue = transactions.fold(0.0, (sum, t) => sum + (t.totalAmount.isNaN ? 0.0 : t.totalAmount));
    double profit = transactions.fold(0.0, (sum, t) => sum + (t.grossProfit.isNaN ? 0.0 : t.grossProfit));
    double tax = transactions.fold(0.0, (sum, t) => sum + (t.taxAmount.isNaN ? 0.0 : t.taxAmount));

    final Map<String, double> paymentBreakdown = {};
    for (var t in transactions) {
      final amount = t.totalAmount.isNaN ? 0.0 : t.totalAmount;
      final method = t.paymentMethod.toLowerCase().replaceAll(' ', '_');
      paymentBreakdown[method] = (paymentBreakdown[method] ?? 0) + amount;
    }

    return {
      'revenue': revenue,
      'profit': profit,
      'tax': tax,
      'count': transactions.length.toDouble(),
      'cash': paymentBreakdown['cash'] ?? 0.0,
      'card': paymentBreakdown['card'] ?? 0.0,
      'mobile_money': paymentBreakdown['mobile_money'] ?? 0.0,
    };
  }

  Future<List<Map<String, dynamic>>> getTopSellingProductsInRange(DateTime start, DateTime end, {int limit = 10}) async {
    final transactions = await getTransactionsInRange(start, end);

    final Map<int, int> productQuantities = {};
    final Map<int, String> productNames = {};

    for (var t in transactions) {
      await t.items.load();
      for (var item in t.items) {
        productQuantities[item.productId] = (productQuantities[item.productId] ?? 0) + item.quantity;
        productNames[item.productId] = item.productName;
      }
    }

    final sortedProducts = productQuantities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sortedProducts.take(limit).map((e) => {
      'productId': e.key,
      'name': productNames[e.key],
      'quantity': e.value,
    }).toList();
  }

  // Comprehensive Backup & Restore Methods
  Future<Map<String, dynamic>> exportBackupData() async {
    final config = await isar.storeConfigs.where().findFirst();
    final users = await isar.users.where().findAll();
    final categories = await isar.categorys.where().findAll();
    final products = await isar.products.where().findAll();
    final customers = await isar.customers.where().findAll();
    final transactions = await isar.saleTransactions.where().findAll();
    final saleItems = await isar.saleItems.where().findAll();
    final logs = await isar.attendanceLogs.where().findAll();

    return {
      'version': 1,
      'app': 'Beleka POS',
      'exportDate': DateTime.now().toIso8601String(),
      'storeConfig': config != null ? {
        'businessName': config.businessName,
        'address': config.address,
        'contactNumber': config.contactNumber,
        'taxId': config.taxId,
        'tpin': config.tpin,
        'sdcId': config.sdcId,
        'mrcNo': config.mrcNo,
        'currencySymbol': config.currencySymbol,
        'terminalName': config.terminalName,
        'logoPath': config.logoPath,
        'primarySector': config.primarySector.name,
        'recoveryCodeHash': config.recoveryCodeHash,
        'taxRate': config.taxRate,
        'loyaltyEnabled': config.loyaltyEnabled,
        'loyaltyEarnRate': config.loyaltyEarnRate,
        'loyaltyRedemptionValue': config.loyaltyRedemptionValue,
        'backupPath': config.backupPath,
        'isManagerMode': config.isManagerMode,
        'serverIp': config.serverIp,
        'port': config.port,
        'defaultPrinterName': config.defaultPrinterName,
        'defaultPrinterAddress': config.defaultPrinterAddress,
        'defaultPrinterType': config.defaultPrinterType,
        'defaultPrinterModel': config.defaultPrinterModel,
        'paperWidthMm': config.paperWidthMm,
        'autoPrintReceipt': config.autoPrintReceipt,
      } : null,
      'users': users.map((u) => {
        'numericId': u.numericId,
        'name': u.name,
        'passwordHash': u.passwordHash,
        'role': u.role,
        'isActive': u.isActive,
      }).toList(),
      'categories': categories.map((c) => {
        'id': c.id,
        'name': c.name,
        'iconPath': c.iconPath,
        'sector': c.sector.name,
      }).toList(),
      'products': products.map((p) => {
        'id': p.id,
        'name': p.name,
        'sku': p.sku,
        'price': p.price,
        'stockLevel': p.stockLevel,
        'categoryId': p.categoryId,
        'unitCost': p.unitCost,
        'sizes': p.sizes,
        'colors': p.colors,
        'imagePath': p.imagePath,
        'isTaxInclusive': p.isTaxInclusive,
        'taxRate': p.taxRate,
        'isArchived': p.isArchived,
        'discountPrice': p.discountPrice,
        'discountStartDate': p.discountStartDate?.toIso8601String(),
        'discountEndDate': p.discountEndDate?.toIso8601String(),
      }).toList(),
      'customers': customers.map((c) => {
        'id': c.id,
        'name': c.name,
        'phoneNumber': c.phoneNumber,
        'email': c.email,
        'accumulatedPoints': c.accumulatedPoints,
        'totalSpend': c.totalSpend,
        'createdAt': c.createdAt?.toIso8601String(),
      }).toList(),
      'saleTransactions': transactions.map((t) => {
        'id': t.id,
        'transactionId': t.transactionId,
        'totalAmount': t.totalAmount,
        'paymentMethod': t.paymentMethod,
        'cashierName': t.cashierName,
        'cashierId': t.cashierId,
        'status': t.status,
        'subtotal': t.subtotal,
        'taxAmount': t.taxAmount,
        'discountAmount': t.discountAmount,
        'totalCost': t.totalCost,
        'grossProfit': t.grossProfit,
        'tenderedAmount': t.tenderedAmount,
        'changeAmount': t.changeAmount,
        'customerId': t.customerId,
        'pointsEarned': t.pointsEarned,
        'pointsRedeemed': t.pointsRedeemed,
        'timestamp': t.timestamp.toIso8601String(),
        'isSynced': t.isSynced,
        'terminalName': t.terminalName,
      }).toList(),
      'saleItems': saleItems.map((si) => {
        'id': si.id,
        'productId': si.productId,
        'productName': si.productName,
        'priceAtSale': si.priceAtSale,
        'unitCostAtSale': si.unitCostAtSale,
        'quantity': si.quantity,
        'isRefunded': si.isRefunded,
        'taxRateAtSale': si.taxRateAtSale,
        'isTaxInclusiveAtSale': si.isTaxInclusiveAtSale,
      }).toList(),
      'attendanceLogs': logs.map((l) => {
        'id': l.id,
        'userId': l.userId,
        'username': l.username,
        'timestamp': l.timestamp.toIso8601String(),
        'type': l.type,
      }).toList(),
    };
  }

  Future<String?> backupDatabase(String targetDirectory) async {
    try {
      final dbFolder = Directory(targetDirectory);
      if (!await dbFolder.exists()) {
        await dbFolder.create(recursive: true);
      }

      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      
      // 1. Save structured JSON snapshot (human-readable & cross-version portable)
      final backupData = await exportBackupData();
      final jsonPath = '${dbFolder.path}/beleka_backup_$timestamp.json';
      final jsonFile = File(jsonPath);
      await jsonFile.writeAsString(const JsonEncoder.withIndent('  ').convert(backupData));

      // 2. Save binary Isar copy
      final isarPath = '${dbFolder.path}/beleka_backup_$timestamp.isar';
      await isar.copyToFile(isarPath);

      // 3. Update last backup date in config
      final config = await isar.storeConfigs.where().findFirst();
      if (config != null) {
        await isar.writeTxn(() async {
          config.lastBackupDate = DateTime.now();
          await isar.storeConfigs.put(config);
        });
      }

      debugPrint('BACKUP_SUCCESS: Database backed up to $jsonPath and $isarPath');
      return jsonPath;
    } catch (e) {
      debugPrint('BACKUP_ERROR: Failed to backup database: $e');
      return null;
    }
  }

  Future<Map<String, int>> restoreFromJsonMap(Map<String, dynamic> data) async {
    final results = <String, int>{
      'users': 0,
      'products': 0,
      'categories': 0,
      'customers': 0,
      'transactions': 0,
    };

    await isar.writeTxn(() async {
      // 1. Restore StoreConfig
      if (data['storeConfig'] != null) {
        final cfg = data['storeConfig'] as Map<String, dynamic>;
        final config = await isar.storeConfigs.where().findFirst() ?? StoreConfig();
        config.businessName = cfg['businessName'] ?? config.businessName;
        config.address = cfg['address'];
        config.contactNumber = cfg['contactNumber'];
        config.taxId = cfg['taxId'];
        config.tpin = cfg['tpin'];
        config.sdcId = cfg['sdcId'];
        config.mrcNo = cfg['mrcNo'];
        config.currencySymbol = cfg['currencySymbol'] ?? 'ZK';
        config.terminalName = cfg['terminalName'] ?? 'POS-01';
        config.logoPath = cfg['logoPath'];
        if (cfg['primarySector'] != null) {
          config.primarySector = CategorySector.values.firstWhere(
            (e) => e.name == cfg['primarySector'],
            orElse: () => CategorySector.other,
          );
        }
        config.recoveryCodeHash = cfg['recoveryCodeHash'];
        config.taxRate = (cfg['taxRate'] as num?)?.toDouble() ?? 16.0;
        config.loyaltyEnabled = cfg['loyaltyEnabled'] ?? false;
        config.loyaltyEarnRate = (cfg['loyaltyEarnRate'] as num?)?.toDouble() ?? 1.0;
        config.loyaltyRedemptionValue = (cfg['loyaltyRedemptionValue'] as num?)?.toDouble() ?? 0.01;
        config.backupPath = cfg['backupPath'];
        config.isManagerMode = cfg['isManagerMode'] ?? true;
        config.serverIp = cfg['serverIp'];
        config.port = cfg['port'] ?? 8080;
        config.defaultPrinterName = cfg['defaultPrinterName'];
        config.defaultPrinterAddress = cfg['defaultPrinterAddress'];
        config.defaultPrinterType = cfg['defaultPrinterType'];
        config.defaultPrinterModel = cfg['defaultPrinterModel'];
        config.paperWidthMm = cfg['paperWidthMm'] ?? 80;
        config.autoPrintReceipt = cfg['autoPrintReceipt'] ?? true;
        config.lastBackupDate = DateTime.now();
        await isar.storeConfigs.put(config);
      }

      // 2. Restore Categories
      if (data['categories'] is List) {
        final categoryList = data['categories'] as List;
        for (final item in categoryList) {
          final cat = Category(
            name: item['name'] ?? 'General',
            iconPath: item['iconPath'] ?? '',
            sector: CategorySector.values.firstWhere(
              (s) => s.name == item['sector'],
              orElse: () => CategorySector.other,
            ),
          );
          if (item['id'] != null) cat.id = item['id'] as int;
          await isar.categorys.put(cat);
          results['categories'] = (results['categories'] ?? 0) + 1;
        }
      }

      // 3. Restore Users
      if (data['users'] is List) {
        final userList = data['users'] as List;
        for (final item in userList) {
          final user = User()
            ..numericId = item['numericId']?.toString() ?? '1001'
            ..name = item['name'] ?? 'Staff'
            ..passwordHash = item['passwordHash'] ?? ''
            ..role = item['role'] ?? 'cashier'
            ..isActive = item['isActive'] ?? true;
          await isar.users.put(user);
          results['users'] = (results['users'] ?? 0) + 1;
        }
      }

      // 4. Restore Products
      if (data['products'] is List) {
        final productList = data['products'] as List;
        for (final item in productList) {
          final product = Product(
            name: item['name'] ?? '',
            sku: item['sku'] ?? '',
            price: (item['price'] as num?)?.toDouble() ?? 0.0,
            stockLevel: (item['stockLevel'] as num?)?.toInt() ?? 0,
            categoryId: (item['categoryId'] as num?)?.toInt() ?? 1,
            unitCost: (item['unitCost'] as num?)?.toDouble() ?? 0.0,
            sizes: (item['sizes'] as List?)?.map((e) => e.toString()).toList(),
            colors: (item['colors'] as List?)?.map((e) => e.toString()).toList(),
            imagePath: item['imagePath'],
            isTaxInclusive: item['isTaxInclusive'] ?? true,
            taxRate: (item['taxRate'] as num?)?.toDouble() ?? 0.0,
            isArchived: item['isArchived'] ?? false,
            discountPrice: (item['discountPrice'] as num?)?.toDouble(),
            discountStartDate: item['discountStartDate'] != null ? DateTime.tryParse(item['discountStartDate']) : null,
            discountEndDate: item['discountEndDate'] != null ? DateTime.tryParse(item['discountEndDate']) : null,
          );
          if (item['id'] != null) product.id = item['id'] as int;
          await isar.products.put(product);
          results['products'] = (results['products'] ?? 0) + 1;
        }
      }

      // 5. Restore Customers
      if (data['customers'] is List) {
        final customerList = data['customers'] as List;
        for (final item in customerList) {
          final customer = Customer(
            name: item['name'] ?? '',
            phoneNumber: item['phoneNumber'] ?? '',
            email: item['email'],
            accumulatedPoints: (item['accumulatedPoints'] as num?)?.toInt() ?? 0,
            totalSpend: (item['totalSpend'] as num?)?.toDouble() ?? 0.0,
            createdAt: item['createdAt'] != null ? DateTime.tryParse(item['createdAt']) : null,
          );
          if (item['id'] != null) customer.id = item['id'] as int;
          await isar.customers.put(customer);
          results['customers'] = (results['customers'] ?? 0) + 1;
        }
      }

      // 6. Restore SaleItems & Transactions
      if (data['saleItems'] is List) {
        final itemsList = data['saleItems'] as List;
        for (final item in itemsList) {
          final saleItem = SaleItem(
            productId: (item['productId'] as num?)?.toInt() ?? 0,
            productName: item['productName'] ?? '',
            priceAtSale: (item['priceAtSale'] as num?)?.toDouble() ?? 0.0,
            unitCostAtSale: (item['unitCostAtSale'] as num?)?.toDouble() ?? 0.0,
            quantity: (item['quantity'] as num?)?.toInt() ?? 1,
            isRefunded: item['isRefunded'] ?? false,
            taxRateAtSale: (item['taxRateAtSale'] as num?)?.toDouble() ?? 0.0,
            isTaxInclusiveAtSale: item['isTaxInclusiveAtSale'] ?? true,
          );
          if (item['id'] != null) saleItem.id = item['id'] as int;
          await isar.saleItems.put(saleItem);
        }
      }

      if (data['saleTransactions'] is List) {
        final txList = data['saleTransactions'] as List;
        for (final item in txList) {
          final tx = SaleTransaction(
            totalAmount: (item['totalAmount'] as num?)?.toDouble() ?? 0.0,
            paymentMethod: item['paymentMethod'] ?? 'Cash',
            cashierName: item['cashierName'] ?? '',
            cashierId: item['cashierId'],
            status: item['status'] ?? 'completed',
            subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0.0,
            taxAmount: (item['taxAmount'] as num?)?.toDouble() ?? 0.0,
            discountAmount: (item['discountAmount'] as num?)?.toDouble() ?? 0.0,
            totalCost: (item['totalCost'] as num?)?.toDouble() ?? 0.0,
            grossProfit: (item['grossProfit'] as num?)?.toDouble() ?? 0.0,
            tenderedAmount: (item['tenderedAmount'] as num?)?.toDouble() ?? 0.0,
            changeAmount: (item['changeAmount'] as num?)?.toDouble() ?? 0.0,
            customerId: (item['customerId'] as num?)?.toInt(),
            pointsEarned: (item['pointsEarned'] as num?)?.toInt() ?? 0,
            pointsRedeemed: (item['pointsRedeemed'] as num?)?.toInt() ?? 0,
            isSynced: item['isSynced'] ?? false,
            terminalName: item['terminalName'],
            transactionId: item['transactionId'],
          );
          if (item['id'] != null) tx.id = item['id'] as int;
          if (item['timestamp'] != null) {
            tx.timestamp = DateTime.tryParse(item['timestamp']) ?? DateTime.now();
          }
          await isar.saleTransactions.put(tx);
          results['transactions'] = (results['transactions'] ?? 0) + 1;
        }
      }

      // 7. Restore Attendance Logs
      if (data['attendanceLogs'] is List) {
        final logsList = data['attendanceLogs'] as List;
        for (final item in logsList) {
          final log = AttendanceLog()
            ..userId = (item['userId'] as num?)?.toInt() ?? 0
            ..username = item['username'] ?? ''
            ..type = item['type'] ?? 'clock_in'
            ..timestamp = item['timestamp'] != null ? (DateTime.tryParse(item['timestamp']) ?? DateTime.now()) : DateTime.now();
          if (item['id'] != null) log.id = item['id'] as int;
          await isar.attendanceLogs.put(log);
        }
      }
    });

    return results;
  }

  Future<Map<String, int>> restoreFromFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('Backup file not found at: $filePath');
    }

    if (filePath.endsWith('.json')) {
      final jsonString = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(jsonString);
      return await restoreFromJsonMap(data);
    } else {
      throw Exception('Unsupported backup format. Please select a .json backup file.');
    }
  }

  Future<List<File>> listRecentBackups({String? customPath}) async {
    final List<File> backups = [];
    final pathsToScan = <String>[];
    
    if (customPath != null && customPath.isNotEmpty) {
      pathsToScan.add(customPath);
    }
    
    final config = await isar.storeConfigs.where().findFirst();
    if (config?.backupPath != null && config!.backupPath!.isNotEmpty) {
      pathsToScan.add(config.backupPath!);
    }

    for (final path in pathsToScan) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) {
          final files = dir.listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.json') || f.path.endsWith('.isar'))
            .toList();
          backups.addAll(files);
        }
      } catch (e) {
        debugPrint('Scan backup folder notice: $e');
      }
    }

    // Sort newest first
    backups.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return backups;
  }
}
