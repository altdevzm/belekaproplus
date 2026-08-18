import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/screens/sales/receipt_detail_modal.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/utils/formatters.dart';
import 'package:beleka_pos/services/api_service.dart';
import 'package:beleka_pos/screens/shell_screen.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

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
    final lowStockAsync = ref.watch(lowStockProductsProvider);
    final paymentDistAsync = ref.watch(paymentDistributionProvider);
    final terminalsAsync = ref.watch(terminalsStreamProvider);
    
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? '\$';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + Actions
          _buildHeader(context, ref),
          const SizedBox(height: 20),
          // Stats row
          statsAsync.when(
            data: (stats) => _buildStatsRow(stats, currency),
            loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D)))),
            error: (e, s) => Text('Error: $e'),
          ),
          const SizedBox(height: 16),
          // Main content area
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Chart + recent transactions
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      // Sales chart (compact)
                      Expanded(
                        flex: 2,
                        child: velocityAsync.when(
                          data: (v) => _buildSalesChart(v),
                          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D))),
                          error: (e, _) => Text('$e'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: transactionsAsync.when(
                          data: (transactions) => _buildRecentTransactions(context, ref, transactions, currency),
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Center(child: Text('Error: $error')),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                // Right: Payment methods + top products + low stock
                SizedBox(
                  width: 280,
                  child: Column(
                    children: [
                      // Terminal Monitoring
                      terminalsAsync.when(
                        data: (terminals) => _buildTerminalMonitoring(terminals, currency),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 12),
                      // Payment breakdown
                      paymentDistAsync.when(
                        data: (dist) => _buildPaymentBreakdown(dist),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 12),
                      // Top products
                      Expanded(
                        child: topProductsAsync.when(
                          data: (products) => _buildTopProducts(products),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Low stock
                      lowStockAsync.when(
                        data: (products) => _buildLowStockAlert(products),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
    final lowStockAsync = ref.watch(lowStockProductsProvider);
    
    final user = ref.watch(authProvider);
    final currency = ref.watch(storeConfigProvider).valueOrNull?.currencySymbol ?? '\$';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCashierHeader(context, ref, user?.name ?? 'Cashier'),
          const SizedBox(height: 20),
          statsAsync.when(
            data: (stats) => _buildCashierStatsRow(stats, currency),
            loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D)))),
            error: (e, s) => Text('Error: $e'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Expanded(
                        flex: 2,
                        child: velocityAsync.when(
                          data: (v) => _buildSalesChart(v),
                          loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D))),
                          error: (e, _) => Text('$e'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: transactionsAsync.when(
                          data: (transactions) => _buildRecentTransactions(context, ref, transactions, currency),
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Center(child: Text('Error: $error')),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                SizedBox(
                  width: 280,
                  child: Column(
                    children: [
                      Expanded(
                        child: topProductsAsync.when(
                          data: (products) => _buildTopProducts(products),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      lowStockAsync.when(
                        data: (products) => _buildLowStockAlert(products),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCashierHeader(BuildContext context, WidgetRef ref, String name) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'My Performance',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Welcome back, $name • Today's Activity",
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
        SizedBox(
          height: 48,
          child: ElevatedButton.icon(
            onPressed: () {
              ref.read(navigationProvider.notifier).state = ScreenType.sales;
            },
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text('GO TO REGISTER', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC1F11D),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCashierStatsRow(Map<String, double> stats, String currency) {
    final todayRev = stats['todayRevenue'] ?? 0;
    final yesterdayRev = stats['yesterdayRevenue'] ?? 0;
    final todayCount = stats['todayCount'] ?? 0;
    final todayItems = stats['todayItems'] ?? 0;

    double revGrowth = yesterdayRev > 0 ? ((todayRev - yesterdayRev) / yesterdayRev) * 100 : 0;
    if (revGrowth.isNaN || revGrowth.isInfinite) revGrowth = 0;

    final avgValue = todayCount > 0 ? todayRev / todayCount : 0.0;

    return Row(
      children: [
        _buildStatCard('My Revenue', CurrencyFormatter.format(todayRev, currency),
            '${revGrowth >= 0 ? '+' : ''}${revGrowth.toStringAsFixed(1)}%', revGrowth >= 0, false),
        const SizedBox(width: 12),
        _buildStatCard('My Transactions', todayCount.toInt().toString(), 'today', true, false),
        const SizedBox(width: 12),
        _buildStatCard('Items Sold', todayItems.toInt().toString(), 'today', true, false),
        const SizedBox(width: 12),
        _buildStatCard('Avg. Sale Value', CurrencyFormatter.format(avgValue, currency), 'per customer', true, false),
      ],
    );
  }


  Widget _buildHeader(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dashboard',
              style: GoogleFonts.inter(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              "Today's overview",
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Start Selling shortcut - Hide for Managers
            if (!ref.watch(isManagerProvider))
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ref.read(navigationProvider.notifier).state = ScreenType.sales;
                  },
                  icon: const Icon(Icons.point_of_sale, size: 18),
                  label: Text('Start Selling', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC1F11D),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                ),
              ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              onSelected: (value) async {
                final stats = ref.read(dashboardStatsProvider).value;
                final topProducts = ref.read(topSellingProductsProvider).value;
                final paymentDist = ref.read(paymentDistributionProvider).value;
                final config = ref.read(storeConfigProvider).value;

                if (stats == null || topProducts == null || paymentDist == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Wait for data to load...')));
                  }
                  return;
                }

                switch (value) {
                  case 'print':
                    final success = await ref.read(printerServiceProvider).printDailySummary(
                          stats: stats,
                          topProducts: topProducts,
                          paymentDist: paymentDist,
                          config: config,
                        );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(success ? 'Summary printed!' : 'Printing failed'),
                          backgroundColor: success ? Colors.green : Colors.red,
                        ),
                      );
                    }
                    break;
                  case 'pdf':
                    await ref.read(exportServiceProvider).exportDailySummaryToPdf(
                          stats: stats,
                          topProducts: topProducts,
                          paymentDist: paymentDist,
                          config: config,
                        );
                    break;
                  case 'excel':
                    await ref.read(exportServiceProvider).exportDailySummaryToExcel(
                          stats: stats,
                          topProducts: topProducts,
                          paymentDist: paymentDist,
                          config: config,
                        );
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'print', child: Text('Print Summary')),
                const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                const PopupMenuItem(value: 'excel', child: Text('Export Excel')),
              ],
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.summarize_outlined, size: 16, color: Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(width: 8),
                    Text('Reports',
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w600, fontSize: 13, color: Colors.white.withValues(alpha: 0.5))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatsRow(Map<String, double> stats, String currency) {
    final todayRev = stats['todayRevenue'] ?? 0;
    final yesterdayRev = stats['yesterdayRevenue'] ?? 0;
    final todayProfit = stats['todayProfit'] ?? 0;
    final yesterdayProfit = stats['yesterdayProfit'] ?? 0;
    final todayTax = stats['todayTax'] ?? 0;
    final yesterdayTax = stats['yesterdayTax'] ?? 0;
    final todayCount = stats['todayCount'] ?? 0;

    double revGrowth = yesterdayRev > 0 ? ((todayRev - yesterdayRev) / yesterdayRev) * 100 : 0;
    if (revGrowth.isNaN || revGrowth.isInfinite) revGrowth = 0;
    
    double profitGrowth = yesterdayProfit > 0 ? ((todayProfit - yesterdayProfit) / yesterdayProfit) * 100 : 0;
    if (profitGrowth.isNaN || profitGrowth.isInfinite) profitGrowth = 0;

    double taxGrowth = yesterdayTax > 0 ? ((todayTax - yesterdayTax) / yesterdayTax) * 100 : 0;
    if (taxGrowth.isNaN || taxGrowth.isInfinite) taxGrowth = 0;

    return Row(
      children: [
        _buildStatCard('Revenue', CurrencyFormatter.format(todayRev, currency),
            '${revGrowth >= 0 ? '+' : ''}${revGrowth.toStringAsFixed(1)}%', revGrowth >= 0, false),
        const SizedBox(width: 12),
        _buildStatCard('Profit', CurrencyFormatter.format(todayProfit, currency),
            '${profitGrowth >= 0 ? '+' : ''}${profitGrowth.toStringAsFixed(1)}%', profitGrowth >= 0, todayProfit < 0),
        const SizedBox(width: 12),
        _buildStatCard('VAT', CurrencyFormatter.format(todayTax, currency),
            '${taxGrowth >= 0 ? '+' : ''}${taxGrowth.toStringAsFixed(1)}%', true, false),
        const SizedBox(width: 12),
        _buildStatCard('Sales', todayCount.toInt().toString(), 'today', true, false),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, String change, bool isPositiveTrend, bool isLoss) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: isLoss ? Colors.redAccent : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isPositiveTrend ? const Color(0xFFC1F11D) : Colors.red).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                change,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isPositiveTrend ? const Color(0xFFC1F11D) : Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesChart(List<Map<String, dynamic>> velocity) {
    final spots = velocity.map((e) => FlSpot(e['hour'].toDouble(), e['revenue'].toDouble())).toList();
    
    // Ensure maxY is at least 10 to prevent crashes when all values are 0
    double maxY = 10;
    for (var spot in spots) {
      if (spot.y > maxY) maxY = spot.y;
    }
    maxY = maxY * 1.2; // Add 20% padding at top

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Sales Today',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Live',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFFC1F11D))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                maxY: maxY,
                minY: 0,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.white.withValues(alpha: 0.03),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFFC1F11D),
                    barWidth: 2.5,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFFC1F11D).withValues(alpha: 0.12),
                          const Color(0xFFC1F11D).withValues(alpha: 0.0),
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
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(BuildContext context, WidgetRef ref, List<SaleTransaction> transactions, String currency) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Recent Transactions',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                      const SizedBox(height: 12),
                      // Search Bar for Receipts
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                        ),
                        child: TextField(
                          onChanged: (val) => ref.read(transactionSearchQueryProvider.notifier).state = val,
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search by Receipt # or Cashier...',
                            hintStyle: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.2)),
                            prefixIcon: Icon(Icons.search, size: 16, color: Colors.white.withValues(alpha: 0.2)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'csv':
                        ref.read(exportServiceProvider).exportTransactionsToCsv(transactions);
                        break;
                      case 'pdf':
                        ref.read(exportServiceProvider).exportTransactionsToPdf(transactions);
                        break;
                      case 'excel':
                        ref.read(exportServiceProvider).exportTransactionsToExcel(transactions);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
                    const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
                    const PopupMenuItem(value: 'excel', child: Text('Export Excel')),
                  ],
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download_rounded, size: 14, color: const Color(0xFFC1F11D)),
                      const SizedBox(width: 4),
                      Text('EXPORT',
                          style: GoogleFonts.inter(
                              fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFC1F11D))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Text('No transactions yet',
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.2))),
                  )
                : ListView.builder(
                    itemCount: transactions.length,
                    itemBuilder: (context, index) {
                      final tx = transactions[index];
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (context) => ReceiptDetailModal(transaction: tx),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Colors.white.withValues(alpha: 0.03)),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Time & Cashier
                                SizedBox(
                                  width: 80,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        DateFormat('HH:mm').format(tx.timestamp),
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFFC1F11D),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        tx.cashierName.toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1,
                                          color: Colors.white.withValues(alpha: 0.3),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Items Sold
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        tx.items.isEmpty 
                                            ? 'NO ITEMS' 
                                            : tx.items.map((e) => '${e.quantity}x ${e.productName}').join(', '),
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white.withValues(alpha: 0.9),
                                          height: 1.4,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.05),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                            ),
                                            child: Text(
                                              tx.paymentMethod.toUpperCase(),
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.white.withValues(alpha: 0.4),
                                                letterSpacing: 1,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (tx.status == 'refunded')
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.redAccent.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.2)),
                                              ),
                                              child: Text(
                                                'REFUNDED',
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w900,
                                                  color: Colors.redAccent,
                                                  letterSpacing: 1,
                                                ),
                                              ),
                                            ),
                                          const SizedBox(width: 8),
                                          if (tx.pointsRedeemed > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFFACC15).withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.2)),
                                              ),
                                              child: Text(
                                                '-%${tx.discountAmount.toStringAsFixed(0)} LOYALTY',
                                                style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w900,
                                                  color: const Color(0xFFFACC15),
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                // Amount
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      CurrencyFormatter.format(tx.totalAmount, currency),
                                      style: GoogleFonts.manrope(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFFC1F11D),
                                      ),
                                    ),
                                    if (tx.taxAmount > 0)
                                      Text(
                                        'INC. TAX',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white.withValues(alpha: 0.2),
                                          letterSpacing: 1,
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
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

  Widget _buildPaymentBreakdown(Map<String, double> distribution) {
    final total = distribution.values.fold(0.0, (sum, v) => sum + v);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Methods',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 14),
          ...distribution.entries.map((e) {
            final pct = total > 0 ? (e.value / total) : 0.0;
            final color = e.key == 'cash'
                ? const Color(0xFFC6B4FF)
                : e.key == 'card'
                    ? const Color(0xFFC1F11D)
                    : const Color(0xFFFFB3B5);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(e.key.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' '),
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
                      Text('${(pct * 100).toStringAsFixed(0)}%',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: pct,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: AlwaysStoppedAnimation(color),
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTopProducts(List<Map<String, dynamic>> products) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Top Products',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
          const SizedBox(height: 12),
          if (products.isEmpty)
            Expanded(
              child: Center(
                child: Text('No sales yet',
                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.2))),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final p = products[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${index + 1}',
                            style: GoogleFonts.inter(
                                fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.4)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p['name'],
                            style: GoogleFonts.inter(
                                fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.75)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${p['quantity']} sold',
                          style: GoogleFonts.inter(
                              fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFFC1F11D)),
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

  Widget _buildLowStockAlert(List<Product> products) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text('Low Stock',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${products.length}',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...products.take(3).map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    Text('${p.stockLevel}',
                        style: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w700, color: Colors.redAccent)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildTerminalMonitoring(List<TerminalInfo> terminals, String currency) {
    if (terminals.isEmpty) return const SizedBox.shrink();
    final activeTerminals = terminals.where((t) => DateTime.now().difference(t.lastHeartbeat).inMinutes < 5).toList();
    final totalActiveSales = activeTerminals.fold(0.0, (sum, t) => sum + t.salesToday);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Live Terminals',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: Color(0xFFC1F11D), shape: BoxShape.circle),
              ),
            ],
          ),
          if (activeTerminals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFFC1F11D).withValues(alpha: 0.15), const Color(0xFFC1F11D).withValues(alpha: 0.05)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                   Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: Color(0xFFC1F11D), shape: BoxShape.circle),
                    child: const Icon(Icons.bolt_rounded, color: Colors.black, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ACTIVE TOTAL REVENUE',
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D), letterSpacing: 1)),
                      Text(CurrencyFormatter.format(totalActiveSales, currency),
                          style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...terminals.map((t) {
            final isOnline = DateTime.now().difference(t.lastHeartbeat).inMinutes < 2;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.terminalName.toUpperCase(),
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: isOnline ? Colors.white : Colors.white24,
                                letterSpacing: 1,
                              ),
                            ),
                            Text(
                              '${t.cashierName} • ID: ${t.cashierId}',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            CurrencyFormatter.format(t.salesToday, currency),
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFC1F11D),
                            ),
                          ),
                          Text(
                            '${t.transactionCount} entries',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              color: Colors.white24,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: LinearProgressIndicator(
                      value: isOnline ? 1.0 : 0.0,
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      valueColor: AlwaysStoppedAnimation(isOnline ? const Color(0xFFC1F11D) : Colors.redAccent),
                      minHeight: 2,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
