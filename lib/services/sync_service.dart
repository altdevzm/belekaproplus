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

  SyncService(this._isar, this._client);

  /// Number of transactions waiting to be synced.
  Future<int> get pendingCount async {
    return await _isar.saleTransactions
        .filter()
        .isSyncedEqualTo(false)
        .count();
  }

  /// Start the background sync loops.
  void startSyncLoops(String terminalName) {
    stopSyncLoops();

    // 1. Transaction retry loop (every 60s)
    _retryTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      syncPendingTransactions();
    });

    // 2. Metadata pull loop (every 5 minutes)
    _metadataTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      syncMetadata();
    });

    // 3. Start heartbeat in client
    _client?.startBackgroundTasks(terminalName);

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
      SaleTransaction transaction, List<SaleItem> items) async {
    if (_client == null || !_client.isConnected) return false;

    try {
      final success = await _client.pushTransaction(transaction, items);
      if (success) {
        await _isar.writeTxn(() async {
          transaction.isSynced = true;
          await _isar.saleTransactions.put(transaction);
        });
        debugPrint('SYNC: Transaction ${transaction.id} synced immediately');
        return true;
      }
    } catch (e) {
      debugPrint('SYNC_IMMEDIATE_FAIL: $e');
    }
    return false;
  }

  /// Push all pending (un-synced) transactions to the Manager server.
  Future<int> syncPendingTransactions() async {
    if (_client == null || !_client.isConnected) return 0;

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
        },
        'items': items
            .map((item) => {
                  'productId': item.productId,
                  'productName': item.productName,
                  'priceAtSale': item.priceAtSale,
                  'unitCostAtSale': item.unitCostAtSale,
                  'quantity': item.quantity,
                  'isRefunded': item.isRefunded,
                  'taxRateAtSale': item.taxRateAtSale,
                  'isTaxInclusiveAtSale': item.isTaxInclusiveAtSale,
                })
            .toList(),
      });
    }

    final syncedCount = await _client.pushBatchTransactions(batch);

    if (syncedCount > 0) {
      // Mark them as synced locally
      await _isar.writeTxn(() async {
        for (final tx in pending.take(syncedCount)) {
          tx.isSynced = true;
          await _isar.saleTransactions.put(tx);
        }
      });
      debugPrint('SYNC_COMPLETE: $syncedCount/${pending.length} synced');
    }

    return syncedCount;
  }

  /// Pulls products and categories from the server and updates local Isar.
  Future<void> syncMetadata() async {
    if (_client == null || !_client.isConnected || _isSyncingMetadata) return;
    _isSyncingMetadata = true;

    try {
      debugPrint('SYNC: Pulling metadata from manager...');
      
      // 1. Sync Categories
      final categories = await _client.fetchCategories();
      if (categories.isNotEmpty) {
        await _isar.writeTxn(() async {
          // We use putAll which handles internal ID matching
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
      
      debugPrint('SYNC: Metadata update complete. (${products.length} products, ${categories.length} categories)');
    } catch (e) {
      debugPrint('SYNC_METADATA_ERROR: $e');
    } finally {
      _isSyncingMetadata = false;
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
