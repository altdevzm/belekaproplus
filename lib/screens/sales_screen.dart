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
              content: Text('Added ${matchedProduct.name} (${scaleBarcodeResult.weightInKg.toStringAsFixed(3)} kg)'),
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

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelBg = isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);
    final primaryColor = theme.colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PANEL 1: Product Catalog & Touch Selection (Left)
        Expanded(
          flex: 6,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panelBg,
              border: Border(right: BorderSide(color: borderColor, width: 1)),
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
                        context,
                        Icons.grid_view_rounded,
                        'PRODUCT CATALOG',
                        primaryColor,
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
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.qr_code_scanner_rounded, size: 16, color: primaryColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    'SCAN',
                                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w700),
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
                                          color: ok ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(ok ? 'Cash drawer opened' : 'Kick command sent (check printer connection)'),
                                      ],
                                    ),
                                    duration: const Duration(seconds: 2),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              height: 34,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.point_of_sale_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text(
                                    'DRAWER',
                                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 11, fontWeight: FontWeight.w700),
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
                            color: isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildViewModeBtn(
                                context,
                                icon: Icons.grid_view_rounded,
                                tooltip: 'Grid View',
                                isSelected: _isGridView,
                                onTap: () => setState(() => _isGridView = true),
                              ),
                              _buildViewModeBtn(
                                context,
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
                const SizedBox(height: 12),

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
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                  decoration: _searchInputDecoration(context),
                ),
                const SizedBox(height: 10),

                // Category Filter Ribbon Chips
                _buildCategoryRibbon(context, allCategories),
                const SizedBox(height: 12),

                // Products Display Area
                Expanded(
                  child: productsAsync.when(
                    data: (_) {
                      if (filteredProducts.isEmpty) {
                        return _buildEmptyCatalogState(context);
                      }
                      if (_isGridView) {
                        return _buildProductsGrid(context, filteredProducts, currency);
                      } else {
                        return _buildProductsList(context, filteredProducts, currency);
                      }
                    },
                    loading: () => const Center(
                      child: CircularProgressIndicator(),
                    ),
                    error: (err, _) => Center(
                      child: Text('Error loading products: $err', style: const TextStyle(color: Color(0xFFDC2626))),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // PANEL 2: Payment Console & Keypad Terminal (Middle)
        Expanded(
          flex: 4,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
              border: Border(right: BorderSide(color: borderColor, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPaymentMethodSelector(context),
                const SizedBox(height: 14),

                if (cartState.items.isEmpty)
                  Expanded(
                    child: _buildEmptyState(
                      context,
                      'Terminal Ready\nScan barcode or tap product to begin sale',
                      icon: Icons.point_of_sale_rounded,
                    ),
                  )
                else ...[
                  Builder(
                    builder: (context) {
                      if (_selectedPaymentMethod.isEmpty) {
                        _selectedPaymentMethod = 'CASH';
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                  if (_selectedPaymentMethod == 'CASH')
                    Expanded(
                      child: Column(
                        children: [
                          _buildTenderDisplay(context, currency),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Row(
                              children: [
                                // Note Shortcuts Grid
                                Expanded(
                                  flex: 4,
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Expanded(child: _buildQuickTenderButton(context, 20, currency)),
                                            const SizedBox(width: 4),
                                            Expanded(child: _buildQuickTenderButton(context, 50, currency)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Expanded(child: _buildQuickTenderButton(context, 100, currency)),
                                            const SizedBox(width: 4),
                                            Expanded(child: _buildQuickTenderButton(context, 200, currency)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Expanded(child: _buildQuickTenderButton(context, 500, currency)),
                                            const SizedBox(width: 4),
                                            Expanded(child: _buildExactAmountBtn(context, cartNotifier, currency)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Touch Keypad Grid
                                Expanded(
                                  flex: 5,
                                  child: _buildNumericKeypad(context),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Expanded(child: _buildDigitalPaymentPrompt(context, currency)),

                  const SizedBox(height: 12),
                  _buildCompleteSaleButton(context, cartNotifier),
                ],
              ],
            ),
          ),
        ),

        // PANEL 3: Live Order Review Cart (Right)
        Expanded(
          flex: 4,
          child: Container(
            decoration: BoxDecoration(
              color: panelBg,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('ORDER REVIEW', style: _headerTextStyle(context)),
                            if (cartState.items.isNotEmpty)
                              Row(
                                children: [
                                  Text(
                                    '${cartState.items.fold<int>(0, (sum, item) => sum + item.quantity)} items',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: primaryColor),
                                  ),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () {
                                      cartNotifier.clear();
                                      setState(() {
                                        _tenderedAmount = 0;
                                        _selectedPaymentMethod = '';
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Text(
                                        'CLEAR',
                                        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626)),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: cartState.items.isEmpty
                            ? _buildEmptyState(context, 'Cart is empty', icon: Icons.shopping_cart_outlined)
                            : ListView.builder(
                                itemCount: cartState.items.length,
                                itemBuilder: (context, index) => _buildCartRow(context, cartState.items[index], cartNotifier, currency),
                              ),
                      ),
                    ],
                  ),
                ),
                _buildOrderSummary(context, cartState, cartNotifier, currency),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

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
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Search product or SKU...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      prefixIcon: Icon(Icons.search_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.close_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: Icon(Icons.qr_code_scanner_rounded, color: primaryColor, size: 20),
                            tooltip: 'Scan Barcode / QR',
                            onPressed: _openCameraScanner,
                          ),
                        ],
                      ),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: primaryColor, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Quick Cash Drawer button
                IconButton(
                  icon: Icon(Icons.point_of_sale_rounded, color: primaryColor, size: 20),
                  tooltip: 'Open Drawer',
                  style: IconButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  onPressed: () async {
                    final config = ref.read(storeConfigProvider).value;
                    final ok = await ref.read(printerServiceProvider).openCashDrawer(config: config);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ok ? 'Cash drawer opened' : 'Kick signal sent'),
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
                  icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, color: theme.colorScheme.onSurfaceVariant, size: 20),
                  tooltip: _isGridView ? 'Switch to List' : 'Switch to Grid',
                  style: IconButton.styleFrom(
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                  ),
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Category Filter Ribbon Chips
            _buildCategoryRibbon(context, allCategories),
            const SizedBox(height: 10),

            // Products Display Area
            Expanded(
              child: productsAsync.when(
                data: (_) {
                  if (filteredProducts.isEmpty) {
                    return _buildEmptyCatalogState(context);
                  }
                  if (_isGridView) {
                    return _buildMobileProductsGrid(context, filteredProducts, currency);
                  } else {
                    return _buildProductsList(context, filteredProducts, currency);
                  }
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (err, _) => Center(
                  child: Text('Error loading products: $err', style: const TextStyle(color: Color(0xFFEF4444))),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Docked Floating Cart & Pay Bar
            _buildMobileBottomBar(context, cartState, cartNotifier, currency),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileProductsGrid(BuildContext context, List<Product> products, String currency) {
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
        return _buildProductCard(context, product, currency);
      },
    );
  }

  Widget _buildMobileBottomBar(BuildContext context, CartState cartState, CartNotifier cartNotifier, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final totalItems = cartState.items.fold<int>(0, (sum, i) => sum + i.quantity);
    final total = cartNotifier.total;
    final hasItems = cartState.items.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1,
        ),
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
                          color: hasItems ? primaryColor.withValues(alpha: 0.12) : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.shopping_bag_outlined,
                          color: hasItems ? primaryColor : theme.colorScheme.onSurfaceVariant,
                          size: 20,
                        ),
                      ),
                      if (totalItems > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$totalItems',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
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
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: hasItems ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          hasItems ? '$totalItems item${totalItems > 1 ? "s" : ""} • Tap to view' : 'Tap item or scan',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: hasItems ? primaryColor : theme.colorScheme.onSurfaceVariant,
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
              backgroundColor: primaryColor,
              disabledBackgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
              foregroundColor: Colors.white,
              disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.payments_rounded, size: 18),
                const SizedBox(width: 6),
                Text(
                  'PAY NOW',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shopping_cart_outlined, color: theme.colorScheme.primary, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'ORDER REVIEW',
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                            ),
                          ],
                        ),
                        if (activeCartState.items.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              activeCartNotifier.clearCart();
                              Navigator.pop(ctx);
                            },
                            child: const Text('Clear All', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                  ),
                  Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), height: 1),

                  // Cart Items
                  Expanded(
                    child: activeCartState.items.isEmpty
                        ? Center(
                            child: Text('Cart is empty', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: activeCartState.items.length,
                            itemBuilder: (context, index) =>
                                _buildCartRow(context, activeCartState.items[index], activeCartNotifier, currency),
                          ),
                  ),

                  // Order Summary & Checkout Trigger
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF162032) : const Color(0xFFF8F9FB),
                      border: Border(top: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildOrderSummary(context, activeCartState, activeCartNotifier, currency),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: activeCartState.items.isEmpty
                                ? null
                                : () {
                                    Navigator.pop(ctx);
                                    _showMobileCheckoutSheet(context, activeCartNotifier, currency);
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: Text(
                              'PROCEED TO PAY (${CurrencyFormatter.format(activeCartNotifier.total, currency)})',
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    setState(() {
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
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle
                  Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 8),
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.payments_rounded, color: theme.colorScheme.primary, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'PAYMENT CHECKOUT',
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurfaceVariant),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), height: 1),

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
                                  context,
                                  'CASH',
                                  Icons.payments_rounded,
                                  theme.colorScheme.primary,
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
                                  context,
                                  'MOBILE MONEY',
                                  Icons.phone_android_rounded,
                                  const Color(0xFFF59E0B),
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
                                  context,
                                  'CARD',
                                  Icons.credit_card_rounded,
                                  const Color(0xFF3B82F6),
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
                            _buildTenderDisplay(context, currency),
                            const SizedBox(height: 14),

                            // Note shortcuts
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildNoteChip(context, 20, currency, () => setModalState(() => _tenderedAmount += 20)),
                                  const SizedBox(width: 6),
                                  _buildNoteChip(context, 50, currency, () => setModalState(() => _tenderedAmount += 50)),
                                  const SizedBox(width: 6),
                                  _buildNoteChip(context, 100, currency, () => setModalState(() => _tenderedAmount += 100)),
                                  const SizedBox(width: 6),
                                  _buildNoteChip(context, 200, currency, () => setModalState(() => _tenderedAmount += 200)),
                                  const SizedBox(width: 6),
                                  _buildNoteChip(context, 500, currency, () => setModalState(() => _tenderedAmount += 500)),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => setModalState(() => _tenderedAmount = total),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'EXACT (${CurrencyFormatter.format(total, currency)})',
                                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
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
                              child: _buildMobileKeypad(context, (key) {
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
                            _buildDigitalPaymentPrompt(context, currency),
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
                      height: 48,
                      child: ElevatedButton(
                        onPressed: (canComplete && !_isProcessingPayment)
                            ? () async {
                                Navigator.pop(ctx);
                                await _finalizeSale(cartNotifier);
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          disabledBackgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                          foregroundColor: Colors.white,
                          disabledForegroundColor: theme.colorScheme.onSurfaceVariant,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: _isProcessingPayment
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : Text(
                                'COMPLETE SALE & PRINT RECEIPT',
                                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5),
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
    BuildContext context,
    String method,
    IconData icon,
    Color color,
    bool isSelected,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant, size: 18),
            const SizedBox(height: 4),
            Text(
              method == 'MOBILE MONEY' ? 'M-MONEY' : method,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoteChip(BuildContext context, double amount, String currency, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '+${CurrencyFormatter.format(amount, currency)}',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _buildMobileKeypad(BuildContext context, ValueChanged<String> onKeyPress) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget buildBtn(String label, {Color? textColor, Color? bgColor}) {
      return Expanded(
        child: Material(
          color: bgColor ?? (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => onKeyPress(label),
            borderRadius: BorderRadius.circular(8),
            child: Center(
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textColor ?? theme.colorScheme.onSurface,
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
              buildBtn('C', textColor: const Color(0xFFEF4444)), const SizedBox(width: 6),
              buildBtn('0'), const SizedBox(width: 6),
              buildBtn('⌫', textColor: const Color(0xFFF59E0B)),
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

  // --- Clean Category Filter Ribbon ---

  Widget _buildCategoryRibbon(BuildContext context, List<Category> categories) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // ALL Category Chip
          _buildCategoryChip(
            context,
            label: 'ALL ITEMS',
            isSelected: _selectedCategoryId == null,
            onTap: () => setState(() => _selectedCategoryId = null),
          ),
          const SizedBox(width: 6),
          ...categories.map((cat) {
            final isSelected = _selectedCategoryId == cat.id;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _buildCategoryChip(
                context,
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

  Widget _buildCategoryChip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : (isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? Colors.white : theme.colorScheme.onSurface,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // --- Products Grid View ---

  Widget _buildProductsGrid(BuildContext context, List<Product> products, String currency) {
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
        return _buildProductCard(context, product, currency);
      },
    );
  }

  Widget _buildProductCard(BuildContext context, Product product, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final cardBg = isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);

    final isOutOfStock = product.stockLevel <= 0;
    
    final hasDiscount = product.discountPrice != null && 
        product.discountStartDate != null && 
        product.discountEndDate != null &&
        DateTime.now().isAfter(product.discountStartDate!) && 
        DateTime.now().isBefore(product.discountEndDate!);

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _handleProductSelection(product),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isOutOfStock 
                  ? const Color(0xFFDC2626).withValues(alpha: 0.4) 
                  : borderColor,
              width: 1,
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
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: (product.imagePath != null && File(product.imagePath!).existsSync())
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(product.imagePath!), fit: BoxFit.cover),
                          )
                        : Icon(Icons.inventory_2_outlined, color: primaryColor, size: 16),
                  ),
                  if (isOutOfStock)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'OUT',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFDC2626),
                          letterSpacing: 0.3,
                        ),
                      ),
                    )
                  else if (product.isWeighted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.scale_rounded, color: primaryColor, size: 10),
                          const SizedBox(width: 2),
                          Text(
                            product.unitOfMeasure.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (hasDiscount)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'PROMO',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Product Name & SKU
              Text(
                product.name,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: isOutOfStock ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '#${product.sku}',
                style: GoogleFonts.inter(
                  fontSize: 9.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),

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
                            style: TextStyle(
                              fontSize: 9.5,
                              color: theme.colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          Text(
                            '${CurrencyFormatter.format(product.discountPrice!, currency)}${product.isWeighted ? "/${product.unitOfMeasure}" : ""}',
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ] else ...[
                          Text(
                            '${CurrencyFormatter.format(product.price, currency)}${product.isWeighted ? "/${product.unitOfMeasure}" : ""}',
                            style: GoogleFonts.inter(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: isOutOfStock ? theme.colorScheme.onSurfaceVariant : primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: isOutOfStock
                          ? (isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9))
                          : primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOutOfStock ? Icons.block_rounded : (product.isWeighted ? Icons.scale_rounded : Icons.add),
                      color: isOutOfStock ? theme.colorScheme.onSurfaceVariant : Colors.white,
                      size: 14,
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

  // --- Products List View ---

  Widget _buildProductsList(BuildContext context, List<Product> products, String currency) {
    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final product = products[index];
        final isOutOfStock = product.stockLevel <= 0;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final primaryColor = theme.colorScheme.primary;
        final cardBg = isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF);
        final borderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);
        
        final hasDiscount = product.discountPrice != null && 
            product.discountStartDate != null && 
            product.discountEndDate != null &&
            DateTime.now().isAfter(product.discountStartDate!) && 
            DateTime.now().isBefore(product.discountEndDate!);

        return Material(
          color: cardBg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => _handleProductSelection(product),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isOutOfStock 
                      ? const Color(0xFFDC2626).withValues(alpha: 0.3) 
                      : borderColor,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: (product.imagePath != null && File(product.imagePath!).existsSync())
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(product.imagePath!), fit: BoxFit.cover),
                          )
                        : Icon(Icons.inventory_2_outlined, color: primaryColor, size: 16),
                  ),
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
                            color: isOutOfStock ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              '#${product.sku}',
                              style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            if (isOutOfStock) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• Out of Stock',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFDC2626),
                                ),
                              ),
                            ] else if (hasDiscount) ...[
                              const SizedBox(width: 8),
                              Text(
                                '• On Promo',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFD97706),
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
                          style: TextStyle(fontSize: 9.5, color: theme.colorScheme.onSurfaceVariant, decoration: TextDecoration.lineThrough),
                        ),
                        Text(
                          CurrencyFormatter.format(product.discountPrice!, currency),
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: primaryColor),
                        ),
                      ] else ...[
                        Text(
                          CurrencyFormatter.format(product.price, currency),
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: primaryColor),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: isOutOfStock ? (isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9)) : primaryColor,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isOutOfStock ? Icons.block_rounded : Icons.add, 
                      color: isOutOfStock ? theme.colorScheme.onSurfaceVariant : Colors.white, 
                      size: 14,
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

  Widget _buildEmptyCatalogState(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(
            'No matching products found',
            style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (_searchController.text.isNotEmpty || _selectedCategoryId != null)
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() => _selectedCategoryId = null);
              },
              icon: Icon(Icons.clear_all_rounded, size: 16, color: primaryColor),
              label: Text('Clear Filters', style: TextStyle(color: primaryColor, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }

  Widget _buildViewModeBtn(
    BuildContext context, {
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildPanelHeader(BuildContext context, IconData icon, String title, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 8),
        Text(title, style: _headerTextStyle(context)),
      ],
    );
  }

  TextStyle _headerTextStyle(BuildContext context) {
    final theme = Theme.of(context);
    return GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.0,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  InputDecoration _searchInputDecoration(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return InputDecoration(
      hintText: 'Search product name or SKU...',
      hintStyle: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
      prefixIcon: Icon(Icons.search_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
      suffixIcon: _searchController.text.isNotEmpty
          ? IconButton(
              icon: Icon(Icons.close_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
              onPressed: () {
                _searchController.clear();
                setState(() {});
              },
            )
          : null,
      filled: true,
      fillColor: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
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
    );
  }

  Widget _buildEmptyState(BuildContext context, String message, {IconData icon = Icons.search_off_rounded}) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Text(message, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodSelector(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Row(
      children: [
        _buildCompactMethodBtn(context, 'CASH', Icons.payments_rounded, primaryColor),
        const SizedBox(width: 8),
        _buildCompactMethodBtn(context, 'MOBILE MONEY', Icons.phone_android_rounded, const Color(0xFFD97706)),
        const SizedBox(width: 8),
        _buildCompactMethodBtn(context, 'CARD', Icons.credit_card_rounded, const Color(0xFF0284C7)),
      ],
    );
  }

  Widget _buildCompactMethodBtn(BuildContext context, String method, IconData icon, Color color) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
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
          duration: const Duration(milliseconds: 150),
          height: 46,
          decoration: BoxDecoration(
            color: isSelected ? color : (isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isSelected ? Colors.white : theme.colorScheme.onSurfaceVariant,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                method == 'MOBILE MONEY' ? 'M-MONEY' : method,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumericKeypad(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              _buildKey(context, '1'), const SizedBox(width: 4),
              _buildKey(context, '2'), const SizedBox(width: 4),
              _buildKey(context, '3'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              _buildKey(context, '4'), const SizedBox(width: 4),
              _buildKey(context, '5'), const SizedBox(width: 4),
              _buildKey(context, '6'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              _buildKey(context, '7'), const SizedBox(width: 4),
              _buildKey(context, '8'), const SizedBox(width: 4),
              _buildKey(context, '9'),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Row(
            children: [
              _buildKey(context, '0'), const SizedBox(width: 4),
              _buildKey(context, '00'), const SizedBox(width: 4),
              _buildClearKey(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKey(BuildContext context, String label) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Material(
        color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(8),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClearKey(BuildContext context) {
    return Expanded(
      child: Material(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => setState(() => _tenderedAmount = 0),
          onLongPress: () => setState(() => _tenderedAmount = 0),
          borderRadius: BorderRadius.circular(8),
          child: const Center(child: Icon(Icons.backspace_rounded, color: Color(0xFFDC2626), size: 16)),
        ),
      ),
    );
  }

  Widget _buildExactAmountBtn(BuildContext context, CartNotifier cartNotifier, String currency) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Material(
      color: primaryColor.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => setState(() => _tenderedAmount = cartNotifier.total),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          child: Text(
            'EXACT',
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: primaryColor),
          ),
        ),
      ),
    );
  }

  Widget _buildDigitalPaymentPrompt(BuildContext context, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final total = ref.read(cartProvider.notifier).total;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _selectedPaymentMethod == 'CARD' ? Icons.credit_card_rounded : Icons.phone_android_rounded,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'PLEASE PROCESS ON MERCHANT DEVICE',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            CurrencyFormatter.format(total, currency),
            style: GoogleFonts.inter(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16),
                const SizedBox(width: 6),
                Text(
                  'READY FOR CONFIRMATION',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF059669),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteSaleButton(BuildContext context, CartNotifier cartNotifier) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final total = cartNotifier.total;
    final isCash = _selectedPaymentMethod == 'CASH';
    final shortAmount = total - _tenderedAmount;
    final canComplete = !isCash || (_tenderedAmount >= total);
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'ZK';

    if (_isProcessingPayment) {
      return Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF059669),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
            ),
            const SizedBox(width: 12),
            Text(
              'PROCESSING TRANSACTION...',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
            ),
          ],
        ),
      );
    }

    if (!canComplete) {
      return Container(
        height: 52,
        width: double.infinity,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.5)),
        ),
        child: InkWell(
          onTap: () {
            setState(() => _tenderedAmount = total);
          },
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _tenderedAmount == 0 
                      ? 'ENTER CASH TENDER AMOUNT (TAP FOR EXACT)' 
                      : 'SHORT BY ${CurrencyFormatter.format(shortAmount, currency)} (TAP FOR EXACT)',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFD97706)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => _finalizeSale(cartNotifier),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF059669),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 2,
          shadowColor: const Color(0xFF059669).withValues(alpha: 0.4),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              'COMPLETE SALE',
              style: GoogleFonts.inter(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTenderDisplay(BuildContext context, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cartNotifier = ref.read(cartProvider.notifier);
    final total = cartNotifier.total;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Text(
            _selectedPaymentMethod == 'CASH' ? 'TENDERED AMOUNT' : 'TOTAL TO PAY', 
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurfaceVariant)
          ),
          const SizedBox(height: 4),
          Text(
            _selectedPaymentMethod == 'CASH' 
              ? (_tenderedAmount == 0 ? 'ENTER AMOUNT' : CurrencyFormatter.format(_tenderedAmount, currency))
              : CurrencyFormatter.format(total, currency),
            style: GoogleFonts.inter(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: (_selectedPaymentMethod == 'CASH' && _tenderedAmount == 0) ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5) : theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickTenderButton(BuildContext context, double amount, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bool isCash = _selectedPaymentMethod == 'CASH';

    return Material(
      color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: isCash ? () => setState(() => _tenderedAmount += amount) : null,
        borderRadius: BorderRadius.circular(8),
        child: Center(
          child: Text(
            CurrencyFormatter.format(amount, currency),
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
          ),
        ),
      ),
    );
  }

  Widget _buildCartRow(BuildContext context, CartItem item, CartNotifier cartNotifier, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final unit = item.product.unitOfMeasure.toLowerCase().trim();
    final unitLabel = unit.isEmpty ? 'kg' : unit;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
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
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: primaryColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'SCALE',
                          style: GoogleFonts.inter(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        item.product.name,
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface, fontSize: 12.5),
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
                  style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildQtyActionBtn(
                  context,
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
                    constraints: const BoxConstraints(minWidth: 36),
                    alignment: Alignment.center,
                    child: Text(
                      item.isWeighted
                          ? '${item.weight.toStringAsFixed(2)} $unitLabel'
                          : '${item.quantity}',
                      style: GoogleFonts.inter(
                        fontSize: item.isWeighted ? 12 : 14,
                        fontWeight: FontWeight.w800,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ),
                _buildQtyActionBtn(
                  context,
                  Icons.add_rounded,
                  () => item.isWeighted
                      ? _handleProductSelection(item.product)
                      : cartNotifier.updateQuantity(item.product.id, 1),
                ),
              ],
            ),
          ),
          
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 16),
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
        title: Text('Edit Quantity', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(border: InputBorder.none),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQty = int.tryParse(controller.text) ?? 1;
              cartNotifier.setQuantity(item.product.id, newQty);
              Navigator.pop(ctx);
            },
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
  }

  Widget _buildQtyActionBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: theme.colorScheme.onSurfaceVariant, size: 14),
        ),
      ),
    );
  }

  Widget _buildOrderSummary(BuildContext context, CartState cartState, CartNotifier cartNotifier, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          // B2B Corporate / Tax Invoice Customer TPIN Card
          if (cartState.customerTpin != null && cartState.customerTpin!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.business_rounded, color: Color(0xFF059669), size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('BUYER TPIN: ${cartState.customerTpin}', style: GoogleFonts.inter(color: const Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 11)),
                        if (cartState.customerBusinessName != null)
                          Text(cartState.customerBusinessName!, style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 10)),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => cartNotifier.setCustomerTpin(null),
                    child: Icon(Icons.close, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            )
          else
            InkWell(
              onTap: () => _showB2bCustomerModal(context, cartNotifier, cartState),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.business_rounded, color: primaryColor, size: 14),
                    const SizedBox(width: 6),
                    Text('+ Buyer TPIN / Tax Invoice', style: GoogleFonts.inter(color: primaryColor, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items Subtotal', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
              Text(CurrencyFormatter.format(cartNotifier.subtotal, currency), style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          if (cartNotifier.tax > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('VAT / Tax', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                Text(CurrencyFormatter.format(cartNotifier.tax, currency), style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          if (cartState.serviceChargeEnabled && cartNotifier.serviceChargeAmount > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'Service Charge (${cartState.serviceChargeRate.toStringAsFixed(0)}% • Untaxed)',
                      style: GoogleFonts.inter(color: primaryColor, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => cartNotifier.toggleServiceCharge(false),
                      child: Icon(Icons.close, size: 14, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                Text(
                  CurrencyFormatter.format(cartNotifier.serviceChargeAmount, currency),
                  style: GoogleFonts.inter(color: primaryColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _showServiceChargeModal(context, cartNotifier, cartState),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('+ Service Charge (Untaxed)', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                    Text('0%', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
          if (cartState.discountAmount > 0) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Discount', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                Text('- ${CurrencyFormatter.format(cartState.discountAmount, currency)}', style: GoogleFonts.inter(color: const Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TOTAL DUE', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
              Text(
                CurrencyFormatter.format(cartNotifier.total, currency),
                style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w900, color: primaryColor),
              ),
            ],
          ),
          if (cartState.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildCompleteSaleButton(context, cartNotifier),
          ],
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
        builder: (context, setModalState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final dialogBg = isDark ? const Color(0xFF151F32) : Colors.white;
          final borderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);
          final fieldBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
          const primaryAccent = Color(0xFF1D4ED8);

          return AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor),
            ),
            title: Row(
              children: [
                const Icon(Icons.business_rounded, color: primaryAccent),
                const SizedBox(width: 10),
                Text('BUYER TPIN / TAX INVOICE', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Enter the corporate buyer's ZRA TPIN to issue an official Tax Invoice for VAT claim.",
                    style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
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
                        style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
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
                              ? const Color(0xFFECFDF5)
                              : fieldBg,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isVerified
                                  ? const Color(0xFF059669)
                                  : verifyError != null
                                      ? const Color(0xFFDC2626)
                                      : borderColor,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isVerified
                                  ? const Color(0xFF059669)
                                  : primaryAccent,
                              width: 1.5,
                            ),
                          ),
                          suffixIcon: isVerifying
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: primaryAccent),
                                  ),
                                )
                              : isVerified
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 22),
                                    )
                                  : TextButton(
                                      onPressed: doVerify,
                                      child: const Text('Verify', style: TextStyle(color: primaryAccent, fontWeight: FontWeight.bold)),
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
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 14),
                          const SizedBox(width: 6),
                          Text(
                            'ZRA Taxpayer Verified',
                            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF059669), fontWeight: FontWeight.w700),
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
                          const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 14),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              verifyError!,
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFD97706), fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Registered Business Name',
                      hintText: 'e.g. ABC Holdings Ltd',
                      filled: true,
                      fillColor: fieldBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addrCtrl,
                    style: GoogleFonts.inter(color: Theme.of(context).colorScheme.onSurface),
                    decoration: InputDecoration(
                      labelText: 'Physical Address',
                      hintText: 'e.g. Plot 45, Cairo Road, Lusaka',
                      filled: true,
                      fillColor: fieldBg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
                style: ElevatedButton.styleFrom(backgroundColor: primaryAccent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                child: const Text('Apply to Invoice'),
              ),
            ],
          );
        },
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
      
      // Clear cart & reset payment state immediately so sale is marked done and cart is ready for next sale
      cartNotifier.clear();
      if (mounted) {
        setState(() {
          _tenderedAmount = 0;
          _selectedPaymentMethod = '';
        });
      }

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
      // Handled inside try-catch so printer hardware disconnection (e.g. Bluetooth error) does not abort completed sale flow
      bool printSuccess = true;
      String? printErrorMessage;
      if (config?.autoPrintReceipt != false) {
        try {
          await printer.printReceipt(transaction, saleItems, config: config);
          if (hasDigitax && !fiscalized) {
            _scheduleDigitaxFiscalRefreshAndPrint(transaction, saleItems);
          }
        } catch (e) {
          printSuccess = false;
          printErrorMessage = e.toString().replaceAll("Exception: ", "");
          debugPrint('Receipt print error notice: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Sale saved! Receipt print error: $printErrorMessage'),
                backgroundColor: const Color(0xFFD97706),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      }

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final dialogBg = isDark ? const Color(0xFF151F32) : Colors.white;
        final borderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);
        const primaryAccent = Color(0xFF1D4ED8);

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: dialogBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor),
            ),
            title: Text('Sale Complete', style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.onSurface, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change Due: ${CurrencyFormatter.format(change, config?.currencySymbol ?? "ZK")}', 
                  style: GoogleFonts.inter(color: const Color(0xFF059669), fontSize: 22, fontWeight: FontWeight.w900),
                ),
                if (!printSuccess && printErrorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDC2626).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.print_disabled_rounded, color: Color(0xFFDC2626), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Print Failed: $printErrorMessage',
                            style: GoogleFonts.inter(color: const Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (hasDigitax && !fiscalized) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD97706).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD97706).withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'DigiTax Fiscalizing... Receipt will print automatically',
                          style: GoogleFonts.inter(color: const Color(0xFFD97706), fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              if (!printSuccess) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await printer.printReceipt(transaction, saleItems, config: config);
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('Receipt printed successfully!'), backgroundColor: Color(0xFF059669)),
                        );
                      }
                    } catch (err) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('Print retry failed: ${err.toString().replaceAll("Exception: ", "")}'), backgroundColor: const Color(0xFFDC2626)),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: Text('RETRY PRINT', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11)),
                ),
              ],
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _searchFocusNode.requestFocus();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                child: Text('NEW SALE', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 12)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFDC2626)));
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
