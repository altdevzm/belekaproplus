import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/cloud_database_service.dart';

final cloudDatabaseServiceProvider = Provider<CloudDatabaseService>((ref) {
  return CloudDatabaseService();
});

final postgresSyncServiceProvider = Provider<PostgresSyncService>((ref) {
  final isar = ref.watch(isarProvider);
  final cloudDb = ref.watch(cloudDatabaseServiceProvider);
  final service = PostgresSyncService(isar: isar, cloudDb: cloudDb);
  service.startAutoSyncLoop();
  return service;
});

class PostgresSyncService {
  final Isar isar;
  final CloudDatabaseService cloudDb;
  Timer? _syncTimer;
  bool _isSyncing = false;

  PostgresSyncService({required this.isar, required this.cloudDb});

  /// Starts periodic 30-second background sync loop for seamless branch-to-HQ transmission
  void startAutoSyncLoop({Duration interval = const Duration(seconds: 30)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (_) async {
      if (_isSyncing) return;
      _isSyncing = true;
      try {
        await syncPendingTransactions();
      } catch (e) {
        debugPrint('[AutoSync Loop] Background sync tick notice: $e');
      } finally {
        _isSyncing = false;
      }
    });
    debugPrint('[PostgresSyncService] Started background sync loop (every ${interval.inSeconds}s)');
  }

  void stopAutoSyncLoop() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Automatically authenticate against Cloud VPS DB and update token in StoreConfig
  Future<String?> _refreshCloudAuthToken(StoreConfig? config, String cloudUrl) async {
    final numericId = config?.cloudAuthUserId ?? '1001';
    final pin = config?.cloudAuthPin ?? '0000';

    debugPrint('[PostgresSyncService] Attempting auto auth token refresh for user $numericId (TPIN: ${config?.tpin})...');
    final authResult = await cloudDb.authenticateUser(
      baseUrl: cloudUrl,
      numericId: numericId,
      pin: pin,
      tpin: config?.tpin,
    );

    if (authResult != null && authResult['access_token'] != null) {
      final newToken = authResult['access_token'] as String;
      if (config != null) {
        await isar.writeTxn(() async {
          config.cloudAuthToken = newToken;
          await isar.storeConfigs.put(config);
        });
      }
      debugPrint('[PostgresSyncService] Successfully refreshed cloud auth token.');
      return newToken;
    }
    debugPrint('[PostgresSyncService] Auto auth token refresh failed.');
    return null;
  }

  /// Push/Sync a specific user or branch manager to Cloud PostgreSQL DB.
  Future<bool> syncUser(User user, {String? plainPin}) async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl = (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final storeId = config?.cloudStoreId ?? 0;
    if (storeId <= 0) {
      debugPrint('[PostgresSyncService] Cannot sync user: cloud branch mapping is missing.');
      return false;
    }
    var token = config?.cloudAuthToken;

    bool result = await cloudDb.syncUser(
      baseUrl: cloudUrl,
      storeId: storeId,
      user: user,
      plainPin: plainPin,
      authToken: token,
    );

    if (!result && (token == null || token.isEmpty)) {
      token = await _refreshCloudAuthToken(config, cloudUrl);
      if (token != null) {
        result = await cloudDb.syncUser(
          baseUrl: cloudUrl,
          storeId: storeId,
          user: user,
          plainPin: plainPin,
          authToken: token,
        );
      }
    }
    return result;
  }

  /// Push/Sync a Store Branch to Cloud PostgreSQL DB.
  /// Returns true if the branch was synced, and saves the cloud store_id back
  /// to branch.cloudStoreId for use in branch report data attribution.
  Future<bool> syncBranch(StoreBranch branch) async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl = (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    var token = config?.cloudAuthToken;

    Future<bool> _doSync(String? tok) async {
      final cloudStoreId = await cloudDb.syncBranch(
        baseUrl: cloudUrl,
        branch: branch,
        tpin: config?.tpin,
        digitaxApiKey: config?.digitaxApiKey,
        digitaxEnvironment: config?.digitaxEnvironment,
        businessTaxType: config?.businessTaxType,
        currencySymbol: config?.currencySymbol,
        authToken: tok,
      );
      if (cloudStoreId != null) {
        // Persist the backend store_id on the local branch for HQ report matching
        if (cloudStoreId > 0 && branch.cloudStoreId != cloudStoreId) {
          await isar.writeTxn(() async {
            branch.cloudStoreId = cloudStoreId;
            await isar.storeBranchs.put(branch);
          });
          debugPrint('[syncBranch] Branch "${branch.name}" mapped to cloud store_id=$cloudStoreId');
        }
        return true;
      }
      return false;
    }

    bool result = await _doSync(token);

    if (!result) {
      token = await _refreshCloudAuthToken(config, cloudUrl);
      if (token != null) {
        result = await _doSync(token);
      }
    }
    return result;
  }

  /// Push/Sync Store Configuration (TPIN, DigiTax Key, Tax Settings) to Cloud DB.
  Future<bool> syncStoreConfigToCloud(StoreConfig config) async {
    final cloudUrl = (config.cloudApiUrl != null && config.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final storeId = config.cloudStoreId ?? 1;
    var token = config.cloudAuthToken;

    return await cloudDb.updateStoreConfig(
      baseUrl: cloudUrl,
      storeId: storeId,
      authToken: token,
      data: {
        'name': config.businessName,
        'tpin': config.tpin,
        'tax_id': config.taxId,
        'currency_symbol': config.currencySymbol,
        'business_tax_type': config.businessTaxType,
        'digitax_api_key': config.digitaxApiKey,
        'digitax_environment': config.digitaxEnvironment,
        'sdc_id': config.sdcId,
        'mrc_no': config.mrcNo,
        'address': config.address,
        'contact_number': config.contactNumber,
        'email': config.email,
      },
    );
  }

  /// Pull latest Store Configuration (TPIN, DigiTax Key, etc.) from Cloud DB into local Isar DB
  Future<bool> pullStoreConfigFromCloud() async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl = (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final storeId = config?.cloudStoreId ?? 0;

    try {
      final stores = await cloudDb.getStores(cloudUrl, authToken: config?.cloudAuthToken);
      if (stores.isEmpty) return false;

      final targetStore = stores.where((s) => s['id'] == storeId).firstOrNull;
      if (targetStore == null) {
        debugPrint('Cloud store ID $storeId not found on server $cloudUrl');
        return false;
      }

      await isar.writeTxn(() async {
        if (targetStore['tpin'] != null && (targetStore['tpin'] as String).isNotEmpty) {
          config?.tpin = targetStore['tpin'];
        }
        if (targetStore['digitax_api_key'] != null && (targetStore['digitax_api_key'] as String).isNotEmpty) {
          config?.digitaxApiKey = targetStore['digitax_api_key'];
        }
        if (targetStore['digitax_environment'] != null) {
          config?.digitaxEnvironment = targetStore['digitax_environment'];
        }
        if (targetStore['business_tax_type'] != null) {
          config?.businessTaxType = targetStore['business_tax_type'];
        }
        if (config != null) {
          await isar.storeConfigs.put(config);
        }
      });
      return true;
    } catch (e) {
      debugPrint('Error pulling store config from cloud: $e');
      return false;
    }
  }

  /// Sync all local users up to Cloud PostgreSQL DB.
  Future<int> syncAllUsersToCloud() async {
    final allUsers = await isar.users.where().findAll();
    int count = 0;
    for (final u in allUsers) {
      final success = await syncUser(u);
      if (success) count++;
    }
    return count;
  }

  /// Sync unsynced transactions from local Isar cache up to online PostgreSQL Cloud DB.
  Future<int> syncPendingTransactions() async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl = (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final storeId = config?.cloudStoreId ?? 0;
    var authToken = config?.cloudAuthToken;

    // Query unsynced sales from local storage
    final unsyncedSales = await isar.saleTransactions
        .filter()
        .isSyncedEqualTo(false)
        .findAll();

    if (unsyncedSales.isEmpty) {
      return 0;
    }

    if (storeId <= 0) {
      throw StateError(
        'Cloud branch mapping is missing; refusing to upload sales to the HQ store.',
      );
    }

    try {
      // Auto-refresh token if missing before making network request
      if (authToken == null || authToken.isEmpty) {
        authToken = await _refreshCloudAuthToken(config, cloudUrl);
      }

      List<String> syncedUuids = [];
      try {
        syncedUuids = await cloudDb.syncBatchSales(
          baseUrl: cloudUrl,
          storeId: storeId,
          transactions: unsyncedSales,
          authToken: authToken,
        );
      } catch (e) {
        // If 401 or Auth error occurs, attempt 1 auto-refresh & retry
        debugPrint('[PostgresSyncService] Batch sync failed ($e), attempting token refresh...');
        authToken = await _refreshCloudAuthToken(config, cloudUrl);
        if (authToken != null) {
          syncedUuids = await cloudDb.syncBatchSales(
            baseUrl: cloudUrl,
            storeId: storeId,
            transactions: unsyncedSales,
            authToken: authToken,
          );
        } else {
          rethrow;
        }
      }

      if (syncedUuids.isNotEmpty) {
        // Mark items as synced in local DB
        await isar.writeTxn(() async {
          for (final sale in unsyncedSales) {
            if (syncedUuids.contains(sale.transactionId)) {
              sale.isSynced = true;
              await isar.saleTransactions.put(sale);
            }
          }

          if (config != null) {
            config.lastCloudSyncDate = DateTime.now();
            await isar.storeConfigs.put(config);
          }
        });

        debugPrint('Successfully synced ${syncedUuids.length} transactions to Cloud PostgreSQL DB');
      }

      return syncedUuids.length;
    } catch (e) {
      debugPrint('Error syncing sales to PostgreSQL Cloud DB: $e');
      rethrow;
    }
  }

  /// Pull sales transactions from Cloud PostgreSQL DB into local Isar DB cache.
  Future<int> pullSalesFromCloud() async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl = (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';

    final owner = await isar.users.filter().roleEqualTo('owner').findFirst();
    final configuredStoreId = config?.cloudStoreId;
    final storeId = owner != null && config?.bhfId == '00'
        ? 0
        : configuredStoreId;

    if (storeId == null || storeId < 0) {
      throw StateError(
        'Cloud branch mapping is missing; refusing to pull data for an unknown store.',
      );
    }
    var authToken = config?.cloudAuthToken;

    try {
      if (authToken == null || authToken.isEmpty) {
        authToken = await _refreshCloudAuthToken(config, cloudUrl);
      }

      var backup = await cloudDb.downloadVpsBackup(
        baseUrl: cloudUrl,
        storeId: storeId,
        token: authToken,
      );

      if (backup == null) {
        // Retry with refreshed token
        authToken = await _refreshCloudAuthToken(config, cloudUrl);
        if (authToken != null) {
          backup = await cloudDb.downloadVpsBackup(
            baseUrl: cloudUrl,
            storeId: storeId,
            token: authToken,
          );
        }
      }

      if (backup == null || backup['sales'] == null) return 0;
      final List rawSales = backup['sales'] as List;
      if (rawSales.isEmpty) return 0;

      int insertedCount = 0;

      for (final raw in rawSales) {
        final uuid = raw['transaction_uuid'] as String? ?? (raw['id'] != null ? 'tx-${raw['id']}' : null);
        if (uuid == null) continue;

        // Check if transaction already exists locally
        final existing = await isar.saleTransactions.filter().transactionIdEqualTo(uuid).findFirst();
        if (existing != null) continue;

        final tx = SaleTransaction(
          totalAmount: (raw['total_amount'] as num?)?.toDouble() ?? 0.0,
          paymentMethod: raw['payment_method'] as String? ?? 'Cash',
          cashierName: raw['cashier_name'] as String? ?? 'Admin',
          status: raw['status'] as String? ?? 'completed',
          subtotal: (raw['subtotal'] as num?)?.toDouble() ?? 0.0,
          taxAmount: (raw['tax_amount'] as num?)?.toDouble() ?? 0.0,
          discountAmount: (raw['discount_amount'] as num?)?.toDouble() ?? 0.0,
          totalCost: (raw['total_cost'] as num?)?.toDouble() ?? 0.0,
          grossProfit: (raw['gross_profit'] as num?)?.toDouble() ?? 0.0,
          tenderedAmount: (raw['tendered_amount'] as num?)?.toDouble() ?? 0.0,
          changeAmount: (raw['change_amount'] as num?)?.toDouble() ?? 0.0,
          customerId: (raw['customer_id'] as num?)?.toInt(),
          pointsEarned: (raw['points_earned'] as num?)?.toInt() ?? 0,
          pointsRedeemed: (raw['points_redeemed'] as num?)?.toInt() ?? 0,
          isSynced: true,
          // Store the backend store_id so HQ can correctly attribute this
          // transaction to the right branch in reports (branch matching uses this)
          cloudStoreId: (raw['store_id'] as num?)?.toInt() ?? 0,
          cashierId: raw['cashier_id']?.toString(),
          terminalName: raw['terminal_name'] as String? ?? 'Terminal-1',
          transactionId: uuid,
          zraReceiptNumber: raw['zra_receipt_number'] as String?,
          zraMarkId: raw['zra_mark_id'] as String?,
          zraQrCode: raw['zra_qr_code'] as String?,
          zraStatus: raw['zra_status'] as String? ?? 'APPROVED',
        );

        if (raw['timestamp'] != null) {
          try {
            tx.timestamp = DateTime.parse(raw['timestamp']);
          } catch (_) {}
        }

        await isar.writeTxn(() async {
          await isar.saleTransactions.put(tx);

          if (raw['items'] != null && raw['items'] is List) {
            final List rawItems = raw['items'] as List;
            for (final rItem in rawItems) {
              final item = SaleItem(
                productId: (rItem['product_id'] as num?)?.toInt() ?? 0,
                productName: rItem['product_name'] as String? ?? 'Product',
                priceAtSale: (rItem['price_at_sale'] as num?)?.toDouble() ?? 0.0,
                unitCostAtSale: (rItem['unit_cost_at_sale'] as num?)?.toDouble() ?? 0.0,
                quantity: (rItem['quantity'] as num?)?.toInt() ?? 1,
              );
              await isar.saleItems.put(item);
              tx.items.add(item);
            }
            await tx.items.save();
          }
        });

        insertedCount++;
      }

      debugPrint('Pulled $insertedCount sales from Cloud VPS into local Isar DB');
      return insertedCount;
    } catch (e) {
      debugPrint('Error pulling sales from cloud: $e');
      rethrow;
    }
  }
}
