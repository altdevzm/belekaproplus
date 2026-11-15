import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';

final restaurantServiceProvider = Provider<RestaurantService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return RestaurantService(db);
});

class RestaurantService {
  RestaurantService(this._db);

  final DatabaseService _db;
  Isar get isar => _db.isar;

  Future<String> getActiveBranchCode() async {
    final config = await _db.getStoreConfig();
    final code = config?.bhfId.trim() ?? '';
    return code.isEmpty ? '00' : code;
  }

  // ---------------------------------------------------------------------------
  // Kitchen Stations
  // ---------------------------------------------------------------------------

  Future<List<KitchenStation>> getStations(String branchCode) async {
    return isar.kitchenStations
        .filter()
        .branchCodeEqualTo(branchCode)
        .findAll();
  }

  Stream<List<KitchenStation>> watchStations(String branchCode) {
    return isar.kitchenStations
        .filter()
        .branchCodeEqualTo(branchCode)
        .watch(fireImmediately: true);
  }

  Future<void> ensureDefaultStations(String branchCode) async {
    final existing = await getStations(branchCode);
    if (existing.isNotEmpty) {
      return;
    }
    final defaults = [
      KitchenStation(name: 'Main Kitchen', branchCode: branchCode),
      KitchenStation(name: 'Bar / Drinks', branchCode: branchCode),
    ];
    await isar.writeTxn(() async {
      await isar.kitchenStations.putAll(defaults);
    });
  }

  // ---------------------------------------------------------------------------
  // Tables & Sessions
  // ---------------------------------------------------------------------------

  Stream<List<RestaurantTable>> watchTables(String branchCode) {
    return isar.restaurantTables
        .filter()
        .branchCodeEqualTo(branchCode)
        .sortByName()
        .watch(fireImmediately: true);
  }

  Future<List<RestaurantTable>> getTables(String branchCode) async {
    return isar.restaurantTables
        .filter()
        .branchCodeEqualTo(branchCode)
        .sortByName()
        .findAll();
  }

  Future<void> saveTable(RestaurantTable table) async {
    table.updatedAt = DateTime.now();
    await isar.writeTxn(() async {
      await isar.restaurantTables.put(table);
    });
  }

  Future<bool> deleteTable(int isarId) async {
    final table = await isar.restaurantTables.get(isarId);
    if (table == null) {
      return false;
    }
    if (table.activeOrderId != null) {
      return false;
    }
    await isar.writeTxn(() async {
      await isar.restaurantTables.delete(isarId);
    });
    return true;
  }

  /// Opens a table session or returns the already-active order (prevents duplicate sessions).
  Future<RestaurantOrder> openTableSession({
    required RestaurantTable table,
    int? waiterId,
    required String waiterName,
  }) async {
    if (table.activeOrderId != null) {
      final existing = await isar.restaurantOrders.get(table.activeOrderId!);
      if (existing != null &&
          existing.status != RestaurantOrderStatus.paid &&
          existing.status != RestaurantOrderStatus.cancelled) {
        return existing;
      }
    }

    final now = DateTime.now();
    final orderNumber =
        'T-${table.name.replaceAll(' ', '')}-${now.millisecondsSinceEpoch % 100000}';

    final order = RestaurantOrder(
      orderNumber: orderNumber,
      serviceType: RestaurantServiceType.table,
      branchCode: table.branchCode,
      tableId: table.id,
      tableName: table.name,
      sessionId: 'SES-${now.millisecondsSinceEpoch}',
      waiterId: waiterId,
      waiterName: waiterName,
      status: RestaurantOrderStatus.draft,
    );

    await isar.writeTxn(() async {
      final orderId = await isar.restaurantOrders.put(order);
      order.id = orderId;
      table.status = RestaurantTableStatus.occupied;
      table.activeOrderId = orderId;
      table.activeSessionId = order.sessionId;
      table.assignedWaiterId = waiterId;
      table.assignedWaiterName = waiterName;
      table.updatedAt = now;
      await isar.restaurantTables.put(table);
    });

    return order;
  }

  Future<void> assignWaiterToTable({
    required RestaurantTable table,
    int? waiterId,
    required String waiterName,
  }) async {
    await isar.writeTxn(() async {
      table.assignedWaiterId = waiterId;
      table.assignedWaiterName = waiterName;
      table.updatedAt = DateTime.now();
      await isar.restaurantTables.put(table);
      if (table.activeOrderId != null) {
        final order = await isar.restaurantOrders.get(table.activeOrderId!);
        if (order != null) {
          order.waiterId = waiterId;
          order.waiterName = waiterName;
          order.updatedAt = DateTime.now();
          await isar.restaurantOrders.put(order);
        }
      }
    });
  }

  Future<String?> transferTable({
    required int fromTableId,
    required int toTableId,
  }) async {
    if (fromTableId == toTableId) {
      return 'Source and target tables must be different.';
    }
    final fromTable = await isar.restaurantTables.get(fromTableId);
    final toTable = await isar.restaurantTables.get(toTableId);
    if (fromTable == null || toTable == null) {
      return 'Table not found.';
    }
    if (fromTable.activeOrderId == null) {
      return 'Source table has no active session.';
    }
    if (toTable.activeOrderId != null) {
      return 'Target table already has an active session. Use Merge instead.';
    }

    final order = await isar.restaurantOrders.get(fromTable.activeOrderId!);
    if (order == null) {
      return 'Active order not found.';
    }

    final now = DateTime.now();
    await isar.writeTxn(() async {
      toTable.status = fromTable.status;
      toTable.activeOrderId = fromTable.activeOrderId;
      toTable.activeSessionId = fromTable.activeSessionId;
      toTable.assignedWaiterId = fromTable.assignedWaiterId;
      toTable.assignedWaiterName = fromTable.assignedWaiterName;
      toTable.updatedAt = now;

      fromTable.status = RestaurantTableStatus.available;
      fromTable.activeOrderId = null;
      fromTable.activeSessionId = null;
      fromTable.assignedWaiterId = null;
      fromTable.assignedWaiterName = null;
      fromTable.updatedAt = now;

      order.tableId = toTable.id;
      order.tableName = toTable.name;
      order.updatedAt = now;

      await isar.restaurantTables.putAll([fromTable, toTable]);
      await isar.restaurantOrders.put(order);
    });
    return null;
  }

  Future<String?> mergeTables({
    required int sourceTableId,
    required int targetTableId,
  }) async {
    if (sourceTableId == targetTableId) {
      return 'Source and target tables must be different.';
    }
    final sourceTable = await isar.restaurantTables.get(sourceTableId);
    final targetTable = await isar.restaurantTables.get(targetTableId);
    if (sourceTable == null || targetTable == null) {
      return 'Table not found.';
    }
    if (sourceTable.activeOrderId == null ||
        targetTable.activeOrderId == null) {
      return 'Both tables must have active sessions to merge.';
    }

    final sourceOrder = await isar.restaurantOrders.get(
      sourceTable.activeOrderId!,
    );
    final targetOrder = await isar.restaurantOrders.get(
      targetTable.activeOrderId!,
    );
    if (sourceOrder == null || targetOrder == null) {
      return 'Active order not found.';
    }

    final sourceItems = await isar.restaurantOrderItems
        .filter()
        .orderIdEqualTo(sourceOrder.id)
        .findAll();

    final now = DateTime.now();
    await isar.writeTxn(() async {
      for (final item in sourceItems) {
        item.orderId = targetOrder.id;
        await isar.restaurantOrderItems.put(item);
      }

      targetOrder.updatedAt = now;
      sourceOrder.status = RestaurantOrderStatus.cancelled;
      sourceOrder.notes =
          'Merged into ${targetTable.name} (${targetOrder.orderNumber})';
      sourceOrder.settledAt = now;
      sourceOrder.updatedAt = now;

      sourceTable.status = RestaurantTableStatus.available;
      sourceTable.activeOrderId = null;
      sourceTable.activeSessionId = null;
      sourceTable.assignedWaiterId = null;
      sourceTable.assignedWaiterName = null;
      sourceTable.updatedAt = now;

      await isar.restaurantOrders.putAll([sourceOrder, targetOrder]);
      await isar.restaurantTables.put(sourceTable);
    });

    await recalculateOrderTotals(targetOrder.id);
    return null;
  }

  Future<void> closeTableSession(int tableId) async {
    final table = await isar.restaurantTables.get(tableId);
    if (table == null) {
      return;
    }
    await isar.writeTxn(() async {
      table.status = RestaurantTableStatus.available;
      table.activeOrderId = null;
      table.activeSessionId = null;
      table.assignedWaiterId = null;
      table.assignedWaiterName = null;
      table.updatedAt = DateTime.now();
      await isar.restaurantTables.put(table);
    });
  }

  // ---------------------------------------------------------------------------
  // Orders & Items
  // ---------------------------------------------------------------------------

  Future<RestaurantOrder> createCounterOrder({
    required String branchCode,
    int? waiterId,
    required String waiterName,
    String? customerName,
  }) async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayCount = await isar.restaurantOrders
        .filter()
        .branchCodeEqualTo(branchCode)
        .serviceTypeEqualTo(RestaurantServiceType.counter)
        .createdAtGreaterThan(todayStart, include: true)
        .count();

    int seq = todayCount + 1;
    String orderNumber = '#${seq.toString().padLeft(3, '0')}';
    while (await isar.restaurantOrders
            .filter()
            .orderNumberEqualTo(orderNumber)
            .findFirst() !=
        null) {
      seq++;
      orderNumber = '#${seq.toString().padLeft(3, '0')}';
    }

    final order = RestaurantOrder(
      orderNumber: orderNumber,
      serviceType: RestaurantServiceType.counter,
      branchCode: branchCode,
      waiterId: waiterId,
      waiterName: waiterName,
      customerName: customerName,
      status: RestaurantOrderStatus.draft,
    );

    await isar.writeTxn(() async {
      final id = await isar.restaurantOrders.put(order);
      order.id = id;
    });
    return order;
  }

  Stream<List<RestaurantOrder>> watchActiveOrders(String branchCode) {
    return isar.restaurantOrders
        .filter()
        .branchCodeEqualTo(branchCode)
        .not()
        .statusEqualTo(RestaurantOrderStatus.paid)
        .and()
        .not()
        .statusEqualTo(RestaurantOrderStatus.cancelled)
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<RestaurantOrder>> watchAllOrders(String branchCode) {
    return isar.restaurantOrders
        .filter()
        .branchCodeEqualTo(branchCode)
        .sortByCreatedAtDesc()
        .watch(fireImmediately: true);
  }

  Stream<List<RestaurantOrderItem>> watchOrderItems(int orderId) {
    return isar.restaurantOrderItems
        .filter()
        .orderIdEqualTo(orderId)
        .watch(fireImmediately: true);
  }

  Future<List<RestaurantOrderItem>> getOrderItems(int orderId) {
    return isar.restaurantOrderItems.filter().orderIdEqualTo(orderId).findAll();
  }

  Future<void> addOrderItem({
    required int orderId,
    required Product product,
    int quantity = 1,
    double modifiersPrice = 0.0,
    String? modifiersJson,
    String? specialInstructions,
  }) async {
    final branchCode = await getActiveBranchCode();
    final station = product.kitchenStationId != null
        ? await isar.kitchenStations.get(product.kitchenStationId!)
        : null;
    final unitPrice = product.price + modifiersPrice;
    final item = RestaurantOrderItem(
      orderId: orderId,
      productId: product.id,
      productName: product.name,
      productSku: product.sku,
      basePrice: product.price,
      modifiersPrice: modifiersPrice,
      unitPrice: unitPrice,
      quantity: quantity,
      taxRate: product.taxRate,
      isTaxInclusive: product.isTaxInclusive,
      kitchenStationId: product.kitchenStationId,
      kitchenStationName: station?.name,
      modifiersJson: modifiersJson,
      specialInstructions:
          (specialInstructions != null &&
              specialInstructions.trim().isNotEmpty)
          ? specialInstructions.trim()
          : null,
      branchCode: branchCode,
    );

    await isar.writeTxn(() async {
      await isar.restaurantOrderItems.put(item);
    });
    await recalculateOrderTotals(orderId);
  }

  Future<bool> removeOrderItem(int itemId) async {
    final item = await isar.restaurantOrderItems.get(itemId);
    if (item == null) {
      return false;
    }
    final orderId = item.orderId;
    await isar.writeTxn(() async {
      await isar.restaurantOrderItems.delete(itemId);
    });
    await recalculateOrderTotals(orderId);
    return true;
  }

  Future<void> recalculateOrderTotals(int orderId) async {
    final order = await isar.restaurantOrders.get(orderId);
    if (order == null) {
      return;
    }
    final items = await getOrderItems(orderId);
    final config = await _db.getStoreConfig();

    double subtotal = 0;
    for (final item in items) {
      if (item.kitchenStatus != KitchenItemStatus.cancelled) {
        subtotal += item.unitPrice * item.quantity;
      }
    }

    final taxRate = config?.taxRate ?? 16.0;
    final taxAmount = taxRate > 0
        ? subtotal - (subtotal / (1 + (taxRate / 100)))
        : 0.0;
    final serviceChargeRate = (config?.serviceChargeEnabled == true &&
            order.serviceType == RestaurantServiceType.table)
        ? (config?.defaultServiceChargeRate ?? 0.0)
        : 0.0;
    final serviceChargeAmount = subtotal * (serviceChargeRate / 100.0);
    final totalAmount = subtotal + serviceChargeAmount;

    await isar.writeTxn(() async {
      order.subtotal = subtotal;
      order.taxAmount = taxAmount;
      order.serviceChargeAmount = serviceChargeAmount;
      order.totalAmount = totalAmount;
      order.updatedAt = DateTime.now();
      await isar.restaurantOrders.put(order);
    });
  }

  Future<void> setOrderServiceCharge(
    int orderId,
    bool enabled, {
    double? customAmount,
  }) async {
    final order = await isar.restaurantOrders.get(orderId);
    if (order == null) return;
    final double charge;
    if (customAmount != null) {
      charge = customAmount > 0 ? customAmount : 0.0;
    } else {
      final config = await _db.getStoreConfig();
      final rate = (config?.defaultServiceChargeRate ?? 0.0) > 0
          ? config!.defaultServiceChargeRate
          : 10.0;
      charge = enabled ? order.subtotal * (rate / 100.0) : 0.0;
    }
    await isar.writeTxn(() async {
      order.serviceChargeAmount = charge;
      order.totalAmount = order.subtotal + charge;
      order.updatedAt = DateTime.now();
      await isar.restaurantOrders.put(order);
    });
  }

  Future<void> submitOrderToKitchen(int orderId) async {
    final order = await isar.restaurantOrders.get(orderId);
    if (order == null) {
      return;
    }
    final items = await getOrderItems(orderId);
    final now = DateTime.now();

    await isar.writeTxn(() async {
      for (final item in items) {
        if (item.ticketNumber == null) {
          item.ticketNumber =
              'KOT-${order.orderNumber}-${now.millisecondsSinceEpoch % 1000}';
          await isar.restaurantOrderItems.put(item);
        }
      }
      if (order.status == RestaurantOrderStatus.draft) {
        order.status = RestaurantOrderStatus.submitted;
        order.submittedAt = now;
      }
      order.updatedAt = now;
      await isar.restaurantOrders.put(order);

      if (order.tableId != null) {
        final table = await isar.restaurantTables.get(order.tableId!);
        if (table != null) {
          table.status = RestaurantTableStatus.ordering;
          table.updatedAt = now;
          await isar.restaurantTables.put(table);
        }
      }
    });
  }

  Future<void> updateKitchenItemStatus({
    required int itemId,
    required KitchenItemStatus nextStatus,
  }) async {
    final item = await isar.restaurantOrderItems.get(itemId);
    if (item == null) {
      return;
    }
    final now = DateTime.now();
    await isar.writeTxn(() async {
      item.kitchenStatus = nextStatus;
      if (nextStatus == KitchenItemStatus.accepted && item.acceptedAt == null) {
        item.acceptedAt = now;
      } else if (nextStatus == KitchenItemStatus.preparing &&
          item.preparingAt == null) {
        item.preparingAt = now;
      } else if (nextStatus == KitchenItemStatus.ready) {
        item.readyAt = now;
      } else if (nextStatus == KitchenItemStatus.served) {
        item.servedAt = now;
      }
      await isar.restaurantOrderItems.put(item);
    });

    await _rollupOrderStatusFromItems(item.orderId);
  }

  Future<void> _rollupOrderStatusFromItems(int orderId) async {
    final order = await isar.restaurantOrders.get(orderId);
    if (order == null ||
        order.status == RestaurantOrderStatus.paid ||
        order.status == RestaurantOrderStatus.cancelled ||
        order.status == RestaurantOrderStatus.awaitingPayment) {
      return;
    }

    final items = (await getOrderItems(orderId))
        .where((i) => i.kitchenStatus != KitchenItemStatus.cancelled)
        .toList();
    if (items.isEmpty) {
      return;
    }

    final allServed = items.every(
      (i) => i.kitchenStatus == KitchenItemStatus.served,
    );
    final allReadyOrServed = items.every(
      (i) =>
          i.kitchenStatus == KitchenItemStatus.ready ||
          i.kitchenStatus == KitchenItemStatus.served,
    );
    final anyReady = items.any(
      (i) => i.kitchenStatus == KitchenItemStatus.ready,
    );
    final anyPreparing = items.any(
      (i) =>
          i.kitchenStatus == KitchenItemStatus.preparing ||
          i.kitchenStatus == KitchenItemStatus.accepted,
    );

    RestaurantOrderStatus nextOrderStatus = order.status;
    if (allServed) {
      nextOrderStatus = RestaurantOrderStatus.served;
    } else if (allReadyOrServed) {
      nextOrderStatus = RestaurantOrderStatus.ready;
    } else if (anyReady) {
      nextOrderStatus = RestaurantOrderStatus.partiallyReady;
    } else if (anyPreparing) {
      nextOrderStatus = RestaurantOrderStatus.inPreparation;
    }

    final now = DateTime.now();
    await isar.writeTxn(() async {
      order.status = nextOrderStatus;
      order.updatedAt = now;
      await isar.restaurantOrders.put(order);

      if (order.tableId != null &&
          nextOrderStatus == RestaurantOrderStatus.served) {
        final table = await isar.restaurantTables.get(order.tableId!);
        if (table != null) {
          table.status = RestaurantTableStatus.served;
          table.updatedAt = now;
          await isar.restaurantTables.put(table);
        }
      }
    });
  }

  Future<void> requestBill(int orderId) async {
    final order = await isar.restaurantOrders.get(orderId);
    if (order == null) {
      return;
    }
    final now = DateTime.now();
    await isar.writeTxn(() async {
      order.status = RestaurantOrderStatus.awaitingPayment;
      order.updatedAt = now;
      await isar.restaurantOrders.put(order);

      if (order.tableId != null) {
        final table = await isar.restaurantTables.get(order.tableId!);
        if (table != null) {
          table.status = RestaurantTableStatus.billing;
          table.updatedAt = now;
          await isar.restaurantTables.put(table);
        }
      }
    });
  }

  Future<void> recordPaymentAndSettle({
    required int orderId,
    required double paidAmount,
    required int saleTransactionId,
    bool forceFullSettlement = false,
  }) async {
    final order = await isar.restaurantOrders.get(orderId);
    if (order == null) {
      return;
    }
    final now = DateTime.now();
    final newPaid = order.paidAmount + paidAmount;
    final settled = forceFullSettlement || newPaid >= order.totalAmount - 0.01;

    await isar.writeTxn(() async {
      order.paidAmount = newPaid;
      order.saleTransactionId = saleTransactionId;
      if (settled) {
        order.status = RestaurantOrderStatus.paid;
        order.settledAt = now;
      }
      order.updatedAt = now;
      await isar.restaurantOrders.put(order);
    });

    if (settled && order.tableId != null) {
      await closeTableSession(order.tableId!);
    }
  }

  Future<void> cancelOrder(int orderId, {String? reason}) async {
    final order = await isar.restaurantOrders.get(orderId);
    if (order == null) {
      return;
    }
    final now = DateTime.now();
    await isar.writeTxn(() async {
      order.status = RestaurantOrderStatus.cancelled;
      if (reason != null && reason.isNotEmpty) {
        order.notes = reason;
      }
      order.settledAt = now;
      order.updatedAt = now;
      await isar.restaurantOrders.put(order);
    });
    if (order.tableId != null) {
      await closeTableSession(order.tableId!);
    }
  }

  // ---------------------------------------------------------------------------
  // Modifiers & Recipes
  // ---------------------------------------------------------------------------

  Future<List<ProductModifierGroup>> getModifiersForProduct(
    int productId,
  ) async {
    return isar.productModifierGroups
        .filter()
        .productIdEqualTo(productId)
        .findAll();
  }

  Future<void> saveModifierGroup(ProductModifierGroup group) async {
    await isar.writeTxn(() async {
      await isar.productModifierGroups.put(group);
    });
  }

  Future<void> deleteModifierGroup(int id) async {
    await isar.writeTxn(() async {
      await isar.productModifierGroups.delete(id);
    });
  }

  Stream<List<KitchenIngredient>> watchKitchenIngredients() async* {
    final code = await getActiveBranchCode();
    yield* isar.kitchenIngredients
        .filter()
        .branchCodeEqualTo(code)
        .watch(fireImmediately: true);
  }

  Future<List<KitchenIngredient>> getKitchenIngredients() async {
    final code = await getActiveBranchCode();
    return isar.kitchenIngredients.filter().branchCodeEqualTo(code).findAll();
  }

  Future<void> saveKitchenIngredient(KitchenIngredient ingredient) async {
    ingredient.branchCode = await getActiveBranchCode();
    await isar.writeTxn(() async {
      await isar.kitchenIngredients.put(ingredient);
    });
  }

  Future<void> deleteKitchenIngredient(int id) async {
    await isar.writeTxn(() async {
      await isar.kitchenIngredients.delete(id);
    });
  }

  Future<List<RecipeIngredient>> getRecipeForProduct(int productId) async {
    return isar.recipeIngredients
        .filter()
        .productIdEqualTo(productId)
        .findAll();
  }

  Future<void> saveRecipeIngredients(
    int productId,
    List<RecipeIngredient> ingredients, {
    bool updateProductPricing = false,
    double? sellingPriceOverride,
  }) async {
    await isar.writeTxn(() async {
      await isar.recipeIngredients
          .filter()
          .productIdEqualTo(productId)
          .deleteAll();
      if (ingredients.isNotEmpty) {
        await isar.recipeIngredients.putAll(ingredients);
      }
      if (updateProductPricing) {
        final product = await isar.products.get(productId);
        if (product != null) {
          final totalCost = ingredients.fold<double>(
            0.0,
            (sum, ing) => sum + (ing.quantityRequired * ing.unitCost),
          );
          final totalPrice = ingredients.fold<double>(
            0.0,
            (sum, ing) => sum + (ing.quantityRequired * ing.unitPrice),
          );
          product.unitCost = totalCost;
          product.price = sellingPriceOverride ?? totalPrice;
          product.useRecipeStockDeduction = ingredients.isNotEmpty;
          await isar.products.put(product);
        }
      }
    });
  }

  Future<void> deductKitchenIngredientsForOrder(
    List<RestaurantOrderItem> items,
  ) async {
    if (items.isEmpty) return;
    await isar.writeTxn(() async {
      for (final item in items) {
        final recipe = await isar.recipeIngredients
            .filter()
            .productIdEqualTo(item.productId)
            .findAll();
        for (final line in recipe) {
          final ing = await isar.kitchenIngredients.get(
            line.ingredientProductId,
          );
          if (ing != null) {
            ing.stockQuantity =
                (ing.stockQuantity - (line.quantityRequired * item.quantity))
                    .clamp(0.0, double.infinity);
            await isar.kitchenIngredients.put(ing);
          }
        }
      }
    });
  }

  static List<Map<String, dynamic>> decodeModifiers(String? jsonStr) {
    if (jsonStr == null || jsonStr.trim().isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }
}
