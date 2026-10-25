import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

import '../models/models.dart';
import 'database_service.dart';

final csvStockServiceProvider = Provider<CsvStockService>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return CsvStockService(db);
});

class CsvColumnMapping {
  int nameIndex;
  int skuIndex;
  int priceIndex;
  int costIndex;
  int stockIndex;
  int categoryIndex;
  int taxCodeIndex;
  int taxRateIndex;

  // Defaults for fill-in-the-blanks / missing fields
  bool autoGenerateSku;
  double defaultPrice;
  double defaultCost;
  int defaultStock;
  int defaultCategoryId;
  String defaultTaxCode;
  double defaultTaxRate;
  bool updateExisting; // true = update existing products by SKU, false = skip

  CsvColumnMapping({
    this.nameIndex = -1,
    this.skuIndex = -1,
    this.priceIndex = -1,
    this.costIndex = -1,
    this.stockIndex = -1,
    this.categoryIndex = -1,
    this.taxCodeIndex = -1,
    this.taxRateIndex = -1,
    this.autoGenerateSku = true,
    this.defaultPrice = 0.0,
    this.defaultCost = 0.0,
    this.defaultStock = 0,
    this.defaultCategoryId = 0,
    this.defaultTaxCode = 'A',
    this.defaultTaxRate = 16.0,
    this.updateExisting = true,
  });
}

class CsvPreviewItem {
  final int rowIndex;
  String name;
  String sku;
  double price;
  double cost;
  int stock;
  String categoryName;
  String taxCode;
  double taxRate;
  bool isDuplicate;
  bool hasMissingFields;
  List<String> warnings;

  CsvPreviewItem({
    required this.rowIndex,
    required this.name,
    required this.sku,
    required this.price,
    required this.cost,
    required this.stock,
    required this.categoryName,
    required this.taxCode,
    required this.taxRate,
    this.isDuplicate = false,
    this.hasMissingFields = false,
    required this.warnings,
  });
}

class CsvImportResult {
  final bool success;
  final int totalRows;
  final int insertedCount;
  final int updatedCount;
  final int skippedCount;
  final int categoriesCreated;
  final List<String> errors;

  CsvImportResult({
    required this.success,
    required this.totalRows,
    required this.insertedCount,
    required this.updatedCount,
    required this.skippedCount,
    required this.categoriesCreated,
    required this.errors,
  });
}

class CsvStockService {
  final DatabaseService _db;

  CsvStockService(this._db);

  /// ─────────────────────────────────────────────────────────────────────────────
  /// EXPORT STOCK TO CSV
  /// ─────────────────────────────────────────────────────────────────────────────
  Future<String?> exportStockToCsv({
    required List<Product> products,
    required List<Category> categories,
    String? branchCode,
  }) async {
    try {
      final categoryMap = {for (final c in categories) c.id: c.name};

      final List<List<dynamic>> rows = [];

      // CSV Header Row
      rows.add([
        'SKU',
        'Product Name',
        'Category',
        'Selling Price',
        'Cost Price',
        'Stock Quantity',
        'Tax Code',
        'Tax Rate (%)',
        'Tax Inclusive',
        'ZRA Item Classification Code',
        'Branch Code',
        'Branch Name',
      ]);

      for (final p in products) {
        final catName = categoryMap[p.categoryId] ?? 'General';
        rows.add([
          p.sku,
          p.name,
          catName,
          p.price.toStringAsFixed(2),
          p.unitCost.toStringAsFixed(2),
          p.stockLevel,
          p.zraTaxCode,
          p.taxRate.toStringAsFixed(1),
          p.isTaxInclusive ? 'Yes' : 'No',
          p.itemClsCd,
          p.branchCode,
          p.branchName ?? '',
        ]);
      }

      final csvData = const ListToCsvConverter().convert(rows);
      final bytes = utf8.encode(csvData);

      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'Beleka_Stock_Catalog_$dateStr.csv';

      return await _saveFileCrossPlatform(bytes, fileName, 'csv');
    } catch (e) {
      debugPrint('CSV_EXPORT_ERROR: $e');
      return null;
    }
  }

  /// ─────────────────────────────────────────────────────────────────────────────
  /// DOWNLOAD SAMPLE TEMPLATE CSV
  /// ─────────────────────────────────────────────────────────────────────────────
  Future<String?> downloadSampleTemplate() async {
    try {
      final List<List<dynamic>> rows = [
        [
          'SKU',
          'Product Name',
          'Category',
          'Selling Price',
          'Cost Price',
          'Stock Quantity',
          'Tax Code',
          'Tax Rate',
        ],
        [
          'BLK-MILK-500',
          'Fresh Full Cream Milk 500ml',
          'Dairy & Eggs',
          '18.50',
          '14.00',
          '50',
          'A',
          '16.0',
        ],
        [
          'BLK-BREAD-01',
          'Sliced White Bread 800g',
          'Bakery',
          '24.00',
          '19.50',
          '35',
          'B',
          '0.0',
        ],
        [
          'BLK-SUGAR-2KG',
          'White Cane Sugar 2kg',
          'Groceries',
          '45.00',
          '38.00',
          '80',
          'A',
          '16.0',
        ],
        [
          'BLK-SOAP-BAR',
          'Hygiene Bath Soap 150g',
          'Toiletries',
          '12.00',
          '8.50',
          '120',
          'A',
          '16.0',
        ],
        [
          'BLK-BOOK-A4',
          'Hardcover A4 Exercise Book',
          'Stationery',
          '35.00',
          '26.00',
          '40',
          'A',
          '16.0',
        ],
      ];

      final csvData = const ListToCsvConverter().convert(rows);
      final bytes = utf8.encode(csvData);
      const fileName = 'Beleka_Stock_Import_Template.csv';

      return await _saveFileCrossPlatform(bytes, fileName, 'csv');
    } catch (e) {
      debugPrint('CSV_TEMPLATE_ERROR: $e');
      return null;
    }
  }

  /// ─────────────────────────────────────────────────────────────────────────────
  /// DETECT CSV DELIMITER AND PARSE ROWS
  /// ─────────────────────────────────────────────────────────────────────────────
  List<List<dynamic>> parseCsvContent(String rawContent) {
    if (rawContent.trim().isEmpty) return [];

    // Detect delimiter from first non-empty line
    final firstLine = rawContent.split(RegExp(r'\r\n|\n|\r')).firstWhere(
          (l) => l.trim().isNotEmpty,
          orElse: () => '',
        );

    String fieldDelimiter = ',';
    final commaCount = ','.allMatches(firstLine).length;
    final semiCount = ';'.allMatches(firstLine).length;
    final tabCount = '\t'.allMatches(firstLine).length;

    if (semiCount > commaCount && semiCount > tabCount) {
      fieldDelimiter = ';';
    } else if (tabCount > commaCount && tabCount > semiCount) {
      fieldDelimiter = '\t';
    }

    final converter = CsvToListConverter(
      fieldDelimiter: fieldDelimiter,
      shouldParseNumbers: false,
      allowInvalid: true,
    );

    return converter.convert(rawContent);
  }

  /// Auto-match CSV headers to Beleka Product fields
  CsvColumnMapping autoDetectMapping(List<String> headers, int defaultCategoryId) {
    final mapping = CsvColumnMapping(defaultCategoryId: defaultCategoryId);

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

      // Name detection
      if (mapping.nameIndex == -1 &&
          (h.contains('productname') ||
              h == 'name' ||
              h == 'product' ||
              h == 'itemname' ||
              h == 'item' ||
              h == 'description' ||
              h == 'title')) {
        mapping.nameIndex = i;
        continue;
      }

      // SKU detection
      if (mapping.skuIndex == -1 &&
          (h.contains('sku') ||
              h.contains('barcode') ||
              h == 'code' ||
              h == 'itemcode' ||
              h == 'upc' ||
              h == 'id' ||
              h == 'productcode')) {
        mapping.skuIndex = i;
        continue;
      }

      // Selling Price detection
      if (mapping.priceIndex == -1 &&
          (h.contains('sellingprice') ||
              h.contains('retail') ||
              h == 'price' ||
              h == 'unitprice' ||
              h == 'rate' ||
              h == 'amount')) {
        mapping.priceIndex = i;
        continue;
      }

      // Cost Price detection
      if (mapping.costIndex == -1 &&
          (h.contains('costprice') ||
              h.contains('unitcost') ||
              h == 'cost' ||
              h == 'purchaseprice' ||
              h == 'buyprice')) {
        mapping.costIndex = i;
        continue;
      }

      // Stock Level detection
      if (mapping.stockIndex == -1 &&
          (h.contains('stockquantity') ||
              h.contains('stocklevel') ||
              h.contains('quantity') ||
              h == 'stock' ||
              h == 'qty' ||
              h == 'balance' ||
              h == 'onhand')) {
        mapping.stockIndex = i;
        continue;
      }

      // Category detection
      if (mapping.categoryIndex == -1 &&
          (h.contains('category') ||
              h == 'cat' ||
              h == 'department' ||
              h == 'dept' ||
              h == 'group')) {
        mapping.categoryIndex = i;
        continue;
      }

      // Tax Code detection
      if (mapping.taxCodeIndex == -1 &&
          (h.contains('taxcode') || h == 'tax' || h == 'vatcode')) {
        mapping.taxCodeIndex = i;
        continue;
      }

      // Tax Rate detection
      if (mapping.taxRateIndex == -1 &&
          (h.contains('taxrate') || h.contains('vatrate') || h == 'rate')) {
        mapping.taxRateIndex = i;
        continue;
      }
    }

    return mapping;
  }

  /// ─────────────────────────────────────────────────────────────────────────────
  /// GENERATE PREVIEW ITEMS FOR VERIFICATION
  /// ─────────────────────────────────────────────────────────────────────────────
  Future<List<CsvPreviewItem>> generatePreview({
    required List<List<dynamic>> rows,
    required CsvColumnMapping mapping,
    required List<Product> existingProducts,
    required List<Category> categories,
  }) async {
    final List<CsvPreviewItem> previews = [];
    final existingSkus = {for (final p in existingProducts) p.sku.trim().toLowerCase(): p};
    final existingNames = {for (final p in existingProducts) p.name.trim().toLowerCase(): p};
    final categoryMap = {for (final c in categories) c.id: c.name};

    final defaultCategoryName = categoryMap[mapping.defaultCategoryId] ?? 'General';

    // Skip header row
    final dataRows = rows.skip(1).toList();

    for (int i = 0; i < dataRows.length; i++) {
      final row = dataRows[i];
      if (row.isEmpty || row.every((c) => c.toString().trim().isEmpty)) continue;

      final List<String> warnings = [];
      bool hasMissing = false;

      // Extract Name
      String name = '';
      if (mapping.nameIndex >= 0 && mapping.nameIndex < row.length) {
        name = row[mapping.nameIndex].toString().trim();
      }
      if (name.isEmpty) {
        name = 'Product #${i + 1}';
        hasMissing = true;
        warnings.add('Missing Name (assigned default)');
      }

      // Extract SKU
      String sku = '';
      if (mapping.skuIndex >= 0 && mapping.skuIndex < row.length) {
        sku = row[mapping.skuIndex].toString().trim();
      }
      if (sku.isEmpty) {
        if (mapping.autoGenerateSku) {
          sku = 'BLK-IMP-${(i + 1).toString().padLeft(4, '0')}';
          warnings.add('Auto-generated SKU');
        } else {
          hasMissing = true;
          warnings.add('Missing SKU');
        }
      }

      // Extract Price
      double price = mapping.defaultPrice;
      if (mapping.priceIndex >= 0 && mapping.priceIndex < row.length) {
        final pVal = row[mapping.priceIndex].toString().replaceAll(RegExp(r'[^0-9.]'), '');
        final parsed = double.tryParse(pVal);
        if (parsed != null) {
          price = parsed;
        } else {
          hasMissing = true;
          warnings.add('Invalid Price (using default K${mapping.defaultPrice.toStringAsFixed(2)})');
        }
      } else {
        warnings.add('Using default Price (K${mapping.defaultPrice.toStringAsFixed(2)})');
      }

      // Extract Cost
      double cost = mapping.defaultCost;
      if (mapping.costIndex >= 0 && mapping.costIndex < row.length) {
        final cVal = row[mapping.costIndex].toString().replaceAll(RegExp(r'[^0-9.]'), '');
        final parsed = double.tryParse(cVal);
        if (parsed != null) cost = parsed;
      }

      // Extract Stock
      int stock = mapping.defaultStock;
      if (mapping.stockIndex >= 0 && mapping.stockIndex < row.length) {
        final sVal = row[mapping.stockIndex].toString().replaceAll(RegExp(r'[^0-9]'), '');
        final parsed = int.tryParse(sVal);
        if (parsed != null) {
          stock = parsed;
        } else {
          warnings.add('Default Stock ($stock)');
        }
      } else {
        warnings.add('Default Stock ($stock)');
      }

      // Extract Category
      String catName = defaultCategoryName;
      if (mapping.categoryIndex >= 0 && mapping.categoryIndex < row.length) {
        final cVal = row[mapping.categoryIndex].toString().trim();
        if (cVal.isNotEmpty) {
          catName = cVal;
        } else {
          warnings.add('Default Category ($defaultCategoryName)');
        }
      } else {
        warnings.add('Default Category ($defaultCategoryName)');
      }

      // Extract Tax Code & Rate
      String taxCode = mapping.defaultTaxCode;
      double taxRate = mapping.defaultTaxRate;
      if (mapping.taxCodeIndex >= 0 && mapping.taxCodeIndex < row.length) {
        final tVal = row[mapping.taxCodeIndex].toString().trim().toUpperCase();
        if (tVal.isNotEmpty) taxCode = tVal;
      }
      if (mapping.taxRateIndex >= 0 && mapping.taxRateIndex < row.length) {
        final rVal = row[mapping.taxRateIndex].toString().replaceAll(RegExp(r'[^0-9.]'), '');
        final parsed = double.tryParse(rVal);
        if (parsed != null) taxRate = parsed;
      }

      final isDup = (sku.isNotEmpty && existingSkus.containsKey(sku.toLowerCase())) ||
          (existingNames.containsKey(name.toLowerCase()));

      previews.add(CsvPreviewItem(
        rowIndex: i + 1,
        name: name,
        sku: sku,
        price: price,
        cost: cost,
        stock: stock,
        categoryName: catName,
        taxCode: taxCode,
        taxRate: taxRate,
        isDuplicate: isDup,
        hasMissingFields: hasMissing,
        warnings: warnings,
      ));
    }

    return previews;
  }

  /// ─────────────────────────────────────────────────────────────────────────────
  /// EXECUTE THE IMPORT TRANSACTION
  /// ─────────────────────────────────────────────────────────────────────────────
  Future<CsvImportResult> executeImport({
    required List<CsvPreviewItem> items,
    required bool updateExisting,
    required String branchCode,
    String? branchName,
    String? currentUserId,
    String? currentUserName,
  }) async {
    int insertedCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    int categoriesCreated = 0;
    final List<String> errors = [];

    try {
      final isar = _db.isar;

      // 1. Fetch current categories into memory
      final existingCategories = await isar.categorys.where().findAll();
      final categoryMap = <String, Category>{};
      for (final c in existingCategories) {
        categoryMap[c.name.trim().toLowerCase()] = c;
      }

      // 2. Fetch existing products for this branch to detect SKU/Name matches
      final existingProducts = await isar.products.where().findAll();
      final productSkuMap = <String, Product>{};
      final productNameMap = <String, Product>{};

      for (final p in existingProducts) {
        if (p.sku.isNotEmpty) {
          productSkuMap[p.sku.trim().toLowerCase()] = p;
        }
        productNameMap[p.name.trim().toLowerCase()] = p;
      }

      final List<StockMovement> movements = [];

      await isar.writeTxn(() async {
        for (final item in items) {
          try {
            // Find or create Category
            final catKey = item.categoryName.trim().toLowerCase();
            Category? cat = categoryMap[catKey];
            if (cat == null && item.categoryName.trim().isNotEmpty) {
              cat = Category(
                name: item.categoryName.trim(),
                sector: CategorySector.other,
              );
              await isar.categorys.put(cat);
              categoryMap[catKey] = cat;
              categoriesCreated++;
            }

            final categoryId = cat?.id ?? 0;

            // Check if product already exists by SKU or Name
            Product? existing;
            if (item.sku.isNotEmpty && productSkuMap.containsKey(item.sku.trim().toLowerCase())) {
              existing = productSkuMap[item.sku.trim().toLowerCase()];
            } else if (productNameMap.containsKey(item.name.trim().toLowerCase())) {
              existing = productNameMap[item.name.trim().toLowerCase()];
            }

            if (existing != null) {
              if (!updateExisting) {
                skippedCount++;
                continue;
              }

              // Update existing product
              final oldStock = existing.stockLevel;
              existing.name = item.name;
              existing.price = item.price;
              existing.unitCost = item.cost;
              existing.stockLevel = item.stock; // Set new physical stock level
              if (categoryId > 0) existing.categoryId = categoryId;
              existing.zraTaxCode = item.taxCode;
              existing.taxRate = item.taxRate;
              existing.isArchived = false;

              await isar.products.put(existing);
              updatedCount++;

              // Record stock movement if stock level changed
              if (oldStock != item.stock) {
                final qtyDiff = (item.stock - oldStock).abs();
                movements.add(StockMovement(
                  productId: existing.id,
                  productName: existing.name,
                  sku: existing.sku,
                  branchCode: branchCode,
                  branchName: branchName,
                  movementType: item.stock >= oldStock ? '01' : '02',
                  actionType: item.stock >= oldStock ? 'ADD' : 'DEDUCT',
                  previousStock: oldStock,
                  quantityChanged: qtyDiff,
                  newStock: item.stock,
                  unitCost: item.cost,
                  totalCostImpact: qtyDiff * item.cost,
                  reasonCategory: 'CSV Stock Import Adjustment',
                  reasonNotes: 'Stock updated via CSV Import from $oldStock to ${item.stock}',
                  userId: currentUserId,
                  userName: currentUserName,
                ));
              }
            } else {
              // Create brand new product
              final newProduct = Product(
                name: item.name,
                sku: item.sku,
                price: item.price,
                unitCost: item.cost,
                stockLevel: item.stock,
                categoryId: categoryId,
                zraTaxCode: item.taxCode,
                taxRate: item.taxRate,
                isTaxInclusive: true,
                itemClsCd: '10101501',
                branchCode: branchCode,
                branchName: branchName,
                isArchived: false,
                isDigitaxSyncEnabled: true,
                isSyncedWithDigitax: false,
              );

              await isar.products.put(newProduct);
              insertedCount++;

              // Update in-memory map to avoid duplicate inserts within the same CSV batch
              if (newProduct.sku.isNotEmpty) {
                productSkuMap[newProduct.sku.trim().toLowerCase()] = newProduct;
              }
              productNameMap[newProduct.name.trim().toLowerCase()] = newProduct;

              // Record opening stock movement
              if (item.stock > 0) {
                movements.add(StockMovement(
                  productId: newProduct.id,
                  productName: newProduct.name,
                  sku: newProduct.sku,
                  branchCode: branchCode,
                  branchName: branchName,
                  movementType: '01',
                  actionType: 'ADD',
                  previousStock: 0,
                  quantityChanged: item.stock,
                  newStock: item.stock,
                  unitCost: item.cost,
                  totalCostImpact: item.stock * item.cost,
                  reasonCategory: 'Initial Stock / Opening Balance',
                  reasonNotes: 'Created via CSV Stock Import with initial stock of ${item.stock}',
                  userId: currentUserId,
                  userName: currentUserName,
                ));
              }
            }
          } catch (rowErr) {
            errors.add('Row #${item.rowIndex} (${item.name}): $rowErr');
          }
        }

        // Put all stock movements
        if (movements.isNotEmpty) {
          await isar.stockMovements.putAll(movements);
        }
      });

      return CsvImportResult(
        success: errors.isEmpty || (insertedCount > 0 || updatedCount > 0),
        totalRows: items.length,
        insertedCount: insertedCount,
        updatedCount: updatedCount,
        skippedCount: skippedCount,
        categoriesCreated: categoriesCreated,
        errors: errors,
      );
    } catch (e) {
      debugPrint('EXECUTE_IMPORT_ERROR: $e');
      return CsvImportResult(
        success: false,
        totalRows: items.length,
        insertedCount: insertedCount,
        updatedCount: updatedCount,
        skippedCount: skippedCount,
        categoriesCreated: categoriesCreated,
        errors: ['Database Error: $e'],
      );
    }
  }

  /// ─────────────────────────────────────────────────────────────────────────────
  /// CROSS-PLATFORM FILE SAVER
  /// ─────────────────────────────────────────────────────────────────────────────
  Future<String?> _saveFileCrossPlatform(
    List<int> bytes,
    String fileName,
    String extension,
  ) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        File? writtenFile;
        try {
          final List<Directory> candidateDirs = [];
          if (Platform.isAndroid) {
            try {
              final extDir = await getExternalStorageDirectory();
              if (extDir != null) candidateDirs.add(extDir);
            } catch (_) {}
          }
          try {
            candidateDirs.add(await getApplicationDocumentsDirectory());
          } catch (_) {}

          for (final dir in candidateDirs) {
            try {
              final file = File('${dir.path}/$fileName');
              await file.writeAsBytes(bytes);
              writtenFile = file;
              break;
            } catch (_) {}
          }
        } catch (_) {}

        if (writtenFile != null && writtenFile.existsSync()) {
          try {
            await Printing.sharePdf(
              bytes: Uint8List.fromList(bytes),
              filename: fileName,
            );
          } catch (_) {}
          return writtenFile.path;
        }
        return null;
      }

      // Windows / Desktop
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [extension],
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        return outputFile;
      }
      return null;
    } catch (e) {
      debugPrint('FILE_SAVE_ERROR: $e');
      return null;
    }
  }
}
