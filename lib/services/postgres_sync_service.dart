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
    debugPrint(
      '[PostgresSyncService] Started background sync loop (every ${interval.inSeconds}s)',
    );
  }

  void stopAutoSyncLoop() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  /// Automatically authenticate against Cloud VPS DB and update token in StoreConfig
  Future<String?> _refreshCloudAuthToken(
    StoreConfig? config,
    String cloudUrl, {
    String? pinOverride,
    String? userIdOverride,
  }) async {
    var numericId = userIdOverride?.trim().isNotEmpty == true
        ? userIdOverride!.trim()
        : (config?.cloudAuthUserId?.trim().isNotEmpty == true
            ? config!.cloudAuthUserId!.trim()
            : '1001');
    var pin = pinOverride?.trim().isNotEmpty == true
        ? pinOverride!.trim()
        : (config?.cloudAuthPin?.trim() ?? '');

    if (pin.isEmpty) {
      final allUsers = await isar.users.where().findAll();
      final adminUser = allUsers.cast<User?>().firstWhere(
        (u) =>
            u?.role == 'owner' ||
            u?.role == 'admin' ||
            u?.role == 'branch_manager' ||
            u?.role == 'manager',
        orElse: () => null,
      );
      if (adminUser != null && adminUser.numericId.isNotEmpty) {
        numericId = adminUser.numericId;
      }
    }

    if (pin.isEmpty) {
      debugPrint(
        '[PostgresSyncService] Cloud PIN is not stored; auto auth token refresh cannot proceed.',
      );
      return null;
    }
    debugPrint(
      '[PostgresSyncService] Attempting auto auth token refresh for user $numericId (TPIN: ${config?.tpin})...',
    );
    final authResult = await cloudDb.authenticateUser(
      baseUrl: cloudUrl,
      numericId: numericId,
      pin: pin,
      tpin: config?.tpin,
    );

    final newToken =
        authResult?['token']?.toString() ??
        authResult?['access_token']?.toString();
    if (newToken != null && newToken.isNotEmpty) {
      if (config != null) {
        await isar.writeTxn(() async {
          config.cloudAuthToken = newToken;
          config.cloudAuthPin = pin;
          config.cloudAuthUserId = numericId;
          await isar.storeConfigs.put(config);
        });
      }
      debugPrint(
        '[PostgresSyncService] Successfully refreshed cloud auth token.',
      );
      return newToken;
    }
    debugPrint('[PostgresSyncService] Auto auth token refresh failed.');
    return null;
  }

  /// Push/Sync a specific user or branch manager to Cloud PostgreSQL DB.
  Future<bool> syncUser(User user, {String? plainPin, int? storeId}) async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl =
        (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final targetStoreId = storeId ?? config?.cloudStoreId ?? 0;
    if (targetStoreId <= 0) {
      debugPrint(
        '[PostgresSyncService] Cannot sync user: cloud branch mapping is missing.',
      );
      return false;
    }
    var token = config?.cloudAuthToken;

    bool result;
    Object? firstError;
    try {
      result = await cloudDb.syncUser(
        baseUrl: cloudUrl,
        storeId: targetStoreId,
        user: user,
        plainPin: plainPin,
        authToken: token,
      );
    } catch (e) {
      firstError = e;
      result = false;
    }

    if (!result) {
      token = await _refreshCloudAuthToken(config, cloudUrl);
      if (token != null) {
        try {
          result = await cloudDb.syncUser(
            baseUrl: cloudUrl,
            storeId: targetStoreId,
            user: user,
            plainPin: plainPin,
            authToken: token,
          );
        } catch (_) {
          rethrow;
        }
      } else if (firstError != null) {
        throw firstError;
      }
    }
    return result;
  }

  Future<bool> deleteUser(User user, {int? storeId}) async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl = (config?.cloudApiUrl?.trim().isNotEmpty == true)
        ? config!.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final targetStoreId = storeId ?? config?.cloudStoreId ?? 0;
    if (targetStoreId <= 0) return true;
    var token = config?.cloudAuthToken;

    Future<bool> remove(String? authToken) => cloudDb.deleteUser(
      baseUrl: cloudUrl,
      storeId: targetStoreId,
      numericId: user.numericId,
      authToken: authToken,
    );

    Object? firstError;
    try {
      if (await remove(token)) return true;
    } catch (e) {
      firstError = e;
    }
    token = await _refreshCloudAuthToken(config, cloudUrl);
    if (token == null) {
      if (firstError != null) throw firstError;
      return false;
    }
    return remove(token);
  }

  /// Push/Sync a Store Branch to Cloud PostgreSQL DB.
  /// Returns true if the branch was synced, and saves the cloud store_id back
  /// to branch.cloudStoreId for use in branch report data attribution.
  Future<bool> syncBranch(
    StoreBranch branch, {
    String? branchApiKey,
    String? authPin,
  }) async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl =
        (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    var token = config?.cloudAuthToken;

    Future<bool> doSync(String? tok) async {
      if (branch.cloudStoreId <= 0) {
        try {
          final stores = await cloudDb.getStores(cloudUrl, authToken: tok);
          final existing = stores.cast<Map<String, dynamic>?>().firstWhere(
            (store) =>
                store?['store_code']?.toString().trim().toUpperCase() ==
                    branch.code.trim().toUpperCase() ||
                store?['bhf_id']?.toString().trim().toUpperCase() ==
                    branch.bhfId.trim().toUpperCase(),
            orElse: () => null,
          );
          if (existing?['id'] != null) {
            branch.cloudStoreId = (existing!['id'] as num).toInt();
            await isar.writeTxn(() async {
              await isar.storeBranchs.put(branch);
            });
          }
        } catch (_) {
          // If store lookup fails, let syncBranch proceed to create/upsert
        }
      }
      final cloudStoreId = await cloudDb.syncBranch(
        baseUrl: cloudUrl,
        branch: branch,
        tpin: config?.tpin,
        // A branch must never inherit HQ credentials. On a branch device,
        // config.digitaxApiKey is that branch's own credential.
        digitaxApiKey: branchApiKey?.trim().isNotEmpty == true
            ? branchApiKey!.trim()
            : branch.bhfId == config?.bhfId
            ? config?.digitaxApiKey
            : null,
        digitaxEnvironment: config?.digitaxEnvironment,
        businessTaxType: config?.businessTaxType,
        currencySymbol: config?.currencySymbol,
        authToken: tok,
      );
      if (cloudStoreId != null) {
        if (cloudStoreId <= 0) {
          throw StateError(
            'VPS accepted branch ${branch.bhfId}, but returned no cloud store ID.',
          );
        }
        // Persist the backend store_id on the local branch for HQ report matching
        if (branch.cloudStoreId != cloudStoreId) {
          await isar.writeTxn(() async {
            branch.cloudStoreId = cloudStoreId;
            await isar.storeBranchs.put(branch);
          });
          debugPrint(
            '[syncBranch] Branch "${branch.name}" mapped to cloud store_id=$cloudStoreId',
          );
        }
        return true;
      }
      return false;
    }

    Object? firstError;
    bool result = false;
    try {
      result = await doSync(token);
    } catch (e) {
      firstError = e;
    }

    if (!result) {
      token = await _refreshCloudAuthToken(
        config,
        cloudUrl,
        pinOverride: authPin,
      );
      if (token == null) {
        if (firstError != null) throw firstError;
        throw StateError(
          'Could not authenticate with the VPS to sync branch ${branch.bhfId}.',
        );
      }
      try {
        result = await doSync(token);
      } catch (e) {
        throw StateError(
          'VPS branch ${branch.bhfId} synchronization failed: $e',
        );
      }
    }
    return result;
  }

  Future<bool> deleteBranch(StoreBranch branch) async {
    if (branch.cloudStoreId <= 0) return true;
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl = (config?.cloudApiUrl?.trim().isNotEmpty == true)
        ? config!.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    var token = config?.cloudAuthToken;

    Future<bool> remove(String? authToken) => cloudDb.deleteBranch(
      baseUrl: cloudUrl,
      storeId: branch.cloudStoreId,
      authToken: authToken,
    );

    try {
      if (await remove(token)) return true;
    } catch (_) {}
    token = await _refreshCloudAuthToken(config, cloudUrl);
    if (token == null) return false;
    return remove(token);
  }

  /// Push/Sync Store Configuration (TPIN, DigiTax Key, Tax Settings) to Cloud DB.
  Future<bool> syncStoreConfigToCloud(StoreConfig config) async {
    final cloudUrl =
        (config.cloudApiUrl != null && config.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final storeId = config.cloudStoreId ?? 1;
    var token = config.cloudAuthToken;

    var result = await cloudDb.updateStoreConfig(
      baseUrl: cloudUrl,
      storeId: storeId,
      authToken: token,
      data: {
        'name': config.businessName,
        'tpin': config.tpin,
        'bhf_id': config.bhfId,
        'tax_id': config.taxId,
        'currency_symbol': config.currencySymbol,
        'business_tax_type': config.businessTaxType,
        'digitax_api_key': config.digitaxApiKey,
        'digitax_environment': config.digitaxEnvironment,
        'lenco_api_key': config.lencoApiKey,
        'lenco_environment': config.lencoEnvironment,
        'lenco_account_id': config.lencoAccountId,
        'lenco_enabled': config.lencoEnabled,
        'sdc_id': config.sdcId,
        'mrc_no': config.mrcNo,
        'address': config.address,
        'contact_number': config.contactNumber,
        'email': config.email,
      },
    );
    if (!result) {
      token = await _refreshCloudAuthToken(config, cloudUrl);
      if (token != null) {
        result = await cloudDb.updateStoreConfig(
          baseUrl: cloudUrl,
          storeId: storeId,
          authToken: token,
          data: {
            'name': config.businessName,
            'tpin': config.tpin,
            'bhf_id': config.bhfId,
            'tax_id': config.taxId,
            'currency_symbol': config.currencySymbol,
            'business_tax_type': config.businessTaxType,
            'digitax_api_key': config.digitaxApiKey,
            'digitax_environment': config.digitaxEnvironment,
            'lenco_api_key': config.lencoApiKey,
            'lenco_environment': config.lencoEnvironment,
            'lenco_account_id': config.lencoAccountId,
            'lenco_enabled': config.lencoEnabled,
            'sdc_id': config.sdcId,
            'mrc_no': config.mrcNo,
            'address': config.address,
            'contact_number': config.contactNumber,
            'email': config.email,
          },
        );
      }
    }
    return result;
  }

  /// Pull latest Store Configuration (TPIN, DigiTax Key, etc.) from Cloud DB into local Isar DB
  Future<bool> pullStoreConfigFromCloud() async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl =
        (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final storeId = config?.cloudStoreId ?? 0;

    try {
      var token = config?.cloudAuthToken;
      List<Map<String, dynamic>> stores;
      try {
        stores = await cloudDb.getStores(cloudUrl, authToken: token);
      } catch (_) {
        token = await _refreshCloudAuthToken(config, cloudUrl);
        if (token == null) return false;
        stores = await cloudDb.getStores(cloudUrl, authToken: token);
      }
      if (stores.isEmpty) return false;

      final targetStore = stores.where((s) => s['id'] == storeId).firstOrNull;
      if (targetStore == null) {
        debugPrint('Cloud store ID $storeId not found on server $cloudUrl');
        return false;
      }

      await isar.writeTxn(() async {
        final remoteTpin = targetStore['tpin']?.toString().trim();
        final remoteApiKey = targetStore['digitax_api_key']?.toString().trim();
        final remoteEnvironment = targetStore['digitax_environment']
            ?.toString()
            .trim();
        final remoteTaxType = targetStore['business_tax_type']
            ?.toString()
            .trim();
        final remoteBhfId = targetStore['bhf_id']?.toString().trim();
        if (remoteTpin?.isNotEmpty == true) config?.tpin = remoteTpin;
        config?.digitaxApiKey = remoteApiKey?.isNotEmpty == true
            ? remoteApiKey
            : null;
        if (remoteEnvironment?.isNotEmpty == true) {
          config?.digitaxEnvironment = remoteEnvironment!;
        }
        if (remoteTaxType?.isNotEmpty == true) {
          config?.businessTaxType = remoteTaxType!;
        }
        if ((config?.bhfId.isEmpty ?? true) && remoteBhfId?.isNotEmpty == true) {
          config?.bhfId = remoteBhfId!;
        }
        if (targetStore['sdc_id'] != null) {
          config?.sdcId = targetStore['sdc_id']?.toString();
        }
        if (targetStore['mrc_no'] != null) {
          config?.mrcNo = targetStore['mrc_no']?.toString();
        }
        if (targetStore['currency_symbol'] != null) {
          config?.currencySymbol =
              targetStore['currency_symbol']?.toString() ?? 'K';
        }
        if (targetStore['branch_name'] != null) {
          config?.branchName = targetStore['branch_name']?.toString();
        }
        if (targetStore['lenco_api_key'] != null) {
          config?.lencoApiKey = targetStore['lenco_api_key']?.toString();
        }
        if (targetStore['lenco_environment'] != null) {
          config?.lencoEnvironment = targetStore['lenco_environment']?.toString() ?? 'sandbox';
        }
        if (targetStore['lenco_account_id'] != null) {
          config?.lencoAccountId = targetStore['lenco_account_id']?.toString();
        }
        if (targetStore['lenco_enabled'] != null) {
          config?.lencoEnabled = targetStore['lenco_enabled'] == true;
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
    final cloudUrl =
        (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final storeId = config?.cloudStoreId ?? 0;
    var authToken = config?.cloudAuthToken;

    await syncInventorySnapshot();

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
        debugPrint(
          '[PostgresSyncService] Batch sync failed ($e), attempting token refresh...',
        );
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

        debugPrint(
          'Successfully synced ${syncedUuids.length} transactions to Cloud PostgreSQL DB',
        );
      }

      return syncedUuids.length;
    } catch (e) {
      debugPrint('Error syncing sales to PostgreSQL Cloud DB: $e');
      rethrow;
    }
  }

  /// Push the branch's current product catalog and stock audit trail to its
  /// mapped cloud store so HQ reports can read inventory independently of sales.
  Future<bool> syncInventorySnapshot() async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl = (config?.cloudApiUrl?.trim().isNotEmpty == true)
        ? config!.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';
    final storeId = config?.cloudStoreId ?? 0;
    if (storeId <= 0) return false;

    // Pull corporate DigiTax configuration before each branch sync so changes
    // made by HQ reach an already-installed branch client.
    await pullStoreConfigFromCloud();

    final branchCode = config?.bhfId.trim().isNotEmpty == true
        ? config!.bhfId.trim()
        : '00';
    final products = await isar.products
        .filter()
        .branchCodeEqualTo(branchCode)
        .findAll();
    final movements = await isar.stockMovements
        .filter()
        .branchCodeEqualTo(branchCode)
        .findAll();
    var token = config?.cloudAuthToken;

    try {
      final synced = await cloudDb.syncInventorySnapshot(
        baseUrl: cloudUrl,
        storeId: storeId,
        products: products,
        movements: movements,
        authToken: token,
      );
      if (synced) return true;
    } catch (e) {
      debugPrint('[PostgresSyncService] Inventory snapshot sync failed: $e');
    }

    token = await _refreshCloudAuthToken(config, cloudUrl);
    if (token == null) return false;
    try {
      return await cloudDb.syncInventorySnapshot(
        baseUrl: cloudUrl,
        storeId: storeId,
        products: products,
        movements: movements,
        authToken: token,
      );
    } catch (e) {
      debugPrint('[PostgresSyncService] Inventory snapshot retry failed: $e');
      return false;
    }
  }

  /// Pull sales transactions from Cloud PostgreSQL DB into local Isar DB cache.
  Future<int> pullSalesFromCloud({int? storeId}) async {
    final config = await isar.storeConfigs.where().findFirst();
    final cloudUrl =
        (config?.cloudApiUrl != null && config!.cloudApiUrl!.trim().isNotEmpty)
        ? config.cloudApiUrl!.trim()
        : 'http://23.139.36.20:8003';

    final configuredStoreId = config?.cloudStoreId;
    var targetStoreId = storeId ?? configuredStoreId;

    if (storeId == null && config?.bhfId.trim() == '00') {
      final stores = await cloudDb.getStores(
        cloudUrl,
        authToken: config?.cloudAuthToken,
      );
      final hq = stores
          .where((store) => store['bhf_id']?.toString().trim() == '00')
          .firstOrNull;
      targetStoreId = (hq?['id'] as num?)?.toInt() ?? targetStoreId;
    }

    if (targetStoreId == null || targetStoreId <= 0) {
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
        storeId: targetStoreId,
        token: authToken,
      );

      if (backup == null) {
        // Retry with refreshed token
        authToken = await _refreshCloudAuthToken(config, cloudUrl);
        if (authToken != null) {
          backup = await cloudDb.downloadVpsBackup(
            baseUrl: cloudUrl,
            storeId: targetStoreId,
            token: authToken,
          );
        }
      }

      if (backup == null || backup['sales'] == null) return 0;
      final List rawSales = backup['sales'] as List;
      if (rawSales.isEmpty) return 0;

      // HQ cache must never aggregate branch sales. Branch reports request
      // their own target store explicitly and keep their data branch-scoped.
      if (storeId == null && config?.bhfId == '00') {
        await isar.writeTxn(() async {
          final cached = await isar.saleTransactions.where().findAll();
          for (final sale in cached) {
            if (sale.cloudStoreId > 0 && sale.cloudStoreId != targetStoreId) {
              await isar.saleTransactions.delete(sale.id);
            }
          }
        });
      }

      int insertedCount = 0;

      num? numericValue(dynamic value) {
        if (value is num) return value;
        return num.tryParse(value?.toString() ?? '');
      }

      for (final raw in rawSales) {
        final uuid =
            raw['transaction_uuid'] as String? ??
            (raw['id'] != null ? 'tx-${raw['id']}' : null);
        if (uuid == null) continue;

        // Check if transaction already exists locally
        final existing = await isar.saleTransactions
            .filter()
            .transactionIdEqualTo(uuid)
            .findFirst();
        if (existing != null) {
          final cloudStoreId = numericValue(raw['store_id'])?.toInt() ?? 0;
          final rawTimestamp = raw['timestamp']?.toString();
          final parsedTimestamp = rawTimestamp == null
              ? null
              : DateTime.tryParse(rawTimestamp);
          existing.cloudStoreId = cloudStoreId > 0
              ? cloudStoreId
              : existing.cloudStoreId;
          if (parsedTimestamp != null) {
            existing.timestamp = parsedTimestamp;
          }
          existing.totalAmount =
              numericValue(raw['total_amount'])?.toDouble() ??
              existing.totalAmount;
          existing.subtotal =
              numericValue(raw['subtotal'])?.toDouble() ?? existing.subtotal;
          existing.taxAmount =
              numericValue(raw['tax_amount'])?.toDouble() ?? existing.taxAmount;
          existing.grossProfit =
              numericValue(raw['gross_profit'])?.toDouble() ??
              existing.grossProfit;
          existing.status = raw['status']?.toString() ?? existing.status;
          await isar.writeTxn(() async {
            await isar.saleTransactions.put(existing);
          });
          continue;
        }

        final tx = SaleTransaction(
          totalAmount: numericValue(raw['total_amount'])?.toDouble() ?? 0.0,
          paymentMethod: raw['payment_method'] as String? ?? 'Cash',
          cashierName: raw['cashier_name'] as String? ?? 'Admin',
          status: raw['status'] as String? ?? 'completed',
          subtotal: numericValue(raw['subtotal'])?.toDouble() ?? 0.0,
          taxAmount: numericValue(raw['tax_amount'])?.toDouble() ?? 0.0,
          discountAmount:
              numericValue(raw['discount_amount'])?.toDouble() ?? 0.0,
          totalCost: numericValue(raw['total_cost'])?.toDouble() ?? 0.0,
          grossProfit: numericValue(raw['gross_profit'])?.toDouble() ?? 0.0,
          tenderedAmount:
              numericValue(raw['tendered_amount'])?.toDouble() ?? 0.0,
          changeAmount: numericValue(raw['change_amount'])?.toDouble() ?? 0.0,
          customerId: numericValue(raw['customer_id'])?.toInt(),
          pointsEarned: numericValue(raw['points_earned'])?.toInt() ?? 0,
          pointsRedeemed: numericValue(raw['points_redeemed'])?.toInt() ?? 0,
          isSynced: true,
          // Store the backend store_id so HQ can correctly attribute this
          // transaction to the right branch in reports (branch matching uses this)
          cloudStoreId: numericValue(raw['store_id'])?.toInt() ?? 0,
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
                productId: numericValue(rItem['product_id'])?.toInt() ?? 0,
                productName: rItem['product_name'] as String? ?? 'Product',
                priceAtSale:
                    numericValue(rItem['price_at_sale'])?.toDouble() ?? 0.0,
                unitCostAtSale:
                    numericValue(rItem['unit_cost_at_sale'])?.toDouble() ?? 0.0,
                quantity: numericValue(rItem['quantity'])?.toInt() ?? 1,
              );
              await isar.saleItems.put(item);
              tx.items.add(item);
            }
            await tx.items.save();
          }
        });

        insertedCount++;
      }

      debugPrint(
        'Pulled $insertedCount sales from Cloud VPS into local Isar DB',
      );
      return insertedCount;
    } catch (e) {
      debugPrint('Error pulling sales from cloud: $e');
      rethrow;
    }
  }
}
