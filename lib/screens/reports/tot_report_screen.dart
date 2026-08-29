import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/tot_service.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final _selectedYearProvider = StateProvider<int>((ref) => DateTime.now().year);
final _selectedMonthProvider = StateProvider<int>((ref) => DateTime.now().month);
final _isLoadingProvider = StateProvider<bool>((ref) => false);

final _totSummaryProvider = FutureProvider.family<TotMonthlySummary?, _SummaryKey>(
  (ref, key) async {
    final config = ref.watch(storeConfigProvider).value;
    if (config == null || config.cloudApiUrl == null || config.cloudApiUrl!.isEmpty) return null;
    final svc = TotService(baseUrl: config.cloudApiUrl!);
    return svc.fetchMonthlySummary(
      storeId: config.cloudStoreId ?? 1,
      year: key.year,
      month: key.month,
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
                child: _buildDropdown<int>(
                  value: month,
                  items: months,
                  label: (m) => DateFormat('MMMM').format(DateTime(year, m)),
                  onChanged: (v) => ref.read(_selectedMonthProvider.notifier).state = v,
                ),
              ),
              const SizedBox(width: 12),
              // Year selector
              Expanded(
                flex: 2,
                child: _buildDropdown<int>(
                  value: year,
                  items: years,
                  label: (y) => '$y',
                  onChanged: (v) => ref.read(_selectedYearProvider.notifier).state = v,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required void Function(T) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1E1E25),
          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white),
          icon: Icon(Icons.expand_more_rounded, color: Colors.white.withValues(alpha: 0.4), size: 18),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(label(item)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  // ── Summary Section (when cloud connected) ──────────────────────────────────

  Widget _buildSummarySection(
    BuildContext context,
    WidgetRef ref,
    TotMonthlySummary summary,
    String currency,
    int storeId,
    int year,
    int month,
  ) {
    final fmt = NumberFormat('#,##0.00');
    final dueDate = summary.dueDate.isNotEmpty ? DateTime.tryParse(summary.dueDate) : null;
    final dueFmt = dueDate != null ? DateFormat('dd MMMM yyyy').format(dueDate) : summary.dueDate;

    return Column(
      children: [
        // Eligibility status
        if (summary.overAnnualLimit) _buildAlertBanner(
          icon: Icons.warning_amber_rounded,
          color: Colors.redAccent,
          title: 'Annual Limit Exceeded — K5,000,000',
          subtitle: 'You must notify the ZRA Commissioner General. You will move to Income Tax next charge year.',
        ) else if (summary.thresholdWarning) _buildAlertBanner(
          icon: Icons.info_outline_rounded,
          color: Colors.orangeAccent,
          title: 'Approaching K5,000,000 Annual Limit',
          subtitle: 'YTD turnover is K${fmt.format(summary.ytdTurnover)}. Plan ahead for possible Income Tax transition.',
        ),
        if (summary.overAnnualLimit || summary.thresholdWarning) const SizedBox(height: 16),

        // Main summary cards
        Row(
          children: [
            _buildSummaryCard(
              label: 'Gross Turnover',
              value: '$currency ${fmt.format(summary.grossTurnover)}',
              icon: Icons.store_rounded,
              color: Colors.white,
              subtitle: '${summary.monthName} ${summary.chargeYear}',
            ),
            const SizedBox(width: 16),
            _buildSummaryCard(
              label: 'TOT Owed',
              value: '$currency ${fmt.format(summary.totAmount)}',
              icon: Icons.account_balance_rounded,
              color: summary.totAmount > 0 ? const Color(0xFFF5C842) : const Color(0xFF5DD39E),
              subtitle: summary.totRatePercent == 0
                  ? 'Below threshold — 0%'
                  : '${summary.totRatePercent.toStringAsFixed(0)}% of gross turnover',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildSummaryCard(
              label: 'YTD Turnover',
              value: '$currency ${fmt.format(summary.ytdTurnover)}',
              icon: Icons.trending_up_rounded,
              color: const Color(0xFFC6B4FF),
              subtitle: 'Jan – ${summary.monthName} ${summary.chargeYear}',
            ),
            const SizedBox(width: 16),
            _buildSummaryCard(
              label: 'Return Due Date',
              value: dueFmt,
              icon: Icons.event_rounded,
              color: _dueDateColor(dueDate),
              subtitle: 'File by 14th of next month',
              valueFontSize: 16,
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Action — submit or mark paid
        if (summary.alreadyFiled)
          _buildFiledBadge(summary)
        else
          _buildSubmitButton(context, ref, summary, storeId, year, month),
      ],
    );
  }

  Color _dueDateColor(DateTime? due) {
    if (due == null) return Colors.white70;
    final today = DateTime.now();
    if (due.isBefore(today)) return Colors.redAccent;
    if (due.difference(today).inDays <= 3) return Colors.orangeAccent;
    return const Color(0xFF5DD39E);
  }

  Widget _buildAlertBanner({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 4),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    double valueFontSize = 20,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF161619),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.4),
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                fontSize: valueFontSize,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFiledBadge(TotMonthlySummary summary) {
    final isPaid = summary.filedStatus == 'paid';
    final color = isPaid ? const Color(0xFF5DD39E) : const Color(0xFFF5C842);
    final icon = isPaid ? Icons.check_circle_rounded : Icons.receipt_rounded;
    final text = isPaid ? 'Return Paid ✓' : 'Return Filed — Awaiting Payment';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Text(text, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(
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
      ('≤ K2,500/month', '0% TOT — Nil return required'),
      ('> K2,500/month', '5% of gross turnover'),
      ('Return deadline', '14th of the following month'),
      ('Annual limit', 'K5,000,000 — switch to Income Tax'),
      ('Records', 'Must be kept for 6 years'),
      ('Excluded', 'Partnerships, mining, consultancy, PSV < 50 seats'),
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
