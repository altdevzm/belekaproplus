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
}
