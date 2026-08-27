import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/cart_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/barcode_service.dart';
import 'package:beleka_pos/services/sync_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/utils/formatters.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

final productsProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final isOwner = ref.watch(isOwnerProvider);
  final currentUser = ref.watch(authProvider);
  final storeConfig = ref.watch(storeConfigProvider).value;

  final String? effectiveBranchCode;
  if (!isOwner) {
    final userBranch = currentUser?.branchCode?.trim();
    if (userBranch != null && userBranch.isNotEmpty && userBranch != '00') {
      effectiveBranchCode = userBranch;
    } else if (storeConfig != null && storeConfig.bhfId.isNotEmpty && storeConfig.bhfId != '00') {
      effectiveBranchCode = storeConfig.bhfId;
    } else {
      effectiveBranchCode = null; // In Headquarters or default store, show all local inventory!
    }
  } else {
    effectiveBranchCode = null; // Owner/HQ can sell all or default branch products
  }

  return db.watchAllProducts(branchCode: effectiveBranchCode);
});

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  
  int? _selectedCategoryId; // null means "ALL"
  bool _isGridView = true; // true = Grid, false = List
  
  bool _isProcessingPayment = false;
  bool _isCheckoutActive = false;
  double _tenderedAmount = 0.0;
  String _selectedPaymentMethod = '';

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isManager = ref.read(isManagerProvider);
      if (isManager) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access Denied: Managers cannot process sales.'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pushReplacementNamed('/dashboard');
      }
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<Product> _getFilteredProducts(List<Product> allProducts) {
    final query = _searchController.text.trim().toLowerCase();
    final user = ref.watch(authProvider);
    final config = ref.watch(storeConfigProvider).value;
    final activeBranch = user?.branchCode?.trim() ?? config?.bhfId.trim() ?? '00';

    return allProducts.where((p) {
      if (p.isArchived) return false;
      
      // Multi-Branch Inventory Isolation:
      if (user?.role == 'cashier' || user?.role == 'branch_manager') {
        if (activeBranch.isNotEmpty && activeBranch != '00') {
          // In a sub-branch: can sell sub-branch stock, HQ master stock ('00'), or unassigned stock ('')
          if (p.branchCode != activeBranch && p.branchCode != '00' && p.branchCode.isNotEmpty) {
            return false;
          }
        }
      }
      
      final matchesCategory = _selectedCategoryId == null || p.categoryId == _selectedCategoryId;
      if (!matchesCategory) return false;

      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) || p.sku.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _handleProductSelection(Product product) async {
    final cartNotifier = ref.read(cartProvider.notifier);
    final success = cartNotifier.addProduct(product, quantity: 1);

    if (mounted) {
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot add item: ${product.name} is currently out of stock'),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        HapticFeedback.lightImpact();
      }
    }
  }

  Future<void> _lookupProduct(String sku) async {
    final db = ref.read(databaseServiceProvider);
    final product = await db.getProductBySku(sku);
    if (product != null) {
      _handleProductSelection(product);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final cartState = ref.watch(cartProvider);
    final cartNotifier = ref.watch(cartProvider.notifier);
    final config = ref.watch(storeConfigProvider).value;
    final currency = config?.currencySymbol ?? 'ZK';

    ref.listen(barcodeStreamProvider, (previous, next) {
      next.whenData((barcode) => _lookupProduct(barcode));
    });

    final allProducts = productsAsync.value ?? [];
    final allCategories = categoriesAsync.value ?? [];
    final filteredProducts = _getFilteredProducts(allProducts);

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // PANEL 1: Product Catalog & Touch Selection (Left)
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Header with View Mode Switcher
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildPanelHeader(
                        Icons.grid_view_rounded,
                        'PRODUCT CATALOG',
                        const Color(0xFFC1F11D),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Cash Drawer Quick Kick Button
                          Tooltip(
                            message: 'Open Cash Drawer',
                            child: InkWell(
                              onTap: () async {
                                final config = ref.read(storeConfigProvider).value;
                                final ok = await ref.read(printerServiceProvider).openCashDrawer(config: config);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          Icon(
                                            ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                                            color: ok ? const Color(0xFFC1F11D) : Colors.orangeAccent,
                                            size: 18,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(ok ? '✓ Cash drawer opened' : '⚠️ Kick command sent (check printer connection)'),
                                        ],
                                      ),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: const Color(0xFF1E1E24),
                                    ),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                height: 34,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.point_of_sale_rounded, size: 16, color: Color(0xFFC1F11D)),
                                    SizedBox(width: 6),
                                    Text(
                                      'DRAWER',
                                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Grid / List View Toggle
                          Container(
                            height: 34,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildViewModeBtn(
                                  icon: Icons.grid_view_rounded,
                                  tooltip: 'Grid View',
                                  isSelected: _isGridView,
                                  onTap: () => setState(() => _isGridView = true),
                                ),
                                _buildViewModeBtn(
                                  icon: Icons.view_list_rounded,
                                  tooltip: 'List View',
                                  isSelected: !_isGridView,
                                  onTap: () => setState(() => _isGridView = false),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Search Bar with Instant Filter & Clear
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (filteredProducts.length == 1) {
                        _handleProductSelection(filteredProducts.first);
                        _searchController.clear();
                        setState(() {});
                      }
                    },
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    decoration: _searchInputDecoration(),
                  ),
                  const SizedBox(height: 12),

                  // Category Filter Ribbon Chips (No stock counts, cleanly aligned)
                  _buildCategoryRibbon(allCategories),
                  const SizedBox(height: 14),

                  // Products Display Area
                  Expanded(
                    child: productsAsync.when(
                      data: (_) {
                        if (filteredProducts.isEmpty) {
                          return _buildEmptyCatalogState();
                        }
                        if (_isGridView) {
                          return _buildProductsGrid(filteredProducts, currency);
                        } else {
                          return _buildProductsList(filteredProducts, currency);
                        }
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(color: Color(0xFFC1F11D)),
                      ),
                      error: (err, _) => Center(
                        child: Text('Error loading products: $err', style: const TextStyle(color: Colors.redAccent)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // PANEL 2: Quick Tender (Middle)
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(20),
              color: const Color(0xFF141418),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isCheckoutActive) ...[
                    _buildPanelHeader(Icons.payments_rounded, 'QUICK TENDER', const Color(0xFFC1F11D)),
                    const SizedBox(height: 28),
                    Expanded(
                      child: Center(
                        child: cartState.items.isEmpty 
                          ? _buildEmptyState('No active transaction', icon: Icons.shopping_basket_outlined)
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'TOTAL DUE', 
                                  style: GoogleFonts.manrope(
                                    fontSize: 12,
                                    letterSpacing: 2,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white30,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  CurrencyFormatter.format(cartNotifier.total, currency), 
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 36),
                                _buildMainPayButton(cartNotifier, currency),
                              ],
                            ),
                      ),
                    ),
                  ] else ...[
                    // Payment Selector always at top during checkout
                    _buildPaymentMethodSelector(),
                    const SizedBox(height: 20),
                    
                    if (_selectedPaymentMethod.isNotEmpty) ...[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedPaymentMethod == 'CASH')
                              Expanded(
                                child: Column(
                                  children: [
                                    _buildTenderDisplay(currency),
                                    const SizedBox(height: 16),
                                    // Custom Numeric Keypad for exact tender
                                    Expanded(
                                      child: Row(
                                        children: [
                                          // Note Shortcuts
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              children: [
                                                Expanded(child: _buildQuickTenderButton(20, currency)),
                                                const SizedBox(height: 8),
                                                Expanded(child: _buildQuickTenderButton(50, currency)),
                                                const SizedBox(height: 8),
                                                Expanded(child: _buildQuickTenderButton(100, currency)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              children: [
                                                Expanded(child: _buildQuickTenderButton(200, currency)),
                                                const SizedBox(height: 8),
                                                Expanded(child: _buildQuickTenderButton(500, currency)),
                                                const SizedBox(height: 8),
                                                Expanded(child: _buildExactAmountBtn(cartNotifier, currency)),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          // Numeric Keypad
                                          Expanded(
                                            flex: 3,
                                            child: _buildNumericKeypad(),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              _buildDigitalPaymentPrompt(currency),
                          ],
                        ),
                      ),
                    ] else ...[
                       Expanded(child: _buildEmptyState('Select Payment Method', icon: Icons.payments_outlined)),
                    ],
                    
                    const SizedBox(height: 16),
                    _buildCheckoutActions(cartNotifier),
                  ],
                ],
              ),
            ),
          ),

          // PANEL 3: Order Review (Right)
          Expanded(
            flex: 4,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A0C),
                border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('ORDER REVIEW', style: _headerTextStyle()),
                              if (cartState.items.isNotEmpty)
                                Text(
                                  '${cartState.items.fold<int>(0, (sum, item) => sum + item.quantity)} items',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFC1F11D)),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: cartState.items.isEmpty
                              ? _buildEmptyState('Cart is empty', icon: Icons.shopping_cart_outlined)
                              : ListView.builder(
                                  itemCount: cartState.items.length,
                                  itemBuilder: (context, index) => _buildCartRow(cartState.items[index], cartNotifier, currency),
                                ),
                        ),
                      ],
                    ),
                  ),
                  _buildOrderSummary(cartState, cartNotifier, currency),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- Clean Category Filter Ribbon (Aligned without stock numbers) ---

  Widget _buildCategoryRibbon(List<Category> categories) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // ALL Category Chip
          _buildCategoryChip(
            label: 'ALL ITEMS',
            isSelected: _selectedCategoryId == null,
            onTap: () => setState(() => _selectedCategoryId = null),
          ),
          const SizedBox(width: 8),
          ...categories.map((cat) {
            final isSelected = _selectedCategoryId == cat.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildCategoryChip(
                label: cat.name.toUpperCase(),
                isSelected: isSelected,
                onTap: () => setState(() => _selectedCategoryId = cat.id),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.06),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
            color: isSelected ? Colors.black : Colors.white70,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  // --- Products Grid View (Aligned & Clean without stock counts) ---

  Widget _buildProductsGrid(List<Product> products, String currency) {
    return GridView.builder(
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final product = products[index];
        return _buildProductCard(product, currency);
      },
    );
  }

  Widget _buildProductCard(Product product, String currency) {
    final isOutOfStock = product.stockLevel <= 0;
    
    final hasDiscount = product.discountPrice != null && 
        product.discountStartDate != null && 
        product.discountEndDate != null &&
        DateTime.now().isAfter(product.discountStartDate!) && 
        DateTime.now().isBefore(product.discountEndDate!);

    return Material(
      color: Colors.white.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _handleProductSelection(product),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isOutOfStock 
                  ? Colors.redAccent.withValues(alpha: 0.25) 
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Product Icon/Image & Out of Stock / Promo Tag
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: (product.imagePath != null && File(product.imagePath!).existsSync())
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(product.imagePath!), fit: BoxFit.cover),
                          )
                        : const Icon(Icons.inventory_2_outlined, color: Color(0xFFC1F11D), size: 19),
                  ),
                  if (isOutOfStock)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'OUT OF STOCK',
                        style: GoogleFonts.manrope(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.redAccent,
                          letterSpacing: 0.3,
                        ),
                      ),
                    )
                  else if (hasDiscount)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'PROMO',
                        style: GoogleFonts.manrope(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFC1F11D),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                ],
              ),

              // Middle: Product Name & SKU
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isOutOfStock ? Colors.white54 : Colors.white,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '#${product.sku}',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 9.5,
                        color: Colors.white30,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Bottom Row: Price & Instant Add Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasDiscount) ...[
                        Text(
                          CurrencyFormatter.format(product.price, currency),
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: Colors.white30,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(product.discountPrice!, currency),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFC1F11D),
                          ),
                        ),
                      ] else ...[
                        Text(
                          CurrencyFormatter.format(product.price, currency),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFC1F11D),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isOutOfStock ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFC1F11D).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOutOfStock ? Icons.block_rounded : Icons.add, 
                      color: isOutOfStock ? Colors.white24 : const Color(0xFFC1F11D), 
                      size: 16,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Products List View (Aligned & Clean without stock counts) ---

  Widget _buildProductsList(List<Product> products, String currency) {
    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final product = products[index];
        final isOutOfStock = product.stockLevel <= 0;
        
        final hasDiscount = product.discountPrice != null && 
            product.discountStartDate != null && 
            product.discountEndDate != null &&
            DateTime.now().isAfter(product.discountStartDate!) && 
            DateTime.now().isBefore(product.discountEndDate!);

        return Material(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => _handleProductSelection(product),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOutOfStock 
                      ? Colors.redAccent.withValues(alpha: 0.2) 
                      : Colors.white.withValues(alpha: 0.04),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: (product.imagePath != null && File(product.imagePath!).existsSync())
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(product.imagePath!), fit: BoxFit.cover),
                          )
                        : const Icon(Icons.inventory_2_outlined, color: Color(0xFFC1F11D), size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: GoogleFonts.manrope(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: isOutOfStock ? Colors.white54 : Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '#${product.sku}',
                              style: GoogleFonts.ibmPlexMono(fontSize: 9.5, color: Colors.white30),
                            ),
                            if (isOutOfStock) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• Out of Stock',
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ] else if (hasDiscount) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• On Promo',
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFC1F11D),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (hasDiscount) ...[
                        Text(
                          CurrencyFormatter.format(product.price, currency),
                          style: const TextStyle(fontSize: 9, color: Colors.white30, decoration: TextDecoration.lineThrough),
                        ),
                        Text(
                          CurrencyFormatter.format(product.discountPrice!, currency),
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D)),
                        ),
                      ] else ...[
                        Text(
                          CurrencyFormatter.format(product.price, currency),
                          style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isOutOfStock ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFC1F11D).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOutOfStock ? Icons.block_rounded : Icons.add, 
                      color: isOutOfStock ? Colors.white24 : const Color(0xFFC1F11D), 
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyCatalogState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 12),
          Text(
            'No matching products found',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white60),
          ),
          const SizedBox(height: 8),
          if (_searchController.text.isNotEmpty || _selectedCategoryId != null)
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() => _selectedCategoryId = null);
              },
              icon: const Icon(Icons.clear_all_rounded, size: 16, color: Color(0xFFC1F11D)),
              label: const Text('Clear Filters', style: TextStyle(color: Color(0xFFC1F11D), fontSize: 12)),
            ),
        ],
      ),
    );
  }

  Widget _buildViewModeBtn({
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFC1F11D) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.black : Colors.white38,
          ),
        ),
      ),
    );
  }

  // --- Payment & Tender Widgets ---

  Widget _buildMainPayButton(CartNotifier cartNotifier, String currency) {
    return Material(
      color: const Color(0xFFC1F11D),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => setState(() => _isCheckoutActive = true),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: 300,
          height: 84,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.payments_rounded, color: Colors.black, size: 28),
              const SizedBox(width: 14),
              Text(
                'PAY NOW',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckoutActions(CartNotifier cartNotifier) {
    return Row(
      children: [
        if (_selectedPaymentMethod.isNotEmpty)
          Expanded(child: _buildCompleteSaleButton(cartNotifier))
        else
          const Spacer(),
        const SizedBox(width: 12),
        if (_selectedPaymentMethod.isNotEmpty)
          _buildActionIconButton(Icons.arrow_back_rounded, 'Change Method', 
                                 () => setState(() => _selectedPaymentMethod = '')),
        const SizedBox(width: 10),
        _buildActionIconButton(Icons.close_rounded, 'Cancel Checkout', () => setState(() {
          _isCheckoutActive = false;
          _selectedPaymentMethod = '';
        })),
      ],
    );
  }

  Widget _buildActionIconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white38, size: 20),
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildPanelHeader(IconData icon, String title, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 10),
        Text(title, style: _headerTextStyle()),
      ],
    );
  }

  TextStyle _headerTextStyle() {
    return GoogleFonts.plusJakartaSans(
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.5,
      color: Colors.white.withValues(alpha: 0.5),
    );
  }

  InputDecoration _searchInputDecoration() {
    return InputDecoration(
      hintText: 'Search product name or SKU...',
      hintStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.2)),
      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
      suffixIcon: _searchController.text.isNotEmpty
          ? IconButton(
              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
            )
          : null,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.03),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      border: _searchBorder(Colors.white.withValues(alpha: 0.1)),
      enabledBorder: _searchBorder(Colors.white.withValues(alpha: 0.05)),
      focusedBorder: _searchBorder(const Color(0xFFC1F11D), width: 1.5),
    );
  }

  OutlineInputBorder _searchBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: width));
  }

  Widget _buildEmptyState(String message, {IconData icon = Icons.search_off_rounded}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(opacity: 0.1, child: Icon(icon, size: 54, color: Colors.white)),
          const SizedBox(height: 8),
          Opacity(opacity: 0.35, child: Text(message, style: GoogleFonts.inter(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSelector() {
    return Row(
      children: [
        _buildCompactMethodBtn('CASH', Icons.payments_rounded, const Color(0xFFC1F11D)),
        const SizedBox(width: 10),
        _buildCompactMethodBtn('MOBILE MONEY', Icons.phone_android_rounded, Colors.orangeAccent),
        const SizedBox(width: 10),
        _buildCompactMethodBtn('CARD', Icons.credit_card_rounded, Colors.blueAccent),
      ],
    );
  }

  Widget _buildCompactMethodBtn(String method, IconData icon, Color color) {
    final isSelected = _selectedPaymentMethod == method;
    return Expanded(
      child: Material(
        color: isSelected ? color.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() {
            _selectedPaymentMethod = method;
            if (method != 'CASH') {
              _tenderedAmount = ref.read(cartProvider.notifier).total;
            } else {
              _tenderedAmount = 0;
            }
          }),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border.all(color: isSelected ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: isSelected ? color : Colors.white24, size: 16),
                const SizedBox(width: 8),
                Text(
                  method == 'MOBILE MONEY' ? 'M-MONEY' : method,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : Colors.white30,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumericKeypad() {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _buildKey('1'), const SizedBox(width: 6),
              _buildKey('2'), const SizedBox(width: 6),
              _buildKey('3'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              _buildKey('4'), const SizedBox(width: 6),
              _buildKey('5'), const SizedBox(width: 6),
              _buildKey('6'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              _buildKey('7'), const SizedBox(width: 6),
              _buildKey('8'), const SizedBox(width: 6),
              _buildKey('9'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              _buildKey('0'), const SizedBox(width: 6),
              _buildKey('00'), const SizedBox(width: 6),
              _buildClearKey(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKey(String label) {
    return Expanded(
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () {
            setState(() {
              String digits = _tenderedAmount.toStringAsFixed(2).replaceAll('.', '');
              if (digits == '000') digits = '';
              digits += label;
              if (digits.length > 10) return;
              _tenderedAmount = double.parse(digits) / 100;
            });
          },
          borderRadius: BorderRadius.circular(10),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClearKey() {
    return Expanded(
      child: Material(
        color: Colors.redAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => setState(() => _tenderedAmount = 0),
          onLongPress: () => setState(() => _tenderedAmount = 0),
          borderRadius: BorderRadius.circular(10),
          child: const Center(child: Icon(Icons.backspace_rounded, color: Colors.redAccent, size: 18)),
        ),
      ),
    );
  }

  Widget _buildExactAmountBtn(CartNotifier cartNotifier, String currency) {
    return Material(
      color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => setState(() => _tenderedAmount = cartNotifier.total),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          child: Text(
            'EXACT',
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D)),
          ),
        ),
      ),
    );
  }

  Widget _buildDigitalPaymentPrompt(String currency) {
    final total = ref.read(cartProvider.notifier).total;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _selectedPaymentMethod == 'CARD' ? Icons.credit_card_rounded : Icons.phone_android_rounded,
              size: 64,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'PLEASE PROCESS ON MERCHANT DEVICE',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.4),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyFormatter.format(total, currency),
            style: GoogleFonts.manrope(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: Color(0xFFC1F11D), size: 16),
                SizedBox(width: 8),
                Text(
                  'READY FOR CONFIRMATION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFC1F11D),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteSaleButton(CartNotifier cartNotifier) {
    final total = cartNotifier.total;
    final isCash = _selectedPaymentMethod == 'CASH';
    final canComplete = !isCash || (_tenderedAmount >= total);

    return Material(
      color: canComplete && !_isProcessingPayment ? const Color(0xFFC1F11D) : Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: (canComplete && !_isProcessingPayment) ? () => _finalizeSale(cartNotifier) : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 56,
          alignment: Alignment.center,
          child: _isProcessingPayment
            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
            : Text(
                'COMPLETE SALE',
                style: GoogleFonts.manrope(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: canComplete ? Colors.black : Colors.white24,
                  letterSpacing: 1,
                ),
              ),
        ),
      ),
    );
  }

  Widget _buildTenderDisplay(String currency) {
    final cartNotifier = ref.read(cartProvider.notifier);
    final total = cartNotifier.total;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Text(
            _selectedPaymentMethod == 'CASH' ? 'TENDERED AMOUNT' : 'TOTAL TO PAY', 
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.4))
          ),
          const SizedBox(height: 8),
          Text(
            _selectedPaymentMethod == 'CASH' 
              ? (_tenderedAmount == 0 ? 'ENTER AMOUNT' : CurrencyFormatter.format(_tenderedAmount, currency))
              : CurrencyFormatter.format(total, currency),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: (_selectedPaymentMethod == 'CASH' && _tenderedAmount == 0) ? Colors.white.withValues(alpha: 0.1) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTenderButton(double amount, String currency) {
    final bool isCash = _selectedPaymentMethod == 'CASH';
    return Opacity(
      opacity: isCash ? 1.0 : 0.3,
      child: Material(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: isCash ? () => setState(() => _tenderedAmount += amount) : null,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              CurrencyFormatter.format(amount, currency),
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCartRow(CartItem item, CartNotifier cartNotifier, String currency) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 12.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${CurrencyFormatter.format(item.unitPrice, currency)} / unit',
                  style: GoogleFonts.jetBrainsMono(fontSize: 9.5, color: Colors.white38),
                ),
              ],
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQtyActionBtn(Icons.remove_rounded, () => cartNotifier.updateQuantity(item.product.id, -1)),
                InkWell(
                  onTap: () => _showQuantityDialog(item, cartNotifier),
                  child: Container(
                    width: 44,
                    alignment: Alignment.center,
                    child: Text(
                      '${item.quantity}',
                      style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D)),
                    ),
                  ),
                ),
                _buildQtyActionBtn(Icons.add_rounded, () => cartNotifier.updateQuantity(item.product.id, 1)),
              ],
            ),
          ),
          
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white12, size: 16),
            onPressed: () => cartNotifier.removeProduct(item.product.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _showQuantityDialog(CartItem item, CartNotifier cartNotifier) {
    final controller = TextEditingController(text: item.quantity.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Edit Quantity', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 15)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 22),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(border: InputBorder.none),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white24)),
          ),
          TextButton(
            onPressed: () {
              final newQty = int.tryParse(controller.text) ?? 1;
              cartNotifier.setQuantity(item.product.id, newQty);
              Navigator.pop(ctx);
            },
            child: const Text('UPDATE', style: TextStyle(color: Color(0xFFC1F11D))),
          ),
        ],
      ),
    );
  }

  Widget _buildQtyActionBtn(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, color: Colors.white38, size: 13),
        ),
      ),
    );
  }

  Widget _buildOrderSummary(CartState cartState, CartNotifier cartNotifier, String currency) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Column(
        children: [
          // B2B Corporate / Tax Invoice Customer TPIN Card
          if (cartState.customerTpin != null && cartState.customerTpin!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.business_rounded, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BUYER TPIN: ${cartState.customerTpin}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                        if (cartState.customerBusinessName != null)
                          Text(cartState.customerBusinessName!, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => cartNotifier.setCustomerTpin(null),
                    child: const Icon(Icons.close, size: 16, color: Colors.white54),
                  ),
                ],
              ),
            )
          else
            InkWell(
              onTap: () => _showB2bCustomerModal(context, cartNotifier, cartState),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.business_rounded, color: Color(0xFFC1F11D), size: 16),
                    SizedBox(width: 8),
                    Text('+ Buyer TPIN / Tax Invoice', style: TextStyle(color: Color(0xFFC1F11D), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Subtotal', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              Text(CurrencyFormatter.format(cartNotifier.total, currency), style: const TextStyle(color: Colors.white, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL DUE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFFC1F11D))),
              Text(
                CurrencyFormatter.format(cartNotifier.total, currency),
                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showB2bCustomerModal(BuildContext context, CartNotifier cartNotifier, CartState cartState) {
    final tpinCtrl = TextEditingController(text: cartState.customerTpin ?? '');
    final nameCtrl = TextEditingController(text: cartState.customerBusinessName ?? '');
    final addrCtrl = TextEditingController(text: cartState.customerAddress ?? '');
    bool isVerifying = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1E),
          title: Row(
            children: [
              const Icon(Icons.business_rounded, color: Color(0xFFC1F11D)),
              const SizedBox(width: 10),
              Text('BUYER TPIN / TAX INVOICE', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Enter the corporate buyer’s ZRA TPIN to issue an official Tax Invoice for VAT claim.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 16),
                TextField(
                  controller: tpinCtrl,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Customer TPIN (10 Digits) *',
                    hintText: '1000000000',
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: isVerifying
                        ? const SizedBox(height: 18, width: 18, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC1F11D))))
                        : TextButton(
                            onPressed: () async {
                              final tpin = tpinCtrl.text.trim();
                              if (tpin.isEmpty) return;
                              setModalState(() => isVerifying = true);
                              try {
                                final res = await ref.read(digitaxInventoryServiceProvider).lookupTaxpayerTpin(tpin);
                                if (res != null) {
                                  nameCtrl.text = res['taxpayer_name'] ?? res['name'] ?? '';
                                  addrCtrl.text = res['physical_address'] ?? res['address'] ?? '';
                                }
                              } finally {
                                setModalState(() => isVerifying = false);
                              }
                            },
                            child: const Text('Verify', style: TextStyle(color: Color(0xFFC1F11D), fontWeight: FontWeight.bold)),
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Registered Business Name',
                    hintText: 'e.g. ABC Holdings Ltd',
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addrCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Physical Address',
                    hintText: 'e.g. Plot 45, Cairo Road, Lusaka',
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                final tpin = tpinCtrl.text.trim();
                final name = nameCtrl.text.trim();
                final addr = addrCtrl.text.trim();
                cartNotifier.setCustomerTpin(
                  tpin.isNotEmpty ? tpin : null,
                  businessName: name.isNotEmpty ? name : null,
                  address: addr.isNotEmpty ? addr : null,
                );
                Navigator.pop(dialogCtx);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC1F11D), foregroundColor: Colors.black),
              child: const Text('Apply to Invoice'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalizeSale(CartNotifier cartNotifier) async {
    setState(() => _isProcessingPayment = true);
    final total = cartNotifier.total;
    final change = _selectedPaymentMethod == 'CASH' ? (_tenderedAmount - total) : 0.0;

    try {
      final cartNotifier = ref.read(cartProvider.notifier);
      final cartState = ref.read(cartProvider);
      final db = ref.read(databaseServiceProvider);
      final printer = ref.read(printerServiceProvider);
      final config = ref.read(storeConfigProvider).value;

      final saleItems = cartState.items.map((item) => SaleItem(
        productId: item.product.id,
        productName: item.product.name,
        priceAtSale: item.unitPrice,
        unitCostAtSale: item.product.unitCost,
        quantity: item.quantity,
        taxRateAtSale: item.product.taxRate,
        isTaxInclusiveAtSale: item.product.isTaxInclusive,
      )).toList();

      final currentUser = ref.read(authProvider);

      final transaction = SaleTransaction(
        totalAmount: total,
        paymentMethod: _selectedPaymentMethod,
        cashierName: currentUser?.name ?? 'Cashier',
        cashierId: currentUser?.id.toString(),
        terminalName: config?.terminalName ?? 'TILL-01',
        subtotal: cartNotifier.subtotal,
        taxAmount: cartNotifier.tax,
        discountAmount: cartState.discountAmount,
        tenderedAmount: _selectedPaymentMethod == 'CASH' ? _tenderedAmount : total,
        changeAmount: _selectedPaymentMethod == 'CASH' ? change : 0.0,
        customerTpin: cartState.customerTpin,
        customerBusinessName: cartState.customerBusinessName,
        customerAddress: cartState.customerAddress,
        zraSdcId: config?.sdcId,
      );

      await db.saveTransaction(transaction, saleItems);
      
      // Fiscalize with DigiTax VSDC Cloud (Live ZRA Smart Invoice & Server-Side Tax Calculations)
      final hasDigitax = config?.digitaxApiKey != null && config!.digitaxApiKey!.trim().isNotEmpty;
      final fiscalized = await ref.read(digitaxInventoryServiceProvider).fiscalizeSaleTransaction(transaction, saleItems);

      // Attempt local real-time sync (or queue for offline)
      ref.read(syncServiceProvider).trySyncTransaction(transaction, saleItems);
      
      // Auto-kick Cash Drawer Hardware Driver on payment completion
      if (config?.autoOpenCashDrawer != false) {
        final isCashOrSplit = transaction.paymentMethod.toLowerCase() == 'cash' || 
                             transaction.paymentMethod.toLowerCase() == 'split';
        if (config?.openDrawerCashOnly != true || isCashOrSplit) {
          try {
            await printer.openCashDrawer(config: config);
          } catch (e) {
            debugPrint('Cash drawer payment kick notice: $e');
          }
        }
      }

      // Option A: Print receipt immediately so customer always leaves with proof of purchase.
      // If online/fiscalized -> prints Tax Invoice with live ZRA QR code.
      // If offline/pending -> prints Customer Sales Slip and syncs fiscal data in the background.
      if (config?.autoPrintReceipt != false) {
        await printer.printReceipt(transaction, saleItems, config: config);
        if (hasDigitax && !fiscalized) {
          _scheduleDigitaxFiscalRefreshAndPrint(transaction, saleItems);
        }
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A1E),
            title: const Text('Sale Complete', style: TextStyle(color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change Due: ${CurrencyFormatter.format(change, config?.currencySymbol ?? "ZK")}', 
                  style: const TextStyle(color: Color(0xFFC1F11D), fontSize: 22, fontWeight: FontWeight.bold),
                ),
                if (hasDigitax && !fiscalized) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAB308).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.hourglass_top_rounded, color: Color(0xFFEAB308), size: 14),
                        SizedBox(width: 6),
                        Text(
                          'DigiTax Fiscalizing... Receipt will print automatically',
                          style: TextStyle(color: Color(0xFFEAB308), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  cartNotifier.clear();
                  setState(() {
                    _tenderedAmount = 0;
                    _isCheckoutActive = false;
                  });
                  _searchFocusNode.requestFocus();
                },
                child: const Text('NEW SALE', style: TextStyle(color: Color(0xFFC1F11D))),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessingPayment = false);
    }
  }

  void _scheduleDigitaxFiscalRefreshAndPrint(SaleTransaction tx, List<SaleItem> items) {
    Future(() async {
      final dtService = ref.read(digitaxInventoryServiceProvider);
      for (int attempt = 1; attempt <= 6; attempt++) {
        await Future.delayed(Duration(seconds: attempt == 1 ? 2 : 3));
        try {
          final refreshed = await dtService.refreshTransactionFiscalData(tx);
          if (refreshed) {
            final config = ref.read(storeConfigProvider).value;
            if (config?.autoPrintReceipt != false) {
              await ref.read(printerServiceProvider).printReceipt(tx, items, config: config);
              debugPrint('DIGITAX_ASYNC_PRINT: Live receipt printed after background confirmation for Tx #${tx.id}');
            }
            break;
          }
        } catch (e) {
          debugPrint('Delayed fiscal refresh attempt $attempt notice: $e');
        }
      }
    });
  }
}
