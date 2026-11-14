import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/restaurant_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/screens/shell_screen.dart';

class RestaurantDashboardScreen extends ConsumerWidget {
  const RestaurantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brandColor = theme.colorScheme.primary;
    final config = ref.watch(storeConfigProvider).valueOrNull;
    final currency = config?.currencySymbol ?? 'ZK';

    final tables = ref.watch(restaurantTablesProvider).valueOrNull ?? [];
    final activeOrders =
        ref.watch(activeRestaurantOrdersProvider).valueOrNull ?? [];
    final allOrders = ref.watch(allRestaurantOrdersProvider).valueOrNull ?? [];

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayPaidOrders = allOrders
        .where(
          (o) =>
              o.status == RestaurantOrderStatus.paid &&
              !o.createdAt.isBefore(todayStart),
        )
        .toList();

    final occupiedCount = tables
        .where((t) => t.status != RestaurantTableStatus.available)
        .length;
    final todayRevenue = todayPaidOrders.fold<double>(
      0.0,
      (sum, o) => sum + o.totalAmount,
    );
    final avgTicket =
        todayPaidOrders.isEmpty ? 0.0 : todayRevenue / todayPaidOrders.length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Header Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.restaurant_rounded,
                      color: brandColor,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Restaurant Operations',
                          style: GoogleFonts.manrope(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '${config?.businessName ?? 'Restaurant'} • Live Floor, Kitchen & Counter Overview',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => ref.read(navigationProvider.notifier).state =
                        ScreenType.restaurantOrders,
                    icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                    label: const Text('Take Order'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // KPI Cards
            LayoutBuilder(
              builder: (context, constraints) {
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: constraints.maxWidth > 950 ? 4 : 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 2.1,
                  children: [
                    _kpiCard(
                      context,
                      title: 'Occupied Tables',
                      value: '$occupiedCount / ${tables.length}',
                      icon: Icons.table_restaurant_rounded,
                      color: const Color(0xFF3B82F6),
                    ),
                    _kpiCard(
                      context,
                      title: 'Open Orders',
                      value: '${activeOrders.length}',
                      icon: Icons.receipt_long_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                    _kpiCard(
                      context,
                      title: 'Today Restaurant Sales',
                      value: '$currency ${todayRevenue.toStringAsFixed(2)}',
                      icon: Icons.payments_rounded,
                      color: const Color(0xFF10B981),
                    ),
                    _kpiCard(
                      context,
                      title: 'Avg Ticket Value',
                      value: '$currency ${avgTicket.toStringAsFixed(2)}',
                      icon: Icons.trending_up_rounded,
                      color: const Color(0xFF8B5CF6),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),

            Text(
              'Workspace Navigation',
              style: GoogleFonts.manrope(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),

            LayoutBuilder(
              builder: (context, constraints) {
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: constraints.maxWidth > 950 ? 3 : 2,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 14,
                  childAspectRatio: 2.35,
                  children: [
                    _navTile(
                      context,
                      ref,
                      title: 'Tables & Floor Plan',
                      subtitle: 'Seat guests, transfer & merge bills',
                      icon: Icons.table_restaurant_rounded,
                      accent: const Color(0xFF3B82F6),
                      target: ScreenType.restaurantTables,
                    ),
                    _navTile(
                      context,
                      ref,
                      title: 'Orders & Takeaway POS',
                      subtitle: 'Table service, #001 takeaway & ZRA checkout',
                      icon: Icons.restaurant_menu_rounded,
                      accent: brandColor,
                      target: ScreenType.restaurantOrders,
                    ),
                    _navTile(
                      context,
                      ref,
                      title: 'Kitchen Display (KDS)',
                      subtitle: 'Station tickets, prep timers & bump',
                      icon: Icons.soup_kitchen_rounded,
                      accent: const Color(0xFFF59E0B),
                      target: ScreenType.kitchenDisplay,
                    ),
                    _navTile(
                      context,
                      ref,
                      title: 'Menu, Extras & Recipes',
                      subtitle: '86 availability, paid extras & stations',
                      icon: Icons.menu_book_rounded,
                      accent: const Color(0xFF10B981),
                      target: ScreenType.restaurantMenu,
                    ),
                    _navTile(
                      context,
                      ref,
                      title: 'Restaurant Reports & PDF',
                      subtitle: 'Receipts, pre-bills, extras & PDF export',
                      icon: Icons.analytics_rounded,
                      accent: const Color(0xFF8B5CF6),
                      target: ScreenType.restaurantReports,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.manrope(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navTile(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required ScreenType target,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => ref.read(navigationProvider.notifier).state = target,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
