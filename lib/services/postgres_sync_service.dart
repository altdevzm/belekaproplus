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
  return PostgresSyncService(isar: isar, cloudDb: cloudDb);
});

class PostgresSyncService {
  final Isar isar;
  final CloudDatabaseService cloudDb;

  PostgresSyncService({required this.isar, required this.cloudDb});

  /// Push/Sync a specific user or branch manager to Cloud PostgreSQL DB.
  Future<bool> syncUser(User user, {String? plainPin}) async {
    final config = await isar.storeConfigs.where().findFirst();
    if (config?.isCloudSyncEnabled != true) return false;
    final cloudUrl = config?.cloudApiUrl;
    if (cloudUrl == null || cloudUrl.trim().isEmpty) return false;

    final storeId = config?.cloudStoreId;
    if (storeId == null) return false;

    return await cloudDb.syncUser(
      baseUrl: cloudUrl.trim(),
      storeId: storeId,
      user: user,
      plainPin: plainPin,
    );
  }

  /// Push/Sync a Store Branch to Cloud PostgreSQL DB.
  Future<bool> syncBranch(StoreBranch branch) async {
    final config = await isar.storeConfigs.where().findFirst();
    if (config?.isCloudSyncEnabled != true) return false;
    final cloudUrl = config?.cloudApiUrl;
    if (cloudUrl == null || cloudUrl.trim().isEmpty) return false;

    return await cloudDb.syncBranch(
      baseUrl: cloudUrl.trim(),
      branch: branch,
      tpin: config?.tpin,
      digitaxApiKey: config?.digitaxApiKey,
      digitaxEnvironment: config?.digitaxEnvironment,
      businessTaxType: config?.businessTaxType,
      currencySymbol: config?.currencySymbol,
    );
  }

  /// Push/Sync Store Configuration (TPIN, DigiTax Key, Tax Settings) to Cloud DB.
  Future<bool> syncStoreConfigToCloud(StoreConfig config) async {
    if (!config.isCloudSyncEnabled) return false;
    final cloudUrl = config.cloudApiUrl;
    if (cloudUrl == null || cloudUrl.trim().isEmpty) return false;

    final storeId = config.cloudStoreId;
    if (storeId == null) return false;

    return await cloudDb.updateStoreConfig(
      baseUrl: cloudUrl.trim(),
      storeId: storeId,
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
    if (config == null || !config.isCloudSyncEnabled) return false;
    final cloudUrl = config.cloudApiUrl;
    if (cloudUrl == null || cloudUrl.trim().isEmpty) return false;

    final storeId = config.cloudStoreId;
    if (storeId == null) return false;

    try {
      final stores = await cloudDb.getStores(cloudUrl.trim());
      if (stores.isEmpty) return false;

      final targetStore = stores.where((s) => s['id'] == storeId).firstOrNull;
      if (targetStore == null) {
        debugPrint('Cloud store ID $storeId not found on server $cloudUrl');
        return false;
      }

      await isar.writeTxn(() async {
        if (targetStore['tpin'] != null && (targetStore['tpin'] as String).isNotEmpty) {
          config.tpin = targetStore['tpin'];
        }
        if (targetStore['digitax_api_key'] != null && (targetStore['digitax_api_key'] as String).isNotEmpty) {
          config.digitaxApiKey = targetStore['digitax_api_key'];
        }
        if (targetStore['digitax_environment'] != null) {
          config.digitaxEnvironment = targetStore['digitax_environment'];
        }
        if (targetStore['business_tax_type'] != null) {
          config.businessTaxType = targetStore['business_tax_type'];
        }
        await isar.storeConfigs.put(config);
      });
      return true;
    } catch (e) {
      debugPrint('Error pulling store config from cloud: $e');
      return false;
    }
  }

  /// Sync all local users up to Cloud PostgreSQL DB.
  Future<int> syncAllUsersToCloud() async {
    final config = await isar.storeConfigs.where().findFirst();
    if (config?.isCloudSyncEnabled != true) return 0;
    final cloudUrl = config?.cloudApiUrl;
    if (cloudUrl == null || cloudUrl.trim().isEmpty) return 0;

    final storeId = config?.cloudStoreId;
    if (storeId == null) return 0;

    final allUsers = await isar.users.where().findAll();
    int count = 0;
    for (final u in allUsers) {
      final success = await cloudDb.syncUser(
        baseUrl: cloudUrl.trim(),
        storeId: storeId,
        user: u,
      );
      if (success) count++;
    }
    return count;
  }

  /// Sync unsynced transactions from local Isar cache up to online PostgreSQL Cloud DB.
  Future<int> syncPendingTransactions() async {
    final config = await isar.storeConfigs.where().findFirst();
    if (config?.isCloudSyncEnabled != true) {
      return 0;
    }
    final cloudUrl = config?.cloudApiUrl;
    if (cloudUrl == null || cloudUrl.trim().isEmpty) {
      return 0;
    }

    final storeId = config?.cloudStoreId;
    if (storeId == null) {
      return 0;
    }

    // Query unsynced sales from local storage
    final unsyncedSales = await isar.saleTransactions
        .filter()
        .isSyncedEqualTo(false)
        .findAll();

    if (unsyncedSales.isEmpty) {
      return 0;
    }

    try {
      final syncedUuids = await cloudDb.syncBatchSales(
        baseUrl: cloudUrl,
        storeId: storeId,
        transactions: unsyncedSales,
      );

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

    final storeId = config?.cloudStoreId ?? 1;

    try {
      final backup = await cloudDb.downloadVpsBackup(
        baseUrl: cloudUrl,
        storeId: storeId,
      );

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
      return 0;
    }
  }
}
