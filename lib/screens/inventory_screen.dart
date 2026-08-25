import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/screens/inventory/product_editor_modal.dart';
import 'package:beleka_pos/screens/inventory/category_management_modal.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/theme_provider.dart';
import 'package:beleka_pos/services/barcode_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

final showArchivedProvider = StateProvider<bool>((ref) => false);
final inventorySearchProvider = StateProvider<String>((ref) => '');
final inventoryCategoryFilterProvider = StateProvider<int?>((ref) => null);
final inventoryBranchFilterProvider = StateProvider<String?>((ref) => null);

final inventoryProductsProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final showArchived = ref.watch(showArchivedProvider);
  final isOwner = ref.watch(isOwnerProvider);
  final currentUser = ref.watch(authProvider);
  final storeConfig = ref.watch(storeConfigProvider).value;
  final activeBranchFilter = ref.watch(inventoryBranchFilterProvider);

  // If Branch Manager/Cashier: strictly isolate to their specific branch bhfId
  final String? effectiveBranchCode;
  if (!isOwner) {
    effectiveBranchCode = (currentUser?.branchCode != null && currentUser!.branchCode!.isNotEmpty && currentUser.branchCode != '00')
        ? currentUser.branchCode!
        : ((storeConfig != null && storeConfig.bhfId.isNotEmpty) ? storeConfig.bhfId : '00');
  } else {
    effectiveBranchCode = activeBranchFilter; // Owner can view all or filter by branch
  }

  return db.watchAllProducts(
    includeArchived: showArchived,
    branchCode: effectiveBranchCode,
  );
});

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _isSyncingDigitax = false;

  @override
  void initState() {
    super.initState();
    // Instant sync: Whenever opening Inventory, immediately sync and pull any changes made on DigiTax catalog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _performInstantDigiTaxSync(silent: true);
    });
  }

  Future<void> _performInstantDigiTaxSync({bool silent = false}) async {
    if (_isSyncingDigitax) return;
    if (!silent) setState(() => _isSyncingDigitax = true);
    try {
      // 1. Ensure latest credentials are fresh from Cloud HQ
      try {
        await ref.read(postgresSyncServiceProvider).pullStoreConfigFromCloud();
      } catch (_) {}

      final currentUser = ref.read(authProvider);
      final storeConfig = ref.read(storeConfigProvider).value;
      final currentBranch = (storeConfig != null && storeConfig.bhfId.isNotEmpty)
          ? storeConfig.bhfId
          : (currentUser?.branchCode ?? '00');
      final syncService = ref.read(digitaxInventoryServiceProvider);

      final result = await syncService.syncAllInventoryWithDigitax(
        branchCode: currentBranch,
      );

      ref.invalidate(inventoryProductsProvider);

      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  result.success ? Icons.cloud_done_rounded : Icons.warning_amber_rounded,
                  color: result.success ? const Color(0xFF10B981) : Colors.orangeAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    result.message,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF16161C),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('DigiTax Sync Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingDigitax = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(inventoryProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final search = ref.watch(inventorySearchProvider);
    final categoryFilter = ref.watch(inventoryCategoryFilterProvider);
    final branchFilter = ref.watch(inventoryBranchFilterProvider);
    final user = ref.watch(authProvider);
    final totalProducts = productsAsync.value ?? [];
    final categories = categoriesAsync.value ?? [];
    
    // Filter products based on search, category, and multi-branch store isolation
    final filteredProducts = totalProducts.where((p) {
      // 1. Multi-Branch Store Isolation
      if (user?.role == 'branch_manager' || user?.role == 'cashier') {
        final assignedBranch = user?.branchCode ?? '00';
        if (p.branchCode != assignedBranch && p.branchCode != '00') {
          return false;
        }
      } else if (branchFilter != null) {
        if (p.branchCode != branchFilter) return false;
      }

      final query = search.toLowerCase();
      final matchesSearch = p.name.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query);
      final matchesCategory = categoryFilter == null || p.categoryId == categoryFilter;
      return matchesSearch && matchesCategory;
    }).toList();
    
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? '\$';

    // Listen for global barcode scans
    ref.listen(barcodeStreamProvider, (previous, next) {
      next.whenData((barcode) {
        _searchController.text = barcode;
        ref.read(inventorySearchProvider.notifier).state = barcode;
      });
    });

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, ref, totalProducts),
          const SizedBox(height: 16),
          _buildFilters(ref),
          const SizedBox(height: 12),
          _buildCategoryFilterBar(ref, totalProducts, categories),
          const SizedBox(height: 14),
          Expanded(
            child: productsAsync.when(
              data: (_) => _buildStockTable(context, ref, filteredProducts, categories, currency),
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D))),
              error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, List<Product> products) {
    final accentColor = ref.watch(accentColorProvider);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              'Inventory',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Text(
                '${products.length} Items',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white60,
                ),
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Export Dropdown
            PopupMenuButton<String>(
              onSelected: (value) {
                final config = ref.read(storeConfigProvider).value;
                switch (value) {
                  case 'csv':
                    ref.read(exportServiceProvider).exportInventoryToCsv(products, config: config);
                    break;
                  case 'excel':
                    ref.read(exportServiceProvider).exportInventoryToExcel(products, config: config);
                    break;
                  case 'pdf':
                    ref.read(exportServiceProvider).exportInventoryToPdf(products, config: config);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                const PopupMenuItem(value: 'excel', child: Text('Export Excel')),
                const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
              ],
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Text(
                      'Export',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Instant DigiTax Sync Button
            OutlinedButton.icon(
              onPressed: _isSyncingDigitax ? null : () => _performInstantDigiTaxSync(silent: false),
              icon: _isSyncingDigitax
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
                    )
                  : const Icon(Icons.sync_rounded, size: 16, color: Color(0xFF10B981)),
              label: Text(
                _isSyncingDigitax ? 'Syncing...' : 'Sync DigiTax',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF10B981)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF10B981), width: 1),
                backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),

            // Manage Categories Button
            OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const CategoryManagementModal(),
              ),
              icon: const Icon(Icons.category_rounded, size: 16),
              label: Text('Categories', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),

            // Quick Add Category Button
            OutlinedButton.icon(
              onPressed: () async {
                final created = await showQuickCreateCategoryDialog(context, ref);
                if (created != null && context.mounted) {
                  ref.read(inventoryCategoryFilterProvider.notifier).state = created.id;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Category "${created.name}" created!'),
                      backgroundColor: const Color(0xFF16161C),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              icon: Icon(Icons.add_circle_outline, size: 16, color: accentColor),
              label: Text('New Category', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: accentColor)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accentColor.withValues(alpha: 0.3)),
                backgroundColor: accentColor.withValues(alpha: 0.05),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 10),

            // Add Product Button
            SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await showDialog<bool>(
                    context: context,
                    builder: (context) => const ProductEditorModal(),
                  );
                  if (result == true) {
                    ref.invalidate(inventoryProductsProvider);
                  }
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text('Add Product', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilters(WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => ref.read(inventorySearchProvider.notifier).state = value,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search products by name, barcode, or SKU...',
                hintStyle: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.25),
                ),
                prefixIcon: Icon(Icons.search, color: Colors.white.withValues(alpha: 0.3), size: 20),
                suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(inventorySearchProvider.notifier).state = '';
                      },
                    )
                  : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _buildArchiveToggle(ref),
      ],
    );
  }

  Widget _buildCategoryFilterBar(WidgetRef ref, List<Product> products, List<Category> categories) {
    final activeFilter = ref.watch(inventoryCategoryFilterProvider);
    final accentColor = ref.watch(accentColorProvider);

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // "ALL PRODUCTS" chip
          _buildCategoryFilterChip(
            label: 'ALL PRODUCTS',
            count: products.length,
            isSelected: activeFilter == null,
            color: accentColor,
            onTap: () => ref.read(inventoryCategoryFilterProvider.notifier).state = null,
          ),
          const SizedBox(width: 8),

          // Chips for each category
          ...categories.map((cat) {
            final count = products.where((p) => p.categoryId == cat.id).length;
            final isSelected = activeFilter == cat.id;
            final color = _getSectorColor(cat.sector);

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildCategoryFilterChip(
                label: cat.name.toUpperCase(),
                count: count,
                isSelected: isSelected,
                color: color,
                onTap: () {
                  if (isSelected) {
                    ref.read(inventoryCategoryFilterProvider.notifier).state = null;
                  } else {
                    ref.read(inventoryCategoryFilterProvider.notifier).state = cat.id;
                  }
                },
              ),
            );
          }),

          // Inline Quick Add Category Button
          InkWell(
            onTap: () async {
              final created = await showQuickCreateCategoryDialog(context, ref);
              if (created != null && context.mounted) {
                ref.read(inventoryCategoryFilterProvider.notifier).state = created.id;
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08), style: BorderStyle.solid),
              ),
              child: Row(
                children: [
                  Icon(Icons.add_rounded, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Text(
                    'NEW CATEGORY',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: accentColor,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip({
    required String label,
    required int count,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? Colors.white : Colors.white60,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? color.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.white38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchiveToggle(WidgetRef ref) {
    final showArchived = ref.watch(showArchivedProvider);
    return InkWell(
      onTap: () => ref.read(showArchivedProvider.notifier).state = !showArchived,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: showArchived ? const Color(0xFFC1F11D).withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: showArchived ? const Color(0xFFC1F11D).withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Icon(
              showArchived ? Icons.archive : Icons.archive_outlined,
              size: 14,
              color: showArchived ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Text(
              'Show Archived',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: showArchived ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockTable(
    BuildContext context, 
    WidgetRef ref, 
    List<Product> products, 
    List<Category> categories, 
    String currency
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          _buildTableHeader(),
          Expanded(
            child: products.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white.withValues(alpha: 0.15)),
                      const SizedBox(height: 12),
                      Text(
                        'No products found in this view',
                        style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _buildStockRow(context, ref, product, categories, currency);
                  },
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          _buildHeaderCell('SKU', flex: 2),
          _buildHeaderCell('Product Name', flex: 3),
          _buildHeaderCell('Category', flex: 2),
          _buildHeaderCell('Stock Level', flex: 2),
          _buildHeaderCell('Selling Price', flex: 2),
          _buildHeaderCell('Status', flex: 2),
          _buildHeaderCell('Actions', flex: 1),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white.withValues(alpha: 0.35),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildStockRow(
    BuildContext context, 
    WidgetRef ref, 
    Product product, 
    List<Category> categories, 
    String currency
  ) {
    final bool isLowStock = product.stockLevel < 10;
    final bool isOutOfStock = product.stockLevel == 0;
    
    String statusLabel = 'IN STOCK';
    Color statusColor = const Color(0xFF4ADE80);
    
    if (product.isArchived) {
      statusLabel = 'ARCHIVED';
      statusColor = Colors.white.withValues(alpha: 0.4);
    } else if (isOutOfStock) {
      statusLabel = 'OUT OF STOCK';
      statusColor = const Color(0xFFF87171);
    } else if (isLowStock) {
      statusLabel = 'LOW STOCK';
      statusColor = const Color(0xFFFACC15);
    }

    // Category allocation lookup
    final matchedCat = categories.where((c) => c.id == product.categoryId).firstOrNull;
    final catName = matchedCat != null ? matchedCat.name.toUpperCase() : 'GENERAL';
    final catColor = matchedCat != null ? _getSectorColor(matchedCat.sector) : Colors.white38;

    return Opacity(
      opacity: product.isArchived ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03))),
        ),
        child: Row(
          children: [
            // SKU
            Expanded(
              flex: 2,
              child: Text(
                product.sku,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),

            // Product Name & Image & Branch Tag
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  _buildProductThumbnail(product.imagePath),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                'BHF-${product.branchCode}',
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              product.isSyncedWithDigitax ? '🟢 DigiTax Synced' : '🟡 Local Stock',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: product.isSyncedWithDigitax ? const Color(0xFF10B981) : Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Allocated Category Badge
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: catColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      catName,
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Stock
            Expanded(
              flex: 2,
              child: Text(
                product.stockLevel.toString().padLeft(3, '0'),
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isOutOfStock ? const Color(0xFFF87171) : (isLowStock ? const Color(0xFFFACC15) : Colors.white),
                ),
              ),
            ),

            // Price
            Expanded(
              flex: 2,
              child: Text(
                '$currency${product.price.toStringAsFixed(2)}',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),

            // Status Badge
            Expanded(
              flex: 2,
              child: UnconstrainedBox(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),

            // Actions
            Expanded(
              flex: 1,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () async {
                      final result = await showDialog<bool>(
                        context: context,
                        builder: (context) => ProductEditorModal(
                          product: product,
                        ),
                      );
                      if (result == true) {
                        ref.invalidate(inventoryProductsProvider);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined, color: Colors.white38, size: 18),
                    tooltip: 'Edit & Allocate Category',
                  ),
                  IconButton(
                    onPressed: () async {
                      final bool isArchiving = !product.isArchived;
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: Container(
                            width: 400,
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E22),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isArchiving ? Icons.warning_amber_rounded : Icons.settings_backup_restore_rounded,
                                  color: isArchiving ? const Color(0xFFFFB3B5) : const Color(0xFFC1F11D),
                                  size: 48,
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  isArchiving ? 'ARCHIVE_PRODUCT' : 'RESTORE_PRODUCT',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  isArchiving
                                      ? 'Are you sure you want to archive ${product.name}? This SKU will be hidden from the catalog.'
                                      : 'Do you want to restore ${product.name} to the active inventory?',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.5),
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 32),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        onPressed: () => Navigator.pop(context, false),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                        ),
                                        child: Text('Cancel',
                                            style: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.5))),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () => Navigator.pop(context, true),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isArchiving ? Colors.red : const Color(0xFFC1F11D),
                                          foregroundColor: isArchiving ? Colors.white : Colors.black,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          elevation: 0,
                                        ),
                                        child: Text(isArchiving ? 'Archive' : 'Restore',
                                            style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      if (confirm == true) {
                        if (isArchiving) {
                          await ref.read(databaseServiceProvider).archiveProduct(product.id);
                        } else {
                          await ref.read(databaseServiceProvider).unarchiveProduct(product.id);
                        }
                        ref.invalidate(inventoryProductsProvider);
                      }
                    },
                    icon: Icon(
                      product.isArchived ? Icons.settings_backup_restore_rounded : Icons.archive_outlined,
                      color: product.isArchived ? const Color(0xFFC1F11D).withValues(alpha: 0.5) : Colors.white24,
                      size: 18,
                    ),
                    tooltip: product.isArchived ? 'Restore Product' : 'Archive Product',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductThumbnail(String? imagePath) {
    final bool hasImage = imagePath != null && File(imagePath).existsSync();
    
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        image: hasImage 
          ? DecorationImage(
              image: FileImage(File(imagePath)),
              fit: BoxFit.cover,
            )
          : null,
      ),
      child: !hasImage 
        ? Center(
            child: Icon(
              Icons.inventory_2_outlined,
              size: 14,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          )
        : null,
    );
  }

  Color _getSectorColor(CategorySector sector) {
    switch (sector) {
      case CategorySector.pharmacy: return const Color(0xFF00D1FF);
      case CategorySector.stationery: return const Color(0xFFB565FF);
      case CategorySector.grocery: return const Color(0xFF00FF85);
      case CategorySector.food: return const Color(0xFFFF5C00);
      case CategorySector.restaurant: return const Color(0xFFF39C12);
      case CategorySector.other: return const Color(0xFFC1F11D);
    }
  }
}
