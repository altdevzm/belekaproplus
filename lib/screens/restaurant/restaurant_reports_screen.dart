import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as pnt;
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/restaurant_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/restaurant_service.dart';

class RestaurantReportsScreen extends ConsumerStatefulWidget {
  const RestaurantReportsScreen({super.key});

  @override
  ConsumerState<RestaurantReportsScreen> createState() =>
      _RestaurantReportsScreenState();
}

class _RestaurantReportsScreenState
    extends ConsumerState<RestaurantReportsScreen> {
  String _range = 'TODAY'; // TODAY | WEEK | ALL
  String _viewTab = 'ORDERS'; // ORDERS | PREBILLS | RECEIPTS
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandColor = theme.colorScheme.primary;
    final config = ref.watch(storeConfigProvider).valueOrNull;
    final currency = config?.currencySymbol ?? 'ZK';
    final ordersAsync = ref.watch(allRestaurantOrdersProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: brandColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.analytics_rounded,
                      color: brandColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Restaurant Reports, Receipts & Pre-Bills',
                          style: GoogleFonts.manrope(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Order reports, pre-bill slips, paid receipts with extras & PDF export',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'TODAY', label: Text('Today')),
                      ButtonSegment(value: 'WEEK', label: Text('7 Days')),
                      ButtonSegment(value: 'ALL', label: Text('All Time')),
                    ],
                    selected: {_range},
                    onSelectionChanged: (s) => setState(() => _range = s.first),
                  ),
                  const SizedBox(width: 12),
                  ordersAsync.maybeWhen(
                    data: (allOrders) => ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _isExporting
                          ? null
                          : () => _exportFullReportPdf(
                                _filterOrdersByRange(allOrders),
                                currency,
                                config,
                              ),
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: Text(
                        _isExporting ? 'Generating...' : 'Save Report PDF',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // View Tabs: Order Reports | Pre-Bills | Paid Receipts
            Row(
              children: [
                _tabPill('ORDERS', 'Order Reports', Icons.list_alt_rounded, brandColor),
                const SizedBox(width: 10),
                _tabPill('PREBILLS', 'Pre-Bill Checks', Icons.request_quote_rounded, brandColor),
                const SizedBox(width: 10),
                _tabPill('RECEIPTS', 'Paid Receipts', Icons.receipt_long_rounded, brandColor),
              ],
            ),
            const SizedBox(height: 16),

            Expanded(
              child: ordersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (allOrders) {
                  final filtered = _filterOrdersByRange(allOrders);
                  final paid = filtered
                      .where((o) => o.status == RestaurantOrderStatus.paid)
                      .toList();
                  final preBills = filtered
                      .where(
                        (o) =>
                            o.status != RestaurantOrderStatus.paid &&
                            o.status != RestaurantOrderStatus.cancelled,
                      )
                      .toList();

                  final tableSales = paid
                      .where(
                        (o) => o.serviceType == RestaurantServiceType.table,
                      )
                      .fold<double>(0.0, (s, o) => s + o.totalAmount);
                  final counterSales = paid
                      .where(
                        (o) => o.serviceType == RestaurantServiceType.counter,
                      )
                      .fold<double>(0.0, (s, o) => s + o.totalAmount);
                  final totalServiceCharge = paid.fold<double>(
                    0.0,
                    (s, o) => s + o.serviceChargeAmount,
                  );

                  final displayList = switch (_viewTab) {
                    'PREBILLS' => preBills,
                    'RECEIPTS' => paid,
                    _ => filtered,
                  };

                  return ListView(
                    children: [
                      Wrap(
                        spacing: 14,
                        runSpacing: 14,
                        children: [
                          _statBox(
                            context,
                            'Table Service Sales',
                            '$currency ${tableSales.toStringAsFixed(2)}',
                            const Color(0xFF3B82F6),
                          ),
                          _statBox(
                            context,
                            'Takeaway / Counter Sales',
                            '$currency ${counterSales.toStringAsFixed(2)}',
                            const Color(0xFF10B981),
                          ),
                          _statBox(
                            context,
                            'Service Charge Collected',
                            '$currency ${totalServiceCharge.toStringAsFixed(2)}',
                            const Color(0xFF8B5CF6),
                          ),
                          _statBox(
                            context,
                            'Open Pre-Bills / Paid',
                            '${preBills.length} / ${paid.length}',
                            const Color(0xFFF59E0B),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      if (displayList.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text('No restaurant orders in this view.'),
                          ),
                        )
                      else
                        ...displayList.map(
                          (o) => _OrderReportCard(
                            order: o,
                            currency: currency,
                            config: config,
                            onSaveOrderPdf: () =>
                                _exportSingleOrderPdf(o, currency, config),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<RestaurantOrder> _filterOrdersByRange(List<RestaurantOrder> allOrders) {
    final now = DateTime.now();
    final cutoff = _range == 'TODAY'
        ? DateTime(now.year, now.month, now.day)
        : (_range == 'WEEK'
            ? now.subtract(const Duration(days: 7))
            : DateTime(2000));
    return allOrders.where((o) => !o.createdAt.isBefore(cutoff)).toList();
  }

  Widget _tabPill(String id, String label, IconData icon, Color brandColor) {
    final selected = _viewTab == id;
    return InkWell(
      onTap: () => setState(() => _viewTab = id),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? brandColor.withValues(alpha: 0.18)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? brandColor
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? brandColor
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: selected
                    ? brandColor
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(
    BuildContext context,
    String title,
    String value,
    Color color,
  ) {
    final theme = Theme.of(context);
    return Container(
      width: 245,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.manrope(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportFullReportPdf(
    List<RestaurantOrder> orders,
    String currency,
    StoreConfig? config,
  ) async {
    setState(() => _isExporting = true);
    try {
      final svc = ref.read(restaurantServiceProvider);
      final doc = pw.Document();
      final orderWidgets = <pw.Widget>[];

      final paid = orders
          .where((o) => o.status == RestaurantOrderStatus.paid)
          .toList();
      final totalSales = paid.fold<double>(0.0, (s, o) => s + o.totalAmount);

      for (final o in orders.take(60)) {
        final items = await svc.getOrderItems(o.id);
        orderWidgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: pdf.PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${o.orderNumber} (${o.tableName ?? 'Takeaway'}) - ${o.status.name.toUpperCase()}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                    pw.Text(
                      '$currency ${o.totalAmount.toStringAsFixed(2)}',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  '${DateFormat('dd/MM/yyyy HH:mm').format(o.createdAt)} | Staff: ${o.waiterName ?? 'Staff'}',
                  style: const pw.TextStyle(fontSize: 8.5),
                ),
                pw.SizedBox(height: 4),
                ...items.map((item) {
                  final mods =
                      RestaurantService.decodeModifiers(item.modifiersJson);
                  final extrasText = mods.isEmpty
                      ? ''
                      : ' [Extras: ${mods.map((m) => '${m['name']} (+$currency ${((m['price'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)})').join(', ')}]';
                  return pw.Text(
                    '  • ${item.quantity}x ${item.productName}$extrasText — $currency ${(item.unitPrice * item.quantity).toStringAsFixed(2)}',
                    style: const pw.TextStyle(fontSize: 9),
                  );
                }),
              ],
            ),
          ),
        );
      }

      doc.addPage(
        pw.MultiPage(
          pageFormat: pdf.PdfPageFormat.a4,
          build: (_) => [
            pw.Text(
              '${config?.businessName ?? 'Beleka POS'} — Restaurant Report ($_range)',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Generated: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())} | Paid Total: $currency ${totalSales.toStringAsFixed(2)} (${paid.length} settled orders)',
              style: const pw.TextStyle(fontSize: 10),
            ),
            pw.Divider(),
            ...orderWidgets,
          ],
        ),
      );

      final bytes = await doc.save();
      await _saveOrSharePdf(
        bytes,
        'restaurant_report_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _exportSingleOrderPdf(
    RestaurantOrder order,
    String currency,
    StoreConfig? config,
  ) async {
    final svc = ref.read(restaurantServiceProvider);
    final items = await svc.getOrderItems(order.id);
    final doc = pw.Document();
    final isPaid = order.status == RestaurantOrderStatus.paid;

    doc.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat.roll80,
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(
                config?.businessName ?? 'Beleka POS',
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                isPaid ? 'RESTAURANT ORDER RECEIPT' : 'PRE-BILL / TABLE CHECK',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Divider(),
            pw.Text('Order: ${order.orderNumber}', style: const pw.TextStyle(fontSize: 9)),
            pw.Text(
              order.tableName != null
                  ? 'Table: ${order.tableName}'
                  : 'Service: Takeaway / Counter',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Text('Staff: ${order.waiterName ?? 'Staff'}', style: const pw.TextStyle(fontSize: 9)),
            pw.Text(
              'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(order.createdAt)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.Divider(),
            ...items.expand((item) {
              final mods =
                  RestaurantService.decodeModifiers(item.modifiersJson);
              return [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item.quantity}x ${item.productName}',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Text(
                      '$currency ${(item.unitPrice * item.quantity).toStringAsFixed(2)}',
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ],
                ),
                if (mods.isNotEmpty)
                  pw.Text(
                    '  + ${mods.map((m) {
                      final p = (m['price'] as num?)?.toDouble() ?? 0.0;
                      return p > 0 ? '${m['name']} (+$currency ${p.toStringAsFixed(2)})' : '${m['name']}';
                    }).join(', ')}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                if (item.specialInstructions != null &&
                    item.specialInstructions!.isNotEmpty)
                  pw.Text(
                    '  Note: ${item.specialInstructions}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
              ];
            }),
            pw.Divider(),
            pw.Text(
              'Subtotal: $currency ${order.subtotal.toStringAsFixed(2)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            if (order.serviceChargeAmount > 0)
              pw.Text(
                'Service Charge: $currency ${order.serviceChargeAmount.toStringAsFixed(2)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            pw.Text(
              'VAT (Incl.): $currency ${order.taxAmount.toStringAsFixed(2)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'TOTAL: $currency ${order.totalAmount.toStringAsFixed(2)}',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    final bytes = await doc.save();
    await _saveOrSharePdf(
      bytes,
      '${order.orderNumber.replaceAll('#', 'ORD_')}.pdf',
    );
  }

  Future<void> _saveOrSharePdf(List<int> bytes, String fileName) async {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save PDF Report',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path != null) {
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved PDF to $path')),
          );
        }
        return;
      }
    } catch (_) {
      await pnt.Printing.sharePdf(
        bytes: Uint8List.fromList(bytes),
        filename: fileName,
      );
    }
  }
}

class _OrderReportCard extends ConsumerWidget {
  const _OrderReportCard({
    required this.order,
    required this.currency,
    required this.config,
    required this.onSaveOrderPdf,
  });

  final RestaurantOrder order;
  final String currency;
  final StoreConfig? config;
  final VoidCallback onSaveOrderPdf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final svc = ref.watch(restaurantServiceProvider);
    final isPaid = order.status == RestaurantOrderStatus.paid;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                .withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isPaid ? Icons.receipt_long_rounded : Icons.request_quote_rounded,
            color: isPaid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          ),
        ),
        title: Text(
          '${order.orderNumber}  •  ${order.tableName ?? 'Takeaway / Counter'}',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        subtitle: Text(
          '${DateFormat('dd MMM yyyy, HH:mm').format(order.createdAt)}  •  Staff: ${order.waiterName ?? 'Staff'}  •  ${order.status.name.toUpperCase()}',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Text(
          '$currency ${order.totalAmount.toStringAsFixed(2)}',
          style: GoogleFonts.ibmPlexMono(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            color: theme.colorScheme.primary,
          ),
        ),
        children: [
          FutureBuilder<List<RestaurantOrderItem>>(
            future: svc.getOrderItems(order.id),
            builder: (context, snap) {
              final items = snap.data ?? [];
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    ...items.map((item) {
                      final mods =
                          RestaurantService.decodeModifiers(item.modifiersJson);
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item.quantity}x ${item.productName}',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (mods.isNotEmpty)
                                    Text(
                                      '+ Extras: ${mods.map((m) {
                                        final p = (m['price'] as num?)?.toDouble() ?? 0.0;
                                        return p > 0 ? '${m['name']} (+$currency ${p.toStringAsFixed(2)})' : '${m['name']}';
                                      }).join(', ')}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.amber,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '$currency ${(item.unitPrice * item.quantity).toStringAsFixed(2)}',
                              style: GoogleFonts.ibmPlexMono(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const Divider(),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: onSaveOrderPdf,
                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 17),
                          label: const Text('Save PDF'),
                        ),
                        OutlinedButton.icon(
                          onPressed: items.isEmpty
                              ? null
                              : () => PrinterService().printPreBill(
                                    order: order,
                                    items: items,
                                    config: config,
                                  ),
                          icon: const Icon(Icons.print_rounded, size: 17),
                          label: const Text('Print Pre-Bill'),
                        ),
                        if (isPaid && order.saleTransactionId != null)
                          OutlinedButton.icon(
                            onPressed: () async {
                              final db = ref.read(databaseServiceProvider);
                              final tx = await db.isar.saleTransactions
                                  .get(order.saleTransactionId!);
                              if (tx != null) {
                                await tx.items.load();
                                await PrinterService().printReceipt(
                                  tx,
                                  tx.items.toList(),
                                  config: config,
                                );
                              }
                            },
                            icon: const Icon(Icons.qr_code_2_rounded, size: 17),
                            label: const Text('Reprint ZRA Receipt'),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
