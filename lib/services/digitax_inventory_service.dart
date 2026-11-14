import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/local_sql_service.dart';
import 'package:beleka_pos/services/network_client.dart';
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
  DigiTaxSyncStatusNotifier()
    : super({
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

final digiTaxAutoSyncProvider =
    StateNotifierProvider<DigiTaxSyncStatusNotifier, Map<String, dynamic>>((
      ref,
    ) {
      return DigiTaxSyncStatusNotifier();
    });

final digitaxInventoryServiceProvider = Provider<DigiTaxInventoryService>((
  ref,
) {
  final service = DigiTaxInventoryService(ref: ref);
  ref.onDispose(service.dispose);
  return service;
});

class DigiTaxInventoryService {
  final Ref ref;

  /// Primary Dio instance used for foreground (user-initiated) requests.
  /// Generous timeouts because the user is waiting for feedback.
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  /// Short-timeout Dio instance used exclusively by the background fiscal queue
  /// worker so it doesn't block for 40 s per transaction during poor connectivity.
  final Dio _backgroundDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ),
  );

  bool _isSyncRunning = false;
  bool _isProcessingFiscalQueue = false;
  bool _isPollingItemStatus = false;
  Timer? _fiscalQueueTimer;
  Timer? _itemStatusPollTimer;

  // In-memory cache for remote catalogue items to avoid redundant pagination on every sale
  List<Map<String, dynamic>>? _remoteItemsCache;
  DateTime? _remoteItemsCacheTime;

  /// Quick reachability probe: resolves `api.digitax.tech` via DNS with a 2 s
  /// timeout. Returns false only when offline or the host is unreachable.
  static Future<bool> canReachDigiTax() async {
    try {
      final result = await InternetAddress.lookup('api.digitax.tech')
          .timeout(const Duration(seconds: 2));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      // If DNS probe times out or fails due to local resolver/hotspot issues,
      // return true to allow Dio HTTP requests to proceed with their own retries.
      return true;
    }
  }

  // Official DigiTax Zambia API Base URL from zm.docs.digitax.tech OpenAPI spec
  static const String digitaxZambiaApiBaseUrl =
      'https://api.digitax.tech/zm/v1';

  DigiTaxInventoryService({required this.ref}) {
    _startPeriodicFiscalWorker();
  }

  void _logFiscalSummaryMismatch(SaleTransaction transaction, dynamic summary) {
    if (summary is! Map) return;

    double? amount(String key) {
      final value = summary[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    var summaryTotal = 0.0;
    var hasSummaryAmounts = false;
    for (final category in const ['vat', 'tot', 'ipl', 'tl', 'excise']) {
      final taxable = amount('taxable_amount_$category');
      final tax = amount('tax_amount_$category');
      if (taxable != null || tax != null) hasSummaryAmounts = true;
      summaryTotal += (taxable ?? 0) + (tax ?? 0);
    }

    if (hasSummaryAmounts &&
        (summaryTotal - transaction.totalAmount).abs() > 0.01) {
      debugPrint(
        'DIGITAX_SALES_TOTAL_MISMATCH: Fiscal summary total '
        '${summaryTotal.toStringAsFixed(2)} differs from recorded paid total '
        '${transaction.totalAmount.toStringAsFixed(2)} for transaction '
        '${transaction.transactionId}; preserving the sale amounts.',
      );
    }
  }

  double? _fiscalResponseTotal(Map<String, dynamic> saleData) {
    double? amount(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    for (final key in const [
      'total_amount',
      'totalAmount',
      'totAmt',
      'amount_due',
    ]) {
      final total = amount(saleData[key]);
      if (total != null) return total;
    }

    final subtotal = amount(saleData['subtotal'] ?? saleData['sub_total']);
    final tax = amount(saleData['tax_amount'] ?? saleData['taxAmount']);
    if (subtotal != null && tax != null) return subtotal + tax;

    final summary = saleData['sales_tax_summary'];
    if (summary is! Map) return null;
    var total = 0.0;
    var hasAmounts = false;
    for (final category in const ['vat', 'tot', 'ipl', 'tl', 'excise']) {
      final taxable = amount(summary['taxable_amount_$category']);
      final categoryTax = amount(summary['tax_amount_$category']);
      if (taxable != null || categoryTax != null) hasAmounts = true;
      total += (taxable ?? 0) + (categoryTax ?? 0);
    }
    return hasAmounts ? total : null;
  }

  List<dynamic> _extractItemList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is Map) {
      for (final key in const [
        'items',
        'data',
        'results',
        'records',
        'content',
      ]) {
        final items = _extractItemList(payload[key]);
        if (items.isNotEmpty) return items;
      }
    }
    return <dynamic>[];
  }

  bool _hasItemListPayload(dynamic payload) {
    if (payload is List) return true;
    if (payload is Map) {
      return const ['items', 'data', 'results', 'records', 'content'].any(
        (key) => payload.containsKey(key) && _hasItemListPayload(payload[key]),
      );
    }
    return false;
  }

  /// Returns the ZRA/DigiTax package unit code for a given unit-of-measure string.
  /// Returns the official ZRA/DigiTax package unit code (UNECE Rec 21).
  /// Validated against live DigiTax Zambia / ZRA VSDC API:
  /// BX (Box), BO (Bottle - NOT BT), PA (Packet/Pack - NOT PK), CA (Can - NOT CN),
  /// CT (Carton), BG (Bag), RO (Roll), BE (Bundle), TB (Tub), AM (Ampoule), NT (Net/Unit).
  String _resolvePackageUnitCode(String? unitOfMeasure) {
    final upper = (unitOfMeasure ?? '').trim().toUpperCase();
    // Pre-empt common aliases to valid UNECE Rec 21 packaging code (NT = Net / Unit / Each)
    if (upper == 'EACH' ||
        upper == 'PCS' ||
        upper == 'PIECE' ||
        upper == 'UNIT' ||
        upper == 'ITEM') {
      return 'NT';
    }
    // Direct match with official DigiTax/ZRA packaging codes
    if (upper == 'BO' ||
        upper == 'PA' ||
        upper == 'BX' ||
        upper == 'CT' ||
        upper == 'CA' ||
        upper == 'BG' ||
        upper == 'BA' ||
        upper == 'RO' ||
        upper == 'BE' ||
        upper == 'TB' ||
        upper == 'AM' ||
        upper == 'NT') {
      return upper;
    }

    final uom = (unitOfMeasure ?? '').trim().toLowerCase();
    if (uom.contains('box') ||
        uom.contains('bx') ||
        uom.contains('tab') ||
        uom.contains('stp')) {
      return 'BX'; // Box
    } else if (uom.contains('btl') || uom.contains('bottle')) {
      return 'BO'; // Bottle (ZRA code BO; DigiTax rejects BT as invalid)
    } else if (uom.contains('pkt') || uom.contains('pack') || uom == 'pk') {
      return 'PA'; // Packet/Package (ZRA code PA; DigiTax rejects PK as invalid)
    } else if (uom.contains('can')) {
      return 'CA'; // Can (ZRA code CA; DigiTax rejects CN as invalid)
    } else if (uom.contains('carton') || uom == 'ctn' || uom == 'crt') {
      return 'CT'; // Carton
    } else if (uom.contains('bag') || uom == 'bg') {
      return 'BG'; // Bag
    } else if (uom == 'ba') {
      return 'BA'; // Barrel
    } else if (uom.contains('roll') || uom == 'rol') {
      return 'RO'; // Roll
    } else if (uom.contains('bundle') || uom == 'bdl') {
      return 'BE'; // Bundle
    } else if (uom.contains('tub')) {
      return 'TB'; // Tub
    } else if (uom.contains('amp')) {
      return 'AM'; // Ampoule
    }
    // Default: NT (Net/None) — standard for pcs, piece, unit, each, item, kg, ltr, etc.
    return 'NT';
  }

  String _resolveQuantityUnitCode(String? unitOfMeasure) {
    final upper = (unitOfMeasure ?? '').trim().toUpperCase();
    if (upper == 'KG') return 'KG';
    if (upper == 'GRM') return 'GRM';
    if (upper == 'L') return 'L';
    if (upper == 'M') return 'M';
    if (upper == 'BOT' || upper == 'BO') return 'BOT';
    if (upper == 'U') return 'U';

    final uom = (unitOfMeasure ?? '').trim().toLowerCase();
    if (uom == 'kg') {
      return 'KG';
    } else if (uom == 'g' || uom == 'grm') {
      return 'GRM'; // ZRA code GRM; DigiTax rejects 'G' as invalid
    } else if (uom == 'ltr' || uom == 'l') {
      return 'L';
    } else if (uom == 'm') {
      return 'M';
    } else if (uom.contains('btl') || uom.contains('bottle')) {
      return 'BOT';
    }
    return 'U';
  }

  /// Resolves the compliant ZRA VAT Category Code (A, B, D, E)
  /// Under ZRA Smart Invoice (VSDC):
  /// - 'A': Standard Rated (16%)
  /// - 'B': Minimum Taxable Value (MTV) / Zero-Rated (0%)
  /// - 'D': Exempt (0%) [Official ZRA Smart Invoice code for exempt supplies; 'C' does not exist in ZRA]
  /// - 'E': Disbursement (0%)
  static String resolveCompliantVatCategoryCode({
    required String? zraTaxCode,
    required double taxRate,
    bool isTotBusiness = false,
  }) {
    if (isTotBusiness) return 'D';
    final code = (zraTaxCode ?? '').trim().toUpperCase();
    if (code == 'TOT' || code == 'D' || code == 'C' || code == 'EXEMPT') {
      return 'D';
    }
    if (code == 'B' || code == 'ZERO') {
      return 'B'; // 0% Zero-Rated (MTV)
    }
    if (code == 'E') {
      return 'E'; // 0% Disbursement
    }
    if (taxRate == 0) {
      return 'D'; // Default 0% to Exempt ('D')
    }
    return 'A'; // 16% Standard VAT
  }

  /// Resolves an appropriate ZRA UNSPSC classification code (verified against ZRA VSDC).
  static String resolveCompliantItemClassCode({
    required String? explicitClsCode,
    required String? zraTaxCode,
    String? productName,
  }) {
    final explicit = (explicitClsCode ?? '').trim();
    // Use valid 8-digit code if provided and not an unapproved 2-digit segment code ending in 000000
    if (RegExp(r'^\d{8}$').hasMatch(explicit) &&
        explicit != '50000000' &&
        explicit != '52000000' &&
        explicit != '53100000' &&
        explicit != '51000000' &&
        explicit != '30000000' &&
        explicit != '43211500') {
      return explicit;
    }

    final code = (zraTaxCode ?? '').trim().toUpperCase();
    // ZRA Rule: Zero-Rated items must belong to appropriate food/agric classifications
    if (code == 'B') {
      return '50202301'; // Food & Groceries (Zero-Rated B compliant - verified COMPLETED)
    }
    // ZRA Rule: Exempt items typically healthcare/pharmaceutical/educational
    if (code == 'C' || code == 'D' || code == 'EXEMPT') {
      return '42141501'; // Medical supplies & Healthcare (Exempt D compliant - verified COMPLETED)
    }

    final text = (productName ?? '').toLowerCase();
    if (text.contains('soup') ||
        text.contains('broth') ||
        text.contains('sauce')) {
      return '50192701'; // Soups & Prepared Foods (verified COMPLETED on ZRA)
    }
    if (text.contains('food') ||
        text.contains('bread') ||
        text.contains('meal') ||
        text.contains('drink') ||
        text.contains('beverage') ||
        text.contains('water') ||
        text.contains('snack') ||
        text.contains('sugar')) {
      return '50202301'; // Food, Beverage & Groceries (verified COMPLETED on ZRA)
    }
    if (text.contains('cloth') ||
        text.contains('shirt') ||
        text.contains('shoe') ||
        text.contains('wear') ||
        text.contains('apparel')) {
      return '53101501'; // Clothing & Apparel (verified COMPLETED on ZRA)
    }
    if (text.contains('drug') ||
        text.contains('med') ||
        text.contains('pharm') ||
        text.contains('health')) {
      return '42141501'; // Medical Supplies & Healthcare (verified COMPLETED on ZRA)
    }
    if (text.contains('soap') ||
        text.contains('lotion') ||
        text.contains('cream') ||
        text.contains('beauty') ||
        text.contains('perfume')) {
      return '53131600'; // Cosmetics & Personal Care (verified COMPLETED on ZRA)
    }
    if (text.contains('hardware') ||
        text.contains('cement') ||
        text.contains('paint') ||
        text.contains('tool')) {
      return '30111501'; // Hardware & Building Materials (verified COMPLETED on ZRA)
    }
    if (text.contains('furnit') ||
        text.contains('desk') ||
        text.contains('chair') ||
        text.contains('table')) {
      return '56101530'; // Commercial & Industrial Furniture (verified COMPLETED on ZRA)
    }

    // Default: General Domestic Consumer Goods & Retail Merchandise (verified COMPLETED on ZRA)
    return '52151501';
  }

  Future<List<Map<String, dynamic>>> _fetchAllRemoteItems(
    Map<String, String> headers, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _remoteItemsCache != null &&
        _remoteItemsCacheTime != null &&
        DateTime.now().difference(_remoteItemsCacheTime!) <
            const Duration(seconds: 5)) {
      return _remoteItemsCache!;
    }

    final List<Map<String, dynamic>> allItems = [];
    String? nextCursor;
    int pageCount = 0;
    const int maxPages = 1000;
    final Set<String> seenCursors = {};

    while (pageCount < maxPages) {
      pageCount++;
      try {
        final resp = await _dio.get(
          '$digitaxZambiaApiBaseUrl/items',
          queryParameters: {
            'page_size': 20,
            if (nextCursor != null && nextCursor.isNotEmpty)
              'after': nextCursor,
          },
          options: Options(headers: headers),
        );

        if (resp.statusCode != 200 ||
            resp.data == null ||
            !_hasItemListPayload(resp.data)) {
          if (allItems.isNotEmpty) {
            // Keep already fetched items rather than failing the entire catalogue
            break;
          }
          throw StateError(
            'Unexpected DigiTax item catalogue response on page $pageCount.',
          );
        }

        final list = _extractItemList(resp.data);
        for (final item in list) {
          if (item is Map) {
            allItems.add(Map<String, dynamic>.from(item));
          }
        }

        if (resp.data is Map && resp.data['pagination'] is Map) {
          final next = resp.data['pagination']['next']?.toString();
          if (next != null &&
              next.isNotEmpty &&
              next != nextCursor &&
              !seenCursors.contains(next)) {
            seenCursors.add(next);
            nextCursor = next;
            continue;
          }
        }
        break;
      } catch (e) {
        debugPrint('DIGITAX_PAGINATION_FETCH_NOTE: Page $pageCount: $e');
        if (allItems.isNotEmpty) {
          // Keep accumulated items if a later page has an issue
          break;
        }
        rethrow;
      }
    }
    _remoteItemsCache = allItems;
    _remoteItemsCacheTime = DateTime.now();
    return allItems;
  }

  String? _extractRemoteItemId(dynamic value) {
    if (value is! Map) {
      return null;
    }

    for (final key in const ['id', 'item_id']) {
      final id = value[key]?.toString().trim();
      if (id != null && id.isNotEmpty && id != 'null') {
        return id;
      }
    }

    for (final key in const ['item', 'data', 'product']) {
      final id = _extractRemoteItemId(value[key]);
      if (id != null) {
        return id;
      }
    }
    return null;
  }

  Map<String, dynamic> _extractRemoteItemMap(dynamic value) {
    if (value is Map) {
      for (final key in const ['item', 'data', 'product']) {
        final inner = value[key];
        if (inner is Map &&
            (inner.containsKey('id') ||
                inner.containsKey('item_id') ||
                inner.containsKey('status') ||
                inner.containsKey('item_name'))) {
          return Map<String, dynamic>.from(inner);
        }
      }
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  String? _extractItemStatusReason(Map<String, dynamic> remoteItem) {
    for (final key in const [
      'status_message',
      'error_message',
      'rejection_reason',
      'vsdc_message',
      'zra_message',
      'reason',
      'error',
      'message',
      'description',
    ]) {
      final val = remoteItem[key]?.toString().trim();
      if (val != null && val.isNotEmpty && val != 'null') {
        return val;
      }
    }
    return null;
  }

  /// Applies the 3-stage DigiTax/ZRA item status (`PENDING`, `COMPLETED`, `FAILED`),
  /// remote unit price (`default_unit_price`), and ZRA classification code to [product].
  void _applyRemoteItemStatusToProduct(
    Product product,
    Map<String, dynamic> remoteItem, {
    bool updateRemotePrice = true,
  }) {
    final rId =
        (remoteItem['id'] ??
                remoteItem['item_id'] ??
                remoteItem['itemId'] ??
                '')
            .toString()
            .trim();
    if (rId.isNotEmpty && rId != 'null') {
      product.itemClsCd = rId;
    }

    final rClass =
        (remoteItem['item_class_code'] ??
                remoteItem['itemClsCd'] ??
                remoteItem['item_cls_cd'] ??
                '')
            .toString()
            .trim();
    if (RegExp(r'^\d{8}$').hasMatch(rClass)) {
      product.zraUnspscClassCode = rClass;
    }

    if (updateRemotePrice) {
      final rPrice =
          double.tryParse(
            (remoteItem['default_unit_price'] ??
                    remoteItem['dftPrc'] ??
                    remoteItem['price'] ??
                    '')
                .toString(),
          ) ??
          0.0;
      if (rPrice > 0) {
        product.digitaxRemotePrice = rPrice;
      }
    }

    final rawStatus =
        (remoteItem['status'] ??
                remoteItem['zra_status'] ??
                remoteItem['sync_status'] ??
                'COMPLETED')
            .toString()
            .trim()
            .toUpperCase();
    final reason = _extractItemStatusReason(remoteItem);

    if (rawStatus == 'PENDING' ||
        rawStatus == 'QUEUED' ||
        rawStatus == 'PROCESSING') {
      product.digitaxSyncStatus = 'PENDING';
      product.digitaxSyncError =
          reason ?? 'Waiting for ZRA VSDC approval (Pending)';
    } else if (rawStatus == 'FAILED' ||
        rawStatus == 'REJECTED' ||
        rawStatus == 'ERROR') {
      product.digitaxSyncStatus = 'FAILED';
      product.digitaxSyncError =
          reason ??
          'Rejected by ZRA VSDC — check ZRA Classification Code & Tax Type';
    } else {
      product.digitaxSyncStatus = 'COMPLETED';
      product.digitaxSyncError = null;
    }
    product.lastDigitaxSyncDate = DateTime.now();
  }

  void _startPeriodicFiscalWorker() {
    _fiscalQueueTimer?.cancel();
    _fiscalQueueTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      try {
        // Skip immediately if DigiTax API is unreachable – avoids wasting 8 s
        // per connect attempt when the terminal has no internet.
        if (!await canReachDigiTax()) {
          debugPrint(
            'DIGITAX_QUEUE_WORKER: DigiTax unreachable – skipping this cycle.',
          );
          return;
        }
        await processPendingFiscalQueue();
      } catch (e) {
        debugPrint('DIGITAX_QUEUE_WORKER_ERROR: $e');
      }
    });

    _itemStatusPollTimer?.cancel();
    _itemStatusPollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) async {
        try {
          await pollPendingAndMismatchedItems();
        } catch (e) {
          debugPrint('DIGITAX_ITEM_STATUS_POLL_ERROR: $e');
        }
      },
    );
  }

  void dispose() {
    _fiscalQueueTimer?.cancel();
    _fiscalQueueTimer = null;
    _itemStatusPollTimer?.cancel();
    _itemStatusPollTimer = null;
  }

  bool _belongsToTargetBranch(
    String productBranch,
    String targetBhfId,
    String configuredBhfId,
    bool isCurrentHq,
  ) {
    final normProd = productBranch.trim();
    if (normProd == targetBhfId) {
      return true;
    }
    if (isCurrentHq) {
      const hqCodes = {'', '0', '00', '000', '01', '001'};
      if (hqCodes.contains(normProd) || normProd == configuredBhfId) {
        return true;
      }
    }
    return false;
  }

  Product? _findMatchingLocalProductForRemoteItem({
    required List<Product> branchProducts,
    required String rId,
    required String rBarcode,
    required String rItemCode,
    required String rName,
  }) {
    // 1. Exact DigiTax item ID match (including archived so we don't resurrect deleted items)
    for (final p in branchProducts) {
      if (p.itemClsCd.trim() == rId) {
        return p;
      }
    }

    final normBarcode = rBarcode.trim().toLowerCase();
    final normItemCode = rItemCode.trim().toLowerCase();
    final normName = rName.trim().toLowerCase();

    // 2. Match active product by barcode / SKU if it doesn't belong to a different DigiTax item ID
    if (normBarcode.isNotEmpty || normItemCode.isNotEmpty) {
      for (final p in branchProducts) {
        if (p.isArchived) {
          continue;
        }
        final pSku = p.sku.trim().toLowerCase();
        if (pSku.isEmpty) {
          continue;
        }
        if ((normBarcode.isNotEmpty && pSku == normBarcode) ||
            (normItemCode.isNotEmpty && pSku == normItemCode)) {
          if (!p.hasUsableDigitaxItemId || p.itemClsCd.trim() == rId) {
            return p;
          }
        }
      }
    }

    // 3. Match active product by exact name if it doesn't belong to a different DigiTax item ID
    if (normName.isNotEmpty) {
      for (final p in branchProducts) {
        if (p.isArchived) {
          continue;
        }
        if (p.name.trim().toLowerCase() == normName) {
          if (!p.hasUsableDigitaxItemId || p.itemClsCd.trim() == rId) {
            return p;
          }
        }
      }
    }

    return null;
  }

  /// Background live listener that polls DigiTax for new remote items, any items in
  /// `PENDING` state, or items with a local vs. DigiTax price mismatch, updating Isar
  /// in real time so UI streams (`db.watchAllProducts()`) reflect `COMPLETED`, `PENDING`,
  /// `FAILED`, and newly added DigiTax items live.
  Future<int> pollPendingAndMismatchedItems() async {
    if (_isPollingItemStatus || _isSyncRunning) {
      return 0;
    }
    _isPollingItemStatus = true;
    int updatedCount = 0;

    try {
      if (!await canReachDigiTax()) {
        return 0;
      }

      final db = ref.read(databaseServiceProvider);
      final config = await db.isar.storeConfigs.where().findFirst();
      final isOwner = ref.read(isOwnerProvider);
      final currentUser = ref.read(authProvider);
      final configuredBhfId = config?.bhfId.trim().isNotEmpty == true
          ? config!.bhfId.trim()
          : '00';
      final String bhfId = (!isOwner &&
              currentUser?.branchCode != null &&
              currentUser!.branchCode!.trim().isNotEmpty)
          ? currentUser.branchCode!.trim()
          : configuredBhfId;
      final isCurrentHq = isOwner ||
          bhfId == configuredBhfId ||
          const {'00', '000', '01', '001'}.contains(bhfId);

      final branchApiKey = await resolveBranchApiKey(bhfId);
      final Set<String> updatedItemIds = {};

      if (branchApiKey != null && branchApiKey.isNotEmpty) {
        final branchHeaders = {
          'Authorization': 'Bearer $branchApiKey',
          'X-API-Key': branchApiKey,
          'Content-Type': 'application/json',
        };

        try {
          final remoteList = await _fetchAllRemoteItems(
            branchHeaders,
            forceRefresh: true,
          );
          final allLocal = await db.isar.products.where().findAll();
          final branchProducts = allLocal
              .where(
                (p) => _belongsToTargetBranch(
                  p.branchCode,
                  bhfId,
                  configuredBhfId,
                  isCurrentHq,
                ),
              )
              .toList();

          for (final r in remoteList) {
            final rId =
                (r['id'] ?? r['item_id'] ?? r['itemId'] ?? '').toString().trim();
            final rItemCode =
                (r['item_code'] ?? r['itemCd'] ?? r['itemCode'] ?? '')
                    .toString()
                    .trim();
            final rBarcode =
                (r['bar_code'] ?? r['barcode'] ?? r['sku'] ?? '')
                    .toString()
                    .trim();
            final rName = (r['item_name'] ??
                    r['itemNm'] ??
                    r['itemName'] ??
                    r['name'] ??
                    '')
                .toString()
                .trim();
            final rPrice =
                double.tryParse(
                  (r['default_unit_price'] ?? r['dftPrc'] ?? r['price'] ?? '0')
                      .toString(),
                ) ??
                0.0;
            final rawStock =
                r['stock_quantity'] ??
                r['stockQuantity'] ??
                r['stock_qty'] ??
                r['current_stock'] ??
                r['stock_level'] ??
                r['quantity'] ??
                r['qty'] ??
                0;
            final remoteStock = rawStock is num
                ? rawStock.toInt()
                : (int.tryParse(rawStock.toString()) ?? 0);

            if (rName.isEmpty || rId.isEmpty) {
              continue;
            }

            final existing = _findMatchingLocalProductForRemoteItem(
              branchProducts: branchProducts,
              rId: rId,
              rBarcode: rBarcode,
              rItemCode: rItemCode,
              rName: rName,
            );

            if (existing != null) {
              if (existing.isArchived || !existing.isDigitaxSyncEnabled) {
                continue;
              }
              updatedItemIds.add(rId);
              final prevStatus = existing.digitaxSyncStatus;
              final prevRemotePrice = existing.digitaxRemotePrice;
              final prevError = existing.digitaxSyncError;
              final prevItemCls = existing.itemClsCd;
              final prevPrice = existing.price;
              final prevStock = existing.stockLevel;

              final hadLocalPriceChange =
                  existing.digitaxRemotePrice != null &&
                  (existing.price - existing.digitaxRemotePrice!).abs() >
                      0.01 &&
                  (existing.price - rPrice).abs() > 0.01;

              _applyRemoteItemStatusToProduct(existing, r);

              if (!hadLocalPriceChange &&
                  rPrice > 0 &&
                  (existing.price - rPrice).abs() > 0.01) {
                existing.price = rPrice;
              }
              if (existing.stockLevel == 0 && remoteStock > 0) {
                existing.stockLevel = remoteStock;
              }

              // If item just transitioned from PENDING -> COMPLETED, push initial stock if remote stock is 0
              if (prevStatus == 'PENDING' &&
                  existing.digitaxSyncStatus == 'COMPLETED' &&
                  existing.stockLevel > 0 &&
                  remoteStock == 0) {
                try {
                  await _backgroundDio.put(
                    '$digitaxZambiaApiBaseUrl/stock/adjust',
                    data: {
                      "item_id": rId,
                      "quantity": existing.stockLevel.abs(),
                      "action": "ADD",
                      "movement_type": "01",
                    },
                    options: Options(headers: branchHeaders),
                  );
                } catch (_) {}
              }

              // If local price was edited by user, push local price to DigiTax
              if (existing.hasDigitaxPriceMismatch &&
                  existing.price > 0 &&
                  existing.digitaxSyncStatus != 'FAILED') {
                try {
                  final putResp = await _backgroundDio.put(
                    '$digitaxZambiaApiBaseUrl/items/$rId',
                    data: {
                      "item_name": existing.name.trim(),
                      "default_unit_price": existing.price,
                      "recommended_retail_price": existing.price,
                    },
                    options: Options(
                      headers: branchHeaders,
                      validateStatus: (s) => s != null && s < 500,
                    ),
                  );
                  if (putResp.statusCode == 200 || putResp.statusCode == 201) {
                    final putMap = _extractRemoteItemMap(putResp.data);
                    _applyRemoteItemStatusToProduct(
                      existing,
                      putMap,
                      updateRemotePrice: false,
                    );
                    existing.digitaxRemotePrice = existing.price;
                  }
                } catch (_) {}
              }

              if (existing.digitaxSyncStatus != prevStatus ||
                  existing.digitaxRemotePrice != prevRemotePrice ||
                  existing.digitaxSyncError != prevError ||
                  existing.itemClsCd != prevItemCls ||
                  existing.price != prevPrice ||
                  existing.stockLevel != prevStock) {
                await db.isar.writeTxn(() async {
                  await db.isar.products.put(existing);
                });
                updatedCount++;
              }
            } else {
              // New item created directly in DigiTax Dashboard — import into local inventory!
              final remoteSku = rBarcode.isNotEmpty
                  ? rBarcode
                  : (rItemCode.isNotEmpty ? rItemCode : rId);
              final imported = Product(
                name: rName,
                sku: remoteSku.isNotEmpty ? remoteSku : rName,
                price: rPrice,
                stockLevel: remoteStock,
                categoryId: 0,
                itemClsCd: rId,
                branchCode: bhfId,
                branchName: config?.branchName,
                isSyncedWithDigitax: false,
                isDigitaxSyncEnabled: true,
                lastDigitaxSyncDate: DateTime.now(),
              );
              _applyRemoteItemStatusToProduct(imported, r);
              await db.isar.writeTxn(() async {
                await db.isar.products.put(imported);
              });
              branchProducts.add(imported);
              updatedItemIds.add(rId);
              updatedCount++;
              debugPrint(
                'DIGITAX_LIVE_IMPORT: Pulled new DigiTax item "${imported.name}" [ID: $rId, Status: ${imported.digitaxSyncStatus}]',
              );
            }
          }
        } catch (e) {
          debugPrint('DIGITAX_LIVE_CATALOG_POLL_NOTE: $e');
        }
      }

      final allProducts = await db.isar.products
          .filter()
          .isArchivedEqualTo(false)
          .and()
          .isDigitaxSyncEnabledEqualTo(true)
          .findAll();

      final candidates = allProducts.where((p) {
        if (!p.hasUsableDigitaxItemId) {
          return false;
        }
        if (updatedItemIds.contains(p.itemClsCd.trim())) {
          return false;
        }
        return p.digitaxSyncStatus == 'PENDING' || p.hasDigitaxPriceMismatch;
      }).toList();

      for (final p in candidates.take(15)) {
        final itemId = p.itemClsCd.trim();
        final branchCode = p.branchCode.trim().isNotEmpty
            ? p.branchCode.trim()
            : '00';
        final apiKey = await resolveBranchApiKey(branchCode);
        if (apiKey == null || apiKey.isEmpty) {
          continue;
        }

        final headers = {
          'Authorization': 'Bearer $apiKey',
          'X-API-Key': apiKey,
          'Content-Type': 'application/json',
        };

        try {
          final resp = await _backgroundDio.get(
            '$digitaxZambiaApiBaseUrl/items/$itemId',
            options: Options(
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );

          if (resp.statusCode == 200 && resp.data is Map) {
            final remoteMap = _extractRemoteItemMap(resp.data);
            final previousStatus = p.digitaxSyncStatus;
            final previousRemotePrice = p.digitaxRemotePrice;

            _applyRemoteItemStatusToProduct(p, remoteMap);

            // If item just transitioned from PENDING -> COMPLETED, push initial stock if remote stock is 0
            if (previousStatus == 'PENDING' &&
                p.digitaxSyncStatus == 'COMPLETED' &&
                p.stockLevel > 0) {
              final rawRemoteStock =
                  remoteMap['stock_quantity'] ??
                  remoteMap['stock'] ??
                  remoteMap['quantity'] ??
                  0;
              final remoteStock = rawRemoteStock is num
                  ? rawRemoteStock.toInt()
                  : (int.tryParse(rawRemoteStock.toString()) ?? 0);
              if (remoteStock == 0) {
                try {
                  await _backgroundDio.put(
                    '$digitaxZambiaApiBaseUrl/stock/adjust',
                    data: {
                      "item_id": itemId,
                      "quantity": p.stockLevel.abs(),
                      "action": "ADD",
                      "movement_type": "01",
                    },
                    options: Options(headers: headers),
                  );
                } catch (_) {}
              }
            }

            // If local price differs from DigiTax price and item is not FAILED, push local price to DigiTax
            if (p.hasDigitaxPriceMismatch &&
                p.price > 0 &&
                p.digitaxSyncStatus != 'FAILED') {
              try {
                final putResp = await _backgroundDio.put(
                  '$digitaxZambiaApiBaseUrl/items/$itemId',
                  data: {
                    "item_name": p.name.trim(),
                    "default_unit_price": p.price,
                    "recommended_retail_price": p.price,
                  },
                  options: Options(
                    headers: headers,
                    validateStatus: (s) => s != null && s < 500,
                  ),
                );
                if (putResp.statusCode == 200 || putResp.statusCode == 201) {
                  final putMap = _extractRemoteItemMap(putResp.data);
                  _applyRemoteItemStatusToProduct(
                    p,
                    putMap,
                    updateRemotePrice: false,
                  );
                  p.digitaxRemotePrice = p.price;
                }
              } catch (e) {
                debugPrint('DIGITAX_LIVE_PRICE_SYNC_NOTE: $e');
              }
            }

            if (p.digitaxSyncStatus != previousStatus ||
                p.digitaxRemotePrice != previousRemotePrice) {
              await db.isar.writeTxn(() async {
                await db.isar.products.put(p);
              });
              updatedCount++;
            }
          }
        } catch (e) {
          debugPrint('DIGITAX_POLL_ITEM_NOTE ($itemId): $e');
        }
      }

      if (updatedCount > 0) {
        await deduplicateLocalProducts();
      }
    } finally {
      _isPollingItemStatus = false;
    }
    return updatedCount;
  }

  /// Explicitly checks or retries DigiTax synchronization for a single [product] on user demand.
  /// Returns the resulting `digitaxSyncStatus` (`COMPLETED`, `PENDING`, `FAILED`, or `OFFLINE`).
  Future<String> checkSingleProductDigitaxStatus(Product product) async {
    if (!product.isDigitaxSyncEnabled) {
      return 'OFFLINE';
    }
    final db = ref.read(databaseServiceProvider);
    final branchCode = product.branchCode.trim().isNotEmpty
        ? product.branchCode.trim()
        : '00';
    final apiKey = await resolveBranchApiKey(branchCode);
    if (apiKey == null || apiKey.isEmpty) {
      throw 'DigiTax API Key is missing for branch $branchCode.';
    }

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    if (product.hasUsableDigitaxItemId &&
        product.digitaxSyncStatus != 'FAILED') {
      final itemId = product.itemClsCd.trim();
      final resp = await _dio.get(
        '$digitaxZambiaApiBaseUrl/items/$itemId',
        options: Options(
          headers: headers,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (resp.statusCode == 200 && resp.data is Map) {
        final remoteMap = _extractRemoteItemMap(resp.data);
        _applyRemoteItemStatusToProduct(product, remoteMap);

        if (product.hasDigitaxPriceMismatch && product.price > 0) {
          final putResp = await _dio.put(
            '$digitaxZambiaApiBaseUrl/items/$itemId',
            data: {
              "item_name": product.name.trim(),
              "default_unit_price": product.price,
              "recommended_retail_price": product.price,
            },
            options: Options(
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (putResp.statusCode == 200 || putResp.statusCode == 201) {
            product.digitaxRemotePrice = product.price;
          }
        }

        await db.isar.writeTxn(() async {
          await db.isar.products.put(product);
        });
        return product.digitaxSyncStatus;
      }
    }

    // If item was FAILED, UNSYNCED, or not found by ID, re-run full single-product registration/update
    await syncSingleProductToDigitax(product, throwOnError: true);
    return product.digitaxSyncStatus;
  }

  // --------------------------------------------------------------------------
  // 1. DE-DUPLICATION ENGINE
  // --------------------------------------------------------------------------

  /// Canonical branch code normalization (preserves configured custom code like '000', 'HQ', '00', etc.)
  static String normalizeBranchCode(String? value, {String? defaultBhfId}) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return (defaultBhfId != null && defaultBhfId.trim().isNotEmpty)
          ? defaultBhfId.trim()
          : '00';
    }
    return trimmed;
  }

  /// Resolves the isolated DigiTax API key for a specific branch.
  /// Each branch MUST have its own isolated API key and isolated catalog.
  Future<String?> resolveBranchApiKey(String? branchCode) async {
    final db = ref.read(databaseServiceProvider);
    final config =
        ref.read(storeConfigProvider).value ??
        await db.isar.storeConfigs.where().findFirst();

    final normConfig = normalizeBranchCode(config?.bhfId);
    final targetBhf = normalizeBranchCode(branchCode, defaultBhfId: normConfig);

    // 1. If this branch matches this device's configured store, use that key
    if (targetBhf == normConfig &&
        config?.digitaxApiKey?.trim().isNotEmpty == true) {
      return config!.digitaxApiKey!.trim();
    }

    // 2. Look up the branch in StoreBranch collection
    final branch = await db.isar.storeBranchs
        .filter()
        .bhfIdEqualTo(targetBhf)
        .or()
        .codeEqualTo(targetBhf)
        .findFirst();

    if (branch?.digitaxApiKey?.trim().isNotEmpty == true) {
      return branch!.digitaxApiKey!.trim();
    }

    // 3. Fallback to active config key ONLY if target is HQ / main store
    if (targetBhf == '00' ||
        targetBhf == '000' ||
        targetBhf == '001' ||
        targetBhf == normConfig) {
      return config?.digitaxApiKey?.trim();
    }

    // For any isolated non-HQ branch with no key of its own, return null to prevent
    // contaminating another branch's or HQ's catalog!
    return null;
  }

  /// Purge all duplicate products in the local database, keeping only one unique entry per DigiTax ID or name/SKU per branch
  Future<int> deduplicateLocalProducts({String? branchCode}) async {
    final db = ref.read(databaseServiceProvider);
    final localSql = ref.read(localSqlServiceProvider);
    final config =
        ref.read(storeConfigProvider).value ??
        await db.isar.storeConfigs.where().findFirst();
    final configuredBhfId = config?.bhfId.trim().isNotEmpty == true
        ? config!.bhfId.trim()
        : '00';
    final isar = db.isar;

    String canonicalBranchBucket(String? rawBranch) {
      final norm = normalizeBranchCode(
        rawBranch,
        defaultBhfId: configuredBhfId,
      );
      if (norm == '00' ||
          norm == '000' ||
          norm == '001' ||
          norm == '01' ||
          norm == configuredBhfId) {
        return configuredBhfId;
      }
      return norm;
    }

    final targetBranch = branchCode != null
        ? canonicalBranchBucket(branchCode)
        : null;
    final allProducts = await isar.products.where().findAll();

    // Sort so records with a valid DigiTax item_ ID and COMPLETED status come first as canonical
    allProducts.sort((a, b) {
      final aHasId = a.hasUsableDigitaxItemId ? 0 : 1;
      final bHasId = b.hasUsableDigitaxItemId ? 0 : 1;
      if (aHasId != bHasId) {
        return aHasId.compareTo(bHasId);
      }
      int statusRank(String s) {
        switch (s.toUpperCase()) {
          case 'COMPLETED':
            return 0;
          case 'PENDING':
            return 1;
          case 'FAILED':
            return 2;
          default:
            return 3;
        }
      }

      final aRank = statusRank(a.digitaxSyncStatus);
      final bRank = statusRank(b.digitaxSyncStatus);
      if (aRank != bRank) {
        return aRank.compareTo(bRank);
      }
      return a.id.compareTo(b.id);
    });

    final Map<String, Product> canonicalByDtId = {};
    final Map<String, Product> canonicalByNameAndSku = {};
    final Map<String, Product> canonicalByName = {};
    final List<Id> duplicateIdsToDelete = [];
    final List<Product> productsToUpdate = [];

    for (final p in allProducts) {
      final normBranch = canonicalBranchBucket(p.branchCode);
      if (p.branchCode != normBranch) {
        p.branchCode = normBranch;
        if (!productsToUpdate.contains(p)) {
          productsToUpdate.add(p);
        }
      }

      if (p.isArchived) {
        continue;
      }

      // If filtering for a specific branch, only deduplicate that branch
      if (targetBranch != null && normBranch != targetBranch) {
        continue;
      }

      final dtItemId = p.hasUsableDigitaxItemId ? p.itemClsCd.trim() : '';
      final nameKey = p.name.trim().toLowerCase();
      final skuKey = p.sku.trim().toLowerCase();

      final dtKey = dtItemId.isNotEmpty ? '${normBranch}_dt_$dtItemId' : '';
      final nameSkuKey = nameKey.isNotEmpty
          ? '${normBranch}_ns_${nameKey}_$skuKey'
          : '';
      final branchNameKey = nameKey.isNotEmpty
          ? '${normBranch}_n_$nameKey'
          : '';

      Product? existingMatch;
      if (dtKey.isNotEmpty) {
        existingMatch = canonicalByDtId[dtKey];
      }
      if (existingMatch == null && nameSkuKey.isNotEmpty) {
        final candidate = canonicalByNameAndSku[nameSkuKey];
        if (candidate != null) {
          final cDtId = candidate.hasUsableDigitaxItemId
              ? candidate.itemClsCd.trim()
              : '';
          if (dtItemId.isEmpty || cDtId.isEmpty || dtItemId == cDtId) {
            existingMatch = candidate;
          }
        }
      }
      if (existingMatch == null && branchNameKey.isNotEmpty) {
        final candidate = canonicalByName[branchNameKey];
        if (candidate != null) {
          final cDtId = candidate.hasUsableDigitaxItemId
              ? candidate.itemClsCd.trim()
              : '';
          // Merge by name when one record is the pulled DigiTax item (with item_... as SKU or ID)
          // and the other is the local record created without a DigiTax item_ ID
          if ((dtItemId.isEmpty && cDtId.isNotEmpty) ||
              (dtItemId.isNotEmpty && cDtId.isEmpty)) {
            existingMatch = candidate;
          }
        }
      }

      if (existingMatch != null && existingMatch.id != p.id) {
        bool modified = false;

        // Keep higher / non-zero stock
        if (p.stockLevel > existingMatch.stockLevel) {
          existingMatch.stockLevel = p.stockLevel;
          modified = true;
        }

        // Keep non-zero price
        if (p.price > 0 && existingMatch.price == 0) {
          existingMatch.price = p.price;
          modified = true;
        }
        if (p.unitCost > 0 && existingMatch.unitCost == 0) {
          existingMatch.unitCost = p.unitCost;
          modified = true;
        }

        // Prefer real barcode/SKU over auto-generated item_... SKU
        if (existingMatch.sku.trim().startsWith('item_') &&
            p.sku.trim().isNotEmpty &&
            !p.sku.trim().startsWith('item_')) {
          existingMatch.sku = p.sku.trim();
          modified = true;
        }

        // Keep specific category if existing is default
        if (p.categoryId != 0 && existingMatch.categoryId == 0) {
          existingMatch.categoryId = p.categoryId;
          modified = true;
        }

        // Keep DigiTax item ID and UNSPSC class code
        if (p.hasUsableDigitaxItemId && !existingMatch.hasUsableDigitaxItemId) {
          if (!existingMatch.itemClsCd.startsWith('item_') &&
              existingMatch.itemClsCd.trim().length >= 8) {
            existingMatch.zraUnspscClassCode = existingMatch.itemClsCd.trim();
          }
          existingMatch.itemClsCd = p.itemClsCd.trim();
          modified = true;
        }
        if ((existingMatch.zraUnspscClassCode.isEmpty ||
                existingMatch.zraUnspscClassCode == '10101501') &&
            p.zraUnspscClassCode.isNotEmpty &&
            p.zraUnspscClassCode != '10101501') {
          existingMatch.zraUnspscClassCode = p.zraUnspscClassCode;
          modified = true;
        }

        // Keep DigiTax sync status & date
        if (p.isSyncedWithDigitax && !existingMatch.isSyncedWithDigitax) {
          existingMatch.isSyncedWithDigitax = true;
          existingMatch.lastDigitaxSyncDate =
              p.lastDigitaxSyncDate ?? DateTime.now();
          modified = true;
        }
        if (existingMatch.digitaxSyncStatus == 'UNSYNCED' &&
            p.digitaxSyncStatus != 'UNSYNCED') {
          existingMatch.digitaxSyncStatus = p.digitaxSyncStatus;
          existingMatch.digitaxSyncError = p.digitaxSyncError;
          existingMatch.digitaxRemotePrice =
              p.digitaxRemotePrice ?? existingMatch.digitaxRemotePrice;
          modified = true;
        }

        // Keep image if present
        if (p.imagePath != null &&
            p.imagePath!.isNotEmpty &&
            (existingMatch.imagePath == null ||
                existingMatch.imagePath!.isEmpty)) {
          existingMatch.imagePath = p.imagePath;
          modified = true;
        }

        if (modified && !productsToUpdate.contains(existingMatch)) {
          productsToUpdate.add(existingMatch);
        }

        if (existingMatch.hasUsableDigitaxItemId) {
          canonicalByDtId['${normBranch}_dt_${existingMatch.itemClsCd.trim()}'] =
              existingMatch;
        }
        productsToUpdate.remove(p);
        duplicateIdsToDelete.add(p.id);
      } else {
        if (dtKey.isNotEmpty) {
          canonicalByDtId[dtKey] = p;
        }
        if (nameSkuKey.isNotEmpty) {
          canonicalByNameAndSku[nameSkuKey] = p;
        }
        if (branchNameKey.isNotEmpty) {
          canonicalByName[branchNameKey] = p;
        }
      }
    }

    if (duplicateIdsToDelete.isNotEmpty || productsToUpdate.isNotEmpty) {
      await isar.writeTxn(() async {
        for (final p in productsToUpdate) {
          await isar.products.put(p);
        }
        for (final id in duplicateIdsToDelete) {
          await isar.products.delete(id);
        }
      });

      try {
        for (final id in duplicateIdsToDelete) {
          await localSql.db.delete(
            'products',
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        for (final p in productsToUpdate) {
          await localSql.db.update(
            'products',
            {
              'name': p.name,
              'price': p.price,
              'stock_level': p.stockLevel,
              'branch_code': p.branchCode,
              'is_synced_with_digitax': p.isSyncedWithDigitax ? 1 : 0,
            },
            where: 'id = ?',
            whereArgs: [p.id],
          );
        }
      } catch (_) {}

      debugPrint(
        'DIGITAX_DEDUPLICATION: Removed ${duplicateIdsToDelete.length} duplicate products, updated ${productsToUpdate.length} canonical records.',
      );
    }
    return duplicateIdsToDelete.length;
  }

  // --------------------------------------------------------------------------
  // 2. INSTANT ON-DEMAND SYNC TRIGGER
  // --------------------------------------------------------------------------

  /// Trigger an instant bidirectional sync with DigiTax
  Future<DigiTaxSyncResult> triggerInstantSync({String? branchCode}) async {
    ref
        .read(digiTaxAutoSyncProvider.notifier)
        .updateStatus(isSyncing: true, lastStatus: 'Syncing with DigiTax...');

    final result = await syncAllInventoryWithDigitax(branchCode: branchCode);

    ref
        .read(digiTaxAutoSyncProvider.notifier)
        .updateStatus(
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

        final bizName =
            infoMap['business_name'] ?? infoMap['name'] ?? 'DigiTax Merchant';
        final tpin = infoMap['tpin'] ?? 'Registered';

        return DigiTaxTestResult(
          success: true,
          statusCode: 200,
          message:
              'HTTP 200 OK: Connected to DigiTax ($bizName • TPIN: $tpin). Live ZRA VSDC active!',
          businessInfo: infoMap,
        );
      } else {
        return DigiTaxTestResult(
          success: false,
          statusCode: response.statusCode,
          message:
              'Server returned HTTP ${response.statusCode}: ${response.data}',
        );
      }
    } on DioException catch (dioErr) {
      final statusCode = dioErr.response?.statusCode;
      final responseData = dioErr.response?.data;
      String errorMsg = 'DigiTax Server Error';

      if (statusCode == 401) {
        errorMsg = 'HTTP 401 Unauthorized: Invalid DigiTax Secret API Key.';
      } else if (statusCode == 403) {
        errorMsg =
            'HTTP 403 Forbidden: API key does not have permission for this DigiTax VSDC endpoint.';
      } else if (statusCode == 404) {
        errorMsg = 'HTTP 404: Endpoint not found on DigiTax API.';
      } else if (dioErr.type == DioExceptionType.connectionTimeout ||
          dioErr.type == DioExceptionType.receiveTimeout) {
        errorMsg =
            'Connection Timeout: Could not reach DigiTax API server within 20 seconds.';
      } else if (dioErr.type == DioExceptionType.connectionError) {
        errorMsg =
            'Network Connection Error: Check your internet connection (${dioErr.message})';
      } else {
        errorMsg =
            'Server Error [HTTP $statusCode]: ${responseData ?? dioErr.message}';
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
      final config = await db.isar.storeConfigs.where().findFirst();

      final isOwner = ref.read(isOwnerProvider);
      final currentUser = ref.read(authProvider);
      final configuredBhfId = config?.bhfId.trim().isNotEmpty == true
          ? config!.bhfId.trim()
          : '00';
      final String bhfId;
      if (branchCode != null && branchCode.isNotEmpty) {
        bhfId = branchCode.trim();
      } else if (!isOwner &&
          currentUser?.branchCode != null &&
          currentUser!.branchCode!.isNotEmpty) {
        bhfId = currentUser.branchCode!.trim();
      } else {
        bhfId = configuredBhfId;
      }

      // 2. Resolve the isolated DigiTax API key for THIS specific branch
      final apiKey = await resolveBranchApiKey(bhfId);
      if (apiKey == null || apiKey.isEmpty) {
        return DigiTaxSyncResult(
          success: false,
          statusCode: 401,
          message:
              'DigiTax Secret API Key is not configured for branch $bhfId. Each branch must have its own isolated DigiTax API key.',
        );
      }

      final isCurrentHq = isOwner || bhfId == configuredBhfId;

      final headers = {
        'Authorization': 'Bearer $apiKey',
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      };

      int pushedCount = 0;
      int pulledCount = 0;
      final List<String> errors = [];

      // 1. Deduplicate existing local products first so we start with a clean catalog
      try {
        await deduplicateLocalProducts(branchCode: bhfId);
      } catch (_) {}

      // Do not continue to imports or uploads unless the remote catalogue was read.
      List<Map<String, dynamic>> remoteList;
      try {
        remoteList = await _fetchAllRemoteItems(headers, forceRefresh: true);
      } catch (e) {
        return DigiTaxSyncResult(
          success: false,
          message:
              'DigiTax catalogue was not changed because its current items could not be read: $e',
          errors: ['Failed to fetch remote items: $e'],
        );
      }

      // Keep ambiguous names and barcodes as candidate lists, never first-match maps.
      final Map<String, Map<String, dynamic>> remoteById = {};
      final Map<String, List<Map<String, dynamic>>> remoteByName = {};
      final Map<String, List<Map<String, dynamic>>> remoteByCode = {};

      for (final item in remoteList) {
        final id = (item['id'] ?? item['item_id'] ?? '').toString();
        final name = (item['item_name'] ?? item['itemNm'] ?? item['name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final code =
            (item['item_code'] ??
                    item['itemCd'] ??
                    item['bar_code'] ??
                    item['barcode'] ??
                    item['sku'] ??
                    '')
                .toString()
                .trim();
        if (id.isNotEmpty) {
          remoteById[id] = item;
        }
        if (name.isNotEmpty) {
          remoteByName.putIfAbsent(name, () => []).add(item);
        }
        if (code.isNotEmpty) {
          remoteByCode.putIfAbsent(code.toLowerCase(), () => []).add(item);
        }
      }

      // ──────────────────────────────────────────────────────────────────────────
      // 3. Pull — Branch-Isolated Sync
      // ──────────────────────────────────────────────────────────────────────────
      final allLocalProducts = await db.isar.products.where().findAll();
      final branchProducts = allLocalProducts
          .where(
            (p) => _belongsToTargetBranch(
              p.branchCode,
              bhfId,
              configuredBhfId,
              isCurrentHq,
            ),
          )
          .toList();
      for (final r in remoteList) {
        final rId = (r['id'] ?? r['item_id'] ?? r['itemId'] ?? '')
            .toString()
            .trim();
        final rItemCode = (r['item_code'] ?? r['itemCd'] ?? r['itemCode'] ?? '')
            .toString()
            .trim();
        final rBarcode = (r['bar_code'] ?? r['barcode'] ?? r['sku'] ?? '')
            .toString()
            .trim();
        final rName =
            (r['item_name'] ?? r['itemNm'] ?? r['itemName'] ?? r['name'] ?? '')
                .toString()
                .trim();
        final rPrice =
            double.tryParse(
              (r['default_unit_price'] ?? r['dftPrc'] ?? r['price'] ?? '0')
                  .toString(),
            ) ??
            0.0;
        final rawStock =
            r['stock_quantity'] ??
            r['stockQuantity'] ??
            r['stock_qty'] ??
            r['current_stock'] ??
            r['stock_level'] ??
            r['quantity'] ??
            r['qty'] ??
            0;
        final remoteStock = rawStock is num
            ? rawStock.toInt()
            : (int.tryParse(rawStock.toString()) ?? 0);

        if (rName.isEmpty) {
          continue;
        }
        if (rId.isEmpty) {
          debugPrint(
            'DIGITAX_PULL_SKIP: Remote item "$rName" has no stable DigiTax ID; refusing to match by name or SKU.',
          );
          continue;
        }

        final remoteSku = rBarcode.isNotEmpty
            ? rBarcode
            : (rItemCode.isNotEmpty ? rItemCode : rId);
        final existing = _findMatchingLocalProductForRemoteItem(
          branchProducts: branchProducts,
          rId: rId,
          rBarcode: rBarcode,
          rItemCode: rItemCode,
          rName: rName,
        );

        if (existing != null) {
          if (existing.isArchived) {
            continue;
          }
          existing.branchCode = bhfId;
          if (!existing.itemClsCd.startsWith('item_') &&
              existing.itemClsCd.trim().length >= 8) {
            existing.zraUnspscClassCode = existing.itemClsCd.trim();
          }
          existing.itemClsCd = rId;
          final hadLocalPriceChange =
              existing.digitaxRemotePrice != null &&
              (existing.price - existing.digitaxRemotePrice!).abs() > 0.01 &&
              (existing.price - rPrice).abs() > 0.01;
          if (!hadLocalPriceChange && existing.price != rPrice && rPrice > 0) {
            existing.price = rPrice;
          }
          if (existing.stockLevel != remoteStock && remoteStock > 0) {
            existing.stockLevel = remoteStock;
          }
          _applyRemoteItemStatusToProduct(existing, r);
          await db.isar.writeTxn(() async {
            await db.isar.products.put(existing);
          });
          pulledCount++;
        } else {
          final imported = Product(
            name: rName,
            sku: remoteSku.isNotEmpty ? remoteSku : rName,
            price: rPrice,
            stockLevel: remoteStock,
            categoryId: 0,
            itemClsCd: rId.isNotEmpty ? rId : '10101501',
            branchCode: bhfId,
            branchName: config?.branchName,
            isSyncedWithDigitax: false,
            isDigitaxSyncEnabled: true,
            lastDigitaxSyncDate: DateTime.now(),
          );
          _applyRemoteItemStatusToProduct(imported, r);
          await db.isar.writeTxn(() async {
            await db.isar.products.put(imported);
          });
          branchProducts.add(imported);
          pulledCount++;
        }
      }

      // 4. Push local products & price updates UP to DigiTax (Only for products belonging to this branch!)
      final localProducts = await db.getAllProducts(branchCode: bhfId);

      for (final p in localProducts) {
        // Offline / Exempt items (isDigitaxSyncEnabled == false) or Tax Exclusive items are local-only stock: do not push to DigiTax
        if (!p.isDigitaxSyncEligible) {
          continue;
        }

        try {
          final pNameKey = p.name.trim().toLowerCase();
          final pCodeKey = p.sku.trim().toLowerCase();
          final storedItemId = p.hasUsableDigitaxItemId
              ? p.itemClsCd.trim()
              : '';
          final nameCandidates = remoteByName[pNameKey] ?? const [];
          final codeCandidates = pCodeKey.isNotEmpty
              ? remoteByCode[pCodeKey] ?? const []
              : const <Map<String, dynamic>>[];
          final candidatePool = codeCandidates.isNotEmpty
              ? codeCandidates
              : nameCandidates;
          final localClass = p.zraUnspscClassCode.trim().toLowerCase();
          final hasSpecificClass =
              localClass.isNotEmpty &&
              localClass != '10101501' &&
              localClass != '56101530';
          final classCandidates = hasSpecificClass
              ? candidatePool.where((candidate) {
                  final code =
                      (candidate['item_class_code'] ??
                              candidate['itemClsCd'] ??
                              candidate['item_cls_cd'] ??
                              '')
                          .toString()
                          .trim()
                          .toLowerCase();
                  return code == localClass;
                }).toList()
              : candidatePool;

          Map<String, dynamic>? existingRemote;
          if (storedItemId.isNotEmpty) {
            existingRemote = remoteById[storedItemId];
          } else if (codeCandidates.length == 1) {
            existingRemote = codeCandidates.single;
          } else if (nameCandidates.length == 1) {
            existingRemote = nameCandidates.single;
          } else if (classCandidates.length == 1) {
            existingRemote = classCandidates.single;
          }

          if (storedItemId.isNotEmpty && existingRemote == null) {
            errors.add(
              'Skipped "${p.name}": DigiTax item ID "$storedItemId" is not present in the remote catalogue.',
            );
            continue;
          }
          if (storedItemId.isEmpty &&
              existingRemote == null &&
              candidatePool.isNotEmpty) {
            errors.add(
              'Skipped "${p.name}": DigiTax match is ambiguous across multiple remote items.',
            );
            continue;
          }

          if (existingRemote != null) {
            final remoteId = (existingRemote['id'] ?? '').toString().trim();
            final remotePrice =
                double.tryParse(
                  (existingRemote['default_unit_price'] ?? '0').toString(),
                ) ??
                0.0;

            _applyRemoteItemStatusToProduct(p, existingRemote);

            if (remoteId.isNotEmpty) {
              p.itemClsCd = remoteId;

              if (p.price > 0 && (p.price - remotePrice).abs() > 0.01) {
                try {
                  final putResp = await _dio.put(
                    '$digitaxZambiaApiBaseUrl/items/$remoteId',
                    data: {
                      "item_name": p.name.trim(),
                      "default_unit_price": p.price,
                      "recommended_retail_price": p.price,
                    },
                    options: Options(headers: headers),
                  );
                  if (putResp.statusCode == 200 || putResp.statusCode == 201) {
                    final putMap = _extractRemoteItemMap(putResp.data);
                    _applyRemoteItemStatusToProduct(
                      p,
                      putMap,
                      updateRemotePrice: false,
                    );
                    p.digitaxRemotePrice = p.price;
                  }
                } catch (putErr) {
                  debugPrint(
                    'DIGITAX_SYNC_PRICE_UPDATE_ERROR (${p.name}): $putErr',
                  );
                }
              }
            }

            p.lastDigitaxSyncDate = DateTime.now();
            await db.isar.writeTxn(() async {
              await db.isar.products.put(p);
            });
            pushedCount++;
          } else {
            // Strictly valid payload per company tax system
            final isTot = config?.businessTaxType == 'TURNOVER_TAX';
            final vatCategoryCode = resolveCompliantVatCategoryCode(
              zraTaxCode: p.zraTaxCode,
              taxRate: p.taxRate,
              isTotBusiness: isTot,
            );
            final classCode = resolveCompliantItemClassCode(
              explicitClsCode: p.zraUnspscClassCode,
              zraTaxCode: p.zraTaxCode,
              productName: p.name,
            );

            final payload = {
              "item_class_code": classCode,
              "item_type_code": "2", // Finished Product
              "item_name": p.name.trim(),
              "origin_nation_code": "ZM",
              "package_unit_code": _resolvePackageUnitCode(p.unitOfMeasure),
              "quantity_unit_code": _resolveQuantityUnitCode(p.unitOfMeasure),
              "vat_category_code": vatCategoryCode,
              if (isTot) "tot_category_code": "TOT",
              "default_unit_price": p.price > 0 ? p.price : 1.0,
              "recommended_retail_price": p.price > 0 ? p.price : 1.0,
              "stock_quantity": p.stockLevel > 0 ? p.stockLevel : 0,
              "is_stock_item": true,
              if (p.sku.isNotEmpty) "bar_code": p.sku.trim(),
            };

            final resp = await _dio.post(
              '$digitaxZambiaApiBaseUrl/items',
              data: payload,
              options: Options(headers: headers),
            );

            if (resp.statusCode == 200 || resp.statusCode == 201) {
              final remoteMap = _extractRemoteItemMap(resp.data);
              final itemId = _extractRemoteItemId(resp.data);
              if (itemId != null) {
                p.itemClsCd = itemId;
              }
              p.zraUnspscClassCode = classCode;
              _applyRemoteItemStatusToProduct(p, remoteMap);
              if (p.digitaxRemotePrice == null && p.price > 0) {
                p.digitaxRemotePrice = p.price;
              }

              // The catalogue snapshot was fetched before this upload. Add this item
              // to it so another local copy in the same sync run links to this record.
              final createdRemoteItem = <String, dynamic>{
                'id': ?itemId,
                'item_name': p.name.trim(),
                'item_code': p.sku.trim(),
                'bar_code': p.sku.trim(),
                'item_class_code': classCode,
                'status': p.digitaxSyncStatus,
                'default_unit_price': p.price,
              };
              if (itemId != null) {
                remoteById[itemId] = createdRemoteItem;
              }
              remoteByName
                  .putIfAbsent(p.name.trim().toLowerCase(), () => [])
                  .add(createdRemoteItem);
              if (p.sku.trim().isNotEmpty) {
                remoteByCode
                    .putIfAbsent(p.sku.trim().toLowerCase(), () => [])
                    .add(createdRemoteItem);
              }

              if (p.digitaxSyncStatus == 'COMPLETED' &&
                  p.stockLevel > 0 &&
                  p.itemClsCd.isNotEmpty) {
                try {
                  await _dio.put(
                    '$digitaxZambiaApiBaseUrl/stock/adjust',
                    data: {
                      "item_id": p.itemClsCd,
                      "quantity": p.stockLevel.abs(),
                      "action": "ADD",
                      "movement_type": "01",
                    },
                    options: Options(headers: headers),
                  );
                } catch (_) {}
              }

              await db.isar.writeTxn(() async {
                await db.isar.products.put(p);
              });

              try {
                await localSql.db.update(
                  'products',
                  {
                    'is_synced_with_digitax': p.isSyncedWithDigitax ? 1 : 0,
                    'last_digitax_sync_date': DateTime.now().toIso8601String(),
                  },
                  where: 'id = ?',
                  whereArgs: [p.id],
                );
              } catch (_) {}

              pushedCount++;
              debugPrint(
                'DIGITAX_PUSH_SUCCESS: Uploaded item "${p.name}" on DigiTax [Status: ${p.digitaxSyncStatus}] (Tax: ${isTot ? "TOT" : "VAT"})',
              );
            }
          }
        } on DioException catch (dioErr) {
          final serverMsg = dioErr.response?.data is Map
              ? (dioErr.response?.data['message'] ??
                    dioErr.response?.data['error'] ??
                    dioErr.response?.data.toString())
              : (dioErr.response?.data?.toString() ?? dioErr.message);
          if (dioErr.response?.statusCode == 409 ||
              (dioErr.response?.statusCode == 400 &&
                  dioErr.response?.data.toString().contains('already exists') ==
                      true)) {
            errors.add(
              'DigiTax reports "${p.name}" already exists, but its item ID could not be matched. Sync again after refreshing the catalogue; no duplicate was created.',
            );
          } else {
            p.digitaxSyncStatus = 'FAILED';
            p.digitaxSyncError =
                'HTTP ${dioErr.response?.statusCode ?? "ERR"}: $serverMsg';
            await db.isar.writeTxn(() async {
              await db.isar.products.put(p);
            });
            errors.add(
              'Failed to push "${p.name}" to DigiTax [HTTP ${dioErr.response?.statusCode}]: $serverMsg',
            );
          }
        } catch (e) {
          errors.add('Failed to push "${p.name}" to DigiTax: $e');
        }
      }

      try {
        await deduplicateLocalProducts(branchCode: bhfId);
      } catch (_) {}

      final successMsg =
          'DigiTax Equilibrium Sync: Pulled $pulledCount, Pushed/Updated $pushedCount items.';
      debugPrint(successMsg);
      return DigiTaxSyncResult(
        success: errors.isEmpty,
        message: errors.isEmpty
            ? successMsg
            : '$successMsg (${errors.length} errors encountered)',
        pulledCount: pulledCount,
        pushedCount: pushedCount,
        errors: errors,
      );
    } catch (e) {
      debugPrint('DIGITAX_SYNC_ERROR: $e');
      return DigiTaxSyncResult(
        success: false,
        message: 'Sync error: $e',
        errors: [e.toString()],
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
    String? movementType,
    String? reasonNotes,
    bool throwOnError = false,
  }) async {
    if (!product.isDigitaxSyncEligible) {
      debugPrint(
        'DIGITAX_SINGLE_PUSH_SKIP: Product ${product.name} is marked offline/local only.',
      );
      return true;
    }

    final db = ref.read(databaseServiceProvider);
    final config = ref.read(storeConfigProvider).value;
    final currentUser = ref.read(authProvider);
    final effectiveBranchCode = (branchCode?.trim().isNotEmpty == true)
        ? branchCode!.trim().padLeft(2, '0')
        : (product.branchCode.trim().isNotEmpty
              ? product.branchCode.trim().padLeft(2, '0')
              : (currentUser?.branchCode?.trim().isNotEmpty == true
                    ? currentUser!.branchCode!.trim().padLeft(2, '0')
                    : (config?.bhfId.trim().isNotEmpty == true
                          ? config!.bhfId.trim().padLeft(2, '0')
                          : '00')));

    final apiKey = await resolveBranchApiKey(effectiveBranchCode);
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint(
        'DIGITAX_SINGLE_PUSH: DigiTax API Key is missing for branch $effectiveBranchCode',
      );
      if (throwOnError) {
        throw 'Branch $effectiveBranchCode does not have its own DigiTax API Key configured.';
      }
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

      if (product.hasUsableDigitaxItemId) {
        digitaxItemId = product.itemClsCd;
      } else {
        try {
          final remoteItems = await _fetchAllRemoteItems(headers);
          final normName = product.name.trim().toLowerCase();
          final normSku = product.sku.trim().toLowerCase();
          final localClass = product.zraUnspscClassCode.trim().toLowerCase();
          final hasSpecificClass =
              localClass.isNotEmpty &&
              localClass != '10101501' &&
              localClass != '56101530';
          final codeMatches = <Map<String, dynamic>>[];
          final nameMatches = <Map<String, dynamic>>[];
          final classMatches = <Map<String, dynamic>>[];

          for (final item in remoteItems) {
            final rId = (item['id'] ?? item['item_id'] ?? '').toString().trim();
            final rName = (item['item_name'] ?? item['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rCode =
                (item['bar_code'] ??
                        item['barcode'] ??
                        item['item_code'] ??
                        item['sku'] ??
                        '')
                    .toString()
                    .trim()
                    .toLowerCase();
            final rClass =
                (item['item_class_code'] ??
                        item['itemClsCd'] ??
                        item['item_cls_cd'] ??
                        '')
                    .toString()
                    .trim()
                    .toLowerCase();
            final codeMatchesProduct = normSku.isNotEmpty && rCode == normSku;
            final nameMatchesProduct = normName.isNotEmpty && rName == normName;

            if (rId.isEmpty && (codeMatchesProduct || nameMatchesProduct)) {
              debugPrint(
                'DIGITAX_SINGLE_PUSH_ABORT: A matching remote item had no stable DigiTax ID.',
              );
              return false;
            }
            if (codeMatchesProduct) {
              codeMatches.add(item);
            }
            if (nameMatchesProduct) {
              nameMatches.add(item);
            }
            if (hasSpecificClass && rClass == localClass) {
              classMatches.add(item);
            }
          }

          Map<String, dynamic>? matchedItem;
          if (codeMatches.length == 1) {
            matchedItem = codeMatches.single;
          } else if (nameMatches.length == 1) {
            matchedItem = nameMatches.single;
          } else {
            final baseMatches = codeMatches.isNotEmpty
                ? codeMatches
                : nameMatches;
            final filtered = hasSpecificClass
                ? classMatches
                      .where(
                        (item) =>
                            codeMatches.contains(item) ||
                            nameMatches.contains(item),
                      )
                      .toList()
                : baseMatches;
            if (filtered.length == 1) {
              matchedItem = filtered.single;
            } else if (baseMatches.isNotEmpty) {
              matchedItem = baseMatches.first;
            }
          }

          if (matchedItem != null) {
            digitaxItemId = (matchedItem['id'] ?? matchedItem['item_id'] ?? '')
                .toString()
                .trim();
            if (digitaxItemId.isEmpty) {
              debugPrint(
                'DIGITAX_SINGLE_PUSH_ABORT: A matching remote item had no stable DigiTax ID.',
              );
              return false;
            }
            _applyRemoteItemStatusToProduct(product, matchedItem);
            final rawSt =
                matchedItem['stock_quantity'] ??
                matchedItem['stock'] ??
                matchedItem['quantity'] ??
                0;
            remoteStock = rawSt is num
                ? rawSt.toInt()
                : (int.tryParse(rawSt.toString()) ?? 0);
          }
        } catch (e) {
          debugPrint('DIGITAX_FETCH_REMOTE_NOTE: $e');
          if (throwOnError) {
            rethrow;
          }
          return false;
        }
      }

      if (digitaxItemId != null && digitaxItemId.isNotEmpty) {
        final targetPrice = product.price > 0 ? product.price : 1.0;
        try {
          final putResp = await _dio.put(
            '$digitaxZambiaApiBaseUrl/items/$digitaxItemId',
            data: {
              "item_name": product.name.trim(),
              "default_unit_price": targetPrice,
              "recommended_retail_price": targetPrice,
            },
            options: Options(headers: headers),
          );
          if (putResp.statusCode == 200 || putResp.statusCode == 201) {
            final putMap = _extractRemoteItemMap(putResp.data);
            _applyRemoteItemStatusToProduct(
              product,
              putMap,
              updateRemotePrice: false,
            );
            product.digitaxRemotePrice = targetPrice;
          }
        } catch (e) {
          debugPrint('DIGITAX_UPDATE_PRICE_NOTE: $e');
          product.digitaxSyncError = 'Price update failed on DigiTax: $e';
          await db.isar.writeTxn(() async {
            await db.isar.products.put(product);
          });
          if (throwOnError) {
            rethrow;
          }
        }

        // Also fetch latest item record from DigiTax to confirm live ZRA status (PENDING / COMPLETED / FAILED)
        try {
          final statusResp = await _dio.get(
            '$digitaxZambiaApiBaseUrl/items/$digitaxItemId',
            options: Options(
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (statusResp.statusCode == 200 && statusResp.data is Map) {
            final statusMap = _extractRemoteItemMap(statusResp.data);
            _applyRemoteItemStatusToProduct(product, statusMap);
            product.digitaxRemotePrice = targetPrice;
          }
        } catch (_) {}

        // 2. Adjust Stock Quantity on DigiTax (PUT /stock/adjust) when COMPLETED
        final baseStock = previousStock ?? remoteStock;
        final stockDiff = product.stockLevel - baseStock;
        if (stockDiff != 0 && product.digitaxSyncStatus == 'COMPLETED') {
          try {
            final effectiveMovementType =
                movementType ?? (stockDiff > 0 ? "06" : "16");
            final adjustPayload = <String, dynamic>{
              "item_id": digitaxItemId,
              "quantity": stockDiff.abs(),
              "action": stockDiff > 0 ? "ADD" : "DEDUCT",
              "movement_type": effectiveMovementType,
            };
            if (reasonNotes != null && reasonNotes.isNotEmpty) {
              adjustPayload["remarks"] = reasonNotes;
            }
            try {
              await _dio.put(
                '$digitaxZambiaApiBaseUrl/stock/adjust',
                data: adjustPayload,
                options: Options(headers: headers),
              );
            } on DioException catch (dioErr) {
              if (dioErr.response?.statusCode == 400 &&
                  adjustPayload.containsKey("remarks")) {
                adjustPayload.remove("remarks");
                await _dio.put(
                  '$digitaxZambiaApiBaseUrl/stock/adjust',
                  data: adjustPayload,
                  options: Options(headers: headers),
                );
              } else {
                rethrow;
              }
            }
            debugPrint(
              'DIGITAX_STOCK_ADJUST_SUCCESS: Adjusted item $digitaxItemId on DigiTax by $stockDiff [Type: $effectiveMovementType] (New Stock: ${product.stockLevel})',
            );
          } catch (stockErr) {
            debugPrint('DIGITAX_STOCK_ADJUST_ERROR: $stockErr');
          }
        }

        product.itemClsCd = digitaxItemId;
        product.lastDigitaxSyncDate = DateTime.now();
        await db.isar.writeTxn(() async {
          await db.isar.products.put(product);
        });
        if (product.digitaxSyncStatus == 'PENDING') {
          Future.delayed(
            const Duration(seconds: 4),
            () => pollPendingAndMismatchedItems(),
          );
        }
        return product.digitaxSyncStatus == 'COMPLETED';
      } else {
        // 3. Register as completely new product on DigiTax per Company Tax System
        final isTot = config?.businessTaxType == 'TURNOVER_TAX';
        final vatCategoryCode = resolveCompliantVatCategoryCode(
          zraTaxCode: product.zraTaxCode,
          taxRate: product.taxRate,
          isTotBusiness: isTot,
        );
        final classCode = resolveCompliantItemClassCode(
          explicitClsCode: product.zraUnspscClassCode,
          zraTaxCode: product.zraTaxCode,
          productName: product.name,
        );
        final targetPrice = product.price > 0 ? product.price : 1.0;

        final payload = {
          "item_class_code": classCode,
          "item_type_code": "2", // Finished product
          "item_name": product.name.trim(),
          "origin_nation_code": "ZM",
          "package_unit_code": _resolvePackageUnitCode(product.unitOfMeasure),
          "quantity_unit_code": _resolveQuantityUnitCode(product.unitOfMeasure),
          "vat_category_code": vatCategoryCode,
          if (isTot) "tot_category_code": "TOT",
          "default_unit_price": targetPrice,
          "recommended_retail_price": targetPrice,
          "stock_quantity": product.stockLevel > 0 ? product.stockLevel : 0,
          "is_stock_item": true,
          if (product.sku.isNotEmpty) "bar_code": product.sku.trim(),
        };

        final resp = await _dio.post(
          '$digitaxZambiaApiBaseUrl/items',
          data: payload,
          options: Options(headers: headers),
        );

        if (resp.statusCode == 200 || resp.statusCode == 201) {
          final remoteMap = _extractRemoteItemMap(resp.data);
          final newId = _extractRemoteItemId(resp.data);
          if (newId != null && newId.isNotEmpty) {
            product.itemClsCd = newId;
          }
          product.zraUnspscClassCode = classCode;
          _applyRemoteItemStatusToProduct(product, remoteMap);
          product.digitaxRemotePrice = targetPrice;
          await db.isar.writeTxn(() async {
            await db.isar.products.put(product);
          });

          // If DigiTax returned PENDING, poll briefly (up to 2 attempts, 1.5s apart)
          // so fast ZRA VSDC approvals flip to COMPLETED immediately.
          if (product.digitaxSyncStatus == 'PENDING' &&
              product.hasUsableDigitaxItemId) {
            for (int attempt = 1; attempt <= 2; attempt++) {
              await Future.delayed(const Duration(milliseconds: 1500));
              try {
                final checkResp = await _dio.get(
                  '$digitaxZambiaApiBaseUrl/items/${product.itemClsCd}',
                  options: Options(
                    headers: headers,
                    validateStatus: (s) => s != null && s < 500,
                  ),
                );
                if (checkResp.statusCode == 200 && checkResp.data is Map) {
                  final checkMap = _extractRemoteItemMap(checkResp.data);
                  _applyRemoteItemStatusToProduct(product, checkMap);
                  await db.isar.writeTxn(() async {
                    await db.isar.products.put(product);
                  });
                  if (product.digitaxSyncStatus != 'PENDING') {
                    break;
                  }
                }
              } catch (_) {}
            }
          }

          debugPrint(
            'DIGITAX_SINGLE_PUSH: Registered new item "${product.name}" on DigiTax [ID: ${product.itemClsCd}, Status: ${product.digitaxSyncStatus}] (Tax: ${isTot ? "TOT" : "VAT"}, Stock: ${product.stockLevel})',
          );

          if (product.digitaxSyncStatus == 'COMPLETED' &&
              product.stockLevel > 0 &&
              product.itemClsCd.isNotEmpty) {
            try {
              final adjResp = await _dio.put(
                '$digitaxZambiaApiBaseUrl/stock/adjust',
                data: {
                  "item_id": product.itemClsCd,
                  "quantity": product.stockLevel.abs(),
                  "action": "ADD",
                  "movement_type": movementType ?? "01",
                },
                options: Options(headers: headers),
              );
              debugPrint(
                'DIGITAX_STOCK_ADJUST_INIT_SUCCESS: [HTTP ${adjResp.statusCode}] Initial stock ${product.stockLevel} adjusted for ${product.name}',
              );
            } catch (adjErr) {
              debugPrint('DIGITAX_STOCK_ADJUST_INIT_ERROR: $adjErr');
            }
          } else if (product.digitaxSyncStatus == 'PENDING') {
            Future.delayed(
              const Duration(seconds: 4),
              () => pollPendingAndMismatchedItems(),
            );
          }

          return product.digitaxSyncStatus == 'COMPLETED';
        } else {
          final serverMsg = resp.data is Map
              ? (resp.data['message'] ??
                    resp.data['error'] ??
                    resp.data.toString())
              : resp.data.toString();
          product.digitaxSyncStatus = 'FAILED';
          product.digitaxSyncError =
              'HTTP ${resp.statusCode}: $serverMsg';
          await db.isar.writeTxn(() async {
            await db.isar.products.put(product);
          });
          if (throwOnError) {
            throw 'DigiTax HTTP ${resp.statusCode}: $serverMsg';
          }
        }
      }
    } on DioException catch (dioErr) {
      final serverMsg = dioErr.response?.data is Map
          ? (dioErr.response?.data['message'] ??
                dioErr.response?.data['error'] ??
                dioErr.response?.data.toString())
          : (dioErr.response?.data?.toString() ?? dioErr.message);
      if (dioErr.response?.statusCode == 409 ||
          (dioErr.response?.statusCode == 400 &&
              dioErr.response?.data.toString().contains('already exists') ==
                  true)) {
        product.digitaxSyncError =
            'Item already exists on DigiTax — run Sync to link its item ID.';
        product.lastDigitaxSyncDate = DateTime.now();
        await db.isar.writeTxn(() async {
          await db.isar.products.put(product);
        });
        return false;
      }
      product.digitaxSyncStatus = 'FAILED';
      product.digitaxSyncError =
          'HTTP ${dioErr.response?.statusCode ?? "ERR"}: $serverMsg';
      await db.isar.writeTxn(() async {
        await db.isar.products.put(product);
      });
      debugPrint('DIGITAX_SINGLE_PUSH_DIO_ERROR: $dioErr');
      if (throwOnError) {
        throw 'DigiTax HTTP ${dioErr.response?.statusCode ?? 'ERR'}: $serverMsg';
      }
    } catch (e) {
      debugPrint('DIGITAX_SINGLE_PUSH_ERROR: $e');
      if (throwOnError) {
        rethrow;
      }
    }
    return false;
  }

  /// Push a dedicated stock adjustment with specific ZRA reason & SAR code directly to DigiTax Cloud
  Future<bool> pushStockMovementAdjustment({
    required Product product,
    required String action, // 'ADD' or 'DEDUCT'
    required String
    movementType, // e.g. '02' Purchase, '06' Audit Surplus, '11' Damaged, '12' Expired, '13' Theft, '14' Store Use, '15' Vendor Return, '16' Shortage
    required int quantity,
    String? remarks,
    String? branchCode,
  }) async {
    if (!product.isDigitaxSyncEligible) {
      debugPrint(
        'DIGITAX_STOCK_ADJUST_SKIP: Product ${product.name} is marked offline/local only.',
      );
      return true;
    }

    final config = ref.read(storeConfigProvider).value;
    final currentUser = ref.read(authProvider);
    final resolvedBranchCode = (branchCode?.trim().isNotEmpty == true)
        ? branchCode!.trim().padLeft(2, '0')
        : (currentUser?.branchCode?.trim().isNotEmpty == true
              ? currentUser!.branchCode!.trim().padLeft(2, '0')
              : (config?.bhfId.trim().isNotEmpty == true
                    ? config!.bhfId.trim().padLeft(2, '0')
                    : '00'));

    final apiKey = await resolveBranchApiKey(resolvedBranchCode);
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint(
        'DIGITAX_STOCK_ADJUST_SKIP: API Key is missing for branch $resolvedBranchCode',
      );
      return false;
    }

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    try {
      String? digitaxItemId;

      // 1. Check if product itself has an item_ ID stored
      if (product.hasUsableDigitaxItemId) {
        digitaxItemId = product.itemClsCd;
      }

      // 2. Fetch full remote catalog with pagination to find this item by name or barcode/sku
      if (digitaxItemId == null || digitaxItemId.isEmpty) {
        try {
          final remoteItems = await _fetchAllRemoteItems(headers);
          final normName = product.name.trim().toLowerCase();
          final normSku = product.sku.trim().toLowerCase();

          for (final item in remoteItems) {
            final rName = (item['item_name'] ?? item['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rBarcode = (item['bar_code'] ?? item['barcode'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rCode = (item['item_code'] ?? item['sku'] ?? '')
                .toString()
                .trim()
                .toLowerCase();

            if ((normName.isNotEmpty && rName == normName) ||
                (normSku.isNotEmpty &&
                    (rBarcode == normSku || rCode == normSku))) {
              digitaxItemId = (item['id'] ?? item['item_id'] ?? '').toString();
              break;
            }
          }
        } catch (fetchErr) {
          debugPrint('DIGITAX_STOCK_ADJUST_FETCH_NOTE: $fetchErr');
        }
      }

      // 3. If still not registered on DigiTax, register it now so it exists in DigiTax!
      if (digitaxItemId == null || digitaxItemId.isEmpty) {
        try {
          await syncSingleProductToDigitax(product);
          final remoteItems = await _fetchAllRemoteItems(headers);
          final normName = product.name.trim().toLowerCase();
          final normSku = product.sku.trim().toLowerCase();
          for (final item in remoteItems) {
            final rName = (item['item_name'] ?? item['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rBarcode = (item['bar_code'] ?? item['barcode'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if ((normName.isNotEmpty && rName == normName) ||
                (normSku.isNotEmpty && rBarcode == normSku)) {
              digitaxItemId = (item['id'] ?? item['item_id'] ?? '').toString();
              break;
            }
          }
        } catch (regErr) {
          debugPrint('DIGITAX_STOCK_ADJUST_REG_NOTE: $regErr');
        }
      }

      if (digitaxItemId == null || digitaxItemId.isEmpty) {
        debugPrint(
          'DIGITAX_STOCK_ADJUST_ERROR: Could not find or register item ID on DigiTax for "${product.name}"',
        );
        return false;
      }

      final payload = <String, dynamic>{
        "item_id": digitaxItemId,
        "quantity": quantity.abs(),
        "action": action, // "ADD" or "DEDUCT"
        "movement_type": movementType,
      };
      if (remarks != null && remarks.trim().isNotEmpty) {
        payload["remarks"] = remarks.trim();
      }

      Response resp;
      try {
        resp = await _dio.put(
          '$digitaxZambiaApiBaseUrl/stock/adjust',
          data: payload,
          options: Options(headers: headers),
        );
      } on DioException catch (dioErr) {
        if (dioErr.response?.statusCode == 400 &&
            payload.containsKey('remarks')) {
          payload.remove('remarks');
          resp = await _dio.put(
            '$digitaxZambiaApiBaseUrl/stock/adjust',
            data: payload,
            options: Options(headers: headers),
          );
        } else {
          rethrow;
        }
      }

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        debugPrint(
          'DIGITAX_STOCK_ADJUST_SUCCESS: Adjusted item $digitaxItemId on DigiTax: $action $quantity (Type: $movementType, Notes: $remarks)',
        );
        return true;
      }
    } on DioException catch (dioErr) {
      debugPrint(
        'DIGITAX_STOCK_ADJUST_DIO_ERROR: [HTTP ${dioErr.response?.statusCode}] ${dioErr.response?.data ?? dioErr.message}',
      );
    } catch (e) {
      debugPrint('DIGITAX_STOCK_ADJUST_EX: $e');
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
    List<SaleItem> items, {
    bool forcePush = false,
  }) async {
    if (transaction.isCreditNote) {
      return await submitCreditNoteToDigitax(
        transaction,
        items: items,
        originalSdcInvoiceNo: transaction.orgInvoiceNo ?? '',
        reason: transaction.creditNoteReason ?? 'Product Exchange / Return',
      );
    }

    // If this sale was ALREADY recorded in DigiTax (has a sale_01... ID) and is
    // currently PENDING ZRA sync, poll GET /sales/{sale_id} instead of re-POSTing
    // a duplicate trader_invoice_number (which DigiTax would reject with HTTP 400).
    if (!forcePush &&
        transaction.zraMarkId != null &&
        transaction.zraMarkId!.trim().startsWith('sale_') &&
        !transaction.zraStatus.toUpperCase().startsWith('FAILED')) {
      return await refreshTransactionFiscalData(transaction);
    }

    final db = ref.read(databaseServiceProvider);
    final config = ref.read(storeConfigProvider).value;

    Future<void> persistFiscalStatus(String status) async {
      transaction.zraStatus = status;
      await db.isar.writeTxn(() async {
        await db.isar.saleTransactions.put(transaction);
      });
    }

    final currentUser = ref.read(authProvider);
    final resolvedBhfId =
        (currentUser?.branchCode != null &&
            currentUser!.branchCode!.trim().isNotEmpty)
        ? currentUser.branchCode!.trim().padLeft(2, '0')
        : (config?.bhfId.trim().isNotEmpty == true
              ? config!.bhfId.trim().padLeft(2, '0')
              : '00');

    final apiKey = await resolveBranchApiKey(resolvedBhfId);
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint(
        'DIGITAX_SALES: Cannot fiscalize - API Key is missing for branch $resolvedBhfId.',
      );
      return false;
    }

    // Per DigiTax ZM MCP spec: trader_invoice_number must be unique across all
    // sales, credit notes, and debit notes, including failed transactions.
    final isRetrySale =
        forcePush ||
        transaction.zraStatus.toUpperCase().startsWith('FAILED') ||
        transaction.zraStatus.toUpperCase() == 'RECONCILIATION_REQUIRED';
    final invoiceNo =
        (!isRetrySale && transaction.transactionId?.isNotEmpty == true)
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

    // Step A: Ensure every fiscal item in the sale exists on DigiTax and has a DigiTax item ID
    final List<Map<String, dynamic>> digitaxItemsPayload = [];

    for (final item in items) {
      var localProd = await db.isar.products.get(item.productId);
      if (localProd == null && item.productSkuAtSale != null && item.productSkuAtSale!.trim().isNotEmpty) {
        localProd = await db.getProductBySku(item.productSkuAtSale!.trim());
      }
      if (localProd == null) {
        final allP = await db.getAllProducts();
        final lowerItemName = item.productName.trim().toLowerCase();
        localProd = allP.where((p) => p.name.trim().toLowerCase() == lowerItemName).firstOrNull;
      }

      // PERMANENT GUARD: Check if the product or sale item is offline/private exempt.
      // 1. If the underlying product in the database has isDigitaxSyncEnabled == false, it is
      //    PERMANENTLY an offline product. It must NEVER be sent to DigiTax, even if forcePush is requested!
      // 2. If the product was never synced with DigiTax and has no usable DigiTax item ID, it is an offline product!
      // 3. If the item was marked isDigitaxExempt at sale time and not explicitly force-pushed, it is also skipped.
      final isOfflineProduct = (localProd != null && !localProd.isDigitaxSyncEnabled) ||
          (localProd != null && !localProd.isSyncedWithDigitax && !localProd.hasUsableDigitaxItemId);
      if (isOfflineProduct || (!forcePush && item.isDigitaxExempt)) {
        debugPrint(
          'DIGITAX_EXEMPT_ITEM: ${item.productName} is an offline/private product. Permanently skipping from DigiTax payload.',
        );
        continue;
      }

      String? digitaxItemId;

      // Check if the product already has a remote DigiTax item ID
      if (localProd != null && localProd.hasUsableDigitaxItemId) {
        digitaxItemId = localProd.itemClsCd;
      }

      // If not stored, query DigiTax items catalog first to find existing ID across multiple attributes
      if (digitaxItemId == null || digitaxItemId.isEmpty) {
        try {
          final remoteItems = await _fetchAllRemoteItems(headers);
          final normName = item.productName.trim().toLowerCase();
          final localSku = localProd?.sku.trim().toLowerCase() ?? '';
          final localCls = localProd?.itemClsCd.trim().toLowerCase() ?? '';
          final hasSpecificClass =
              localCls.isNotEmpty &&
              !localCls.startsWith('item_') &&
              localCls != '10101501' &&
              localCls != '56101530';
          final codeMatches = <Map<String, dynamic>>[];
          final nameMatches = <Map<String, dynamic>>[];
          final classMatches = <Map<String, dynamic>>[];

          for (final rem in remoteItems) {
            final rId = (rem['id'] ?? rem['item_id'] ?? '').toString().trim();
            final rName = (rem['item_name'] ?? rem['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rCode = (rem['item_code'] ?? rem['code'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rBarcode = (rem['bar_code'] ?? rem['barcode'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rClass =
                (rem['item_class_code'] ??
                        rem['itemClsCd'] ??
                        rem['item_cls_cd'] ??
                        '')
                    .toString()
                    .trim()
                    .toLowerCase();
            final isCodeMatch =
                localSku.isNotEmpty &&
                (rCode == localSku || rBarcode == localSku);
            final isNameMatch =
                rName.isNotEmpty &&
                (rName == normName ||
                    rName.replaceAll(RegExp(r'\s+'), '') ==
                        normName.replaceAll(RegExp(r'\s+'), ''));
            if (isCodeMatch) codeMatches.add(rem);
            if (isNameMatch) nameMatches.add(rem);
            if (hasSpecificClass && rClass == localCls) {
              classMatches.add(rem);
            }
            if (rId.isEmpty && (isCodeMatch || isNameMatch)) {
              debugPrint(
                'DIGITAX_SALES_ABORT: A matching remote product has no stable DigiTax ID.',
              );
              return false;
            }
          }

          // Resolve matching remote product:
          // 1. Exact Barcode / SKU match is definitive — never discard an exact barcode match
          if (codeMatches.length == 1) {
            digitaxItemId = (codeMatches.single['id'] ?? codeMatches.single['item_id'] ?? '').toString().trim();
          } else if (codeMatches.length > 1) {
            // Disambiguate by name or classification if multiple barcode matches exist
            final bothMatch = codeMatches.where((c) => nameMatches.contains(c)).toList();
            final best = bothMatch.isNotEmpty ? bothMatch.first : codeMatches.first;
            digitaxItemId = (best['id'] ?? best['item_id'] ?? '').toString().trim();
          } else if (nameMatches.length == 1) {
            // 2. Unique exact name match
            digitaxItemId = (nameMatches.single['id'] ?? nameMatches.single['item_id'] ?? '').toString().trim();
          } else if (nameMatches.length > 1) {
            // Disambiguate by classification if multiple identical names exist
            final classAndName = classMatches.where((c) => nameMatches.contains(c)).toList();
            final best = classAndName.isNotEmpty ? classAndName.first : nameMatches.first;
            digitaxItemId = (best['id'] ?? best['item_id'] ?? '').toString().trim();
          }

          if (digitaxItemId != null && digitaxItemId.isNotEmpty) {
            final prodToSave = localProd;
            if (prodToSave != null) {
              prodToSave.itemClsCd = digitaxItemId;
              final matchedMap = remoteItems.firstWhere(
                (r) =>
                    (r['id'] ?? r['item_id'] ?? '').toString().trim() ==
                    digitaxItemId,
                orElse: () => <String, dynamic>{'id': digitaxItemId},
              );
              _applyRemoteItemStatusToProduct(prodToSave, matchedMap);
              await db.isar.writeTxn(() async {
                await db.isar.products.put(prodToSave);
              });
              // Append to local memory cache so subsequent items/lookups hit memory
              if (_remoteItemsCache != null) {
                _remoteItemsCache!.add({
                  'id': digitaxItemId,
                  'item_id': digitaxItemId,
                  'item_name': item.productName.trim(),
                  'bar_code': (prodToSave.sku.trim().isNotEmpty)
                      ? prodToSave.sku.trim()
                      : "SKU-${item.productId}",
                  'status': prodToSave.digitaxSyncStatus,
                });
              }
              debugPrint(
                'DIGITAX_SALES: Linked "${item.productName}" to existing DigiTax item ID "$digitaxItemId" [Status: ${prodToSave.digitaxSyncStatus}].',
              );
            }
          }
        } catch (e) {
          debugPrint('DIGITAX_SALES: Remote item lookup notice: $e');
          return false;
        }
      }

      // If the item does not exist in the DigiTax catalog, it is an offline/unregistered item!
      // NEVER auto-register products onto DigiTax during sales/checkout!
      // Offline products must stay offline and be skipped from the fiscal payload.
      if (digitaxItemId == null || digitaxItemId.isEmpty) {
        debugPrint(
          'DIGITAX_SALES: "${item.productName}" is not registered on DigiTax (offline product). Skipping from fiscal invoice payload.',
        );
        continue;
      }

      // Live pre-sale verification: if the product was marked PENDING/FAILED or has a price mismatch,
      // query DigiTax live and push any updated unit price before submitting the sale!
      if (localProd != null) {
        if (localProd.digitaxSyncStatus == 'PENDING' ||
            localProd.digitaxSyncStatus == 'FAILED' ||
            localProd.hasDigitaxPriceMismatch) {
          try {
            final itemCheckResp = await _dio.get(
              '$digitaxZambiaApiBaseUrl/items/$digitaxItemId',
              options: Options(
                headers: headers,
                validateStatus: (s) => s != null && s < 500,
              ),
            );
            if (itemCheckResp.statusCode == 200 &&
                itemCheckResp.data is Map) {
              final remoteMap = _extractRemoteItemMap(itemCheckResp.data);
              _applyRemoteItemStatusToProduct(localProd, remoteMap);
              await db.isar.writeTxn(() async {
                await db.isar.products.put(localProd!);
              });
            }
          } catch (_) {}
        }

        if (localProd.digitaxSyncStatus == 'PENDING' ||
            localProd.digitaxSyncStatus == 'FAILED') {
          debugPrint(
            'DIGITAX_SALES_HOLD: Item "${localProd.name}" ($digitaxItemId) has DigiTax status ${localProd.digitaxSyncStatus}. Holding fiscal submission until COMPLETED.',
          );
          await persistFiscalStatus(
            'HOLD_ITEM_${localProd.digitaxSyncStatus}: ${localProd.name} (${localProd.digitaxSyncError ?? "Not yet approved by ZRA"})',
          );
          return false;
        }

        final remotePrice = localProd.digitaxRemotePrice;
        if (item.priceAtSale > 0 &&
            ((remotePrice != null &&
                    (item.priceAtSale - remotePrice).abs() > 0.01) ||
                localProd.hasDigitaxPriceMismatch)) {
          try {
            final putResp = await _dio.put(
              '$digitaxZambiaApiBaseUrl/items/$digitaxItemId',
              data: {
                "item_name": localProd.name.trim(),
                "default_unit_price": item.priceAtSale,
                "recommended_retail_price": item.priceAtSale,
              },
              options: Options(
                headers: headers,
                validateStatus: (s) => s != null && s < 500,
              ),
            );
            if (putResp.statusCode == 200 || putResp.statusCode == 201) {
              localProd.digitaxRemotePrice = item.priceAtSale;
              await db.isar.writeTxn(() async {
                await db.isar.products.put(localProd!);
              });
            }
          } catch (e) {
            debugPrint('DIGITAX_SALES_PRICE_SYNC_NOTE: $e');
          }
        }
      }

      final effectiveQty = (item.isWeighted && item.weight > 0)
          ? item.weight
          : item.quantity.toDouble();
      final vatCategoryCode = resolveCompliantVatCategoryCode(
        zraTaxCode: localProd?.zraTaxCode,
        taxRate: item.taxRateAtSale,
        isTotBusiness: isTot,
      );

      digitaxItemsPayload.add({
        "item_id": digitaxItemId,
        "item_name": item.productName,
        "item_code": "SKU-${item.productId}",
        "quantity": effectiveQty,
        "unit_price": double.parse(item.priceAtSale.toStringAsFixed(4)),
        "package_unit_quantity": 1,
        "discount_rate": 0.0000,
        "discount_amount": 0.0000,
        "total_amount": double.parse(
          (effectiveQty * item.priceAtSale).toStringAsFixed(4),
        ),
        "vat_category_code": vatCategoryCode,
        if (isTot) "tot_category_code": "TOT",
      });
    }

    // If sale only contains offline/private products, bypass DigiTax cloud submission completely
    if (digitaxItemsPayload.isEmpty) {
      debugPrint(
        'DIGITAX_SALES_BYPASS: All items in sale #$invoiceNo are offline/private products. Skipping cloud fiscalization.',
      );
      transaction.zraSdcId = null;
      transaction.zraReceiptNumber = null;
      transaction.zraMarkId = null;
      transaction.zraInternalData = null;
      transaction.zraQrCode = null;
      transaction.zraInvoiceType = 'Internal / Non-Fiscal';
      transaction.zraStatus = 'LOCAL_EXEMPT';
      await db.isar.writeTxn(() async {
        await db.isar.saleTransactions.put(transaction);
      });
      return true;
    }

    // Step B: Submit the sale to DigiTax (POST /sales)
    String paymentCode = '01'; // 01 CASH
    final pMethod = transaction.paymentMethod.toUpperCase();
    if (pMethod.contains('CARD')) {
      paymentCode = '05';
    } else if (pMethod.contains('MOBILE') ||
        pMethod.contains('MOMO') ||
        pMethod.contains('AIRTEL') ||
        pMethod.contains('MTN')) {
      paymentCode = '06';
    }

    final customerTpin = transaction.customerTpin?.trim();
    final customerName =
        (transaction.customerBusinessName != null &&
            transaction.customerBusinessName!.isNotEmpty)
        ? transaction.customerBusinessName!.trim()
        : 'General Customer';

    final salePayload = {
      "kind": "NORMAL",
      "sale_date": saleDate,
      "currency_code": "ZMW",
      "payment_type_code": paymentCode,
      "trader_invoice_number": invoiceNo,
      "customer_name": customerName,
      if (customerTpin != null && customerTpin.isNotEmpty)
        "customer_tpin": customerTpin,
      if (transaction.customerAddress != null &&
          transaction.customerAddress!.isNotEmpty)
        "customer_address": transaction.customerAddress,
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
        debugPrint(
          'DIGITAX_SALES_QUEUED: Initial response from DigiTax: $data',
        );

        if (data is! Map) {
          await persistFiscalStatus('RECONCILIATION_REQUIRED');
          return false;
        }

        Map<String, dynamic> saleData = Map<String, dynamic>.from(data);
        if (saleData['sale'] is Map) {
          saleData = Map<String, dynamic>.from(saleData['sale']);
        } else if (saleData['data'] is Map) {
          saleData = Map<String, dynamic>.from(saleData['data']);
        }
        final saleId = saleData['id']?.toString();

        // Helper function to extract ZRA signature across top-level and nested maps
        String? extractSig(Map<String, dynamic> m) {
          final s =
              m['receipt_signature'] ??
              m['signature'] ??
              m['vsdc_signature'] ??
              m['receipt_sign'] ??
              m['vsdc_sign'] ??
              m['rcpt_sign'];
          if (s != null &&
              s.toString().trim().isNotEmpty &&
              s.toString() != 'null') {
            return s.toString().trim();
          }
          if (m['sale'] is Map) {
            final inner = extractSig(Map<String, dynamic>.from(m['sale']));
            if (inner != null) return inner;
          }
          if (m['data'] is Map) {
            final inner = extractSig(Map<String, dynamic>.from(m['data']));
            if (inner != null) return inner;
          }
          return null;
        }

        String? liveSignature = extractSig(saleData);

        // If not immediately signed (DigiTax async ZRA VSDC sync), poll with progressive fast-intervals
        // Typical completion is 500ms–4s; polling up to 18 attempts (~10s) ensures the paper receipt
        // prints WITH the official ZRA QR code rather than printing too early while still PENDING.
        if (liveSignature == null || liveSignature.isEmpty) {
          for (int attempt = 1; attempt <= 18; attempt++) {
            final pollDelayMs = attempt <= 2 ? 300 : (attempt <= 5 ? 500 : 750);
            await Future.delayed(Duration(milliseconds: pollDelayMs));
            try {
              // Always prefer GET /sales/{id} when we have the DigiTax sale ID
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
                  final list =
                      pData['sales'] ??
                      pData['data'] ??
                      pData['items'] ??
                      pData['results'];
                  if (list is List && list.isNotEmpty) pData = list.first;
                  if (pData is Map) {
                    final mapData = Map<String, dynamic>.from(pData);
                    final pollStatus = mapData['status']
                        ?.toString()
                        .toUpperCase();
                    final sig = extractSig(mapData);
                    // Update saleData from the nested object if present
                    if (mapData['sale'] is Map) {
                      saleData = Map<String, dynamic>.from(mapData['sale']);
                    } else if (mapData['data'] is Map) {
                      saleData = Map<String, dynamic>.from(mapData['data']);
                    } else {
                      saleData = mapData;
                    }
                    if (sig != null && sig.isNotEmpty) {
                      liveSignature = sig;
                      debugPrint(
                        'DIGITAX_POLL_SUCCESS: Sale #$invoiceNo signed after $attempt attempt(s) (status=$pollStatus)',
                      );
                      break;
                    }
                    if (pollStatus == 'FAILED') {
                      debugPrint(
                        'DIGITAX_POLL_FAILED: Sale #$invoiceNo was marked FAILED by ZRA VSDC',
                      );
                      break;
                    }
                    // If status is COMPLETED but signature still missing, keep polling
                    debugPrint(
                      'DIGITAX_POLL_WAIT: Attempt $attempt — status=$pollStatus, sig=$sig',
                    );
                  }
                }
              }
            } catch (e) {
              debugPrint(
                'DIGITAX_POLL_NOTICE: Attempt $attempt for $invoiceNo: $e',
              );
            }
          }
        }

        final saleStatusUpper = saleData['status']?.toString().toUpperCase();
        if (saleStatusUpper == 'FAILED') {
          debugPrint(
            'DIGITAX_SALE_FAILED: Sale #$invoiceNo (id=$saleId) was rejected by ZRA VSDC',
          );
          transaction.zraStatus = 'FAILED';
          if (saleId != null && saleId.isNotEmpty) {
            transaction.zraMarkId = saleId;
          }
          await db.isar.writeTxn(() async {
            await db.isar.saleTransactions.put(transaction);
          });
          return false;
        }

        // IMPORTANT: Do NOT fall back to the DigiTax sale ID as the signature!
        // If polling exhausted without a ZRA signature, set PENDING so the
        // cashier can refresh from transaction history once ZRA completes.
        // The refreshTransactionFiscalData() method will fill it in later.
        liveSignature ??= 'PENDING';

        // Virtual SDC Device ID (from DigiTax registration)
        // DigiTax returns sdc_id = "" (empty) — derive from TPIN+branch when missing
        final rawSdc =
            saleData['sdc_id'] ??
            saleData['sdcId'] ??
            saleData['serial_number'];
        String sdcId =
            (rawSdc != null &&
                rawSdc.toString().trim().isNotEmpty &&
                rawSdc.toString() != 'null')
            ? rawSdc.toString().trim()
            : (config?.sdcId?.isNotEmpty == true
                  ? config!.sdcId!
                  : ((config?.tpin?.isNotEmpty == true)
                        ? '${config!.tpin!}001'
                        : ''));

        // SDC Invoice Number (ZRA Smart Invoice format: INV{SDC_ID}/{number})
        // Never use sale_number here because sale_number is assigned while still PENDING in DigiTax
        final rawRcpt =
            saleData['receipt_number'] ??
            saleData['invoice_number'] ??
            saleData['sdc_invoice_number'];
        String sdcRcptNo = 'PENDING';
        if (rawRcpt != null &&
            rawRcpt.toString().trim().isNotEmpty &&
            rawRcpt.toString() != 'null') {
          final rcptStr = rawRcpt.toString().trim();
          if (rcptStr.toUpperCase().startsWith('INV0') ||
              rcptStr.toUpperCase().startsWith('INV1/') ||
              rcptStr.toUpperCase().startsWith('INV/') ||
              rcptStr.toUpperCase().startsWith('CN')) {
            sdcRcptNo = rcptStr;
          } else {
            final cleanNum = rcptStr
                .replaceFirst(RegExp(r'^(INV|CN)-0*'), '')
                .replaceFirst(RegExp(r'^(INV|CN)-'), '');
            final sdcClean = sdcId.replaceAll(
              RegExp(r'^SDC', caseSensitive: false),
              '',
            );
            sdcRcptNo = sdcClean.isNotEmpty
                ? 'INV$sdcClean/$cleanNum'
                : 'INV1/$cleanNum';
          }
        }
        if (sdcId.isEmpty) {
          final match = RegExp(
            r'INV(\d+)/',
            caseSensitive: false,
          ).firstMatch(sdcRcptNo);
          if (match != null &&
              match.group(1) != null &&
              match.group(1) != '1') {
            sdcId = 'SDC${match.group(1)}';
          }
        }

        if (sdcRcptNo == 'PENDING' ||
            liveSignature.isEmpty ||
            liveSignature == 'PENDING') {
          transaction.zraSdcId = sdcId.isEmpty ? null : sdcId;
          transaction.zraReceiptNumber = 'PENDING';
          if (saleId != null && saleId.isNotEmpty) {
            transaction.zraMarkId = saleId;
          }
          await persistFiscalStatus('PENDING');
          debugPrint(
            'DIGITAX_SALES_PENDING_ZRA: Recorded in DigiTax (id=$saleId) · still syncing with ZRA for transaction ${transaction.transactionId}.',
          );
          return false;
        }

        // ZRA VSDC Internal Data
        final rawInternalData = saleData['internal_data']?.toString();
        final internalData =
            (rawInternalData != null &&
                rawInternalData.trim().isNotEmpty &&
                rawInternalData != 'null')
            ? rawInternalData.trim()
            : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');

        // ZRA Verification QR URL: prioritize official receipt_url returned by DigiTax,
        // and always guarantee a valid verification URL when approved so QR code always prints.
        final fallbackSdcForQr = sdcId.isNotEmpty
            ? sdcId
            : ((config?.tpin?.isNotEmpty == true)
                  ? '${config!.tpin!}001'
                  : 'SDC1');
        final qrData =
            (saleData['receipt_url']?.toString().trim().isNotEmpty == true &&
                saleData['receipt_url'].toString().trim() != 'null')
            ? saleData['receipt_url'].toString().trim()
            : ((saleData['qr_code']?.toString().trim().isNotEmpty == true &&
                      saleData['qr_code'].toString().trim() != 'null')
                  ? saleData['qr_code'].toString().trim()
                  : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$fallbackSdcForQr&rcpt=$sdcRcptNo');

        // Invoice type
        final invoiceType = switch (saleData['receipt_type_code']?.toString()) {
          'S' => 'Normal Sale',
          'R' => 'Credit Note',
          'C' => 'Copy',
          _ =>
            saleData['kind'] != null
                ? saleData['kind'].toString().replaceAll('_', ' ').toUpperCase()
                : 'Normal Sale',
        };

        _logFiscalSummaryMismatch(transaction, saleData['sales_tax_summary']);

        transaction.zraSdcId = sdcId;
        transaction.zraReceiptNumber = sdcRcptNo;
        transaction.zraMarkId = liveSignature;
        transaction.zraInternalData = internalData;
        transaction.zraQrCode = qrData;
        transaction.zraInvoiceType = invoiceType;
        final expectedFiscalTotal = digitaxItemsPayload.fold<double>(
          0.0,
          (sum, itm) =>
              sum + ((itm['total_amount'] as num?)?.toDouble() ?? 0.0),
        );
        final fiscalTotal = _fiscalResponseTotal(saleData);
        final targetTotal =
            expectedFiscalTotal > 0 ? expectedFiscalTotal : transaction.totalAmount;
        if (fiscalTotal != null &&
            (fiscalTotal - targetTotal).abs() > 0.01) {
          transaction.zraStatus = 'RECONCILIATION_REQUIRED';
          await db.isar.writeTxn(() async {
            await db.isar.saleTransactions.put(transaction);
          });
          debugPrint(
            'DIGITAX_SALES_TOTAL_MISMATCH: DigiTax receipt $sdcRcptNo totals ${fiscalTotal.toStringAsFixed(2)}, but target total is ${targetTotal.toStringAsFixed(2)} (local tx total: ${transaction.totalAmount.toStringAsFixed(2)}). Receipt metadata was preserved and the sale requires reconciliation.',
          );
          return false;
        }
        transaction.zraStatus = 'APPROVED';

        await db.isar.writeTxn(() async {
          await db.isar.saleTransactions.put(transaction);
        });

        // Cache the DigiTax virtual SDC ID back to StoreConfig
        if (sdcId.isNotEmpty && config != null && config.sdcId != sdcId) {
          config.sdcId = sdcId;
          try {
            await db.saveStoreConfig(config);
          } catch (_) {}
          debugPrint(
            'DIGITAX_SDC_CACHED: Virtual SDC ID "$sdcId" cached to StoreConfig',
          );
        }

        debugPrint(
          'DIGITAX_FISCALIZED_LIVE: SDC ID: $sdcId | SDC Inv No: $sdcRcptNo | Signature: ${transaction.zraMarkId} | Internal: $internalData | QR: $qrData',
        );
        return true;
      }
    } on DioException catch (dioErr) {
      debugPrint(
        'DIGITAX_SALES_ERROR: [HTTP ${dioErr.response?.statusCode}] ${dioErr.response?.data ?? dioErr.message}',
      );
      if (dioErr.response?.statusCode == 409 ||
          dioErr.response?.data?.toString().contains(
                'trader_invoice_number has already been used',
              ) ==
              true) {
        debugPrint(
          'DIGITAX_SALES_409_CONFLICT: Invoice ${transaction.transactionId} already exists in DigiTax. Auto-recovering fiscal metadata...',
        );
        final recovered = await refreshTransactionFiscalData(
          transaction,
          useShortTimeout: true,
        );
        if (recovered) {
          debugPrint(
            'DIGITAX_SALES_409_RESOLVED: Successfully synced existing ZRA receipt for ${transaction.transactionId}!',
          );
          return true;
        }
        await persistFiscalStatus('RECONCILIATION_REQUIRED');
        debugPrint(
          'DIGITAX_SALES_RECONCILIATION_REQUIRED: transaction ${transaction.transactionId} conflicts with an existing trader invoice number; refusing to resubmit automatically.',
        );
        return false;
      }
      final responseStatus = dioErr.response?.statusCode;
      // Connection / send / receive timeouts mean the request never reached
      // DigiTax (or DigiTax is busy). Keep status as PENDING so the 45 s queue
      // worker will retry once the network recovers.
      if (dioErr.type == DioExceptionType.connectionTimeout ||
          dioErr.type == DioExceptionType.sendTimeout ||
          dioErr.type == DioExceptionType.receiveTimeout ||
          dioErr.type == DioExceptionType.connectionError) {
        await persistFiscalStatus('PENDING');
        debugPrint(
          'DIGITAX_SALES_TIMEOUT: Transaction ${transaction.transactionId} kept as PENDING – will retry when DigiTax is reachable.',
        );
        return false;
      }
      await persistFiscalStatus(
        responseStatus == null || responseStatus >= 500
            ? 'RECONCILIATION_REQUIRED'
            : 'FAILED',
      );
    } catch (e) {
      await persistFiscalStatus('RECONCILIATION_REQUIRED');
      debugPrint('DIGITAX_SALES_RECONCILIATION_REQUIRED: $e');
    }
    return false;
  }

  /// Submits an official ZRA Fiscal Credit Note (Refund / Return) to DigiTax
  /// Per DigiTax ZM API spec: POST /credit-notes with sale_id, return_date, refund_reason_code, trader_invoice_number, items
  Future<bool> submitCreditNoteToDigitax(
    SaleTransaction refundTx, {
    List<SaleItem>? items,
    required String originalSdcInvoiceNo,
    required String reason,
    SaleTransaction? originalSale,
  }) async {
    final db = ref.read(databaseServiceProvider);
    final config = ref.read(storeConfigProvider).value;

    // If this Credit Note is ALREADY recorded in DigiTax (has a sale_01... ID)
    // and is in PENDING state (syncing with ZRA), do NOT POST /credit-notes again
    // (which would fail with duplicate trader_invoice_number). Poll GET /sales/{id} instead.
    if (refundTx.zraMarkId != null &&
        refundTx.zraMarkId!.trim().startsWith('sale_') &&
        !refundTx.zraStatus.toUpperCase().startsWith('FAILED')) {
      return await refreshTransactionFiscalData(refundTx);
    }

    // Even if zraMarkId was not saved yet (or if a previous duplicate POST marked it FAILED),
    // check GET /credit-notes first to see if DigiTax already recorded this Credit Note.
    if (refundTx.transactionId != null &&
        refundTx.transactionId!.trim().isNotEmpty) {
      final alreadyCompleted = await refreshTransactionFiscalData(
        refundTx,
        useShortTimeout: true,
      );
      if (alreadyCompleted) {
        return true;
      }
      if (refundTx.zraMarkId != null &&
          refundTx.zraMarkId!.trim().startsWith('sale_') &&
          refundTx.zraStatus.toUpperCase() == 'PENDING') {
        return false;
      }
    }

    Future<void> persistCreditNoteStatus(String status) async {
      refundTx
        ..isCreditNote = true
        ..orgInvoiceNo = originalSdcInvoiceNo
        ..creditNoteReason = reason
        ..zraStatus = status;
      await db.isar.writeTxn(() async {
        await db.isar.saleTransactions.put(refundTx);
      });
    }

    final currentUser = ref.read(authProvider);
    final resolvedBhfId =
        (currentUser?.branchCode != null &&
            currentUser!.branchCode!.trim().isNotEmpty)
        ? currentUser.branchCode!.trim().padLeft(2, '0')
        : (config?.bhfId.trim().isNotEmpty == true
              ? config!.bhfId.trim().padLeft(2, '0')
              : '00');

    final apiKey =
        await resolveBranchApiKey(resolvedBhfId) ??
        config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('DIGITAX_CREDIT_NOTE: No API Key configured – skipped');
      return false;
    }

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    final effectiveItems = <SaleItem>[];
    if (items != null && items.isNotEmpty) {
      effectiveItems.addAll(items);
    } else {
      try {
        await refundTx.items.load();
        effectiveItems.addAll(refundTx.items);
      } catch (_) {}
    }

    if (effectiveItems.isEmpty) {
      debugPrint(
        'DIGITAX_CREDIT_NOTE_ERROR: No items provided for credit note.',
      );
      return false;
    }
    effectiveItems.removeWhere((item) => item.isDigitaxExempt);
    if (effectiveItems.isEmpty) {
      await persistCreditNoteStatus('OFFLINE_EXEMPT');
      return true;
    }

    // trader_invoice_number must be unique across sales, credit notes, and debit notes (including failed attempts)
    final isRetryAttempt =
        refundTx.zraStatus.toUpperCase().startsWith('FAILED') ||
        refundTx.zraStatus.toUpperCase() == 'RECONCILIATION_REQUIRED';
    final traderInvNo =
        (!isRetryAttempt &&
            refundTx.transactionId != null &&
            refundTx.transactionId!.trim().isNotEmpty)
        ? refundTx.transactionId!.trim()
        : ((refundTx.id > 0)
              ? 'CN-${refundTx.id}-${DateTime.now().millisecondsSinceEpoch % 100000}'
              : 'CN-${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}');
    refundTx.transactionId = traderInvNo;

    final origTraderInvNo = refundTx.orgInvoiceNo?.isNotEmpty == true
        ? refundTx.orgInvoiceNo!
        : originalSdcInvoiceNo;

    // Use UTC date so DigiTax never rejects return_date as a "future date" due to timezone offset
    final saleDateYmd = DateTime.now()
        .toUtc()
        .toIso8601String()
        .substring(0, 10);

    // Map reason text to official DigiTax Zambia refund_reason_code
    // 01: WRONG PRODUCT, 02: WRONG PRICE, 03: DAMAGED GOODS, 04: WRONG CUSTOMER INVOICED, 05: DUPLICATED INVOICE, 06: EXCESS SUPPLIES, 07: Other
    String refundReasonCode = '07'; // Default: Other / Return
    final rLower = reason.toLowerCase();
    if (rLower.contains('wrong product') ||
        rLower.contains('wrong item') ||
        rLower.contains('wrong size') ||
        rLower.contains('model')) {
      refundReasonCode = '01';
    } else if (rLower.contains('price') || rLower.contains('overcharge')) {
      refundReasonCode = '02';
    } else if (rLower.contains('damage') ||
        rLower.contains('defect') ||
        rLower.contains('fault') ||
        rLower.contains('broken') ||
        rLower.contains('expire')) {
      refundReasonCode = '03';
    } else if (rLower.contains('wrong customer')) {
      refundReasonCode = '04';
    } else if (rLower.contains('duplicate')) {
      refundReasonCode = '05';
    } else if (rLower.contains('excess')) {
      refundReasonCode = '06';
    } else {
      refundReasonCode = '07'; // Other
    }

    // Strategy 1: Official DigiTax Zambia POST /credit-notes endpoint
    // Requires resolving original sale_id on DigiTax and item_id for each returned item
    try {
      // 1a. Resolve local originalSale if not explicitly passed
      SaleTransaction? resolvedOrigSale = originalSale;
      if (resolvedOrigSale == null) {
        final allLocalSales = await db.isar.saleTransactions
            .filter()
            .isCreditNoteEqualTo(false)
            .findAll();
        for (final s in allLocalSales) {
          if (s.zraReceiptNumber == origTraderInvNo ||
              s.transactionId == origTraderInvNo ||
              'INV-${s.id}' == origTraderInvNo ||
              'INV-#${s.id.toString().padLeft(6, '0')}' == origTraderInvNo) {
            resolvedOrigSale = s;
            break;
          }
        }
      }

      // Extract candidate identifiers to match the original sale on DigiTax
      final candidateIds = <String>{
        if (origTraderInvNo.trim().isNotEmpty) origTraderInvNo.trim(),
        if (originalSdcInvoiceNo.trim().isNotEmpty) originalSdcInvoiceNo.trim(),
        if (resolvedOrigSale?.transactionId?.trim().isNotEmpty == true)
          resolvedOrigSale!.transactionId!.trim(),
        if (resolvedOrigSale?.zraReceiptNumber?.trim().isNotEmpty == true)
          resolvedOrigSale!.zraReceiptNumber!.trim(),
        if (resolvedOrigSale != null) 'INV-${resolvedOrigSale.id}',
      };
      final origSignature =
          (resolvedOrigSale?.zraMarkId != null &&
              resolvedOrigSale!.zraMarkId!.trim().isNotEmpty &&
              resolvedOrigSale.zraMarkId != 'PENDING')
          ? resolvedOrigSale.zraMarkId!.trim()
          : null;

      // Extract numeric receipt_number (e.g. "INV001/38" -> "38", "INV1/38" -> "38")
      String? cleanNumericRcptNo;
      for (final cand in candidateIds) {
        final slashIdx = cand.lastIndexOf('/');
        if (slashIdx != -1 && slashIdx + 1 < cand.length) {
          final tail = cand.substring(slashIdx + 1).trim();
          if (int.tryParse(tail) != null) {
            cleanNumericRcptNo = int.parse(tail).toString();
            break;
          }
        }
      }

      // 1b. Resolve DigiTax item_id for each returned item using local + remote catalog lookup
      List<Map<String, dynamic>>? remoteCatalog;
      final resolvedItemIds = <int, String>{};
      for (final item in effectiveItems) {
        var product = await db.isar.products.get(item.productId);
        if (product == null &&
            item.productSkuAtSale != null &&
            item.productSkuAtSale!.trim().isNotEmpty) {
          product = await db.getProductBySku(item.productSkuAtSale!.trim());
        }
        String? digitaxItemId =
            (product?.itemClsCd.trim().startsWith('item_') == true)
            ? product!.itemClsCd.trim()
            : null;

        if (digitaxItemId == null) {
          remoteCatalog ??= await _fetchAllRemoteItems(headers);
          final localSku =
              (product?.sku.trim().isNotEmpty == true
                      ? product!.sku.trim()
                      : (item.productSkuAtSale?.trim() ?? ''))
                  .toLowerCase();
          final normName =
              (product?.name.trim().isNotEmpty == true
                      ? product!.name.trim()
                      : item.productName.trim())
                  .toLowerCase();

          for (final rem in remoteCatalog) {
            final rId = (rem['id'] ?? rem['item_id'] ?? '').toString().trim();
            if (!rId.startsWith('item_')) {
              continue;
            }
            final rCode = (rem['item_code'] ?? rem['code'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rBarcode = (rem['bar_code'] ?? rem['barcode'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            final rName = (rem['item_name'] ?? rem['name'] ?? '')
                .toString()
                .trim()
                .toLowerCase();
            if ((localSku.isNotEmpty &&
                    (rCode == localSku || rBarcode == localSku)) ||
                (normName.isNotEmpty && rName == normName)) {
              digitaxItemId = rId;
              break;
            }
          }
        }

        if (digitaxItemId != null && digitaxItemId.isNotEmpty) {
          resolvedItemIds[item.productId] = digitaxItemId;
        }
      }

      // 1c. Locate the exact original sale on DigiTax (paginating up to 5 pages of GET /sales)
      String? origSaleId;
      Map<String, dynamic>? matchedOrigSaleMap;

      if (origSignature != null && origSignature.startsWith('sale_')) {
        origSaleId = origSignature;
      }
      for (final cand in candidateIds) {
        if (cand.startsWith('sale_')) {
          origSaleId = cand;
          break;
        }
      }

      if (origSaleId != null) {
        try {
          final directResp = await _dio.get(
            '$digitaxZambiaApiBaseUrl/sales/$origSaleId',
            options: Options(
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (directResp.statusCode == 200 && directResp.data is Map) {
            matchedOrigSaleMap = Map<String, dynamic>.from(
              directResp.data as Map,
            );
          }
        } catch (_) {}
      }

      if (matchedOrigSaleMap == null) {
        String? afterCursor;
        Map<String, dynamic>? fallbackItemMatchSale;

        for (int page = 0; page < 5; page++) {
          final qp = <String, dynamic>{'page_size': 20};
          if (afterCursor != null && afterCursor.isNotEmpty) {
            qp['after'] = afterCursor;
          }
          final findSaleResp = await _dio.get(
            '$digitaxZambiaApiBaseUrl/sales',
            queryParameters: qp,
            options: Options(
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (findSaleResp.statusCode != 200 || findSaleResp.data is! Map) {
            break;
          }
          final sData = Map<String, dynamic>.from(findSaleResp.data as Map);
          final list =
              sData['data'] ??
              sData['sales'] ??
              sData['items'] ??
              sData['results'];
          if (list is! List || list.isEmpty) {
            break;
          }

          for (final rawSale in list) {
            if (rawSale is! Map) {
              continue;
            }
            final saleMap = Map<String, dynamic>.from(rawSale);
            final sId = saleMap['id']?.toString().trim() ?? '';
            final sTraderInv =
                saleMap['trader_invoice_number']?.toString().trim() ?? '';
            final sSaleNo = saleMap['sale_number']?.toString().trim() ?? '';
            final sRcptNo = saleMap['receipt_number']?.toString().trim() ?? '';
            final sSig = saleMap['receipt_signature']?.toString().trim() ?? '';

            final bool isExactMatch =
                candidateIds.contains(sId) ||
                (sTraderInv.isNotEmpty && candidateIds.contains(sTraderInv)) ||
                (sSaleNo.isNotEmpty && candidateIds.contains(sSaleNo)) ||
                (origSignature != null &&
                    sSig.isNotEmpty &&
                    sSig == origSignature) ||
                (cleanNumericRcptNo != null &&
                    sRcptNo.isNotEmpty &&
                    sRcptNo == cleanNumericRcptNo);

            if (isExactMatch) {
              matchedOrigSaleMap = saleMap;
              origSaleId = sId;
              break;
            }

            // Fallback candidate: if this sale contains all returned item_ids
            if (fallbackItemMatchSale == null &&
                resolvedItemIds.isNotEmpty &&
                saleMap['item_list'] is List) {
              final saleItemList = saleMap['item_list'] as List;
              final saleItemIds = saleItemList
                  .whereType<Map>()
                  .map((m) => m['item_id']?.toString().trim() ?? '')
                  .toSet();
              final allPresent = resolvedItemIds.values.every(
                (reqId) => saleItemIds.contains(reqId),
              );
              if (allPresent) {
                fallbackItemMatchSale = saleMap;
              }
            }
          }

          if (matchedOrigSaleMap != null) {
            break;
          }

          final pagination = sData['pagination'];
          final nextCursor = (pagination is Map)
              ? pagination['next']?.toString().trim()
              : null;
          if (nextCursor == null || nextCursor.isEmpty) {
            break;
          }
          afterCursor = nextCursor;
        }

        if (matchedOrigSaleMap == null && fallbackItemMatchSale != null) {
          matchedOrigSaleMap = fallbackItemMatchSale;
          origSaleId = fallbackItemMatchSale['id']?.toString().trim();
        }
      }

      // Extract original sale's item_list from DigiTax so we can match exact item_id & unit_price
      final origDigiTaxItems = <Map<String, dynamic>>[];
      if (matchedOrigSaleMap != null &&
          matchedOrigSaleMap['item_list'] is List) {
        for (final rawIt in (matchedOrigSaleMap['item_list'] as List)) {
          if (rawIt is Map) {
            origDigiTaxItems.add(Map<String, dynamic>.from(rawIt));
          }
        }
      }

      // Build items array for POST /credit-notes
      final creditNoteItemsList = <Map<String, dynamic>>[];
      bool allItemsHaveId = true;

      for (final item in effectiveItems) {
        final effectiveQty = (item.isWeighted && item.weight > 0)
            ? item.weight.ceil()
            : item.quantity;
        String? digitaxItemId = resolvedItemIds[item.productId];
        double unitPriceToUse = item.priceAtSale;

        // Cross-check with the original DigiTax sale's item_list
        if (origDigiTaxItems.isNotEmpty) {
          Map<String, dynamic>? matchedOrigLine;
          if (digitaxItemId != null) {
            for (final oLine in origDigiTaxItems) {
              if (oLine['item_id']?.toString().trim() == digitaxItemId) {
                matchedOrigLine = oLine;
                break;
              }
            }
          }
          if (matchedOrigLine == null && origDigiTaxItems.length == 1) {
            matchedOrigLine = origDigiTaxItems.first;
          }
          if (matchedOrigLine == null) {
            for (final oLine in origDigiTaxItems) {
              final oPrice = (oLine['unit_price'] as num?)?.toDouble();
              if (oPrice != null && (oPrice - item.priceAtSale).abs() < 0.05) {
                matchedOrigLine = oLine;
                break;
              }
            }
          }
          if (matchedOrigLine != null) {
            final oItemId = matchedOrigLine['item_id']?.toString().trim();
            if (oItemId != null && oItemId.startsWith('item_')) {
              digitaxItemId = oItemId;
            }
            final oUnitPrice = (matchedOrigLine['unit_price'] as num?)
                ?.toDouble();
            if (oUnitPrice != null && oUnitPrice > 0) {
              unitPriceToUse = oUnitPrice;
            }
          }
        }

        if (digitaxItemId != null && digitaxItemId.isNotEmpty) {
          final lineTotal = double.parse(
            (effectiveQty * unitPriceToUse).abs().toStringAsFixed(4),
          );
          creditNoteItemsList.add({
            'item_id': digitaxItemId,
            'quantity': effectiveQty,
            'unit_price': double.parse(unitPriceToUse.toStringAsFixed(4)),
            'total_amount': lineTotal,
            'package_unit_quantity': 1,
            'discount_rate': 0,
            'discount_amount': 0,
          });
        } else {
          allItemsHaveId = false;
        }
      }

      if (origSaleId != null &&
          origSaleId.isNotEmpty &&
          allItemsHaveId &&
          creditNoteItemsList.isNotEmpty) {
        final dedicatedPayload = {
          'sale_id': origSaleId,
          'return_date': saleDateYmd,
          'refund_reason_code': refundReasonCode,
          'trader_invoice_number': traderInvNo,
          'items': creditNoteItemsList,
        };

        debugPrint(
          'DIGITAX_DEDICATED_CREDIT_NOTE_POST → $digitaxZambiaApiBaseUrl/credit-notes',
        );
        debugPrint('DIGITAX_DEDICATED_PAYLOAD: $dedicatedPayload');

        final dedicatedResp = await _dio.post(
          '$digitaxZambiaApiBaseUrl/credit-notes',
          data: dedicatedPayload,
          options: Options(
            headers: headers,
            validateStatus: (s) => s != null && s < 600,
          ),
        );

        debugPrint(
          'DIGITAX_DEDICATED_CN_RESPONSE: [HTTP ${dedicatedResp.statusCode}] ${dedicatedResp.data}',
        );

        if (dedicatedResp.statusCode == 200 ||
            dedicatedResp.statusCode == 201) {
          Map<String, dynamic> saleData = {};
          if (dedicatedResp.data is Map) {
            saleData = Map<String, dynamic>.from(dedicatedResp.data as Map);
            if (saleData['sale'] is Map) {
              saleData = Map<String, dynamic>.from(saleData['sale'] as Map);
            } else if (saleData['data'] is Map) {
              saleData = Map<String, dynamic>.from(saleData['data'] as Map);
            }
          }

          final cnSaleId = saleData['id']?.toString().trim();

          // Immediately persist Stage 1 (PENDING — Recorded in DigiTax · still syncing with ZRA)
          // with the DigiTax sale_01... ID before polling, so any concurrent UI or queue
          // worker knows it is already recorded in DigiTax and never re-POSTs it.
          if (cnSaleId != null && cnSaleId.isNotEmpty) {
            refundTx
              ..isCreditNote = true
              ..orgInvoiceNo = origTraderInvNo
              ..creditNoteReason = reason
              ..zraReceiptNumber = 'PENDING'
              ..zraMarkId = cnSaleId
              ..zraInvoiceType = 'Credit Note (R)'
              ..zraStatus = 'PENDING';
            await db.isar.writeTxn(() async {
              await db.isar.saleTransactions.put(refundTx);
            });
          }

          String? extractCnSig(Map<String, dynamic> m) {
            final s =
                m['receipt_signature'] ??
                m['signature'] ??
                m['vsdc_signature'] ??
                m['vsdcMarkId'] ??
                m['zra_mark_id'];
            if (s != null &&
                s.toString().trim().isNotEmpty &&
                s.toString() != 'null') {
              return s.toString().trim();
            }
            if (m['sale'] is Map) {
              return extractCnSig(Map<String, dynamic>.from(m['sale'] as Map));
            }
            if (m['data'] is Map) {
              return extractCnSig(Map<String, dynamic>.from(m['data'] as Map));
            }
            return null;
          }

          String? liveSignature = extractCnSig(saleData);

          // Poll GET /sales/{cnSaleId} up to 16 attempts (~8s) so ZRA VSDC has time to
          // return receipt_signature and receipt_url BEFORE the Credit Note receipt prints.
          if ((liveSignature == null || liveSignature.isEmpty) &&
              cnSaleId != null &&
              cnSaleId.isNotEmpty) {
            for (int attempt = 1; attempt <= 16; attempt++) {
              final delayMs = attempt <= 2 ? 300 : 500;
              await Future.delayed(Duration(milliseconds: delayMs));
              try {
                final pollResp = await _dio.get(
                  '$digitaxZambiaApiBaseUrl/sales/$cnSaleId',
                  options: Options(
                    headers: headers,
                    validateStatus: (s) => s != null && s < 500,
                  ),
                );
                if (pollResp.statusCode == 200 && pollResp.data is Map) {
                  var pMap = Map<String, dynamic>.from(pollResp.data as Map);
                  if (pMap['sale'] is Map) {
                    pMap = Map<String, dynamic>.from(pMap['sale'] as Map);
                  } else if (pMap['data'] is Map) {
                    pMap = Map<String, dynamic>.from(pMap['data'] as Map);
                  }
                  saleData = pMap;
                  final sig = extractCnSig(pMap);
                  if (sig != null && sig.isNotEmpty) {
                    liveSignature = sig;
                    break;
                  }
                  final pollSt = pMap['status']?.toString().toUpperCase();
                  if (pollSt == 'FAILED') {
                    break;
                  }
                }
              } catch (_) {}
            }
          }

          final cnRemoteStatus =
              (saleData['status'] ?? '').toString().trim().toUpperCase();
          if (cnRemoteStatus == 'FAILED') {
            final failReason =
                (saleData['status_reason'] ??
                        saleData['error_message'] ??
                        saleData['message'] ??
                        'ZRA rejected the submission · needs attention.')
                    .toString()
                    .trim();
            refundTx
              ..isCreditNote = true
              ..orgInvoiceNo = origTraderInvNo
              ..creditNoteReason = reason
              ..zraReceiptNumber = null
              ..zraMarkId = cnSaleId
              ..zraQrCode = null
              ..zraInvoiceType = 'Credit Note (R)'
              ..zraStatus = 'FAILED: $failReason';
            await db.isar.writeTxn(() async {
              await db.isar.saleTransactions.put(refundTx);
            });
            debugPrint(
              'DIGITAX_CN_ZRA_FAILED: Credit Note $cnSaleId rejected by ZRA ($failReason)',
            );
            return false;
          }

          final sdcId =
              (saleData['sdc_id']?.toString().trim().isNotEmpty == true)
              ? saleData['sdc_id'].toString().trim()
              : (config?.sdcId ?? '');
          // Only use ZRA-assigned receipt_number (never sale_number, which is assigned while still pending)
          final rcptNumberRaw =
              saleData['receipt_number'] ??
              saleData['zra_receipt_number'] ??
              saleData['sdc_invoice_number'];
          final rawRcptStr =
              (rcptNumberRaw != null && rcptNumberRaw.toString() != 'null')
              ? rcptNumberRaw.toString().trim()
              : '';
          String sdcRcptNo = 'PENDING';
          if (rawRcptStr.isNotEmpty) {
            if (int.tryParse(rawRcptStr) != null && sdcId.isNotEmpty) {
              final cleanSdc = sdcId.replaceAll(
                RegExp(r'^SDC', caseSensitive: false),
                '',
              );
              sdcRcptNo = 'CN$cleanSdc/$rawRcptStr';
            } else if (int.tryParse(rawRcptStr) != null) {
              sdcRcptNo = 'CN1/$rawRcptStr';
            } else {
              sdcRcptNo = rawRcptStr;
            }
          }

          final isApproved =
              (liveSignature != null && liveSignature.isNotEmpty) ||
              (cnRemoteStatus == 'COMPLETED' && sdcRcptNo != 'PENDING');

          if (!isApproved) {
            // Stage 1: Pending — Recorded in DigiTax · still syncing with ZRA
            refundTx
              ..isCreditNote = true
              ..orgInvoiceNo = origTraderInvNo
              ..creditNoteReason = reason
              ..zraSdcId = sdcId.isNotEmpty ? sdcId : null
              ..zraReceiptNumber = 'PENDING'
              ..zraMarkId = cnSaleId ?? 'PENDING'
              ..zraQrCode = null
              ..zraInvoiceType = 'Credit Note (R)'
              ..zraStatus = 'PENDING';
            await db.isar.writeTxn(() async {
              await db.isar.saleTransactions.put(refundTx);
            });
            debugPrint(
              'DIGITAX_CN_PENDING_ZRA: Credit Note recorded in DigiTax (ID: $cnSaleId) · still syncing with ZRA.',
            );
            return false;
          }

          // Stage 2: Completed — Accepted by ZRA · Smart Invoice issued
          final internalData =
              (saleData['internal_data']?.toString().trim().isNotEmpty == true)
              ? saleData['internal_data'].toString().trim()
              : (config?.mrcNo ?? '');
          final fallbackCnSdc = sdcId.isNotEmpty
              ? sdcId
              : ((config?.tpin?.isNotEmpty == true)
                    ? '${config!.tpin!}001'
                    : 'SDC1');
          final effectiveCnRcpt =
              sdcRcptNo != 'PENDING' ? sdcRcptNo : traderInvNo;
          final qrUrl =
              (saleData['receipt_url']?.toString().trim().isNotEmpty == true &&
                  saleData['receipt_url'].toString().trim() != 'null')
              ? saleData['receipt_url'].toString().trim()
              : ((saleData['qr_code']?.toString().trim().isNotEmpty == true &&
                        saleData['qr_code'].toString().trim() != 'null')
                    ? saleData['qr_code'].toString().trim()
                    : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$fallbackCnSdc&rcpt=$effectiveCnRcpt');

          refundTx
            ..isCreditNote = true
            ..orgInvoiceNo = origTraderInvNo
            ..creditNoteReason = reason
            ..zraSdcId = sdcId
            ..zraReceiptNumber = sdcRcptNo != 'PENDING' ? sdcRcptNo : traderInvNo
            ..zraMarkId = liveSignature ?? cnSaleId
            ..zraInternalData = internalData
            ..zraQrCode = qrUrl
            ..zraInvoiceType = 'Credit Note (R)'
            ..zraStatus = 'APPROVED';

          await db.isar.writeTxn(() async {
            await db.isar.saleTransactions.put(refundTx);
          });

          // Restock items in DigiTax cloud inventory once ZRA approves
          for (final item in effectiveItems) {
            try {
              final product = await db.isar.products.get(item.productId);
              if (product != null && product.isDigitaxSyncEnabled) {
                final int restoreQty = (item.isWeighted && item.weight > 0)
                    ? item.weight.ceil()
                    : item.quantity;
                await pushStockMovementAdjustment(
                  product: product,
                  action: 'ADD',
                  movementType: '11',
                  quantity: restoreQty,
                  remarks: 'Restocked via Credit Note for Tx #${refundTx.id}',
                );
              }
            } catch (e) {
              debugPrint('DIGITAX_RESTOCK_PUSH_ERROR: $e');
            }
          }

          debugPrint(
            'DIGITAX_DEDICATED_CN_SUCCESS ✓ CN: ${refundTx.zraReceiptNumber} (DigiTax ID: $cnSaleId, Status: ${refundTx.zraStatus})',
          );
          return true;
        } else {
          // Before marking FAILED, check if DigiTax already recorded this Credit Note in GET /credit-notes
          final recoveredAfterPost = await refreshTransactionFiscalData(
            refundTx,
            useShortTimeout: true,
          );
          if (recoveredAfterPost) {
            return true;
          }
          if (refundTx.zraMarkId != null &&
              refundTx.zraMarkId!.trim().startsWith('sale_') &&
              refundTx.zraStatus.toUpperCase() == 'PENDING') {
            return false;
          }

          String errDetail = '';
          if (dedicatedResp.data is Map) {
            errDetail =
                (dedicatedResp.data['message'] ??
                        dedicatedResp.data['error'] ??
                        '')
                    .toString()
                    .trim();
          }
          final status =
              dedicatedResp.statusCode == 409 ||
                  (dedicatedResp.statusCode != null &&
                      dedicatedResp.statusCode! >= 500)
              ? 'PENDING'
              : (errDetail.isNotEmpty ? 'FAILED: $errDetail' : 'FAILED');
          await persistCreditNoteStatus(status);
          debugPrint(
            'DIGITAX_CREDIT_NOTE_REJECTED: HTTP ${dedicatedResp.statusCode} - ${dedicatedResp.data}',
          );
          return false;
        }
      } else {
        // Original sale is still syncing to DigiTax or item IDs are pending; keep Credit Note in PENDING state
        debugPrint(
          'DIGITAX_CN_LOOKUP_PENDING: origSaleId=$origSaleId, allItemsHaveId=$allItemsHaveId, itemsCount=${creditNoteItemsList.length} -> keeping PENDING',
        );
        refundTx
          ..isCreditNote = true
          ..orgInvoiceNo = origTraderInvNo
          ..creditNoteReason = reason
          ..zraReceiptNumber = 'PENDING'
          ..zraInvoiceType = 'Credit Note (R)'
          ..zraStatus = 'PENDING';
        await db.isar.writeTxn(() async {
          await db.isar.saleTransactions.put(refundTx);
        });
        return false;
      }
    } catch (strategy1Err) {
      await persistCreditNoteStatus('PENDING');
      debugPrint('DIGITAX_CN_NETWORK_PENDING: $strategy1Err');
      return false;
    }
  }

  /// Submits a standalone manual refund voucher directly to DigiTax VSDC as an official credit adjustment
  Future<bool> submitManualRefundToDigitax(RefundTransaction refund) async {
    final config = ref.read(storeConfigProvider).value;
    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('DIGITAX_MANUAL_REFUND: No API Key configured');
      return false;
    }

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    final saleDate = refund.refundDate
        .toIso8601String()
        .replaceAll('T', ' ')
        .substring(0, 19);
    final bhfId = config?.bhfId ?? '00';

    final creditNotePayload = {
      "kind": "CREDIT_NOTE",
      "invoice_type": "CREDIT_NOTE",
      "org_invoice_no": refund.saleTransactionUuid ?? "MANUAL-REFUND",
      "reason": refund.reason,
      "sale_date": saleDate,
      "currency_code": "ZMW",
      "payment_type_code": refund.refundType.contains('CARD')
          ? "02"
          : (refund.refundType.contains('MOBILE') ? "06" : "01"),
      "trader_invoice_number": refund.refundNumber,
      "customer_name": "General Retail Customer",
      "bhf_id": bhfId,
      "items": [
        {
          "item_name": "Sales Refund - ${refund.reason}",
          "item_code": "REFUND-MISC",
          "quantity": 1,
          "unit_price": refund.amount,
          "package_unit_quantity": 1,
          "discount_rate": 0,
          "discount_amount": 0,
          "total_amount": refund.amount,
          "vat_category_code": "A",
        },
      ],
    };

    try {
      debugPrint('DIGITAX_MANUAL_REFUND_POST: $creditNotePayload');
      final resp = await _dio.post(
        '$digitaxZambiaApiBaseUrl/sales',
        data: creditNotePayload,
        options: Options(headers: headers),
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        debugPrint('DIGITAX_MANUAL_REFUND_SUCCESS: ${refund.refundNumber}');
        return true;
      }
    } on DioException catch (dioErr) {
      debugPrint(
        'DIGITAX_MANUAL_REFUND_DIO_ERR: [${dioErr.response?.statusCode}] ${dioErr.response?.data ?? dioErr.message}',
      );
    } catch (e) {
      debugPrint('DIGITAX_MANUAL_REFUND_ERROR: $e');
    }
    return false;
  }

  /// Submits an official ZRA Fiscal Debit Note (Additional Charge / Upward Adjustment) to DigiTax
  /// Per DigiTax ZM API spec: kind='DEBIT_NOTE', invoice_type='DEBIT_NOTE', org_invoice_no referencing original invoice
  Future<bool> submitDebitNoteToDigitax(
    SaleTransaction debitTx, {
    List<SaleItem>? items,
    required String originalSdcInvoiceNo,
    required String reason,
  }) async {
    final db = ref.read(databaseServiceProvider);
    final config = ref.read(storeConfigProvider).value;
    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('DIGITAX_DEBIT_NOTE: No API Key configured – skipped');
      return false;
    }

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    final saleDate = debitTx.timestamp
        .toIso8601String()
        .replaceAll('T', ' ')
        .substring(0, 19);
    final bhfId = config?.bhfId ?? '00';

    final effectiveItems = <SaleItem>[];
    if (items != null && items.isNotEmpty) {
      effectiveItems.addAll(items);
    } else {
      try {
        await debitTx.items.load();
        effectiveItems.addAll(debitTx.items);
      } catch (_) {}
    }

    if (effectiveItems.isEmpty) {
      debugPrint('DIGITAX_DEBIT_NOTE_ERROR: No items provided for debit note.');
      return false;
    }
    effectiveItems.removeWhere((item) => item.isDigitaxExempt);
    if (effectiveItems.isEmpty) return true;

    String paymentTypeCode;
    switch (debitTx.paymentMethod.toUpperCase()) {
      case 'MOBILE MONEY':
        paymentTypeCode = '06';
        break;
      case 'CARD':
        paymentTypeCode = '05';
        break;
      case 'CREDIT':
        paymentTypeCode = '02';
        break;
      default:
        paymentTypeCode = '01'; // CASH
    }

    final digitaxItemsPayload = <Map<String, dynamic>>[];
    for (final item in effectiveItems) {
      final effectiveQty = (item.isWeighted && item.weight > 0)
          ? item.weight
          : item.quantity.toDouble();
      final lineTotal = (effectiveQty * item.priceAtSale).abs();
      final taxRate = item.taxRateAtSale;
      final vatCode = item.taxRateAtSale == 0 ? 'E' : 'A';

      digitaxItemsPayload.add({
        'item_name': item.productName,
        'item_code': 'SKU-${item.productId}',
        'quantity': effectiveQty.abs(),
        'unit_price': item.priceAtSale,
        'package_unit_quantity': 1,
        'tax_rate': taxRate,
        'discount_rate': 0,
        'discount_amount': 0,
        'total_amount': lineTotal,
        'vat_category_code': vatCode,
      });
    }

    final traderInvNo = (debitTx.id > 0)
        ? 'DN-${debitTx.id}'
        : 'DN-${DateTime.now().millisecondsSinceEpoch.toString().substring(4)}';

    final invoiceNumber = debitTx.id > 0
        ? debitTx.id
        : int.tryParse(traderInvNo.replaceAll(RegExp(r'[^0-9]'), '')) ??
              (DateTime.now().millisecondsSinceEpoch % 100000000);

    String origTraderInvNo = originalSdcInvoiceNo.trim();
    if (origTraderInvNo.isEmpty) {
      origTraderInvNo =
          (debitTx.orgInvoiceNo != null && debitTx.orgInvoiceNo!.isNotEmpty)
          ? debitTx.orgInvoiceNo!
          : (debitTx.transactionId ?? 'ORIG-${debitTx.id}');
    }

    final debitNotePayload = {
      "kind": "DEBIT_NOTE",
      "invoice_type": "DEBIT_NOTE",
      "invoice_status_code": "01",
      "invoice_number": invoiceNumber,
      "org_invoice_no": origTraderInvNo,
      "reason": reason.isNotEmpty
          ? reason
          : "Additional Items / Upward Price Correction",
      "sale_date": saleDate,
      "currency_code": "ZMW",
      "payment_type_code": paymentTypeCode,
      "trader_invoice_number": traderInvNo,
      "customer_name": debitTx.customerBusinessName?.trim().isNotEmpty == true
          ? debitTx.customerBusinessName!.trim()
          : "Walk-in Customer",
      if (debitTx.customerTpin?.trim().isNotEmpty == true)
        "customer_tin": debitTx.customerTpin!.trim(),
      "bhf_id": bhfId,
      "items": digitaxItemsPayload,
    };

    try {
      debugPrint(
        'DIGITAX_DEBIT_NOTE_POST: $traderInvNo against org: $origTraderInvNo',
      );
      final resp = await _dio.post(
        '$digitaxZambiaApiBaseUrl/sales',
        data: debitNotePayload,
        options: Options(headers: headers),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        Map<String, dynamic> saleData = (resp.data is Map)
            ? Map<String, dynamic>.from(resp.data)
            : {'raw': resp.data};

        final liveSignature = saleData['receipt_signature']?.toString().trim();
        final rcptNumberRaw =
            saleData['receipt_number'] ?? saleData['zra_receipt_number'];
        final sdcRcptNo = (rcptNumberRaw?.toString().isNotEmpty == true)
            ? rcptNumberRaw.toString()
            : traderInvNo;
        final internalData =
            saleData['internal_data']?.toString() ?? (config?.mrcNo ?? '');
        final sdcId = saleData['sdc_id']?.toString() ?? (config?.sdcId ?? '');
        final qrUrl = (saleData['receipt_url']?.toString().isNotEmpty == true)
            ? saleData['receipt_url'].toString()
            : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin}&sdc=$sdcId&rcpt=$sdcRcptNo';

        debitTx
          ..orgInvoiceNo = origTraderInvNo
          ..creditNoteReason = reason
          ..zraSdcId = sdcId
          ..zraReceiptNumber = sdcRcptNo
          ..zraMarkId = liveSignature ?? 'APPROVED'
          ..zraInternalData = internalData
          ..zraQrCode = qrUrl
          ..zraInvoiceType = 'Debit Note (D)'
          ..zraStatus = (liveSignature?.isNotEmpty == true)
              ? 'APPROVED'
              : 'PENDING';

        await db.isar.writeTxn(() async {
          await db.isar.saleTransactions.put(debitTx);
        });

        debugPrint(
          'DIGITAX_DEBIT_NOTE_SUCCESS ✓ DN: ${debitTx.zraReceiptNumber}',
        );
        return true;
      }
    } on DioException catch (dioErr) {
      debugPrint(
        'DIGITAX_DN_DIO_ERROR: [${dioErr.response?.statusCode}] ${dioErr.response?.data ?? dioErr.message}',
      );
    } catch (e) {
      debugPrint('DIGITAX_DEBIT_NOTE_ERROR: $e');
    }
    return false;
  }

  /// Automatically process offline or pending transactions and submit them to DigiTax
  Future<int> processPendingFiscalQueue() async {
    if (_isProcessingFiscalQueue) return 0;
    _isProcessingFiscalQueue = true;
    try {
      return await _processPendingFiscalQueue();
    } finally {
      _isProcessingFiscalQueue = false;
    }
  }

  Future<int> _processPendingFiscalQueue() async {
    final config = ref.read(storeConfigProvider).value;
    final currentUser = ref.read(authProvider);
    final branchCode = currentUser?.branchCode?.trim().isNotEmpty == true
        ? currentUser!.branchCode!.trim()
        : (config?.bhfId.trim().isNotEmpty == true
              ? config!.bhfId.trim()
              : '00');
    final apiKey = await resolveBranchApiKey(branchCode);
    if (apiKey == null || apiKey.isEmpty) return 0;

    final db = ref.read(databaseServiceProvider);
    final allTx = await db.isar.saleTransactions.where().findAll();
    final pendingTransactions = allTx.where((tx) {
      final hasReceipt =
          tx.zraReceiptNumber != null &&
          tx.zraReceiptNumber!.trim().isNotEmpty &&
          tx.zraReceiptNumber != 'PENDING';
      if (hasReceipt) return false;
      final statusUpper = tx.zraStatus.toUpperCase();
      if (statusUpper == 'APPROVED' ||
          statusUpper == 'FISCALIZED' ||
          statusUpper == 'LOCAL_EXEMPT' ||
          statusUpper == 'OFFLINE_EXEMPT') {
        return false;
      }
      if (!tx.isCreditNote && statusUpper == 'FAILED') {
        return false;
      }
      return true;
    }).toList();

    if (pendingTransactions.isEmpty) return 0;

    debugPrint(
      'DIGITAX_QUEUE_WORKER: Processing ${pendingTransactions.length} pending/offline transactions...',
    );

    int fiscalizedCount = 0;
    for (final tx in pendingTransactions) {
      try {
        // Step 1: First try recovering from DigiTax in case it was already accepted
        // (resolves 409 conflicts and previous network timeouts without double-submitting)
        final recovered = await refreshTransactionFiscalData(
          tx,
          useShortTimeout: true,
        );
        if (recovered) {
          fiscalizedCount++;
          debugPrint(
            'DIGITAX_QUEUE_WORKER: Tx #${tx.id} (${tx.transactionId}) resolved via live fiscal refresh!',
          );
          continue;
        }

        // If the transaction is ALREADY recorded in DigiTax (has a sale_01... ID)
        // and is in PENDING state (still syncing with ZRA), do NOT re-POST it to
        // /sales or /credit-notes! We will poll it again on the next queue cycle.
        if (tx.zraMarkId != null &&
            tx.zraMarkId!.trim().startsWith('sale_') &&
            !tx.zraStatus.toUpperCase().startsWith('FAILED')) {
          debugPrint(
            'DIGITAX_QUEUE_WORKER: Tx #${tx.id} (DigiTax ID: ${tx.zraMarkId}) is recorded in DigiTax and still syncing with ZRA (PENDING).',
          );
          continue;
        }

        await tx.items.load();
        final items = tx.items.toList();
        final localProducts = <Product>[];
        for (final item in items) {
          final product = await db.isar.products.get(item.productId);
          if (product != null) localProducts.add(product);
        }

        // Note: fiscalizeSaleTransaction will auto-register unregistered items on DigiTax
        // and return false if registration fails, so we no longer short-circuit here.

        final success = await fiscalizeSaleTransaction(tx, items);
        if (success) {
          fiscalizedCount++;
        }
      } catch (e) {
        debugPrint('DIGITAX_QUEUE_ERROR on Tx ${tx.id}: $e');
      }
    }
    return fiscalizedCount;
  }

  /// Built-in ZRA Corporate Taxpayer Registry fallback directory for instant
  /// offline & sandbox verification of major Zambian corporate TPINs.
  static const Map<String, Map<String, String>> _zraCorporateTaxpayerDirectory = {
    '1001874162': {
      'taxpayer_name': 'ACACIA FOOD AND BEVERAGES LIMITED',
      'physical_address':
          'Plot 8492, Lumumbashi Road, Chinika Industrial Area, Lusaka',
    },
    '1001646043': {
      'taxpayer_name': 'ZAMBIA REVENUE AUTHORITY',
      'physical_address': 'Revenue House, Kalambo Road, Lusaka',
    },
    '1000000818': {
      'taxpayer_name': 'ZAMBIA SUGAR PLC',
      'physical_address': 'Nakambala Estate, Mazabuka',
    },
    '1001593152': {
      'taxpayer_name': 'TRADE KINGS LIMITED',
      'physical_address': 'Plot 29381, Nampundwe Road, Light Industrial Area, Lusaka',
    },
    '1001592890': {
      'taxpayer_name': 'SHOPRITE CHECKERS ZAMBIA LIMITED',
      'physical_address': 'Cairo Road, Lusaka',
    },
    '1001594671': {
      'taxpayer_name': 'ZAMBEEF PRODUCTS PLC',
      'physical_address': 'Plot 4970, Manda Road, Industrial Area, Lusaka',
    },
    '1001595015': {
      'taxpayer_name': 'ZAMBIA BREWERIES PLC',
      'physical_address': 'Plot 6438, Mungwi Road, Heavy Industrial Area, Lusaka',
    },
    '1001595023': {
      'taxpayer_name': 'NATIONAL BREWERIES PLC',
      'physical_address': 'Plot 6438, Mungwi Road, Heavy Industrial Area, Lusaka',
    },
    '1001594019': {
      'taxpayer_name': 'PARMALAT ZAMBIA LIMITED',
      'physical_address': 'Plot 6469, Mungwi Road, Heavy Industrial Area, Lusaka',
    },
    '1001591681': {
      'taxpayer_name': 'CHILANGA CEMENT PLC',
      'physical_address': 'Kafue Road, Chilanga, Lusaka',
    },
    '1001592203': {
      'taxpayer_name': 'AIRTEL NETWORKS ZAMBIA PLC',
      'physical_address': 'Airtel House, Corner of Addis Ababa Drive & Great East Road, Lusaka',
    },
    '1001593489': {
      'taxpayer_name': 'MTN ZAMBIA LIMITED',
      'physical_address': 'Plot 2374, Great East Road, Lusaka',
    },
    '1001595287': {
      'taxpayer_name': 'ZAMBIA TELECOMMUNICATIONS COMPANY LIMITED',
      'physical_address': 'Zamtel House, Corner of Church & Chilubi Roads, Lusaka',
    },
    '1001595201': {
      'taxpayer_name': 'ZESCO LIMITED',
      'physical_address': 'Stand No. 6949, Great East Road, Lusaka',
    },
    '2032126930': {
      'taxpayer_name': 'NONA INNOVATIONS LIMITED',
      'physical_address': 'Lusaka, PLOT NO. 402, CHELSTONE, LUSAKA PROVINCE',
    },
    '2002720806': {
      'taxpayer_name': 'NAMIRI TECHNOLOGY ZAMBIA LIMITED',
      'physical_address': 'Lusaka, 1394, MUSHEMI ROAD, ROAD SPARK',
    },
    '2004189376': {
      'taxpayer_name': 'RIGHTFEST TWENTY FOUR INVESTMENTS LIMITED',
      'physical_address': 'STAND NO, CHUD/16/A CHUDLEIGH, LUSAKA',
    },
    '2003080899': {
      'taxpayer_name': 'BAIHUIFENG INVESTMENT LIMITED',
      'physical_address': 'Lusaka, LUSAKA PROVINCE',
    },
    '2001689328': {
      'taxpayer_name': 'ILETCO ELECTRICAL LTD',
      'physical_address': 'Lusaka, LUSAKA PROVINCE',
    },
    '2004105632': {
      'taxpayer_name': 'KUMAWA PAPER MILLS LIMITED',
      'physical_address': 'Lusaka, LUSAKA PROVINCE',
    },
    '1003305157': {
      'taxpayer_name': 'REMSONS INVESTMENTS ZAMBIA LIMITED',
      'physical_address': 'Lusaka, LUSAKA PROVINCE',
    },
    '1001802106': {
      'taxpayer_name': 'SM BURHANI LTD',
      'physical_address': 'Lusaka, LUSAKA PROVINCE',
    },
    '1000806641': {
      'taxpayer_name': 'TIYIMBE PHONE ENTERPRISES',
      'physical_address': 'Lusaka, LUSAKA PROVINCE',
    },
    '1019884121': {
      'taxpayer_name': 'CORANK ENTERPRISE',
      'physical_address': 'Lusaka, LUSAKA PROVINCE',
    },
  };

  static String? _zraPortalJSessionId;
  static String? _zraPortalCsrfToken;
  static DateTime? _zraPortalSessionTime;

  Future<bool> _refreshZraPortalSession(HttpClient client) async {
    try {
      final uri = Uri.parse(
        'https://sandboxportal.zra.org.zm/main/signup/indexTinUser',
      );
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
      );
      final resp = await req.close().timeout(const Duration(seconds: 6));
      for (final c in resp.cookies) {
        if (c.name.toUpperCase() == 'JSESSIONID' && c.value.isNotEmpty) {
          _zraPortalJSessionId = c.value;
        }
      }
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));
      final csrfMatch = RegExp(
        r'<meta\s+name="csrf-token"\s+content="([^"]+)"',
        caseSensitive: false,
      ).firstMatch(body);
      if (csrfMatch != null) {
        _zraPortalCsrfToken = csrfMatch.group(1)?.trim();
      }
      if (_zraPortalJSessionId != null && _zraPortalCsrfToken != null) {
        _zraPortalSessionTime = DateTime.now();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<Map<String, dynamic>?> _postZraPortalForm(
    HttpClient client,
    String path,
    String cleanTpin,
  ) async {
    try {
      final uri = Uri.parse('https://sandboxportal.zra.org.zm$path');
      final req = await client.postUrl(uri).timeout(const Duration(seconds: 6));
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/x-www-form-urlencoded; charset=UTF-8',
      );
      req.headers.set('X-Requested-With', 'XMLHttpRequest');
      if (_zraPortalCsrfToken != null) {
        req.headers.set('X-CSRF-Token', _zraPortalCsrfToken!);
      }
      if (_zraPortalJSessionId != null) {
        req.headers.set(
          HttpHeaders.cookieHeader,
          'JSESSIONID=$_zraPortalJSessionId',
        );
      }
      final payload = utf8.encode('tin=${Uri.encodeQueryComponent(cleanTpin)}');
      req.contentLength = payload.length;
      req.add(payload);
      final resp = await req.close().timeout(const Duration(seconds: 6));
      final text = (await resp
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 6)))
          .trim();
      if (text.isEmpty) {
        return null;
      }
      if (text.startsWith('<')) {
        return {'_expired': true};
      }
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  /// Queries ZRA Smart Invoice Portal's taxpayer verification endpoints
  /// (`getTaxpayerVerify`, `getVsdcTaxpayerVerify`, `getEtaxData`) to resolve any
  /// registered 10-digit Zambian TPIN into its official business name and address.
  Future<Map<String, dynamic>?> _lookupZraSmartInvoicePortal(
    String cleanTpin,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6)
      ..badCertificateCallback = (_, _, _) => true;
    try {
      final sessionExpired = _zraPortalJSessionId == null ||
          _zraPortalCsrfToken == null ||
          _zraPortalSessionTime == null ||
          DateTime.now().difference(_zraPortalSessionTime!) >
              const Duration(minutes: 4);
      if (sessionExpired) {
        final ok = await _refreshZraPortalSession(client);
        if (!ok) {
          return null;
        }
      }

      Future<List<Map<String, dynamic>?>> runQueries() {
        return Future.wait([
          _postZraPortalForm(
            client,
            '/main/signup/getTaxpayerVerify',
            cleanTpin,
          ),
          _postZraPortalForm(
            client,
            '/main/signup/getVsdcTaxpayerVerify',
            cleanTpin,
          ),
          _postZraPortalForm(
            client,
            '/common/getEtaxData',
            cleanTpin,
          ),
        ]);
      }

      var results = await runQueries();
      if (results.any((r) => r != null && r['_expired'] == true)) {
        final refreshed = await _refreshZraPortalSession(client);
        if (refreshed) {
          results = await runQueries();
        }
      }

      // 1. Check getTaxpayerVerify response
      final taxResp = results[0];
      if (taxResp != null && taxResp['base'] is Map) {
        final base = Map<String, dynamic>.from(taxResp['base'] as Map);
        String name = (base['taxPayerName'] ?? '').toString().trim();
        if (name.isEmpty &&
            base['businessNames'] is List &&
            (base['businessNames'] as List).isNotEmpty) {
          name = (base['businessNames'] as List).first.toString().trim();
        }
        final rawLoc = (base['locationDescription'] ?? base['prvncNm'] ?? '')
            .toString()
            .replaceAll(RegExp(r',+'), ', ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (_isValidTaxpayerName(name)) {
          return {
            'tpin': cleanTpin,
            'taxpayer_name': name,
            'physical_address': rawLoc,
          };
        }
      }

      // 2. Check getVsdcTaxpayerVerify response (for TPINs already signed up on Smart Invoice)
      final vsdcResp = results[1];
      if (vsdcResp != null && vsdcResp['base'] is Map) {
        final base = Map<String, dynamic>.from(vsdcResp['base'] as Map);
        final name =
            (base['taxprNm'] ?? base['businessNm'] ?? '').toString().trim();
        final rawLoc = (base['locDesc'] ?? base['prvncNm'] ?? '')
            .toString()
            .replaceAll(RegExp(r',+'), ', ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        if (_isValidTaxpayerName(name)) {
          return {
            'tpin': cleanTpin,
            'taxpayer_name': name,
            'physical_address': rawLoc,
          };
        }
      }

      // 3. Check getEtaxData response
      final etaxResp = results[2];
      if (etaxResp != null && etaxResp['citizen'] is Map) {
        final citizen = Map<String, dynamic>.from(etaxResp['citizen'] as Map);
        final name = (citizen['mbrNm'] ?? '').toString().trim();
        if (_isValidTaxpayerName(name)) {
          return {
            'tpin': cleanTpin,
            'taxpayer_name': name,
            'physical_address': '',
          };
        }
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return null;
  }

  static bool _isValidTaxpayerName(String? raw) {
    if (raw == null) {
      return false;
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    final lower = trimmed.toLowerCase();
    return lower != 'lookup' &&
        lower != 'test lookup' &&
        lower != 'unknown' &&
        lower != 'n/a' &&
        lower != 'null';
  }

  Future<void> _cacheTaxpayerLocally({
    required String tpin,
    required String name,
    String? address,
  }) async {
    final cleanTpin = tpin.trim();
    final cleanName = name.trim();
    final cleanAddr = (address ?? '').trim();
    if (cleanTpin.length != 10 || !_isValidTaxpayerName(cleanName)) {
      return;
    }
    try {
      final db = ref.read(databaseServiceProvider);
      final existingByTpin = await db.isar.suppliers
          .filter()
          .tpinEqualTo(cleanTpin)
          .findFirst();
      final existingByName = await db.isar.suppliers
          .filter()
          .nameEqualTo(cleanName, caseSensitive: false)
          .findFirst();
      final target = existingByTpin ?? existingByName;
      await db.isar.writeTxn(() async {
        if (target != null) {
          target.tpin = cleanTpin;
          target.name = cleanName;
          if (cleanAddr.isNotEmpty) {
            target.address = cleanAddr;
          }
          await db.isar.suppliers.put(target);
        } else {
          final supplier = Supplier()
            ..name = cleanName
            ..tpin = cleanTpin
            ..address = cleanAddr.isNotEmpty ? cleanAddr : null;
          await db.isar.suppliers.put(supplier);
        }
      });
    } catch (_) {}
  }

  /// Persist a verified or manually entered customer TPIN + business name locally
  /// and sync it to DigiTax's `/customers` endpoint so future lookups resolve immediately.
  Future<void> saveVerifiedCustomerTpin({
    required String tpin,
    required String name,
    String? address,
  }) async {
    final cleanTpin = tpin.trim().replaceAll(RegExp(r'\s'), '');
    final cleanName = name.trim();
    final cleanAddr = (address ?? '').trim();
    if (cleanTpin.length != 10 || !_isValidTaxpayerName(cleanName)) {
      return;
    }

    await _cacheTaxpayerLocally(
      tpin: cleanTpin,
      name: cleanName,
      address: cleanAddr,
    );

    // If running on a Cashier terminal, also sync the customer TPIN to the Manager POS over LAN
    try {
      final client = ref.read(networkClientProvider);
      if (client != null) {
        await client.saveTaxpayerTpin(
          tpin: cleanTpin,
          name: cleanName,
          address: cleanAddr,
        );
      }
    } catch (_) {}

    try {
      final currentUser = ref.read(authProvider);
      final apiKey = await resolveBranchApiKey(currentUser?.branchCode);
      if (apiKey == null || apiKey.isEmpty) {
        return;
      }
      await _dio.post(
        '$digitaxZambiaApiBaseUrl/customers',
        data: {
          'customer_tin': cleanTpin,
          'customer_name': cleanName,
          'phone': '0970000000',
          if (cleanAddr.isNotEmpty) 'address': cleanAddr,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'X-API-Key': apiKey,
            'Content-Type': 'application/json',
          },
          validateStatus: (s) => s != null && s < 500,
        ),
      );
    } catch (_) {}
  }

  /// Lookup and verify a Zambian taxpayer TPIN via local cache, ZRA directory, and DigiTax API
  /// Returns a map with keys: taxpayer_name, physical_address, tpin, error (on failure)
  Future<Map<String, dynamic>?> lookupTaxpayerTpin(String tpin) async {
    final db = ref.read(databaseServiceProvider);
    final config =
        ref.read(storeConfigProvider).value ??
        await db.isar.storeConfigs.where().findFirst();

    // Validate TPIN format first
    final cleanTpin = tpin.trim().replaceAll(RegExp(r'\s'), '');
    if (cleanTpin.length != 10 || !RegExp(r'^\d{10}$').hasMatch(cleanTpin)) {
      return {'error': 'TPIN must be exactly 10 digits'};
    }

    // 1. Check if it matches the store/seller's own configured TPIN or any branch TPIN
    if (config?.tpin != null && cleanTpin == config!.tpin!.trim()) {
      final name = config.businessName.trim();
      if (_isValidTaxpayerName(name)) {
        return {
          'tpin': cleanTpin,
          'taxpayer_name': name,
          'physical_address': (config.branchName ?? config.address ?? '').trim(),
        };
      }
    }
    try {
      final matchingBranch = await db.isar.storeBranchs
          .filter()
          .tpinEqualTo(cleanTpin)
          .findFirst();
      if (matchingBranch != null && _isValidTaxpayerName(matchingBranch.name)) {
        return {
          'tpin': cleanTpin,
          'taxpayer_name': matchingBranch.name.trim(),
          'physical_address': (matchingBranch.address ?? '').trim(),
        };
      }
    } catch (_) {}

    // 2. Check local DB past transactions for instant cache response
    try {
      final pastTx = await db.isar.saleTransactions
          .filter()
          .customerTpinEqualTo(cleanTpin)
          .findFirst();
      if (pastTx != null && _isValidTaxpayerName(pastTx.customerBusinessName)) {
        return {
          'tpin': cleanTpin,
          'taxpayer_name': pastTx.customerBusinessName!.trim(),
          'physical_address': (pastTx.customerAddress ?? '').trim(),
        };
      }
    } catch (_) {}

    // 3. Check local DB suppliers
    try {
      final localSupplier = await db.isar.suppliers
          .filter()
          .tpinEqualTo(cleanTpin)
          .findFirst();
      if (localSupplier != null && _isValidTaxpayerName(localSupplier.name)) {
        return {
          'tpin': cleanTpin,
          'taxpayer_name': localSupplier.name.trim(),
          'physical_address': (localSupplier.address ?? '').trim(),
        };
      }
    } catch (_) {}

    // 4. Check local DB purchase orders and customers
    try {
      final pastPo = await db.isar.purchaseOrders
          .filter()
          .supplierTpinEqualTo(cleanTpin)
          .findFirst();
      if (pastPo != null && _isValidTaxpayerName(pastPo.supplierName)) {
        return {
          'tpin': cleanTpin,
          'taxpayer_name': pastPo.supplierName.trim(),
          'physical_address': '',
        };
      }
      final localCustomer = await db.isar.customers
          .filter()
          .phoneNumberEqualTo(cleanTpin)
          .findFirst();
      if (localCustomer != null && _isValidTaxpayerName(localCustomer.name)) {
        return {
          'tpin': cleanTpin,
          'taxpayer_name': localCustomer.name.trim(),
          'physical_address': '',
        };
      }
    } catch (_) {}

    // 5. Check built-in ZRA Corporate Taxpayer Directory
    final directoryEntry = _zraCorporateTaxpayerDirectory[cleanTpin];
    if (directoryEntry != null) {
      final dName = directoryEntry['taxpayer_name'] ?? '';
      final dAddr = directoryEntry['physical_address'] ?? '';
      if (_isValidTaxpayerName(dName)) {
        await _cacheTaxpayerLocally(
          tpin: cleanTpin,
          name: dName,
          address: dAddr,
        );
        return {
          'tpin': cleanTpin,
          'taxpayer_name': dName,
          'physical_address': dAddr,
        };
      }
    }

    // 5b. If running on a Cashier terminal over LAN, ask the Manager POS first
    // (Manager POS has the master supplier/customer DB and branch DigiTax keys)
    if (config?.isManagerMode == false) {
      try {
        final client = ref.read(networkClientProvider);
        if (client != null) {
          final lanRes = await client.lookupTaxpayerTpin(cleanTpin);
          if (lanRes != null) {
            final lName = (lanRes['taxpayer_name'] ?? lanRes['name'] ?? '')
                .toString()
                .trim();
            final lAddr =
                (lanRes['physical_address'] ?? lanRes['address'] ?? '')
                    .toString()
                    .trim();
            if (_isValidTaxpayerName(lName)) {
              await _cacheTaxpayerLocally(
                tpin: cleanTpin,
                name: lName,
                address: lAddr,
              );
              return {
                'tpin': cleanTpin,
                'taxpayer_name': lName,
                'physical_address': lAddr,
              };
            }
          }
        }
      } catch (_) {}
    }

    // 5c. Live ZRA Smart Invoice Portal verification (resolves any registered 10-digit Zambian TPIN)
    try {
      final zraLive = await _lookupZraSmartInvoicePortal(cleanTpin);
      if (zraLive != null) {
        final zName = (zraLive['taxpayer_name'] ?? '').toString().trim();
        final zAddr = (zraLive['physical_address'] ?? '').toString().trim();
        if (_isValidTaxpayerName(zName)) {
          await _cacheTaxpayerLocally(
            tpin: cleanTpin,
            name: zName,
            address: zAddr,
          );
          unawaited(
            saveVerifiedCustomerTpin(
              tpin: cleanTpin,
              name: zName,
              address: zAddr,
            ),
          );
          return {
            'tpin': cleanTpin,
            'taxpayer_name': zName,
            'physical_address': zAddr,
          };
        }
      }
    } catch (_) {}

    // Collect all configured DigiTax API keys (cashier's branch + active store + all branches)
    final apiKeys = <String>{};
    final currentUser = ref.read(authProvider);
    final cashierBranchKey = await resolveBranchApiKey(currentUser?.branchCode);
    if (cashierBranchKey != null && cashierBranchKey.trim().isNotEmpty) {
      apiKeys.add(cashierBranchKey.trim());
    }
    final resolvedKey = await resolveBranchApiKey(null);
    if (resolvedKey != null && resolvedKey.trim().isNotEmpty) {
      apiKeys.add(resolvedKey.trim());
    }
    if (config?.digitaxApiKey != null &&
        config!.digitaxApiKey!.trim().isNotEmpty) {
      apiKeys.add(config.digitaxApiKey!.trim());
    }
    try {
      final branches = await db.isar.storeBranchs.where().findAll();
      for (final b in branches) {
        final bKey = b.digitaxApiKey?.trim();
        if (bKey != null && bKey.isNotEmpty) {
          apiKeys.add(bKey);
        }
      }
    } catch (_) {}

    // If Cashier terminal still has no DigiTax API key locally, pull it from Manager POS over LAN
    if (apiKeys.isEmpty && config?.isManagerMode == false) {
      try {
        final client = ref.read(networkClientProvider);
        if (client != null) {
          final serverInfo = await client.getServerInfo();
          final remoteKey = serverInfo?['digitaxApiKey']?.toString().trim();
          if (remoteKey != null && remoteKey.isNotEmpty) {
            apiKeys.add(remoteKey);
            if (config != null) {
              config.digitaxApiKey = remoteKey;
              await db.isar.writeTxn(() async {
                await db.isar.storeConfigs.put(config);
              });
            }
          }
        }
      } catch (_) {}
    }

    if (apiKeys.isEmpty) {
      return null;
    }

    for (final apiKey in apiKeys) {
      final headers = {
        'Authorization': 'Bearer $apiKey',
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      };

      // 6. Query /info endpoint (returns registered business name & TPIN)
      try {
        final infoResp = await _dio.get(
          '$digitaxZambiaApiBaseUrl/info',
          options: Options(
            headers: headers,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (infoResp.statusCode == 200 && infoResp.data is Map) {
          final iData = Map<String, dynamic>.from(infoResp.data as Map);
          final infoTpin = (iData['tax_pin'] ?? '').toString().trim();
          if (infoTpin == cleanTpin) {
            final bName = (iData['branch_office_name'] ??
                    config?.businessName ??
                    '')
                .toString()
                .trim();
            final bAddr = (iData['location_description'] ??
                    iData['province_name'] ??
                    '')
                .toString()
                .trim();
            if (_isValidTaxpayerName(bName)) {
              await _cacheTaxpayerLocally(
                tpin: cleanTpin,
                name: bName,
                address: bAddr,
              );
              return {
                'tpin': cleanTpin,
                'taxpayer_name': bName,
                'physical_address': bAddr,
              };
            }
          }
        }
      } catch (_) {}

      // 7. Query /customers list endpoint (paginated up to 50 pages)
      try {
        String? custCursor;
        for (int page = 0; page < 50; page++) {
          final custResp = await _dio.get(
            '$digitaxZambiaApiBaseUrl/customers',
            queryParameters: {
              'page_size': 20,
              if (custCursor != null && custCursor.isNotEmpty)
                'after': custCursor,
            },
            options: Options(
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (custResp.statusCode == 200 && custResp.data != null) {
            List cList = [];
            if (custResp.data is List) {
              cList = custResp.data;
            } else if (custResp.data is Map && custResp.data['data'] is List) {
              cList = custResp.data['data'];
            } else if (custResp.data is Map &&
                custResp.data['customers'] is List) {
              cList = custResp.data['customers'];
            }
            for (final c in cList) {
              if (c is Map) {
                final cTpin = (c['customer_tpin'] ??
                        c['customer_tin'] ??
                        c['tpin'] ??
                        c['tax_pin'] ??
                        '')
                    .toString()
                    .trim();
                final cName = (c['customer_name'] ??
                        c['name'] ??
                        c['business_name'] ??
                        '')
                    .toString()
                    .trim();
                final cAddr = (c['address'] ?? c['physical_address'] ?? '')
                    .toString()
                    .trim();
                if (cTpin.length == 10 && _isValidTaxpayerName(cName)) {
                  await _cacheTaxpayerLocally(
                    tpin: cTpin,
                    name: cName,
                    address: cAddr,
                  );
                  if (cTpin == cleanTpin) {
                    return {
                      'tpin': cleanTpin,
                      'taxpayer_name': cName,
                      'physical_address': cAddr,
                    };
                  }
                }
              }
            }
            if (custResp.data is Map && custResp.data['pagination'] is Map) {
              final next = custResp.data['pagination']['next']?.toString();
              if (next != null && next.isNotEmpty && next != custCursor) {
                custCursor = next;
                continue;
              }
            }
          }
          break;
        }
      } catch (_) {}

      // 8. Query /suppliers list endpoint (sellers/vendors, paginated up to 50 pages)
      try {
        String? supCursor;
        for (int page = 0; page < 50; page++) {
          final supResp = await _dio.get(
            '$digitaxZambiaApiBaseUrl/suppliers',
            queryParameters: {
              'page_size': 20,
              if (supCursor != null && supCursor.isNotEmpty)
                'after': supCursor,
            },
            options: Options(
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (supResp.statusCode == 200 && supResp.data != null) {
            List sList = [];
            if (supResp.data is List) {
              sList = supResp.data;
            } else if (supResp.data is Map && supResp.data['data'] is List) {
              sList = supResp.data['data'];
            } else if (supResp.data is Map &&
                supResp.data['suppliers'] is List) {
              sList = supResp.data['suppliers'];
            }
            for (final s in sList) {
              if (s is Map) {
                final sTpin = (s['supplier_tpin'] ??
                        s['supplier_tin'] ??
                        s['tpin'] ??
                        s['tax_pin'] ??
                        '')
                    .toString()
                    .trim();
                final sName = (s['supplier_name'] ??
                        s['name'] ??
                        s['business_name'] ??
                        '')
                    .toString()
                    .trim();
                final sAddr = (s['address'] ?? s['physical_address'] ?? '')
                    .toString()
                    .trim();
                if (sTpin.length == 10 && _isValidTaxpayerName(sName)) {
                  await _cacheTaxpayerLocally(
                    tpin: sTpin,
                    name: sName,
                    address: sAddr,
                  );
                  if (sTpin == cleanTpin) {
                    return {
                      'tpin': cleanTpin,
                      'taxpayer_name': sName,
                      'physical_address': sAddr,
                    };
                  }
                }
              }
            }
            if (supResp.data is Map && supResp.data['pagination'] is Map) {
              final next = supResp.data['pagination']['next']?.toString();
              if (next != null && next.isNotEmpty && next != supCursor) {
                supCursor = next;
                continue;
              }
            }
          }
          break;
        }
      } catch (_) {}
    }

    return null;
  }

  Future<Map<String, dynamic>> compileZraFiscalZReport({DateTime? date}) async {
    final db = ref.read(databaseServiceProvider);
    final targetDate = date ?? DateTime.now();
    final startOfDay = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      0,
      0,
      0,
    );
    final endOfDay = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      23,
      59,
      59,
    );

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
        final effectiveQty = (item.isWeighted && item.weight > 0)
            ? item.weight
            : item.quantity.toDouble();
        final itemTotal = (effectiveQty * item.priceAtSale);
        if (item.taxRateAtSale == 16.0 ||
            (item.taxRateAtSale == 0 && tx.taxAmount > 0)) {
          final vat = item.isTaxInclusiveAtSale
              ? (itemTotal * 16 / 116)
              : (itemTotal * 0.16);
          final taxable = item.isTaxInclusiveAtSale
              ? (itemTotal - vat)
              : itemTotal;
          taxA16Taxable += tx.isCreditNote ? -taxable : taxable;
          taxA16Vat += tx.isCreditNote ? -vat : vat;
        } else if (item.taxRateAtSale == 0) {
          taxB0Taxable += tx.isCreditNote ? -itemTotal : itemTotal;
        }
      }
    }

    grossSales = double.parse(grossSales.toStringAsFixed(2));
    taxA16Taxable = double.parse(taxA16Taxable.toStringAsFixed(2));
    taxB0Taxable = double.parse(taxB0Taxable.toStringAsFixed(2));
    taxCExportTaxable = double.parse(taxCExportTaxable.toStringAsFixed(2));
    taxDExemptTaxable = double.parse(taxDExemptTaxable.toStringAsFixed(2));
    taxEZeroTaxable = double.parse(taxEZeroTaxable.toStringAsFixed(2));

    // Preserve 4-decimal fiscal precision (e.g. 1.3793 per K10 sale -> 2.7586 for two sales)
    taxA16Vat = double.parse(taxA16Vat.toStringAsFixed(4));

    // Total tax strictly matches the fiscal VAT collected (2.7586)
    totalTax = taxA16Vat;
    final netSales = double.parse((grossSales - totalTax).toStringAsFixed(2));

    return {
      'date': targetDate,
      'totalTransactions': transactions.length,
      'normalInvoicesCount': normalInvoicesCount,
      'creditNotesCount': creditNotesCount,
      'grossSales': grossSales,
      'totalTax': totalTax,
      'netSales': netSales,
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

  /// Query DigiTax for the live fiscal control data of a specific transaction.
  /// Pass [useShortTimeout] = true when calling from background contexts (queue
  /// worker) so a slow network doesn't stall the app for 30 s per attempt.
  Future<bool> refreshTransactionFiscalData(
    SaleTransaction transaction, {
    bool useShortTimeout = false,
  }) async {
    final dio = useShortTimeout ? _backgroundDio : _dio;
    final config = ref.read(storeConfigProvider).value;
    final currentUser = ref.read(authProvider);
    final resolvedBhfId =
        (currentUser?.branchCode != null &&
            currentUser!.branchCode!.trim().isNotEmpty)
        ? currentUser.branchCode!.trim().padLeft(2, '0')
        : (config?.bhfId.trim().isNotEmpty == true
              ? config!.bhfId.trim().padLeft(2, '0')
              : '00');
    final apiKey =
        await resolveBranchApiKey(resolvedBhfId) ??
        config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) return false;

    final db = ref.read(databaseServiceProvider);
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    final traderInvoice = transaction.transactionId ?? 'INV-${transaction.id}';

    // If the stored signature looks like a DigiTax sale ID (sale_...), use it
    // to do a direct GET /sales/{id} lookup — much more reliable than trader_invoice_number
    final storedMark = transaction.zraMarkId;
    final directSaleId = (storedMark != null && storedMark.startsWith('sale_'))
        ? storedMark
        : null;

    try {
      final listEndpoint = transaction.isCreditNote
          ? '$digitaxZambiaApiBaseUrl/credit-notes'
          : '$digitaxZambiaApiBaseUrl/sales';

      Map<String, dynamic>? matchData;

      if (directSaleId != null) {
        // Per DigiTax OpenAPI spec: GET /sales/{sale_id} returns a single Sale object
        // (including credit notes, debit notes, LPO sales, and normal sales).
        final resp = await dio.get(
          '$digitaxZambiaApiBaseUrl/sales/$directSaleId',
          options: Options(
            headers: headers,
            validateStatus: (s) => s != null && s < 500,
          ),
        );
        if (resp.statusCode == 200 && resp.data is Map) {
          var singleMap = Map<String, dynamic>.from(resp.data as Map);
          if (singleMap['sale'] is Map) {
            singleMap = Map<String, dynamic>.from(singleMap['sale'] as Map);
          } else if (singleMap['data'] is Map) {
            singleMap = Map<String, dynamic>.from(singleMap['data'] as Map);
          }
          if (singleMap['id'] != null) {
            matchData = singleMap;
          }
        }
      }

      if (matchData == null) {
        // Paginate GET /credit-notes or GET /sales (up to 3 pages) to find the transaction
        String? afterCursor;
        for (int page = 0; page < 3; page++) {
          final qp = <String, dynamic>{'page_size': 20};
          if (afterCursor != null && afterCursor.isNotEmpty) {
            qp['after'] = afterCursor;
          }
          final resp = await dio.get(
            listEndpoint,
            queryParameters: qp,
            options: Options(
              headers: headers,
              validateStatus: (s) => s != null && s < 500,
            ),
          );
          if (resp.statusCode != 200 || resp.data is! Map) {
            break;
          }
          final bodyMap = Map<String, dynamic>.from(resp.data as Map);
          final list =
              bodyMap['data'] ??
              bodyMap['sales'] ??
              bodyMap['items'] ??
              bodyMap['results'];
          if (list is! List || list.isEmpty) {
            break;
          }
          for (final s in list) {
            if (s is! Map) {
              continue;
            }
            final sTrader = s['trader_invoice_number']?.toString().trim() ?? '';
            final sId = s['id']?.toString().trim() ?? '';
            final bool isMatch =
                sTrader == traderInvoice ||
                sId == traderInvoice ||
                (transaction.isCreditNote &&
                    transaction.id > 0 &&
                    (sTrader == 'CN-${transaction.id}' ||
                        sTrader.startsWith('CN-${transaction.id}-'))) ||
                (!transaction.isCreditNote &&
                    transaction.id > 0 &&
                    (sTrader == 'INV-${transaction.id}' ||
                        sTrader.startsWith('INV-${transaction.id}-')));
            if (isMatch) {
              matchData = Map<String, dynamic>.from(s);
              break;
            }
          }
          if (matchData != null) {
            break;
          }
          final pagination = bodyMap['pagination'];
          final nextCursor = (pagination is Map)
              ? pagination['next']?.toString().trim()
              : null;
          if (nextCursor == null || nextCursor.isEmpty) {
            break;
          }
          afterCursor = nextCursor;
        }
      }

      if (matchData != null) {
        final remoteStatusUpper =
            (matchData['status'] ?? '').toString().trim().toUpperCase();
        final matchedDigiTaxId = matchData['id']?.toString().trim();

        // Stage 3: Failed — ZRA rejected the submission · needs attention
        if (remoteStatusUpper == 'FAILED') {
          final failReason =
              (matchData['status_reason'] ??
                      matchData['error_message'] ??
                      matchData['message'] ??
                      'ZRA rejected the submission · needs attention.')
                  .toString()
                  .trim();
          transaction.zraStatus = 'FAILED: $failReason';
          transaction.zraReceiptNumber = null;
          transaction.zraQrCode = null;
          if (matchedDigiTaxId != null && matchedDigiTaxId.isNotEmpty) {
            transaction.zraMarkId = matchedDigiTaxId;
          }
          await db.isar.writeTxn(() async {
            await db.isar.saleTransactions.put(transaction);
          });
          return false;
        }

        // Only use ZRA-assigned receipt_number (never sale_number, which is assigned while still pending)
        final rawRcpt =
            matchData['receipt_number'] ??
            matchData['invoice_number'] ??
            matchData['sdc_invoice_number'];
        String? parsedSdcRcptNo;
        if (rawRcpt != null &&
            rawRcpt.toString().trim().isNotEmpty &&
            rawRcpt.toString() != 'null') {
          final rcptStr = rawRcpt.toString().trim();
          if (rcptStr.toUpperCase().startsWith('INV0') ||
              rcptStr.toUpperCase().startsWith('INV1/') ||
              rcptStr.toUpperCase().startsWith('INV/') ||
              rcptStr.toUpperCase().startsWith('CN')) {
            parsedSdcRcptNo = rcptStr;
          } else {
            final cleanNum = rcptStr
                .replaceFirst(RegExp(r'^(INV|CN)-0*'), '')
                .replaceFirst(RegExp(r'^(INV|CN)-'), '');
            final prefix = transaction.isCreditNote ? 'CN1/' : 'INV1/';
            parsedSdcRcptNo = '$prefix$cleanNum';
          }
        }

        // Helper function to extract ZRA signature across top-level and nested maps
        String? extractSig(Map<dynamic, dynamic> m) {
          final s =
              m['receipt_signature'] ??
              m['signature'] ??
              m['vsdc_signature'] ??
              m['receipt_sign'] ??
              m['vsdc_sign'] ??
              m['rcpt_sign'];
          if (s != null &&
              s.toString().trim().isNotEmpty &&
              s.toString() != 'null') {
            return s.toString().trim();
          }
          if (m['sale'] is Map) {
            final inner = extractSig(Map<dynamic, dynamic>.from(m['sale']));
            if (inner != null) {
              return inner;
            }
          }
          if (m['data'] is Map) {
            final inner = extractSig(Map<dynamic, dynamic>.from(m['data']));
            if (inner != null) {
              return inner;
            }
          }
          return null;
        }

        // Helper function to extract ZRA QR receipt URL across top-level and nested maps
        String? extractQrUrl(Map<dynamic, dynamic> m) {
          final q = m['receipt_url'] ?? m['qr_code'] ?? m['qr_url'];
          if (q != null &&
              q.toString().trim().isNotEmpty &&
              q.toString().trim() != 'null') {
            return q.toString().trim();
          }
          if (m['sale'] is Map) {
            final inner = extractQrUrl(Map<dynamic, dynamic>.from(m['sale']));
            if (inner != null) {
              return inner;
            }
          }
          if (m['data'] is Map) {
            final inner = extractQrUrl(Map<dynamic, dynamic>.from(m['data']));
            if (inner != null) {
              return inner;
            }
          }
          return null;
        }

        final parsedSignature = extractSig(matchData);
        final parsedInternalData =
            matchData['internal_data']?.toString().isNotEmpty == true
            ? matchData['internal_data'].toString()
            : null;
        final parsedSdcId = (matchData['sdc_id']?.toString().isNotEmpty == true)
            ? matchData['sdc_id'].toString()
            : ((matchData['serial_number']?.toString().isNotEmpty == true)
                  ? matchData['serial_number'].toString()
                  : null);
        final parsedQrUrl = extractQrUrl(matchData);
        final parsedInvoiceType = switch (matchData['receipt_type_code']
            ?.toString()) {
          'S' => 'Normal Sale',
          'R' => 'Credit Note',
          'C' => 'Copy',
          _ => matchData['kind']?.toString().replaceAll('_', ' ').toUpperCase(),
        };

        final isCompletedOrApproved =
            remoteStatusUpper == 'COMPLETED' ||
            remoteStatusUpper == 'APPROVED' ||
            (parsedSignature != null && parsedSignature.isNotEmpty) ||
            (parsedSdcRcptNo != null &&
                parsedSdcRcptNo.isNotEmpty &&
                parsedSdcRcptNo != 'PENDING');

        // Stage 1: Pending — Recorded in DigiTax · still syncing with ZRA
        if (!isCompletedOrApproved) {
          transaction.zraStatus = 'PENDING';
          transaction.zraReceiptNumber = 'PENDING';
          if (matchedDigiTaxId != null && matchedDigiTaxId.isNotEmpty) {
            transaction.zraMarkId = matchedDigiTaxId;
          }
          transaction.zraQrCode = null;
          await db.isar.writeTxn(() async {
            await db.isar.saleTransactions.put(transaction);
          });
          return false;
        }

        if (isCompletedOrApproved) {
          if (parsedSignature != null &&
              parsedSignature.isNotEmpty &&
              !parsedSignature.startsWith('sale_')) {
            transaction.zraMarkId = parsedSignature;
          }
          if (parsedSdcRcptNo != null &&
              parsedSdcRcptNo.isNotEmpty &&
              parsedSdcRcptNo != 'PENDING') {
            transaction.zraReceiptNumber = parsedSdcRcptNo;
          }
          if (parsedInternalData != null &&
              parsedInternalData.isNotEmpty &&
              parsedInternalData != 'PENDING') {
            transaction.zraInternalData = parsedInternalData;
          }
          if (parsedSdcId != null &&
              parsedSdcId.isNotEmpty &&
              parsedSdcId != 'PENDING') {
            transaction.zraSdcId = parsedSdcId;
          }
          if (parsedQrUrl != null && parsedQrUrl.isNotEmpty) {
            transaction.zraQrCode = parsedQrUrl;
          } else if (transaction.zraQrCode == null ||
              transaction.zraQrCode!.trim().isEmpty ||
              transaction.zraQrCode == 'PENDING') {
            final effectiveSdc =
                (transaction.zraSdcId != null &&
                    transaction.zraSdcId!.isNotEmpty &&
                    transaction.zraSdcId != 'PENDING')
                ? transaction.zraSdcId!
                : (config?.sdcId?.isNotEmpty == true
                      ? config!.sdcId!
                      : ((config?.tpin?.isNotEmpty == true)
                            ? '${config!.tpin!}001'
                            : 'SDC1'));
            final effectiveRcpt =
                (transaction.zraReceiptNumber != null &&
                    transaction.zraReceiptNumber!.isNotEmpty &&
                    transaction.zraReceiptNumber != 'PENDING')
                ? transaction.zraReceiptNumber!
                : (transaction.transactionId ?? 'INV-${transaction.id}');
            transaction.zraQrCode =
                'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$effectiveSdc&rcpt=$effectiveRcpt';
          }
          if (parsedInvoiceType != null && parsedInvoiceType.isNotEmpty) {
            transaction.zraInvoiceType = parsedInvoiceType;
          }

          // Pull server-calculated taxes from DigiTax
          _logFiscalSummaryMismatch(
            transaction,
            matchData['sales_tax_summary'],
          );

          transaction.zraStatus = 'APPROVED';

          await db.isar.writeTxn(() async {
            await db.isar.saleTransactions.put(transaction);
          });

          if (parsedSdcId != null &&
              parsedSdcId.isNotEmpty &&
              config != null &&
              config.sdcId != parsedSdcId) {
            config.sdcId = parsedSdcId;
            try {
              await db.saveStoreConfig(config);
            } catch (_) {}
          }

          debugPrint(
            'DIGITAX_REFRESHED_LIVE: Transaction #${transaction.id} updated -> SDC Inv: ${transaction.zraReceiptNumber}, Signature: ${transaction.zraMarkId}, Internal: ${transaction.zraInternalData}',
          );
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
      final double unitPrice =
          double.tryParse(item['cost']?.toString() ?? '0') ?? 0.0;

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
      if (prod != null &&
          prod.isDigitaxSyncEligible &&
          !prod.itemClsCd.startsWith('item_')) {
        try {
          await syncSingleProductToDigitax(prod);
          // Reload from DB to pick up the newly assigned itemClsCd
          final reloaded = await db.isar.products.get(prod.id);
          if (reloaded != null) prod = reloaded;
        } catch (e) {
          debugPrint('DIGITAX_AUTO_REGISTER_ON_PO_NOTE: $e');
        }
      }

      final String? digitaxItemId =
          (prod != null &&
              prod.isDigitaxSyncEligible &&
              prod.itemClsCd.startsWith('item_'))
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
          "_product": prod,
        });
      }
    }

    if (purchaseItems.isEmpty) {
      debugPrint(
        'DIGITAX_PURCHASE_SYNC: No items with valid DigiTax item_id found to submit',
      );
      return false;
    }

    final digitsOnly = poNumber.replaceAll(RegExp(r'[^0-9]'), '');
    final int invoiceNum = digitsOnly.isNotEmpty
        ? (int.tryParse(digitsOnly) ??
              (poNumber.hashCode.abs() % 900000 + 1000))
        : (poNumber.hashCode.abs() % 900000 + 1000);

    final cleanItemsPayload = purchaseItems.map((pi) {
      final map = Map<String, dynamic>.from(pi);
      map.remove('_product');
      return map;
    }).toList();

    final purchasePayload = {
      "purchase_date": DateTime.now().toIso8601String().substring(0, 10),
      "supplier_name": supplierName.isNotEmpty
          ? supplierName
          : 'Trade Supplier',
      if (supplierTin != null && supplierTin.trim().isNotEmpty)
        "supplier_tin": supplierTin.trim(),
      "supplier_invoice_number": invoiceNum,
      "payment_type_code": "07",
      "reject": false,
      "items": cleanItemsPayload,
    };

    bool purchaseInvoiceSuccess = false;
    try {
      final resp = await _dio.post(
        '$digitaxZambiaApiBaseUrl/purchases',
        data: purchasePayload,
        options: Options(headers: headers),
      );
      purchaseInvoiceSuccess = resp.statusCode == 200 || resp.statusCode == 201;
      debugPrint(
        'DIGITAX_PURCHASE_SYNC_SUCCESS: Created purchase invoice in DigiTax (${resp.data})',
      );
    } catch (e) {
      debugPrint('DIGITAX_PURCHASE_SYNC_ERROR: $e');
    }

    // 2. Adjust Cloud Stock Quantities on DigiTax & Record Local StockMovement Audit (movement_type: '02' Purchase Intake)
    for (final pItem in purchaseItems) {
      final itemId = pItem['item_id'] as String;
      final qty = pItem['quantity'] as int;
      final prod = pItem['_product'] as Product?;
      try {
        await _dio.put(
          '$digitaxZambiaApiBaseUrl/stock/adjust',
          data: {
            "item_id": itemId,
            "quantity": qty,
            "action": "ADD",
            "movement_type": "02", // Official ZRA Purchase / GRN Stock In
            "remarks":
                "Purchase Intake PO: $poNumber • Supplier: $supplierName",
          },
          options: Options(headers: headers),
        );
        debugPrint(
          'DIGITAX_PO_STOCK_IN_SUCCESS: Adjusted cloud stock for $itemId by +$qty',
        );
      } catch (stockErr) {
        debugPrint('DIGITAX_PO_STOCK_IN_ERROR: $stockErr');
      }

      if (prod != null) {
        try {
          await db.recordStockMovement(
            product: prod,
            actionType: 'ADD',
            movementType: '02',
            quantityChanged: qty,
            newStockLevel: prod.stockLevel,
            reasonCategory: 'Restock / Supplier Delivery',
            reasonNotes: 'Purchase PO: $poNumber • Supplier: $supplierName',
            branchCode: branchCode ?? config?.bhfId ?? '00',
            branchName: config?.branchName ?? 'Main Store',
            isSyncedWithDigitax: true,
          );
        } catch (e) {
          debugPrint('PO_STOCK_MOVEMENT_RECORD_NOTE: $e');
        }
      }
    }

    return purchaseInvoiceSuccess;
  }

  /// Fetches all remote products directly from DigiTax Cloud and returns their current stock quantities
  Future<Map<String, Map<String, dynamic>>> fetchRemoteStockMap() async {
    final config = ref.read(storeConfigProvider).value;

    final apiKey = config?.digitaxApiKey?.trim();
    if (apiKey == null || apiKey.isEmpty) return {};

    final headers = {
      'Authorization': 'Bearer $apiKey',
      'X-API-Key': apiKey,
      'Content-Type': 'application/json',
    };

    try {
      final remoteList = await _fetchAllRemoteItems(headers);

      final Map<String, Map<String, dynamic>> map = {};
      for (final item in remoteList) {
        final id = (item['id'] ?? '').toString();
        final name = (item['item_name'] ?? item['itemNm'] ?? item['name'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final code =
            (item['item_code'] ??
                    item['itemCd'] ??
                    item['bar_code'] ??
                    item['barcode'] ??
                    item['sku'] ??
                    '')
                .toString()
                .trim()
                .toLowerCase();
        final barcode = (item['bar_code'] ?? item['barcode'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final rawStock =
            item['stock_quantity'] ??
            item['quantity'] ??
            item['stock_level'] ??
            0;
        final int stock = (rawStock is num)
            ? rawStock.toInt()
            : (int.tryParse(rawStock.toString()) ?? 0);
        final rawPrice =
            item['default_unit_price'] ?? item['dftPrc'] ?? item['price'] ?? 0;
        final double price = (rawPrice is num)
            ? rawPrice.toDouble()
            : (double.tryParse(rawPrice.toString()) ?? 0.0);

        final itemData = <String, dynamic>{
          'id': id,
          'name': (item['item_name'] ?? item['itemNm'] ?? item['name'] ?? '')
              .toString()
              .trim(),
          'stock': stock,
          'price': price,
          'tax_code':
              (item['vat_category_code'] ??
                      item['taxTyCd'] ??
                      item['tax_code'] ??
                      'A')
                  .toString(),
        };

        if (id.isNotEmpty) map[id] = itemData;
        if (name.isNotEmpty) map[name] = itemData;
        if (code.isNotEmpty) map[code] = itemData;
        if (barcode.isNotEmpty) map[barcode] = itemData;
      }
      return map;
    } catch (e) {
      debugPrint('DIGITAX_FETCH_REMOTE_STOCK_ERROR: $e');
      return {};
    }
  }

  /// Returns a map of productId -> total unpushed sold quantity across all pending sales.
  /// Used by stock reconciliation to detect when a stock discrepancy is caused by unsynced sales.
  Future<Map<int, int>> getUnpushedSalesQtyMap() async {
    final db = ref.read(databaseServiceProvider);
    final allTx = await db.isar.saleTransactions.where().findAll();
    final pendingTxs = allTx.where((tx) {
      final hasReceipt = tx.zraReceiptNumber != null &&
          tx.zraReceiptNumber!.trim().isNotEmpty &&
          tx.zraReceiptNumber != 'PENDING';
      if (hasReceipt) return false;
      final s = tx.zraStatus.toUpperCase();
      return s != 'APPROVED' &&
          s != 'FISCALIZED' &&
          s != 'FAILED' &&
          s != 'LOCAL_EXEMPT' &&
          s != 'OFFLINE_EXEMPT';
    }).toList();

    final Map<int, int> productQtyMap = {};
    for (final tx in pendingTxs) {
      await tx.items.load();
      for (final item in tx.items) {
        final current = productQtyMap[item.productId] ?? 0;
        final qty = (item.isWeighted && item.weight > 0)
            ? item.weight.ceil()
            : item.quantity;
        productQtyMap[item.productId] = current + qty;
      }
    }
    return productQtyMap;
  }

  /// Returns the count of local sales that have not yet reached DigiTax / ZRA
  Future<int> countPendingFiscalTransactions() async {
    final db = ref.read(databaseServiceProvider);
    final allTx = await db.isar.saleTransactions.where().findAll();
    return allTx.where((tx) {
      final hasReceipt = tx.zraReceiptNumber != null &&
          tx.zraReceiptNumber!.trim().isNotEmpty &&
          tx.zraReceiptNumber != 'PENDING';
      if (hasReceipt) return false;
      final s = tx.zraStatus.toUpperCase();
      return s != 'APPROVED' &&
          s != 'FISCALIZED' &&
          s != 'FAILED' &&
          s != 'LOCAL_EXEMPT' &&
          s != 'OFFLINE_EXEMPT';
    }).length;
  }

  /// Reconciles stock for a single item by either pulling from DigiTax or pushing local POS stock to DigiTax
  Future<bool> reconcileProductStock({
    required Product product,
    required int targetStock,
    required bool
    pushToDigiTax, // true = adjust DigiTax to match POS; false = set POS to match DigiTax
    String? remarks,
  }) async {
    final db = ref.read(databaseServiceProvider);
    final localSql = ref.read(localSqlServiceProvider);
    final config = await db.getStoreConfig();
    final branchCode = product.branchCode.isNotEmpty
        ? product.branchCode
        : (config?.bhfId ?? '00');
    final currentPosStock = product.stockLevel;

    if (!pushToDigiTax) {
      // 1. PULL: Update local POS stock to match DigiTax Cloud
      final delta = targetStock - currentPosStock;
      final actionType = delta >= 0 ? 'ADD' : 'DEDUCT';
      final movementType = delta >= 0
          ? '06'
          : '16'; // 06 Surplus, 16 Discrepancy

      await db.isar.writeTxn(() async {
        product.stockLevel = targetStock;
        await db.isar.products.put(product);
      });

      await db.recordStockMovement(
        product: product,
        actionType: actionType,
        movementType: movementType,
        quantityChanged: delta.abs(),
        newStockLevel: targetStock,
        reasonCategory: 'DigiTax Cloud Stock Reconciliation',
        reasonNotes:
            remarks ??
            'Reconciled POS stock to match DigiTax cloud quantity ($targetStock)',
        branchCode: branchCode,
        branchName: config?.branchName ?? 'Main Store',
        isSyncedWithDigitax: true,
      );

      try {
        await localSql.update(
          'products',
          {'stock_level': targetStock},
          where: 'id = ?',
          whereArgs: [product.id],
        );
      } catch (sqlErr) {
        debugPrint('LocalSql update stock note: $sqlErr');
      }

      return true;
    } else {
      // 2. PUSH: Adjust DigiTax cloud stock to match local POS physical count
      final delta = currentPosStock - targetStock;
      if (delta == 0) return true; // Already matched

      final action = delta > 0 ? 'ADD' : 'DEDUCT';
      final movementType = delta > 0
          ? '06'
          : '16'; // 06 Audit Surplus, 16 Audit Shortage

      final success = await pushStockMovementAdjustment(
        product: product,
        action: action,
        movementType: movementType,
        quantity: delta.abs(),
        remarks:
            remarks ??
            'Physical count audit reconciliation to match POS stock ($currentPosStock)',
        branchCode: branchCode,
      );

      if (success) {
        await db.recordStockMovement(
          product: product,
          actionType: action,
          movementType: movementType,
          quantityChanged: delta.abs(),
          newStockLevel: currentPosStock,
          reasonCategory: 'Physical Stock Count Reconciliation',
          reasonNotes:
              'Adjusted DigiTax cloud ledger by ${delta > 0 ? "+$delta" : "$delta"} to match POS ($currentPosStock)',
          branchCode: branchCode,
          branchName: config?.branchName ?? 'Main Store',
          isSyncedWithDigitax: true,
        );
      }

      return success;
    }
  }
}
