import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/customer_display_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/restaurant_service.dart';
import 'package:beleka_pos/widgets/food_3d_visualizer.dart';

/// Client-side Customer-Facing Display for dual-screen Restaurant POS setups.
/// Mirrors the active dish 3D customization stage + live itemized order cart.
class CustomerDisplayScreen extends ConsumerWidget {
  final bool isEmbeddedPreview;

  const CustomerDisplayScreen({
    super.key,
    this.isEmbeddedPreview = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayState = ref.watch(customerDisplayProvider);
    final config = ref.watch(storeConfigProvider).valueOrNull;
    final currency = config?.currencySymbol ?? 'ZK';
    final storeName = config?.businessName ?? 'BELEKA RESTAURANT';

    final order = displayState.activeOrder;
    final activeProduct = displayState.activeProduct;

    return Scaffold(
      backgroundColor: const Color(0xFF070B14),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBanner(context, storeName, order),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 780;
                  if (isWide) {
                    return Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: _buildStagePanel(
                            displayState,
                            activeProduct,
                            currency,
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: _buildOrderSummaryPanel(ref, order, currency),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildStagePanel(
                          displayState,
                          activeProduct,
                          currency,
                        ),
                      ),
                      Expanded(
                        flex: 5,
                        child: _buildOrderSummaryPanel(ref, order, currency),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBanner(
    BuildContext context,
    String storeName,
    RestaurantOrder? order,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0E1525),
        border: Border(bottom: BorderSide(color: Color(0xFF1F2A40))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.restaurant_menu_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storeName.toUpperCase(),
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'CUSTOMER DISPLAY • LIVE 3D ORDER PREVIEW',
                  style: GoogleFonts.inter(
                    color: const Color(0xFF60A5FA),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          if (order != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                'Order #${order.orderNumber} • ${order.tableName ?? 'Takeaway'}',
                style: GoogleFonts.inter(
                  color: const Color(0xFF34D399),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (!isEmbeddedPreview) ...[
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close Client Display',
              icon: const Icon(Icons.close_rounded, color: Color(0xFF94A3B8)),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF1E293B),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStagePanel(
    CustomerDisplayState displayState,
    Product? activeProduct,
    String currency,
  ) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF101829), Color(0xFF0A0F1D)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F2A40)),
      ),
      child: activeProduct != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            color: Color(0xFF60A5FA),
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'NOW CUSTOMIZING',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF93C5FD),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Drag to rotate 3D view',
                      style: GoogleFonts.inter(
                        color: const Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: Food3DVisualizer(
                      productName: activeProduct.name,
                      productImagePath: activeProduct.imagePath,
                      basePrice: activeProduct.price,
                      currency: currency,
                      extras: displayState.activeExtras,
                      lastAddedExtraName: displayState.lastAddedExtraName,
                      animationTrigger: displayState.animationTrigger,
                      height: 320,
                    ),
                  ),
                ),
                if (displayState.availableExtras.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.add_circle_outline_rounded,
                        color: Color(0xFFFBBF24),
                        size: 15,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AVAILABLE EXTRAS • ASK YOUR CASHIER TO ADD:',
                        style: GoogleFonts.inter(
                          color: const Color(0xFFFDE68A),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 54,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: displayState.availableExtras.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final ex = displayState.availableExtras[index];
                        final name = ex['name']?.toString() ?? 'Extra';
                        final price = (ex['price'] as num?)?.toDouble() ?? 0.0;
                        final img = ex['imagePath']?.toString();
                        final hasImg = img != null &&
                            img.isNotEmpty &&
                            File(img).existsSync();
                        final isSelected = displayState.activeExtras.any(
                          (a) => a['name'] == name,
                        );
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF10B981).withValues(alpha: 0.22)
                                : const Color(0xFF141E33),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF273554),
                              width: isSelected ? 1.6 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (hasImg) ...[
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFF475569),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child: Image.file(
                                      File(img),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    price > 0
                                        ? '+$currency ${price.toStringAsFixed(2)}'
                                        : 'Free',
                                    style: GoogleFonts.inter(
                                      color: isSelected
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFFFBBF24),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              if (isSelected) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF34D399),
                                  size: 16,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            )
          : _buildIdleShowcase(),
    );
  }

  Widget _buildIdleShowcase() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF3B82F6).withValues(alpha: 0.25),
                const Color(0xFF8B5CF6).withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
            ),
          ),
          child: const Icon(
            Icons.fastfood_rounded,
            size: 50,
            color: Color(0xFF60A5FA),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Freshly Prepared For You',
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Select any dish or dessert to preview it in interactive 3D\nwith live extras and pricing.',
          style: GoogleFonts.inter(
            color: const Color(0xFF94A3B8),
            fontSize: 14,
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildOrderSummaryPanel(
    WidgetRef ref,
    RestaurantOrder? order,
    String currency,
  ) {
    final svc = ref.watch(restaurantServiceProvider);
    if (order == null) {
      return _buildOrderSummaryContent(null, const [], currency);
    }
    return StreamBuilder<List<RestaurantOrderItem>>(
      stream: svc.watchOrderItems(order.id),
      builder: (context, snap) {
        return _buildOrderSummaryContent(
          order,
          snap.data ?? const [],
          currency,
        );
      },
    );
  }

  Widget _buildOrderSummaryContent(
    RestaurantOrder? order,
    List<RestaurantOrderItem> items,
    String currency,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1525),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF1F2A40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.receipt_long_rounded,
                color: Color(0xFF34D399),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Your Order',
                style: GoogleFonts.plusJakartaSans(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${items.length} item${items.length == 1 ? '' : 's'}',
                style: GoogleFonts.inter(
                  color: const Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF1F2A40), height: 1),
          const SizedBox(height: 12),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No items added yet.\nYour order items will appear here.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: const Color(0xFF64748B),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final extras = _parseExtras(item.modifiersJson);
                      final lineTotal = item.unitPrice * item.quantity;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141E33),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF22304D)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${item.quantity}x',
                                    style: GoogleFonts.inter(
                                      color: const Color(0xFF93C5FD),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    item.productName,
                                    style: GoogleFonts.inter(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '$currency ${lineTotal.toStringAsFixed(2)}',
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFF34D399),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            if (extras.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: extras.map((ex) {
                                  final name = ex['name']?.toString() ?? 'Extra';
                                  final price =
                                      (ex['price'] as num?)?.toDouble() ?? 0.0;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E293B),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      price > 0
                                          ? '+ $name ($currency${price.toStringAsFixed(2)})'
                                          : '+ $name',
                                      style: GoogleFonts.inter(
                                        color: const Color(0xFFFBBF24),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF1F2A40), height: 1),
          const SizedBox(height: 14),
          _buildTotalRow(
            'Subtotal',
            '$currency ${(order?.subtotal ?? 0.0).toStringAsFixed(2)}',
          ),
          if ((order?.serviceChargeAmount ?? 0.0) > 0) ...[
            const SizedBox(height: 6),
            _buildTotalRow(
              'Service Charge',
              '$currency ${order!.serviceChargeAmount.toStringAsFixed(2)}',
            ),
          ],
          if ((order?.taxAmount ?? 0.0) > 0) ...[
            const SizedBox(height: 6),
            _buildTotalRow(
              'Tax',
              '$currency ${order!.taxAmount.toStringAsFixed(2)}',
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF065F46), Color(0xFF047857)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'TOTAL DUE',
                  style: GoogleFonts.plusJakartaSans(
                    color: const Color(0xFFD1FAE5),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  '$currency ${(order?.totalAmount ?? 0.0).toStringAsFixed(2)}',
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: const Color(0xFF94A3B8),
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _parseExtras(String? modifiersJson) {
    if (modifiersJson == null || modifiersJson.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(modifiersJson);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
