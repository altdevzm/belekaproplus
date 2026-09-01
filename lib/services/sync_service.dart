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
      final response = await _client.pushTransaction(transaction, items);
      if (response != null && response['success'] == true) {
        await _isar.writeTxn(() async {
          transaction.isSynced = true;
          if (response['zraReceiptNumber'] != null && (response['zraReceiptNumber'] as String).isNotEmpty) {
            transaction.zraReceiptNumber = response['zraReceiptNumber'] as String;
            transaction.zraMarkId = response['zraMarkId'] as String?;
            transaction.zraQrCode = response['zraQrCode'] as String?;
            transaction.zraInternalData = response['zraInternalData'] as String?;
            transaction.zraSdcId = response['zraSdcId'] as String?;
            transaction.zraInvoiceType = response['zraInvoiceType'] as String?;
            transaction.zraStatus = response['zraStatus'] as String? ?? 'APPROVED';
          }
          await _isar.saleTransactions.put(transaction);
        });
        debugPrint('SYNC: Transaction ${transaction.id} synced immediately (Fiscal: ${transaction.zraStatus})');
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
                if (upd['zraReceiptNumber'] != null && (upd['zraReceiptNumber'] as String).isNotEmpty) {
                  tx.zraReceiptNumber = upd['zraReceiptNumber'] as String;
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

  /// Pulls products, categories, store tax config, and transaction fiscal status updates from the Manager server.
  Future<void> syncMetadata() async {
    if (_client == null || !_client.isConnected || _isSyncingMetadata) return;
    _isSyncingMetadata = true;

    try {
      debugPrint('SYNC: Pulling metadata and tax config from manager...');

      // 0. Sync Store Config (including DigiTax API credentials)
      final serverInfo = await _client.getServerInfo();
      if (serverInfo != null) {
        final apiKey = serverInfo['digitaxApiKey']?.toString().trim();
        final sdcId = serverInfo['sdcId']?.toString().trim();
        final tpin = serverInfo['tpin']?.toString().trim();
        final taxType = serverInfo['businessTaxType']?.toString().trim();
        final bhfId = serverInfo['bhfId']?.toString().trim();
        final env = serverInfo['digitaxEnvironment']?.toString().trim();

        final config = await _isar.storeConfigs.where().findFirst() ?? StoreConfig();
        bool configChanged = false;

        if (apiKey != null && apiKey.isNotEmpty && config.digitaxApiKey != apiKey) {
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
        if (taxType != null && taxType.isNotEmpty && config.businessTaxType != taxType) {
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

        if (configChanged) {
          await _isar.writeTxn(() async {
            await _isar.storeConfigs.put(config);
          });
          debugPrint('SYNC: Local StoreConfig synced with Manager DigiTax credentials');
        }
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
            if (txId != null && rcptNo != null && rcptNo.isNotEmpty) {
              final tx = await _isar.saleTransactions.filter().transactionIdEqualTo(txId).findFirst();
              if (tx != null && (tx.zraReceiptNumber == null || tx.zraReceiptNumber!.isEmpty)) {
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
      
      debugPrint('SYNC: Metadata update complete. (${products.length} products, ${categories.length} categories, ${fiscalUpdates.length} fiscal status updates)');
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
