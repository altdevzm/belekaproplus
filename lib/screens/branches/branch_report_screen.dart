import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

enum BranchReportPeriod {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  last30Days,
  thisYear,
  custom,
}

class BranchReportScreen extends ConsumerStatefulWidget {
  final StoreBranch initialBranch;

  const BranchReportScreen({
    super.key,
    required this.initialBranch,
  });

  @override
  ConsumerState<BranchReportScreen> createState() => _BranchReportScreenState();
}

class _BranchReportScreenState extends ConsumerState<BranchReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late StoreBranch _selectedBranch;
  BranchReportPeriod _selectedPeriod = BranchReportPeriod.today;

  late DateTime _startDate;
  late DateTime _endDate;
  bool _isLoading = false;

  List<SaleTransaction> _transactions = [];
  List<Expense> _expenses = [];
  List<StockMovement> _stockMovements = [];
  List<Product> _products = [];

  @override
  void initState() {
    super.initState();
    _selectedBranch = widget.initialBranch;
    _tabController = TabController(length: 3, vsync: this);
    _applyPeriod(BranchReportPeriod.today, reload: false);
    _loadReportData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _applyPeriod(BranchReportPeriod period, {bool reload = true}) {
    final now = DateTime.now();
    _selectedPeriod = period;

    switch (period) {
      case BranchReportPeriod.today:
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case BranchReportPeriod.yesterday:
        final y = now.subtract(const Duration(days: 1));
        _startDate = DateTime(y.year, y.month, y.day);
        _endDate = DateTime(y.year, y.month, y.day, 23, 59, 59, 999);
        break;
      case BranchReportPeriod.thisWeek:
        // Start of week (Monday)
        final daysFromMon = (now.weekday - 1);
        final mon = now.subtract(Duration(days: daysFromMon));
        _startDate = DateTime(mon.year, mon.month, mon.day);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case BranchReportPeriod.thisMonth:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
        break;
      case BranchReportPeriod.last30Days:
        _startDate = now.subtract(const Duration(days: 30));
        _endDate = now;
        break;
      case BranchReportPeriod.thisYear:
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year, 12, 31, 23, 59, 59, 999);
        break;
      case BranchReportPeriod.custom:
        // Keep existing custom dates
        break;
    }

    if (reload) {
      _loadReportData();
    }
  }

  String _getPeriodLabel() {
    switch (_selectedPeriod) {
      case BranchReportPeriod.today:
        return 'Today (${DateFormat('dd MMM yyyy').format(_startDate)})';
      case BranchReportPeriod.yesterday:
        return 'Yesterday (${DateFormat('dd MMM yyyy').format(_startDate)})';
      case BranchReportPeriod.thisWeek:
        return 'This Week (${DateFormat('dd MMM').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)})';
      case BranchReportPeriod.thisMonth:
        return 'This Month (${DateFormat('MMMM yyyy').format(_startDate)})';
      case BranchReportPeriod.last30Days:
        return 'Last 30 Days';
      case BranchReportPeriod.thisYear:
        return 'This Year (${_startDate.year})';
      case BranchReportPeriod.custom:
        return '${DateFormat('dd MMM yyyy').format(_startDate)} - ${DateFormat('dd MMM yyyy').format(_endDate)}';
    }
  }

  Future<void> _loadReportData() async {
    setState(() => _isLoading = true);
    final db = ref.read(databaseServiceProvider);

    try {
      // Automatically pull latest sales from Cloud VPS
      try {
        await ref.read(postgresSyncServiceProvider).pullSalesFromCloud();
      } catch (e) {
        debugPrint('Cloud sales sync pull notice: $e');
      }

      final txs = await db.getTransactionsForBranchInRange(
        _selectedBranch.code,
        branchBhfId: _selectedBranch.bhfId,
        branchName: _selectedBranch.name,
        branchCloudStoreId: _selectedBranch.cloudStoreId > 0 ? _selectedBranch.cloudStoreId : null,
        start: _startDate,
        end: _endDate,
      );

      final exps = await db.getExpensesForBranchInRange(
        _selectedBranch.name,
        branchCode: _selectedBranch.code,
        start: _startDate,
        end: _endDate,
      );

      final movs = await db.getStockMovementsForBranchInRange(
        _selectedBranch.code,
        branchName: _selectedBranch.name,
        start: _startDate,
        end: _endDate,
      );

      final prods = await db.getAllProducts(branchCode: _selectedBranch.code);

      if (mounted) {
        setState(() {
          _transactions = txs;
          _expenses = exps;
          _stockMovements = movs;
          _products = prods;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading report data: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    }
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = BranchReportPeriod.custom;
        _startDate = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59, 999);
      });
      _loadReportData();
    }
  }

  Future<void> _exportPdf({required bool printDirectly}) async {
    final export = ref.read(exportServiceProvider);
    final config = ref.read(storeConfigProvider).value;

    await export.exportBranchComprehensiveReportToPdf(
      branch: _selectedBranch,
      periodLabel: _getPeriodLabel(),
      startDate: _startDate,
      endDate: _endDate,
      transactions: _transactions,
      expenses: _expenses,
      stockMovements: _stockMovements,
      products: _products,
      config: config,
      printDirectly: printDirectly,
    );

    if (mounted && !printDirectly) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Executive Branch Report for ${_selectedBranch.name} exported to PDF!'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final branches = ref.watch(storeBranchesProvider).value ?? [];
    final currentConfig = ref.watch(storeConfigProvider).value;
    final currency = currentConfig?.currencySymbol ?? 'K';

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation Bar
            _buildTopNavHeader(context, isDark, branches),

            // Branch Details & Controls Header
            _buildBranchControlHeader(context, isDark, primaryColor, currency),

            // Tab Bar
            _buildTabBar(context, isDark, primaryColor),

            // Tab Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildSalesPerformanceTab(context, isDark, primaryColor, currency),
                        _buildProfitabilityTab(context, isDark, primaryColor, currency),
                        _buildInventoryTab(context, isDark, primaryColor, currency),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNavHeader(BuildContext context, bool isDark, List<StoreBranch> branches) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 750;

        final titleWidget = Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back to Store Network',
              splashRadius: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text(
                          'Branch Module',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                        Text(
                          'Executive Branch Reports',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'HEADQUARTERS AUDIT & BRANCH REPORT HUB',
                    style: GoogleFonts.inter(
                      fontSize: isPhone ? 13 : 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        );

        final actionButtons = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Branch Switcher Dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedBranch.id,
                  dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                  icon: const Icon(Icons.store_rounded, size: 18),
                  items: branches.map((b) {
                    return DropdownMenuItem<int>(
                      value: b.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: b.status == 'ONLINE' ? const Color(0xFF059669) : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${b.name} (${b.code})',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          if (b.isHQ) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('HQ', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF2563EB))),
                            ),
                          ],
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      final found = branches.firstWhere((b) => b.id == val, orElse: () => _selectedBranch);
                      setState(() {
                        _selectedBranch = found;
                      });
                      _loadReportData();
                    }
                  },
                ),
              ),
            ),
            // Refresh Button
            IconButton(
              onPressed: _loadReportData,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              tooltip: 'Refresh Report',
              splashRadius: 20,
            ),
            // Print Button
            OutlinedButton.icon(
              onPressed: () => _exportPdf(printDirectly: true),
              icon: const Icon(Icons.print_rounded, size: 16),
              label: Text('Print', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            // PDF Export Button
            ElevatedButton.icon(
              onPressed: () => _exportPdf(printDirectly: false),
              icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.white),
              label: Text('Export PDF', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        );

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151F32) : Colors.white,
            border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0))),
          ),
          child: isPhone
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleWidget,
                    const SizedBox(height: 10),
                    actionButtons,
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: titleWidget),
                    actionButtons,
                  ],
                ),
        );
      },
    );
  }

  Widget _buildBranchControlHeader(BuildContext context, bool isDark, Color primaryColor, String currency) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Branch Metadata Chips
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Branch Code: ${_selectedBranch.code}',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: primaryColor),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF059669).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'DigiTax bhfId: ${_selectedBranch.bhfId}',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'Manager: ${_selectedBranch.managerName ?? "Unassigned"}',
                          style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurface),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedBranch.address != null && _selectedBranch.address!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.location_on_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            _selectedBranch.address!,
                            style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                ],
              ),

              // Date Period Selector
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _buildPeriodChip('Today', BranchReportPeriod.today),
                  _buildPeriodChip('Yesterday', BranchReportPeriod.yesterday),
                  _buildPeriodChip('This Week', BranchReportPeriod.thisWeek),
                  _buildPeriodChip('This Month', BranchReportPeriod.thisMonth),
                  _buildPeriodChip('Last 30D', BranchReportPeriod.last30Days),
                  _buildPeriodChip('This Year', BranchReportPeriod.thisYear),
                  ActionChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 14),
                    label: Text(
                      _selectedPeriod == BranchReportPeriod.custom ? _getPeriodLabel() : 'Custom',
                      style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600),
                    ),
                    backgroundColor: _selectedPeriod == BranchReportPeriod.custom ? primaryColor.withValues(alpha: 0.15) : null,
                    side: BorderSide(
                      color: _selectedPeriod == BranchReportPeriod.custom ? primaryColor : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                    ),
                    onPressed: _selectCustomDateRange,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String label, BranchReportPeriod period) {
    final isSelected = _selectedPeriod == period;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return ChoiceChip(
      label: Text(label, style: GoogleFonts.inter(fontSize: 11.5, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
      selected: isSelected,
      selectedColor: primaryColor.withValues(alpha: 0.15),
      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
      side: BorderSide(color: isSelected ? primaryColor : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1))),
      onSelected: (selected) {
        if (selected) {
          _applyPeriod(period);
        }
      },
    );
  }

  Widget _buildTabBar(BuildContext context, bool isDark, Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0))),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: primaryColor,
        unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
        indicatorColor: primaryColor,
        indicatorWeight: 3,
        labelStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(
            icon: Icon(Icons.trending_up_rounded, size: 18),
            text: '1. Sales Performance',
          ),
          Tab(
            icon: Icon(Icons.account_balance_wallet_rounded, size: 18),
            text: '2. Profitability & P&L',
          ),
          Tab(
            icon: Icon(Icons.inventory_2_rounded, size: 18),
            text: '3. Inventory & Stock Audit',
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: SALES PERFORMANCE
  // ==========================================
  Widget _buildSalesPerformanceTab(BuildContext context, bool isDark, Color primaryColor, String currency) {
    final theme = Theme.of(context);

    // Compute sales statistics
    double grossSales = 0.0;
    double refundsAndVoids = 0.0;
    double discountsGiven = 0.0;
    double cashSales = 0.0;
    double cardSales = 0.0;
    double momoSales = 0.0;
    double creditSales = 0.0;
    int completedCount = 0;
    int refundCount = 0;

    // Timeline map: Date String -> Sales Stats
    final Map<String, Map<String, dynamic>> dailyTimeline = {};
    // Terminal map: Terminal/Cashier -> Sales Stats
    final Map<String, Map<String, dynamic>> cashierMap = {};

    for (final tx in _transactions) {
      final dateKey = DateFormat('yyyy-MM-dd').format(tx.timestamp);
      if (!dailyTimeline.containsKey(dateKey)) {
        dailyTimeline[dateKey] = {'gross': 0.0, 'net': 0.0, 'txCount': 0, 'date': tx.timestamp};
      }

      final cashierKey = tx.cashierName.isNotEmpty ? tx.cashierName : (tx.terminalName ?? 'Standard Till');
      if (!cashierMap.containsKey(cashierKey)) {
        cashierMap[cashierKey] = {'amount': 0.0, 'txCount': 0};
      }

      if (tx.status == 'refunded' || tx.isCreditNote) {
        refundCount++;
        refundsAndVoids += tx.totalAmount.abs();
      } else {
        completedCount++;
        grossSales += tx.totalAmount;
        discountsGiven += tx.discountAmount;

        final method = tx.paymentMethod.toLowerCase();
        if (method.contains('cash')) {
          cashSales += tx.totalAmount;
        } else if (method.contains('airtel') || method.contains('mtn') || method.contains('momo') || method.contains('money') || method.contains('zamtel')) {
          momoSales += tx.totalAmount;
        } else if (method.contains('credit') || method.contains('invoice') || method.contains('acc')) {
          creditSales += tx.totalAmount;
        } else {
          cardSales += tx.totalAmount;
        }

        dailyTimeline[dateKey]!['gross'] = (dailyTimeline[dateKey]!['gross'] as double) + tx.totalAmount;
        dailyTimeline[dateKey]!['txCount'] = (dailyTimeline[dateKey]!['txCount'] as int) + 1;

        cashierMap[cashierKey]!['amount'] = (cashierMap[cashierKey]!['amount'] as double) + tx.totalAmount;
        cashierMap[cashierKey]!['txCount'] = (cashierMap[cashierKey]!['txCount'] as int) + 1;
      }
    }

    final double netSales = (grossSales - refundsAndVoids).clamp(0.0, double.infinity);
    final double avgTxValue = completedCount > 0 ? (netSales / completedCount) : 0.0;

    // Compute net for timeline
    for (final entry in dailyTimeline.entries) {
      entry.value['net'] = entry.value['gross'];
    }

    final sortedDays = dailyTimeline.entries.toList()
      ..sort((a, b) => (b.value['date'] as DateTime).compareTo(a.value['date'] as DateTime));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 4 KPI Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - (3 * 16)) / 4;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'TOTAL GROSS SALES',
                    value: '$currency ${grossSales.toStringAsFixed(2)}',
                    subtitle: '$completedCount completed transactions',
                    icon: Icons.payments_rounded,
                    color: const Color(0xFF2563EB),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'NET SALES (AFTER REFUNDS)',
                    value: '$currency ${netSales.toStringAsFixed(2)}',
                    subtitle: 'Realized branch revenue',
                    icon: Icons.monetization_on_rounded,
                    color: const Color(0xFF059669),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'AVERAGE TICKET (ATV)',
                    value: '$currency ${avgTxValue.toStringAsFixed(2)}',
                    subtitle: 'Avg basket value per buyer',
                    icon: Icons.shopping_basket_rounded,
                    color: const Color(0xFF7C3AED),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'DISCOUNTS & REFUNDS',
                    value: '$currency ${(discountsGiven + refundsAndVoids).toStringAsFixed(2)}',
                    subtitle: 'Disc: $currency${discountsGiven.toStringAsFixed(1)} | Ref: $currency${refundsAndVoids.toStringAsFixed(1)} ($refundCount)',
                    icon: Icons.assignment_return_rounded,
                    color: const Color(0xFFEA580C),
                    isDark: isDark,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Middle Row: Payment Methods Breakdown & Cashier Performance
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Payment Methods Card
            Expanded(
              flex: 5,
              child: _buildSectionCard(
                isDark: isDark,
                title: 'Payment Channel Breakdown',
                subtitle: 'Cash, Card/POS, Mobile Money & Credit Invoices',
                icon: Icons.pie_chart_rounded,
                iconColor: const Color(0xFF2563EB),
                child: Column(
                  children: [
                    _buildPaymentProgressRow('Cash Payments', cashSales, netSales, currency, const Color(0xFF059669), Icons.money_rounded),
                    const SizedBox(height: 12),
                    _buildPaymentProgressRow('Card / POS Payments', cardSales, netSales, currency, const Color(0xFF2563EB), Icons.credit_card_rounded),
                    const SizedBox(height: 12),
                    _buildPaymentProgressRow('Mobile Money (Airtel / MTN / Zamtel)', momoSales, netSales, currency, const Color(0xFFD97706), Icons.phone_android_rounded),
                    const SizedBox(height: 12),
                    _buildPaymentProgressRow('Credit Sales / Account Invoices', creditSales, netSales, currency, const Color(0xFF7C3AED), Icons.receipt_long_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Cashiers / Tills Card
            Expanded(
              flex: 5,
              child: _buildSectionCard(
                isDark: isDark,
                title: 'Branch Cashier & Till Performance',
                subtitle: 'Sales recorded by staff at this branch',
                icon: Icons.badge_rounded,
                iconColor: const Color(0xFF059669),
                child: cashierMap.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('No cashier activity in this period', style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      )
                    : Column(
                        children: cashierMap.entries.map((entry) {
                          final pct = netSales > 0 ? (entry.value['amount'] as double) / netSales * 100 : 0.0;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: primaryColor.withValues(alpha: 0.15),
                                  child: Icon(Icons.person, size: 16, color: primaryColor),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(entry.key, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                                      Text('${entry.value['txCount']} transactions (${pct.toStringAsFixed(1)}% of sales)', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                                    ],
                                  ),
                                ),
                                Text(
                                  '$currency ${(entry.value['amount'] as double).toStringAsFixed(2)}',
                                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Timeline Sales by Day / Week
        _buildSectionCard(
          isDark: isDark,
          title: 'Sales by Day / Timeline Breakdown',
          subtitle: 'Daily transaction frequency, gross sales, and volume trends for ${_selectedBranch.name}',
          icon: Icons.calendar_view_day_rounded,
          iconColor: const Color(0xFF7C3AED),
          child: sortedDays.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('No transactions recorded for this branch in the selected timeframe.', style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                  ),
                )
              : Table(
                  border: TableBorder(
                    horizontalInside: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), width: 1),
                  ),
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(1.2),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(3),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC)),
                      children: [
                        _tableHeader('DATE', isDark),
                        _tableHeader('TX COUNT', isDark),
                        _tableHeader('GROSS REVENUE', isDark),
                        _tableHeader('VOLUME VISUALIZER', isDark),
                      ],
                    ),
                    ...sortedDays.map((e) {
                      final dt = e.value['date'] as DateTime;
                      final amt = e.value['gross'] as double;
                      final txC = e.value['txCount'] as int;
                      final maxAmt = sortedDays.map((x) => x.value['gross'] as double).fold(1.0, (prev, curr) => curr > prev ? curr : prev);
                      final progress = (amt / maxAmt).clamp(0.05, 1.0);

                      return TableRow(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: Text(DateFormat('EEE, dd MMM yyyy').format(dt), style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: Text('$txC txns', style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: Text('$currency ${amt.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: const Color(0xFF059669))),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 8,
                                      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                      valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('${(progress * 100).toStringAsFixed(0)}%', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: PROFITABILITY
  // ==========================================
  Widget _buildProfitabilityTab(BuildContext context, bool isDark, Color primaryColor, String currency) {
    final theme = Theme.of(context);

    // Compute profitability
    double grossSales = 0.0;
    double refundsAndVoids = 0.0;
    double discountsGiven = 0.0;
    double cogs = 0.0;

    for (final tx in _transactions) {
      if (tx.status == 'refunded' || tx.isCreditNote) {
        refundsAndVoids += tx.totalAmount.abs();
      } else {
        grossSales += tx.totalAmount;
        discountsGiven += tx.discountAmount;
        cogs += tx.totalCost;
      }
    }

    final double netSales = (grossSales - refundsAndVoids).clamp(0.0, double.infinity);
    final double grossProfit = netSales - cogs;
    final double grossProfitMargin = netSales > 0 ? (grossProfit / netSales * 100) : 0.0;

    // Expenses allocated to this branch
    final double totalBranchExpenses = _expenses.fold(0.0, (sum, e) => sum + e.amount);
    final double netProfitEstimate = grossProfit - totalBranchExpenses;
    final double netProfitMargin = netSales > 0 ? (netProfitEstimate / netSales * 100) : 0.0;

    // Expenses breakdown by category
    final Map<String, double> expensesByCategory = {};
    for (final exp in _expenses) {
      expensesByCategory[exp.category] = (expensesByCategory[exp.category] ?? 0.0) + exp.amount;
    }

    final isProfit = netProfitEstimate >= 0;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 4 KPI Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - (3 * 16)) / 4;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'COST OF GOODS SOLD (COGS)',
                    value: '$currency ${cogs.toStringAsFixed(2)}',
                    subtitle: 'Wholesale acquisition cost of items sold',
                    icon: Icons.inventory_rounded,
                    color: const Color(0xFF64748B),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'GROSS PROFIT',
                    value: '$currency ${grossProfit.toStringAsFixed(2)}',
                    subtitle: 'Gross Margin: ${grossProfitMargin.toStringAsFixed(1)}%',
                    icon: Icons.show_chart_rounded,
                    color: const Color(0xFF0284C7),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'ALLOCATED BRANCH EXPENSES',
                    value: '$currency ${totalBranchExpenses.toStringAsFixed(2)}',
                    subtitle: '${_expenses.length} expense vouchers recorded',
                    icon: Icons.receipt_long_rounded,
                    color: const Color(0xFFEA580C),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'NET PROFIT ESTIMATE',
                    value: '$currency ${netProfitEstimate.toStringAsFixed(2)}',
                    subtitle: 'Net Margin: ${netProfitMargin.toStringAsFixed(1)}% (${isProfit ? "Profitable" : "Operating Loss"})',
                    icon: isProfit ? Icons.check_circle_rounded : Icons.warning_rounded,
                    color: isProfit ? const Color(0xFF059669) : const Color(0xFFDC2626),
                    isDark: isDark,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Income Statement / P&L Breakdown Card
        _buildSectionCard(
          isDark: isDark,
          title: 'Branch Profit & Loss (P&L) Statement',
          subtitle: 'Executive income statement audit for ${_selectedBranch.name}',
          icon: Icons.account_balance_rounded,
          iconColor: const Color(0xFF059669),
          child: Column(
            children: [
              _buildPnLRow('Gross Sales Revenue', grossSales, currency, isDark, isBold: false, isAdd: true),
              _buildPnLRow('Less: Discounts Given', -discountsGiven, currency, isDark, isBold: false, isNegative: true),
              _buildPnLRow('Less: Customer Refunds & Credit Notes', -refundsAndVoids, currency, isDark, isBold: false, isNegative: true),
              const Divider(height: 20),
              _buildPnLRow('NET OPERATING REVENUE', netSales, currency, isDark, isBold: true, color: const Color(0xFF2563EB)),
              const SizedBox(height: 6),
              _buildPnLRow('Less: Cost of Goods Sold (COGS)', -cogs, currency, isDark, isBold: false, isNegative: true),
              const Divider(height: 20),
              _buildPnLRow(
                'GROSS PROFIT (${grossProfitMargin.toStringAsFixed(1)}% Margin)',
                grossProfit,
                currency,
                isDark,
                isBold: true,
                color: const Color(0xFF0284C7),
              ),
              const SizedBox(height: 6),
              _buildPnLRow('Less: Branch Operating Expenses (OPEX)', -totalBranchExpenses, currency, isDark, isBold: false, isNegative: true),
              const Divider(height: 24, thickness: 2),
              _buildPnLRow(
                'ESTIMATED NET OPERATING PROFIT',
                netProfitEstimate,
                currency,
                isDark,
                isBold: true,
                fontSize: 16,
                color: isProfit ? const Color(0xFF059669) : const Color(0xFFDC2626),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Branch Expenses by Category Card
        _buildSectionCard(
          isDark: isDark,
          title: 'Allocated Branch Operating Expenses by Category',
          subtitle: 'Rent, Utilities, Salaries, Fuel, Maintenance, and Supplies',
          icon: Icons.category_rounded,
          iconColor: const Color(0xFFEA580C),
          child: expensesByCategory.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No branch operating expenses recorded for this period.', style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                  ),
                )
              : Column(
                  children: [
                    ...expensesByCategory.entries.map((entry) {
                      final pct = totalBranchExpenses > 0 ? (entry.value / totalBranchExpenses * 100) : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(entry.key, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface)),
                                Text('$currency ${entry.value.toStringAsFixed(2)} (${pct.toStringAsFixed(1)}%)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFEA580C))),
                              ],
                            ),
                            const SizedBox(height: 5),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (pct / 100).clamp(0.02, 1.0),
                                minHeight: 6,
                                backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                valueColor: const AlwaysStoppedAnimation(Color(0xFFEA580C)),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    // Recent Expense Transactions
                    Text('Detailed Expense Vouchers Log', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                    const SizedBox(height: 8),
                    Table(
                      border: TableBorder(
                        horizontalInside: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC)),
                          children: [
                            _tableHeader('VOUCHER #', isDark),
                            _tableHeader('DATE', isDark),
                            _tableHeader('CATEGORY', isDark),
                            _tableHeader('PAYMENT ACCOUNT', isDark),
                            _tableHeader('RECORDED BY', isDark),
                            _tableHeader('AMOUNT', isDark),
                          ],
                        ),
                        ..._expenses.take(10).map((exp) {
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                child: Text(exp.expenseNumber, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: primaryColor)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                child: Text(DateFormat('dd MMM, HH:mm').format(exp.expenseDate), style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                child: Text(exp.category, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                child: Text(exp.paymentAccountName, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                child: Text(exp.recordedBy ?? 'Staff', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                child: Text('$currency ${exp.amount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFEA580C))),
                              ),
                            ],
                          );
                        }),
                      ],
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 3: INVENTORY & STOCK AUDIT
  // ==========================================
  Widget _buildInventoryTab(BuildContext context, bool isDark, Color primaryColor, String currency) {
    final theme = Theme.of(context);

    // Compute inventory stats
    double stockCostValuation = 0.0;
    double stockRetailValuation = 0.0;
    int lowStockCount = 0;
    int outOfStockCount = 0;
    final List<Product> lowStockProducts = [];

    for (final prod in _products) {
      if (!prod.isArchived) {
        final qty = prod.stockLevel;
        stockCostValuation += (qty * prod.unitCost);
        stockRetailValuation += (qty * prod.price);

        if (qty <= 0) {
          outOfStockCount++;
          lowStockProducts.add(prod);
        } else if (qty < 10) {
          lowStockCount++;
          lowStockProducts.add(prod);
        }
      }
    }

    // Items sold calculation & Fast/Slow moving
    final Map<int, Map<String, dynamic>> productSalesMap = {};
    for (final tx in _transactions) {
      if (tx.status != 'refunded' && !tx.isCreditNote) {
        for (final item in tx.items) {
          final pid = item.productId;
          if (!productSalesMap.containsKey(pid)) {
            productSalesMap[pid] = {
              'name': item.productName,
              'qty': 0,
              'revenue': 0.0,
            };
          }
          productSalesMap[pid]!['qty'] = (productSalesMap[pid]!['qty'] as int) + item.quantity;
          productSalesMap[pid]!['revenue'] = (productSalesMap[pid]!['revenue'] as double) + (item.priceAtSale * item.quantity);
        }
      }
    }

    int totalItemsSoldUnits = 0;
    for (final p in productSalesMap.values) {
      totalItemsSoldUnits += (p['qty'] as int);
    }

    // Fast Moving: Top sellers
    final fastMoving = productSalesMap.entries.toList()
      ..sort((a, b) => (b.value['qty'] as int).compareTo(a.value['qty'] as int));

    // Slow Moving: Products with stock > 0 but 0 sales in period
    final slowMoving = _products.where((p) => !p.isArchived && p.stockLevel > 0 && !productSalesMap.containsKey(p.id)).toList()
      ..sort((a, b) => b.stockLevel.compareTo(a.stockLevel));

    // Stock movement breakdowns
    int stockReceivedQty = 0;
    double stockReceivedCost = 0.0;
    int stockTransferredInQty = 0;
    int stockTransferredOutQty = 0;
    int stockDamagedExpiredQty = 0;
    double stockDamagedExpiredCost = 0.0;
    int stockAdjustmentsQty = 0;

    for (final sm in _stockMovements) {
      final rCat = sm.reasonCategory.toLowerCase();
      final act = sm.actionType.toUpperCase();

      if (rCat.contains('restock') || rCat.contains('purchase') || rCat.contains('received')) {
        stockReceivedQty += sm.quantityChanged;
        stockReceivedCost += sm.totalCostImpact > 0 ? sm.totalCostImpact : (sm.quantityChanged * sm.unitCost);
      } else if (rCat.contains('transfer in')) {
        stockTransferredInQty += sm.quantityChanged;
      } else if (rCat.contains('transfer out')) {
        stockTransferredOutQty += sm.quantityChanged;
      } else if (rCat.contains('damage') || rCat.contains('broken') || rCat.contains('expired') || rCat.contains('theft') || rCat.contains('loss')) {
        stockDamagedExpiredQty += sm.quantityChanged;
        stockDamagedExpiredCost += sm.totalCostImpact > 0 ? sm.totalCostImpact : (sm.quantityChanged * sm.unitCost);
      } else if (act == 'RECOUNT' || rCat.contains('shrinkage') || rCat.contains('audit') || rCat.contains('adjustment')) {
        stockAdjustmentsQty += sm.quantityChanged;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 4 KPI Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - (3 * 16)) / 4;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'STOCK VALUATION (COST)',
                    value: '$currency ${stockCostValuation.toStringAsFixed(2)}',
                    subtitle: 'Retail Value: $currency${stockRetailValuation.toStringAsFixed(0)}',
                    icon: Icons.inventory_2_rounded,
                    color: const Color(0xFF2563EB),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'TOTAL ITEMS SOLD',
                    value: '$totalItemsSoldUnits units',
                    subtitle: 'Across ${productSalesMap.length} unique products',
                    icon: Icons.shopping_cart_checkout_rounded,
                    color: const Color(0xFF059669),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'LOW & OUT-OF-STOCK ALERTS',
                    value: '${lowStockCount + outOfStockCount} items',
                    subtitle: 'Out of stock: $outOfStockCount | Low: $lowStockCount',
                    icon: Icons.error_outline_rounded,
                    color: outOfStockCount > 0 ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
                  child: _buildMetricCard(
                    title: 'DAMAGED & ADJUSTMENTS',
                    value: '$stockDamagedExpiredQty dmg / $stockAdjustmentsQty adj',
                    subtitle: 'Damage cost: $currency${stockDamagedExpiredCost.toStringAsFixed(1)}',
                    icon: Icons.published_with_changes_rounded,
                    color: const Color(0xFF7C3AED),
                    isDark: isDark,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Stock Movement Flow Breakdown (Received, Transfers, Damaged, Adjustments)
        _buildSectionCard(
          isDark: isDark,
          title: 'Stock Flow & Inflow/Outflow Audit',
          subtitle: 'Stock received, inter-branch transfers, damages, and audit adjustments for this period',
          icon: Icons.swap_vert_rounded,
          iconColor: const Color(0xFF2563EB),
          child: Row(
            children: [
              Expanded(
                child: _buildStockFlowTile(
                  'Stock Received (Restock/PO)',
                  '+$stockReceivedQty units',
                  'Cost: $currency${stockReceivedCost.toStringAsFixed(2)}',
                  Icons.add_shopping_cart_rounded,
                  const Color(0xFF059669),
                  isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStockFlowTile(
                  'Transfers In / Out',
                  'In: $stockTransferredInQty | Out: $stockTransferredOutQty',
                  'Branch stock transfers',
                  Icons.sync_alt_rounded,
                  const Color(0xFF2563EB),
                  isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStockFlowTile(
                  'Damaged / Expired Goods',
                  '-$stockDamagedExpiredQty units',
                  'Loss: $currency${stockDamagedExpiredCost.toStringAsFixed(2)}',
                  Icons.delete_sweep_rounded,
                  const Color(0xFFDC2626),
                  isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStockFlowTile(
                  'Physical Audit Adjustments',
                  '$stockAdjustmentsQty units',
                  'Audit shrinkage & recounts',
                  Icons.tune_rounded,
                  const Color(0xFF7C3AED),
                  isDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Fast-Moving Products vs Slow-Moving Products Side-by-Side
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fast Moving Table
            Expanded(
              flex: 5,
              child: _buildSectionCard(
                isDark: isDark,
                title: '⚡ Fast-Moving Products (Top Sellers)',
                subtitle: 'Highest unit volume and sales revenue in period',
                icon: Icons.bolt_rounded,
                iconColor: const Color(0xFF059669),
                child: fastMoving.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('No sales recorded in this period', style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      )
                    : Table(
                        border: TableBorder(
                          horizontalInside: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                        ),
                        columnWidths: const {
                          0: FlexColumnWidth(0.6),
                          1: FlexColumnWidth(3),
                          2: FlexColumnWidth(1.2),
                          3: FlexColumnWidth(2),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC)),
                            children: [
                              _tableHeader('#', isDark),
                              _tableHeader('PRODUCT', isDark),
                              _tableHeader('SOLD', isDark),
                              _tableHeader('REVENUE', isDark),
                            ],
                          ),
                          ...fastMoving.take(7).map((entry) {
                            final rank = fastMoving.indexOf(entry) + 1;
                            return TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Text('$rank', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Text(entry.value['name'] as String, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Text('${entry.value['qty']} pcs', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF059669))),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Text('$currency ${(entry.value['revenue'] as double).toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: primaryColor)),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
              ),
            ),
            const SizedBox(width: 16),

            // Slow Moving / Dead Stock Table
            Expanded(
              flex: 5,
              child: _buildSectionCard(
                isDark: isDark,
                title: '⏳ Slow-Moving Products (Zero Period Sales)',
                subtitle: 'Products in stock on shelves with zero movement',
                icon: Icons.hourglass_empty_rounded,
                iconColor: const Color(0xFFD97706),
                child: slowMoving.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('All stocked products have recorded sales!', style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      )
                    : Table(
                        border: TableBorder(
                          horizontalInside: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                        ),
                        columnWidths: const {
                          0: FlexColumnWidth(3),
                          1: FlexColumnWidth(1.5),
                          2: FlexColumnWidth(2),
                        },
                        children: [
                          TableRow(
                            decoration: BoxDecoration(color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC)),
                            children: [
                              _tableHeader('PRODUCT', isDark),
                              _tableHeader('CURRENT STOCK', isDark),
                              _tableHeader('STOCK VALUE', isDark),
                            ],
                          ),
                          ...slowMoving.take(7).map((prod) {
                            final val = prod.stockLevel * prod.price;
                            return TableRow(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Text(prod.name, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Text('${prod.stockLevel} units', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFD97706))),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Text('$currency ${val.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Low-Stock and Out-of-Stock Warning List
        if (lowStockProducts.isNotEmpty)
          _buildSectionCard(
            isDark: isDark,
            title: '⚠️ Low-Stock & Out-of-Stock Warning List',
            subtitle: 'Critical stock levels requiring replenishment for ${_selectedBranch.name}',
            icon: Icons.warning_amber_rounded,
            iconColor: const Color(0xFFDC2626),
            child: Table(
              border: TableBorder(
                horizontalInside: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC)),
                  children: [
                    _tableHeader('PRODUCT NAME', isDark),
                    _tableHeader('BARCODE / SKU', isDark),
                    _tableHeader('CURRENT STOCK', isDark),
                    _tableHeader('REORDER THRESHOLD', isDark),
                    _tableHeader('UNIT COST', isDark),
                    _tableHeader('STATUS', isDark),
                  ],
                ),
                ...lowStockProducts.take(10).map((p) {
                  final isOut = p.stockLevel <= 0;
                  return TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        child: Text(p.name, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        child: Text(p.sku.isNotEmpty ? p.sku : 'N/A', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        child: Text('${p.stockLevel} units', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: isOut ? const Color(0xFFDC2626) : const Color(0xFFEA580C))),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        child: Text('< 10 units', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        child: Text('$currency ${p.unitCost.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isOut ? const Color(0xFFDC2626).withValues(alpha: 0.15) : const Color(0xFFEA580C).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isOut ? 'OUT OF STOCK' : 'LOW STOCK',
                            style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.bold, color: isOut ? const Color(0xFFDC2626) : const Color(0xFFEA580C)),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  // ==========================================
  // SHARED UI HELPER WIDGETS
  // ==========================================
  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant,
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

  Widget _buildSectionCard({
    required bool isDark,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Widget child,
  }) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildPaymentProgressRow(String label, double amount, double total, String currency, Color color, IconData icon) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pct = total > 0 ? (amount / total * 100) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
            ),
            Text(
              '$currency ${amount.toStringAsFixed(2)} ',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            ),
            Text('(${pct.toStringAsFixed(1)}%)', style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.01, 1.0),
            minHeight: 6,
            backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _buildPnLRow(
    String label,
    double amount,
    String currency,
    bool isDark, {
    bool isBold = false,
    bool isNegative = false,
    bool isAdd = false,
    Color? color,
    double fontSize = 13.5,
  }) {
    final theme = Theme.of(context);
    final textColor = color ?? (isNegative ? const Color(0xFFDC2626) : theme.colorScheme.onSurface);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              color: color ?? theme.colorScheme.onSurface,
            ),
          ),
          Text(
            '${amount < 0 ? "-" : (isAdd ? "" : "")}$currency ${amount.abs().toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockFlowTile(String title, String qty, String subtitle, IconData icon, Color color, bool isDark) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(qty, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _tableHeader(String label, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        ),
      ),
    );
  }
}
