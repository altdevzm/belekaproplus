import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/customer_display_provider.dart';
import 'package:beleka_pos/providers/restaurant_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/screens/restaurant/customer_display_screen.dart';
import 'package:beleka_pos/screens/restaurant/restaurant_modal_widgets.dart';
import 'package:beleka_pos/screens/shell_screen.dart';
import 'package:beleka_pos/widgets/food_3d_visualizer.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/restaurant_service.dart';
import 'package:beleka_pos/services/sync_service.dart';

class OrderEntryScreen extends ConsumerStatefulWidget {
  const OrderEntryScreen({super.key});

  @override
  ConsumerState<OrderEntryScreen> createState() => _OrderEntryScreenState();
}

class _OrderEntryScreenState extends ConsumerState<OrderEntryScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _ticketTenderedCtrl = TextEditingController();
  int? _lastTenderOrderId;
  int? _selectedCategoryId;
  bool _isSettling = false;
  int _mobileTab = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      ref.read(syncServiceProvider).syncMetadata();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _ticketTenderedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandColor = theme.colorScheme.primary;
    final config = ref.watch(storeConfigProvider).valueOrNull;
    final currency = config?.currencySymbol ?? 'ZK';
    final ordersAsync = ref.watch(activeRestaurantOrdersProvider);
    final selectedOrderId = ref.watch(selectedRestaurantOrderIdProvider);
    final productsAsync = ref.watch(restaurantProductsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final activeOrders = ordersAsync.valueOrNull ?? [];
    RestaurantOrder? currentOrder;
    if (selectedOrderId != null) {
      currentOrder =
          activeOrders.where((o) => o.id == selectedOrderId).firstOrNull;
    }
    currentOrder ??= activeOrders.firstOrNull;
    final syncedOrder = ref.read(customerDisplayProvider).activeOrder;
    if (syncedOrder?.id != currentOrder?.id ||
        syncedOrder?.totalAmount != currentOrder?.totalAmount) {
      final targetOrder = currentOrder;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(customerDisplayProvider.notifier).setOrder(targetOrder);
        }
      });
    }

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.f1): () {
          ref.read(navigationProvider.notifier).state =
              ScreenType.restaurantTables;
        },
        const SingleActivator(LogicalKeyboardKey.f2): () {
          if (config?.restaurantCounterServiceEnabled ?? true) {
            _createCounterOrder();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f3): () {
          _searchFocusNode.requestFocus();
        },
        const SingleActivator(LogicalKeyboardKey.slash): () {
          if (!_searchFocusNode.hasFocus) {
            _searchFocusNode.requestFocus();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f7): () {
          if (currentOrder != null) {
            _printCurrentPreBill(currentOrder, config);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f8): () {
          if (currentOrder != null) {
            _sendOrderByIdToKitchen(currentOrder, config);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f9): () {
          if (currentOrder != null && !_isSettling) {
            _startSettlementFromShortcut(currentOrder, currency, config);
          }
        },
        const SingleActivator(LogicalKeyboardKey.f12): () {
          if (currentOrder != null && !_isSettling) {
            _startSettlementFromShortcut(currentOrder, currency, config);
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 820;

              final menuPanel = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Bar: Order Switcher & Action Buttons
                  if (activeOrders.isNotEmpty)
                    SizedBox(
                      height: 44,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: activeOrders.map((o) {
                          final selected = currentOrder?.id == o.id;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(
                                o.tableName != null
                                    ? '${o.tableName} (${o.orderNumber})'
                                    : 'Takeaway ${o.orderNumber}',
                              ),
                              selected: selected,
                              onSelected: (_) {
                                ref
                                    .read(
                                      selectedRestaurantOrderIdProvider
                                          .notifier,
                                    )
                                    .state = o.id;
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  if (activeOrders.isNotEmpty) const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          ref.read(navigationProvider.notifier).state =
                              ScreenType.restaurantTables;
                        },
                        icon: const Icon(
                          Icons.table_restaurant_rounded,
                          size: 18,
                        ),
                        label: Text(isCompact ? 'Tables' : 'Tables [F1]'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          ref
                              .read(customerDisplayProvider.notifier)
                              .setOrder(currentOrder);
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const CustomerDisplayScreen(),
                            ),
                          );
                        },
                        icon: const Icon(
                          Icons.desktop_windows_rounded,
                          size: 18,
                        ),
                        label: const Text('Client Screen'),
                      ),
                      if (config?.restaurantCounterServiceEnabled ?? true)
                        ElevatedButton.icon(
                          onPressed: _createCounterOrder,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(
                            isCompact ? 'New Takeaway' : 'New Takeaway [F2]',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandColor,
                            foregroundColor: Colors.black,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search & Category Filter
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: isCompact
                          ? 'Search menu items...'
                          : 'Search menu items... [F3]',
                      prefixIcon: const Icon(Icons.search_rounded),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  categoriesAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                    data: (cats) => SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: const Text('All'),
                            selected: _selectedCategoryId == null,
                            onSelected: (_) =>
                                setState(() => _selectedCategoryId = null),
                          ),
                          const SizedBox(width: 8),
                          ...cats.map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(c.name),
                                selected: _selectedCategoryId == c.id,
                                onSelected: (_) =>
                                    setState(() => _selectedCategoryId = c.id),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Menu Grid
                  Expanded(
                    child: productsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (products) {
                        final q = _searchController.text.trim().toLowerCase();
                        final menuItems = products.where((p) {
                          if (!p.isAvailableNow) {
                            return false;
                          }
                          if (p.restaurantProductType != 'menu_item' &&
                              p.restaurantProductType != 'both') {
                            return false;
                          }
                          if (_selectedCategoryId != null &&
                              p.categoryId != _selectedCategoryId) {
                            return false;
                          }
                          if (q.isNotEmpty &&
                              !p.name.toLowerCase().contains(q) &&
                              !p.sku.toLowerCase().contains(q)) {
                            return false;
                          }
                          return true;
                        }).toList();

                        if (menuItems.isEmpty) {
                          return const Center(
                            child: Text('No available menu items match.'),
                          );
                        }

                        return GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: isCompact ? 175 : 205,
                            mainAxisExtent: isCompact ? 176 : 194,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: menuItems.length,
                          itemBuilder: (_, idx) {
                            final p = menuItems[idx];
                            return InkWell(
                              onTap: () => _onProductTap(
                                currentOrder,
                                p,
                                currency,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        width: double.infinity,
                                        color: theme.colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.35),
                                        child: _buildDishImage(
                                          p.imagePath,
                                          theme,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        10,
                                        8,
                                        10,
                                        10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            p.name,
                                            style: GoogleFonts.manrope(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                '$currency ${p.price.toStringAsFixed(2)}',
                                                style: GoogleFonts.ibmPlexMono(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 12.5,
                                                  color: brandColor,
                                                ),
                                              ),
                                              Text(
                                                '${p.prepTimeMinutes}m',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  color: theme.colorScheme
                                                      .onSurfaceVariant,
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
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );

              final ticketPanel = Container(
                padding: EdgeInsets.all(isCompact ? 12 : 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: currentOrder == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              isCompact
                                  ? 'Tap any menu item to start\na Takeaway Order'
                                  : 'Tap any menu item to start\na Takeaway Order, or press [F2]',
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : _buildOrderTicketPanel(
                        context,
                        currentOrder,
                        currency,
                        config,
                      ),
              );

              if (isCompact) {
                return Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      SegmentedButton<int>(
                        segments: [
                          const ButtonSegment(
                            value: 0,
                            icon: Icon(Icons.restaurant_menu_rounded, size: 18),
                            label: Text('Menu'),
                          ),
                          ButtonSegment(
                            value: 1,
                            icon: const Icon(
                              Icons.receipt_long_rounded,
                              size: 18,
                            ),
                            label: Text(
                              currentOrder == null
                                  ? 'Ticket'
                                  : 'Ticket (${currentOrder.orderNumber})',
                            ),
                          ),
                        ],
                        selected: {_mobileTab},
                        onSelectionChanged: (s) =>
                            setState(() => _mobileTab = s.first),
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        child: _mobileTab == 0 ? menuPanel : ticketPanel,
                      ),
                      if (_mobileTab == 0 && currentOrder != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: brandColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      currentOrder.tableName ??
                                          'Takeaway ${currentOrder.orderNumber}',
                                      style: GoogleFonts.manrope(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      '$currency ${currentOrder.totalAmount.toStringAsFixed(2)}',
                                      style: GoogleFonts.ibmPlexMono(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: brandColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () =>
                                    setState(() => _mobileTab = 1),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: brandColor,
                                  foregroundColor: Colors.black,
                                ),
                                icon: const Icon(
                                  Icons.receipt_long_rounded,
                                  size: 18,
                                ),
                                label: const Text('View Ticket'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(flex: 6, child: menuPanel),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: ticketPanel),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildShortcutBar(theme),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDishImage(String? imagePath, ThemeData theme) {
    if (imagePath != null && imagePath.isNotEmpty) {
      if (imagePath.startsWith('data:image')) {
        final commaIdx = imagePath.indexOf(',');
        if (commaIdx != -1) {
          try {
            final bytes = base64Decode(imagePath.substring(commaIdx + 1));
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _dishPlaceholderIcon(theme),
            );
          } catch (_) {}
        }
      } else {
        final f = File(imagePath);
        if (f.existsSync()) {
          return Image.file(
            f,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _dishPlaceholderIcon(theme),
          );
        }
      }
    }
    return _dishPlaceholderIcon(theme);
  }

  Widget _dishPlaceholderIcon(ThemeData theme) {
    return Icon(
      Icons.fastfood_rounded,
      size: 32,
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
    );
  }

  Widget _buildShortcutBar(ThemeData theme) {
    const shortcuts = [
      'F1 Tables',
      'F2 New Takeaway',
      'F3 Search',
      'F7 Pre-Bill',
      'F8 Send Kitchen',
      'F9/F12 Pay & ZRA Receipt',
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 4,
        children: shortcuts
            .map(
              (s) => Text(
                s,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildOrderTicketPanel(
    BuildContext context,
    RestaurantOrder order,
    String currency,
    StoreConfig? config,
  ) {
    final theme = Theme.of(context);
    final svc = ref.watch(restaurantServiceProvider);

    return StreamBuilder<List<RestaurantOrderItem>>(
      stream: svc.watchOrderItems(order.id),
      builder: (context, snap) {
        final items = snap.data ?? [];
        final remaining =
            (order.totalAmount - order.paidAmount).clamp(0.0, double.infinity);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.tableName != null
                            ? '${order.tableName} • ${order.orderNumber}'
                            : 'Order ${order.orderNumber} (Takeaway)',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Status: ${_orderStatusLabel(order.status)} • Staff: ${order.waiterName ?? 'Staff'}',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Print KOT',
                  onPressed: items.isEmpty
                      ? null
                      : () async {
                          final stations =
                              ref.read(kitchenStationsProvider).valueOrNull ??
                                  [];
                          await PrinterService().printRoutedKitchenTickets(
                            order: order,
                            items: items,
                            stations: stations,
                            config: config,
                          );
                        },
                  icon: const Icon(Icons.print_rounded),
                ),
                IconButton(
                  tooltip: 'Print Pre-Bill [F7]',
                  onPressed: items.isEmpty
                      ? null
                      : () async {
                          await PrinterService().printPreBill(
                            order: order,
                            items: items,
                            config: config,
                          );
                        },
                  icon: const Icon(Icons.receipt_outlined),
                ),
              ],
            ),
            const Divider(height: 18),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Tap menu items on the left to add.'))
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 10),
                      itemBuilder: (_, idx) {
                        final item = items[idx];
                        final mods = RestaurantService.decodeModifiers(
                          item.modifiersJson,
                        );
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.quantity}x ${item.productName}',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (mods.isNotEmpty)
                                    Text(
                                      mods
                                          .map((m) {
                                            final p =
                                                (m['price'] as num?)?.toDouble() ??
                                                    0.0;
                                            return p > 0
                                                ? '${m['name']} (+$currency ${p.toStringAsFixed(0)})'
                                                : '${m['name']}';
                                          })
                                          .join(', '),
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  if (item.specialInstructions != null &&
                                      item.specialInstructions!.isNotEmpty)
                                    Text(
                                      'Note: ${item.specialInstructions}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  Text(
                                    _kitchenStatusLabel(item.kitchenStatus),
                                    style: GoogleFonts.inter(
                                      fontSize: 10.5,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '$currency ${(item.unitPrice * item.quantity).toStringAsFixed(2)}',
                              style: GoogleFonts.ibmPlexMono(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                            if (item.kitchenStatus ==
                                KitchenItemStatus.newTicket)
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => svc.removeOrderItem(item.id),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            const Divider(height: 16),
            _totalRow(
              'Subtotal',
              '$currency ${order.subtotal.toStringAsFixed(2)}',
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Service Charge',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: items.isEmpty
                          ? null
                          : () => _showCustomServiceChargeDialog(
                              order,
                              currency,
                              config,
                            ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(0, 38),
                        side: BorderSide(
                          color: order.serviceChargeAmount > 0
                              ? const Color(0xFF10B981)
                              : theme.colorScheme.primary,
                        ),
                      ),
                      icon: Icon(
                        order.serviceChargeAmount > 0
                            ? Icons.edit_rounded
                            : Icons.add_rounded,
                        size: 16,
                        color: order.serviceChargeAmount > 0
                            ? const Color(0xFF10B981)
                            : theme.colorScheme.primary,
                      ),
                      label: Text(
                        order.serviceChargeAmount > 0
                            ? 'Edit / Clear'
                            : 'Add Service Charge',
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: order.serviceChargeAmount > 0
                              ? const Color(0xFF10B981)
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '$currency ${order.serviceChargeAmount.toStringAsFixed(2)}',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            _totalRow(
              'VAT (Incl.)',
              '$currency ${order.taxAmount.toStringAsFixed(2)}',
            ),
            if (order.paidAmount > 0)
              _totalRow(
                'Already Paid',
                '- $currency ${order.paidAmount.toStringAsFixed(2)}',
              ),
            const SizedBox(height: 4),
            _totalRow(
              order.paidAmount > 0 ? 'Balance Due' : 'Total',
              '$currency ${remaining.toStringAsFixed(2)}',
              isBold: true,
            ),
            const SizedBox(height: 10),
            Builder(
              builder: (context) {
                if (_lastTenderOrderId != order.id) {
                  _lastTenderOrderId = order.id;
                  _ticketTenderedCtrl.clear();
                }
                final tenderedVal =
                    double.tryParse(_ticketTenderedCtrl.text.trim()) ?? 0.0;
                final changeVal = tenderedVal - remaining;
                final hasTenderInput = _ticketTenderedCtrl.text.trim().isNotEmpty;

                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _ticketTenderedCtrl,
                              onChanged: (_) => setState(() {}),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Amount Given ($currency)',
                                hintText: remaining.toStringAsFixed(2),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 10,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                suffixIcon: hasTenderInput
                                    ? IconButton(
                                        tooltip: 'Clear',
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 16,
                                        ),
                                        onPressed: () => setState(
                                          () => _ticketTenderedCtrl.clear(),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: (!hasTenderInput
                                      ? theme.colorScheme.surface
                                      : (changeVal >= -0.001
                                          ? const Color(0xFF10B981)
                                          : Colors.redAccent))
                                  .withValues(alpha: hasTenderInput ? 0.16 : 0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: !hasTenderInput
                                    ? theme.colorScheme.outline
                                        .withValues(alpha: 0.2)
                                    : (changeVal >= -0.001
                                        ? const Color(0xFF10B981)
                                        : Colors.redAccent),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  !hasTenderInput || changeVal >= -0.001
                                      ? 'Change Due'
                                      : 'Short By',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: !hasTenderInput
                                        ? theme.colorScheme.onSurfaceVariant
                                        : (changeVal >= -0.001
                                            ? const Color(0xFF10B981)
                                            : Colors.redAccent),
                                  ),
                                ),
                                Text(
                                  '$currency ${hasTenderInput ? changeVal.abs().toStringAsFixed(2) : '0.00'}',
                                  style: GoogleFonts.ibmPlexMono(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w900,
                                    color: !hasTenderInput
                                        ? theme.colorScheme.onSurface
                                        : (changeVal >= -0.001
                                            ? const Color(0xFF10B981)
                                            : Colors.redAccent),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            label: Text(
                              'EXACT',
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                              ),
                            ),
                            backgroundColor: theme.colorScheme.primary,
                            visualDensity: VisualDensity.compact,
                            onPressed: items.isEmpty
                                ? null
                                : () => setState(() {
                                      _ticketTenderedCtrl.text =
                                          remaining.toStringAsFixed(2);
                                    }),
                          ),
                          for (final note in const [
                            1,
                            2,
                            5,
                            10,
                            20,
                            50,
                            100,
                            200,
                            500,
                          ])
                            ActionChip(
                              label: Text(
                                '$currency$note',
                                style: GoogleFonts.ibmPlexMono(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              visualDensity: VisualDensity.compact,
                              onPressed: items.isEmpty
                                  ? null
                                  : () => setState(() {
                                        final cur = double.tryParse(
                                              _ticketTenderedCtrl.text.trim(),
                                            ) ??
                                            0.0;
                                        _ticketTenderedCtrl.text =
                                            (cur + note).toStringAsFixed(2);
                                      }),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (order.serviceType != RestaurantServiceType.counter) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: items.isEmpty
                          ? null
                          : () => _sendToKitchen(order, items, config),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text(
                        'Kitchen [F8]',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: items.isEmpty
                        ? null
                        : () async {
                            await svc.requestBill(order.id);
                            await PrinterService().printPreBill(
                              order: order,
                              items: items,
                              config: config,
                            );
                          },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    icon: const Icon(Icons.receipt_outlined, size: 18),
                    label: Text(
                      'Pre-Bill [F7]',
                      style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (items.isEmpty || _isSettling)
                    ? null
                    : () => _showSettlePaymentDialog(
                          order,
                          items,
                          remaining,
                          currency,
                          config,
                          initialTendered: double.tryParse(
                            _ticketTenderedCtrl.text.trim(),
                          ),
                        ),
                icon: _isSettling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.payments_rounded, size: 20),
                label: Text(
                  _isSettling
                      ? 'Processing ZRA...'
                      : 'Pay & ZRA Receipt [F9]',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.black,
                  minimumSize: const Size.fromHeight(54),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _totalRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.ibmPlexMono(
              fontSize: isBold ? 15 : 12.5,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<RestaurantOrder> _createCounterOrder() async {
    final user = ref.read(authProvider);
    final branch = ref.read(activeRestaurantBranchProvider);
    final svc = ref.read(restaurantServiceProvider);
    final order = await svc.createCounterOrder(
      branchCode: branch,
      waiterId: user?.id,
      waiterName: user?.name ?? 'Staff',
    );
    ref.read(selectedRestaurantOrderIdProvider.notifier).state = order.id;
    return order;
  }

  Future<void> _printCurrentPreBill(
    RestaurantOrder order,
    StoreConfig? config,
  ) async {
    final items =
        await ref.read(restaurantServiceProvider).getOrderItems(order.id);
    if (items.isEmpty) {
      return;
    }
    await PrinterService().printPreBill(
      order: order,
      items: items,
      config: config,
    );
  }

  Future<void> _sendOrderByIdToKitchen(
    RestaurantOrder order,
    StoreConfig? config,
  ) async {
    final items =
        await ref.read(restaurantServiceProvider).getOrderItems(order.id);
    if (items.isEmpty) {
      return;
    }
    await _sendToKitchen(order, items, config);
  }

  Future<void> _startSettlementFromShortcut(
    RestaurantOrder order,
    String currency,
    StoreConfig? config,
  ) async {
    final items =
        await ref.read(restaurantServiceProvider).getOrderItems(order.id);
    if (items.isEmpty) {
      return;
    }
    final remaining =
        (order.totalAmount - order.paidAmount).clamp(0.0, double.infinity);
    await _showSettlePaymentDialog(order, items, remaining, currency, config);
  }

  Future<void> _onProductTap(
    RestaurantOrder? currentOrder,
    Product product,
    String currency,
  ) async {
    final order = currentOrder ?? await _createCounterOrder();
    final svc = ref.read(restaurantServiceProvider);
    final modifiers = await svc.getModifiersForProduct(product.id);
    final noteCtrl = TextEditingController();
    final extraNameCtrl = TextEditingController();
    final extraPriceCtrl = TextEditingController(text: '0');
    final selectedMods = <Map<String, dynamic>>[];
    String? lastAddedExtra;
    int animTrigger = 0;

    if (!mounted) {
      noteCtrl.dispose();
      extraNameCtrl.dispose();
      extraPriceCtrl.dispose();
      return;
    }

    final availableExtras = <Map<String, dynamic>>[];
    for (final group in modifiers) {
      try {
        final opts = jsonDecode(group.optionsJson) as List<dynamic>;
        for (final opt in opts.whereType<Map<String, dynamic>>()) {
          availableExtras.add({
            'group': group.name,
            'name': opt['name']?.toString() ?? '',
            'price': (opt['price'] as num?)?.toDouble() ?? 0.0,
            if (opt['imagePath'] != null) 'imagePath': opt['imagePath'],
          });
        }
      } catch (_) {}
    }

    final hasProductImg =
        product.imagePath != null &&
        product.imagePath!.isNotEmpty &&
        File(product.imagePath!).existsSync();
    final hasAnyExtraImg = availableExtras.any((e) {
      final p = e['imagePath']?.toString();
      return p != null && p.isNotEmpty && File(p).existsSync();
    });
    final showVisualStage = hasProductImg || hasAnyExtraImg;

    final displayNotifier = ref.read(customerDisplayProvider.notifier);
    displayNotifier.setOrder(order);
    displayNotifier.previewProduct(
      product,
      extras: const [],
      availableExtras: availableExtras,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => RestaurantModalShell(
          icon: Icons.restaurant_menu_rounded,
          title: product.name,
          subtitle:
              'Base price: $currency ${product.price.toStringAsFixed(2)} • Tap extras to animate 3D preview',
          width: 580,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
              label: const Text('Add to Order'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showVisualStage || selectedMods.isNotEmpty) ...[
                Food3DVisualizer(
                  productName: product.name,
                  productImagePath: product.imagePath,
                  basePrice: product.price,
                  currency: currency,
                  extras: List<Map<String, dynamic>>.from(selectedMods),
                  lastAddedExtraName: lastAddedExtra,
                  animationTrigger: animTrigger,
                  height: 240,
                ),
                const SizedBox(height: 16),
              ],
              ...modifiers.map((group) {
                List<dynamic> opts = [];
                try {
                  opts = jsonDecode(group.optionsJson) as List<dynamic>;
                } catch (_) {}
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    buildModalFieldLabel(ctx, group.name),
                    ...opts.whereType<Map<String, dynamic>>().map((opt) {
                      final name = opt['name']?.toString() ?? '';
                      final price = (opt['price'] as num?)?.toDouble() ?? 0.0;
                      final isChosen = selectedMods.any(
                        (m) => m['group'] == group.name && m['name'] == name,
                      );
                      return CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          price > 0
                              ? '$name (+$currency ${price.toStringAsFixed(2)})'
                              : name,
                        ),
                        value: isChosen,
                        onChanged: (val) {
                          setLocal(() {
                            if (!group.allowMultiple) {
                              selectedMods.removeWhere(
                                (m) => m['group'] == group.name,
                              );
                            }
                            if (val == true) {
                              selectedMods.add({
                                'group': group.name,
                                'name': name,
                                'price': price,
                                if (opt['imagePath'] != null)
                                  'imagePath': opt['imagePath'],
                              });
                              lastAddedExtra = name;
                              animTrigger++;
                              displayNotifier.previewProduct(
                                product,
                                extras: List<Map<String, dynamic>>.from(
                                  selectedMods,
                                ),
                                addedExtraName: name,
                              );
                            } else {
                              selectedMods.removeWhere(
                                (m) =>
                                    m['group'] == group.name &&
                                    m['name'] == name,
                              );
                              displayNotifier.previewProduct(
                                product,
                                extras: List<Map<String, dynamic>>.from(
                                  selectedMods,
                                ),
                              );
                            }
                          });
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                );
              }),
              buildModalFieldLabel(ctx, 'Custom Extra & Cost'),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: extraNameCtrl,
                      decoration: restaurantInputDecoration(
                        ctx,
                        hintText: 'e.g. Extra Bacon',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: extraPriceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: restaurantInputDecoration(
                        ctx,
                        hintText: 'Cost ($currency)',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      final n = extraNameCtrl.text.trim();
                      final p =
                          double.tryParse(extraPriceCtrl.text.trim()) ?? 0.0;
                      if (n.isEmpty) {
                        return;
                      }
                      setLocal(() {
                        selectedMods.add({
                          'group': 'Extras',
                          'name': n,
                          'price': p,
                        });
                        lastAddedExtra = n;
                        animTrigger++;
                        displayNotifier.previewProduct(
                          product,
                          extras: List<Map<String, dynamic>>.from(
                            selectedMods,
                          ),
                          addedExtraName: n,
                        );
                        extraNameCtrl.clear();
                        extraPriceCtrl.text = '0';
                      });
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              buildModalFieldLabel(ctx, 'Kitchen Note (Optional)'),
              TextField(
                controller: noteCtrl,
                decoration: restaurantInputDecoration(
                  ctx,
                  hintText: 'e.g. No onions, well done',
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed == true) {
      final extraPrice = selectedMods.fold<double>(
        0.0,
        (sum, m) => sum + ((m['price'] as num?)?.toDouble() ?? 0.0),
      );
      await svc.addOrderItem(
        orderId: order.id,
        product: product,
        modifiersPrice: extraPrice,
        modifiersJson: selectedMods.isEmpty ? null : jsonEncode(selectedMods),
        specialInstructions: noteCtrl.text.trim(),
      );
    }

    displayNotifier.clearPreview();
    noteCtrl.dispose();
    extraNameCtrl.dispose();
    extraPriceCtrl.dispose();
  }

  Future<void> _showCustomServiceChargeDialog(
    RestaurantOrder order,
    String currency,
    StoreConfig? config,
  ) async {
    final svc = ref.read(restaurantServiceProvider);
    final amtCtrl = TextEditingController(
      text: order.serviceChargeAmount > 0
          ? order.serviceChargeAmount.toStringAsFixed(2)
          : '',
    );

    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => RestaurantModalShell(
        icon: Icons.room_service_rounded,
        title: 'Custom Service Charge',
        subtitle:
            'Shown on receipt & recorded in Restaurant Reports (not sent to ZRA)',
        width: 440,
        actions: [
          if (order.serviceChargeAmount > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0.0),
              child: const Text(
                'Clear Charge',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = double.tryParse(amtCtrl.text.trim()) ?? 0.0;
              Navigator.pop(ctx, val < 0 ? 0.0 : val);
            },
            child: const Text('Apply'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildModalFieldLabel(ctx, 'Service Charge Amount ($currency)'),
            TextField(
              controller: amtCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: restaurantInputDecoration(
                ctx,
                hintText: 'Enter custom amount (e.g. 25.00)',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('5%'),
                  onPressed: () => amtCtrl.text =
                      (order.subtotal * 0.05).toStringAsFixed(2),
                ),
                ActionChip(
                  label: const Text('10%'),
                  onPressed: () => amtCtrl.text =
                      (order.subtotal * 0.10).toStringAsFixed(2),
                ),
                ActionChip(
                  label: const Text('15%'),
                  onPressed: () => amtCtrl.text =
                      (order.subtotal * 0.15).toStringAsFixed(2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    amtCtrl.dispose();

    if (result != null) {
      await svc.setOrderServiceCharge(
        order.id,
        result > 0,
        customAmount: result,
      );
    }
  }

  Future<void> _sendToKitchen(
    RestaurantOrder order,
    List<RestaurantOrderItem> items,
    StoreConfig? config,
  ) async {
    final svc = ref.read(restaurantServiceProvider);
    await svc.submitOrderToKitchen(order.id);
    final stations = ref.read(kitchenStationsProvider).valueOrNull ?? [];
    await PrinterService().printRoutedKitchenTickets(
      order: order,
      items: items,
      stations: stations,
      config: config,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order ${order.orderNumber} sent to Kitchen!')),
      );
    }
  }

  Future<void> _showSettlePaymentDialog(
    RestaurantOrder order,
    List<RestaurantOrderItem> items,
    double remaining,
    String currency,
    StoreConfig? config, {
    double? initialTendered,
  }) async {
    String paymentMethod = 'CASH';
    String momoNetwork = 'Airtel Money';
    String cardType = 'Visa / Mastercard';
    final amountCtrl = TextEditingController(
      text: remaining.toStringAsFixed(2),
    );
    final tenderedCtrl = TextEditingController(
      text: (initialTendered != null && initialTendered > 0
              ? initialTendered
              : remaining)
          .toStringAsFixed(2),
    );
    final refCtrl = TextEditingController();
    bool isSplit = false;
    bool replaceTenderOnNextKey = true;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final theme = Theme.of(ctx);
          final brandColor = theme.colorScheme.primary;
          final payVal = (double.tryParse(amountCtrl.text.trim()) ?? 0.0)
              .clamp(0.0, remaining);
          final effectivePay = isSplit ? payVal : remaining;
          final tenderedVal = paymentMethod == 'CASH'
              ? (double.tryParse(tenderedCtrl.text.trim()) ?? 0.0)
              : effectivePay;
          final changeDue =
              paymentMethod == 'CASH' ? (tenderedVal - effectivePay) : 0.0;
          final canComplete = effectivePay > 0 &&
              (paymentMethod != 'CASH' || tenderedVal + 0.001 >= effectivePay);

          void pressKeypad(String key) {
            setLocal(() {
              if (key == 'C') {
                tenderedCtrl.text = '0';
                replaceTenderOnNextKey = true;
                return;
              }
              if (key == '⌫') {
                final cur = tenderedCtrl.text;
                if (cur.length <= 1) {
                  tenderedCtrl.text = '0';
                  replaceTenderOnNextKey = true;
                } else {
                  tenderedCtrl.text = cur.substring(0, cur.length - 1);
                  replaceTenderOnNextKey = false;
                }
                return;
              }
              if (replaceTenderOnNextKey) {
                tenderedCtrl.text = key == '.' ? '0.' : (key == '00' ? '0' : key);
                replaceTenderOnNextKey = false;
              } else {
                if (key == '.' && tenderedCtrl.text.contains('.')) return;
                if (tenderedCtrl.text == '0' && key != '.') {
                  tenderedCtrl.text = key == '00' ? '0' : key;
                } else {
                  tenderedCtrl.text = '${tenderedCtrl.text}$key';
                }
              }
            });
          }

          Widget methodCard({
            required String value,
            required String label,
            required IconData icon,
            required Color accent,
          }) {
            final selected = paymentMethod == value;
            return Expanded(
              child: InkWell(
                onTap: () => setLocal(() {
                  paymentMethod = value;
                  if (value == 'CASH') {
                    tenderedCtrl.text = effectivePay.toStringAsFixed(2);
                    replaceTenderOnNextKey = true;
                  }
                }),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? accent.withValues(alpha: 0.16)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? accent
                          : theme.colorScheme.outline.withValues(alpha: 0.2),
                      width: selected ? 1.8 : 1.0,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: selected
                            ? accent
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                          color: selected
                              ? accent
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget tenderChip(String label, VoidCallback onTap, {bool highlight = false}) {
            return ActionChip(
              label: Text(
                label,
                style: GoogleFonts.ibmPlexMono(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: highlight ? Colors.black : null,
                ),
              ),
              backgroundColor: highlight ? brandColor : null,
              onPressed: onTap,
            );
          }

          Widget keyBtn(String label, {Color? bg, Color? fg}) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ElevatedButton(
                  onPressed: () => pressKeypad(label),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: bg ??
                        theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.45),
                    foregroundColor: fg ?? theme.colorScheme.onSurface,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            );
          }

          return RestaurantModalShell(
            icon: Icons.point_of_sale_rounded,
            title: 'Cashier Checkout • ${order.orderNumber}',
            subtitle:
                'Total Due: $currency ${remaining.toStringAsFixed(2)} • ZRA Smart Invoice',
            width: 560,
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: canComplete ? () => Navigator.pop(ctx, true) : null,
                icon: const Icon(Icons.qr_code_2_rounded, size: 19),
                label: Text(
                  'Complete Sale & Print ZRA',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                ),
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Balance Due Summary Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: brandColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: brandColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isSplit ? 'Paying Now' : 'Amount Due',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '$currency ${effectivePay.toStringAsFixed(2)}',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: brandColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Payment Method Cards
                buildModalFieldLabel(ctx, 'Select Payment Method'),
                Row(
                  children: [
                    methodCard(
                      value: 'CASH',
                      label: 'Cash',
                      icon: Icons.payments_rounded,
                      accent: const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    methodCard(
                      value: 'MOBILE MONEY',
                      label: 'Mobile Money',
                      icon: Icons.phone_android_rounded,
                      accent: const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 8),
                    methodCard(
                      value: 'CARD',
                      label: 'Card / POS',
                      icon: Icons.credit_card_rounded,
                      accent: const Color(0xFF3B82F6),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Split / Partial Payment Switch
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.18),
                    ),
                  ),
                  child: SwitchListTile(
                    dense: true,
                    title: Text(
                      'Split / Partial Payment',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    value: isSplit,
                    onChanged: (v) => setLocal(() {
                      isSplit = v;
                      if (!v) {
                        amountCtrl.text = remaining.toStringAsFixed(2);
                        if (paymentMethod == 'CASH') {
                          tenderedCtrl.text = remaining.toStringAsFixed(2);
                          replaceTenderOnNextKey = true;
                        }
                      }
                    }),
                  ),
                ),
                if (isSplit) ...[
                  const SizedBox(height: 10),
                  buildModalFieldLabel(ctx, 'Split Payment Amount ($currency)'),
                  TextField(
                    controller: amountCtrl,
                    onChanged: (_) => setLocal(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: restaurantInputDecoration(ctx, hintText: '0.00'),
                  ),
                ],
                const SizedBox(height: 14),

                // Mode-Specific Cashier Tender Screen
                if (paymentMethod == 'CASH') ...[
                  buildModalFieldLabel(
                    ctx,
                    'Cash Given / Amount Tendered ($currency)',
                  ),
                  TextField(
                    controller: tenderedCtrl,
                    onChanged: (_) => setLocal(() {
                      replaceTenderOnNextKey = false;
                    }),
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: restaurantInputDecoration(
                      ctx,
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Quick Bank Note Tender Buttons
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      tenderChip(
                        'EXACT',
                        () => setLocal(() {
                          tenderedCtrl.text = effectivePay.toStringAsFixed(2);
                          replaceTenderOnNextKey = true;
                        }),
                        highlight: true,
                      ),
                      for (final note in const [
                        1,
                        2,
                        5,
                        10,
                        20,
                        50,
                        100,
                        200,
                        500,
                      ])
                        tenderChip(
                          '$currency$note',
                          () => setLocal(() {
                            tenderedCtrl.text = note.toStringAsFixed(2);
                            replaceTenderOnNextKey = true;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Change Due / Shortfall Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: (changeDue >= -0.001
                              ? const Color(0xFF10B981)
                              : Colors.redAccent)
                          .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (changeDue >= -0.001
                                ? const Color(0xFF10B981)
                                : Colors.redAccent)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          changeDue >= -0.001 ? 'Change Due' : 'Short By',
                          style: GoogleFonts.manrope(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: changeDue >= -0.001
                                ? const Color(0xFF10B981)
                                : Colors.redAccent,
                          ),
                        ),
                        Text(
                          '$currency ${(changeDue >= -0.001 ? changeDue.abs() : changeDue.abs()).toStringAsFixed(2)}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: changeDue >= -0.001
                                ? const Color(0xFF10B981)
                                : Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Touch Numeric Keypad
                  Column(
                    children: [
                      Row(
                        children: [
                          keyBtn('1'),
                          keyBtn('2'),
                          keyBtn('3'),
                          keyBtn('⌫', fg: Colors.orangeAccent),
                        ],
                      ),
                      Row(
                        children: [
                          keyBtn('4'),
                          keyBtn('5'),
                          keyBtn('6'),
                          keyBtn('C', fg: Colors.redAccent),
                        ],
                      ),
                      Row(
                        children: [
                          keyBtn('7'),
                          keyBtn('8'),
                          keyBtn('9'),
                          keyBtn('.'),
                        ],
                      ),
                      Row(
                        children: [
                          keyBtn('0'),
                          keyBtn('00'),
                        ],
                      ),
                    ],
                  ),
                ] else if (paymentMethod == 'MOBILE MONEY') ...[
                  buildModalFieldLabel(ctx, 'Mobile Money Network'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final net in const [
                        'Airtel Money',
                        'MTN MoMo',
                        'Zamtel Kwacha',
                      ])
                        ChoiceChip(
                          label: Text(net),
                          selected: momoNetwork == net,
                          onSelected: (_) => setLocal(() => momoNetwork = net),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  buildModalFieldLabel(
                    ctx,
                    'Customer Phone or Txn Reference (Optional)',
                  ),
                  TextField(
                    controller: refCtrl,
                    decoration: restaurantInputDecoration(
                      ctx,
                      hintText: 'e.g. 097XXXXXXX or MoMo Ref #',
                    ),
                  ),
                ] else ...[
                  buildModalFieldLabel(ctx, 'Card / POS Terminal Type'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in const [
                        'Visa / Mastercard',
                        'Debit / Local Bank',
                      ])
                        ChoiceChip(
                          label: Text(c),
                          selected: cardType == c,
                          onSelected: (_) => setLocal(() => cardType = c),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  buildModalFieldLabel(
                    ctx,
                    'POS Approval / Last 4 Digits (Optional)',
                  ),
                  TextField(
                    controller: refCtrl,
                    decoration: restaurantInputDecoration(
                      ctx,
                      hintText: 'e.g. Auth #123456',
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    final payAmount = (double.tryParse(amountCtrl.text.trim()) ?? 0.0)
        .clamp(0.0, remaining);
    final effectivePay = isSplit ? payAmount : remaining;
    final tenderedAmount = paymentMethod == 'CASH'
        ? (double.tryParse(tenderedCtrl.text.trim()) ?? effectivePay)
        : effectivePay;
    final changeAmount = paymentMethod == 'CASH'
        ? (tenderedAmount - effectivePay).clamp(0.0, double.infinity)
        : 0.0;
    final finalMethod = paymentMethod == 'MOBILE MONEY'
        ? 'MOBILE MONEY ($momoNetwork)'
        : (paymentMethod == 'CARD' ? 'CARD ($cardType)' : 'CASH');

    amountCtrl.dispose();
    tenderedCtrl.dispose();
    refCtrl.dispose();
    if (confirm != true || effectivePay <= 0) {
      return;
    }

    setState(() => _isSettling = true);
    try {
      final db = ref.read(databaseServiceProvider);
      final user = ref.read(authProvider);
      final svc = ref.read(restaurantServiceProvider);

      final saleItems = <SaleItem>[];
      for (final item in items) {
        final product = await db.isar.products.get(item.productId);
        if (product == null) {
          continue;
        }
        saleItems.add(
          SaleItem(
            productId: product.id,
            productName: item.productName,
            productSkuAtSale: product.sku,
            priceAtSale: item.unitPrice,
            unitCostAtSale: product.unitCost,
            quantity: item.quantity,
            taxRateAtSale: product.taxRate,
            isTaxInclusiveAtSale: product.isTaxInclusive,
            unitOfMeasure: product.displayUnitOfMeasure,
            isDigitaxExempt: product.isDigitaxSyncEnabled == false ||
                (!product.isSyncedWithDigitax &&
                    !product.hasUsableDigitaxItemId),
          ),
        );
      }

      final isFull = payAmount >= remaining - 0.01;
      final ratio = order.totalAmount > 0
          ? (effectivePay / order.totalAmount).clamp(0.0, 1.0)
          : 1.0;

      final openShift = await db.getOpenShiftForTerminal(
        config?.terminalName ?? 'TERMINAL-01',
      );

      final allItemsExempt = saleItems.every((i) => i.isDigitaxExempt);
      final tx = SaleTransaction(
        totalAmount: effectivePay,
        paymentMethod: finalMethod,
        cashierName: user?.name ?? 'Cashier',
        cashierId: user?.numericId,
        terminalName: config?.terminalName ?? 'TERMINAL-01',
        subtotal: order.subtotal * ratio,
        taxAmount: order.taxAmount * ratio,
        serviceChargeAmount: order.serviceChargeAmount * ratio,
        serviceChargeRate: 0.0,
        tenderedAmount: tenderedAmount,
        changeAmount: changeAmount,
        zraStatus: allItemsExempt ? 'LOCAL_EXEMPT' : 'PENDING_SUBMISSION',
      )
        ..cashShiftNumber = openShift?.shiftNumber
        ..cloudStoreId = config?.cloudStoreId ?? 0;

      // 1. Real-time ZRA DigiTax fiscalization BEFORE stock deduction & receipt printing
      final hasDigitax =
          config?.digitaxApiKey != null && config!.digitaxApiKey!.isNotEmpty;
      final syncService = ref.read(syncServiceProvider);
      if (hasDigitax && !allItemsExempt) {
        final reachable = await DigiTaxInventoryService.canReachDigiTax();
        if (reachable) {
          final digitax = ref.read(digitaxInventoryServiceProvider);
          await digitax.fiscalizeSaleTransaction(tx, saleItems);
          final statusUpper = tx.zraStatus.toUpperCase();
          if (statusUpper.startsWith('FAILED') ||
              statusUpper.startsWith('REJECTED')) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Sale Failed — ZRA Rejected (${tx.zraStatus}). Stock unchanged; please retry.',
                  ),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
            return;
          }
        } else if (config.isManagerMode == false) {
          await syncService.trySyncTransaction(tx, saleItems);
        }
      }

      // 2. Persist sale & deduct stock
      await db.saveTransaction(tx, saleItems);
      if (!tx.isSynced) {
        unawaited(syncService.trySyncTransaction(tx, saleItems));
      }

      // 3. Deduct recipe ingredients from Kitchen Mini-Stock when configured
      await svc.deductKitchenIngredientsForOrder(items);
      for (final item in items) {
        final product = await db.isar.products.get(item.productId);
        if (product != null && product.useRecipeStockDeduction) {
          final ingredients = await svc.getRecipeForProduct(product.id);
          if (ingredients.isNotEmpty) {
            await db.isar.writeTxn(() async {
              for (final ing in ingredients) {
                final stockProd =
                    await db.isar.products.get(ing.ingredientProductId);
                if (stockProd != null) {
                  final deduct = (ing.quantityRequired * item.quantity).round();
                  final nextStock = stockProd.stockLevel - deduct;
                  stockProd.stockLevel = nextStock < 0 ? 0 : nextStock;
                  await db.isar.products.put(stockProd);
                }
              }
            });
          }
        }
      }

      // 4. Auto-submit takeaway / draft orders to Kitchen Display & print KOT automatically for Takeaway
      if (order.status == RestaurantOrderStatus.draft) {
        await svc.submitOrderToKitchen(order.id);
        final kotPrinter = PrinterService();
        final isTakeaway = order.serviceType == RestaurantServiceType.counter;
        final hasKitchenPrinter =
            (kotPrinter.kitchenPrinterConfig ??
                await kotPrinter.loadKitchenPrinterConfig()) !=
            null;
        if (isTakeaway ||
            config?.restaurantAutoPrintKot == true ||
            hasKitchenPrinter) {
          final stations =
              ref.read(kitchenStationsProvider).valueOrNull ?? [];
          await kotPrinter.printRoutedKitchenTickets(
            order: order,
            items: items,
            stations: stations,
            config: config,
          );
        }
      }

      // 5. Mark restaurant order paid & close table session if settled
      await svc.recordPaymentAndSettle(
        orderId: order.id,
        paidAmount: effectivePay,
        saleTransactionId: tx.id,
        forceFullSettlement: isFull,
      );

      // 6. Print fiscal ZRA receipt with QR code (both COMPLETE and PENDING print QR)
      await PrinterService().printReceipt(
        tx,
        saleItems,
        config: config,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFull
                  ? (changeAmount > 0
                      ? 'Order ${order.orderNumber} settled! Change Due: $currency ${changeAmount.toStringAsFixed(2)}'
                      : 'Order ${order.orderNumber} settled & ZRA receipt printed!')
                  : 'Partial payment of $currency ${effectivePay.toStringAsFixed(2)} recorded.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settlement error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSettling = false);
      }
    }
  }

  String _orderStatusLabel(RestaurantOrderStatus s) {
    return switch (s) {
      RestaurantOrderStatus.draft => 'Draft',
      RestaurantOrderStatus.submitted => 'Submitted',
      RestaurantOrderStatus.inPreparation => 'In Prep',
      RestaurantOrderStatus.partiallyReady => 'Partly Ready',
      RestaurantOrderStatus.ready => 'Ready',
      RestaurantOrderStatus.served => 'Served',
      RestaurantOrderStatus.awaitingPayment => 'Awaiting Payment',
      RestaurantOrderStatus.paid => 'Paid',
      RestaurantOrderStatus.cancelled => 'Cancelled',
    };
  }

  String _kitchenStatusLabel(KitchenItemStatus s) {
    return switch (s) {
      KitchenItemStatus.newTicket => 'New',
      KitchenItemStatus.accepted => 'Accepted',
      KitchenItemStatus.preparing => 'Preparing',
      KitchenItemStatus.ready => 'Ready',
      KitchenItemStatus.served => 'Served',
      KitchenItemStatus.cancelled => 'Cancelled',
    };
  }
}
