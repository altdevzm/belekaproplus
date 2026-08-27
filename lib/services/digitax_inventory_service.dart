import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/local_sql_service.dart';
import 'package:beleka_pos/services/printer_service.dart';
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
  Timer? _fiscalQueueTimer;

  // Official DigiTax Zambia API Base URL from zm.docs.digitax.tech OpenAPI spec
  static const String digitaxZambiaApiBaseUrl = 'https://api.digitax.tech/zm/v1';

  DigiTaxInventoryService({required this.ref}) {
    _startPeriodicFiscalWorker();
  }

  void _startPeriodicFiscalWorker() {
    _fiscalQueueTimer?.cancel();
    _fiscalQueueTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      final config = ref.read(storeConfigProvider).value;
      if (config?.digitaxApiKey?.trim().isNotEmpty == true) {
        await processPendingFiscalQueue();
      }
    });
  }

  void dispose() {
    _fiscalQueueTimer?.cancel();
    _fiscalQueueTimer = null;
  }

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

      // Map remote items by DigiTax ID, name, and barcode/code (used by push section)
      final Map<String, Map<String, dynamic>> remoteById = {};
      final Map<String, Map<String, dynamic>> remoteByName = {};
      final Map<String, Map<String, dynamic>> remoteByCode = {};

      for (final item in remoteList) {
        if (item is Map<String, dynamic>) {
          final id   = (item['id'] ?? '').toString();
          final name = (item['item_name'] ?? item['itemNm'] ?? item['name'] ?? '').toString().trim().toLowerCase();
          final code = (item['item_code'] ?? item['itemCd'] ?? item['bar_code'] ?? item['barcode'] ?? item['sku'] ?? '').toString().trim();
          if (id.isNotEmpty)   remoteById[id]     = item;
          if (name.isNotEmpty) remoteByName[name] = item;
          if (code.isNotEmpty) remoteByCode[code] = item;
        }
      }

      // ──────────────────────────────────────────────────────────────────────────
      // 3. Pull — Branch-Isolated Sync
      //
      // IMPORTANT: DigiTax GET /items returns ALL items for the business (confirmed
      // from official API docs — no bhf_id filter parameter exists).
      // The shared catalog must be isolated here in the local Isar DB using branchCode.
      //
      // Rules:
      //  • Branch managers ('01', '02', …): ONLY update products that were already
      //    pushed BY THIS BRANCH, matched exclusively by DigiTax item id (itemClsCd).
      //    Name-matching is disabled to prevent cross-contamination with identically-
      //    named HQ / other-branch products.
      //  • HQ owner ('00'): can match by DigiTax ID first, then fall back to name/
      //    barcode, and can auto-create new products from the master catalog.
      // ──────────────────────────────────────────────────────────────────────────
      for (final r in remoteList) {
        if (r is! Map) continue;

        final rId     = (r['id'] ?? '').toString();
        final rItemCode = (r['item_code'] ?? r['itemCd'] ?? '').toString();
        final rBarcode  = (r['bar_code'] ?? r['barcode'] ?? r['sku'] ?? '').toString();
        final rName   = (r['item_name'] ?? r['itemNm'] ?? r['name'] ?? '').toString().trim();
        final rPrice  = double.tryParse((r['default_unit_price'] ?? r['dftPrc'] ?? r['price'] ?? '0').toString()) ?? 0.0;
        final rTaxCode = (r['vat_category_code'] ?? r['taxTyCd'] ?? r['tax_code'] ?? 'A').toString();
        final rQty    = int.tryParse((r['stock_quantity'] ?? r['qty'] ?? r['stock_level'] ?? '0').toString()) ?? 0;

        if (rName.isEmpty) continue;

        if (bhfId != '00') {
          // ── BRANCH MANAGER ── strict isolation ────────────────────────────
          // Only update products already linked to this DigiTax item (by id).
          if (rId.isEmpty) continue;
          final existingByDtId = await db.isar.products
              .filter()
              .branchCodeEqualTo(bhfId)
              .and()
              .itemClsCdEqualTo(rId)
              .findFirst();

          if (existingByDtId != null) {
            bool modified = false;
            if (existingByDtId.price == 0 && rPrice > 0) {
              existingByDtId.price = rPrice;
              modified = true;
            }
            if (!existingByDtId.isSyncedWithDigitax) {
              existingByDtId.isSyncedWithDigitax = true;
              modified = true;
            }
            existingByDtId.lastDigitaxSyncDate = DateTime.now();
            if (modified) {
              await db.isar.writeTxn(() async {
                await db.isar.products.put(existingByDtId);
              });
            }
            pulledCount++;
          }
          // No match by DigiTax ID → skip. Never create HQ items in branch DB.
        } else {
          // ── HQ OWNER ── can match broadly and auto-create ──────────────────
          // Priority 1: exact DigiTax item id (safest — no name collision risk)
          Product? existing;
          if (rId.isNotEmpty) {
            existing = await db.isar.products
                .filter()
                .branchCodeEqualTo('00')
                .and()
                .itemClsCdEqualTo(rId)
                .findFirst();
          }

          // Priority 2: name or barcode (for products pushed before itemClsCd was stored)
          existing ??= await db.isar.products
              .filter()
              .branchCodeEqualTo('00')
              .and()
              .group((q) => q
                  .nameEqualTo(rName, caseSensitive: false)
                  .or()
                  .skuEqualTo(rBarcode.isNotEmpty
                      ? rBarcode
                      : (rItemCode.isNotEmpty ? rItemCode : '__no_match__')))
              .findFirst();

          if (existing != null) {
            bool modified = false;
            if (existing.price == 0 && rPrice > 0) {
              existing.price = rPrice;
              modified = true;
            }
            if (rId.isNotEmpty && existing.itemClsCd != rId) {
              existing.itemClsCd = rId;
              modified = true;
            }
            if (!existing.isSyncedWithDigitax) {
              existing.isSyncedWithDigitax = true;
              modified = true;
            }
            existing.lastDigitaxSyncDate = DateTime.now();
            if (modified) {
              await db.isar.writeTxn(() async {
                await db.isar.products.put(existing!);
              });
            }
          } else if (isOwner) {
            // HQ Owner: auto-create from DigiTax master catalog
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

          // Priority 1: match by DigiTax item ID already stored locally (most reliable)
          // Priority 2: fall back to name / barcode match (for newly-added products)
          final existingRemote = (p.itemClsCd.isNotEmpty && p.itemClsCd.startsWith('item_')
              ? remoteById[p.itemClsCd]
              : null) ?? remoteByName[pNameKey] ?? (pCodeKey.isNotEmpty ? remoteByCode[pCodeKey] : null);

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

    final invoiceNo = transaction.transactionId?.isNotEmpty == true
        ? transaction.transactionId!
        : 'INV-${transaction.id}-${DateTime.now().millisecondsSinceEpoch % 100000}';
    transaction.transactionId = invoiceNo;
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
        "unit_price": double.parse(item.priceAtSale.toStringAsFixed(4)),
        "package_unit_quantity": 1,
        "discount_rate": 0.0000,
        "discount_amount": 0.0000,
        "total_amount": double.parse((item.quantity * item.priceAtSale).toStringAsFixed(4)),
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
        debugPrint('DIGITAX_SALES_QUEUED: Initial response from DigiTax: $data');

        if (data is! Map) return false;

        Map<String, dynamic> saleData = Map<String, dynamic>.from(data);
        final saleId = saleData['id']?.toString();

        // If not immediately signed (DigiTax queue processing), poll for live ZRA signature
        if (saleData['receipt_signature'] == null || saleData['receipt_signature'].toString().trim().isEmpty) {
          for (int attempt = 1; attempt <= 5; attempt++) {
            await Future.delayed(const Duration(milliseconds: 1000));
            try {
              final pollResp = (saleId != null && saleId.isNotEmpty)
                  ? await _dio.get(
                      '$digitaxZambiaApiBaseUrl/sales/$saleId',
                      options: Options(headers: headers),
                    )
                  : await _dio.get(
                      '$digitaxZambiaApiBaseUrl/sales',
                      queryParameters: {'trader_invoice_number': invoiceNo},
                      options: Options(headers: headers),
                    );

              if (pollResp.statusCode == 200 && pollResp.data != null) {
                dynamic pData = pollResp.data;
                if (pData is Map) {
                  final list = pData['sales'] ?? pData['data'] ?? pData['items'] ?? pData['results'];
                  if (list is List && list.isNotEmpty) pData = list.first;
                  if (pData is Map) {
                    final sig = pData['receipt_signature']?.toString();
                    if (sig != null && sig.trim().isNotEmpty) {
                      saleData = Map<String, dynamic>.from(pData);
                      debugPrint('DIGITAX_POLL_SUCCESS: Sale #$invoiceNo signed after $attempt attempt(s)!');
                      break;
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('DIGITAX_POLL_NOTICE: Attempt $attempt for $invoiceNo: $e');
            }
          }
        }

        final liveSignature = saleData['receipt_signature']?.toString().trim();
        if (liveSignature == null || liveSignature.isEmpty) {
          debugPrint('DIGITAX_PENDING: Sale $invoiceNo is queued in DigiTax VSDC. Waiting for background confirmation.');
          return false;
        }

        // SDC Invoice Number (ZRA Smart Invoice format: INV1/{number})
        final rawRcpt = saleData['receipt_number'] ?? saleData['invoice_number'] ?? saleData['sdc_invoice_number'] ?? saleData['sale_number'];
        String sdcRcptNo = 'PENDING';
        if (rawRcpt != null && rawRcpt.toString().trim().isNotEmpty && rawRcpt.toString() != 'null') {
          final rcptStr = rawRcpt.toString().trim();
          if (rcptStr.toUpperCase().startsWith('INV1/') || rcptStr.toUpperCase().startsWith('INV/') || rcptStr.toUpperCase().startsWith('CN')) {
            sdcRcptNo = rcptStr;
          } else {
            final cleanNum = rcptStr.replaceFirst(RegExp(r'^(INV|CN)-0*'), '').replaceFirst(RegExp(r'^(INV|CN)-'), '');
            sdcRcptNo = 'INV1/$cleanNum';
          }
        }

        // ZRA VSDC Internal Data
        final internalData = saleData['internal_data']?.toString() ?? (config?.mrcNo ?? '');

        // Virtual SDC Device ID (from DigiTax registration)
        final sdcId = (saleData['sdc_id']?.toString().isNotEmpty == true)
            ? saleData['sdc_id'].toString()
            : ((saleData['serial_number']?.toString().isNotEmpty == true)
                ? saleData['serial_number'].toString()
                : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : ''));

        // ZRA Verification QR URL
        final qrData = (saleData['receipt_url']?.toString().isNotEmpty == true)
            ? saleData['receipt_url'].toString()
            : (sdcId.isNotEmpty
                ? 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcId&rcpt=$sdcRcptNo'
                : '');

        // Invoice type
        final invoiceType = switch (saleData['receipt_type_code']?.toString()) {
          'S' => 'Normal Sale',
          'R' => 'Credit Note',
          'C' => 'Copy',
          _ => saleData['kind'] != null ? saleData['kind'].toString().replaceAll('_', ' ').toUpperCase() : 'Normal Sale',
        };

        // Server-Side Tax Calculations from DigiTax (VAT, TOT, IPL, TL, Excise)
        final taxSummary = saleData['sales_tax_summary'];
        if (taxSummary is Map) {
          final vatTaxable = double.tryParse((taxSummary['taxable_amount_vat'] ?? '0').toString()) ?? 0.0;
          final vatTax = double.tryParse((taxSummary['tax_amount_vat'] ?? '0').toString()) ?? 0.0;
          final totTaxable = double.tryParse((taxSummary['taxable_amount_tot'] ?? '0').toString()) ?? 0.0;
          final totTax = double.tryParse((taxSummary['tax_amount_tot'] ?? '0').toString()) ?? 0.0;
          final iplTaxable = double.tryParse((taxSummary['taxable_amount_ipl'] ?? '0').toString()) ?? 0.0;
          final iplTax = double.tryParse((taxSummary['tax_amount_ipl'] ?? '0').toString()) ?? 0.0;
          final tlTaxable = double.tryParse((taxSummary['taxable_amount_tl'] ?? '0').toString()) ?? 0.0;
          final tlTax = double.tryParse((taxSummary['tax_amount_tl'] ?? '0').toString()) ?? 0.0;
          final exciseTaxable = double.tryParse((taxSummary['taxable_amount_excise'] ?? '0').toString()) ?? 0.0;
          final exciseTax = double.tryParse((taxSummary['tax_amount_excise'] ?? '0').toString()) ?? 0.0;

          final serverTax = vatTax + totTax + iplTax + tlTax + exciseTax;
          final serverSubtotal = vatTaxable + totTaxable + iplTaxable + tlTaxable + exciseTaxable;

          if (serverSubtotal > 0) {
            transaction.subtotal = serverSubtotal;
            transaction.taxAmount = serverTax;
            transaction.totalAmount = serverSubtotal + serverTax;
          }
        }

        transaction.zraSdcId = sdcId;
        transaction.zraReceiptNumber = sdcRcptNo;
        transaction.zraMarkId = liveSignature;
        transaction.zraInternalData = internalData;
        transaction.zraQrCode = qrData;
        transaction.zraInvoiceType = invoiceType;
        transaction.zraStatus = 'APPROVED';

        await db.isar.writeTxn(() async {
          await db.isar.saleTransactions.put(transaction);
        });

        // Cache the DigiTax virtual SDC ID back to StoreConfig
        if (sdcId.isNotEmpty && config != null && config.sdcId != sdcId) {
          config.sdcId = sdcId;
          try { await db.saveStoreConfig(config); } catch (_) {}
          debugPrint('DIGITAX_SDC_CACHED: Virtual SDC ID "$sdcId" cached to StoreConfig');
        }

        debugPrint('DIGITAX_FISCALIZED_LIVE: SDC ID: $sdcId | SDC Inv No: $sdcRcptNo | Signature: $liveSignature | Internal: $internalData | Type: $invoiceType');
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
        Map<String, dynamic> saleData = Map<String, dynamic>.from(data);
        final saleId = saleData['id']?.toString();

        if (saleData['receipt_signature'] == null || saleData['receipt_signature'].toString().trim().isEmpty) {
          for (int attempt = 1; attempt <= 4; attempt++) {
            await Future.delayed(const Duration(milliseconds: 1000));
            try {
              final pollResp = (saleId != null && saleId.isNotEmpty)
                  ? await _dio.get('$digitaxZambiaApiBaseUrl/sales/$saleId', options: Options(headers: headers))
                  : await _dio.get('$digitaxZambiaApiBaseUrl/sales', queryParameters: {'trader_invoice_number': "CN-${refundTx.id}"}, options: Options(headers: headers));
              if (pollResp.statusCode == 200 && pollResp.data != null) {
                dynamic pData = pollResp.data;
                if (pData is Map) {
                  final list = pData['sales'] ?? pData['data'] ?? pData['items'] ?? pData['results'];
                  if (list is List && list.isNotEmpty) pData = list.first;
                  if (pData is Map) {
                    final sig = pData['receipt_signature']?.toString();
                    if (sig != null && sig.trim().isNotEmpty) {
                      saleData = Map<String, dynamic>.from(pData);
                      break;
                    }
                  }
                }
              }
            } catch (_) {}
          }
        }

        final liveSignature = saleData['receipt_signature']?.toString().trim();
        if (liveSignature == null || liveSignature.isEmpty) {
          debugPrint('DIGITAX_CN_PENDING: Credit note for Tx #${refundTx.id} is queued.');
          return false;
        }

        final rcptNumberRaw = saleData['receipt_number'];
        final sdcRcptNo = (rcptNumberRaw != null && rcptNumberRaw.toString().isNotEmpty)
            ? rcptNumberRaw.toString()
            : 'CN-${refundTx.id}';
        final internalData = saleData['internal_data']?.toString() ?? (config?.mrcNo ?? '');
        final sdcId = saleData['sdc_id']?.toString() ?? (saleData['serial_number']?.toString() ?? (config?.sdcId ?? ''));
        final qrUrl = (saleData['receipt_url']?.toString().isNotEmpty == true)
            ? saleData['receipt_url'].toString()
            : (sdcId.isNotEmpty ? 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin}&sdc=$sdcId&rcpt=$sdcRcptNo' : '');

        refundTx.zraSdcId = sdcId;
        refundTx.zraReceiptNumber = sdcRcptNo;
        refundTx.zraMarkId = liveSignature;
        refundTx.zraInternalData = internalData;
        refundTx.zraQrCode = qrUrl;
        refundTx.zraInvoiceType = 'Credit Note';
        refundTx.zraStatus = 'APPROVED';

        // Cache SDC ID if updated
        if (sdcId.isNotEmpty && config != null && config.sdcId != sdcId) {
          config.sdcId = sdcId;
          try { await db.isar.writeTxn(() async { await db.isar.storeConfigs.put(config); }); } catch (_) {}
        }
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
    final config = ref.read(storeConfigProvider).value;
    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) return 0;

    final db = ref.read(databaseServiceProvider);
    final pendingTransactions = await db.isar.saleTransactions
        .filter()
        .zraStatusEqualTo('PENDING', caseSensitive: false)
        .or()
        .zraStatusEqualTo('pending', caseSensitive: false)
        .or()
        .zraReceiptNumberIsNull()
        .findAll();

    if (pendingTransactions.isEmpty) return 0;

    int fiscalizedCount = 0;
    for (final tx in pendingTransactions) {
      try {
        await tx.items.load();
        final success = await fiscalizeSaleTransaction(tx, tx.items.toList());
        if (success) {
          fiscalizedCount++;
          if (config?.autoPrintReceipt != false) {
            try {
              await ref.read(printerServiceProvider).printReceipt(tx, tx.items.toList(), config: config);
              debugPrint('DIGITAX_OFFLINE_SYNC_PRINT: Tx #${tx.id} printed after background sync');
            } catch (_) {}
          }
        }
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

        if (matchData is! Map) return false;

        final rawRcpt = matchData['receipt_number'] ?? matchData['invoice_number'] ?? matchData['sdc_invoice_number'] ?? matchData['sale_number'];
        String? parsedSdcRcptNo;
        if (rawRcpt != null && rawRcpt.toString().trim().isNotEmpty && rawRcpt.toString() != 'null') {
          final rcptStr = rawRcpt.toString().trim();
          if (rcptStr.toUpperCase().startsWith('INV1/') || rcptStr.toUpperCase().startsWith('INV/') || rcptStr.toUpperCase().startsWith('CN')) {
            parsedSdcRcptNo = rcptStr;
          } else {
            final cleanNum = rcptStr.replaceFirst(RegExp(r'^(INV|CN)-0*'), '').replaceFirst(RegExp(r'^(INV|CN)-'), '');
            parsedSdcRcptNo = 'INV1/$cleanNum';
          }
        }
        final parsedSignature = matchData['receipt_signature']?.toString().isNotEmpty == true
            ? matchData['receipt_signature'].toString() : null;
        final parsedInternalData = matchData['internal_data']?.toString().isNotEmpty == true
            ? matchData['internal_data'].toString() : null;
        final parsedSdcId = (matchData['sdc_id']?.toString().isNotEmpty == true)
            ? matchData['sdc_id'].toString()
            : ((matchData['serial_number']?.toString().isNotEmpty == true)
                ? matchData['serial_number'].toString()
                : null);
        final parsedQrUrl = matchData['receipt_url']?.toString().isNotEmpty == true
            ? matchData['receipt_url'].toString() : null;
        final parsedInvoiceType = switch (matchData['receipt_type_code']?.toString()) {
          'S' => 'Normal Sale',
          'R' => 'Credit Note',
          'C' => 'Copy',
          _ => matchData['kind']?.toString().replaceAll('_', ' ').toUpperCase(),
        };

        if (parsedSignature != null && parsedSignature.isNotEmpty) {
          transaction.zraMarkId = parsedSignature;
          if (parsedSdcRcptNo != null) transaction.zraReceiptNumber = parsedSdcRcptNo;
          if (parsedInternalData != null) transaction.zraInternalData = parsedInternalData;
          if (parsedSdcId != null) transaction.zraSdcId = parsedSdcId;
          if (parsedQrUrl != null) transaction.zraQrCode = parsedQrUrl;
          if (parsedInvoiceType != null) transaction.zraInvoiceType = parsedInvoiceType;

          // Pull server-calculated taxes from DigiTax
          final taxSummary = matchData['sales_tax_summary'];
          if (taxSummary is Map) {
            final vatTaxable = double.tryParse((taxSummary['taxable_amount_vat'] ?? '0').toString()) ?? 0.0;
            final vatTax = double.tryParse((taxSummary['tax_amount_vat'] ?? '0').toString()) ?? 0.0;
            final totTaxable = double.tryParse((taxSummary['taxable_amount_tot'] ?? '0').toString()) ?? 0.0;
            final totTax = double.tryParse((taxSummary['tax_amount_tot'] ?? '0').toString()) ?? 0.0;
            final iplTaxable = double.tryParse((taxSummary['taxable_amount_ipl'] ?? '0').toString()) ?? 0.0;
            final iplTax = double.tryParse((taxSummary['tax_amount_ipl'] ?? '0').toString()) ?? 0.0;
            final tlTaxable = double.tryParse((taxSummary['taxable_amount_tl'] ?? '0').toString()) ?? 0.0;
            final tlTax = double.tryParse((taxSummary['tax_amount_tl'] ?? '0').toString()) ?? 0.0;
            final exciseTaxable = double.tryParse((taxSummary['taxable_amount_excise'] ?? '0').toString()) ?? 0.0;
            final exciseTax = double.tryParse((taxSummary['tax_amount_excise'] ?? '0').toString()) ?? 0.0;

            final serverTax = vatTax + totTax + iplTax + tlTax + exciseTax;
            final serverSubtotal = vatTaxable + totTaxable + iplTaxable + tlTaxable + exciseTaxable;

            if (serverSubtotal > 0) {
              transaction.subtotal = serverSubtotal;
              transaction.taxAmount = serverTax;
              transaction.totalAmount = serverSubtotal + serverTax;
            }
          }

          transaction.zraStatus = 'APPROVED';

          await db.isar.writeTxn(() async {
            await db.isar.saleTransactions.put(transaction);
          });

          if (parsedSdcId != null && parsedSdcId.isNotEmpty && config != null && config.sdcId != parsedSdcId) {
            config.sdcId = parsedSdcId;
            try { await db.saveStoreConfig(config); } catch (_) {}
          }

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
}
