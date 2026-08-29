import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/tax_reminder_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:isar/isar.dart';

// ─── Local Tax Statement Computation ──────────────────────────────────────────

DateTime _dueDate(int chargeYear, int chargeMonth, int dueDay) {
  int dueMonth = chargeMonth + 1;
  int dueYear = chargeYear;
  if (dueMonth > 12) {
    dueMonth = 1;
    dueYear++;
  }
  return DateTime(dueYear, dueMonth, dueDay);
}

Future<Map<String, dynamic>> _computeLocalTaxStatement(
  DatabaseService db,
  StoreConfig? config,
  int year,
  int month,
) async {
  final taxType = config?.businessTaxType ?? 'VAT_STANDARD';
  final startOfMonth = DateTime(year, month, 1);
  final nextMonth = month == 12 ? 1 : month + 1;
  final nextYear = month == 12 ? year + 1 : year;
  final endOfMonth = DateTime(nextYear, nextMonth, 1).subtract(const Duration(milliseconds: 1));

  final transactions = await db.isar.saleTransactions
      .filter()
      .timestampBetween(startOfMonth, endOfMonth)
      .findAll();

  final validTx = transactions.where((t) => t.status != 'refunded').toList();
  final taxes = <Map<String, dynamic>>[];

  if (taxType == 'TURNOVER_TAX') {
    double grossTurnover = 0.0;
    for (var t in validTx) {
      grossTurnover += (t.totalAmount.isNaN ? 0.0 : t.totalAmount);
    }
    final totRate = grossTurnover <= 2500.0 ? 0.0 : 5.0;
    final totAmount = grossTurnover <= 2500.0 ? 0.0 : (grossTurnover * 0.05);

    final startOfYear = DateTime(year, 1, 1);
    final ytdTx = await db.isar.saleTransactions
        .filter()
        .timestampBetween(startOfYear, endOfMonth)
        .findAll();
    double ytdTurnover = 0.0;
    for (var t in ytdTx.where((t) => t.status != 'refunded')) {
      ytdTurnover += (t.totalAmount.isNaN ? 0.0 : t.totalAmount);
    }

    final due = _dueDate(year, month, 14);

    taxes.add({
      'tax_code': 'TOT',
      'tax_name': 'Turnover Tax (TOT)',
      'description': '5% on gross monthly turnover above K2,500',
      'gross_sales': grossTurnover,
      'taxable_base': grossTurnover,
      'rate_percent': totRate,
      'amount_payable': totAmount,
      'nil_return': totAmount == 0.0,
      'due_date': due.toIso8601String(),
      'due_day': 14,
      'is_filed': false,
      'supplemental': {
        'ytd_turnover': ytdTurnover,
        'annual_limit': 5000000.0,
        'over_annual_limit': ytdTurnover > 5000000.0,
        'threshold_warning_80pct': ytdTurnover > 4000000.0,
      },
    });
  }

  if (taxType == 'VAT_STANDARD' || taxType == 'COMPOSITE') {
    double grossSales = 0.0;
    double outputVat = 0.0;
    for (var t in validTx) {
      final total = t.totalAmount.isNaN ? 0.0 : t.totalAmount;
      final tax = (t.taxAmount.isNaN || t.taxAmount == 0.0)
          ? (total * 16.0 / 116.0)
          : t.taxAmount;
      grossSales += total;
      outputVat += tax;
    }

    final purchases = await db.isar.purchaseOrders.where().findAll();
    double poTotal = 0.0;
    for (var po in purchases) {
      if (po.createdAt.year == year &&
          po.createdAt.month == month &&
          po.status == 'received') {
        poTotal += (po.totalAmount.isNaN ? 0.0 : po.totalAmount);
      }
    }

    final inputVat = poTotal * 16.0 / 116.0;
    final netVat = outputVat - inputVat;
    final amountPayable = netVat > 0 ? netVat : 0.0;
    final refundClaim = netVat < 0 ? (-netVat) : 0.0;
    final due = _dueDate(year, month, 18);

    taxes.add({
      'tax_code': 'VAT',
      'tax_name': 'Value Added Tax (VAT) — Suppliers',
      'description': '16% VAT on taxable supplies (Output VAT less Input VAT)',
      'gross_sales': grossSales,
      'taxable_base': grossSales - outputVat,
      'rate_percent': 16.0,
      'output_vat': outputVat,
      'input_vat': inputVat,
      'amount_payable': amountPayable,
      'vat_refund_claim': refundClaim,
      'nil_return': amountPayable == 0.0 && refundClaim == 0.0,
      'due_date': due.toIso8601String(),
      'due_day': 18,
      'is_filed': false,
      'supplemental': {
        'total_purchases_inclusive': poTotal,
        'net_purchases_ex_vat': poTotal - inputVat,
      },
    });
  }

  double totalAutoComputed = 0.0;
  for (var t in taxes) {
    final amt = (t['amount_payable'] as num?)?.toDouble();
    if (amt != null) totalAutoComputed += amt;
  }

  return {
    'store_id': config?.cloudStoreId ?? 1,
    'store_name': config?.businessName ?? 'Beleka POS',
    'tpin': config?.tpin ?? 'Not Set',
    'bhf_id': config?.bhfId ?? '00',
    'business_tax_type': taxType,
    'charge_year': year,
    'charge_month': month,
    'month_label': '${DateFormat('MMMM').format(DateTime(year, month))} $year',
    'generated_at': DateTime.now().toIso8601String(),
    'total_auto_computed_payable': totalAutoComputed,
    'taxes': taxes,
  };
}

// ─── Providers ────────────────────────────────────────────────────────────────

final _taxBannerDismissedProvider = StateProvider<bool>((ref) => false);

/// Quick local deadlines (no API) for the banner chip — strictly filtered by tax type.
final taxDeadlinesProvider = Provider<List<ZraTaxDeadline>>((ref) {
  final config = ref.watch(storeConfigProvider).value;
  if (config == null) return [];
  return ref
      .watch(taxReminderServiceProvider)
      .getLocalDeadlines(businessTaxType: config.businessTaxType);
});

/// Full tax statement fetched from the backend API or computed locally from Isar DB.
final _taxStatementProvider =
    FutureProvider.family<Map<String, dynamic>?, _StatementKey>(
  (ref, key) async {
    final config = ref.watch(storeConfigProvider).value;
    String? baseUrl = config?.cloudApiUrl?.trim();
    if (baseUrl != null && baseUrl.isNotEmpty) {
      try {
        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 3),
        ));
        final resp = await dio.get(
          '$baseUrl/api/v1/tax-statement/monthly/${config?.cloudStoreId ?? 1}',
          queryParameters: {'year': key.year, 'month': key.month},
        );
        if (resp.statusCode == 200) {
          return Map<String, dynamic>.from(resp.data);
        }
      } catch (e) {
        debugPrint('TaxStatement remote fetch error, computing locally: $e');
      }
    }

    // Fallback to local computation from Isar DB
    final db = ref.read(databaseServiceProvider);
    return await _computeLocalTaxStatement(db, config, key.year, key.month);
  },
);

class _StatementKey {
  final int storeId, year, month;
  const _StatementKey(this.storeId, this.year, this.month);
  @override
  bool operator ==(Object o) =>
      o is _StatementKey &&
      o.storeId == storeId &&
      o.year == year &&
      o.month == month;
  @override
  int get hashCode => Object.hash(storeId, year, month);
}

// ─── Banner Chip ──────────────────────────────────────────────────────────────

class TaxReminderBanner extends ConsumerWidget {
  const TaxReminderBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(_taxBannerDismissedProvider);
    if (dismissed) return const SizedBox.shrink();

    final deadlines = ref.watch(taxDeadlinesProvider);
    if (deadlines.isEmpty) return const SizedBox.shrink();

    final urgent = deadlines.first;
    final svc = ref.watch(taxReminderServiceProvider);
    final color = svc.urgencyColor(urgent.urgency);
    final label = svc.urgencyLabel(urgent);

    return GestureDetector(
      onTap: () => _openModal(context, ref),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              urgent.urgency == TaxUrgency.overdue
                  ? Icons.error_rounded
                  : Icons.notifications_active_rounded,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 5),
            Text(
              '${urgent.taxCode} $label',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            if (deadlines.length > 1) ...[
              const SizedBox(width: 4),
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    '${deadlines.length}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () =>
                  ref.read(_taxBannerDismissedProvider.notifier).state = true,
              child: Icon(Icons.close_rounded,
                  size: 12, color: color.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }

  void _openModal(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (ctx) => _TaxPaymentModal(parentRef: ref),
    );
  }
}

// ─── Tax Payment Modal ────────────────────────────────────────────────────────

class _TaxPaymentModal extends ConsumerStatefulWidget {
  final WidgetRef parentRef;
  const _TaxPaymentModal({required this.parentRef});

  @override
  ConsumerState<_TaxPaymentModal> createState() => _TaxPaymentModalState();
}

class _TaxPaymentModalState extends ConsumerState<_TaxPaymentModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _scaleAnim;
  bool _exporting = false;
  int? _selectedYear;
  int? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _scaleAnim =
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutBack);
    _animCtrl.forward();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(storeConfigProvider).value;
    final now = DateTime.now();
    final chargeYear = _selectedYear ?? now.year;
    final chargeMonth = _selectedMonth ?? now.month;
    final storeId = config?.cloudStoreId ?? 1;

    final statementAsync = ref.watch(
        _taxStatementProvider(_StatementKey(storeId, chargeYear, chargeMonth)));

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720),
          decoration: BoxDecoration(
            color: const Color(0xFF111115),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.65),
                blurRadius: 48,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, config, chargeYear, chargeMonth),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: statementAsync.when(
                      data: (statement) => _buildStatementBody(
                        context,
                        statement ?? {
                          'business_tax_type': config?.businessTaxType ?? 'VAT_STANDARD',
                          'store_name': config?.businessName ?? 'Beleka POS',
                          'tpin': config?.tpin ?? 'Not Set',
                          'taxes': [],
                        },
                        config,
                      ),
                      loading: () => const _LoadingBody(),
                      error: (e, _) => _buildStatementBody(
                        context,
                        {
                          'business_tax_type': config?.businessTaxType ?? 'VAT_STANDARD',
                          'store_name': config?.businessName ?? 'Beleka POS',
                          'tpin': config?.tpin ?? 'Not Set',
                          'taxes': [],
                        },
                        config,
                      ),
                    ),
                ),
              ),
              _buildActions(context, config, statementAsync.value),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, dynamic config,
      int chargeYear, int chargeMonth) {
    final monthLabel =
        DateFormat('MMMM yyyy').format(DateTime(chargeYear, chargeMonth));
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5C842).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.account_balance_rounded,
                color: Color(0xFFF5C842), size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ZRA Tax Payment Statement',
                  style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'Period: ',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.white38),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (chargeMonth == 1) {
                            _selectedMonth = 12;
                            _selectedYear = chargeYear - 1;
                          } else {
                            _selectedMonth = chargeMonth - 1;
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.chevron_left_rounded,
                            size: 18, color: Color(0xFFF5C842)),
                      ),
                    ),
                    Text(
                      monthLabel,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFF5C842)),
                    ),
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (chargeMonth == 12) {
                            _selectedMonth = 1;
                            _selectedYear = chargeYear + 1;
                          } else {
                            _selectedMonth = chargeMonth + 1;
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 2),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 18, color: Color(0xFFF5C842)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.3)),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ── Statement body (with real figures) ─────────────────────────────────────

  Widget _buildStatementBody(BuildContext context,
      Map<String, dynamic> statement, dynamic config) {
    final svc = ref.read(taxReminderServiceProvider);
    final currency = config?.currencySymbol ?? 'K';
    final taxType = statement['business_tax_type'] as String? ?? '';
    final taxes = (statement['taxes'] as List<dynamic>? ?? []);
    final today = DateTime.now();
    final deadlines = taxes
        .map((e) => ZraTaxDeadline.fromApiEntry(
            Map<String, dynamic>.from(e), today))
        .toList();
    final fmt = NumberFormat('#,##0.00');
    final total =
        (statement['total_auto_computed_payable'] as num?)?.toDouble() ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Business info strip
        _buildBusinessStrip(statement, taxType, currency),
        const SizedBox(height: 20),

        // Tax cards
        ...deadlines.map((d) => _buildTaxCard(d, svc, currency, fmt)),

        const SizedBox(height: 16),
        // Total payable box (auto-computed taxes only)
        if (total > 0) _buildTotalBox(currency, total, fmt),
        const SizedBox(height: 16),
        _buildZraRulesBox(taxType),
      ],
    );
  }

  Widget _buildBusinessStrip(
      Map<String, dynamic> statement, String taxType, String currency) {
    String taxLabel;
    Color taxColor;
    switch (taxType) {
      case 'TURNOVER_TAX':
        taxLabel = 'Turnover Tax (TOT)';
        taxColor = const Color(0xFFF5C842);
      case 'VAT_STANDARD':
        taxLabel = 'VAT — Standard';
        taxColor = const Color(0xFF5DD39E);
      case 'COMPOSITE':
        taxLabel = 'Composite (VAT + TOT)';
        taxColor = const Color(0xFFC6B4FF);
      case 'EXEMPT':
        taxLabel = 'Exempt';
        taxColor = Colors.white38;
      default:
        taxLabel = taxType;
        taxColor = Colors.white54;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (statement['store_name'] as String? ?? '').toUpperCase(),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'TPIN: ${statement['tpin'] ?? 'Not Set'}',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: taxColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: taxColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              taxLabel,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: taxColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxCard(ZraTaxDeadline d, TaxReminderService svc,
      String currency, NumberFormat fmt) {
    final color = svc.urgencyColor(d.urgency);
    final label = svc.urgencyLabel(d);
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: d.needsAction
              ? color.withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.taxName,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                      if (d.description != null) ...[
                        const SizedBox(height: 2),
                        Text(d.description!,
                            style: GoogleFonts.inter(
                                fontSize: 11, color: Colors.white38)),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Figures row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildFiguresRow(d, currency, fmt),
          ),
          // Due date footer
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.event_rounded,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.3)),
                const SizedBox(width: 6),
                Text(
                  'Due: ${dateFmt.format(d.dueDate)}',
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.8)),
                ),
                if (d.isAlreadyFiled == true) ...[
                  const Spacer(),
                  Icon(Icons.check_circle_rounded,
                      size: 13, color: const Color(0xFF5DD39E)),
                  const SizedBox(width: 4),
                  Text(
                    'Filed',
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF5DD39E)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiguresRow(
      ZraTaxDeadline d, String currency, NumberFormat fmt) {
    // VAT card — shows output / input / net
    if (d.taxCode == 'VAT' &&
        d.outputVat != null &&
        d.inputVat != null) {
      return Row(
        children: [
          _figureChip('Output VAT', '$currency ${fmt.format(d.outputVat!)}',
              Colors.white70),
          const SizedBox(width: 8),
          _figureChip('Input VAT', '$currency ${fmt.format(d.inputVat!)}',
              Colors.white38),
          const SizedBox(width: 8),
          _figureChip(
            'NET PAYABLE',
            '$currency ${fmt.format(d.amountPayable ?? 0)}',
            d.amountPayable != null && d.amountPayable! > 0
                ? const Color(0xFFF5C842)
                : const Color(0xFF5DD39E),
            large: true,
          ),
        ],
      );
    }

    // TOT card — shows gross turnover + tax
    if (d.taxCode == 'TOT' && d.taxableBase != null) {
      return Row(
        children: [
          _figureChip(
              'Gross Turnover',
              '$currency ${fmt.format(d.taxableBase!)}',
              Colors.white70),
          const SizedBox(width: 8),
          _figureChip(
              'Rate', '${d.ratePercent?.toStringAsFixed(0) ?? "0"}%',
              Colors.white38),
          const SizedBox(width: 8),
          _figureChip(
            d.nilReturn == true ? 'NIL RETURN' : 'TOT PAYABLE',
            d.nilReturn == true
                ? 'K0.00'
                : '$currency ${fmt.format(d.amountPayable ?? 0)}',
            d.nilReturn == true
                ? const Color(0xFF5DD39E)
                : const Color(0xFFF5C842),
            large: true,
          ),
        ],
      );
    }

    // PAYE / SDL / WHT — from payroll, no auto amount
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 14, color: Colors.white24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Amount sourced from your payroll system — enter manually on ZRA portal.',
              style: GoogleFonts.inter(
                  fontSize: 11, color: Colors.white30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _figureChip(String label, String value, Color valueColor,
      {bool large = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(
          color: valueColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: valueColor.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.4),
                  letterSpacing: 0.3),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: large ? 15 : 13,
                  fontWeight: FontWeight.w900,
                  color: valueColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalBox(String currency, double total, NumberFormat fmt) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF5C842).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: const Color(0xFFF5C842).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_rounded,
              color: const Color(0xFFF5C842).withValues(alpha: 0.7),
              size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Auto-Computed Tax Payable',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.5)),
                ),
                Text(
                  '(VAT + TOT only — PAYE/SDL/WHT require payroll data)',
                  style: GoogleFonts.inter(
                      fontSize: 10, color: Colors.white24),
                ),
              ],
            ),
          ),
          Text(
            '$currency ${fmt.format(total)}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFF5C842),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZraRulesBox([String? taxType]) {
    final t = taxType ?? 'VAT_STANDARD';
    final rules = <(String, String)>[];
    if (t == 'TURNOVER_TAX' || t == 'COMPOSITE') {
      rules.add(('14th', 'Turnover Tax (TOT) — 14th of the month following transaction'));
    }
    if (t == 'VAT_STANDARD' || t == 'COMPOSITE') {
      rules.add(('18th', 'Value Added Tax (VAT Suppliers) — 18th of the month following transaction'));
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5C842).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFFF5C842).withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_rounded,
                  size: 13,
                  color: const Color(0xFFF5C842).withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text(
                'ZRA Filing Deadlines',
                style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFF5C842).withValues(alpha: 0.7)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rules.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(r.$1,
                        style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withValues(alpha: 0.6))),
                  ),
                  const SizedBox(width: 6),
                  Text('→',
                      style: GoogleFonts.inter(
                          fontSize: 10, color: Colors.white24)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(r.$2,
                        style: GoogleFonts.inter(
                            fontSize: 10, color: Colors.white30)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ── Actions ─────────────────────────────────────────────────────────────────

  Widget _buildActions(BuildContext context, dynamic config,
      Map<String, dynamic>? statement) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _exporting
                    ? null
                    : () => _exportPdf(context, config, statement),
                icon: _exporting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.black)),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(
                  _exporting
                      ? 'Generating PDF...'
                      : 'Export ZRA Tax Statement PDF',
                  style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5C842),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side:
                    BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text('Close',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context, dynamic config,
      Map<String, dynamic>? statement) async {
    setState(() => _exporting = true);
    try {
      final exportSvc = ref.read(exportServiceProvider);
      final svc = ref.read(taxReminderServiceProvider);

      // Build deadline list — from API if available, else local
      final List<ZraTaxDeadline> deadlines;
      if (statement != null) {
        deadlines = svc.fromApiResponse(statement, allDeadlines: true);
      } else {
        deadlines = svc.getLocalDeadlines(
            businessTaxType: config?.businessTaxType ?? 'VAT_STANDARD');
      }

      await exportSvc.exportTaxReminderPdf(
        config: config,
        deadlines: deadlines,
        periodLabel: statement?['month_label'] as String?,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('ZRA Tax Statement PDF saved successfully.'),
          backgroundColor: Color(0xFF5DD39E),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }
}

// ── Loading ────────────────────────────────────────────────────────────────────

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Color(0xFFF5C842)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Fetching tax figures from cloud...',
              style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white38,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
