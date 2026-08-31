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
import 'package:beleka_pos/screens/reports/tot_report_screen.dart';

enum ReportPeriod { daily, weekly, monthly, yearly, custom }

final reportPeriodProvider = StateProvider<ReportPeriod>((ref) => ReportPeriod.daily);

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

  double revenue = transactions.fold(0.0, (sum, t) {
    if (t.totalAmount.isNaN) return sum;
    if (t.status == 'refunded' && !t.isCreditNote) return sum;
    if (t.isCreditNote) return sum - t.totalAmount;
    return sum + t.totalAmount;
  });
  double profit = transactions.fold(0.0, (sum, t) {
    if (t.grossProfit.isNaN) return sum;
    if (t.status == 'refunded' && !t.isCreditNote) return sum;
    return sum + t.grossProfit;
  });
  double tax = transactions.fold(0.0, (sum, t) {
    if (t.taxAmount.isNaN) return sum;
    if (t.status == 'refunded' && !t.isCreditNote) return sum;
    if (t.isCreditNote) return sum - t.taxAmount;
    return sum + t.taxAmount;
  });

  final Map<String, double> paymentBreakdown = {};
  for (var t in transactions) {
    if (t.status == 'refunded' && !t.isCreditNote) continue;
    final factor = t.isCreditNote ? -1.0 : 1.0;
    final amount = (t.totalAmount.isNaN ? 0.0 : t.totalAmount) * factor;
    final method = t.paymentMethod.toLowerCase().replaceAll(' ', '_');
    paymentBreakdown[method] = (paymentBreakdown[method] ?? 0) + amount;
  }

  final activeCount = transactions.where((t) => t.status != 'refunded' && !t.isCreditNote).length;

  return {
    'revenue': revenue,
    'profit': profit,
    'tax': tax,
    'count': activeCount.toDouble(),
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
    if (t.status == 'refunded') continue;
    for (var item in t.items) {
      if (item.isRefunded) continue;
      final qty = (item.isWeighted && item.weight > 0) ? item.weight.ceil() : item.quantity;
      final factor = t.isCreditNote ? -1 : 1;
      productQuantities[item.productId] = (productQuantities[item.productId] ?? 0) + (qty * factor);
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

  void _applyPeriod(WidgetRef ref, ReportPeriod period) {
    ref.read(reportPeriodProvider.notifier).state = period;
    final now = DateTime.now();

    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    switch (period) {
      case ReportPeriod.daily:
        start = DateTime(now.year, now.month, now.day, 0, 0, 0, 0);
        break;
      case ReportPeriod.weekly:
        final daysToMonday = (now.weekday - DateTime.monday) % 7;
        final startOfWeek = now.subtract(Duration(days: daysToMonday));
        start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day, 0, 0, 0, 0);
        break;
      case ReportPeriod.monthly:
        start = DateTime(now.year, now.month, 1, 0, 0, 0, 0);
        break;
      case ReportPeriod.yearly:
        start = DateTime(now.year, 1, 1, 0, 0, 0, 0);
        break;
      case ReportPeriod.custom:
        return; // Custom range handled by DatePicker
    }

    ref.read(reportDateRangeProvider.notifier).state = DateTimeRange(start: start, end: end);
  }

  String _getPeriodTitle(ReportPeriod period, DateTimeRange range) {
    final df = DateFormat('dd MMM yyyy');
    switch (period) {
      case ReportPeriod.daily:
        return 'DAILY FINANCIAL SUMMARY (${df.format(range.start)})';
      case ReportPeriod.weekly:
        return 'WEEKLY FINANCIAL SUMMARY (${df.format(range.start)} - ${df.format(range.end)})';
      case ReportPeriod.monthly:
        return 'MONTHLY FINANCIAL SUMMARY (${DateFormat('MMMM yyyy').format(range.start)})';
      case ReportPeriod.yearly:
        return 'YEARLY FINANCIAL SUMMARY (${range.start.year})';
      case ReportPeriod.custom:
        return 'FINANCIAL SUMMARY (${df.format(range.start)} - ${df.format(range.end)})';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final range = ref.watch(reportDateRangeProvider);
    final activePeriod = ref.watch(reportPeriodProvider);
    final transactionsAsync = ref.watch(reportTransactionsProvider);
    final stats = ref.watch(reportStatsProvider);
    final topProducts = ref.watch(reportTopProductsProvider);
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? '\$';

    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, ref, range, activePeriod, stats, topProducts),
          const SizedBox(height: 16),
          _buildPeriodSelector(context, ref, activePeriod, range),
          const SizedBox(height: 20),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCards(context, ref, stats, currency, activePeriod, range),
                  const SizedBox(height: 24),
                  if (topProducts.isNotEmpty) ...[
                    _buildTopProductsSection(context, topProducts),
                    const SizedBox(height: 24),
                  ],
                  transactionsAsync.when(
                    data: (transactions) => SizedBox(
                      height: 500,
                      child: _buildTransactionList(context, ref, transactions, currency),
                    ),
                    loading: () => Center(child: CircularProgressIndicator(color: primaryColor)),
                    error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Color(0xFFDC2626)))),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector(BuildContext context, WidgetRef ref, ReportPeriod activePeriod, DateTimeRange range) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final options = [
      {'period': ReportPeriod.daily, 'label': 'Daily (Today)'},
      {'period': ReportPeriod.weekly, 'label': 'Weekly (This Week)'},
      {'period': ReportPeriod.monthly, 'label': 'Monthly (This Month)'},
      {'period': ReportPeriod.yearly, 'label': 'Yearly (This Year)'},
      {'period': ReportPeriod.custom, 'label': 'Custom Range'},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: options.map((opt) {
            final period = opt['period'] as ReportPeriod;
            final isSelected = activePeriod == period;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                onTap: () {
                  if (period == ReportPeriod.custom) {
                    _openCustomDatePicker(context, ref, range);
                  } else {
                    _applyPeriod(ref, period);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? primaryColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    opt['label'] as String,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected ? Colors.white : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _openCustomDatePicker(BuildContext context, WidgetRef ref, DateTimeRange range) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: range,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: theme.colorScheme.primary,
              onPrimary: Colors.white,
              surface: isDark ? const Color(0xFF151F32) : Colors.white,
              onSurface: isDark ? Colors.white : const Color(0xFF172033),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      ref.read(reportPeriodProvider.notifier).state = ReportPeriod.custom;
      ref.read(reportDateRangeProvider.notifier).state = DateTimeRange(
        start: DateTime(picked.start.year, picked.start.month, picked.start.day, 0, 0, 0, 0),
        end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999),
      );
    }
  }

  Widget _buildHeader(
    BuildContext context,
    WidgetRef ref,
    DateTimeRange range,
    ReportPeriod activePeriod,
    Map<String, double> stats,
    List<Map<String, dynamic>> topProducts,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final dateFormat = DateFormat('MMM d, yyyy');
    final todayStr = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Enterprise Breadcrumb Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text('Workspace', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant)),
                Icon(Icons.chevron_right_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                Text('Financial Reports & ZRA Compliance', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: primaryColor)),
              ],
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text('ZRA DigiTax Audit & Fiscal Reporting Active', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF059669))),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF151F32) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                  ),
                  child: Text(todayStr, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Main Header Title and Action Menus Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FINANCIAL & FISCAL REPORTS MANAGEMENT',
                  style: GoogleFonts.inter(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Audit range: ${dateFormat.format(range.start)} - ${dateFormat.format(range.end)}',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            Consumer(
              builder: (context, ref, child) {
                final config = ref.watch(storeConfigProvider).value;
                final isTot = config?.businessTaxType == 'TURNOVER_TAX' || config?.businessTaxType == 'COMPOSITE';
                return Row(
                  children: [
                    _buildFinancialSummaryMenu(context, ref, range, activePeriod, stats, topProducts),
                    const SizedBox(width: 10),
                    _buildStockAdjustmentReportMenu(context, ref, range),
                    const SizedBox(width: 10),
                    _buildZraZReportMenu(context, ref, range),
                    if (isTot) ...[
                      const SizedBox(width: 10),
                      _buildTotReturnButton(context),
                    ],
                    const SizedBox(width: 10),
                    _buildExportMenu(context, ref),
                  ],
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFinancialSummaryMenu(
    BuildContext context,
    WidgetRef ref,
    DateTimeRange range,
    ReportPeriod activePeriod,
    Map<String, double> stats,
    List<Map<String, dynamic>> topProducts,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final df = DateFormat('dd MMM yyyy');
    final dateSubtitle = (range.start.year == range.end.year && range.start.month == range.end.month && range.start.day == range.end.day)
        ? df.format(range.start)
        : '${df.format(range.start)} - ${df.format(range.end)}';
    final title = _getPeriodTitle(activePeriod, range);

    return PopupMenuButton<String>(
      tooltip: 'Financial Summary Actions',
      offset: const Offset(0, 52),
      color: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      onSelected: (value) async {
        final printer = ref.read(printerServiceProvider);
        final exportService = ref.read(exportServiceProvider);
        final config = ref.read(storeConfigProvider).value;

        switch (value) {
          case 'print':
            final printed = await printer.printFinancialSummarySlip(
              periodTitle: title,
              dateRangeLabel: dateSubtitle,
              stats: stats,
              config: config,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(printed
                      ? '$title printed successfully!'
                      : 'Print command sent (check printer connection).'),
                  backgroundColor: printed ? const Color(0xFF059669) : Colors.orangeAccent,
                ),
              );
            }
            break;

          case 'pdf_slip':
            await exportService.exportFinancialSummarySlipToPdf(
              periodTitle: title,
              dateRangeLabel: dateSubtitle,
              stats: stats,
              config: config,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$title Slip (80mm) saved as PDF!'),
                  backgroundColor: const Color(0xFF059669),
                ),
              );
            }
            break;

          case 'pdf_report':
            await exportService.exportFinancialSummaryToPdf(
              periodTitle: title,
              dateRangeLabel: dateSubtitle,
              stats: stats,
              topProducts: topProducts,
              config: config,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('$title Executive Report (A4) saved as PDF!'),
                  backgroundColor: const Color(0xFF059669),
                ),
              );
            }
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'print',
          child: Row(
            children: [
              Icon(Icons.print_rounded, size: 18, color: primaryColor),
              const SizedBox(width: 10),
              Text('Print Financial Slip', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pdf_slip',
          child: Row(
            children: [
              const Icon(Icons.receipt_rounded, size: 18, color: Color(0xFF0284C7)),
              const SizedBox(width: 10),
              Text('Save as PDF Slip (80mm)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pdf_report',
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: 10),
              Text('Save as PDF Report (A4)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
      ],
      child: const ActionButton(
        icon: Icons.payments_rounded,
        label: 'Financial Slip ▾',
        isPrimary: true,
      ),
    );
  }

  Widget _buildZraZReportMenu(BuildContext context, WidgetRef ref, DateTimeRange range) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return PopupMenuButton<String>(
      tooltip: 'ZRA Fiscal Z-Report Actions',
      offset: const Offset(0, 52),
      color: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      onSelected: (value) async {
        final digitaxService = ref.read(digitaxInventoryServiceProvider);
        final printerService = ref.read(printerServiceProvider);
        final exportService = ref.read(exportServiceProvider);
        final config = ref.read(storeConfigProvider).value;

        final reportData = await digitaxService.compileZraFiscalZReport(date: range.start);

        switch (value) {
          case 'print':
            final printed = await printerService.printZraFiscalZReport(
              reportData: reportData,
              config: config,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(printed
                      ? 'ZRA Fiscal Z-Report printed successfully!'
                      : 'ZRA Fiscal Z-Report generated (Check printer connection).'),
                  backgroundColor: printed ? const Color(0xFF059669) : Colors.orangeAccent,
                ),
              );
            }
            break;

          case 'pdf_slip':
            await exportService.exportZraFiscalZReportSlipToPdf(
              reportData: reportData,
              config: config,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('ZRA Fiscal Z-Report Slip (80mm) saved as PDF!'),
                  backgroundColor: Color(0xFF059669),
                ),
              );
            }
            break;

          case 'pdf_report':
            await exportService.exportZraFiscalZReportToPdf(
              reportData: reportData,
              config: config,
            );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Official ZRA Fiscal Z-Report (A4) saved as PDF!'),
                  backgroundColor: Color(0xFF059669),
                ),
              );
            }
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'print',
          child: Row(
            children: [
              Icon(Icons.print_rounded, size: 18, color: primaryColor),
              const SizedBox(width: 10),
              Text('Print Z-Report (Thermal)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pdf_slip',
          child: Row(
            children: [
              const Icon(Icons.receipt_rounded, size: 18, color: Color(0xFF0284C7)),
              const SizedBox(width: 10),
              Text('Save as PDF Slip (80mm)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pdf_report',
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: 10),
              Text('Save Official ZRA PDF (A4)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
      ],
      child: const ActionButton(
        icon: Icons.receipt_long_rounded,
        label: 'ZRA Fiscal Z-Report ▾',
      ),
    );
  }

  Widget _buildStockAdjustmentReportMenu(BuildContext context, WidgetRef ref, DateTimeRange range) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopupMenuButton<String>(
      tooltip: 'Stock Adjustments & ZRA SAR Report',
      offset: const Offset(0, 52),
      color: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      onSelected: (value) async {
        final db = ref.read(databaseServiceProvider);
        final exportService = ref.read(exportServiceProvider);
        final config = ref.read(storeConfigProvider).value;

        final allMovements = await db.getStockMovements();
        // Filter by selected report date range
        final inRange = allMovements.where((m) {
          return m.timestamp.isAfter(range.start) && m.timestamp.isBefore(range.end);
        }).toList();

        if (inRange.isEmpty && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No stock adjustment records found in the selected date range.')),
          );
          return;
        }

        switch (value) {
          case 'print':
            await exportService.exportStockMovementsToPdf(
              inRange,
              config: config,
              dateRange: range,
              printDirectly: true,
            );
            break;
          case 'pdf':
            await exportService.exportStockMovementsToPdf(
              inRange,
              config: config,
              dateRange: range,
              printDirectly: false,
            );
            break;
          case 'excel':
            await exportService.exportStockMovementsToExcel(inRange, config: config);
            break;
          case 'csv':
            await exportService.exportStockMovementsToCsv(inRange, config: config);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'print',
          child: Row(
            children: [
              const Icon(Icons.print_rounded, size: 18, color: Color(0xFF059669)),
              const SizedBox(width: 10),
              Text('Print SAR Audit Report', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: 10),
              Text('Save as PDF Document (A4)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              const Icon(Icons.table_chart_rounded, size: 18, color: Color(0xFF059669)),
              const SizedBox(width: 10),
              Text('Export to Excel (.xlsx)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'csv',
          child: Row(
            children: [
              const Icon(Icons.text_snippet_rounded, size: 18, color: Color(0xFFD97706)),
              const SizedBox(width: 10),
              Text('Export to CSV (.csv)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
      ],
      child: const ActionButton(
        icon: Icons.inventory_2_outlined,
        label: 'Stock SAR Report ▾',
      ),
    );
  }

  Widget _buildTotReturnButton(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TotReportScreen()),
          );
        },
        icon: const Icon(Icons.receipt_long_rounded, size: 16),
        label: Text(
          'TOT Return',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFFBEB),
          foregroundColor: const Color(0xFFD97706),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFFDE68A)),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildExportMenu(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return PopupMenuButton<String>(
      tooltip: 'Export Transactions Data',
      offset: const Offset(0, 52),
      color: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
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
        PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
              const SizedBox(width: 10),
              Text('Export PDF Report', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              const Icon(Icons.table_chart_rounded, size: 18, color: Color(0xFF059669)),
              const SizedBox(width: 10),
              Text('Export Excel (.xlsx)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'csv',
          child: Row(
            children: [
              const Icon(Icons.description_rounded, size: 18, color: Color(0xFF0284C7)),
              const SizedBox(width: 10),
              Text('Export CSV (.csv)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ],
          ),
        ),
      ],
      child: const ActionButton(
        icon: Icons.download_rounded,
        label: 'Export Data ▾',
      ),
    );
  }

  Widget _buildSummaryCards(
    BuildContext context,
    WidgetRef ref,
    Map<String, double> stats,
    String currency,
    ReportPeriod activePeriod,
    DateTimeRange range,
  ) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Column(
      children: [
        Column(
          children: [
            Row(
              children: [
                _buildStatCard(
                  context,
                  'Total Revenue',
                  CurrencyFormatter.format(stats['revenue'] ?? 0.0, currency),
                  Icons.payments_rounded,
                  primaryColor,
                  subtitle: 'Gross sales amount',
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  context,
                  'Gross Profit',
                  CurrencyFormatter.format(stats['profit'] ?? 0.0, currency),
                  (stats['profit'] ?? 0) >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  (stats['profit'] ?? 0) >= 0 ? const Color(0xFF059669) : const Color(0xFFDC2626),
                  subtitle: 'Revenue minus costs',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatCard(
                  context,
                  'Actual Tax (VAT/TOT)',
                  CurrencyFormatter.format(stats['tax'] ?? 0.0, currency),
                  Icons.account_balance_wallet_rounded,
                  const Color(0xFF0284C7),
                  subtitle: 'Total tax collected',
                ),
                const SizedBox(width: 16),
                _buildStatCard(
                  context,
                  'Transactions',
                  (stats['count'] ?? 0).toInt().toString(),
                  Icons.receipt_long_rounded,
                  const Color(0xFFD97706),
                  subtitle: 'Completed sales count',
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
            children: [
              Icon(Icons.pie_chart_outline_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                'PAYMENT METHOD DISTRIBUTION',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildPaymentMethodItem(context, 'Cash Sales', stats['cash'] ?? 0.0, currency, const Color(0xFF059669)),
              _buildVerticalDivider(context),
              _buildPaymentMethodItem(context, 'Card Payments', stats['card'] ?? 0.0, currency, const Color(0xFF0284C7)),
              _buildVerticalDivider(context),
              _buildPaymentMethodItem(context, 'Mobile Money', stats['mobile_money'] ?? 0.0, currency, const Color(0xFFD97706)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: 36,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0),
    );
  }

  Widget _buildPaymentMethodItem(BuildContext context, String label, double amount, String currency, Color color) {
    final theme = Theme.of(context);

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            CurrencyFormatter.format(amount, currency),
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: amount > 0 ? color : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon, Color color, {String? subtitle}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151F32) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(BuildContext context, WidgetRef ref, List<SaleTransaction> transactions, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (transactions.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151F32) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                'No Transaction Records Found',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'No sale transactions recorded in the selected period range.',
                style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'DETAILED TRANSACTION HISTORY',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              '${transactions.length} Total Records',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: transactions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final itemNames = tx.items.map((i) => '${i.quantity}x ${i.productName}').join(', ');

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
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
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? _getPaymentColor(tx.paymentMethod).withValues(alpha: 0.15)
                        : _getPaymentColor(tx.paymentMethod).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _getPaymentIcon(tx.paymentMethod),
                    color: _getPaymentColor(tx.paymentMethod),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${tx.id}',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: tx.status == 'refunded' ? const Color(0xFFDC2626) : theme.colorScheme.onSurface,
                            ),
                          ),
                          if (tx.status == 'refunded') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'REFUNDED',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFFDC2626),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Text(
                            '•  ${DateFormat('dd MMM yyyy, HH:mm').format(tx.timestamp)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        itemNames.isEmpty ? 'No items recorded' : itemNames,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      CurrencyFormatter.format(tx.totalAmount, currency),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: tx.status == 'refunded' ? const Color(0xFFDC2626) : primaryColor,
                      ),
                    ),
                    if (tx.taxAmount > 0)
                      Text(
                        'VAT: ${CurrencyFormatter.format(tx.taxAmount, currency)}',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    Text(
                      tx.paymentMethod.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () async {
                        final items = await ref.read(transactionItemsProvider(tx.id).future);
                        final config = ref.read(storeConfigProvider).value;
                        ref.read(exportServiceProvider).exportReceiptToPdf(tx, items, config: config, printDirectly: true);
                      },
                      icon: Icon(Icons.print_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      tooltip: 'Print Tax Receipt',
                    ),
                    IconButton(
                      onPressed: () async {
                        final items = await ref.read(transactionItemsProvider(tx.id).future);
                        final config = ref.read(storeConfigProvider).value;
                        ref.read(exportServiceProvider).exportReceiptToPdf(tx, items, config: config, printDirectly: false);
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
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
        return const Color(0xFF059669);
      case 'card':
        return const Color(0xFF0284C7);
      case 'mobile_money':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF1D4ED8);
    }
  }

  Widget _buildTopProductsSection(BuildContext context, List<Map<String, dynamic>> products) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.star_rounded, size: 18, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Text(
              'TOP SELLING PRODUCTS IN PERIOD',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151F32) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: products.map((p) => _buildTopProductItem(context, p)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildTopProductItem(BuildContext context, Map<String, dynamic> product) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C283D) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${product['quantity']}x',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: primaryColor,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              product['name'] ?? 'Unknown Product',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: theme.colorScheme.onSurfaceVariant),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? primaryColor : (isDark ? const Color(0xFF151F32) : Colors.white),
          foregroundColor: isPrimary ? Colors.white : theme.colorScheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isPrimary ? BorderSide.none : BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}
