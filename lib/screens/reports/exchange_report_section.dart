import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/services/product_exchange_service.dart';
import 'package:beleka_pos/screens/sales/product_exchange_modal.dart';
import 'package:beleka_pos/utils/formatters.dart';

/// Product Exchange reporting (Section F):
/// totals, most exchanged products, value by branch, additional payments,
/// refunds and outstanding customer credit.
class ExchangeReportSection extends ConsumerWidget {
  final DateTimeRange range;
  final String currency;

  const ExchangeReportSection({
    super.key,
    required this.range,
    required this.currency,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final panelBg = isDark ? const Color(0xFF151F32) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    final reportAsync = ref.watch(exchangeReportProvider(range));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: reportAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Text('Exchange report unavailable: $e'),
        data: (r) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.swap_horiz_rounded,
                      color: Color(0xFF3B82F6),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PRODUCT EXCHANGE REPORT',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => ref.invalidate(exchangeReportProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _statCard(
                  context,
                  'Total Exchanges',
                  r.totalExchanges.toString(),
                  const Color(0xFF3B82F6),
                  borderColor,
                ),
                _statCard(
                  context,
                  'Returned Value',
                  CurrencyFormatter.format(r.totalReturnedValue, currency),
                  const Color(0xFFD97706),
                  borderColor,
                ),
                _statCard(
                  context,
                  'Replacement Value',
                  CurrencyFormatter.format(r.totalReplacementValue, currency),
                  const Color(0xFF059669),
                  borderColor,
                ),
                _statCard(
                  context,
                  'Additional Payments',
                  CurrencyFormatter.format(
                    r.totalAdditionalPaymentsCollected,
                    currency,
                  ),
                  const Color(0xFF2563EB),
                  borderColor,
                ),
                _statCard(
                  context,
                  'Refunds from Exchanges',
                  CurrencyFormatter.format(
                    r.totalRefundsFromExchanges,
                    currency,
                  ),
                  const Color(0xFFDC2626),
                  borderColor,
                ),
                _statCard(
                  context,
                  'Outstanding Customer Credit',
                  CurrencyFormatter.format(
                    r.totalOutstandingCustomerCredit,
                    currency,
                  ),
                  const Color(0xFF7C3AED),
                  borderColor,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionTitle(context, 'MOST FREQUENTLY EXCHANGED PRODUCTS'),
            if (r.mostFrequentlyExchangedProducts.isEmpty)
              _emptyText(context, 'No exchanged products in this period.')
            else
              ...r.mostFrequentlyExchangedProducts.map(
                (p) => _row(
                  context,
                  '${p['product_name']}',
                  'Qty ${(p['total_qty'] as num?)?.toInt() ?? 0} • '
                      '${(p['exchange_count'] as num?)?.toInt() ?? 0} exchange(s) • '
                      '${CurrencyFormatter.format((p['total_value'] as num?)?.toDouble() ?? 0.0, currency)}',
                ),
              ),
            const SizedBox(height: 14),
            _sectionTitle(context, 'EXCHANGE VALUE BY BRANCH'),
            if (r.exchangeValueByBranch.isEmpty)
              _emptyText(context, 'No branch exchange activity.')
            else
              ...r.exchangeValueByBranch.map(
                (b) => _row(
                  context,
                  '${b['branchName']} (${b['branchCode']})',
                  '${b['exchangeCount']} exch • Returned ${CurrencyFormatter.format(b['returnedValue'] as double, currency)} • '
                      'Replaced ${CurrencyFormatter.format(b['replacementValue'] as double, currency)} • '
                      'Collected ${CurrencyFormatter.format(b['additionalCollected'] as double, currency)} • '
                      'Refunded ${CurrencyFormatter.format(b['refundedAmount'] as double, currency)}',
                ),
              ),
            const SizedBox(height: 14),
            _sectionTitle(context, 'OUTSTANDING CUSTOMER CREDIT'),
            if (r.customerCreditBalances.isEmpty)
              _emptyText(context, 'No outstanding exchange credit.')
            else
              ...r.customerCreditBalances.map(
                (c) => _row(
                  context,
                  '${c['customer_name']}'
                  '${(c['customer_phone']?.toString() ?? '').isNotEmpty ? ' • ${c['customer_phone']}' : ''}',
                  '${c['exchange_number'] ?? ''} • Balance ${CurrencyFormatter.format((c['remaining_balance'] as num?)?.toDouble() ?? 0.0, currency)}',
                ),
              ),
            const SizedBox(height: 14),
            _sectionTitle(context, 'RECENT EXCHANGES'),
            if (r.recentExchanges.isEmpty)
              _emptyText(context, 'No exchanges recorded in this period.')
            else
              ...r.recentExchanges.take(25).map(
                (e) => InkWell(
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => ExchangeReceiptDialog(record: e),
                  ),
                  child: _row(
                    context,
                    '${e.exchangeNumber} • ${e.originalInvoiceNo}',
                    '${DateFormat('dd MMM HH:mm').format(e.createdAt)} • ${e.customerName} • '
                        'Diff ${e.differenceAmount >= 0 ? '+' : '-'}${CurrencyFormatter.format(e.differenceAmount.abs(), currency)} • '
                        '${e.paymentMethod} • by ${e.cashierName}',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    Color color,
    Color borderColor,
  ) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _emptyText(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String title, String subtitle) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
