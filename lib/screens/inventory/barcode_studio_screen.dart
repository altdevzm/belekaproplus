import 'dart:typed_data';

import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/screens/inventory_screen.dart';
import 'package:beleka_pos/services/barcode_studio_service.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class BarcodeStudioScreen extends ConsumerStatefulWidget {
  const BarcodeStudioScreen({super.key});

  @override
  ConsumerState<BarcodeStudioScreen> createState() =>
      _BarcodeStudioScreenState();
}

class _BarcodeStudioScreenState extends ConsumerState<BarcodeStudioScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _onlyOpenItems = false;
  A4LabelPreset _selectedPreset = A4LabelPreset.presets.first;
  bool _showPrice = true;
  bool _showStoreName = true;
  bool _showCutGuides = true;
  int _mobileTab = 0; // 0 = Catalog & Queue, 1 = A4 Sheet Preview
  bool _isPrinting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _generateBarcodeForProduct(Product product) async {
    final studio = ref.read(barcodeStudioServiceProvider);
    final db = ref.read(databaseServiceProvider);
    final exclude = ref
        .read(barcodeStudioQueueProvider)
        .map((j) => j.product.sku)
        .toSet();
    final newCode = await studio.generateUniqueEan13(excludeCodes: exclude);

    await db.isar.writeTxn(() async {
      product.sku = newCode;
      await db.isar.products.put(product);
    });

    ref.invalidate(inventoryProductsProvider);
    ref.read(barcodeStudioQueueProvider.notifier).refreshProduct(product);
    final copies = product.stockLevel > 0 ? product.stockLevel.clamp(1, 100) : 10;
    ref
        .read(barcodeStudioQueueProvider.notifier)
        .addOrUpdate(product, copies: copies);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Generated EAN-13 "$newCode" for ${product.name} & queued $copies labels',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<Uint8List> _buildCurrentPdf() async {
    final queue = ref.read(barcodeStudioQueueProvider);
    final config = ref.read(storeConfigProvider).value;
    final studio = ref.read(barcodeStudioServiceProvider);
    return studio.buildA4LabelSheetPdf(
      jobs: queue,
      preset: _selectedPreset,
      currencySymbol: config?.currencySymbol ?? 'K',
      storeName: config?.businessName,
      showPrice: _showPrice,
      showStoreName: _showStoreName,
      showCutGuides: _showCutGuides,
    );
  }

  Future<void> _printA4() async {
    final queue = ref.read(barcodeStudioQueueProvider);
    if (queue.isEmpty) return;
    setState(() => _isPrinting = true);
    try {
      final bytes = await _buildCurrentPdf();
      await ref.read(barcodeStudioServiceProvider).printA4Sheet(
            pdfBytes: bytes,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _shareOrSavePdf() async {
    final queue = ref.read(barcodeStudioQueueProvider);
    if (queue.isEmpty) return;
    setState(() => _isPrinting = true);
    try {
      final bytes = await _buildCurrentPdf();
      await ref.read(barcodeStudioServiceProvider).shareOrSaveA4Pdf(
            pdfBytes: bytes,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = theme.colorScheme.primary;
    final queue = ref.watch(barcodeStudioQueueProvider);
    final totalLabels = queue.fold<int>(0, (sum, j) => sum + j.copies);
    final totalPages = totalLabels == 0
        ? 0
        : (totalLabels / _selectedPreset.labelsPerPage).ceil();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          return Column(
            children: [
              _buildHeader(
                context,
                isDark: isDark,
                accentColor: accentColor,
                totalLabels: totalLabels,
                totalPages: totalPages,
                queueNotEmpty: queue.isNotEmpty,
                isWide: isWide,
              ),
              if (!isWide)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: SegmentedButton<int>(
                    segments: [
                      ButtonSegment(
                        value: 0,
                        icon: const Icon(Icons.qr_code_2_rounded, size: 16),
                        label: Text('Items & Queue (${queue.length})'),
                      ),
                      ButtonSegment(
                        value: 1,
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                        label: Text('A4 Sheet ($totalPages p)'),
                      ),
                    ],
                    selected: {_mobileTab},
                    onSelectionChanged: (s) =>
                        setState(() => _mobileTab = s.first),
                  ),
                ),
              Expanded(
                child: isWide
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              flex: 5,
                              child: _buildCatalogAndQueuePane(
                                isDark: isDark,
                                accentColor: accentColor,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 6,
                              child: _buildPreviewPane(
                                isDark: isDark,
                                accentColor: accentColor,
                                queue: queue,
                                totalLabels: totalLabels,
                                totalPages: totalPages,
                              ),
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: _mobileTab == 0
                            ? _buildCatalogAndQueuePane(
                                isDark: isDark,
                                accentColor: accentColor,
                              )
                            : _buildPreviewPane(
                                isDark: isDark,
                                accentColor: accentColor,
                                queue: queue,
                                totalLabels: totalLabels,
                                totalPages: totalPages,
                              ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required bool isDark,
    required Color accentColor,
    required int totalLabels,
    required int totalPages,
    required bool queueNotEmpty,
    required bool isWide,
  }) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 20 : 14,
        isWide ? 24 : 16,
        14,
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.qr_code_scanner_rounded,
                  color: accentColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Barcode Studio',
                    style: GoogleFonts.manrope(
                      fontSize: isWide ? 22 : 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Generate open-item barcodes & print cut-and-stick A4 sheets',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (totalLabels > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$totalLabels labels • $totalPages A4 ${totalPages == 1 ? "page" : "pages"}',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: (!queueNotEmpty || _isPrinting) ? null : _shareOrSavePdf,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  side: BorderSide(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.16)
                        : Colors.black.withValues(alpha: 0.16),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                label: Text(
                  'Save PDF',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: (!queueNotEmpty || _isPrinting) ? null : _printA4,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: _isPrinting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_rounded, size: 16),
                label: Text(
                  'Print A4 Sheet',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogAndQueuePane({
    required bool isDark,
    required Color accentColor,
  }) {
    final productsAsync = ref.watch(inventoryProductsProvider);
    final queue = ref.watch(barcodeStudioQueueProvider);
    final config = ref.watch(storeConfigProvider).value;
    final currency = config?.currencySymbol ?? 'K';

    return Column(
      children: [
        // Print Queue Card
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16161B) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'A4 PRINT QUEUE (${queue.length} ITEMS)',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (queue.isNotEmpty)
                    TextButton.icon(
                      onPressed: () =>
                          ref.read(barcodeStudioQueueProvider.notifier).clear(),
                      icon: const Icon(Icons.clear_all_rounded, size: 15),
                      label: const Text('Clear'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (queue.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'No labels queued yet. Pick any product below or click "Generate" on an open item to add labels to your A4 sheet.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 190),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: queue.length,
                    separatorBuilder: (_, _) => const Divider(height: 10),
                    itemBuilder: (context, index) {
                      final job = queue[index];
                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  job.product.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${job.product.sku} • $currency${job.product.price.toStringAsFixed(2)}',
                                  style: GoogleFonts.ibmPlexMono(
                                    fontSize: 11,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Decrease copies',
                            icon: const Icon(Icons.remove_circle_outline, size: 18),
                            onPressed: () => ref
                                .read(barcodeStudioQueueProvider.notifier)
                                .updateCopies(job.product.id, job.copies - 1),
                          ),
                          InkWell(
                            onTap: () => _editCopiesDialog(job),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${job.copies}×',
                                style: GoogleFonts.ibmPlexMono(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: accentColor,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Increase copies',
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            onPressed: () => ref
                                .read(barcodeStudioQueueProvider.notifier)
                                .updateCopies(job.product.id, job.copies + 1),
                          ),
                          IconButton(
                            tooltip: 'Remove from sheet',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () => ref
                                .read(barcodeStudioQueueProvider.notifier)
                                .remove(job.product.id),
                          ),
                        ],
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Product Picker + Open Item Barcode Generator
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16161B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08),
              ),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim().toLowerCase()),
                        decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          hintText: 'Search stock items or barcodes...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Open / Non-EAN'),
                      selected: _onlyOpenItems,
                      onSelected: (v) => setState(() => _onlyOpenItems = v),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: productsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
                    data: (products) {
                      final filtered = products.where((p) {
                        if (_onlyOpenItems &&
                            BarcodeStudioService.isValidEan13(p.sku.trim())) {
                          return false;
                        }
                        if (_searchQuery.isEmpty) return true;
                        return p.name.toLowerCase().contains(_searchQuery) ||
                            p.sku.toLowerCase().contains(_searchQuery);
                      }).toList();

                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            _onlyOpenItems
                                ? 'All items already have valid EAN-13 barcodes!'
                                : 'No matching products found.',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 8),
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          final sku = p.sku.trim();
                          final hasEan = BarcodeStudioService.isValidEan13(sku);
                          final isInStore = hasEan && sku.startsWith('299');
                          final queuedJob = queue.cast<BarcodeLabelJob?>().firstWhere(
                                (j) => j?.product.id == p.id,
                                orElse: () => null,
                              );
                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            title: Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (isInStore
                                            ? const Color(0xFF10B981)
                                            : (hasEan
                                                ? const Color(0xFF3B82F6)
                                                : Colors.orangeAccent))
                                        .withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    sku.isEmpty ? 'NO BARCODE' : sku,
                                    style: GoogleFonts.ibmPlexMono(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: isInStore
                                          ? const Color(0xFF10B981)
                                          : (hasEan
                                              ? const Color(0xFF3B82F6)
                                              : Colors.orangeAccent),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Stock: ${p.stockLevel} • $currency${p.price.toStringAsFixed(2)}',
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black54,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!hasEan)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _generateBarcodeForProduct(p),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orangeAccent,
                                        side: BorderSide(
                                          color: Colors.orangeAccent
                                              .withValues(alpha: 0.45),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        minimumSize: Size.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.auto_awesome_rounded,
                                        size: 14,
                                      ),
                                      label: Text(
                                        'Generate',
                                        style: GoogleFonts.manrope(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ElevatedButton.icon(
                                  onPressed: sku.isEmpty
                                      ? () => _generateBarcodeForProduct(p)
                                      : () {
                                          final qty = p.stockLevel > 0
                                              ? p.stockLevel.clamp(1, 50)
                                              : 10;
                                          ref
                                              .read(barcodeStudioQueueProvider
                                                  .notifier)
                                              .addOrUpdate(p, copies: qty);
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: queuedJob != null
                                        ? const Color(0xFF10B981)
                                            .withValues(alpha: 0.16)
                                        : accentColor,
                                    foregroundColor: queuedJob != null
                                        ? const Color(0xFF10B981)
                                        : Colors.black,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    minimumSize: Size.zero,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  icon: Icon(
                                    queuedJob != null
                                        ? Icons.check_rounded
                                        : Icons.add_rounded,
                                    size: 14,
                                  ),
                                  label: Text(
                                    queuedJob != null
                                        ? '${queuedJob.copies}×'
                                        : 'Sheet',
                                    style: GoogleFonts.manrope(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editCopiesDialog(BarcodeLabelJob job) async {
    final ctrl = TextEditingController(text: job.copies.toString());
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Label Copies: ${job.product.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Number of labels (1 - 500)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim())),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (res != null && res > 0) {
      ref
          .read(barcodeStudioQueueProvider.notifier)
          .updateCopies(job.product.id, res);
    }
  }

  Widget _buildPreviewPane({
    required bool isDark,
    required Color accentColor,
    required List<BarcodeLabelJob> queue,
    required int totalLabels,
    required int totalPages,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16161B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sheet Layout Controls
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<A4LabelPreset>(
                value: _selectedPreset,
                items: A4LabelPreset.presets
                    .map(
                      (p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          '${p.label} — ${p.subtitle}',
                          style: GoogleFonts.inter(fontSize: 12),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedPreset = v);
                },
              ),
              FilterChip(
                label: const Text('Price'),
                selected: _showPrice,
                onSelected: (v) => setState(() => _showPrice = v),
              ),
              FilterChip(
                label: const Text('Store Name'),
                selected: _showStoreName,
                onSelected: (v) => setState(() => _showStoreName = v),
              ),
              FilterChip(
                label: const Text('Cut Guides'),
                selected: _showCutGuides,
                onSelected: (v) => setState(() => _showCutGuides = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: PdfPreview(
                key: ValueKey(
                  '${_selectedPreset.id}-$_showPrice-$_showStoreName-$_showCutGuides-${queue.map((e) => '${e.product.id}:${e.product.sku}:${e.copies}').join(',')}',
                ),
                build: (_) => _buildCurrentPdf(),
                initialPageFormat: PdfPageFormat.a4,
                allowSharing: false,
                allowPrinting: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                useActions: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
