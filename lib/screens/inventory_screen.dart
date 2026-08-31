import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/utils/formatters.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/screens/inventory/product_editor_modal.dart';
import 'package:beleka_pos/screens/inventory/category_management_modal.dart';
import 'package:beleka_pos/screens/inventory/add_stock_modal.dart';
import 'package:beleka_pos/screens/inventory/stock_movement_history_modal.dart';
import 'package:beleka_pos/screens/inventory/digitax_stock_reconcile_modal.dart';
import 'package:beleka_pos/providers/store_provider.dart';
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

  // If Branch Manager/Cashier: isolate to their specific branch if configured, else show local store inventory
  final String? effectiveBranchCode;
  if (!isOwner) {
    final userBranch = currentUser?.branchCode?.trim();
    if (userBranch != null && userBranch.isNotEmpty && userBranch != '00') {
      effectiveBranchCode = userBranch;
    } else if (storeConfig != null && storeConfig.bhfId.isNotEmpty && storeConfig.bhfId != '00') {
      effectiveBranchCode = storeConfig.bhfId;
    } else {
      effectiveBranchCode = null; // Show all products in local store / HQ
    }
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
      final isOwner = ref.read(isOwnerProvider);
      final storeConfig = ref.read(storeConfigProvider).value;

      final String currentBranch;
      if (isOwner) {
        currentBranch = ref.read(inventoryBranchFilterProvider) ?? '00';
      } else {
        final userBranch = currentUser?.branchCode?.trim();
        if (userBranch != null && userBranch.isNotEmpty && userBranch != '00') {
          currentBranch = userBranch;
        } else if (storeConfig != null && storeConfig.bhfId.isNotEmpty && storeConfig.bhfId != '00') {
          currentBranch = storeConfig.bhfId;
        } else {
          currentBranch = '01';
        }
      }

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
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    
    final productsAsync = ref.watch(inventoryProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final search = ref.watch(inventorySearchProvider);
    final categoryFilter = ref.watch(inventoryCategoryFilterProvider);
    final branchFilter = ref.watch(inventoryBranchFilterProvider);
    final user = ref.watch(authProvider);
    final storeConfig = ref.watch(storeConfigProvider).value;
    final totalProducts = productsAsync.value ?? [];
    final categories = categoriesAsync.value ?? [];
    
    // Filter products based on search, category, and multi-branch store isolation
    final filteredProducts = totalProducts.where((p) {
      if (user?.role == 'branch_manager' || user?.role == 'cashier') {
        final assignedBranch = (user?.branchCode != null && user!.branchCode!.isNotEmpty && user.branchCode != '00')
            ? user.branchCode!
            : (storeConfig?.bhfId.isNotEmpty == true ? storeConfig!.bhfId : '00');
        if (p.branchCode != assignedBranch) {
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

    final double totalValue = totalProducts.fold(0.0, (sum, p) => sum + (p.price * p.stockLevel));
    final int lowStockCount = totalProducts.where((p) => p.stockLevel < 10 && p.stockLevel > 0 && !p.isArchived).length;
    final int outOfStockCount = totalProducts.where((p) => p.stockLevel == 0 && !p.isArchived).length;

    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBreadcrumbBar(context),
          const SizedBox(height: 16),
          _buildHeader(context, ref, totalProducts),
          const SizedBox(height: 16),
          _buildFourStockStatsRow(
            context,
            totalSkus: totalProducts.length,
            totalValue: totalValue,
            lowStockCount: lowStockCount,
            outOfStockCount: outOfStockCount,
            currency: currency,
          ),
          const SizedBox(height: 16),
          _buildFilters(context, ref),
          const SizedBox(height: 12),
          _buildCategoryFilterBar(context, ref, totalProducts, categories),
          const SizedBox(height: 14),
          Expanded(
            child: productsAsync.when(
              data: (_) => _buildStockTable(context, ref, filteredProducts, categories, currency),
              loading: () => Center(child: CircularProgressIndicator(color: primaryColor)),
              error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Color(0xFFDC2626)))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBreadcrumbBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              'Workspace',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Stock & Inventory',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF059669),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'DigiTax Catalog Active',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 13, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('E, MMM d, yyyy').format(DateTime.now()),
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFourStockStatsRow(
    BuildContext context, {
    required int totalSkus,
    required double totalValue,
    required int lowStockCount,
    required int outOfStockCount,
    required String currency,
  }) {
    return Row(
      children: [
        _buildStockMetricCard(
          context,
          label: 'Total Products',
          value: '$totalSkus SKUs',
          growthText: 'Active Catalog',
          isPositive: true,
          icon: Icons.inventory_2_rounded,
          iconBgColor: const Color(0xFFEFF6FF),
          iconColor: const Color(0xFF1D4ED8),
        ),
        const SizedBox(width: 14),
        _buildStockMetricCard(
          context,
          label: 'Stock Valuation',
          value: CurrencyFormatter.format(totalValue, currency),
          growthText: 'Retail Value',
          isPositive: true,
          icon: Icons.monetization_on_rounded,
          iconBgColor: const Color(0xFFECFDF5),
          iconColor: const Color(0xFF059669),
        ),
        const SizedBox(width: 14),
        _buildStockMetricCard(
          context,
          label: 'Low Stock Alert',
          value: '$lowStockCount Items',
          growthText: lowStockCount > 0 ? 'Needs Reorder' : 'Optimal',
          isPositive: lowStockCount == 0,
          icon: Icons.warning_amber_rounded,
          iconBgColor: const Color(0xFFFFFBEB),
          iconColor: const Color(0xFFD97706),
        ),
        const SizedBox(width: 14),
        _buildStockMetricCard(
          context,
          label: 'Out of Stock',
          value: '$outOfStockCount Items',
          growthText: outOfStockCount > 0 ? 'Action Required' : 'All Available',
          isPositive: outOfStockCount == 0,
          icon: Icons.error_outline_rounded,
          iconBgColor: const Color(0xFFFEF2F2),
          iconColor: const Color(0xFFDC2626),
        ),
      ],
    );
  }

  Widget _buildStockMetricCard(
    BuildContext context, {
    required String label,
    required String value,
    required String growthText,
    required bool isPositive,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151F32) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDark ? iconColor.withValues(alpha: 0.15) : iconBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 18, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isPositive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                growthText,
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, List<Product> products) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

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
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Text(
                '${products.length} Items',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
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
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
                  border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Export',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Instant DigiTax Sync Button
            OutlinedButton.icon(
              onPressed: _isSyncingDigitax ? null : () => _performInstantDigiTaxSync(silent: false),
              icon: _isSyncingDigitax
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF059669)),
                    )
                  : const Icon(Icons.sync_rounded, size: 16, color: Color(0xFF059669)),
              label: Text(
                _isSyncingDigitax ? 'Syncing...' : 'Sync DigiTax',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF059669)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF059669), width: 1),
                backgroundColor: const Color(0xFFECFDF5),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 8),

            // DigiTax Stock Reconciliation Button
            OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const DigiTaxStockReconcileModal(),
              ),
              icon: const Icon(Icons.compare_arrows_rounded, size: 16, color: Color(0xFF0284C7)),
              label: Text(
                'Reconcile Stock',
                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF0284C7)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0284C7), width: 1),
                backgroundColor: const Color(0xFFF0F9FF),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 8),

            // Stock Movements Audit History Button
            OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const StockMovementHistoryModal(),
              ),
              icon: Icon(Icons.history_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
              label: Text('Stock Movements', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: theme.colorScheme.onSurface)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), width: 1),
                backgroundColor: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 8),

            // Manage Categories Button
            OutlinedButton.icon(
              onPressed: () => showDialog(
                context: context,
                builder: (context) => const CategoryManagementModal(),
              ),
              icon: Icon(Icons.category_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
              label: Text('Categories', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: theme.colorScheme.onSurface)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                backgroundColor: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(width: 8),

            // Add Product Button
            SizedBox(
              height: 40,
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
                icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                label: Text('Add Product', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFilters(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 40,
            child: TextField(
              controller: _searchController,
              onChanged: (value) => ref.read(inventorySearchProvider.notifier).state = value,
              style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: 'Search products by name, barcode, or SKU...',
                hintStyle: GoogleFonts.inter(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant, size: 18),
                suffixIcon: _searchController.text.isNotEmpty 
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 16, color: theme.colorScheme.onSurfaceVariant),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(inventorySearchProvider.notifier).state = '';
                      },
                    )
                  : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: primaryColor, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _buildArchiveToggle(context, ref),
      ],
    );
  }

  Widget _buildCategoryFilterBar(BuildContext context, WidgetRef ref, List<Product> products, List<Category> categories) {
    final activeFilter = ref.watch(inventoryCategoryFilterProvider);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // "ALL PRODUCTS" chip
          _buildCategoryFilterChip(
            context,
            label: 'ALL PRODUCTS',
            count: products.length,
            isSelected: activeFilter == null,
            color: primaryColor,
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
                context,
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
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip(
    BuildContext context, {
    required String label,
    required int count,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : (isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withValues(alpha: 0.2) : (isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArchiveToggle(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final showArchived = ref.watch(showArchivedProvider);

    return InkWell(
      onTap: () => ref.read(showArchivedProvider.notifier).state = !showArchived,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: showArchived ? primaryColor.withValues(alpha: 0.1) : (isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: showArchived ? primaryColor : (isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            Icon(
              showArchived ? Icons.archive : Icons.archive_outlined,
              size: 14,
              color: showArchived ? primaryColor : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              'Show Archived',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: showArchived ? primaryColor : theme.colorScheme.onSurface,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          _buildTableHeader(context),
          Expanded(
            child: products.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text(
                        'No products found in this view',
                        style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
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

  Widget _buildTableHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          _buildHeaderCell(context, 'SKU', flex: 2),
          _buildHeaderCell(context, 'Product Name', flex: 3),
          _buildHeaderCell(context, 'Category', flex: 2),
          _buildHeaderCell(context, 'Stock Level', flex: 2),
          _buildHeaderCell(context, 'Selling Price', flex: 2),
          _buildHeaderCell(context, 'Status', flex: 2),
          _buildHeaderCell(context, 'Actions', flex: 2),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(BuildContext context, String label, {int flex = 1}) {
    final theme = Theme.of(context);
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
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
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final bool isLowStock = product.stockLevel < 10;
    final bool isOutOfStock = product.stockLevel == 0;
    
    String statusLabel = 'IN STOCK';
    Color statusColor = const Color(0xFF059669);
    
    if (product.isArchived) {
      statusLabel = 'ARCHIVED';
      statusColor = theme.colorScheme.onSurfaceVariant;
    } else if (isOutOfStock) {
      statusLabel = 'OUT OF STOCK';
      statusColor = const Color(0xFFDC2626);
    } else if (isLowStock) {
      statusLabel = 'LOW STOCK';
      statusColor = const Color(0xFFD97706);
    }

    final matchedCat = categories.where((c) => c.id == product.categoryId).firstOrNull;
    final catName = matchedCat != null ? matchedCat.name.toUpperCase() : 'GENERAL';

    return Opacity(
      opacity: product.isArchived ? 0.5 : 1.0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            // SKU
            Expanded(
              flex: 2,
              child: Text(
                product.sku,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),

            // Product Name & Image & Branch Tag
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  _buildProductThumbnail(context, product.imagePath),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'BHF-${product.branchCode}',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              !product.isDigitaxSyncEnabled
                                  ? 'Offline (Exempt)'
                                  : (product.isSyncedWithDigitax ? 'DigiTax Synced' : 'Pending Sync'),
                              style: GoogleFonts.inter(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w600,
                                color: !product.isDigitaxSyncEnabled
                                    ? const Color(0xFF0284C7)
                                    : (product.isSyncedWithDigitax ? const Color(0xFF059669) : const Color(0xFFD97706)),
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
              child: Text(
                catName,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Stock
            Expanded(
              flex: 2,
              child: Text(
                product.stockLevel.toString(),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isOutOfStock ? const Color(0xFFDC2626) : (isLowStock ? const Color(0xFFD97706) : theme.colorScheme.onSurface),
                ),
              ),
            ),

            // Price
            Expanded(
              flex: 2,
              child: Text(
                '$currency${product.price.toStringAsFixed(2)}',
                style: GoogleFonts.inter(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: primaryColor,
                ),
              ),
            ),

            // Status Badge
            Expanded(
              flex: 2,
              child: UnconstrainedBox(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    statusLabel,
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),

            // Actions
            Expanded(
              flex: 2,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () async {
                      final result = await showDialog<bool>(
                        context: context,
                        builder: (context) => StockAdjustmentModal(
                          product: product,
                        ),
                      );
                      if (result == true) {
                        ref.invalidate(inventoryProductsProvider);
                      }
                    },
                    icon: Icon(Icons.tune_rounded, color: primaryColor, size: 18),
                    tooltip: 'Adjust Stock & Record Reason',
                  ),
                  IconButton(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (context) => StockMovementHistoryModal(
                        productId: product.id,
                        productName: product.name,
                      ),
                    ),
                    icon: Icon(Icons.history_rounded, color: theme.colorScheme.onSurfaceVariant, size: 18),
                    tooltip: 'View Stock Movement Audit Log',
                  ),
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
                    icon: Icon(Icons.edit_outlined, color: theme.colorScheme.onSurfaceVariant, size: 18),
                    tooltip: 'Edit Product Details',
                  ),
                  IconButton(
                    onPressed: () async {
                      final bool isArchiving = !product.isArchived;
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(isArchiving ? 'Archive Product' : 'Restore Product', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
                          content: Text(
                            isArchiving
                                ? 'Are you sure you want to archive ${product.name}? This SKU will be hidden from the active catalog.'
                                : 'Do you want to restore ${product.name} to the active catalog?',
                            style: GoogleFonts.inter(fontSize: 13),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('CANCEL'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isArchiving ? const Color(0xFFDC2626) : primaryColor,
                              ),
                              child: Text(isArchiving ? 'ARCHIVE' : 'RESTORE'),
                            ),
                          ],
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
                      color: product.isArchived ? primaryColor : theme.colorScheme.onSurfaceVariant,
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

  Widget _buildProductThumbnail(BuildContext context, String? imagePath) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final bool hasImage = imagePath != null && File(imagePath).existsSync();
    
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
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
                color: primaryColor,
              ),
            )
          : null,
    );
  }

  Color _getSectorColor(CategorySector sector) {
    switch (sector) {
      case CategorySector.pharmacy: return const Color(0xFF0284C7);
      case CategorySector.stationery: return const Color(0xFFD97706);
      case CategorySector.grocery: return const Color(0xFF059669);
      case CategorySector.food: return const Color(0xFFDC2626);
      case CategorySector.restaurant: return const Color(0xFFEA580C);
      case CategorySector.other: return const Color(0xFF1D4ED8);
    }
  }
}
