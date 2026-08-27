import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/utils/formatters.dart';
import 'package:beleka_pos/screens/sales/receipt_detail_modal.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/services/printer_service.dart';

final reportDateRangeProvider = StateProvider<DateTimeRange>((ref) {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, now.month, now.day, 0, 0, 0, 0),
    end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999),
  );
});

final reportTransactionsProvider = StreamProvider<List<SaleTransaction>>((ref) {
  final range = ref.watch(reportDateRangeProvider);
  final db = ref.watch(databaseServiceProvider);
  return db.watchTransactionsInRange(range.start, range.end);
});

final reportStatsProvider = Provider<Map<String, double>>((ref) {
  final transactions = ref.watch(reportTransactionsProvider).value ?? [];

  double revenue = transactions.fold(0.0, (sum, t) => sum + (t.totalAmount.isNaN ? 0.0 : t.totalAmount));
  double profit = transactions.fold(0.0, (sum, t) => sum + (t.grossProfit.isNaN ? 0.0 : t.grossProfit));
  double tax = transactions.fold(0.0, (sum, t) => sum + (t.taxAmount.isNaN ? 0.0 : t.taxAmount));

  final Map<String, double> paymentBreakdown = {};
  for (var t in transactions) {
    final amount = t.totalAmount.isNaN ? 0.0 : t.totalAmount;
    final method = t.paymentMethod.toLowerCase().replaceAll(' ', '_');
    paymentBreakdown[method] = (paymentBreakdown[method] ?? 0) + amount;
  }

  return {
    'revenue': revenue,
    'profit': profit,
    'tax': tax,
    'count': transactions.length.toDouble(),
    'cash': paymentBreakdown['cash'] ?? 0.0,
    'card': paymentBreakdown['card'] ?? 0.0,
    'mobile_money': paymentBreakdown['mobile_money'] ?? 0.0,
  };
});

final reportTopProductsProvider = Provider<List<Map<String, dynamic>>>((ref) {
  final transactions = ref.watch(reportTransactionsProvider).value ?? [];

  final Map<int, int> productQuantities = {};
  final Map<int, String> productNames = {};

  for (var t in transactions) {
    for (var item in t.items) {
      productQuantities[item.productId] = (productQuantities[item.productId] ?? 0) + item.quantity;
      productNames[item.productId] = item.productName;
    }
  }

  final sortedProducts = productQuantities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return sortedProducts.take(10).map((e) => {
    'productId': e.key,
    'name': productNames[e.key] ?? 'Product #${e.key}',
    'quantity': e.value,
  }).toList();
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(reportDateRangeProvider);
    final transactionsAsync = ref.watch(reportTransactionsProvider);
    final stats = ref.watch(reportStatsProvider);
    final topProducts = ref.watch(reportTopProductsProvider);
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? '\$';

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, ref, range),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCards(context, ref, stats, currency),
                  const SizedBox(height: 32),
                  if (topProducts.isNotEmpty) ...[
                    _buildTopProductsSection(context, topProducts),
                    const SizedBox(height: 32),
                  ],
                  transactionsAsync.when(
                    data: (transactions) => SizedBox(
                      height: 500, // Fixed height or adjust as needed
                      child: _buildTransactionList(context, ref, transactions, currency),
                    ),
                    loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D))),
                    error: (e, _) => Center(child: Text('Error: $e')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, DateTimeRange range) {
    final dateFormat = DateFormat('MMM d, yyyy');
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sales Reports',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${dateFormat.format(range.start)} - ${dateFormat.format(range.end)}',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
        Row(
          children: [
            _buildDateRangePicker(context, ref, range),
            const SizedBox(width: 12),
            ActionButton(
              icon: Icons.receipt_long_rounded,
              label: 'ZRA Fiscal Z-Report',
              onPressed: () async {
                final digitaxService = ref.read(digitaxInventoryServiceProvider);
                final printerService = ref.read(printerServiceProvider);
                final config = ref.read(storeConfigProvider).value;

                final reportData = await digitaxService.compileZraFiscalZReport(date: range.start);
                final printed = await printerService.printZraFiscalZReport(
                  reportData: reportData,
                  config: config,
                );

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(printed ? 'ZRA Fiscal Z-Report printed successfully!' : 'ZRA Fiscal Z-Report generated (Check printer connection).'),
                      backgroundColor: printed ? const Color(0xFF10B981) : Colors.orangeAccent,
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 12),
            _buildExportMenu(context, ref),
          ],
        ),
      ],
    );
  }

  Widget _buildDateRangePicker(BuildContext context, WidgetRef ref, DateTimeRange range) {
    return ActionButton(
      icon: Icons.calendar_today_rounded,
      label: 'Select Date Range',
      onPressed: () async {
        final picked = await showDateRangePicker(
          context: context,
          initialDateRange: range,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFFC1F11D),
                  onPrimary: Colors.black,
                  surface: Color(0xFF1A1A1E),
                  onSurface: Colors.white,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          ref.read(reportDateRangeProvider.notifier).state = DateTimeRange(
            start: DateTime(picked.start.year, picked.start.month, picked.start.day, 0, 0, 0, 0),
            end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
          );
        }
      },
    );
  }

  Widget _buildExportMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        final transactions = ref.read(reportTransactionsProvider).value;
        if (transactions == null || transactions.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No transactions to export')),
          );
          return;
        }

        final exportService = ref.read(exportServiceProvider);
        final config = ref.read(storeConfigProvider).value;
        switch (value) {
          case 'pdf':
            await exportService.exportTransactionsToPdf(transactions, config: config);
            break;
          case 'excel':
            await exportService.exportTransactionsToExcel(transactions, config: config);
            break;
          case 'csv':
            await exportService.exportTransactionsToCsv(transactions, config: config);
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
        const PopupMenuItem(value: 'excel', child: Text('Export Excel')),
        const PopupMenuItem(value: 'csv', child: Text('Export CSV')),
      ],
      child: const ActionButton(
        icon: Icons.download_rounded,
        label: 'Export Data',
        isPrimary: true,
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context, WidgetRef ref, Map<String, double> stats, String currency) {
    return Column(
      children: [
        Column(
          children: [
            Row(
              children: [
                _buildStatCard(
                  'Total Revenue',
                  CurrencyFormatter.format(stats['revenue'] ?? 0.0, currency),
                  Icons.payments_rounded,
                  const Color(0xFFC1F11D),
                  subtitle: 'Gross sales amount',
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Gross Profit',
                  CurrencyFormatter.format(stats['profit'] ?? 0.0, currency),
                  (stats['profit'] ?? 0) >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  (stats['profit'] ?? 0) >= 0 ? const Color(0xFFC6B4FF) : Colors.redAccent,
                  subtitle: 'Revenue minus costs',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatCard(
                  'Actual Tax',
                  CurrencyFormatter.format(stats['tax'] ?? 0.0, currency),
                  Icons.account_balance_wallet_rounded,
                  const Color(0xFF5DD39E),
                  subtitle: 'Total VAT collected',
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  'Transactions',
                  (stats['count'] ?? 0).toInt().toString(),
                  Icons.receipt_long_rounded,
                  Colors.orangeAccent,
                  subtitle: 'Number of completed sales',
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 24),
        _buildPaymentBreakdown(context, stats, currency),
      ],
    );
  }

  Widget _buildPaymentBreakdown(BuildContext context, Map<String, double> stats, String currency) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 20, color: Colors.white.withValues(alpha: 0.5)),
              const SizedBox(width: 8),
              Text(
                'Payment Distribution',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildPaymentMethodItem('Cash', stats['cash'] ?? 0.0, currency, Colors.greenAccent),
              _buildVerticalDivider(),
              _buildPaymentMethodItem('Card', stats['card'] ?? 0.0, currency, Colors.blueAccent),
              _buildVerticalDivider(),
              _buildPaymentMethodItem('Mobile Money', stats['mobile_money'] ?? 0.0, currency, Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 40,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white.withValues(alpha: 0.05),
    );
  }

  Widget _buildPaymentMethodItem(String label, double amount, String currency, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.format(amount, currency),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: amount > 0 ? color : Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, {String? subtitle}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161619),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                if (subtitle != null)
                  Icon(Icons.info_outline_rounded, size: 16, color: Colors.white.withValues(alpha: 0.1)),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(BuildContext context, WidgetRef ref, List<SaleTransaction> transactions, String currency) {
    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.receipt_long_rounded, size: 64, color: Colors.white.withValues(alpha: 0.05)),
            ),
            const SizedBox(height: 24),
            Text(
              'No records found for this period',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 20, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            Text(
              'Detailed Transaction History',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.separated(
            itemCount: transactions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              return _buildTransactionCard(context, ref, tx, currency);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionCard(BuildContext context, WidgetRef ref, SaleTransaction tx, String currency) {
    final itemNames = tx.items.map((i) => '${i.quantity}x ${i.productName}').join(', ');

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (context) => ReceiptDetailModal(transaction: tx),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _getPaymentColor(tx.paymentMethod).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getPaymentIcon(tx.paymentMethod),
                    color: _getPaymentColor(tx.paymentMethod),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${tx.id}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: tx.status == 'refunded' ? Colors.redAccent : Colors.white,
                            ),
                          ),
                          if (tx.status == 'refunded') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'REFUNDED',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            DateFormat('MMM d, HH:mm').format(tx.timestamp),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        itemNames.isEmpty ? 'No items recorded' : itemNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          color: Colors.white.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.format(tx.totalAmount, currency),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFC1F11D),
                      ),
                    ),
                    if (tx.taxAmount > 0)
                      Text(
                        'TAX: ${CurrencyFormatter.format(tx.taxAmount, currency)}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    Text(
                      tx.paymentMethod.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () async {
                        final items = await ref.read(transactionItemsProvider(tx.id).future);
                        final config = ref.read(storeConfigProvider).value;
                        ref.read(exportServiceProvider).exportReceiptToPdf(tx, items, config: config, printDirectly: true);
                      },
                      icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white70),
                      tooltip: 'Print Tax Receipt',
                    ),
                    IconButton(
                      onPressed: () async {
                        final items = await ref.read(transactionItemsProvider(tx.id).future);
                        final config = ref.read(storeConfigProvider).value;
                        ref.read(exportServiceProvider).exportReceiptToPdf(tx, items, config: config, printDirectly: false);
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
                      tooltip: 'Export Receipt PDF',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getPaymentIcon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Icons.money_rounded;
      case 'card':
        return Icons.credit_card_rounded;
      case 'mobile_money':
        return Icons.phone_android_rounded;
      default:
        return Icons.payment_rounded;
    }
  }

  Color _getPaymentColor(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Colors.greenAccent;
      case 'card':
        return Colors.blueAccent;
      case 'mobile_money':
        return Colors.orangeAccent;
      default:
        return Colors.white;
    }
  }

  Widget _buildTopProductsSection(BuildContext context, List<Map<String, dynamic>> products) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.star_rounded, size: 20, color: Colors.orangeAccent.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Text(
              'Top Selling Products',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161619),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: products.map((p) => _buildTopProductItem(p)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopProductItem(Map<String, dynamic> product) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${product['quantity']}x',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFFC1F11D),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              product['name'] ?? 'Unknown Product',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.white.withValues(alpha: 0.1)),
        ],
      ),
    );
  }
}

class ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;

  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFFC1F11D) : const Color(0xFF1A1A1E),
          foregroundColor: isPrimary ? Colors.black : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: isPrimary ? BorderSide.none : BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
