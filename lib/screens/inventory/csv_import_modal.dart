import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:isar/isar.dart';

import '../../models/models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/store_provider.dart';
import '../../services/csv_stock_service.dart';
import '../../services/database_service.dart';
import '../inventory_screen.dart';

class CsvImportModal extends ConsumerStatefulWidget {
  const CsvImportModal({super.key});

  @override
  ConsumerState<CsvImportModal> createState() => _CsvImportModalState();
}

class _CsvImportModalState extends ConsumerState<CsvImportModal> {
  int _currentStep = 0; // 0: Select File, 1: Column Mapping & Defaults, 2: Preview & Import

  // File data
  String? _fileName;
  List<List<dynamic>> _allRows = [];
  List<String> _headers = [];

  // Mapping & Defaults
  late CsvColumnMapping _mapping;

  // Preview data
  List<CsvPreviewItem> _previewItems = [];
  bool _isLoadingPreview = false;

  // Import execution
  bool _isImporting = false;
  CsvImportResult? _importResult;

  @override
  void initState() {
    super.initState();
    _mapping = CsvColumnMapping();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STEP 1: PICK FILE
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _pickCsvFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      _fileName = file.name;

      String content = '';
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }

      if (content.trim().isEmpty) {
        _showToast('The selected CSV file is empty.', isError: true);
        return;
      }

      final csvService = ref.read(csvStockServiceProvider);
      _allRows = csvService.parseCsvContent(content);

      if (_allRows.isEmpty) {
        _showToast('Could not read any rows from this CSV file.', isError: true);
        return;
      }

      _headers = _allRows.first.map((e) => e.toString().trim()).toList();

      // Find first category id as default
      final categories = ref.read(categoriesProvider).value ?? [];
      final defaultCatId = categories.isNotEmpty ? categories.first.id : 0;

      // Auto-detect mappings from headers
      _mapping = csvService.autoDetectMapping(_headers, defaultCatId);

      setState(() {
        _currentStep = 1;
      });
    } catch (e) {
      _showToast('Error reading CSV: $e', isError: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STEP 2: LOAD PREVIEW
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _generatePreview() async {
    setState(() => _isLoadingPreview = true);
    try {
      final db = ref.read(databaseServiceProvider);
      final existingProducts = await db.isar.products.where().findAll();
      final categories = await db.isar.categorys.where().findAll();
      final csvService = ref.read(csvStockServiceProvider);

      final items = await csvService.generatePreview(
        rows: _allRows,
        mapping: _mapping,
        existingProducts: existingProducts,
        categories: categories,
      );

      setState(() {
        _previewItems = items;
        _isLoadingPreview = false;
        _currentStep = 2;
      });
    } catch (e) {
      setState(() => _isLoadingPreview = false);
      _showToast('Failed to generate preview: $e', isError: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STEP 3: EXECUTE IMPORT
  // ─────────────────────────────────────────────────────────────────────────────
  Future<void> _startImport() async {
    if (_previewItems.isEmpty) return;
    setState(() => _isImporting = true);

    try {
      final csvService = ref.read(csvStockServiceProvider);
      final currentUser = ref.read(authProvider);
      final isOwner = ref.read(isOwnerProvider);
      final storeConfig = ref.read(storeConfigProvider).value;

      final String currentBranch;
      if (isOwner) {
        currentBranch = ref.read(inventoryBranchFilterProvider) ?? '00';
      } else {
        currentBranch = currentUser?.branchCode?.trim() ?? (storeConfig?.bhfId ?? '00');
      }

      final result = await csvService.executeImport(
        items: _previewItems,
        updateExisting: _mapping.updateExisting,
        branchCode: currentBranch,
        branchName: storeConfig?.branchName,
        currentUserId: currentUser?.numericId,
        currentUserName: currentUser?.name,
      );

      setState(() {
        _importResult = result;
        _isImporting = false;
      });

      // Invalidate inventory and categories so UI updates immediately
      ref.invalidate(inventoryProductsProvider);
      ref.invalidate(categoriesProvider);
    } catch (e) {
      setState(() => _isImporting = false);
      _showToast('Import failed: $e', isError: true);
    }
  }

  void _showToast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = const Color(0xFF10B981);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF111827) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 720),
        child: Column(
          children: [
            // Header
            _buildDialogHeader(isDark, primaryColor),

            const Divider(height: 1, color: Color(0xFF1F2937)),

            // Stepper Indicator
            _buildStepper(isDark, primaryColor),

            const Divider(height: 1, color: Color(0xFF1F2937)),

            // Content Body
            Expanded(
              child: _isImporting
                  ? _buildImportingProgress()
                  : _importResult != null
                      ? _buildResultView(isDark, primaryColor)
                      : _buildStepContent(isDark, primaryColor),
            ),

            const Divider(height: 1, color: Color(0xFF1F2937)),

            // Footer Actions
            _buildDialogFooter(isDark, primaryColor),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DIALOG HEADER
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildDialogHeader(bool isDark, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.file_upload_rounded, color: primaryColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Stock Catalog (CSV)',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Upload products from any CSV file with automatic column matching & fallback fill-in-blanks.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded, color: isDark ? Colors.white54 : Colors.black54),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STEPPER HEADER
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStepper(bool isDark, Color primaryColor) {
    final steps = [
      {'title': '1. Select File', 'sub': 'Upload CSV or template'},
      {'title': '2. Column Mapping', 'sub': 'Match & fill in blanks'},
      {'title': '3. Preview & Import', 'sub': 'Verify before adding'},
    ];

    return Container(
      color: isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            return Expanded(
              child: Container(
                height: 2,
                color: (i ~/ 2) < _currentStep
                    ? primaryColor
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
              ),
            );
          }

          final stepIdx = i ~/ 2;
          final isActive = stepIdx == _currentStep;
          final isDone = stepIdx < _currentStep;

          return Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? primaryColor
                      : isActive
                          ? primaryColor.withValues(alpha: 0.18)
                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  border: Border.all(
                    color: isActive || isDone ? primaryColor : Colors.transparent,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text(
                          '${stepIdx + 1}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isActive ? primaryColor : (isDark ? Colors.white54 : Colors.black54),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    steps[stepIdx]['title']!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? (isDark ? Colors.white : Colors.black87)
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                  ),
                ],
              ),
            ],
          );
        }),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STEP CONTENT SWITCHER
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStepContent(bool isDark, Color primaryColor) {
    switch (_currentStep) {
      case 0:
        return _buildStep1SelectFile(isDark, primaryColor);
      case 1:
        return _buildStep2MappingAndDefaults(isDark, primaryColor);
      case 2:
        return _buildStep3Preview(isDark, primaryColor);
      default:
        return const SizedBox();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STEP 1 WIDGET: SELECT FILE OR SAMPLE TEMPLATE
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStep1SelectFile(bool isDark, Color primaryColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          // Drag & Drop / Upload Card
          InkWell(
            onTap: _pickCsvFile,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.4) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.5),
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.cloud_upload_outlined, size: 42, color: primaryColor),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Click to select your CSV Stock file',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Compatible with exports from QuickBooks, Excel, Square, Vend, Shopify, and custom POS systems.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12.5, color: isDark ? Colors.white54 : Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _pickCsvFile,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: Text('Browse Files (.csv)', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // Download Template Banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.download_rounded, color: Color(0xFF0284C7), size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Don\'t have a file ready? Use our Sample Template',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Download a pre-formatted CSV template with example Zambian retail items, SKU codes, and ZRA tax rates.',
                        style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final path = await ref.read(csvStockServiceProvider).downloadSampleTemplate();
                    if (path != null) {
                      _showToast('Sample template saved to $path');
                    }
                  },
                  icon: const Icon(Icons.file_download_outlined, size: 16, color: Color(0xFF0284C7)),
                  label: Text('Download Template', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: const Color(0xFF0284C7))),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF0284C7)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STEP 2 WIDGET: COLUMN MAPPING & FILL-IN-THE-BLANKS DEFAULTS
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStep2MappingAndDefaults(bool isDark, Color primaryColor) {
    final categories = ref.watch(categoriesProvider).value ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File overview badge
          Row(
            children: [
              Icon(Icons.description_outlined, size: 16, color: primaryColor),
              const SizedBox(width: 8),
              Text(
                'File: ${_fileName ?? "CSV"} (${_allRows.length - 1} rows detected, ${_headers.length} columns)',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: primaryColor),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _currentStep = 0),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Change File'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Text(
            'Map Columns & Fill-in Missing Information',
            style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: isDark ? Colors.white : const Color(0xFF0F172A)),
          ),
          const SizedBox(height: 4),
          Text(
            'Since other POS systems use different column names, match them here. Any parts missing in the CSV will automatically use your chosen fill-in defaults.',
            style: GoogleFonts.inter(fontSize: 12.5, color: isDark ? Colors.white54 : Colors.black54),
          ),

          const SizedBox(height: 20),

          // 1. Product Name (Required)
          _buildMappingRow(
            label: 'Product Name',
            isRequired: true,
            hint: 'Identifies the product',
            columnIndex: _mapping.nameIndex,
            onChanged: (val) => setState(() => _mapping.nameIndex = val),
            isDark: isDark,
          ),

          // 2. SKU / Barcode & Auto-generator
          _buildMappingRow(
            label: 'SKU / Barcode',
            isRequired: false,
            hint: 'Unique code or barcode',
            columnIndex: _mapping.skuIndex,
            onChanged: (val) => setState(() => _mapping.skuIndex = val),
            isDark: isDark,
            fallbackWidget: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Auto-generate SKU if blank or missing', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
              subtitle: Text('Generates unique barcodes like BLK-IMP-0001', style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white38 : Colors.black45)),
              value: _mapping.autoGenerateSku,
              activeThumbColor: primaryColor,
              onChanged: (v) => setState(() => _mapping.autoGenerateSku = v),
            ),
          ),

          // 3. Selling Price
          _buildMappingRow(
            label: 'Selling Price (ZMW)',
            isRequired: true,
            hint: 'Customer retail price',
            columnIndex: _mapping.priceIndex,
            onChanged: (val) => setState(() => _mapping.priceIndex = val),
            isDark: isDark,
            fallbackWidget: Row(
              children: [
                Text('Default price if blank: K', style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  height: 32,
                  child: TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      hintText: '0.00',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    style: GoogleFonts.inter(fontSize: 12),
                    onChanged: (v) => _mapping.defaultPrice = double.tryParse(v) ?? 0.0,
                  ),
                ),
              ],
            ),
          ),

          // 4. Cost Price / Unit Cost
          _buildMappingRow(
            label: 'Cost Price (Unit Cost)',
            isRequired: false,
            hint: 'Supplier purchase price',
            columnIndex: _mapping.costIndex,
            onChanged: (val) => setState(() => _mapping.costIndex = val),
            isDark: isDark,
            fallbackWidget: Row(
              children: [
                Text('Default cost if blank: K', style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  height: 32,
                  child: TextField(
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      hintText: '0.00',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    style: GoogleFonts.inter(fontSize: 12),
                    onChanged: (v) => _mapping.defaultCost = double.tryParse(v) ?? 0.0,
                  ),
                ),
              ],
            ),
          ),

          // 5. Stock Level / Quantity
          _buildMappingRow(
            label: 'Stock Quantity',
            isRequired: false,
            hint: 'Current units on shelf',
            columnIndex: _mapping.stockIndex,
            onChanged: (val) => setState(() => _mapping.stockIndex = val),
            isDark: isDark,
            fallbackWidget: Row(
              children: [
                Text('Default stock if blank:', style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 70,
                  height: 32,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      hintText: '0',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    style: GoogleFonts.inter(fontSize: 12),
                    onChanged: (v) => _mapping.defaultStock = int.tryParse(v) ?? 0,
                  ),
                ),
              ],
            ),
          ),

          // 6. Category
          _buildMappingRow(
            label: 'Category',
            isRequired: false,
            hint: 'e.g. Groceries, Bakery, Drinks',
            columnIndex: _mapping.categoryIndex,
            onChanged: (val) => setState(() => _mapping.categoryIndex = val),
            isDark: isDark,
            fallbackWidget: Row(
              children: [
                Text('Fallback Category:', style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('cat_${_mapping.defaultCategoryId}'),
                    initialValue: _mapping.defaultCategoryId > 0 ? _mapping.defaultCategoryId : (categories.isNotEmpty ? categories.first.id : 0),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      isDense: true,
                    ),
                    items: [
                      if (categories.isEmpty)
                        const DropdownMenuItem(value: 0, child: Text('General / Default')),
                      for (final cat in categories)
                        DropdownMenuItem(value: cat.id, child: Text(cat.name, style: GoogleFonts.inter(fontSize: 12))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _mapping.defaultCategoryId = val);
                    },
                  ),
                ),
              ],
            ),
          ),

          // 7. ZRA Tax Classification
          _buildMappingRow(
            label: 'ZRA Tax Code',
            isRequired: false,
            hint: 'A (16%), B (0%), C (Exempt), E (Non-VAT), TOT (3%)',
            columnIndex: _mapping.taxCodeIndex,
            onChanged: (val) => setState(() => _mapping.taxCodeIndex = val),
            isDark: isDark,
            fallbackWidget: Row(
              children: [
                Text('Default Tax Code:', style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _mapping.defaultTaxCode,
                  underline: const SizedBox(),
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: primaryColor),
                  items: const [
                    DropdownMenuItem(value: 'A', child: Text('A — Standard 16%')),
                    DropdownMenuItem(value: 'B', child: Text('B — Zero-Rated 0%')),
                    DropdownMenuItem(value: 'C', child: Text('C — Exempt 0%')),
                    DropdownMenuItem(value: 'E', child: Text('E — Non-VAT / Medical')),
                    DropdownMenuItem(value: 'TOT', child: Text('TOT — Turnover Tax 3%')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() {
                        _mapping.defaultTaxCode = v;
                        _mapping.defaultTaxRate = (v == 'A') ? 16.0 : (v == 'TOT' ? 3.0 : 0.0);
                      });
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Duplicate Behavior Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: primaryColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'If SKU already exists in inventory:',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: isDark ? Colors.white : Colors.black87),
                      ),
                      Text(
                        _mapping.updateExisting
                            ? 'Update existing product\'s stock level, selling price & cost price'
                            : 'Skip existing products and only import new ones',
                        style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _mapping.updateExisting,
                  activeThumbColor: primaryColor,
                  onChanged: (v) => setState(() => _mapping.updateExisting = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMappingRow({
    required String label,
    required bool isRequired,
    required String hint,
    required int columnIndex,
    required ValueChanged<int> onChanged,
    required bool isDark,
    Widget? fallbackWidget,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.2) : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        ),
                        if (isRequired) ...[
                          const SizedBox(width: 4),
                          const Text('*', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        ],
                      ],
                    ),
                    Text(hint, style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white38 : Colors.black45)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('col_${label}_$columnIndex'),
                  initialValue: columnIndex,
                  isDense: true,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: -1,
                      child: Text('— Not in CSV (Use Fill-in Default) —', style: GoogleFonts.inter(fontSize: 12, color: Colors.orangeAccent)),
                    ),
                    for (int i = 0; i < _headers.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text('${i + 1}. ${_headers[i]}', style: GoogleFonts.inter(fontSize: 12)),
                      ),
                  ],
                  onChanged: (val) {
                    if (val != null) onChanged(val);
                  },
                ),
              ),
            ],
          ),
          if (fallbackWidget != null) ...[
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            fallbackWidget,
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // STEP 3 WIDGET: PREVIEW & VERIFICATION TABLE
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildStep3Preview(bool isDark, Color primaryColor) {
    if (_isLoadingPreview) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 16),
            Text('Processing CSV and validating rows...', style: GoogleFonts.inter(fontSize: 14)),
          ],
        ),
      );
    }

    final newCount = _previewItems.where((i) => !i.isDuplicate).length;
    final updateCount = _previewItems.where((i) => i.isDuplicate).length;
    final warningCount = _previewItems.where((i) => i.warnings.isNotEmpty).length;

    return Column(
      children: [
        // Statistics strip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              _buildStatChip(
                icon: Icons.list_alt_rounded,
                label: 'Total: ${_previewItems.length}',
                color: isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                icon: Icons.add_circle_outline,
                label: 'New Items: $newCount',
                color: const Color(0xFF10B981),
              ),
              const SizedBox(width: 12),
              _buildStatChip(
                icon: Icons.sync_rounded,
                label: 'Will Update: $updateCount',
                color: const Color(0xFF0284C7),
              ),
              const SizedBox(width: 12),
              if (warningCount > 0)
                _buildStatChip(
                  icon: Icons.info_outline,
                  label: '$warningCount using defaults',
                  color: Colors.orangeAccent,
                ),
            ],
          ),
        ),

        // Table
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 40,
                dataRowMinHeight: 44,
                dataRowMaxHeight: 52,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Product Name')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(label: Text('Selling Price')),
                  DataColumn(label: Text('Cost')),
                  DataColumn(label: Text('Stock')),
                  DataColumn(label: Text('Category')),
                  DataColumn(label: Text('Tax')),
                ],
                rows: _previewItems.take(50).map((item) {
                  return DataRow(
                    cells: [
                      DataCell(Text('${item.rowIndex}')),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: item.isDuplicate
                                ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                                : const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            item.isDuplicate ? 'Update' : 'New',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: item.isDuplicate ? const Color(0xFF0284C7) : const Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(item.name, style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12.5)),
                            if (item.warnings.isNotEmpty)
                              Text(item.warnings.first, style: GoogleFonts.inter(fontSize: 10, color: Colors.orangeAccent)),
                          ],
                        ),
                      ),
                      DataCell(Text(item.sku, style: GoogleFonts.robotoMono(fontSize: 11.5))),
                      DataCell(Text('K${item.price.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12))),
                      DataCell(Text('K${item.cost.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white60))),
                      DataCell(Text('${item.stock}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                      DataCell(Text(item.categoryName, style: GoogleFonts.inter(fontSize: 12))),
                      DataCell(Text('${item.taxCode} (${item.taxRate.toStringAsFixed(0)}%)', style: GoogleFonts.inter(fontSize: 11.5))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),

        if (_previewItems.length > 50)
          Container(
            padding: const EdgeInsets.all(8),
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            child: Text(
              'Showing first 50 of ${_previewItems.length} rows for review. All ${_previewItems.length} items will be imported.',
              style: GoogleFonts.inter(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
            ),
          ),
      ],
    );
  }

  Widget _buildStatChip({required IconData icon, required String label, required Color color}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // IMPORT PROGRESS VIEW
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildImportingProgress() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF10B981)),
          const SizedBox(height: 20),
          Text(
            'Importing products into your stock...',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Writing items to local database and updating stock movement ledger.',
            style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // RESULT VIEW
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildResultView(bool isDark, Color primaryColor) {
    final res = _importResult!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_rounded, size: 54, color: primaryColor),
            ),
            const SizedBox(height: 20),
            Text(
              'Stock Catalog Imported Successfully!',
              style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Your inventory and stock levels have been updated.',
              style: GoogleFonts.inter(fontSize: 13, color: isDark ? Colors.white54 : Colors.black54),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _buildResultCard('New Products', '${res.insertedCount}', primaryColor, isDark),
                _buildResultCard('Updated Items', '${res.updatedCount}', const Color(0xFF0284C7), isDark),
                _buildResultCard('New Categories', '${res.categoriesCreated}', Colors.purpleAccent, isDark),
                if (res.skippedCount > 0)
                  _buildResultCard('Skipped', '${res.skippedCount}', Colors.orangeAccent, isDark),
              ],
            ),
            if (res.errors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${res.errors.length} rows had errors and were skipped.',
                  style: GoogleFonts.inter(fontSize: 12, color: Colors.redAccent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(String label, String value, Color color, bool isDark) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(value, style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.black54)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DIALOG FOOTER
  // ─────────────────────────────────────────────────────────────────────────────
  Widget _buildDialogFooter(bool isDark, Color primaryColor) {
    if (_importResult != null) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: SizedBox(
          width: 200,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Done & View Inventory', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            OutlinedButton.icon(
              onPressed: () => setState(() => _currentStep--),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back'),
            )
          else
            const SizedBox(),
          Row(
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 12),
              if (_currentStep == 1)
                ElevatedButton.icon(
                  onPressed: _generatePreview,
                  icon: const Icon(Icons.table_view_rounded, size: 16),
                  label: Text('Next: Preview Products', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                )
              else if (_currentStep == 2)
                ElevatedButton.icon(
                  onPressed: _startImport,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: Text('Import ${_previewItems.length} Products', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
