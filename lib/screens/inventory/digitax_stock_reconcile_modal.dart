import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';

class StockDiscrepancyItem {
  final Product product;
  final int posStock;
  final int digitaxStock;
  final String digitaxItemId;
  final int variance; // posStock - digitaxStock

  StockDiscrepancyItem({
    required this.product,
    required this.posStock,
    required this.digitaxStock,
    required this.digitaxItemId,
    required this.variance,
  });
}

class DigiTaxStockReconcileModal extends ConsumerStatefulWidget {
  const DigiTaxStockReconcileModal({super.key});

  @override
  ConsumerState<DigiTaxStockReconcileModal> createState() => _DigiTaxStockReconcileModalState();
}

class _DigiTaxStockReconcileModalState extends ConsumerState<DigiTaxStockReconcileModal> {
  bool _isLoading = true;
  String? _error;
  List<StockDiscrepancyItem> _allItems = [];
  bool _showDiscrepanciesOnly = true;
  String _searchQuery = '';
  final Set<int> _reconcilingIds = {};

  @override
  void initState() {
    super.initState();
    _loadComparison();
  }

  Future<void> _loadComparison() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final db = ref.read(databaseServiceProvider);
      final digitaxService = ref.read(digitaxInventoryServiceProvider);

      final localProducts = await db.getAllProducts();
      final remoteMap = await digitaxService.fetchRemoteStockMap();

      if (remoteMap.isEmpty) {
        setState(() {
          _error = 'Could not fetch inventory from DigiTax. Please verify internet connectivity and DigiTax API keys in Settings.';
          _isLoading = false;
        });
        return;
      }

      final List<StockDiscrepancyItem> items = [];

      for (final p in localProducts) {
        Map<String, dynamic>? remoteItem;

        if (p.itemClsCd.isNotEmpty && remoteMap.containsKey(p.itemClsCd)) {
          remoteItem = remoteMap[p.itemClsCd];
        } else if (remoteMap.containsKey(p.name.trim().toLowerCase())) {
          remoteItem = remoteMap[p.name.trim().toLowerCase()];
        } else if (p.sku.isNotEmpty && remoteMap.containsKey(p.sku.trim())) {
          remoteItem = remoteMap[p.sku.trim()];
        }

        if (remoteItem != null) {
          final int cloudStock = (remoteItem['stock'] as num?)?.toInt() ?? 0;
          final int posStock = p.stockLevel;
          final int variance = posStock - cloudStock;

          items.add(StockDiscrepancyItem(
            product: p,
            posStock: posStock,
            digitaxStock: cloudStock,
            digitaxItemId: remoteItem['id'] ?? p.itemClsCd,
            variance: variance,
          ));
        }
      }

      setState(() {
        _allItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error loading stock comparison: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _reconcileItem(StockDiscrepancyItem item, bool pushToDigiTax) async {
    setState(() => _reconcilingIds.add(item.product.id));

    try {
      final digitaxService = ref.read(digitaxInventoryServiceProvider);
      final success = await digitaxService.reconcileProductStock(
        product: item.product,
        targetStock: pushToDigiTax ? item.posStock : item.digitaxStock,
        pushToDigiTax: pushToDigiTax,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                pushToDigiTax
                    ? 'Pushed POS stock (${item.posStock}) to DigiTax for "${item.product.name}"'
                    : 'Updated POS stock to ${item.digitaxStock} (matching DigiTax) for "${item.product.name}"',
              ),
              backgroundColor: const Color(0xFF4ADE80),
            ),
          );
        }
        await _loadComparison();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to reconcile with DigiTax. Please check connection.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _reconcilingIds.remove(item.product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final activeGreen = const Color(0xFF4ADE80);

    final filtered = _allItems.where((item) {
      if (_showDiscrepanciesOnly && item.variance == 0) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return item.product.name.toLowerCase().contains(q) || item.product.sku.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    final discrepancyCount = _allItems.where((i) => i.variance != 0).length;
    final matchedCount = _allItems.where((i) => i.variance == 0).length;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 880,
        height: 640,
        decoration: BoxDecoration(
          color: const Color(0xFF16161A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 40,
              spreadRadius: 8,
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: activeGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: activeGreen.withValues(alpha: 0.3)),
                      ),
                      child: Icon(Icons.cloud_sync_rounded, color: activeGreen, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DigiTax Stock Reconciliation',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Compare Local POS Inventory with DigiTax Cloud Ledger',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Refresh from DigiTax',
                      onPressed: _isLoading ? null : _loadComparison,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, color: Colors.white54),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Summary KPI Cards
            Row(
              children: [
                Expanded(
                  child: _buildKpiCard(
                    title: 'DISCREPANCIES',
                    value: '$discrepancyCount Items',
                    subtitle: 'Quantity variance detected',
                    color: discrepancyCount > 0 ? Colors.amber : activeGreen,
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildKpiCard(
                    title: 'PERFECTLY MATCHED',
                    value: '$matchedCount Items',
                    subtitle: 'Identical quantities',
                    color: activeGreen,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildKpiCard(
                    title: 'TOTAL DIGITAX ITEMS',
                    value: '${_allItems.length} Tracked',
                    subtitle: 'Linked in Cloud Catalog',
                    color: const Color(0xFF60A5FA),
                    icon: Icons.cloud_done_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Filter & Search Toolbar
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.search_rounded, color: Colors.white38, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v),
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: 'Search by product name or SKU...',
                              hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: Text('Discrepancies Only ($discrepancyCount)'),
                  selected: _showDiscrepanciesOnly,
                  onSelected: (v) => setState(() => _showDiscrepanciesOnly = v),
                  backgroundColor: Colors.white.withValues(alpha: 0.04),
                  selectedColor: Colors.amber.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: _showDiscrepanciesOnly ? Colors.amber : Colors.white60,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  side: BorderSide(
                    color: _showDiscrepanciesOnly ? Colors.amber.withValues(alpha: 0.5) : Colors.white12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Content Table
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF4ADE80), strokeWidth: 3),
                          SizedBox(height: 16),
                          Text('Fetching live inventory from DigiTax Cloud...', style: TextStyle(color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    )
                  : (_error != null)
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
                                const SizedBox(height: 12),
                                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _loadComparison,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Try Again'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : (filtered.isEmpty)
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline_rounded, color: activeGreen, size: 40),
                                  const SizedBox(height: 12),
                                  Text(
                                    _showDiscrepanciesOnly ? 'All product stock levels perfectly match DigiTax!' : 'No matching products found',
                                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            )
                          : Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.02),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (c, i) => Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
                                  itemBuilder: (context, index) {
                                    final item = filtered[index];
                                    final isReconciling = _reconcilingIds.contains(item.product.id);
                                    final isMatched = item.variance == 0;

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      color: isMatched
                                          ? Colors.transparent
                                          : Colors.amber.withValues(alpha: 0.03),
                                      child: Row(
                                        children: [
                                          // Product Name & SKU
                                          Expanded(
                                            flex: 3,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.product.name,
                                                  style: GoogleFonts.inter(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'SKU: ${item.product.sku} • $currency${item.product.price.toStringAsFixed(2)}',
                                                  style: GoogleFonts.ibmPlexMono(
                                                    color: Colors.white38,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // POS Stock
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('POS Physical Stock', style: TextStyle(color: Colors.white38, fontSize: 10)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${item.posStock} units',
                                                  style: GoogleFonts.ibmPlexMono(
                                                    color: Colors.white,
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // DigiTax Cloud Stock
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('DigiTax Cloud Stock', style: TextStyle(color: Colors.white38, fontSize: 10)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${item.digitaxStock} units',
                                                  style: GoogleFonts.ibmPlexMono(
                                                    color: const Color(0xFF60A5FA),
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          // Variance Pill
                                          Expanded(
                                            flex: 2,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isMatched
                                                      ? activeGreen.withValues(alpha: 0.1)
                                                      : (item.variance > 0
                                                          ? Colors.blue.withValues(alpha: 0.15)
                                                          : Colors.orange.withValues(alpha: 0.15)),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isMatched
                                                        ? activeGreen.withValues(alpha: 0.3)
                                                        : (item.variance > 0 ? Colors.blue.withValues(alpha: 0.4) : Colors.orange.withValues(alpha: 0.4)),
                                                  ),
                                                ),
                                                child: Text(
                                                  isMatched
                                                      ? 'MATCHED'
                                                      : (item.variance > 0 ? '+${item.variance} in POS' : '${item.variance} in POS'),
                                                  style: GoogleFonts.ibmPlexMono(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w700,
                                                    color: isMatched
                                                        ? activeGreen
                                                        : (item.variance > 0 ? const Color(0xFF93C5FD) : Colors.orangeAccent),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),

                                          // Actions
                                          if (isMatched)
                                            const SizedBox(
                                              width: 170,
                                              child: Center(
                                                child: Icon(Icons.check_circle_rounded, color: Color(0xFF4ADE80), size: 18),
                                              ),
                                            )
                                          else
                                            SizedBox(
                                              width: 180,
                                              child: isReconciling
                                                  ? const Center(
                                                      child: SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF4ADE80)),
                                                      ),
                                                    )
                                                  : Row(
                                                      mainAxisAlignment: MainAxisAlignment.end,
                                                      children: [
                                                        // Pull Button (Update POS to Cloud)
                                                        Tooltip(
                                                          message: 'Set POS quantity to ${item.digitaxStock} (Match DigiTax)',
                                                          child: OutlinedButton(
                                                            onPressed: () => _reconcileItem(item, false),
                                                            style: OutlinedButton.styleFrom(
                                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                              visualDensity: VisualDensity.compact,
                                                              side: const BorderSide(color: Colors.white24),
                                                            ),
                                                            child: Text('📥 Pull to POS', style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 6),
                                                        // Push Button (Adjust DigiTax to match POS)
                                                        Tooltip(
                                                          message: 'Adjust DigiTax quantity to ${item.posStock} (Match POS shelf stock)',
                                                          child: ElevatedButton(
                                                            onPressed: () => _reconcileItem(item, true),
                                                            style: ElevatedButton.styleFrom(
                                                              backgroundColor: activeGreen,
                                                              foregroundColor: Colors.black,
                                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                              visualDensity: VisualDensity.compact,
                                                              elevation: 0,
                                                            ),
                                                            child: Text('📤 Push to Cloud', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700)),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
