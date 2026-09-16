import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/screens/expenses/record_expense_modal.dart';

final expensesStreamProvider = StreamProvider.autoDispose<List<Expense>>((ref) async* {
  final db = ref.watch(databaseServiceProvider);
  yield await db.getAllExpenses();
  await for (final _ in db.isar.expenses.watchLazy()) {
    yield await db.getAllExpenses();
  }
});

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});

  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String _searchQuery = '';
  String _selectedBranchFilter = 'All Branches';
  String _selectedCategoryFilter = 'All Categories';
  String _selectedTimeFilter = 'This Month'; // 'Today', 'This Week', 'This Month', 'All Time', 'Custom'
  DateTimeRange? _customDateRange;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openRecordExpenseModal([Expense? expense]) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RecordExpenseModal(existingExpense: expense),
    ).then((val) {
      if (val == true) {
        ref.invalidate(expensesStreamProvider);
      }
    });
  }

  void _confirmDeleteExpense(Expense expense) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 20),
            ),
            const SizedBox(width: 10),
            Text('Delete Expense Voucher?', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to delete expense "${expense.title}" (${expense.expenseNumber}) of amount ${expense.amount.toStringAsFixed(2)}?',
          style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final db = ref.read(databaseServiceProvider);
              await db.deleteExpense(expense.id);
              ref.invalidate(expensesStreamProvider);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Expense deleted successfully'), backgroundColor: Color(0xFFEF4444)),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  List<Expense> _filterExpenses(List<Expense> allExpenses) {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;

    switch (_selectedTimeFilter) {
      case 'Today':
        start = DateTime(now.year, now.month, now.day);
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'This Week':
        start = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;
      case 'This Month':
        start = DateTime(now.year, now.month, 1);
        end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;
      case 'Custom':
        if (_customDateRange != null) {
          start = _customDateRange!.start;
          end = DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59);
        }
        break;
      case 'All Time':
      default:
        break;
    }

    return allExpenses.where((e) {
      // Date filter
      if (start != null && e.expenseDate.isBefore(start)) return false;
      if (end != null && e.expenseDate.isAfter(end)) return false;

      // Branch filter
      if (_selectedBranchFilter != 'All Branches') {
        final bUpper = _selectedBranchFilter.toUpperCase();
        final eb = e.branch.toUpperCase();
        if (eb != bUpper && !eb.contains(bUpper)) return false;
      }

      // Category filter
      if (_selectedCategoryFilter != 'All Categories') {
        if (e.category.toLowerCase() != _selectedCategoryFilter.toLowerCase()) return false;
      }

      // Search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final title = (e.notes ?? '').toLowerCase();
        final ref = (e.referenceNumber ?? '').toLowerCase();
        final num = e.expenseNumber.toLowerCase();
        final cat = e.category.toLowerCase();
        final rec = (e.recordedBy ?? '').toLowerCase();
        if (!title.contains(q) && !ref.contains(q) && !num.contains(q) && !cat.contains(q) && !rec.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final config = ref.watch(storeConfigProvider).value;
    final currency = config?.currencySymbol ?? 'K';
    final branchesAsync = ref.watch(storeBranchesProvider);
    final expensesAsync = ref.watch(expensesStreamProvider);

    final cardBg = isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF);
    final borderCol = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 700;

        return Container(
          color: theme.scaffoldBackgroundColor,
          padding: EdgeInsets.all(isPhone ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Bar – adaptive
              if (isPhone)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'EXPENSES',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                'OPEX',
                                style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: primaryColor),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            expensesAsync.when(
                              data: (allExps) {
                                final filtered = _filterExpenses(allExps);
                                return PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    final export = ref.read(exportServiceProvider);
                                    if (value == 'pdf') {
                                      await export.exportExpensesToPdf(filtered, config: config);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'pdf',
                                      child: Row(
                                        children: [
                                          Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 16),
                                          SizedBox(width: 8),
                                          Text('Export Expenses (PDF)'),
                                        ],
                                      ),
                                    ),
                                  ],
                                  child: Container(
                                    height: 36,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: borderCol),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.download_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Export',
                                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 11.5, color: theme.colorScheme.onSurface),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () => _openRecordExpenseModal(),
                              icon: const Icon(Icons.add_rounded, size: 15, color: Colors.white),
                              label: Text(
                                'Record',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Record petty cash, utilities, fuel & bills',
                      style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'EXPENSE MANAGEMENT',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                'MULTI-BRANCH OPEX',
                                style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: primaryColor),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Record and audit petty cash, branch utilities, fuel, supplier bills, and operating costs',
                          style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // Export & Reports Dropdown
                        expensesAsync.when(
                          data: (allExps) {
                            final filtered = _filterExpenses(allExps);
                            return PopupMenuButton<String>(
                              onSelected: (value) async {
                                final export = ref.read(exportServiceProvider);
                                if (value == 'pdf') {
                                  await export.exportExpensesToPdf(filtered, config: config);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'pdf',
                                  child: Row(
                                    children: [
                                      Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 16),
                                      SizedBox(width: 8),
                                      Text('Export Expenses Report (PDF)'),
                                    ],
                                  ),
                                ),
                              ],
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderCol),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.download_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Export & Print',
                                      style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: theme.colorScheme.onSurface),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 10),

                        // Record Expense Button
                        ElevatedButton.icon(
                          onPressed: () => _openRecordExpenseModal(),
                          icon: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
                          label: Text(
                            'Record Expense',
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              SizedBox(height: isPhone ? 12 : 16),

              // KPI Summary Metrics Cards – responsive 2x2 on phones
              expensesAsync.when(
                data: (allExpenses) {
                  final now = DateTime.now();
                  final todayStart = DateTime(now.year, now.month, now.day);
                  final monthStart = DateTime(now.year, now.month, 1);

                  final todayExpenses = allExpenses.where((e) => !e.expenseDate.isBefore(todayStart)).toList();
                  final monthExpenses = allExpenses.where((e) => !e.expenseDate.isBefore(monthStart)).toList();

                  final todayTotal = todayExpenses.fold<double>(0.0, (sum, e) => sum + e.amount);
                  final monthTotal = monthExpenses.fold<double>(0.0, (sum, e) => sum + e.amount);

                  // Top category this month
                  final catTotals = <String, double>{};
                  for (final e in monthExpenses) {
                    catTotals[e.category] = (catTotals[e.category] ?? 0.0) + e.amount;
                  }
                  String topCategory = 'None';
                  double topCategoryAmount = 0.0;
                  if (catTotals.isNotEmpty) {
                    final sorted = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                    topCategory = sorted.first.key;
                    topCategoryAmount = sorted.first.value;
                  }

                  final card1 = _buildMetricCard(
                    context,
                    title: 'TODAY\'S EXPENSES',
                    value: '$currency ${todayTotal.toStringAsFixed(2)}',
                    subtitle: '${todayExpenses.length} vouchers recorded',
                    icon: Icons.today_rounded,
                    color: const Color(0xFFF59E0B),
                    isPhone: isPhone,
                  );
                  final card2 = _buildMetricCard(
                    context,
                    title: 'THIS MONTH\'S OPEX',
                    value: '$currency ${monthTotal.toStringAsFixed(2)}',
                    subtitle: '${monthExpenses.length} vouchers this month',
                    icon: Icons.calendar_month_rounded,
                    color: const Color(0xFF3B82F6),
                    isPhone: isPhone,
                  );
                  final card3 = _buildMetricCard(
                    context,
                    title: 'TOP CATEGORY',
                    value: topCategory,
                    subtitle: '$currency ${topCategoryAmount.toStringAsFixed(2)} (${monthTotal > 0 ? (topCategoryAmount / monthTotal * 100).toStringAsFixed(0) : 0}%)',
                    icon: Icons.pie_chart_rounded,
                    color: const Color(0xFF8B5CF6),
                    isPhone: isPhone,
                  );
                  final card4 = _buildMetricCard(
                    context,
                    title: 'TOTAL VOUCHERS',
                    value: allExpenses.length.toString(),
                    subtitle: 'Lifetime tracked vouchers',
                    icon: Icons.receipt_long_rounded,
                    color: const Color(0xFF10B981),
                    isPhone: isPhone,
                  );

                  if (isPhone) {
                    return Column(
                      children: [
                        Row(children: [Expanded(child: card1), const SizedBox(width: 8), Expanded(child: card2)]),
                        const SizedBox(height: 8),
                        Row(children: [Expanded(child: card3), const SizedBox(width: 8), Expanded(child: card4)]),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(child: card1),
                      const SizedBox(width: 12),
                      Expanded(child: card2),
                      const SizedBox(width: 12),
                      Expanded(child: card3),
                      const SizedBox(width: 12),
                      Expanded(child: card4),
                    ],
                  );
                },
                loading: () => const SizedBox(height: 80, child: Center(child: CircularProgressIndicator())),
                error: (_, _) => const SizedBox.shrink(),
              ),
              SizedBox(height: isPhone ? 12 : 16),

              // Search & Filter Toolbar – adaptive on phones
              Container(
                padding: EdgeInsets.symmetric(horizontal: isPhone ? 10 : 14, vertical: isPhone ? 8 : 10),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderCol),
                ),
                child: isPhone
                    ? Column(
                        children: [
                          // Search Input
                          Container(
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: GoogleFonts.inter(fontSize: 12.5),
                              decoration: InputDecoration(
                                hintText: 'Search description, voucher, staff...',
                                hintStyle: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
                                prefixIcon: const Icon(Icons.search_rounded, size: 16),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded, size: 14),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val.trim()),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Horizontal scrolling filter bar
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // Branch Filter Dropdown
                                branchesAsync.when(
                                  data: (branches) {
                                    final branchOptions = ['All Branches', 'Main Branch', ...branches.map((b) => b.name).where((n) => n != 'Main Branch')];
                                    return Container(
                                      height: 32,
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: borderCol),
                                      ),
                                      child: DropdownButtonHideUnderline(
                                        child: DropdownButton<String>(
                                          value: branchOptions.contains(_selectedBranchFilter) ? _selectedBranchFilter : 'All Branches',
                                          items: branchOptions.map((b) {
                                            return DropdownMenuItem(
                                              value: b,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.store_rounded, size: 13, color: primaryColor),
                                                  const SizedBox(width: 4),
                                                  Text(b, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) setState(() => _selectedBranchFilter = val);
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox.shrink(),
                                  error: (_, _) => const SizedBox.shrink(),
                                ),
                                const SizedBox(width: 6),

                                // Category Filter Dropdown
                                Container(
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: borderCol),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedCategoryFilter,
                                      items: const [
                                        'All Categories',
                                        'Transport / Fuel',
                                        'Utilities',
                                        'Rent',
                                        'Salaries & Wages',
                                        'Supplies & Stationery',
                                        'Repairs & Maintenance',
                                        'Marketing & Advertising',
                                        'Taxes & Licenses',
                                        'Meals & Refreshments',
                                        'Other',
                                      ].map((c) {
                                        return DropdownMenuItem(
                                          value: c,
                                          child: Text(c, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) setState(() => _selectedCategoryFilter = val);
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),

                                // Time Range Filter
                                Container(
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: borderCol),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedTimeFilter,
                                      items: const [
                                        'Today',
                                        'This Week',
                                        'This Month',
                                        'All Time',
                                        'Custom',
                                      ].map((t) {
                                        return DropdownMenuItem(
                                          value: t,
                                          child: Text(t, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600)),
                                        );
                                      }).toList(),
                                      onChanged: (val) async {
                                        if (val == 'Custom') {
                                          final range = await showDateRangePicker(
                                            context: context,
                                            firstDate: DateTime(2020),
                                            lastDate: DateTime.now().add(const Duration(days: 1)),
                                          );
                                          if (range != null) {
                                            setState(() {
                                              _customDateRange = range;
                                              _selectedTimeFilter = 'Custom';
                                            });
                                          }
                                        } else if (val != null) {
                                          setState(() => _selectedTimeFilter = val);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          // Search Input
                          Expanded(
                            flex: 3,
                            child: Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: TextField(
                                controller: _searchController,
                                style: GoogleFonts.inter(fontSize: 13),
                                decoration: InputDecoration(
                                  hintText: 'Search by description, reference, notes, or staff...',
                                  hintStyle: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear_rounded, size: 16),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchQuery = '');
                                          },
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                                ),
                                onChanged: (val) => setState(() => _searchQuery = val.trim()),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Branch Filter Dropdown
                          branchesAsync.when(
                            data: (branches) {
                              final branchOptions = ['All Branches', 'Main Branch', ...branches.map((b) => b.name).where((n) => n != 'Main Branch')];
                              return Container(
                                height: 38,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: borderCol),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: branchOptions.contains(_selectedBranchFilter) ? _selectedBranchFilter : 'All Branches',
                                    items: branchOptions.map((b) {
                                      return DropdownMenuItem(
                                        value: b,
                                        child: Row(
                                          children: [
                                            Icon(Icons.store_rounded, size: 14, color: primaryColor),
                                            const SizedBox(width: 6),
                                            Text(b, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedBranchFilter = val);
                                    },
                                  ),
                                ),
                              );
                            },
                            loading: () => const SizedBox.shrink(),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 10),

                          // Category Filter Dropdown
                          Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderCol),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedCategoryFilter,
                                items: const [
                                  'All Categories',
                                  'Transport / Fuel',
                                  'Utilities',
                                  'Rent',
                                  'Salaries & Wages',
                                  'Supplies & Stationery',
                                  'Repairs & Maintenance',
                                  'Marketing & Advertising',
                                  'Taxes & Licenses',
                                  'Meals & Refreshments',
                                  'Other',
                                ].map((c) {
                                  return DropdownMenuItem(
                                    value: c,
                                    child: Text(c, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedCategoryFilter = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Time Range Filter
                          Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderCol),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _selectedTimeFilter,
                                items: const [
                                  'Today',
                                  'This Week',
                                  'This Month',
                                  'All Time',
                                  'Custom',
                                ].map((t) {
                                  return DropdownMenuItem(
                                    value: t,
                                    child: Text(t, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                  );
                                }).toList(),
                                onChanged: (val) async {
                                  if (val == 'Custom') {
                                    final range = await showDateRangePicker(
                                      context: context,
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime.now().add(const Duration(days: 1)),
                                    );
                                    if (range != null) {
                                      setState(() {
                                        _customDateRange = range;
                                        _selectedTimeFilter = 'Custom';
                                      });
                                    }
                                  } else if (val != null) {
                                    setState(() => _selectedTimeFilter = val);
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              SizedBox(height: isPhone ? 12 : 16),

              // Expenses Content (Mobile List vs Desktop Table)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: isPhone ? Colors.transparent : cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: isPhone ? null : Border.all(color: borderCol),
                  ),
                  child: expensesAsync.when(
                    data: (allExpenses) {
                      final filtered = _filterExpenses(allExpenses);

                      if (filtered.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.receipt_long_rounded, size: 40, color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'No Expense Vouchers Found',
                                style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _searchQuery.isNotEmpty || _selectedBranchFilter != 'All Branches' || _selectedCategoryFilter != 'All Categories'
                                    ? 'Try clearing or changing your filters'
                                    : 'Click "Record Expense" to log your first branch operating expense',
                                style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => _openRecordExpenseModal(),
                                icon: const Icon(Icons.add_rounded, size: 16),
                                label: const Text('Record New Expense'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      if (isPhone) {
                        return _buildMobileExpenseList(context, filtered, allExpenses.length, currency, isDark, primaryColor, borderCol);
                      }

                      return Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                              border: Border(bottom: BorderSide(color: borderCol)),
                            ),
                            child: Row(
                              children: [
                                Expanded(flex: 2, child: _tableHeader('VOUCHER #')),
                                Expanded(flex: 2, child: _tableHeader('DATE & TIME')),
                                Expanded(flex: 2, child: _tableHeader('BRANCH')),
                                Expanded(flex: 4, child: _tableHeader('DESCRIPTION / EXACT DETAILS')),
                                Expanded(flex: 2, child: _tableHeader('CATEGORY')),
                                Expanded(flex: 2, child: _tableHeader('PAID FROM')),
                                Expanded(flex: 2, child: _tableHeader('AMOUNT', alignRight: true)),
                                const SizedBox(width: 80, child: Text('ACTIONS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                              ],
                            ),
                          ),

                          // Table Rows
                          Expanded(
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => Divider(height: 1, color: borderCol),
                              itemBuilder: (context, index) {
                                final exp = filtered[index];
                                return _buildExpenseRow(context, exp, currency, isDark, primaryColor);
                              },
                            ),
                          ),

                          // Table Footer (Totals Bar)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                              border: Border(top: BorderSide(color: borderCol)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'SHOWING ${filtered.length} OF ${allExpenses.length} EXPENSE VOUCHERS',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      'FILTERED TOTAL: ',
                                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant),
                                    ),
                                    Text(
                                      '$currency ${filtered.fold<double>(0.0, (sum, e) => sum + e.amount).toStringAsFixed(2)}',
                                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFFEF4444)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Center(child: Text('Error loading expenses: $err')),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileExpenseList(
    BuildContext context,
    List<Expense> expenses,
    int totalCount,
    String currency,
    bool isDark,
    Color primaryColor,
    Color borderCol,
  ) {
    final theme = Theme.of(context);
    final cardBg = isDark ? const Color(0xFF151F32) : Colors.white;

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: expenses.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final exp = expenses[index];
              final isCash = exp.paymentAccountName.toLowerCase().contains('cash');
              final catColor = _getCategoryColor(exp.category);

              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: borderCol),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Voucher # badge, Branch, Date & Time
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.receipt_rounded, size: 12, color: primaryColor),
                              const SizedBox(width: 4),
                              Text(
                                exp.expenseNumber,
                                style: GoogleFonts.inter(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            exp.branch,
                            style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('dd MMM yyyy, HH:mm').format(exp.expenseDate),
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Middle Row: Title / Description + Amount
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                exp.title,
                                style: GoogleFonts.inter(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (exp.referenceNumber != null && exp.referenceNumber!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Ref: ${exp.referenceNumber}',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$currency ${exp.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Category & Payment Account Row
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: catColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            exp.category,
                            style: GoogleFonts.inter(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: catColor,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isCash ? Icons.payments_rounded : Icons.account_balance_rounded,
                                size: 11,
                                color: isCash ? const Color(0xFF10B981) : theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                exp.paymentAccountName,
                                style: GoogleFonts.inter(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: borderCol),
                    const SizedBox(height: 6),

                    // Bottom Row: Recorded By info + Quick Actions
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (exp.recordedBy != null && exp.recordedBy!.isNotEmpty)
                          Text(
                            'By: ${exp.recordedBy}',
                            style: GoogleFonts.inter(
                              fontSize: 10.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.print_rounded, size: 16),
                              tooltip: 'Print Voucher',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () async {
                                final export = ref.read(exportServiceProvider);
                                final config = ref.read(storeConfigProvider).value;
                                await export.exportExpenseVoucherToPdf(exp, config: config, printDirectly: false);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_rounded, size: 16),
                              tooltip: 'Edit Voucher',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () => _openRecordExpenseModal(exp),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                              tooltip: 'Delete Voucher',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () => _confirmDeleteExpense(exp),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // Mobile Summary Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderCol),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${expenses.length} OF $totalCount VOUCHERS',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Row(
                children: [
                  Text(
                    'TOTAL: ',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '$currency ${expenses.fold<double>(0.0, (sum, e) => sum + e.amount).toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(String title, {bool alignRight = false}) {
    final theme = Theme.of(context);
    return Text(
      title,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.5,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildExpenseRow(BuildContext context, Expense exp, String currency, bool isDark, Color primaryColor) {
    final theme = Theme.of(context);
    final isCash = exp.paymentAccountName.toLowerCase().contains('cash');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Voucher #
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(Icons.receipt_rounded, size: 14, color: primaryColor),
                ),
                const SizedBox(width: 8),
                Text(
                  exp.expenseNumber,
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: primaryColor),
                ),
              ],
            ),
          ),

          // Date & Time
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd MMM yyyy, HH:mm').format(exp.expenseDate),
              style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),

          // Branch
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                exp.branch,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Description / Exact Details
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exp.title,
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
                if (exp.referenceNumber != null && exp.referenceNumber!.isNotEmpty)
                  Text(
                    'Ref: ${exp.referenceNumber}',
                    style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),

          // Category
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _getCategoryColor(exp.category).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: _getCategoryColor(exp.category).withValues(alpha: 0.3)),
              ),
              child: Text(
                exp.category,
                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: _getCategoryColor(exp.category)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),

          // Paid From
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(
                  isCash ? Icons.payments_rounded : Icons.account_balance_rounded,
                  size: 14,
                  color: isCash ? const Color(0xFF10B981) : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    exp.paymentAccountName,
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // Amount
          Expanded(
            flex: 2,
            child: Text(
              '$currency ${exp.amount.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFFEF4444)),
            ),
          ),

          // Actions
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Print Voucher PDF
                IconButton(
                  icon: const Icon(Icons.print_rounded, size: 16),
                  tooltip: 'Print Voucher',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () async {
                    final export = ref.read(exportServiceProvider);
                    final config = ref.read(storeConfigProvider).value;
                    await export.exportExpenseVoucherToPdf(exp, config: config, printDirectly: false);
                  },
                ),
                // Edit
                IconButton(
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  tooltip: 'Edit Voucher',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _openRecordExpenseModal(exp),
                ),
                // Delete
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                  tooltip: 'Delete Voucher',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () => _confirmDeleteExpense(exp),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'transport / fuel':
      case 'fuel':
        return const Color(0xFFF59E0B);
      case 'utilities':
        return const Color(0xFF3B82F6);
      case 'rent':
        return const Color(0xFF8B5CF6);
      case 'salaries & wages':
      case 'salaries':
        return const Color(0xFF10B981);
      case 'supplies & stationery':
      case 'supplies':
        return const Color(0xFF06B6D4);
      case 'repairs & maintenance':
      case 'repairs':
        return const Color(0xFFEF4444);
      case 'marketing & advertising':
      case 'marketing':
        return const Color(0xFFEC4899);
      case 'taxes & licenses':
        return const Color(0xFF6366F1);
      case 'meals & refreshments':
        return const Color(0xFF14B8A6);
      default:
        return const Color(0xFF64748B);
    }
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool isPhone = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.all(isPhone ? 10 : 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: isPhone ? 9.5 : 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: EdgeInsets.all(isPhone ? 4 : 5),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                child: Icon(icon, color: color, size: isPhone ? 13 : 15),
              ),
            ],
          ),
          SizedBox(height: isPhone ? 4 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: GoogleFonts.inter(
                fontSize: isPhone ? 14.5 : 16,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
          SizedBox(height: isPhone ? 2 : 3),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: isPhone ? 9.5 : 10.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
