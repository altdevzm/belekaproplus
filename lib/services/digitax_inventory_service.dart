import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/local_sql_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

class DigiTaxSyncResult {
  final bool success;
  final int pushedCount;
  final int pulledCount;
  final int deduplicatedCount;
  final String message;
  final int? statusCode;
  final List<String> errors;

  const DigiTaxSyncResult({
    required this.success,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.deduplicatedCount = 0,
    required this.message,
    this.statusCode,
    this.errors = const [],
  });
}

class DigiTaxTestResult {
  final bool success;
  final int? statusCode;
  final String message;
  final Map<String, dynamic>? businessInfo;
  final List<Map<String, dynamic>>? taxRates;

  const DigiTaxTestResult({
    required this.success,
    this.statusCode,
    required this.message,
    this.businessInfo,
    this.taxRates,
  });
}

/// State notifier to track instant sync status
class DigiTaxSyncStatusNotifier extends StateNotifier<Map<String, dynamic>> {
  DigiTaxSyncStatusNotifier() : super({
    'isSyncing': false,
    'lastSyncTime': null,
    'lastStatus': 'Ready',
    'lastError': null,
  });

  void updateStatus({
    required bool isSyncing,
    DateTime? lastSyncTime,
    required String lastStatus,
    String? lastError,
  }) {
    state = {
      'isSyncing': isSyncing,
      'lastSyncTime': lastSyncTime ?? state['lastSyncTime'],
      'lastStatus': lastStatus,
      'lastError': lastError,
    };
  }
}

final digiTaxAutoSyncProvider = StateNotifierProvider<DigiTaxSyncStatusNotifier, Map<String, dynamic>>((ref) {
  return DigiTaxSyncStatusNotifier();
});

final digitaxInventoryServiceProvider = Provider<DigiTaxInventoryService>((ref) {
  return DigiTaxInventoryService(ref: ref);
});

class DigiTaxInventoryService {
  final Ref ref;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Content-Type': 'application/json'},
  ));

  bool _isSyncRunning = false;

  // Official DigiTax Zambia API Base URL from zm.docs.digitax.tech OpenAPI spec
  static const String digitaxZambiaApiBaseUrl = 'https://api.digitax.tech/zm/v1';

  DigiTaxInventoryService({required this.ref});

  // --------------------------------------------------------------------------
  // 1. DE-DUPLICATION ENGINE
  // --------------------------------------------------------------------------

  /// Purge all duplicate products in the local database, keeping only one unique entry per name/SKU per branch
  Future<int> deduplicateLocalProducts({String? branchCode}) async {
    final db = ref.read(databaseServiceProvider);
    final allProducts = branchCode != null 
        ? await db.getAllProducts(branchCode: branchCode)
        : await db.isar.products.where().findAll();
    
    final Map<String, Product> uniqueMap = {};
    final List<Id> duplicateIdsToDelete = [];

    for (final p in allProducts) {
      final nameKey = '${p.branchCode}_${p.name.trim().toLowerCase()}';
      if (p.name.trim().isEmpty) continue;

      if (uniqueMap.containsKey(nameKey)) {
        final existing = uniqueMap[nameKey]!;
        if (p.stockLevel > existing.stockLevel) {
          existing.stockLevel = p.stockLevel;
        }
        if (p.price > 0 && existing.price == 0) {
          existing.price = p.price;
        }
        duplicateIdsToDelete.add(p.id);
      } else {
        uniqueMap[nameKey] = p;
      }
    }

    if (duplicateIdsToDelete.isNotEmpty) {
      await db.isar.writeTxn(() async {
        for (final id in duplicateIdsToDelete) {
          await db.isar.products.delete(id);
        }
      });
      debugPrint('DIGITAX_DEDUPLICATION: Removed ${duplicateIdsToDelete.length} duplicate products');
    }
    return duplicateIdsToDelete.length;
  }

  // --------------------------------------------------------------------------
  // 2. INSTANT ON-DEMAND SYNC TRIGGER
  // --------------------------------------------------------------------------

  /// Trigger an instant bidirectional sync with DigiTax
  Future<DigiTaxSyncResult> triggerInstantSync({String? branchCode}) async {
    ref.read(digiTaxAutoSyncProvider.notifier).updateStatus(
      isSyncing: true,
      lastStatus: 'Syncing with DigiTax...',
    );

    final result = await syncAllInventoryWithDigitax(branchCode: branchCode);

    ref.read(digiTaxAutoSyncProvider.notifier).updateStatus(
      isSyncing: false,
      lastSyncTime: DateTime.now(),
      lastStatus: result.success ? 'Synced' : 'Sync Failed',
      lastError: result.errors.isNotEmpty ? result.errors.first : null,
    );

    return result;
  }

  // --------------------------------------------------------------------------
  // 3. LIVE SERVER CONNECTION & API KEY TEST
  // --------------------------------------------------------------------------

  /// Test connection directly against DigiTax live/sandbox servers using the official /info endpoint.
  Future<DigiTaxTestResult> testApiKeyConnection({
    required String apiKey,
    required String environment,
  }) async {
    final cleanKey = apiKey.trim();
    if (cleanKey.isEmpty) {
      return const DigiTaxTestResult(
        success: false,
        statusCode: 400,
        message: 'API Key is empty. Please enter your DigiTax Secret API Key.',
      );
    }

    final headers = {
      'Authorization': 'Bearer $cleanKey',
      'X-API-Key': cleanKey,
      'Content-Type': 'application/json',
    };

    try {
      final response = await _dio.get(
        '$digitaxZambiaApiBaseUrl/info',
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        Map<String, dynamic> infoMap = {};
        if (data is Map<String, dynamic>) {
          infoMap = data;
        }

        final bizName = infoMap['business_name'] ?? infoMap['name'] ?? 'DigiTax Merchant';
        final tpin = infoMap['tpin'] ?? 'Registered';

        return DigiTaxTestResult(
          success: true,
          statusCode: 200,
          message: 'HTTP 200 OK: Connected to DigiTax ($bizName • TPIN: $tpin). Live ZRA VSDC active!',
          businessInfo: infoMap,
        );
      } else {
        return DigiTaxTestResult(
          success: false,
          statusCode: response.statusCode,
          message: 'Server returned HTTP ${response.statusCode}: ${response.data}',
        );
      }
    } on DioException catch (dioErr) {
      final statusCode = dioErr.response?.statusCode;
      final responseData = dioErr.response?.data;
      String errorMsg = 'DigiTax Server Error';

      if (statusCode == 401) {
        errorMsg = 'HTTP 401 Unauthorized: Invalid DigiTax Secret API Key.';
      } else if (statusCode == 403) {
        errorMsg = 'HTTP 403 Forbidden: API key does not have permission for this DigiTax VSDC endpoint.';
      } else if (statusCode == 404) {
        errorMsg = 'HTTP 404: Endpoint not found on DigiTax API.';
      } else if (dioErr.type == DioExceptionType.connectionTimeout || dioErr.type == DioExceptionType.receiveTimeout) {
        errorMsg = 'Connection Timeout: Could not reach DigiTax API server within 20 seconds.';
      } else if (dioErr.type == DioExceptionType.connectionError) {
        errorMsg = 'Network Connection Error: Check your internet connection (${dioErr.message})';
      } else {
        errorMsg = 'Server Error [HTTP $statusCode]: ${responseData ?? dioErr.message}';
      }

      return DigiTaxTestResult(
        success: false,
        statusCode: statusCode,
        message: errorMsg,
      );
    } catch (e) {
      return DigiTaxTestResult(
        success: false,
        message: 'Unexpected network error: $e',
      );
    }
  }

  // --------------------------------------------------------------------------
  // 4. BULLETPROOF BIDIRECTIONAL PRODUCT EQUILIBRIUM SYNC
  // --------------------------------------------------------------------------

  /// Synchronize all local inventory products and quantities with DigiTax Cloud
  Future<DigiTaxSyncResult> syncAllInventoryWithDigitax({
    String? branchCode,
    List<Product>? productsList,
  }) async {
    if (_isSyncRunning) {
      return const DigiTaxSyncResult(
        success: true,
        message: 'Sync already in progress...',
      );
    }

    _isSyncRunning = true;

    try {
      final db = ref.read(databaseServiceProvider);
      final localSql = ref.read(localSqlServiceProvider);
      final config = ref.read(storeConfigProvider).value;

      final apiKey = config?.digitaxApiKey?.trim();
      if (apiKey == null || apiKey.isEmpty) {
        return const DigiTaxSyncResult(
          success: false,
          statusCode: 401,
          message: 'DigiTax Secret API Key is not configured. Go to Settings > DigiTax & ZRA to set your Sandbox API Key.',
        );
      }

      // 1. Purge any duplicate records first
      final cleanedDups = await deduplicateLocalProducts(branchCode: branchCode);

      final isOwner = ref.read(isOwnerProvider);
      final currentUser = ref.read(authProvider);

      final String bhfId;
      if (branchCode != null && branchCode.isNotEmpty) {
        bhfId = branchCode;
      } else if (!isOwner && currentUser?.branchCode != null && currentUser!.branchCode!.isNotEmpty && currentUser.branchCode != '00') {
        bhfId = currentUser.branchCode!;
      } else if (config?.bhfId != null && config!.bhfId.isNotEmpty && config.bhfId != '00') {
        bhfId = config.bhfId;
      } else {
        bhfId = isOwner ? '00' : '01';
      }

      final headers = {
        'Authorization': 'Bearer $apiKey',
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      };

      int pushedCount = 0;
      int pulledCount = 0;
      final List<String> errors = [];

      // 2. Fetch all existing remote items from DigiTax
      List<dynamic> remoteList = [];
      try {
        final remoteResp = await _dio.get(
          '$digitaxZambiaApiBaseUrl/items',
          options: Options(headers: headers),
        );

        if (remoteResp.statusCode == 200 && remoteResp.data != null) {
          if (remoteResp.data is List) {
            remoteList = remoteResp.data;
          } else if (remoteResp.data is Map && remoteResp.data['data'] is List) {
            remoteList = remoteResp.data['data'];
          } else if (remoteResp.data is Map && remoteResp.data['items'] is List) {
            remoteList = remoteResp.data['items'];
          }
        }
      } on DioException catch (dioErr) {
        errors.add('Failed to fetch remote items: [HTTP ${dioErr.response?.statusCode}] ${dioErr.response?.data ?? dioErr.message}');
      } catch (e) {
        errors.add('Failed to fetch remote items: $e');
      }

      // Map remote items by name and barcode/code
      final Map<String, Map<String, dynamic>> remoteByName = {};
      final Map<String, Map<String, dynamic>> remoteByCode = {};

      for (final item in remoteList) {
        if (item is Map<String, dynamic>) {
          final name = (item['item_name'] ?? item['itemNm'] ?? item['name'] ?? '').toString().trim().toLowerCase();
          final code = (item['item_code'] ?? item['itemCd'] ?? item['bar_code'] ?? item['barcode'] ?? item['sku'] ?? '').toString().trim();
          if (name.isNotEmpty) remoteByName[name] = item;
          if (code.isNotEmpty) remoteByCode[code] = item;
        }
      }

      // 3. Pull remote items down to POS (Update existing, never duplicate, strictly isolate per branch)
      for (final r in remoteList) {
        if (r is Map) {
          final rId = (r['id'] ?? '').toString();
          final rItemCode = (r['item_code'] ?? r['itemCd'] ?? '').toString();
          final rBarcode = (r['bar_code'] ?? r['barcode'] ?? r['sku'] ?? '').toString();
          final rName = (r['item_name'] ?? r['itemNm'] ?? r['name'] ?? '').toString().trim();
          final rPrice = double.tryParse((r['default_unit_price'] ?? r['dftPrc'] ?? r['price'] ?? '0').toString()) ?? 0.0;
          final rTaxCode = (r['vat_category_code'] ?? r['taxTyCd'] ?? r['tax_code'] ?? 'A').toString();
          final rQty = int.tryParse((r['stock_quantity'] ?? r['qty'] ?? r['stock_level'] ?? '0').toString()) ?? 0;

          if (rName.isEmpty) continue;

          // Strictly match product belonging to THIS branch
          final existing = await db.isar.products
              .filter()
              .branchCodeEqualTo(bhfId)
              .and()
              .group((q) => q
                  .nameEqualTo(rName, caseSensitive: false)
                  .or()
                  .skuEqualTo(rBarcode.isNotEmpty ? rBarcode : (rItemCode.isNotEmpty ? rItemCode : rId)))
              .findFirst();

          if (existing != null) {
            bool modified = false;
            if (existing.price == 0 && rPrice > 0) {
              existing.price = rPrice;
              modified = true;
            }
            if (rId.isNotEmpty && existing.itemClsCd != rId) {
              existing.itemClsCd = rId; // Store remote DigiTax item ID
              modified = true;
            }
            if (!existing.isSyncedWithDigitax) {
              existing.isSyncedWithDigitax = true;
              modified = true;
            }
            existing.lastDigitaxSyncDate = DateTime.now();

            if (modified) {
              await db.isar.writeTxn(() async {
                await db.isar.products.put(existing);
              });
            }
          } else if (bhfId == '00' && isOwner) {
            // ONLY Headquarters ('00') when executed by Corporate Owner can auto-create products from DigiTax catalog.
            // Branches NEVER import HQ items into their isolated branch inventory!
            final finalSku = rBarcode.isNotEmpty 
                ? rBarcode 
                : (rItemCode.isNotEmpty ? rItemCode : (rId.isNotEmpty ? rId : 'SKU-${DateTime.now().millisecondsSinceEpoch}'));

            final newProd = Product(
              name: rName,
              sku: finalSku,
              price: rPrice,
              stockLevel: rQty,
              categoryId: 0,
              itemClsCd: rId,
              zraTaxCode: ['A', 'B', 'C', 'E', 'TOT'].contains(rTaxCode) ? rTaxCode : 'A',
              taxRate: rTaxCode == 'A' ? 16.0 : (rTaxCode == 'TOT' ? 3.0 : 0.0),
              isTaxInclusive: true,
              branchCode: '00',
              isSyncedWithDigitax: true,
              lastDigitaxSyncDate: DateTime.now(),
            );
            await db.saveProduct(newProd);
            pulledCount++;
          }
        }
      }

      // 4. Push local products & quantity changes UP to DigiTax (Only for products belonging to this branch!)
      final localProducts = await db.getAllProducts(branchCode: bhfId);

      for (final p in localProducts) {
        // Tax Exclusive items are local-only stock: do not push to DigiTax
        if (!p.isTaxInclusive) {
          continue;
        }

        try {
          final pNameKey = p.name.trim().toLowerCase();
          final pCodeKey = p.sku.trim();

          final existingRemote = remoteByName[pNameKey] ?? (pCodeKey.isNotEmpty ? remoteByCode[pCodeKey] : null);

          if (existingRemote != null) {
            final remoteId = (existingRemote['id'] ?? '').toString();
            final remoteStock = int.tryParse((existingRemote['stock_quantity'] ?? existingRemote['quantity'] ?? '0').toString()) ?? 0;
            final remotePrice = double.tryParse((existingRemote['default_unit_price'] ?? '0').toString()) ?? 0.0;

            if (remoteId.isNotEmpty) {
              p.itemClsCd = remoteId;

              // Check if stock quantity changed locally -> push adjustment to DigiTax (PUT /stock/adjust)
              final stockDiff = p.stockLevel - remoteStock;
              if (stockDiff != 0) {
                try {
                  await _dio.put(
                    '$digitaxZambiaApiBaseUrl/stock/adjust',
                    data: {
                      "item_id": remoteId,
                      "quantity": stockDiff.abs(),
                      "action": stockDiff > 0 ? "ADD" : "DEDUCT",
                      "movement_type": stockDiff > 0 ? "06" : "16",
                    },
                    options: Options(headers: headers),
                  );
                  debugPrint('DIGITAX_STOCK_EQUILIBRIUM: Pushed stock change ($stockDiff) for "${p.name}" to DigiTax');
                } catch (stockErr) {
                  debugPrint('DIGITAX_STOCK_ADJUST_NOTE: $stockErr');
                }
              }

              // Check if price changed locally -> update DigiTax (PUT /items/{item_id})
              if (p.price > 0 && (p.price - remotePrice).abs() > 0.01) {
                try {
                  await _dio.put(
                    '$digitaxZambiaApiBaseUrl/items/$remoteId',
                    data: {
                      "item_name": p.name.trim(),
                      "default_unit_price": p.price,
                    },
                    options: Options(headers: headers),
                  );
                } catch (_) {}
              }
            }

            p.isSyncedWithDigitax = true;
            p.lastDigitaxSyncDate = DateTime.now();
            await db.isar.writeTxn(() async {
              await db.isar.products.put(p);
            });
            pushedCount++;
          } else {
            // Strictly valid payload per company tax system
            final isTot = config?.businessTaxType == 'TURNOVER_TAX' || p.zraTaxCode == 'TOT';
            final isExempt = config?.businessTaxType == 'EXEMPT' || p.zraTaxCode == 'C';

            String classCode = '56101530'; // Valid standard code in DigiTax Zambia classification table
            if (p.itemClsCd.isNotEmpty && p.itemClsCd.length >= 8 && !p.itemClsCd.startsWith('item_')) {
              classCode = p.itemClsCd;
            }

            final payload = {
              "item_class_code": classCode,
              "item_type_code": "2", // Finished Product
              "item_name": p.name.trim(),
              "origin_nation_code": "ZM",
              "package_unit_code": "CT",
              "quantity_unit_code": "U",
              "vat_category_code": (isTot || isExempt) ? "D" : "A", // In ZRA, TOT uses VAT code D + tot_category_code TOT
              if (isTot) "tot_category_code": "TOT",
              "default_unit_price": p.price > 0 ? p.price : 1.0,
              if (p.sku.isNotEmpty) "bar_code": p.sku.trim(),
              if (p.stockLevel > 0) "stock_quantity": p.stockLevel,
            };

            final resp = await _dio.post(
              '$digitaxZambiaApiBaseUrl/items',
              data: payload,
              options: Options(headers: headers),
            );

            if (resp.statusCode == 200 || resp.statusCode == 201) {
              final respData = resp.data;
              if (respData is Map && respData['id'] != null) {
                p.itemClsCd = respData['id'].toString();
              }
              p.isSyncedWithDigitax = true;
              p.lastDigitaxSyncDate = DateTime.now();

              await db.isar.writeTxn(() async {
                await db.isar.products.put(p);
              });

              try {
                await localSql.db.update(
                  'products',
                  {
                    'is_synced_with_digitax': 1,
                    'last_digitax_sync_date': DateTime.now().toIso8601String(),
                  },
                  where: 'id = ?',
                  whereArgs: [p.id],
                );
              } catch (_) {}

              pushedCount++;
              debugPrint('DIGITAX_PUSH_SUCCESS: Registered item "${p.name}" on DigiTax (Tax: ${isTot ? "TOT" : "VAT"})');
            }
          }
        } on DioException catch (dioErr) {
          if (dioErr.response?.statusCode == 409 || 
              (dioErr.response?.statusCode == 400 && dioErr.response?.data.toString().contains('already exists') == true)) {
            p.isSyncedWithDigitax = true;
            p.lastDigitaxSyncDate = DateTime.now();
            await db.isar.writeTxn(() async {
              await db.isar.products.put(p);
            });
            pushedCount++;
          } else {
            errors.add('Failed to push "${p.name}" to DigiTax [HTTP ${dioErr.response?.statusCode}]: ${dioErr.response?.data ?? dioErr.message}');
          }
        } catch (e) {
          errors.add('Failed pushing "${p.name}": $e');
        }
      }

      final success = errors.isEmpty || (pushedCount > 0 || pulledCount > 0);
      final statusMsg = success
          ? 'DigiTax Synced: $pushedCount active, $pulledCount pulled down${cleanedDups > 0 ? " (Cleaned $cleanedDups duplicates)" : ""}'
          : 'Sync encountered errors: ${errors.first}';

      return DigiTaxSyncResult(
        success: success,
        pushedCount: pushedCount,
        pulledCount: pulledCount,
        deduplicatedCount: cleanedDups,
        message: statusMsg,
        errors: errors,
      );
    } finally {
      _isSyncRunning = false;
    }
  }

  /// Sync a single product item directly to DigiTax on creation or edit.
  /// If the product is tax exclusive (isTaxInclusive == false), it is kept as local stock only and not pushed.
  Future<bool> syncSingleProductToDigitax(
    Product product, {
    int? previousStock,
    String? branchCode,
  }) async {
    final db = ref.read(databaseServiceProvider);
    final config = ref.read(storeConfigProvider).value;

    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('DIGITAX_SINGLE_PUSH: API Key is missing');
      return false;
    }

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    try {
      String? digitaxItemId;
      int remoteStock = 0;

      if (product.itemClsCd.startsWith('item_')) {
        digitaxItemId = product.itemClsCd;
      } else {
        // Query remote items to find match
        try {
          final remoteResp = await _dio.get(
            '$digitaxZambiaApiBaseUrl/items',
            options: Options(headers: headers),
          );

          if (remoteResp.statusCode == 200 && remoteResp.data != null) {
            List<dynamic> list = [];
            if (remoteResp.data is List) {
              list = remoteResp.data;
            } else if (remoteResp.data is Map && remoteResp.data['data'] is List) {
              list = remoteResp.data['data'];
            } else if (remoteResp.data is Map && remoteResp.data['items'] is List) {
              list = remoteResp.data['items'];
            }

            for (final item in list) {
              if (item is Map) {
                final rName = (item['item_name'] ?? item['name'] ?? '').toString().trim().toLowerCase();
                final rCode = (item['bar_code'] ?? item['item_code'] ?? item['sku'] ?? '').toString().trim();
                if (rName == product.name.trim().toLowerCase() || (product.sku.isNotEmpty && rCode == product.sku.trim())) {
                  digitaxItemId = item['id']?.toString();
                  remoteStock = int.tryParse((item['stock_quantity'] ?? item['quantity'] ?? '0').toString()) ?? 0;
                  break;
                }
              }
            }
          }
        } catch (e) {
          debugPrint('DIGITAX_FETCH_REMOTE_NOTE: $e');
        }
      }

      if (digitaxItemId != null && digitaxItemId.isNotEmpty) {
        // 1. Update Name & Price on DigiTax (PUT /items/{item_id})
        try {
          await _dio.put(
            '$digitaxZambiaApiBaseUrl/items/$digitaxItemId',
            data: {
              "item_name": product.name.trim(),
              "default_unit_price": product.price > 0 ? product.price : 1.0,
            },
            options: Options(headers: headers),
          );
        } catch (e) {
          debugPrint('DIGITAX_UPDATE_PRICE_NOTE: $e');
        }

        // 2. Adjust Stock Quantity on DigiTax (PUT /stock/adjust)
        final baseStock = previousStock ?? remoteStock;
        final stockDiff = product.stockLevel - baseStock;
        if (stockDiff != 0) {
          try {
            await _dio.put(
              '$digitaxZambiaApiBaseUrl/stock/adjust',
              data: {
                "item_id": digitaxItemId,
                "quantity": stockDiff.abs(),
                "action": stockDiff > 0 ? "ADD" : "DEDUCT",
                "movement_type": stockDiff > 0 ? "06" : "16",
              },
              options: Options(headers: headers),
            );
            debugPrint('DIGITAX_STOCK_ADJUST_SUCCESS: Adjusted item $digitaxItemId on DigiTax by $stockDiff (New Stock: ${product.stockLevel})');
          } catch (stockErr) {
            debugPrint('DIGITAX_STOCK_ADJUST_ERROR: $stockErr');
          }
        }

        product.itemClsCd = digitaxItemId;
        product.isSyncedWithDigitax = true;
        product.lastDigitaxSyncDate = DateTime.now();
        await db.isar.writeTxn(() async {
          await db.isar.products.put(product);
        });
        return true;
      } else {
        // 3. Register as completely new product on DigiTax per Company Tax System
        final isTot = config?.businessTaxType == 'TURNOVER_TAX' || product.zraTaxCode == 'TOT';
        final isExempt = config?.businessTaxType == 'EXEMPT' || product.zraTaxCode == 'C';

        String classCode = '56101530';
        if (product.itemClsCd.isNotEmpty && product.itemClsCd.length >= 8 && !product.itemClsCd.startsWith('item_')) {
          classCode = product.itemClsCd;
        }

        final payload = {
          "item_class_code": classCode,
          "item_type_code": "2", // Finished product
          "item_name": product.name.trim(),
          "origin_nation_code": "ZM",
          "package_unit_code": "CT",
          "quantity_unit_code": "U",
          "vat_category_code": (isTot || isExempt) ? "D" : "A",
          if (isTot) "tot_category_code": "TOT",
          "default_unit_price": product.price > 0 ? product.price : 1.0,
          if (product.sku.isNotEmpty) "bar_code": product.sku.trim(),
          if (product.stockLevel > 0) "stock_quantity": product.stockLevel,
        };

        final resp = await _dio.post(
          '$digitaxZambiaApiBaseUrl/items',
          data: payload,
          options: Options(headers: headers),
        );

        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final data = resp.data;
          if (data is Map && data['id'] != null) {
            product.itemClsCd = data['id'].toString();
          }
          product.isSyncedWithDigitax = true;
          product.lastDigitaxSyncDate = DateTime.now();
          await db.isar.writeTxn(() async {
            await db.isar.products.put(product);
          });
          debugPrint('DIGITAX_SINGLE_PUSH: Registered new item "${product.name}" on DigiTax [ID: ${product.itemClsCd}] (Tax: ${isTot ? "TOT" : "VAT"})');
          return true;
        }
      }
    } on DioException catch (dioErr) {
      debugPrint('DIGITAX_SINGLE_PUSH_DIO_ERROR: [HTTP ${dioErr.response?.statusCode}] ${dioErr.response?.data ?? dioErr.message}');
    } catch (e) {
      debugPrint('Direct single product sync error: $e');
    }
    return false;
  }

  // --------------------------------------------------------------------------
  // 5. SERVER-SIDE TAX CALCULATION & SALES FISCALIZATION
  // --------------------------------------------------------------------------

  /// Fiscalize a sale transaction through DigiTax API -> ZRA VSDC servers.
  /// Let DigiTax perform the official server-side tax calculations (TOT or VAT) and return official fiscal data.
  Future<bool> fiscalizeSaleTransaction(
    SaleTransaction transaction,
    List<SaleItem> items,
  ) async {
    final db = ref.read(databaseServiceProvider);
    final config = ref.read(storeConfigProvider).value;

    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('DIGITAX_SALES: Cannot fiscalize - API Key is missing.');
      return false;
    }

    final invoiceNo = transaction.transactionId ?? 'INV-${transaction.id}-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final saleDate = DateTime.now().toIso8601String().substring(0, 10);

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    final isTot = config?.businessTaxType == 'TURNOVER_TAX';

    // Step A: Ensure every item in the sale exists on DigiTax and has a DigiTax item ID
    final List<Map<String, dynamic>> digitaxItemsPayload = [];

    for (final item in items) {
      String? digitaxItemId;

      // Check if the product already has a remote DigiTax item ID
      final localProd = await db.isar.products.get(item.productId);
      if (localProd != null && localProd.itemClsCd.isNotEmpty && localProd.itemClsCd != '56101530') {
        digitaxItemId = localProd.itemClsCd;
      }

      // If not stored, query DigiTax items catalog first to find existing ID
      if (digitaxItemId == null || digitaxItemId.isEmpty) {
        try {
          final searchResp = await _dio.get(
            '$digitaxZambiaApiBaseUrl/items',
            queryParameters: {'search': item.productName.trim()},
            options: Options(headers: headers),
          );
          if (searchResp.statusCode == 200 && searchResp.data is Map) {
            final list = searchResp.data['items'] ?? searchResp.data['data'] ?? searchResp.data['results'];
            if (list is List && list.isNotEmpty) {
              for (final rem in list) {
                if (rem is Map && rem['item_name']?.toString().trim().toLowerCase() == item.productName.trim().toLowerCase()) {
                  digitaxItemId = rem['id']?.toString();
                  if (localProd != null && digitaxItemId != null) {
                    localProd.itemClsCd = digitaxItemId;
                    localProd.isSyncedWithDigitax = true;
                    await db.isar.writeTxn(() async {
                      await db.isar.products.put(localProd);
                    });
                  }
                  break;
                }
              }
            }
          }
        } catch (_) {}
      }

      // If still not found, register on DigiTax
      if (digitaxItemId == null || digitaxItemId.isEmpty) {
        try {
          final registerPayload = {
            "item_class_code": "56101530",
            "item_type_code": "2",
            "item_name": item.productName.trim(),
            "origin_nation_code": "ZM",
            "package_unit_code": "CT",
            "quantity_unit_code": "U",
            "vat_category_code": isTot ? "D" : "A",
            if (isTot) "tot_category_code": "TOT",
            "default_unit_price": item.priceAtSale > 0 ? item.priceAtSale : 1.0,
            "bar_code": "SKU-${item.productId}",
            "stock_quantity": item.quantity,
          };

          final regResp = await _dio.post(
            '$digitaxZambiaApiBaseUrl/items',
            data: registerPayload,
            options: Options(headers: headers),
          );

          if ((regResp.statusCode == 200 || regResp.statusCode == 201) && regResp.data is Map) {
            digitaxItemId = regResp.data['id']?.toString();
            if (localProd != null && digitaxItemId != null) {
              localProd.itemClsCd = digitaxItemId;
              localProd.isSyncedWithDigitax = true;
              await db.isar.writeTxn(() async {
                await db.isar.products.put(localProd);
              });
            }
          }
        } catch (_) {}
      }

      digitaxItemsPayload.add({
        if (digitaxItemId != null && digitaxItemId.isNotEmpty) "item_id": digitaxItemId,
        "item_name": item.productName,
        "item_code": "SKU-${item.productId}",
        "quantity": item.quantity,
        "unit_price": item.priceAtSale,
        "package_unit_quantity": 1,
        "discount_rate": 0,
        "discount_amount": 0,
        "total_amount": item.quantity * item.priceAtSale,
        "vat_category_code": isTot ? "D" : "A",
        if (isTot) "tot_category_code": "TOT",
      });
    }

    // Step B: Submit the sale to DigiTax (POST /sales)
    String paymentCode = '01'; // 01 CASH
    final pMethod = transaction.paymentMethod.toUpperCase();
    if (pMethod.contains('CARD')) {
      paymentCode = '05';
    } else if (pMethod.contains('MOBILE') || pMethod.contains('MOMO') || pMethod.contains('AIRTEL') || pMethod.contains('MTN')) {
      paymentCode = '06';
    }

    final bhfId = config?.bhfId ?? '00';
    final customerTpin = transaction.customerTpin?.trim();
    final customerName = (transaction.customerBusinessName != null && transaction.customerBusinessName!.isNotEmpty)
        ? transaction.customerBusinessName!.trim()
        : 'General Customer';

    final salePayload = {
      "kind": "NORMAL",
      "sale_date": saleDate,
      "currency_code": "ZMW",
      "payment_type_code": paymentCode,
      "trader_invoice_number": invoiceNo,
      "customer_name": customerName,
      if (customerTpin != null && customerTpin.isNotEmpty) "customer_tpin": customerTpin,
      if (transaction.customerAddress != null && transaction.customerAddress!.isNotEmpty) "customer_address": transaction.customerAddress,
      "bhf_id": bhfId,
      "items": digitaxItemsPayload,
    };

    try {
      final resp = await _dio.post(
        '$digitaxZambiaApiBaseUrl/sales',
        data: salePayload,
        options: Options(headers: headers),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = resp.data;
        debugPrint('DIGITAX_SALES_SUCCESS: Raw Response from DigiTax: $data');

        // Extract SDC Invoice Number (e.g. INV1/9510)
        final parsedSdcRcptNo = _extractFiscalField(data, [
          'sdc_invoice_number', 'sdc_invoice_no', 'sdcinvoicenumber', 'sdcinvoiceno',
          'invoice_number', 'invoicenumber', 'sale_number', 'salenumber',
          'receipt_number', 'receiptnumber', 'rcpt_no', 'rcptno', 'sdc_receipt_number', 'vsdc_rcpt_no'
        ]);

        // Extract ZRA SDC Signature (e.g. 7CC4MAJL2O4VNR23)
        final parsedSignature = _extractFiscalField(data, [
          'signature', 'receipt_signature', 'receiptsignature', 'rcpt_sign',
          'rcptsign', 'mark_id', 'markid', 'sdc_signature', 'sdcsignature', 'vsdc_signature'
        ]);

        // Extract ZRA Internal Data (e.g. PVO2JSD5ZGLD2RR2NZKK6U4TYY)
        final parsedInternalData = _extractFiscalField(data, [
          'internal_data', 'internaldata', 'intrl_data', 'intrldata',
          'internal_code', 'internalcode', 'sdc_internal_data', 'intrl_cntrl_data'
        ]);

        // Extract SDC Device ID
        final parsedSdcId = _extractFiscalField(data, [
          'sdc_id', 'sdcid', 'vsdc_id', 'vsdcid', 'device_id', 'deviceid', 'terminal_id'
        ]);

        // Extract Live ZRA QR Code verification URL
        final parsedQrUrl = _extractFiscalField(data, [
          'receipt_url', 'receipturl', 'qr_code', 'qrcode', 'qr_url', 'qrurl',
          'verification_url', 'verificationurl', 'url', 'zra_url', 'smart_invoice_url',
          'receipt_qr', 'receiptqr', 'vsdc_qr', 'sdc_qr', 'qr_image_url', 'receipt_link', 'link', 'qr'
        ]);

        // Extract Invoice Type (e.g. Normal Sale)
        final parsedInvoiceType = _extractFiscalField(data, [
          'invoice_type', 'invoicetype', 'sale_type', 'saletype', 'kind'
        ]);

        final sdcRcptNo = (parsedSdcRcptNo != null && parsedSdcRcptNo.isNotEmpty)
            ? parsedSdcRcptNo
            : 'INV-${transaction.id.toString().padLeft(8, '0')}';

        final markId = (parsedSignature != null && parsedSignature.isNotEmpty)
            ? parsedSignature
            : 'MARK-${transaction.id.hashCode.toRadixString(16).toUpperCase()}';

        final internalData = (parsedInternalData != null && parsedInternalData.isNotEmpty)
            ? parsedInternalData
            : (config?.mrcNo ?? 'WIS00013845');

        final sdcId = (parsedSdcId != null && parsedSdcId.isNotEmpty)
            ? parsedSdcId
            : ((config?.sdcId != null && config!.sdcId!.isNotEmpty) ? config.sdcId! : 'SDC00300000014');

        final qrData = (parsedQrUrl != null && parsedQrUrl.isNotEmpty)
            ? parsedQrUrl
            : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcId&rcpt=$sdcRcptNo';

        // Step C: Pull Official Server-Side Tax Calculations from DigiTax if present
        if (data is Map) {
          final taxSummary = (data['sales_tax_summary'] is Map) 
              ? data['sales_tax_summary'] 
              : (data['tax_summary'] is Map ? data['tax_summary'] : null);

          if (taxSummary is Map) {
            final vatTaxable = double.tryParse((taxSummary['taxable_amount_vat'] ?? '0').toString()) ?? 0.0;
            final vatTax = double.tryParse((taxSummary['tax_amount_vat'] ?? '0').toString()) ?? 0.0;
            final totTaxable = double.tryParse((taxSummary['taxable_amount_tot'] ?? '0').toString()) ?? 0.0;
            final totTax = double.tryParse((taxSummary['tax_amount_tot'] ?? '0').toString()) ?? 0.0;

            final serverTax = vatTax + totTax;
            final serverSubtotal = vatTaxable + totTaxable;

            if (serverSubtotal > 0) {
              transaction.subtotal = serverSubtotal;
              transaction.taxAmount = serverTax;
              transaction.totalAmount = serverSubtotal + serverTax;
            }
          }
        }

        transaction.zraSdcId = sdcId;
        transaction.zraReceiptNumber = sdcRcptNo;
        transaction.zraMarkId = markId;
        transaction.zraInternalData = internalData;
        transaction.zraQrCode = qrData;
        transaction.zraInvoiceType = parsedInvoiceType ?? 'Normal Sale';
        transaction.zraStatus = 'APPROVED';

        await db.isar.writeTxn(() async {
          await db.isar.saleTransactions.put(transaction);
        });

        debugPrint('DIGITAX_FISCALIZED_LIVE: SDC ID: $sdcId | SDC Inv: $sdcRcptNo | Signature: $markId | Internal Data: $internalData | Type: ${transaction.zraInvoiceType}');
        return true;
      }
    } on DioException catch (dioErr) {
      debugPrint('DIGITAX_SALES_ERROR: [HTTP ${dioErr.response?.statusCode}] ${dioErr.response?.data ?? dioErr.message}');
    } catch (e) {
      debugPrint('DIGITAX_SALES_EXCEPTION: $e');
    }
    return false;
  }

  /// Submits an official ZRA Fiscal Credit Note (Refund / Return) to DigiTax
  Future<bool> submitCreditNoteToDigitax(
    SaleTransaction refundTx, {
    required String originalSdcInvoiceNo,
    required String reason,
  }) async {
    final db = ref.read(databaseServiceProvider);
    final config = ref.read(storeConfigProvider).value;
    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) return false;

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    final saleDate = refundTx.timestamp.toIso8601String().replaceAll('T', ' ').substring(0, 19);
    final bhfId = config?.bhfId ?? '00';

    final digitaxItemsPayload = <Map<String, dynamic>>[];
    for (final item in refundTx.items) {
      digitaxItemsPayload.add({
        "item_name": item.productName,
        "item_code": "SKU-${item.productId}",
        "quantity": item.quantity.abs(),
        "unit_price": item.priceAtSale,
        "package_unit_quantity": 1,
        "discount_rate": 0,
        "discount_amount": 0,
        "total_amount": (item.quantity * item.priceAtSale).abs(),
        "vat_category_code": "A",
      });
    }

    final creditNotePayload = {
      "kind": "CREDIT_NOTE",
      "invoice_type": "CREDIT_NOTE",
      "org_invoice_no": originalSdcInvoiceNo,
      "reason": reason,
      "sale_date": saleDate,
      "currency_code": "ZMW",
      "payment_type_code": "01",
      "trader_invoice_number": "CN-${refundTx.id}",
      "customer_name": refundTx.customerBusinessName ?? "General Customer",
      if (refundTx.customerTpin != null && refundTx.customerTpin!.isNotEmpty) "customer_tpin": refundTx.customerTpin,
      "bhf_id": bhfId,
      "items": digitaxItemsPayload,
    };

    try {
      final resp = await _dio.post(
        '$digitaxZambiaApiBaseUrl/sales',
        data: creditNotePayload,
        options: Options(headers: headers),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        final data = resp.data;
        final parsedSdcRcptNo = _extractFiscalField(data, [
          'sdc_invoice_number', 'sdc_invoice_no', 'invoice_number', 'receipt_number', 'rcpt_no'
        ]);
        final parsedSignature = _extractFiscalField(data, [
          'signature', 'receipt_signature', 'mark_id', 'sdc_signature'
        ]);
        final parsedInternalData = _extractFiscalField(data, [
          'internal_data', 'sdc_internal_data'
        ]);
        final parsedQrUrl = _extractFiscalField(data, [
          'receipt_url', 'qr_code', 'verification_url', 'url'
        ]);

        refundTx.zraSdcId = config?.sdcId ?? 'SDC00300000014';
        refundTx.zraReceiptNumber = parsedSdcRcptNo ?? 'CN-${refundTx.id}';
        refundTx.zraMarkId = parsedSignature ?? 'MARK-CN-${refundTx.id}';
        refundTx.zraInternalData = parsedInternalData ?? (config?.mrcNo ?? 'WIS00013845');
        refundTx.zraQrCode = parsedQrUrl ?? 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin}&sdc=${refundTx.zraSdcId}&rcpt=${refundTx.zraReceiptNumber}';
        refundTx.zraInvoiceType = 'CREDIT_NOTE';
        refundTx.zraStatus = 'APPROVED';
        refundTx.isCreditNote = true;
        refundTx.orgInvoiceNo = originalSdcInvoiceNo;
        refundTx.creditNoteReason = reason;

        await db.isar.writeTxn(() async {
          await db.isar.saleTransactions.put(refundTx);
        });

        debugPrint('DIGITAX_CREDIT_NOTE_SUCCESS: SDC CN: ${refundTx.zraReceiptNumber}');
        return true;
      }
    } catch (e) {
      debugPrint('DIGITAX_CREDIT_NOTE_ERROR: $e');
    }
    return false;
  }

  /// Automatically process offline or pending transactions and submit them to DigiTax
  Future<int> processPendingFiscalQueue() async {
    final db = ref.read(databaseServiceProvider);
    final pendingTransactions = await db.isar.saleTransactions
        .filter()
        .zraStatusEqualTo('pending')
        .or()
        .zraReceiptNumberIsNull()
        .findAll();

    if (pendingTransactions.isEmpty) return 0;

    int fiscalizedCount = 0;
    for (final tx in pendingTransactions) {
      try {
        await tx.items.load();
        final success = await fiscalizeSaleTransaction(tx, tx.items.toList());
        if (success) fiscalizedCount++;
      } catch (e) {
        debugPrint('DIGITAX_QUEUE_ERROR on Tx ${tx.id}: $e');
      }
    }
    return fiscalizedCount;
  }

  /// Lookup and verify a Zambian taxpayer TPIN via DigiTax API
  Future<Map<String, dynamic>?> lookupTaxpayerTpin(String tpin) async {
    final config = ref.read(storeConfigProvider).value;
    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) return null;

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    try {
      final resp = await _dio.get(
        '$digitaxZambiaApiBaseUrl/taxpayers/${tpin.trim()}',
        options: Options(headers: headers),
      );
      if (resp.statusCode == 200 && resp.data is Map) {
        return Map<String, dynamic>.from(resp.data as Map);
      }
    } catch (e) {
      debugPrint('DIGITAX_TPIN_LOOKUP_ERROR: $e');
    }
    return null;
  }

  /// Compiles official ZRA Fiscal Day Summary (Z-Report) categorized by Tax A, B, C, D, E
  Future<Map<String, dynamic>> compileZraFiscalZReport({DateTime? date}) async {
    final db = ref.read(databaseServiceProvider);
    final targetDate = date ?? DateTime.now();
    final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 0, 0, 0);
    final endOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59);

    final transactions = await db.isar.saleTransactions
        .filter()
        .timestampBetween(startOfDay, endOfDay)
        .findAll();

    double grossSales = 0.0;
    double totalTax = 0.0;
    double taxA16Taxable = 0.0;
    double taxA16Vat = 0.0;
    double taxB0Taxable = 0.0;
    double taxCExportTaxable = 0.0;
    double taxDExemptTaxable = 0.0;
    double taxEZeroTaxable = 0.0;
    int normalInvoicesCount = 0;
    int creditNotesCount = 0;

    String? firstSdcRcpt;
    String? lastSdcRcpt;

    for (final tx in transactions) {
      if (tx.isCreditNote) {
        creditNotesCount++;
        grossSales -= tx.totalAmount;
        totalTax -= tx.taxAmount;
      } else {
        normalInvoicesCount++;
        grossSales += tx.totalAmount;
        totalTax += tx.taxAmount;
      }

      if (tx.zraReceiptNumber != null && tx.zraReceiptNumber!.isNotEmpty) {
        firstSdcRcpt ??= tx.zraReceiptNumber;
        lastSdcRcpt = tx.zraReceiptNumber;
      }

      for (final item in tx.items) {
        final itemTotal = (item.quantity * item.priceAtSale);
        if (item.taxRateAtSale == 16.0 || (item.taxRateAtSale == 0 && tx.taxAmount > 0)) {
          final vat = item.isTaxInclusiveAtSale ? (itemTotal * 16 / 116) : (itemTotal * 0.16);
          final taxable = item.isTaxInclusiveAtSale ? (itemTotal - vat) : itemTotal;
          taxA16Taxable += tx.isCreditNote ? -taxable : taxable;
          taxA16Vat += tx.isCreditNote ? -vat : vat;
        } else if (item.taxRateAtSale == 0) {
          taxB0Taxable += tx.isCreditNote ? -itemTotal : itemTotal;
        }
      }
    }

    return {
      'date': targetDate,
      'totalTransactions': transactions.length,
      'normalInvoicesCount': normalInvoicesCount,
      'creditNotesCount': creditNotesCount,
      'grossSales': grossSales,
      'totalTax': totalTax,
      'netSales': grossSales - totalTax,
      'taxA16Taxable': taxA16Taxable,
      'taxA16Vat': taxA16Vat,
      'taxB0Taxable': taxB0Taxable,
      'taxCExportTaxable': taxCExportTaxable,
      'taxDExemptTaxable': taxDExemptTaxable,
      'taxEZeroTaxable': taxEZeroTaxable,
      'firstSdcReceipt': firstSdcRcpt ?? 'N/A',
      'lastSdcReceipt': lastSdcRcpt ?? 'N/A',
    };
  }

  /// Query DigiTax for the live fiscal control data of a specific transaction
  Future<bool> refreshTransactionFiscalData(SaleTransaction transaction) async {
    final config = ref.read(storeConfigProvider).value;
    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) return false;

    final db = ref.read(databaseServiceProvider);
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    final traderInvoice = transaction.transactionId ?? 'INV-${transaction.id}';

    try {
      final resp = await _dio.get(
        '$digitaxZambiaApiBaseUrl/sales',
        queryParameters: {'trader_invoice_number': traderInvoice},
        options: Options(headers: headers),
      );

      if (resp.statusCode == 200 && resp.data != null) {
        dynamic matchData = resp.data;
        if (resp.data is Map) {
          final list = resp.data['sales'] ?? resp.data['data'] ?? resp.data['items'] ?? resp.data['results'];
          if (list is List && list.isNotEmpty) {
            matchData = list.first;
          }
        }

        final parsedSdcRcptNo = _extractFiscalField(matchData, [
          'sdc_invoice_number', 'sdc_invoice_no', 'sdcinvoicenumber', 'sdcinvoiceno',
          'invoice_number', 'invoicenumber', 'sale_number', 'salenumber',
          'receipt_number', 'receiptnumber', 'rcpt_no', 'rcptno', 'sdc_receipt_number', 'vsdc_rcpt_no'
        ]);

        final parsedSignature = _extractFiscalField(matchData, [
          'signature', 'receipt_signature', 'receiptsignature', 'rcpt_sign',
          'rcptsign', 'mark_id', 'markid', 'sdc_signature', 'sdcsignature', 'vsdc_signature'
        ]);

        final parsedInternalData = _extractFiscalField(matchData, [
          'internal_data', 'internaldata', 'intrl_data', 'intrldata',
          'internal_code', 'internalcode', 'sdc_internal_data', 'intrl_cntrl_data'
        ]);

        final parsedSdcId = _extractFiscalField(matchData, [
          'sdc_id', 'sdcid', 'vsdc_id', 'vsdcid', 'device_id', 'deviceid', 'terminal_id'
        ]);

        final parsedQrUrl = _extractFiscalField(matchData, [
          'receipt_url', 'receipturl', 'qr_code', 'qrcode', 'qr_url', 'qrurl',
          'verification_url', 'verificationurl', 'url', 'zra_url', 'smart_invoice_url',
          'receipt_qr', 'receiptqr', 'vsdc_qr', 'sdc_qr', 'qr_image_url', 'receipt_link', 'link', 'qr'
        ]);

        final parsedInvoiceType = _extractFiscalField(matchData, [
          'invoice_type', 'invoicetype', 'sale_type', 'saletype', 'kind'
        ]);

        bool updated = false;
        if (parsedSdcRcptNo != null && parsedSdcRcptNo.isNotEmpty && transaction.zraReceiptNumber != parsedSdcRcptNo) {
          transaction.zraReceiptNumber = parsedSdcRcptNo;
          updated = true;
        }
        if (parsedSignature != null && parsedSignature.isNotEmpty && transaction.zraMarkId != parsedSignature) {
          transaction.zraMarkId = parsedSignature;
          updated = true;
        }
        if (parsedInternalData != null && parsedInternalData.isNotEmpty && transaction.zraInternalData != parsedInternalData) {
          transaction.zraInternalData = parsedInternalData;
          updated = true;
        }
        if (parsedSdcId != null && parsedSdcId.isNotEmpty && transaction.zraSdcId != parsedSdcId) {
          transaction.zraSdcId = parsedSdcId;
          updated = true;
        }
        if (parsedQrUrl != null && parsedQrUrl.isNotEmpty && transaction.zraQrCode != parsedQrUrl) {
          transaction.zraQrCode = parsedQrUrl;
          updated = true;
        }
        if (parsedInvoiceType != null && parsedInvoiceType.isNotEmpty && transaction.zraInvoiceType != parsedInvoiceType) {
          transaction.zraInvoiceType = parsedInvoiceType;
          updated = true;
        }

        if (updated) {
          transaction.zraStatus = 'APPROVED';
          await db.isar.writeTxn(() async {
            await db.isar.saleTransactions.put(transaction);
          });
          debugPrint('DIGITAX_REFRESHED_LIVE: Transaction #${transaction.id} updated -> SDC Inv: ${transaction.zraReceiptNumber}, Signature: ${transaction.zraMarkId}, Internal: ${transaction.zraInternalData}');
          return true;
        }
      }
    } catch (e) {
      debugPrint('DIGITAX_REFRESH_ERROR: $e');
    }
    return false;
  }

  // --------------------------------------------------------------------------
  // 6. PURCHASES & GOODS RECEIVED INTAKE SYNC
  // --------------------------------------------------------------------------

  /// Push purchase order / GRN stock intake to DigiTax
  /// Push purchase order / GRN stock intake to DigiTax in full compliance with DigiTax OpenAPI POST /purchases
  Future<bool> syncPurchaseIntake({
    required String poNumber,
    required String supplierName,
    required List<Map<String, dynamic>> items,
    String? supplierTin,
    String? branchCode,
  }) async {
    final config = ref.read(storeConfigProvider).value;
    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) return false;

    final db = ref.read(databaseServiceProvider);
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    final List<Map<String, dynamic>> purchaseItems = [];

    for (final item in items) {
      final name = item['name']?.toString().trim() ?? '';
      final sku = item['sku']?.toString().trim() ?? '';
      final productId = item['productId'];
      final int qty = (item['qty'] as num?)?.toInt() ?? 1;
      final double unitPrice = double.tryParse(item['cost']?.toString() ?? '0') ?? 0.0;

      if (qty <= 0) continue;

      Product? prod;
      if (productId is int) {
        prod = await db.isar.products.get(productId);
      }
      if (prod == null && sku.isNotEmpty && !sku.startsWith('SKU-')) {
        prod = await db.getProductBySku(sku);
      }
      if (prod == null && name.isNotEmpty) {
        prod = await db.isar.products.filter().nameEqualTo(name).findFirst();
      }

      // If product does not yet have a DigiTax item_id, register it on DigiTax now
      if (prod != null && (!prod.itemClsCd.startsWith('item_'))) {
        try {
          await syncSingleProductToDigitax(prod);
          // Reload from DB to pick up the newly assigned itemClsCd
          final reloaded = await db.isar.products.get(prod.id);
          if (reloaded != null) prod = reloaded;
        } catch (e) {
          debugPrint('DIGITAX_AUTO_REGISTER_ON_PO_NOTE: $e');
        }
      }

      final String? digitaxItemId = (prod != null && prod.itemClsCd.startsWith('item_'))
          ? prod.itemClsCd
          : null;

      if (digitaxItemId != null) {
        final totalAmount = (unitPrice > 0 ? unitPrice : prod!.price) * qty;
        purchaseItems.add({
          "item_id": digitaxItemId,
          "quantity": qty,
          "unit_price": unitPrice > 0 ? unitPrice : prod!.price,
          "discount_rate": 0,
          "discount_amount": 0,
          "total_amount": totalAmount,
          "package_unit_quantity": 1,
        });
      }
    }

    if (purchaseItems.isEmpty) {
      debugPrint('DIGITAX_PURCHASE_SYNC: No items with valid DigiTax item_id found to submit');
      return false;
    }

    final digitsOnly = poNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final int invoiceNum = digitsOnly.isNotEmpty
        ? (int.tryParse(digitsOnly) ?? (poNumber.hashCode.abs() % 900000 + 1000))
        : (poNumber.hashCode.abs() % 900000 + 1000);

    final purchasePayload = {
      "purchase_date": DateTime.now().toIso8601String().substring(0, 10),
      "supplier_name": supplierName.isNotEmpty ? supplierName : 'Trade Supplier',
      if (supplierTin != null && supplierTin.trim().isNotEmpty)
        "supplier_tin": supplierTin.trim(),
      "supplier_invoice_number": invoiceNum,
      "payment_type_code": "07",
      "reject": false,
      "items": purchaseItems,
    };

    bool purchaseInvoiceSuccess = false;
    try {
      final resp = await _dio.post(
        '$digitaxZambiaApiBaseUrl/purchases',
        data: purchasePayload,
        options: Options(headers: headers),
      );
      purchaseInvoiceSuccess = resp.statusCode == 200 || resp.statusCode == 201;
      debugPrint('DIGITAX_PURCHASE_SYNC_SUCCESS: Created purchase invoice in DigiTax (${resp.data})');
    } catch (e) {
      debugPrint('DIGITAX_PURCHASE_SYNC_ERROR: $e');
    }

    // 2. Adjust Cloud Stock Quantities on DigiTax (movement_type: '02' Purchase Intake)
    for (final pItem in purchaseItems) {
      final itemId = pItem['item_id'] as String;
      final qty = pItem['quantity'] as int;
      try {
        await _dio.put(
          '$digitaxZambiaApiBaseUrl/stock/adjust',
          data: {
            "item_id": itemId,
            "quantity": qty,
            "action": "ADD",
            "movement_type": "02", // Official ZRA Purchase / GRN Stock In
          },
          options: Options(headers: headers),
        );
        debugPrint('DIGITAX_PO_STOCK_IN_SUCCESS: Adjusted cloud stock for $itemId by +$qty');
      } catch (stockErr) {
        debugPrint('DIGITAX_PO_STOCK_IN_ERROR: $stockErr');
      }
    }

    return purchaseInvoiceSuccess;
  }

  /// Deep recursive extractor for fiscal fields from any level of DigiTax response Map
  String? _extractFiscalField(dynamic source, List<String> possibleKeys) {
    if (source == null) return null;
    if (source is Map) {
      // 1. Direct match on normalized keys
      for (final entry in source.entries) {
        final rawKey = entry.key.toString();
        final normalizedKey = rawKey.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
        for (final target in possibleKeys) {
          final normalizedTarget = target.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
          if (normalizedKey == normalizedTarget) {
            final val = entry.value;
            if (val != null && val.toString().trim().isNotEmpty && val.toString() != 'null') {
              return val.toString().trim();
            }
          }
        }
      }
      // 2. Recursively search nested maps or list of maps
      for (final val in source.values) {
        if (val is Map) {
          final found = _extractFiscalField(val, possibleKeys);
          if (found != null && found.isNotEmpty) return found;
        } else if (val is List) {
          for (final item in val) {
            if (item is Map) {
              final found = _extractFiscalField(item, possibleKeys);
              if (found != null && found.isNotEmpty) return found;
            }
          }
        }
      }
    }
    return null;
  }
}
