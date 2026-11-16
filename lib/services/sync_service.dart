import 'dart:async';

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/network_client.dart';

/// Manages data synchronization between a Cashier terminal and the Manager server.
///
/// For Cashier terminals (Terminal Mode):
/// - Periodically pulls Latest Products and Categories.
/// - Pushes completed transactions in real-time or batch (if offline).
/// - Sends heartbeats to keep the session alive on the Manager dashboard.
class SyncService {
  final Isar _isar;
  final NetworkClient? _client;
  Timer? _retryTimer;
  Timer? _metadataTimer;
  bool _isSyncingMetadata = false;
  bool _isSyncingRestaurant = false;

  SyncService(this._isar, this._client);

  /// Number of transactions waiting to be synced.
  Future<int> get pendingCount async {
    return await _isar.saleTransactions.filter().isSyncedEqualTo(false).count();
  }

  /// Start the background sync loops.
  void startSyncLoops(String terminalName, {String? cashierId, String? cashierName}) {
    stopSyncLoops();

    // 1. Transaction retry, store-mode, fiscal updates & restaurant state sync loop (every 15s)
    _retryTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      syncPendingTransactions();
      syncStoreModeFromServer();
      syncFiscalUpdatesOnly();
      syncRestaurantState();
    });

    // 2. Metadata pull loop (every 60s)
    _metadataTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      syncMetadata();
    });

    // 3. Start heartbeat in client
    _client?.startBackgroundTasks(
      terminalName,
      cashierId: cashierId,
      cashierName: cashierName,
    );

    // Initial sync
    syncPendingTransactions();
    syncMetadata();
  }

  /// Stop all background loops.
  void stopSyncLoops() {
    _retryTimer?.cancel();
    _metadataTimer?.cancel();
    _retryTimer = null;
    _metadataTimer = null;
    _client?.stopBackgroundTasks();
  }

  /// Attempt to push a single transaction to the server right after sale.
  /// Returns true if successfully synced, false if queued for later.
  Future<bool> trySyncTransaction(
    SaleTransaction transaction,
    List<SaleItem> items,
  ) async {
    if (_client == null) return false;

    try {
      final response = await _client.pushTransaction(transaction, items);
      if (response != null && response['success'] == true) {
        transaction.isSynced = true;
        final dSaleId = response['digitaxSaleId'] as String?;
        if (dSaleId != null && dSaleId.isNotEmpty) {
          transaction.digitaxSaleId = dSaleId;
        }
        final respStatus = (response['zraStatus'] as String?) ?? '';
        final rcpt = response['zraReceiptNumber'] as String?;
        final mark = response['zraMarkId'] as String?;
        final qr = response['zraQrCode'] as String?;
        final isConfirmed = respStatus.toUpperCase() == 'APPROVED' &&
            rcpt != null &&
            rcpt.isNotEmpty &&
            rcpt != 'PENDING' &&
            mark != null &&
            mark.isNotEmpty &&
            !mark.startsWith('sale_') &&
            qr != null &&
            qr.isNotEmpty &&
            qr != 'PENDING';
        if (isConfirmed) {
          transaction.zraReceiptNumber = rcpt;
          transaction.zraMarkId = mark;
          transaction.zraQrCode = qr;
          transaction.zraInternalData = response['zraInternalData'] as String?;
          transaction.zraSdcId = response['zraSdcId'] as String?;
          transaction.zraInvoiceType = response['zraInvoiceType'] as String?;
          transaction.zraStatus = 'APPROVED';
        } else {
          if (respStatus.isNotEmpty) {
            transaction.zraStatus = respStatus;
          }
          final sdc = response['zraSdcId'] as String?;
          if (sdc != null && sdc.isNotEmpty && sdc != 'PENDING') {
            transaction.zraSdcId = sdc;
          }
        }
        if (transaction.id > 0 && transaction.id != Isar.autoIncrement) {
          await _isar.writeTxn(() async {
            await _isar.saleTransactions.put(transaction);
          });
        }
        debugPrint(
          'SYNC: Transaction ${transaction.id} synced immediately (Fiscal: ${transaction.zraStatus})',
        );
        return true;
      }
    } catch (e) {
      debugPrint('SYNC_IMMEDIATE_FAIL: $e');
    }
    return false;
  }

  /// Push all pending (un-synced) transactions to the Manager server.
  Future<int> syncPendingTransactions() async {
    if (_client == null) return 0;

    final pending = await _isar.saleTransactions
        .filter()
        .isSyncedEqualTo(false)
        .findAll();

    if (pending.isEmpty) return 0;

    debugPrint('SYNC: Found ${pending.length} pending transactions');

    // Build the batch payload
    final batch = <Map<String, dynamic>>[];
    final itemsMap = <int, List<SaleItem>>{};

    for (final tx in pending) {
      await tx.items.load();
      final items = tx.items.toList();
      itemsMap[tx.id] = items;

      batch.add({
        'transaction': {
          'totalAmount': tx.totalAmount,
          'paymentMethod': tx.paymentMethod,
          'cashierName': tx.cashierName,
          'status': tx.status,
          'subtotal': tx.subtotal,
          'taxAmount': tx.taxAmount,
          'discountAmount': tx.discountAmount,
          'totalCost': tx.totalCost,
          'grossProfit': tx.grossProfit,
          'tenderedAmount': tx.tenderedAmount,
          'changeAmount': tx.changeAmount,
          'cashierId': tx.cashierId,
          'terminalName': tx.terminalName,
          'cashShiftNumber': tx.cashShiftNumber,
          'externalPaymentReference': tx.externalPaymentReference,
          'externalPaymentConfirmedBy': tx.externalPaymentConfirmedBy,
          'externalPaymentConfirmedAt': tx.externalPaymentConfirmedAt
              ?.toIso8601String(),
          'transactionId': tx.transactionId,
          'customerTpin': tx.customerTpin,
          'customerBusinessName': tx.customerBusinessName,
          'customerAddress': tx.customerAddress,
          'zraSdcId': tx.zraSdcId,
          'zraReceiptNumber': tx.zraReceiptNumber,
          'zraMarkId': tx.zraMarkId,
          'zraInternalData': tx.zraInternalData,
          'zraQrCode': tx.zraQrCode,
          'zraInvoiceType': tx.zraInvoiceType,
          'zraStatus': tx.zraStatus,
          'orgInvoiceNo': tx.orgInvoiceNo,
          'isCreditNote': tx.isCreditNote,
          'creditNoteReason': tx.creditNoteReason,
          'timestamp': tx.timestamp.toIso8601String(),
        },
        'items': items
            .map(
              (item) => {
                'productId': item.productId,
                'productName': item.productName,
                'priceAtSale': item.priceAtSale,
                'unitCostAtSale': item.unitCostAtSale,
                'quantity': item.quantity,
                'isRefunded': item.isRefunded,
                'isDigitaxExempt': item.isDigitaxExempt,
                'taxRateAtSale': item.taxRateAtSale,
                'isTaxInclusiveAtSale': item.isTaxInclusiveAtSale,
              },
            )
            .toList(),
      });
    }

    final resp = await _client.pushBatchTransactions(batch);
    int syncedCount = 0;

    if (resp != null && resp['synced'] is int) {
      syncedCount = resp['synced'] as int;
      final fiscalUpdates = resp['fiscalUpdates'] as List<dynamic>?;

      // Mark them as synced locally and apply fiscal updates
      await _isar.writeTxn(() async {
        for (final tx in pending.take(syncedCount)) {
          tx.isSynced = true;

          if (fiscalUpdates != null) {
            for (final upd in fiscalUpdates) {
              if (upd is Map && upd['transactionId'] == tx.transactionId) {
                final updRcpt = upd['zraReceiptNumber'] as String?;
                if (updRcpt != null &&
                    updRcpt.isNotEmpty &&
                    updRcpt != 'PENDING') {
                  tx.zraReceiptNumber = updRcpt;
                  tx.zraMarkId = upd['zraMarkId'] as String?;
                  tx.zraQrCode = upd['zraQrCode'] as String?;
                  tx.zraInternalData = upd['zraInternalData'] as String?;
                  tx.zraSdcId = upd['zraSdcId'] as String?;
                  tx.zraInvoiceType = upd['zraInvoiceType'] as String?;
                  tx.zraStatus = upd['zraStatus'] as String? ?? 'APPROVED';
                }
                break;
              }
            }
          }

          await _isar.saleTransactions.put(tx);
        }
      });
      debugPrint('SYNC_COMPLETE: $syncedCount/${pending.length} synced');
    }

    return syncedCount;
  }

  /// Lightweight poll to keep the Till's businessMode (Retail vs Restaurant)
  /// and DigiTax settings in sync with the Master POS.
  Future<void> syncStoreModeFromServer() async {
    if (_client == null) return;
    try {
      final serverInfo = await _client.getServerInfo();
      if (serverInfo != null) {
        await _applyServerConfig(serverInfo);
      }
    } catch (_) {}
  }

  Future<void> _applyServerConfig(Map<String, dynamic> serverInfo) async {
    final apiKey = serverInfo['digitaxApiKey']?.toString().trim();
    final sdcId = serverInfo['sdcId']?.toString().trim();
    final tpin = serverInfo['tpin']?.toString().trim();
    final taxType = serverInfo['businessTaxType']?.toString().trim();
    final bhfId = serverInfo['bhfId']?.toString().trim();
    final env = serverInfo['digitaxEnvironment']?.toString().trim();
    final businessMode = serverInfo['businessMode']?.toString().trim();
    final tableSvc = serverInfo['restaurantTableServiceEnabled'];
    final counterSvc = serverInfo['restaurantCounterServiceEnabled'];
    final autoKot = serverInfo['restaurantAutoPrintKot'];

    final config =
        await _isar.storeConfigs.where().findFirst() ?? StoreConfig();
    bool configChanged = false;

    if (apiKey != null &&
        apiKey.isNotEmpty &&
        config.digitaxApiKey != apiKey) {
      config.digitaxApiKey = apiKey;
      configChanged = true;
    }
    if (sdcId != null && sdcId.isNotEmpty && config.sdcId != sdcId) {
      config.sdcId = sdcId;
      configChanged = true;
    }
    if (tpin != null && tpin.isNotEmpty && config.tpin != tpin) {
      config.tpin = tpin;
      configChanged = true;
    }
    if (taxType != null &&
        taxType.isNotEmpty &&
        config.businessTaxType != taxType) {
      config.businessTaxType = taxType;
      configChanged = true;
    }
    if (bhfId != null && bhfId.isNotEmpty && config.bhfId != bhfId) {
      config.bhfId = bhfId;
      configChanged = true;
    }
    if (env != null && env.isNotEmpty && config.digitaxEnvironment != env) {
      config.digitaxEnvironment = env;
      configChanged = true;
    }
    if (businessMode != null &&
        businessMode.isNotEmpty &&
        config.businessMode != businessMode) {
      config.businessMode = businessMode;
      configChanged = true;
    }
    if (tableSvc is bool &&
        config.restaurantTableServiceEnabled != tableSvc) {
      config.restaurantTableServiceEnabled = tableSvc;
      configChanged = true;
    }
    if (counterSvc is bool &&
        config.restaurantCounterServiceEnabled != counterSvc) {
      config.restaurantCounterServiceEnabled = counterSvc;
      configChanged = true;
    }
    if (autoKot is bool && config.restaurantAutoPrintKot != autoKot) {
      config.restaurantAutoPrintKot = autoKot;
      configChanged = true;
    }

    if (configChanged) {
      await _isar.writeTxn(() async {
        await _isar.storeConfigs.put(config);
      });
      debugPrint(
        'SYNC: Local StoreConfig synced with Master POS (mode=${config.businessMode})',
      );
    }
  }

  /// Pulls products, categories, store tax config, and transaction fiscal status updates from the Manager server.
  Future<void> syncMetadata() async {
    if (_client == null || _isSyncingMetadata) return;
    _isSyncingMetadata = true;

    try {
      debugPrint('SYNC: Pulling metadata and tax config from manager...');

      // 0. Sync Store Config (including DigiTax API credentials)
      final serverInfo = await _client.getServerInfo();
      if (serverInfo != null) {
        await _applyServerConfig(serverInfo);
      }

      // 1. Sync Categories
      final categories = await _client.fetchCategories();
      if (categories.isNotEmpty) {
        await _isar.writeTxn(() async {
          await _isar.categorys.putAll(categories);
        });
      }

      // 2. Sync Products
      final products = await _client.fetchProducts();
      if (products.isNotEmpty) {
        await _isar.writeTxn(() async {
          await _isar.products.putAll(products);
        });
      }

      // 3. Sync Fiscal Status Updates for local transactions
      final fiscalUpdates = await _client.fetchTransactionFiscalUpdates();
      if (fiscalUpdates.isNotEmpty) {
        await _isar.writeTxn(() async {
          for (final upd in fiscalUpdates) {
            final txId = upd['transactionId'] as String?;
            final rcptNo = upd['zraReceiptNumber'] as String?;
            if (txId != null &&
                rcptNo != null &&
                rcptNo.isNotEmpty &&
                rcptNo != 'PENDING') {
              final tx = await _isar.saleTransactions
                  .filter()
                  .transactionIdEqualTo(txId)
                  .findFirst();
              if (tx != null &&
                  (tx.zraReceiptNumber == null ||
                      tx.zraReceiptNumber!.isEmpty ||
                      tx.zraReceiptNumber == 'PENDING' ||
                      tx.zraQrCode == null ||
                      tx.zraQrCode!.isEmpty)) {
                tx.zraReceiptNumber = rcptNo;
                tx.zraMarkId = upd['zraMarkId'] as String?;
                tx.zraQrCode = upd['zraQrCode'] as String?;
                tx.zraInternalData = upd['zraInternalData'] as String?;
                tx.zraSdcId = upd['zraSdcId'] as String?;
                tx.zraInvoiceType = upd['zraInvoiceType'] as String?;
                tx.zraStatus = upd['zraStatus'] as String? ?? 'APPROVED';
                await _isar.saleTransactions.put(tx);
              }
            }
          }
        });
      }

      debugPrint(
        'SYNC: Metadata update complete. (${products.length} products, ${categories.length} categories, ${fiscalUpdates.length} fiscal status updates)',
      );
    } catch (e) {
      debugPrint('SYNC_METADATA_ERROR: $e');
    } finally {
      _isSyncingMetadata = false;
    }

    await syncRestaurantState();
  }

  /// Lightweight 15s pull of ZRA fiscal updates for any local PENDING transactions on Tills.
  Future<void> syncFiscalUpdatesOnly() async {
    if (_client == null) return;
    try {
      final hasPending = await _isar.saleTransactions
          .filter()
          .zraReceiptNumberEqualTo('PENDING')
          .or()
          .zraReceiptNumberIsNull()
          .or()
          .zraStatusEqualTo('PENDING')
          .or()
          .zraStatusEqualTo('SUBMITTED_TO_DIGITAX')
          .or()
          .zraStatusEqualTo('VERIFICATION_REQUIRED')
          .or()
          .zraStatusEqualTo('PENDING_SUBMISSION')
          .count();
      if (hasPending == 0) return;

      final fiscalUpdates = await _client.fetchTransactionFiscalUpdates();
      if (fiscalUpdates.isEmpty) return;

      await _isar.writeTxn(() async {
        for (final upd in fiscalUpdates) {
          final txId = upd['transactionId'] as String?;
          final rcptNo = upd['zraReceiptNumber'] as String?;
          if (txId != null &&
              rcptNo != null &&
              rcptNo.isNotEmpty &&
              rcptNo != 'PENDING') {
            final tx = await _isar.saleTransactions
                .filter()
                .transactionIdEqualTo(txId)
                .findFirst();
            if (tx != null &&
                (tx.zraReceiptNumber == null ||
                    tx.zraReceiptNumber!.isEmpty ||
                    tx.zraReceiptNumber == 'PENDING' ||
                    tx.zraQrCode == null ||
                    tx.zraQrCode!.isEmpty)) {
              tx.zraReceiptNumber = rcptNo;
              tx.zraMarkId = upd['zraMarkId'] as String?;
              tx.zraQrCode = upd['zraQrCode'] as String?;
              tx.zraInternalData = upd['zraInternalData'] as String?;
              tx.zraSdcId = upd['zraSdcId'] as String?;
              tx.zraInvoiceType = upd['zraInvoiceType'] as String?;
              tx.zraStatus = upd['zraStatus'] as String? ?? 'APPROVED';
              await _isar.saleTransactions.put(tx);
            }
          }
        }
      });
    } catch (e) {
      debugPrint('SYNC_FISCAL_UPDATES_ERROR: $e');
    }
  }

  /// Pulls live restaurant tables and active orders/items from the Master POS
  /// when the store is operating in restaurant mode.
  Future<void> syncRestaurantState() async {
    if (_client == null || _isSyncingRestaurant) return;
    _isSyncingRestaurant = true;

    try {
      final config = await _isar.storeConfigs.get(1);
      if (config?.businessMode != 'restaurant') return;

      final tablesJson = await _client.fetchRestaurantTables();
      final ordersJson = await _client.fetchRestaurantOrders();

      final tables = tablesJson.map((j) {
        final statusName = j['status'] as String? ?? 'available';
        final status = RestaurantTableStatus.values.firstWhere(
          (e) => e.name == statusName,
          orElse: () => RestaurantTableStatus.available,
        );
        final table = RestaurantTable(
          id: (j['id'] as num).toInt(),
          name: j['name'] as String? ?? 'Table',
          section: j['section'] as String? ?? 'Main Floor',
          capacity: (j['capacity'] as num?)?.toInt() ?? 4,
          status: status,
          branchCode: j['branchCode'] as String? ?? '00',
          activeSessionId: j['activeSessionId'] as String?,
          activeOrderId: (j['activeOrderId'] as num?)?.toInt(),
          assignedWaiterId: (j['assignedWaiterId'] as num?)?.toInt(),
          assignedWaiterName: j['assignedWaiterName'] as String?,
          mergedIntoTableId: (j['mergedIntoTableId'] as num?)?.toInt(),
          isActive: j['isActive'] as bool? ?? true,
        );
        if (j['updatedAt'] is String) {
          table.updatedAt =
              DateTime.tryParse(j['updatedAt'] as String) ?? DateTime.now();
        }
        return table;
      }).toList();

      final orders = <RestaurantOrder>[];
      final items = <RestaurantOrderItem>[];
      final serverOrderIds = <int>{};

      for (final j in ordersJson) {
        final orderId = (j['id'] as num).toInt();
        serverOrderIds.add(orderId);

        final serviceTypeName = j['serviceType'] as String? ?? 'table';
        final serviceType = RestaurantServiceType.values.firstWhere(
          (e) => e.name == serviceTypeName,
          orElse: () => RestaurantServiceType.table,
        );
        final statusName = j['status'] as String? ?? 'submitted';
        final status = RestaurantOrderStatus.values.firstWhere(
          (e) => e.name == statusName,
          orElse: () => RestaurantOrderStatus.submitted,
        );

        final order = RestaurantOrder(
          id: orderId,
          orderNumber: j['orderNumber'] as String? ?? 'ORD-$orderId',
          serviceType: serviceType,
          branchCode: j['branchCode'] as String? ?? '00',
          tableId: (j['tableId'] as num?)?.toInt(),
          tableName: j['tableName'] as String?,
          sessionId: j['sessionId'] as String?,
          waiterId: (j['waiterId'] as num?)?.toInt(),
          waiterName: j['waiterName'] as String?,
          customerName: j['customerName'] as String?,
          customerId: (j['customerId'] as num?)?.toInt(),
          status: status,
          subtotal: (j['subtotal'] as num?)?.toDouble() ?? 0.0,
          taxAmount: (j['taxAmount'] as num?)?.toDouble() ?? 0.0,
          serviceChargeAmount:
              (j['serviceChargeAmount'] as num?)?.toDouble() ?? 0.0,
          discountAmount: (j['discountAmount'] as num?)?.toDouble() ?? 0.0,
          totalAmount: (j['totalAmount'] as num?)?.toDouble() ?? 0.0,
          paidAmount: (j['paidAmount'] as num?)?.toDouble() ?? 0.0,
          saleTransactionId: (j['saleTransactionId'] as num?)?.toInt(),
          notes: j['notes'] as String?,
        );
        if (j['createdAt'] is String) {
          order.createdAt =
              DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now();
        }
        if (j['submittedAt'] is String) {
          order.submittedAt = DateTime.tryParse(j['submittedAt'] as String);
        }
        if (j['settledAt'] is String) {
          order.settledAt = DateTime.tryParse(j['settledAt'] as String);
        }
        if (j['updatedAt'] is String) {
          order.updatedAt =
              DateTime.tryParse(j['updatedAt'] as String) ?? DateTime.now();
        }
        orders.add(order);

        final rawItems = j['items'] as List? ?? [];
        for (final rawItem in rawItems) {
          final ij = rawItem as Map<String, dynamic>;
          final kitchenStatusName = ij['kitchenStatus'] as String? ?? 'newTicket';
          final kitchenStatus = KitchenItemStatus.values.firstWhere(
            (e) => e.name == kitchenStatusName,
            orElse: () => KitchenItemStatus.newTicket,
          );
          final item = RestaurantOrderItem(
            id: (ij['id'] as num).toInt(),
            orderId: (ij['orderId'] as num?)?.toInt() ?? orderId,
            productId: (ij['productId'] as num?)?.toInt() ?? 0,
            productName: ij['productName'] as String? ?? 'Item',
            productSku: ij['productSku'] as String? ?? '',
            basePrice: (ij['basePrice'] as num?)?.toDouble() ?? 0.0,
            modifiersPrice: (ij['modifiersPrice'] as num?)?.toDouble() ?? 0.0,
            unitPrice: (ij['unitPrice'] as num?)?.toDouble() ?? 0.0,
            quantity: (ij['quantity'] as num?)?.toInt() ?? 1,
            taxRate: (ij['taxRate'] as num?)?.toDouble() ?? 16.0,
            isTaxInclusive: ij['isTaxInclusive'] as bool? ?? true,
            kitchenStationId: (ij['kitchenStationId'] as num?)?.toInt(),
            kitchenStationName: ij['kitchenStationName'] as String?,
            ticketNumber: ij['ticketNumber'] as String?,
            kitchenStatus: kitchenStatus,
            modifiersJson: ij['modifiersJson'] as String?,
            specialInstructions: ij['specialInstructions'] as String?,
            isSettled: ij['isSettled'] as bool? ?? false,
            settledSaleTransactionId:
                (ij['settledSaleTransactionId'] as num?)?.toInt(),
            branchCode: ij['branchCode'] as String? ?? '00',
          );
          if (ij['createdAt'] is String) {
            item.createdAt =
                DateTime.tryParse(ij['createdAt'] as String) ?? DateTime.now();
          }
          items.add(item);
        }
      }

      await _isar.writeTxn(() async {
        if (tables.isNotEmpty) {
          await _isar.restaurantTables.putAll(tables);
        }

        // Remove stale non-draft active orders that were settled/cancelled on Master POS
        final localActive = await _isar.restaurantOrders
            .filter()
            .not()
            .statusEqualTo(RestaurantOrderStatus.paid)
            .and()
            .not()
            .statusEqualTo(RestaurantOrderStatus.cancelled)
            .findAll();
        for (final localOrder in localActive) {
          if (localOrder.status != RestaurantOrderStatus.draft &&
              !serverOrderIds.contains(localOrder.id)) {
            localOrder.status = RestaurantOrderStatus.paid;
            await _isar.restaurantOrders.put(localOrder);
          }
        }

        for (final orderId in serverOrderIds) {
          await _isar.restaurantOrderItems
              .filter()
              .orderIdEqualTo(orderId)
              .deleteAll();
        }
        if (orders.isNotEmpty) {
          await _isar.restaurantOrders.putAll(orders);
        }
        if (items.isNotEmpty) {
          await _isar.restaurantOrderItems.putAll(items);
        }
      });
    } catch (e) {
      debugPrint('SYNC_RESTAURANT_ERROR: $e');
    } finally {
      _isSyncingRestaurant = false;
    }
  }

  void dispose() {
    stopSyncLoops();
  }
}

/// Riverpod provider for the sync service.
final syncServiceProvider = Provider<SyncService>((ref) {
  final isar = ref.watch(isarProvider);
  final client = ref.watch(networkClientProvider);
  return SyncService(isar, client);
});

/// Provider that exposes the pending sync count as a stream.
final pendingSyncCountProvider = StreamProvider<int>((ref) async* {
  final syncService = ref.watch(syncServiceProvider);
  while (true) {
    yield await syncService.pendingCount;
    await Future.delayed(const Duration(seconds: 10));
  }
});
