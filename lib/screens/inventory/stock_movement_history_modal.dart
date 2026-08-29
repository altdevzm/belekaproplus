import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/theme_provider.dart';

final stockMovementFilterReasonProvider = StateProvider<String?>((ref) => null);
final stockMovementSearchProvider = StateProvider<String>((ref) => '');

class StockMovementHistoryModal extends ConsumerStatefulWidget {
  final int? productId;
  final String? productName;

  const StockMovementHistoryModal({
    super.key,
    this.productId,
    this.productName,
  });

  @override
  ConsumerState<StockMovementHistoryModal> createState() => _StockMovementHistoryModalState();
}

class _StockMovementHistoryModalState extends ConsumerState<StockMovementHistoryModal> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseServiceProvider);
    final accentColor = ref.watch(accentColorProvider);
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final filterReason = ref.watch(stockMovementFilterReasonProvider);
    final search = ref.watch(stockMovementSearchProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 900,
        height: 700,
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 50,
              spreadRadius: 10,
            ),
          ],
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                      ),
                      child: Icon(Icons.history_rounded, color: accentColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.productName != null
                              ? 'STOCK ADJUSTMENT AUDIT: ${widget.productName!.toUpperCase()}'
                              : 'INVENTORY STOCK MOVEMENTS & AUDIT LOG',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Full ZRA Smart Invoice SAR Traceability (Additions, Write-Offs & Recounts)',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.4)),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filter Bar
            Row(
              children: [
                // Search Field
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => ref.read(stockMovementSearchProvider.notifier).state = v,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search by product name, SKU, reason, or operator...',
                        hintStyle: GoogleFonts.inter(color: Colors.white24, fontSize: 12),
                        prefixIcon: Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Reason Filter Dropdown
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: filterReason,
                      dropdownColor: const Color(0xFF1A1A20),
                      icon: const Icon(Icons.filter_list_rounded, color: Colors.white38, size: 18),
                      hint: Text('All Reasons', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('All Reasons', style: GoogleFonts.inter(color: Colors.white, fontSize: 12)),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'ADD',
                          child: Text('➕ All Stock In (Additions)', style: GoogleFonts.inter(color: const Color(0xFF10B981), fontSize: 12)),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'DEDUCT',
                          child: Text('➖ All Stock Out (Write-offs)', style: GoogleFonts.inter(color: const Color(0xFFEF4444), fontSize: 12)),
                        ),
                        DropdownMenuItem<String?>(
                          value: 'RECOUNT',
                          child: Text('🔄 Physical Recounts', style: GoogleFonts.inter(color: const Color(0xFF3B82F6), fontSize: 12)),
                        ),
                      ],
                      onChanged: (val) => ref.read(stockMovementFilterReasonProvider.notifier).state = val,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Print & Export Action Menu
                PopupMenuButton<String>(
                  tooltip: 'Print & Export Stock Report',
                  offset: const Offset(0, 48),
                  color: const Color(0xFF1E1E24),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  onSelected: (val) async {
                    final exportService = ref.read(exportServiceProvider);
                    final config = ref.read(storeConfigProvider).value;
                    final allItems = await db.getStockMovements(productId: widget.productId);
                    
                    final currentFiltered = allItems.where((m) {
                      if (filterReason != null && m.actionType != filterReason) return false;
                      if (search.trim().isNotEmpty) {
                        final q = search.trim().toLowerCase();
                        return m.productName.toLowerCase().contains(q) ||
                            m.sku.toLowerCase().contains(q) ||
                            m.reasonCategory.toLowerCase().contains(q) ||
                            (m.reasonNotes?.toLowerCase().contains(q) ?? false) ||
                            (m.userName?.toLowerCase().contains(q) ?? false);
                      }
                      return true;
                    }).toList();

                    if (currentFiltered.isEmpty && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No stock movement records to export.')),
                      );
                      return;
                    }

                    if (val == 'print') {
                      await exportService.exportStockMovementsToPdf(
                        currentFiltered,
                        config: config,
                        reasonFilter: filterReason,
                        printDirectly: true,
                      );
                    } else if (val == 'pdf') {
                      await exportService.exportStockMovementsToPdf(
                        currentFiltered,
                        config: config,
                        reasonFilter: filterReason,
                        printDirectly: false,
                      );
                    } else if (val == 'excel') {
                      await exportService.exportStockMovementsToExcel(currentFiltered, config: config);
                    } else if (val == 'csv') {
                      await exportService.exportStockMovementsToCsv(currentFiltered, config: config);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'print',
                      child: Row(
                        children: [
                          const Icon(Icons.print_rounded, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 10),
                          Text('🖨️ Print SAR Report', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'pdf',
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 18),
                          const SizedBox(width: 10),
                          Text('📄 Export PDF Document', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'excel',
                      child: Row(
                        children: [
                          const Icon(Icons.table_chart_rounded, color: Colors.greenAccent, size: 18),
                          const SizedBox(width: 10),
                          Text('📊 Export Excel (.xlsx)', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'csv',
                      child: Row(
                        children: [
                          const Icon(Icons.text_snippet_rounded, color: Colors.amberAccent, size: 18),
                          const SizedBox(width: 10),
                          Text('📝 Export CSV (.csv)', style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    height: 42,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.print_rounded, size: 16, color: accentColor),
                        const SizedBox(width: 8),
                        Text(
                          'Print / Export',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: accentColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Live Stream Table
            Expanded(
              child: StreamBuilder<List<StockMovement>>(
                stream: db.watchStockMovements(productId: widget.productId),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final allMovements = snapshot.data ?? [];
                  
                  // Filter by search & action
                  final movements = allMovements.where((m) {
                    if (filterReason != null && m.actionType != filterReason) {
                      return false;
                    }
                    if (search.trim().isNotEmpty) {
                      final q = search.trim().toLowerCase();
                      final match = m.productName.toLowerCase().contains(q) ||
                          m.sku.toLowerCase().contains(q) ||
                          m.reasonCategory.toLowerCase().contains(q) ||
                          (m.reasonNotes?.toLowerCase().contains(q) ?? false) ||
                          (m.userName?.toLowerCase().contains(q) ?? false);
                      if (!match) return false;
                    }
                    return true;
                  }).toList();

                  if (movements.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                          const SizedBox(height: 12),
                          Text(
                            'No stock movement audit records found.',
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF18181C),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                    ),
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
                          ),
                          child: Row(
                            children: [
                              _buildHeaderCell('Date & Time', flex: 2),
                              _buildHeaderCell('Product & SKU', flex: 3),
                              _buildHeaderCell('Action & Delta', flex: 2),
                              _buildHeaderCell('Reason & ZRA Code', flex: 3),
                              _buildHeaderCell('Balance', flex: 2),
                              _buildHeaderCell('Operator', flex: 2),
                              _buildHeaderCell('DigiTax Sync', flex: 2),
                            ],
                          ),
                        ),

                        // Table List
                        Expanded(
                          child: ListView.separated(
                            itemCount: movements.length,
                            separatorBuilder: (_, _) => Divider(color: Colors.white.withValues(alpha: 0.03), height: 1),
                            itemBuilder: (context, index) {
                              final m = movements[index];
                              final isAdd = m.actionType == 'ADD';
                              final deltaColor = isAdd ? const Color(0xFF10B981) : const Color(0xFFEF4444);
                              final deltaSign = isAdd ? '+' : '-';
                              final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Row(
                                  children: [
                                    // Timestamp
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        dateFormat.format(m.timestamp),
                                        style: GoogleFonts.ibmPlexMono(fontSize: 11, color: Colors.white70),
                                      ),
                                    ),

                                    // Product & SKU
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.productName,
                                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'SKU: ${m.sku}',
                                            style: GoogleFonts.ibmPlexMono(fontSize: 10, color: Colors.white38),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Action & Delta
                                    Expanded(
                                      flex: 2,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: deltaColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: deltaColor.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              '$deltaSign${m.quantityChanged}',
                                              style: GoogleFonts.ibmPlexMono(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: deltaColor,
                                              ),
                                            ),
                                          ),
                                          if (m.totalCostImpact > 0) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              '$currency${m.totalCostImpact.toStringAsFixed(2)}',
                                              style: GoogleFonts.ibmPlexMono(fontSize: 9, color: Colors.white38),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    // Reason & ZRA Code
                                    Expanded(
                                      flex: 3,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                                decoration: BoxDecoration(
                                                  color: Colors.white.withValues(alpha: 0.08),
                                                  borderRadius: BorderRadius.circular(3),
                                                ),
                                                child: Text(
                                                  'ZRA ${m.movementType}',
                                                  style: GoogleFonts.ibmPlexMono(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white60),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  m.reasonCategory,
                                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (m.reasonNotes != null && m.reasonNotes!.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              m.reasonNotes!,
                                              style: GoogleFonts.inter(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.white38),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    // Balance (Old -> New)
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${m.previousStock} ➔ ${m.newStock}',
                                        style: GoogleFonts.ibmPlexMono(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70),
                                      ),
                                    ),

                                    // Operator
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        m.userName ?? 'System',
                                        style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // DigiTax Sync
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Icon(
                                            m.isSyncedWithDigitax ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                                            size: 14,
                                            color: m.isSyncedWithDigitax ? const Color(0xFF10B981) : Colors.amber,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            m.isSyncedWithDigitax ? 'Synced' : 'Local Queue',
                                            style: GoogleFonts.inter(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: m.isSyncedWithDigitax ? const Color(0xFF10B981) : Colors.amber,
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
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Colors.white38,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
