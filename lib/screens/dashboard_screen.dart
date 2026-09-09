import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/screens/sales/receipt_detail_modal.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/utils/formatters.dart';
import 'package:beleka_pos/services/api_service.dart';
import 'package:beleka_pos/screens/shell_screen.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/widgets/license_expiry_banner.dart';
import 'package:beleka_pos/services/license_service.dart';

final recentTransactionsProvider = StreamProvider<List<SaleTransaction>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final query = ref.watch(transactionSearchQueryProvider);
  return db.watchRecentTransactions(limit: query.isEmpty ? 10 : 50, query: query);
});

final transactionSearchQueryProvider = StateProvider<String>((ref) => '');

final dashboardStatsProvider = StreamProvider<Map<String, double>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchDashboardStats();
});

final salesVelocityProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchSalesVelocityData();
});

final topSellingProductsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchTopSellingProducts();
});

final lowStockProductsProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchLowStockProducts();
});

final paymentDistributionProvider = StreamProvider<Map<String, double>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  return db.watchPaymentMethodDistribution();
});

final terminalsStreamProvider = StreamProvider<List<TerminalInfo>>((ref) {
  final api = ref.watch(apiServiceProvider);
  return api.terminalsStream;
});

final cashierDashboardStatsProvider = StreamProvider<Map<String, double>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final user = ref.watch(authProvider);
  if (user == null) return Stream.value({});
  return db.watchCashierDashboardStats(user.name);
});

final cashierSalesVelocityProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final user = ref.watch(authProvider);
  if (user == null) return Stream.value([]);
  return db.watchCashierSalesVelocityData(user.name);
});

final cashierRecentTransactionsProvider = StreamProvider<List<SaleTransaction>>((ref) {
  final db = ref.watch(databaseServiceProvider);
  final user = ref.watch(authProvider);
  final query = ref.watch(transactionSearchQueryProvider);
  if (user == null) return Stream.value([]);
  return db.watchCashierRecentTransactions(user.name, limit: query.isEmpty ? 10 : 50, query: query);
});

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = ref.watch(isManagerProvider);
    
    if (isManager) {
      return _buildManagerDashboard(context, ref);
    } else {
      return _buildCashierDashboard(context, ref);
    }
  }

  Widget _buildManagerDashboard(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(dashboardStatsProvider);
    final transactionsAsync = ref.watch(recentTransactionsProvider);
    final velocityAsync = ref.watch(salesVelocityProvider);
    final topProductsAsync = ref.watch(topSellingProductsProvider);
    final paymentDistAsync = ref.watch(paymentDistributionProvider);
    final lowStockAsync = ref.watch(lowStockProductsProvider);
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb & Status Bar
          _buildTopBreadcrumbBar(context),
          const SizedBox(height: 16),

          // Greeting Header Bar
          _buildGreetingHeader(context, ref),
          const SizedBox(height: 16),

          // License Expiry Warning Card (only shown for timed licenses ≤30 days)
          const LicenseExpiryDashboardCard(),
          const _LicenseExpiryCardSpacer(),

          // 4 Stats Cards Row
          statsAsync.when(
            data: (stats) => _buildFourStatsRow(context, stats, currency),
            loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
            error: (e, s) => Text('Error: $e'),
          ),
          const SizedBox(height: 20),

          // Middle Charts Section (Revenue Overview + Payment Methods) - Adaptive
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 850;
              final revenueWidget = velocityAsync.when(
                data: (v) => _buildRevenueOverviewCard(context, v, statsAsync.valueOrNull, currency),
                loading: () => const SizedBox(height: 340, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text('$e'),
              );
              final paymentDistWidget = paymentDistAsync.when(
                data: (dist) => _buildPaymentMethodsDonutCard(context, dist, statsAsync.valueOrNull, currency),
                loading: () => const SizedBox(height: 340, child: Center(child: CircularProgressIndicator())),
                error: (_, _) => const SizedBox.shrink(),
              );

              if (isCompact) {
                return Column(
                  children: [
                    revenueWidget,
                    const SizedBox(height: 16),
                    paymentDistWidget,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: revenueWidget),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: paymentDistWidget),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // Bottom Row (Recent Transactions + Top Products) - Adaptive
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 850;
              final transactionsWidget = SizedBox(
                height: 360,
                child: transactionsAsync.when(
                  data: (transactions) => _buildRecentTransactionsCard(context, ref, transactions, currency),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, stack) => Center(child: Text('Error: $error')),
                ),
              );

              final topProductsWidget = SizedBox(
                height: 360,
                child: Column(
                  children: [
                    Expanded(
                      child: topProductsAsync.when(
                        data: (products) => _buildTopProductsCard(context, products),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ),
                    if (lowStockAsync.valueOrNull?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 12),
                      lowStockAsync.when(
                        data: (products) => _buildLowStockAlert(context, products),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              );

              if (isCompact) {
                return Column(
                  children: [
                    transactionsWidget,
                    const SizedBox(height: 16),
                    topProductsWidget,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: transactionsWidget),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: topProductsWidget),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCashierDashboard(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(cashierDashboardStatsProvider);
    final transactionsAsync = ref.watch(cashierRecentTransactionsProvider);
    final velocityAsync = ref.watch(cashierSalesVelocityProvider);
    final topProductsAsync = ref.watch(topSellingProductsProvider);
    final user = ref.watch(authProvider);
    final currency = ref.watch(storeConfigProvider).valueOrNull?.currencySymbol ?? 'K';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTopBreadcrumbBar(context),
          const SizedBox(height: 16),
          _buildCashierHeader(context, ref, user?.name ?? 'Cashier'),
          const SizedBox(height: 20),
          statsAsync.when(
            data: (stats) => _buildFourStatsRow(context, stats, currency),
            loading: () => const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
            error: (e, s) => Text('Error: $e'),
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 850;
              final velocityWidget = velocityAsync.when(
                data: (v) => _buildRevenueOverviewCard(context, v, statsAsync.valueOrNull, currency),
                loading: () => const SizedBox(height: 340, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Text('$e'),
              );
              final topProductsWidget = SizedBox(
                height: 340,
                child: topProductsAsync.when(
                  data: (products) => _buildTopProductsCard(context, products),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              );

              if (isCompact) {
                return Column(
                  children: [
                    velocityWidget,
                    const SizedBox(height: 16),
                    topProductsWidget,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: velocityWidget),
                  const SizedBox(width: 16),
                  Expanded(flex: 1, child: topProductsWidget),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 360,
            child: transactionsAsync.when(
              data: (transactions) => _buildRecentTransactionsCard(context, ref, transactions, currency),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
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
        // Left Breadcrumb
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
              'Dashboard',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        // Right Badges & Controls
        Row(
          children: [
            // Status Badge
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
                    'All systems operational',
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
            // Notification Bell
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Icon(Icons.notifications_none_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 10),
            // Date Indicator Badge
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

  Widget _buildGreetingHeader(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final userName = ref.watch(authProvider)?.name ?? 'User';

    final hour = DateTime.now().hour;
    final timeGreeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()).toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$timeGreeting, $userName',
              style: GoogleFonts.inter(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Here is what is happening across your store today.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Export report button
            PopupMenuButton<String>(
              onSelected: (value) async {
                final stats = ref.read(dashboardStatsProvider).value;
                final topProducts = ref.read(topSellingProductsProvider).value;
                final paymentDist = ref.read(paymentDistributionProvider).value;
                final config = ref.read(storeConfigProvider).value;
                if (stats == null || topProducts == null || paymentDist == null) return;
                if (value == 'pdf') {
                  await ref.read(exportServiceProvider).exportDailySummaryToPdf(
                    stats: stats, topProducts: topProducts, paymentDist: paymentDist, config: config);
                } else if (value == 'excel') {
                  await ref.read(exportServiceProvider).exportDailySummaryToExcel(
                    stats: stats, topProducts: topProducts, paymentDist: paymentDist, config: config);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                PopupMenuItem(value: 'excel', child: Text('Export Excel')),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151F32) : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.file_upload_outlined, size: 16, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 6),
                    Text(
                      'Export report',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // New sale primary button
            ElevatedButton.icon(
              onPressed: () {
                ref.read(navigationProvider.notifier).state = ScreenType.sales;
              },
              icon: const Icon(Icons.shopping_cart_outlined, size: 16, color: Colors.white),
              label: Text(
                'New sale',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCashierHeader(BuildContext context, WidgetRef ref, String name) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Performance',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Welcome back, $name • Today's Activity",
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        ElevatedButton.icon(
          onPressed: () {
            ref.read(navigationProvider.notifier).state = ScreenType.sales;
          },
          icon: const Icon(Icons.shopping_cart_outlined, size: 16, color: Colors.white),
          label: Text('GO TO REGISTER', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            elevation: 0,
          ),
        ),
      ],
    );
  }

  Widget _buildFourStatsRow(BuildContext context, Map<String, double> stats, String currency) {
    final todayRev = stats['todayRevenue'] ?? 0.0;
    final yesterdayRev = stats['yesterdayRevenue'] ?? 0.0;
    final todayProfit = stats['todayProfit'] ?? 0.0;
    final yesterdayProfit = stats['yesterdayProfit'] ?? 0.0;
    final todayCount = (stats['todayCount'] ?? 0.0).toInt();
    
    double revGrowth = yesterdayRev > 0
        ? ((todayRev - yesterdayRev) / yesterdayRev) * 100
        : (todayRev > 0 ? 100.0 : 0.0);
    if (revGrowth.isNaN || revGrowth.isInfinite) revGrowth = 0.0;

    double profitGrowth = yesterdayProfit > 0
        ? ((todayProfit - yesterdayProfit) / yesterdayProfit) * 100
        : (todayProfit > 0 ? 100.0 : 0.0);
    if (profitGrowth.isNaN || profitGrowth.isInfinite) profitGrowth = 0.0;

    final marginPct = todayRev > 0 ? (todayProfit / todayRev * 100) : 0.0;
    final avgValue = todayCount > 0 ? todayRev / todayCount : 0.0;

    final card1 = _buildSingleMetricCard(
      context,
      label: 'Total revenue',
      value: CurrencyFormatter.format(todayRev, currency),
      growthText: '${revGrowth >= 0 ? '↗' : '↘'} ${revGrowth.abs().toStringAsFixed(1)}%',
      isPositive: revGrowth >= 0,
      subtitle: 'vs. yesterday (${CurrencyFormatter.format(yesterdayRev, currency)})',
      icon: Icons.attach_money_rounded,
      iconBgColor: const Color(0xFFEFF6FF),
      iconColor: const Color(0xFF1D4ED8),
    );
    final card2 = _buildSingleMetricCard(
      context,
      label: 'Gross profit',
      value: CurrencyFormatter.format(todayProfit, currency),
      growthText: '${profitGrowth >= 0 ? '↗' : '↘'} ${profitGrowth.abs().toStringAsFixed(1)}%',
      isPositive: profitGrowth >= 0,
      subtitle: '${marginPct.toStringAsFixed(1)}% margin',
      icon: Icons.trending_up_rounded,
      iconBgColor: const Color(0xFFECFDF5),
      iconColor: const Color(0xFF059669),
    );
    final card3 = _buildSingleMetricCard(
      context,
      label: 'Total orders',
      value: '$todayCount',
      growthText: todayCount > 0 ? '↗ Active' : '0 today',
      isPositive: todayCount > 0,
      subtitle: '$todayCount orders today',
      icon: Icons.shopping_bag_outlined,
      iconBgColor: const Color(0xFFFFFBEB),
      iconColor: const Color(0xFFD97706),
    );
    final card4 = _buildSingleMetricCard(
      context,
      label: 'Average order value',
      value: CurrencyFormatter.format(avgValue, currency),
      growthText: avgValue > 0 ? '↗ Live' : '0.00',
      isPositive: avgValue > 0,
      subtitle: 'Based on $todayCount orders',
      icon: Icons.bar_chart_rounded,
      iconBgColor: const Color(0xFFF0F9FF),
      iconColor: const Color(0xFF0284C7),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              card1,
              const SizedBox(height: 12),
              card2,
              const SizedBox(height: 12),
              card3,
              const SizedBox(height: 12),
              card4,
            ],
          );
        }

        if (constraints.maxWidth < 1050) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: card1),
                  const SizedBox(width: 14),
                  Expanded(child: card2),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: card3),
                  const SizedBox(width: 14),
                  Expanded(child: card4),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: card1),
            const SizedBox(width: 14),
            Expanded(child: card2),
            const SizedBox(width: 14),
            Expanded(child: card3),
            const SizedBox(width: 14),
            Expanded(child: card4),
          ],
        );
      },
    );
  }

  Widget _buildSingleMetricCard(
    BuildContext context, {
    required String label,
    required String value,
    required String growthText,
    required bool isPositive,
    required String subtitle,
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDark ? iconColor.withValues(alpha: 0.15) : iconBgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isPositive ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    growthText,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isPositive ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

  Widget _buildRevenueOverviewCard(
    BuildContext context,
    List<Map<String, dynamic>> velocity,
    Map<String, double>? stats,
    String currency,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    List<FlSpot> spots = velocity.map((e) => FlSpot((e['hour'] as num).toDouble(), (e['revenue'] as num).toDouble())).toList();
    if (spots.isEmpty) {
      spots = List.generate(24, (i) => FlSpot(i.toDouble(), 0.0));
    }

    double maxY = 10.0;
    for (var s in spots) {
      if (s.y > maxY) maxY = s.y * 1.2;
    }

    final totalRev = stats?['todayRevenue'] ?? 0.0;
    final yesterdayRev = stats?['yesterdayRevenue'] ?? 0.0;
    double revGrowth = yesterdayRev > 0
        ? ((totalRev - yesterdayRev) / yesterdayRev) * 100
        : (totalRev > 0 ? 100.0 : 0.0);
    if (revGrowth.isNaN || revGrowth.isInfinite) revGrowth = 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Revenue overview',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Hourly sales performance today',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // Revenue / Orders segmented indicator
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF151F32) : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2),
                        ],
                      ),
                      child: Text(
                        'Revenue (24h)',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: primaryColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Line Chart Area
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                maxY: maxY,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 54,
                      getTitlesWidget: (val, meta) {
                        return Text(
                          '$currency ${val.toInt()}',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: 4,
                      getTitlesWidget: (val, meta) {
                        final hour = val.toInt();
                        if (hour < 0 || hour > 23) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${hour.toString().padLeft(2, '0')}:00',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: primaryColor,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          primaryColor.withValues(alpha: 0.25),
                          primaryColor.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Today Total',
                    style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.format(totalRev, currency),
                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    '${revGrowth >= 0 ? '↗' : '↘'} ${revGrowth.abs().toStringAsFixed(1)}%',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: revGrowth >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'vs. yesterday',
                    style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsDonutCard(
    BuildContext context,
    Map<String, double> distribution,
    Map<String, double>? stats,
    String currency,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final totalOrders = (stats?['todayCount'] ?? 0.0).toInt();
    final cardAmt = distribution['card'] ?? 0.0;
    final cashAmt = distribution['cash'] ?? 0.0;
    final mobileAmt = distribution['mobile_money'] ?? distribution['mobile'] ?? 0.0;
    final totalAmt = cardAmt + cashAmt + mobileAmt;

    final cardPct = totalAmt > 0 ? ((cardAmt / totalAmt) * 100).round() : 0;
    final cashPct = totalAmt > 0 ? ((cashAmt / totalAmt) * 100).round() : 0;
    final mobilePct = totalAmt > 0 ? ((mobileAmt / totalAmt) * 100).round() : 0;

    final pieSections = totalAmt > 0
        ? [
            if (cardAmt > 0) PieChartSectionData(color: primaryColor, value: cardPct.toDouble(), title: '', radius: 18),
            if (cashAmt > 0) PieChartSectionData(color: const Color(0xFF059669), value: cashPct.toDouble(), title: '', radius: 18),
            if (mobileAmt > 0) PieChartSectionData(color: const Color(0xFFD97706), value: mobilePct.toDouble(), title: '', radius: 18),
          ]
        : [
            PieChartSectionData(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), value: 100, title: '', radius: 18),
          ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment methods',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sales by tender type today',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.credit_card_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Donut Chart + Legend Side by Side
          Row(
            children: [
              // Donut PieChart
              SizedBox(
                width: 140,
                height: 140,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 3,
                        centerSpaceRadius: 45,
                        sections: pieSections,
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$totalOrders',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'orders',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Legend Column
              Expanded(
                child: Column(
                  children: [
                    _buildDonutLegendItem(context, 'Card', '$cardPct%', CurrencyFormatter.format(cardAmt, currency), primaryColor),
                    const SizedBox(height: 12),
                    _buildDonutLegendItem(context, 'Cash', '$cashPct%', CurrencyFormatter.format(cashAmt, currency), const Color(0xFF059669)),
                    const SizedBox(height: 12),
                    _buildDonutLegendItem(context, 'Mobile money', '$mobilePct%', CurrencyFormatter.format(mobileAmt, currency), const Color(0xFFD97706)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDonutLegendItem(BuildContext context, String title, String percentage, String amount, Color color) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              percentage,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
            ),
            Text(
              amount,
              style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRecentTransactionsCard(
    BuildContext context,
    WidgetRef ref,
    List<SaleTransaction> transactions,
    String currency,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent transactions',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Your latest completed sales',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  ref.read(navigationProvider.notifier).state = ScreenType.reports;
                },
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  children: [
                    Text(
                      'View all',
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16, color: primaryColor),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Text(
                      'No recent transactions',
                      style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    itemCount: transactions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, indent: 0, endIndent: 0),
                    itemBuilder: (context, index) {
                      final tx = transactions[index];
                      return InkWell(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => ReceiptDetailModal(transaction: tx),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.receipt_long_rounded, size: 18, color: primaryColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Receipt #${tx.id}',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: theme.colorScheme.onSurface,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${tx.cashierName} • ${DateFormat('MMM d, HH:mm').format(tx.timestamp)}',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tx.paymentMethod.toUpperCase(),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                CurrencyFormatter.format(tx.totalAmount, currency),
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProductsCard(BuildContext context, List<Map<String, dynamic>> products) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Top products',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Best performers this week',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Text(
                      'No sales recorded',
                      style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final p = products[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: index == 0
                                    ? primaryColor
                                    : isDark
                                        ? const Color(0xFF1C283D)
                                        : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${index + 1}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: index == 0 ? Colors.white : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p['name'] ?? 'Product',
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${p['quantity']} sold',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: primaryColor,
                                ),
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
  }

  Widget _buildLowStockAlert(BuildContext context, List<Product> products) {
    if (products.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              Text(
                'Low Stock Alert',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFFF59E0B)),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${products.length}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...products.take(3).map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${p.stockLevel}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFEF4444),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// Renders a spacing gap only when the LicenseExpiryDashboardCard is visible.
/// Avoids extra spacing when the card returns SizedBox.shrink().
class _LicenseExpiryCardSpacer extends ConsumerWidget {
  const _LicenseExpiryCardSpacer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final license = ref.read(licenseServiceProvider).activeLicense;
    if (license == null || license.expiresAt == null) return const SizedBox.shrink();
    if (!license.isExpired && license.remainingDays > 7) return const SizedBox.shrink();
    return const SizedBox(height: 16);
  }
}
