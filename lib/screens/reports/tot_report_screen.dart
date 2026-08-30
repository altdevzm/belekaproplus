import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/tot_service.dart';

import 'package:beleka_pos/services/database_service.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _selectedYearProvider = StateProvider<int>((ref) => DateTime.now().year);
final _selectedMonthProvider = StateProvider<int>((ref) => DateTime.now().month);
final _isLoadingProvider = StateProvider<bool>((ref) => false);

final _totSummaryProvider = FutureProvider.family<TotMonthlySummary?, _SummaryKey>(
  (ref, key) async {
    final config = ref.watch(storeConfigProvider).value;
    final db = ref.watch(databaseServiceProvider);

    // 1. Try Cloud API if configured
    if (config?.cloudApiUrl != null && config!.cloudApiUrl!.isNotEmpty) {
      try {
        final svc = TotService(baseUrl: config.cloudApiUrl!);
        final cloudSummary = await svc.fetchMonthlySummary(
          storeId: config.cloudStoreId ?? 1,
          year: key.year,
          month: key.month,
        );
        if (cloudSummary != null) return cloudSummary;
      } catch (e) {
        debugPrint('TotReport: Cloud fetch failed, falling back to local database: $e');
      }
    }

    // 2. Compile directly from Local Database (Full Offline Support)
    final startOfMonth = DateTime(key.year, key.month, 1, 0, 0, 0);
    final endOfMonth = (key.month == 12)
        ? DateTime(key.year, 12, 31, 23, 59, 59, 999)
        : DateTime(key.year, key.month + 1, 0, 23, 59, 59, 999);

    final monthTxs = await db.getTransactionsInRange(startOfMonth, endOfMonth);

    double grossTurnover = monthTxs.fold(0.0, (sum, t) {
      if (t.totalAmount.isNaN) return sum;
      if (t.status == 'refunded' && !t.isCreditNote) return sum;
      if (t.isCreditNote) return sum - t.totalAmount;
      return sum + t.totalAmount;
    });

    // YTD calculation from Jan 1 to end of current month
    final startOfYear = DateTime(key.year, 1, 1, 0, 0, 0);
    final ytdTxs = await db.getTransactionsInRange(startOfYear, endOfMonth);
    double ytdTurnover = ytdTxs.fold(0.0, (sum, t) {
      if (t.totalAmount.isNaN) return sum;
      if (t.status == 'refunded' && !t.isCreditNote) return sum;
      if (t.isCreditNote) return sum - t.totalAmount;
      return sum + t.totalAmount;
    });

    final totRate = grossTurnover <= 1000.0 ? 0.0 : 5.0;
    final totAmount = grossTurnover <= 1000.0 ? 0.0 : double.parse((grossTurnover * 0.05).toStringAsFixed(2));
    final nextMonth = key.month == 12 ? 1 : key.month + 1;
    final nextYear = key.month == 12 ? key.year + 1 : key.year;
    final dueDateStr = '$nextYear-${nextMonth.toString().padLeft(2, '0')}-14';

    return TotMonthlySummary(
      storeId: config?.cloudStoreId ?? 1,
      storeName: config?.businessName ?? 'Local Store',
      tpin: config?.tpin ?? '1000000000',
      chargeYear: key.year,
      chargeMonth: key.month,
      monthName: DateFormat('MMMM').format(startOfMonth),
      grossTurnover: double.parse(grossTurnover.toStringAsFixed(2)),
      totRatePercent: totRate,
      totAmount: totAmount,
      dueDate: dueDateStr,
      ytdTurnover: double.parse(ytdTurnover.toStringAsFixed(2)),
      annualLimit: 5000000.0,
      overAnnualLimit: ytdTurnover > 5000000.0,
      thresholdWarning: ytdTurnover > 4000000.0,
      alreadyFiled: false,
      filedStatus: 'COMPILED LOCALLY (OFFLINE)',
    );
  },
);

final _totReturnsProvider = FutureProvider.family<List<TotReturnRecord>, int>(
  (ref, storeId) async {
    final config = ref.watch(storeConfigProvider).value;
    if (config == null || config.cloudApiUrl == null || config.cloudApiUrl!.isEmpty) return [];
    final svc = TotService(baseUrl: config.cloudApiUrl!);
    return svc.listReturns(storeId: storeId, year: DateTime.now().year);
  },
);

class _SummaryKey {
  final int storeId, year, month;
  const _SummaryKey(this.storeId, this.year, this.month);
  @override
  bool operator ==(Object o) => o is _SummaryKey && o.storeId == storeId && o.year == year && o.month == month;
  @override
  int get hashCode => Object.hash(storeId, year, month);
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class TotReportScreen extends ConsumerStatefulWidget {
  const TotReportScreen({super.key});

  @override
  ConsumerState<TotReportScreen> createState() => _TotReportScreenState();
}

class _TotReportScreenState extends ConsumerState<TotReportScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(storeConfigProvider).value;
    final storeId = config?.cloudStoreId ?? 1;
    final currency = config?.currencySymbol ?? 'K';
    final year = ref.watch(_selectedYearProvider);
    final month = ref.watch(_selectedMonthProvider);
    final summaryAsync = ref.watch(_totSummaryProvider(_SummaryKey(storeId, year, month)));
    final returnsAsync = ref.watch(_totReturnsProvider(storeId));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D10),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context, currency),
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _buildMonthPicker(context, ref, year, month),
                  const SizedBox(height: 24),
                  summaryAsync.when(
                    data: (summary) => summary != null
                        ? _buildSummarySection(context, ref, summary, currency, storeId, year, month)
                        : _buildOfflineCard(context, ref, storeId, year, month, currency),
                    loading: () => const _LoadingCard(),
                    error: (e, _) => _buildOfflineCard(context, ref, storeId, year, month, currency),
                  ),
                  const SizedBox(height: 32),
                  _buildZraRulesCard(context),
                  const SizedBox(height: 32),
                  _buildReturnHistory(context, ref, returnsAsync, currency, storeId),
                  const SizedBox(height: 40),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── App Bar ─────────────────────────────────────────────────────────────────

  Widget _buildAppBar(BuildContext context, String currency) {
    return SliverAppBar(
      backgroundColor: const Color(0xFF0D0D10),
      expandedHeight: 120,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A1500), Color(0xFF0D0D10)],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5C842).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFF5C842), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Turnover Tax (TOT)',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'ZRA Monthly Return Compiler',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: const Color(0xFFF5C842).withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  // ── Month Picker ─────────────────────────────────────────────────────────────

  Widget _buildMonthPicker(BuildContext context, WidgetRef ref, int year, int month) {
    final now = DateTime.now();
    final months = List.generate(12, (i) => i + 1);
    final years = List.generate(5, (i) => now.year - i);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 16, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(width: 8),
              Text(
                'Reporting Period',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.5),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Month selector
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: month,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E1E22),
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      items: months.map((m) {
                        final name = DateFormat('MMMM').format(DateTime(2024, m));
                        return DropdownMenuItem(value: m, child: Text(name));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) ref.read(_selectedMonthProvider.notifier).state = v;
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Year selector
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: year,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF1E1E22),
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                      items: years.map((y) => DropdownMenuItem(value: y, child: Text('$y'))).toList(),
                      onChanged: (v) {
                        if (v != null) ref.read(_selectedYearProvider.notifier).state = v;
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Summary Section ─────────────────────────────────────────────────────────

  Widget _buildSummarySection(
    BuildContext context,
    WidgetRef ref,
    TotMonthlySummary summary,
    String currency,
    int storeId,
    int year,
    int month,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTurnoverHero(context, summary, currency),
        const SizedBox(height: 16),
        _buildKeyMetricsRow(context, summary, currency),
        const SizedBox(height: 16),
        if (summary.alreadyFiled)
          _buildFiledBanner(context, summary)
        else
          _buildSubmitAction(context, ref, summary, storeId, year, month),
      ],
    );
  }

  Widget _buildTurnoverHero(BuildContext context, TotMonthlySummary summary, String currency) {
    final fmt = NumberFormat('#,##0.00');
    final isNil = summary.totAmount == 0;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isNil
              ? [const Color(0xFF0F2015), const Color(0xFF161619)]
              : [const Color(0xFF231C00), const Color(0xFF161619)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isNil
              ? const Color(0xFF5DD39E).withValues(alpha: 0.25)
              : const Color(0xFFF5C842).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${summary.monthName.toUpperCase()} ${summary.chargeYear}',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (isNil ? const Color(0xFF5DD39E) : const Color(0xFFF5C842)).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isNil ? 'NIL RETURN (0%)' : 'TAX DUE: ${summary.totRatePercent.toStringAsFixed(0)}%',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isNil ? const Color(0xFF5DD39E) : const Color(0xFFF5C842),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Gross Turnover (Total Sales)',
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 4),
          Text(
            '$currency${fmt.format(summary.grossTurnover)}',
            style: GoogleFonts.inter(
              fontSize: 34,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.08)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('TOT Tax Owed to ZRA', style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
                  const SizedBox(height: 2),
                  Text(
                    '$currency${fmt.format(summary.totAmount)}',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isNil ? const Color(0xFF5DD39E) : const Color(0xFFF5C842),
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Payment Deadline', style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.5))),
                  const SizedBox(height: 2),
                  Text(
                    summary.dueDate,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeyMetricsRow(BuildContext context, TotMonthlySummary summary, String currency) {
    final fmt = NumberFormat('#,##0.00');
    final ytdPct = ((summary.ytdTurnover / summary.annualLimit) * 100).clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YTD Turnover vs ZRA Limit',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.7)),
              ),
              Text(
                '${ytdPct.toStringAsFixed(1)}% of K5.0M Limit',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: summary.overAnnualLimit
                      ? Colors.redAccent
                      : (summary.thresholdWarning ? const Color(0xFFF5C842) : const Color(0xFF5DD39E)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (summary.ytdTurnover / summary.annualLimit).clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: AlwaysStoppedAnimation(
                summary.overAnnualLimit
                    ? Colors.redAccent
                    : (summary.thresholdWarning ? const Color(0xFFF5C842) : const Color(0xFF5DD39E)),
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('YTD Accumulated: $currency${fmt.format(summary.ytdTurnover)}', style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
              Text('Limit: ${currency}5,000,000', style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
          if (summary.overAnnualLimit) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Turnover exceeds K5,000,000 limit. Under ZRA rules, you must transition to Standard Income Tax / VAT.',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFiledBanner(BuildContext context, TotMonthlySummary summary) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF5DD39E).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5DD39E).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF5DD39E), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Return Filed for this Period',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF5DD39E)),
                ),
                Text(
                  'Status: ${summary.filedStatus ?? "SUBMITTED"} • Return ID: #${summary.filedReturnId ?? "N/A"}',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitAction(
    BuildContext context,
    WidgetRef ref,
    TotMonthlySummary summary,
    int storeId,
    int year,
    int month,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: () => _submitReturn(context, ref, summary, storeId, year, month),
        icon: const Icon(Icons.send_rounded, size: 20),
        label: Text(
          summary.totAmount == 0
              ? 'File NIL Return (K0.00 TOT)'
              : 'Submit TOT Return — K${NumberFormat('#,##0.00').format(summary.totAmount)}',
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF5C842),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }

  Future<void> _submitReturn(
    BuildContext context,
    WidgetRef ref,
    TotMonthlySummary summary,
    int storeId,
    int year,
    int month,
  ) async {
    final config = ref.read(storeConfigProvider).value;
    if (config?.cloudApiUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud connection required to submit TOT return.')),
      );
      return;
    }

    // Confirm dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Submit TOT Return', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Period: ${summary.monthName} ${summary.chargeYear}',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 8),
            Text('Gross Turnover: K${NumberFormat('#,##0.00').format(summary.grossTurnover)}',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 4),
            Text(
              'TOT Amount: K${NumberFormat('#,##0.00').format(summary.totAmount)} (${summary.totRatePercent.toStringAsFixed(0)}%)',
              style: GoogleFonts.inter(
                color: const Color(0xFFF5C842),
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text('This return will be submitted to ZRA via DigiTax.',
                style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF5C842),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Confirm & Submit', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Submit
    ref.read(_isLoadingProvider.notifier).state = true;
    final svc = TotService(baseUrl: config!.cloudApiUrl!);
    final result = await svc.submitReturn(storeId: storeId, year: year, month: month);
    ref.read(_isLoadingProvider.notifier).state = false;

    // Invalidate to refresh UI
    ref.invalidate(_totSummaryProvider(_SummaryKey(storeId, year, month)));
    ref.invalidate(_totReturnsProvider(storeId));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result != null
                ? result.message
                : 'Return submitted locally. Ref: ${result?.digitaxReference ?? 'N/A'}',
          ),
          backgroundColor: const Color(0xFF5DD39E),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ── Offline / No Cloud Card ─────────────────────────────────────────────────

  Widget _buildOfflineCard(
    BuildContext context,
    WidgetRef ref,
    int storeId,
    int year,
    int month,
    String currency,
  ) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cloud_off_rounded, size: 48, color: Colors.white.withValues(alpha: 0.1)),
          ),
          const SizedBox(height: 20),
          Text(
            'Cloud Connection Required',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'TOT reports are compiled from your cloud sales database.\n'
            'Configure the Cloud API URL in Settings to proceed.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, color: Colors.white38, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── ZRA Rules Card ──────────────────────────────────────────────────────────

  Widget _buildZraRulesCard(BuildContext context) {
    final rules = [
      ('≤ K1,000/month', '0% TOT — NIL return required (K12,000/year exemption)'),
      ('> K1,000/month', '5% of monthly gross sales / turnover'),
      ('Purchase Orders', 'Input VAT cannot be deducted (forms part of inventory cost)'),
      ('Return deadline', '14th of the following month'),
      ('Annual limit', 'K5,000,000 — must switch to Income Tax'),
      ('Records', 'Must be kept for 6 years'),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF5C842).withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_rounded, size: 16, color: const Color(0xFFF5C842).withValues(alpha: 0.7)),
              const SizedBox(width: 8),
              Text(
                'ZRA TOT Rules at a Glance',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFF5C842).withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...rules.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(top: 6, right: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5C842).withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: '${r.$1}  ',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          TextSpan(
                            text: r.$2,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ── Return History ───────────────────────────────────────────────────────────

  Widget _buildReturnHistory(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<TotReturnRecord>> returnsAsync,
    String currency,
    int storeId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.history_rounded, size: 18, color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(width: 8),
            Text(
              'Filing History — ${DateTime.now().year}',
              style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),
        returnsAsync.when(
          data: (records) => records.isEmpty
              ? _buildEmptyHistory()
              : Column(
                  children: records.map((r) => _buildReturnRow(context, ref, r, currency, storeId)).toList(),
                ),
          loading: () => const _LoadingCard(),
          error: (e, _) => _buildEmptyHistory(),
        ),
      ],
    );
  }

  Widget _buildEmptyHistory() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Center(
        child: Text(
          'No TOT returns filed this year yet.',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white24),
        ),
      ),
    );
  }

  Widget _buildReturnRow(
    BuildContext context,
    WidgetRef ref,
    TotReturnRecord record,
    String currency,
    int storeId,
  ) {
    final (statusColor, statusLabel, statusIcon) = switch (record.status) {
      'paid' => (const Color(0xFF5DD39E), 'Paid', Icons.check_circle_rounded),
      'submitted' => (const Color(0xFFF5C842), 'Submitted', Icons.receipt_rounded),
      _ => (Colors.white38, 'Draft', Icons.edit_note_rounded),
    };
    final fmt = NumberFormat('#,##0.00');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: record.status == 'submitted'
              ? () => _showMarkPaidDialog(context, ref, record, storeId)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                // Month badge
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      record.monthName.substring(0, 3).toUpperCase(),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${record.monthName} ${record.chargeYear}',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Turnover: $currency ${fmt.format(record.grossTurnover)}',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$currency ${fmt.format(record.totAmount)}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: record.totAmount > 0 ? Colors.white : Colors.white38,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(statusIcon, size: 11, color: statusColor),
                          const SizedBox(width: 4),
                          Text(
                            statusLabel,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
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

  Future<void> _showMarkPaidDialog(
    BuildContext context,
    WidgetRef ref,
    TotReturnRecord record,
    int storeId,
  ) async {
    final config = ref.read(storeConfigProvider).value;
    if (config?.cloudApiUrl == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Mark as Paid?', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Text(
          'Confirm payment of K${NumberFormat('#,##0.00').format(record.totAmount)} TOT for ${record.monthName} ${record.chargeYear}.',
          style: GoogleFonts.inter(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5DD39E),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Confirm Paid', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final svc = TotService(baseUrl: config!.cloudApiUrl!);
    final ok = await svc.markPaid(storeId: storeId, returnId: record.id);
    ref.invalidate(_totReturnsProvider(storeId));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Return marked as paid!' : 'Failed to update status. Please try again.'),
          backgroundColor: ok ? const Color(0xFF5DD39E) : Colors.redAccent,
        ),
      );
    }
  }
}

// ─── Loading Card ──────────────────────────────────────────────────────────────

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF5C842)),
          ),
        ),
      ),
    );
  }
}
