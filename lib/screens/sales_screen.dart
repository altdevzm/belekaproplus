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
import 'package:beleka_pos/services/scale_service.dart';
import 'package:beleka_pos/services/sync_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/screens/sales/weight_scale_modal.dart';
import 'package:beleka_pos/widgets/camera_barcode_scanner_modal.dart';
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
    final config = ref.read(storeConfigProvider).value;
    final currency = config?.currencySymbol ?? 'ZK';

    if (product.isWeighted) {
      final double? weight = await showDialog<double>(
        context: context,
        builder: (context) => WeightScaleModal(
          product: product,
          currency: currency,
        ),
      );

      if (weight != null && weight > 0) {
        final success = cartNotifier.addWeightedProduct(
          product,
          weight: weight,
          tareWeight: product.tareWeight,
        );
        if (mounted && success) {
          HapticFeedback.mediumImpact();
        }
      }
      return;
    }

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

  Future<void> _lookupProduct(String barcode) async {
    final scaleService = ref.read(scaleServiceProvider);
    final scaleBarcodeResult = scaleService.parseScaleBarcode(barcode);
    final db = ref.read(databaseServiceProvider);
    
    if (scaleBarcodeResult != null) {
      // Find product matching the PLU code or SKU prefix
      final products = await db.getAllProducts();
      final matchedProduct = products.where((p) => 
        p.isWeighted && (p.scalePlu == scaleBarcodeResult.pluCode || p.sku == scaleBarcodeResult.pluCode || p.sku == barcode)
      ).firstOrNull;

      if (matchedProduct != null) {
        final cartNotifier = ref.read(cartProvider.notifier);
        cartNotifier.addWeightedProduct(
          matchedProduct,
          weight: scaleBarcodeResult.weightInKg,
          tareWeight: matchedProduct.tareWeight,
        );
        if (mounted) {
          HapticFeedback.mediumImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚖️ Added ${matchedProduct.name} (${scaleBarcodeResult.weightInKg.toStringAsFixed(3)} kg)'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(milliseconds: 1500),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    final product = await db.getProductBySku(barcode);
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1050) {
            return _buildDesktopSalesLayout(
              context,
              productsAsync,
              filteredProducts,
              allCategories,
              cartState,
              cartNotifier,
              currency,
            );
          } else {
            return _buildMobileSalesLayout(
              context,
              productsAsync,
              filteredProducts,
              allCategories,
              cartState,
              cartNotifier,
              currency,
            );
          }
        },
      ),
    );
  }

  // --- Adaptive Desktop / Tablet 3-Column POS Layout ---

  Widget _buildDesktopSalesLayout(
    BuildContext context,
    AsyncValue<List<Product>> productsAsync,
    List<Product> filteredProducts,
    List<Category> allCategories,
    CartState cartState,
    CartNotifier cartNotifier,
    String currency,
  ) {
    return Row(
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
                    Expanded(
                      child: _buildPanelHeader(
                        Icons.grid_view_rounded,
                        'PRODUCT CATALOG',
                        const Color(0xFFC1F11D),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Camera Barcode / QR Scanner
                        Tooltip(
                          message: 'Scan Product Barcode / QR',
                          child: InkWell(
                            onTap: _openCameraScanner,
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC1F11D).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.25)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.qr_code_scanner_rounded, size: 16, color: Color(0xFFC1F11D)),
                                  SizedBox(width: 4),
                                  Text(
                                    'SCAN',
                                    style: TextStyle(color: Color(0xFFC1F11D), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
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
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.point_of_sale_rounded, size: 16, color: Color(0xFFC1F11D)),
                                  SizedBox(width: 4),
                                  Text(
                                    'DRAWER',
                                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
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
    );
  }

  // --- Dedicated Adaptive Mobile Sales View ---

  Widget _buildMobileSalesLayout(
    BuildContext context,
    AsyncValue<List<Product>> productsAsync,
    List<Product> filteredProducts,
    List<Category> allCategories,
    CartState cartState,
    CartNotifier cartNotifier,
    String currency,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Mobile Search & Quick Tools
            Row(
              children: [
                Expanded(
                  child: TextField(
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
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search product or SKU...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white30),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Colors.white38),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFFC1F11D), size: 20),
                            tooltip: 'Scan Barcode / QR',
                            onPressed: _openCameraScanner,
                          ),
                        ],
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Quick Cash Drawer button
                IconButton(
                  icon: const Icon(Icons.point_of_sale_rounded, color: Color(0xFFC1F11D), size: 20),
                  tooltip: 'Open Drawer',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final config = ref.read(storeConfigProvider).value;
                    final ok = await ref.read(printerServiceProvider).openCashDrawer(config: config);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? '✓ Cash drawer opened' : '⚠️ Kick signal sent'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 4),
                // Grid / List toggle
                IconButton(
                  icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, color: Colors.white70, size: 20),
                  tooltip: _isGridView ? 'Switch to List' : 'Switch to Grid',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Category Filter Ribbon Chips
            _buildCategoryRibbon(allCategories),
            const SizedBox(height: 10),

            // Products Display Area
            Expanded(
              child: productsAsync.when(
                data: (_) {
                  if (filteredProducts.isEmpty) {
                    return _buildEmptyCatalogState();
                  }
                  if (_isGridView) {
                    return _buildMobileProductsGrid(filteredProducts, currency);
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

            const SizedBox(height: 8),

            // Docked Floating Cart & Pay Bar
            _buildMobileBottomBar(cartState, cartNotifier, currency),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileProductsGrid(List<Product> products, String currency) {
    return GridView.builder(
      itemCount: products.length,
      padding: const EdgeInsets.only(bottom: 6),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 175,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemBuilder: (context, index) {
        final product = products[index];
        return _buildProductCard(product, currency);
      },
    );
  }

  Widget _buildMobileBottomBar(CartState cartState, CartNotifier cartNotifier, String currency) {
    final totalItems = cartState.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final total = cartNotifier.total;
    final hasItems = cartState.items.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasItems ? const Color(0xFFC1F11D).withValues(alpha: 0.35) : Colors.white.withValues(alpha: 0.08),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cart Summary & Tap to View Sheet
          Expanded(
            child: InkWell(
              onTap: hasItems ? () => _showMobileCartSheet(context, cartState, cartNotifier, currency) : null,
              borderRadius: BorderRadius.circular(10),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: hasItems ? const Color(0xFFC1F11D).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          color: hasItems ? const Color(0xFFC1F11D) : Colors.white38,
                          size: 20,
                        ),
                      ),
                      if (totalItems > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFC1F11D),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$totalItems',
                              style: GoogleFonts.manrope(
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          hasItems ? CurrencyFormatter.format(total, currency) : 'Cart is Empty',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: hasItems ? Colors.white : Colors.white38,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          hasItems ? '$totalItems item${totalItems > 1 ? "s" : ""} • Tap to view' : 'Tap item or scan',
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: hasItems ? const Color(0xFFC1F11D) : Colors.white30,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // Pay Button
          ElevatedButton(
            onPressed: hasItems ? () => _showMobileCheckoutSheet(context, cartNotifier, currency) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC1F11D),
              disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
              foregroundColor: Colors.black,
              disabledForegroundColor: Colors.white24,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: hasItems ? 4 : 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.payments_rounded, size: 18),
                const SizedBox(width: 6),
                Text(
                  'PAY NOW',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMobileCartSheet(
    BuildContext context,
    CartState cartState,
    CartNotifier cartNotifier,
    String currency,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final activeCartState = ref.watch(cartProvider);
            final activeCartNotifier = ref.watch(cartProvider.notifier);
            final media = MediaQuery.of(context);

            return Container(
              height: media.size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFF141418),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.shopping_cart_outlined, color: Color(0xFFC1F11D), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'ORDER REVIEW',
                              style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ],
                        ),
                        if (activeCartState.items.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              activeCartNotifier.clearCart();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),

                  // Cart Items
                  Expanded(
                    child: activeCartState.items.isEmpty
                        ? Center(
                            child: Text('Cart is empty', style: GoogleFonts.inter(color: Colors.white38)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: activeCartState.items.length,
                            itemBuilder: (context, index) =>
                                _buildCartRow(activeCartState.items[index], activeCartNotifier, currency),
                          ),
                  ),

                  // Order Summary & Checkout Trigger
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B20),
                      border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildOrderSummary(activeCartState, activeCartNotifier, currency),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: activeCartState.items.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _showMobileCheckoutSheet(context, activeCartNotifier, currency);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC1F11D),
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              'PROCEED TO PAY (${CurrencyFormatter.format(activeCartNotifier.total, currency)})',
                              style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showMobileCheckoutSheet(
    BuildContext context,
    CartNotifier cartNotifier,
    String currency,
  ) {
    setState(() {
      _isCheckoutActive = true;
      _selectedPaymentMethod = 'CASH';
      _tenderedAmount = 0.0;
    });

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final total = cartNotifier.total;
            final isCash = _selectedPaymentMethod == 'CASH';
            final canComplete = !isCash || (_tenderedAmount >= total);

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(
                color: Color(0xFF141418),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.payments_rounded, color: Color(0xFFC1F11D), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'PAYMENT CHECKOUT',
                              style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 1),

                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Payment Method Selector
                          Row(
                            children: [
                              Expanded(
                                child: _buildMobileMethodBtn(
                                  'CASH',
                                  Icons.payments_rounded,
                                  const Color(0xFFC1F11D),
                                  _selectedPaymentMethod == 'CASH',
                                  () => setModalState(() {
                                    _selectedPaymentMethod = 'CASH';
                                    _tenderedAmount = 0.0;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMobileMethodBtn(
                                  'MOBILE MONEY',
                                  Icons.phone_android_rounded,
                                  Colors.orangeAccent,
                                  _selectedPaymentMethod == 'MOBILE MONEY',
                                  () => setModalState(() {
                                    _selectedPaymentMethod = 'MOBILE MONEY';
                                    _tenderedAmount = total;
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMobileMethodBtn(
                                  'CARD',
                                  Icons.credit_card_rounded,
                                  Colors.blueAccent,
                                  _selectedPaymentMethod == 'CARD',
                                  () => setModalState(() {
                                    _selectedPaymentMethod = 'CARD';
                                    _tenderedAmount = total;
                                  }),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          if (_selectedPaymentMethod == 'CASH') ...[
                            _buildTenderDisplay(currency),
                            const SizedBox(height: 14),

                            // Note shortcuts
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildNoteChip(20, currency, () => setModalState(() => _tenderedAmount += 20)),
                                  const SizedBox(width: 6),
                                  _buildNoteChip(50, currency, () => setModalState(() => _tenderedAmount += 50)),
                                  const SizedBox(width: 6),
                                  _buildNoteChip(100, currency, () => setModalState(() => _tenderedAmount += 100)),
                                  const SizedBox(width: 6),
                                  _buildNoteChip(200, currency, () => setModalState(() => _tenderedAmount += 200)),
                                  const SizedBox(width: 6),
                                  _buildNoteChip(500, currency, () => setModalState(() => _tenderedAmount += 500)),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => setModalState(() => _tenderedAmount = total),
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        'EXACT (${CurrencyFormatter.format(total, currency)})',
                                        style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFC1F11D)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Numeric Keypad
                            SizedBox(
                              height: 220,
                              child: _buildMobileKeypad((key) {
                                setModalState(() {
                                  if (key == 'C') {
                                    _tenderedAmount = 0.0;
                                  } else if (key == '⌫') {
                                    String digits = _tenderedAmount.toStringAsFixed(2).replaceAll('.', '');
                                    if (digits.length > 3) {
                                      digits = digits.substring(0, digits.length - 1);
                                      _tenderedAmount = double.parse(digits) / 100;
                                    } else {
                                      _tenderedAmount = 0.0;
                                    }
                                  } else {
                                    String digits = _tenderedAmount.toStringAsFixed(2).replaceAll('.', '');
                                    if (digits == '000') digits = '';
                                    digits += key;
                                    if (digits.length <= 10) {
                                      _tenderedAmount = double.parse(digits) / 100;
                                    }
                                  }
                                });
                              }),
                            ),
                          ] else ...[
                            _buildDigitalPaymentPrompt(currency),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Complete Sale Button
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: (canComplete && !_isProcessingPayment)
                            ? () async {
                                Navigator.pop(ctx);
                                await _finalizeSale(cartNotifier);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC1F11D),
                          disabledBackgroundColor: Colors.white.withValues(alpha: 0.05),
                          foregroundColor: Colors.black,
                          disabledForegroundColor: Colors.white24,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isProcessingPayment
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                            : Text(
                                'COMPLETE SALE & PRINT RECEIPT',
                                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMobileMethodBtn(
    String method,
    IconData icon,
    Color color,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.black : Colors.white70, size: 18),
            const SizedBox(height: 4),
            Text(
              method == 'MOBILE MONEY' ? 'M-MONEY' : method,
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.black : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteChip(double amount, String currency, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          '+${CurrencyFormatter.format(amount, currency)}',
          style: GoogleFonts.manrope(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildMobileKeypad(ValueChanged<String> onKeyPress) {
    Widget buildBtn(String label, {Color? textColor, Color? bgColor}) {
      return Expanded(
        child: Material(
          color: bgColor ?? Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => onKeyPress(label),
            borderRadius: BorderRadius.circular(10),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: textColor ?? Colors.white,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              buildBtn('1'), const SizedBox(width: 6),
              buildBtn('2'), const SizedBox(width: 6),
              buildBtn('3'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              buildBtn('4'), const SizedBox(width: 6),
              buildBtn('5'), const SizedBox(width: 6),
              buildBtn('6'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              buildBtn('7'), const SizedBox(width: 6),
              buildBtn('8'), const SizedBox(width: 6),
              buildBtn('9'),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            children: [
              buildBtn('C', textColor: Colors.redAccent), const SizedBox(width: 6),
              buildBtn('0'), const SizedBox(width: 6),
              buildBtn('⌫', textColor: Colors.amberAccent),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openCameraScanner() async {
    final scannedCode = await CameraBarcodeScannerModal.show(context);
    if (scannedCode != null && scannedCode.isNotEmpty) {
      _lookupProduct(scannedCode);
    }
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
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 175,
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
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              // Top Row: Product Icon/Image & Badge
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: (product.imagePath != null && File(product.imagePath!).existsSync())
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(product.imagePath!), fit: BoxFit.cover),
                          )
                        : const Icon(Icons.inventory_2_outlined, color: Color(0xFFC1F11D), size: 18),
                  ),
                  if (isOutOfStock)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'OUT',
                        style: GoogleFonts.manrope(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.redAccent,
                          letterSpacing: 0.3,
                        ),
                      ),
                    )
                  else if (product.isWeighted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC1F11D).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.scale_rounded, color: Color(0xFFC1F11D), size: 9),
                          const SizedBox(width: 2),
                          Text(
                            product.unitOfMeasure.toUpperCase(),
                            style: GoogleFonts.manrope(
                              fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFC1F11D),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (hasDiscount)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'PROMO',
                        style: GoogleFonts.manrope(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Product Name & SKU — tightly below the icon
              Text(
                product.name,
                style: GoogleFonts.manrope(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: isOutOfStock ? Colors.white38 : Colors.white,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '#${product.sku}',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 9,
                  color: Colors.white24,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

              // Push price & add button to bottom
              const Spacer(),

              // Bottom Row: Price & Instant Add
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasDiscount) ...[
                          Text(
                            CurrencyFormatter.format(product.price, currency),
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white24,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          Text(
                            '${CurrencyFormatter.format(product.discountPrice!, currency)}${product.isWeighted ? "/${product.unitOfMeasure}" : ""}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFC1F11D),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ] else ...[
                          Text(
                            '${CurrencyFormatter.format(product.price, currency)}${product.isWeighted ? "/${product.unitOfMeasure}" : ""}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                              color: isOutOfStock ? Colors.white24 : const Color(0xFFC1F11D),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isOutOfStock
                          ? Colors.white.withValues(alpha: 0.04)
                          : const Color(0xFFC1F11D),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOutOfStock ? Icons.block_rounded : (product.isWeighted ? Icons.scale_rounded : Icons.add),
                      color: isOutOfStock ? Colors.white24 : Colors.black,
                      size: 15,
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
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedPaymentMethod = method;
          if (method != 'CASH') {
            _tenderedAmount = ref.read(cartProvider.notifier).total;
          } else {
            _tenderedAmount = 0;
          }
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          height: 52,
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? color : Colors.white.withValues(alpha: 0.18),
              width: isSelected ? 0 : 1.2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.45),
                      blurRadius: 14,
                      spreadRadius: 0,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.black : Colors.white.withValues(alpha: 0.75),
                size: 17,
              ),
              const SizedBox(width: 7),
              Text(
                method == 'MOBILE MONEY' ? 'M-MONEY' : method,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                  color: isSelected ? Colors.black : Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
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
    final unit = item.product.unitOfMeasure.toLowerCase().trim();
    final unitLabel = unit.isEmpty ? 'kg' : unit;

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
                Row(
                  children: [
                    if (item.isWeighted)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'SCALE',
                          style: GoogleFonts.manrope(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFC1F11D),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        item.product.name,
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 12.5),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.isWeighted
                      ? '${item.weight.toStringAsFixed(3)} $unitLabel @ ${CurrencyFormatter.format(item.unitPrice, currency)}/$unitLabel'
                      : '${CurrencyFormatter.format(item.unitPrice, currency)} / unit',
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
                _buildQtyActionBtn(
                  Icons.remove_rounded,
                  () => item.isWeighted
                      ? _handleProductSelection(item.product)
                      : cartNotifier.updateQuantity(item.product.id, -1),
                ),
                InkWell(
                  onTap: () => item.isWeighted
                      ? _handleProductSelection(item.product)
                      : _showQuantityDialog(item, cartNotifier),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    constraints: const BoxConstraints(minWidth: 44),
                    alignment: Alignment.center,
                    child: Text(
                      item.isWeighted
                          ? '${item.weight.toStringAsFixed(2)} $unitLabel'
                          : '${item.quantity}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: item.isWeighted ? 12.5 : 16,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFC1F11D),
                      ),
                    ),
                  ),
                ),
                _buildQtyActionBtn(
                  Icons.add_rounded,
                  () => item.isWeighted
                      ? _handleProductSelection(item.product)
                      : cartNotifier.updateQuantity(item.product.id, 1),
                ),
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
    if (item.isWeighted) {
      _handleProductSelection(item.product);
      return;
    }
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
              Text('Items Subtotal', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
              Text(CurrencyFormatter.format(cartNotifier.subtotal, currency), style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
          if (cartNotifier.tax > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('VAT / Tax', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                Text(CurrencyFormatter.format(cartNotifier.tax, currency), style: const TextStyle(color: Colors.white, fontSize: 12)),
              ],
            ),
          ],
          if (cartState.serviceChargeEnabled && cartNotifier.serviceChargeAmount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Service Charge (${cartState.serviceChargeRate.toStringAsFixed(0)}% • Untaxed)',
                      style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: () => cartNotifier.toggleServiceCharge(false),
                      child: const Icon(Icons.close, size: 14, color: Colors.white38),
                    ),
                  ],
                ),
                Text(
                  CurrencyFormatter.format(cartNotifier.serviceChargeAmount, currency),
                  style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _showServiceChargeModal(context, cartNotifier, cartState),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('+ Service Charge (Untaxed)', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 11)),
                    Text('0%', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
          if (cartState.discountAmount > 0) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Discount', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12)),
                Text('- ${CurrencyFormatter.format(cartState.discountAmount, currency)}', style: const TextStyle(color: Color(0xFFC1F11D), fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
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

  void _showServiceChargeModal(BuildContext context, CartNotifier cartNotifier, CartState cartState) {
    final rateCtrl = TextEditingController(
      text: cartState.serviceChargeRate > 0 ? cartState.serviceChargeRate.toStringAsFixed(0) : '10',
    );

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.room_service_rounded, color: Color(0xFF60A5FA)),
            const SizedBox(width: 10),
            Text('Restaurant Service Charge', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apply a non-taxable service charge to this bill. This charge is NOT subject to VAT and is not invoiced to DigiTax.',
              style: GoogleFonts.inter(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 16),
            Text('QUICK SELECT PERCENTAGE', style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white38, letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(
              children: [
                ...[5, 10, 15].map((rate) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text('$rate%'),
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    labelStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                    onPressed: () {
                      rateCtrl.text = rate.toString();
                    },
                  ),
                )),
              ],
            ),
            const SizedBox(height: 14),
            Text('CUSTOM PERCENTAGE (%)', style: GoogleFonts.manrope(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white38, letterSpacing: 1)),
            const SizedBox(height: 8),
            TextField(
              controller: rateCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                suffixText: '%',
                suffixStyle: const TextStyle(color: Colors.white60),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cartNotifier.toggleServiceCharge(false);
              Navigator.pop(dialogCtx);
            },
            child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF60A5FA),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              final rate = double.tryParse(rateCtrl.text.trim()) ?? 0.0;
              cartNotifier.setServiceChargeRate(rate);
              Navigator.pop(dialogCtx);
            },
            child: const Text('Apply Charge', style: TextStyle(fontWeight: FontWeight.bold)),
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
    bool isVerified = false;
    String? verifyError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                const Text(
                  "Enter the corporate buyer's ZRA TPIN to issue an official Tax Invoice for VAT claim.",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),

                Builder(
                  builder: (context) {
                    Future<void> doVerify() async {
                      final tpin = tpinCtrl.text.trim();
                      if (tpin.length != 10) {
                        setModalState(() => verifyError = 'TPIN must be exactly 10 digits');
                        return;
                      }
                      setModalState(() {
                        isVerifying = true;
                        verifyError = null;
                      });
                      try {
                        final res = await ref.read(digitaxInventoryServiceProvider).lookupTaxpayerTpin(tpin);
                        if (res != null && res.containsKey('error')) {
                          setModalState(() {
                            verifyError = res['error'] as String?;
                            isVerified = false;
                          });
                        } else if (res != null) {
                          final fetchedName = (res['taxpayer_name'] ?? res['name'] ?? '').toString();
                          final fetchedAddr = (res['physical_address'] ?? res['address'] ?? '').toString();
                          if (fetchedName.isNotEmpty) nameCtrl.text = fetchedName;
                          if (fetchedAddr.isNotEmpty) addrCtrl.text = fetchedAddr;
                          setModalState(() {
                            isVerified = true;
                            verifyError = null;
                          });
                        } else {
                          setModalState(() {
                            verifyError = 'TPIN not found. Enter business name manually.';
                            isVerified = false;
                          });
                        }
                      } finally {
                        setModalState(() => isVerifying = false);
                      }
                    }

                    return TextField(
                      controller: tpinCtrl,
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      maxLength: 10,
                      onChanged: (val) {
                        final clean = val.trim();
                        if (clean.length == 10) {
                          doVerify();
                        } else if (isVerified || verifyError != null) {
                          setModalState(() {
                            isVerified = false;
                            verifyError = null;
                          });
                        }
                      },
                      decoration: InputDecoration(
                        labelText: 'Customer TPIN (10 Digits) *',
                        hintText: '1000000000',
                        counterText: '',
                        filled: true,
                        fillColor: isVerified
                            ? const Color(0xFF10B981).withValues(alpha: 0.08)
                            : Colors.black26,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isVerified
                                ? const Color(0xFF10B981)
                                : verifyError != null
                                    ? Colors.redAccent
                                    : Colors.white24,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                            color: isVerified
                                ? const Color(0xFF10B981)
                                : const Color(0xFFC1F11D),
                            width: 1.5,
                          ),
                        ),
                        suffixIcon: isVerifying
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFC1F11D)),
                                ),
                              )
                            : isVerified
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 22),
                                  )
                                : TextButton(
                                    onPressed: doVerify,
                                    child: const Text('Verify', style: TextStyle(color: Color(0xFFC1F11D), fontWeight: FontWeight.bold)),
                                  ),
                      ),
                    );
                  },
                ),

                // Verified banner
                if (isVerified)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'ZRA Taxpayer Verified',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF10B981), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),

                // Error message
                if (verifyError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            verifyError!,
                            style: GoogleFonts.inter(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
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
                if (tpin.isEmpty || name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter the TPIN and business name')),
                  );
                  return;
                }
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
        quantity: item.isWeighted ? 1 : item.quantity,
        taxRateAtSale: item.product.taxRate,
        isTaxInclusiveAtSale: item.product.isTaxInclusive,
        weight: item.isWeighted ? item.weight : 0.0,
        isWeighted: item.isWeighted,
        unitOfMeasure: item.product.unitOfMeasure,
        isDigitaxExempt: !item.product.isDigitaxSyncEnabled,
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
        serviceChargeAmount: cartNotifier.serviceChargeAmount,
        serviceChargeRate: cartState.serviceChargeRate,
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
