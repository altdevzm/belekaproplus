import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show debugPrint, DateTimeRange;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:beleka_pos/utils/formatters.dart';

final exportServiceProvider = Provider((ref) => ExportService());

class ExportService {
  // --- Brand & Style Helpers ---

  PdfColor _getBrandColor(StoreConfig? config) {
    if (config?.brandColorHex != null && config!.brandColorHex!.isNotEmpty) {
      try {
        String hex = config.brandColorHex!.replaceAll('#', '').trim();
        if (hex.length == 6) hex = 'FF$hex';
        final intVal = int.parse(hex, radix: 16);
        return PdfColor.fromInt(intVal);
      } catch (e) {
        debugPrint('Error parsing brandColorHex: $e');
      }
    }
    return _getSectorColor(config?.primarySector ?? CategorySector.other);
  }

  bool _isColorLight(PdfColor color) {
    final luminance = (0.299 * color.red + 0.587 * color.green + 0.114 * color.blue);
    return luminance > 0.65;
  }

  Future<pw.MemoryImage?> _loadLogoImage(StoreConfig? config) async {
    final logoPath = config?.logoPath;
    if (logoPath != null && File(logoPath).existsSync()) {
      try {
        return pw.MemoryImage(File(logoPath).readAsBytesSync());
      } catch (e) {
        debugPrint('Error loading custom logo from path: $e');
      }
    }
    // Fallback to asset logo
    try {
      final byteData = await rootBundle.load('assets/images/logo.png');
      return pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (e) {
      debugPrint('PDF Logo fallback error: $e');
      return null;
    }
  }

  pw.Widget _buildDocumentHeader(
    StoreConfig? config, {
    required String title,
    required PdfColor brandColor,
    pw.MemoryImage? logoImage,
  }) {
    final companyName = (config != null && config.businessName.isNotEmpty)
        ? config.businessName.toUpperCase()
        : 'BELEKA PRO POS';
    final branch = config?.branchName ?? config?.terminalName;
    final address = config?.address;
    final phone = config?.contactNumber;
    final email = config?.email;
    final website = config?.website;
    final tpin = (config?.tpin != null && config!.tpin!.isNotEmpty)
        ? config.tpin!
        : (config?.taxId != null && config!.taxId!.isNotEmpty ? config.taxId! : null);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null)
                    pw.Container(
                      width: 58,
                      height: 58,
                      margin: const pw.EdgeInsets.only(right: 14),
                      decoration: pw.BoxDecoration(
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                        border: pw.Border.all(color: brandColor, width: 1.5),
                      ),
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.ClipRRect(
                        horizontalRadius: 6,
                        verticalRadius: 6,
                        child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                            color: brandColor,
                          ),
                        ),
                        if (branch != null && branch.isNotEmpty)
                          pw.Text(
                            'Branch / Outlet: $branch',
                            style: pw.TextStyle(
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.grey800,
                            ),
                          ),
                        if (address != null && address.isNotEmpty)
                          pw.Text(
                            address,
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                          ),
                        if ((phone != null && phone.isNotEmpty) || (email != null && email.isNotEmpty))
                          pw.Text(
                            [
                              if (phone != null && phone.isNotEmpty) 'Tel: $phone',
                              if (email != null && email.isNotEmpty) 'Email: $email',
                            ].join('   |   '),
                            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
                          ),
                        if (website != null && website.isNotEmpty)
                          pw.Text(
                            website,
                            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.blue800),
                          ),
                        if (tpin != null && tpin.isNotEmpty)
                          pw.Container(
                            margin: const pw.EdgeInsets.only(top: 4),
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: const pw.BoxDecoration(
                              color: PdfColors.grey200,
                              borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                            ),
                            child: pw.Text(
                              'TPIN / TAX PIN: $tpin',
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: pw.FontWeight.bold,
                                color: PdfColors.black,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: pw.BoxDecoration(
                    color: brandColor,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    title.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey600),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          height: 2.5,
          decoration: pw.BoxDecoration(
            color: brandColor,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          ),
        ),
        pw.SizedBox(height: 12),
      ],
    );
  }

  // --- CSV Exports ---

  Future<void> exportTransactionsToCsv(List<SaleTransaction> transactions, {StoreConfig? config}) async {
    List<List<dynamic>> rows = [];
    final currency = config?.currencySymbol ?? 'ZK';
    
    // Header with Company Branding & Contacts
    if (config != null) {
      rows.add(['COMPANY', config.businessName.toUpperCase()]);
      if (config.branchName != null && config.branchName!.isNotEmpty) {
        rows.add(['BRANCH', config.branchName!]);
      }
      if (config.address != null && config.address!.isNotEmpty) {
        rows.add(['ADDRESS', config.address!]);
      }
      if (config.contactNumber != null && config.contactNumber!.isNotEmpty) {
        rows.add(['CONTACT', config.contactNumber!]);
      }
      if (config.email != null && config.email!.isNotEmpty) {
        rows.add(['EMAIL', config.email!]);
      }
      if (config.tpin != null && config.tpin!.isNotEmpty) {
        rows.add(['TPIN', config.tpin!]);
      }
      rows.add(['REPORT', 'Transaction Sales Ledger']);
      rows.add(['GENERATED', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())]);
      rows.add([]); // Spacing
    }

    rows.add([
      'Date & Time',
      'Transaction ID',
      'Cashier',
      'Subtotal ($currency)',
      'Tax ($currency)',
      'Discount ($currency)',
      'Total ($currency)',
      'Payment Method',
      'Status'
    ]);

    double totalCash = 0;
    double totalCard = 0;
    double totalMomo = 0;
    double grandTotal = 0;

    for (var tx in transactions) {
      final total = tx.totalAmount.isNaN ? 0.0 : tx.totalAmount;
      final subtotal = tx.subtotal.isNaN ? 0.0 : tx.subtotal;
      final tax = tx.taxAmount.isNaN ? 0.0 : tx.taxAmount;
      final discount = tx.discountAmount.isNaN ? 0.0 : tx.discountAmount;

      rows.add([
        DateFormat('yyyy-MM-dd HH:mm').format(tx.timestamp),
        tx.id.toString(),
        tx.cashierName,
        subtotal.isNaN ? '0.00' : subtotal.toStringAsFixed(2),
        tax.isNaN ? '0.00' : tax.toStringAsFixed(2),
        discount.isNaN ? '0.00' : discount.abs().toStringAsFixed(2),
        total.isNaN ? '0.00' : total.toStringAsFixed(2),
        tx.paymentMethod.toUpperCase(),
        tx.status
      ]);

      grandTotal += total;
      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash')) {
        totalCash += total;
      } else if (method.contains('card')) {
        totalCard += total;
      } else if (method.contains('mobile') || method.contains('momo')) {
        totalMomo += total;
      }
    }

    // Summary
    rows.add([]);
    rows.add(['FINANCIAL SUMMARY']);
    rows.add(['Total Cash Collected', '', '', '', '', '', CurrencyFormatter.format(totalCash, currency)]);
    rows.add(['Total Card Collected', '', '', '', '', '', CurrencyFormatter.format(totalCard, currency)]);
    rows.add(['Total Mobile Money', '', '', '', '', '', CurrencyFormatter.format(totalMomo, currency)]);
    rows.add(['GRAND REVENUE TOTAL', '', '', '', '', '', CurrencyFormatter.format(grandTotal, currency)]);

    String csvData = const ListToCsvConverter().convert(rows);
    await _saveFile(Uint8List.fromList(csvData.codeUnits), 'transactions_${DateTime.now().millisecondsSinceEpoch}.csv', extensions: ['csv']);
  }

  // --- PDF Transaction Report ---

  Future<void> exportTransactionsToPdf(List<SaleTransaction> transactions, {StoreConfig? config}) async {
    final pdf = pw.Document();
    final currency = config?.currencySymbol ?? 'ZK';
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);

    // Calculate Summary Data
    double totalCash = 0;
    double totalCard = 0;
    double totalMomo = 0;
    double totalTax = 0;
    double grandTotal = 0;

    for (var tx in transactions) {
      final total = tx.totalAmount.isNaN ? 0.0 : tx.totalAmount;
      final tax = tx.taxAmount.isNaN ? 0.0 : tx.taxAmount;
      grandTotal += total;
      totalTax += tax;
      
      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash')) {
        totalCash += total;
      } else if (method.contains('card')) {
        totalCard += total;
      } else if (method.contains('mobile') || method.contains('momo')) {
        totalMomo += total;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildDocumentHeader(
          config,
          title: 'Transaction Report',
          brandColor: brandColor,
          logoImage: logoImage,
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['Time', 'Tx ID', 'Cashier', 'Method', 'Tax ($currency)', 'Total ($currency)'],
            data: transactions.map((tx) {
              final total = tx.totalAmount.isNaN ? 0.0 : tx.totalAmount;
              final tax = tx.taxAmount.isNaN ? 0.0 : tx.taxAmount;
              return [
                DateFormat('yyyy-MM-dd HH:mm').format(tx.timestamp),
                tx.id.toString(),
                tx.cashierName,
                tx.paymentMethod.toUpperCase(),
                tax.toStringAsFixed(2),
                total.toStringAsFixed(2),
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
              fontSize: 9.5,
            ),
            headerDecoration: pw.BoxDecoration(
              color: brandColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            cellHeight: 24,
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.center,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 250,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: brandColor, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'PAYMENT SUMMARY',
                    style: pw.TextStyle(
                      fontSize: 11,
                      fontWeight: pw.FontWeight.bold,
                      color: brandColor,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(thickness: 1, color: brandColor),
                  _buildSummaryRow('Total Cash:', CurrencyFormatter.format(totalCash, currency)),
                  _buildSummaryRow('Total Card:', CurrencyFormatter.format(totalCard, currency)),
                  _buildSummaryRow('Total Mobile Money:', CurrencyFormatter.format(totalMomo, currency)),
                  _buildSummaryRow('Total Tax (VAT):', CurrencyFormatter.format(totalTax, currency)),
                  pw.Divider(thickness: 1),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('GRAND TOTAL:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        CurrencyFormatter.format(grandTotal, currency),
                        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: brandColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 16),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}   •   Beleka Pro POS Document Export',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey),
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    await _saveFile(bytes, 'transactions_${DateTime.now().millisecondsSinceEpoch}.pdf', extensions: ['pdf']);
  }

  /// Export or Print Individual Sale Receipt (PDF)
  Future<void> exportReceiptToPdf(
    SaleTransaction transaction,
    List<SaleItem> items, {
    StoreConfig? config,
    bool printDirectly = false,
  }) async {
    final pdf = pw.Document();
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateOnlyStr = DateFormat('dd/MM/yyyy').format(transaction.timestamp);
    final timeOnlyStr = DateFormat('HH:mm:ss').format(transaction.timestamp);

    String formatZraInvoiceNo(String? raw) {
      if (raw == null || raw.trim().isEmpty || raw.trim() == 'PENDING' || raw.trim() == 'null') return 'PENDING';
      final trimmed = raw.trim();
      if (trimmed.toUpperCase().startsWith('INV1/') || trimmed.toUpperCase().startsWith('INV/') || trimmed.toUpperCase().startsWith('CN')) return trimmed;
      final clean = trimmed.replaceFirst(RegExp(r'^(INV|CN)-0*'), '').replaceFirst(RegExp(r'^(INV|CN)-'), '');
      return 'INV1/$clean';
    }

    final sdcIdStr = (transaction.zraSdcId != null && transaction.zraSdcId!.isNotEmpty)
        ? transaction.zraSdcId!
        : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : 'PENDING');
    final sdcInvNoStr = formatZraInvoiceNo(transaction.zraReceiptNumber);
    final signatureStr = (transaction.zraMarkId != null && transaction.zraMarkId!.isNotEmpty)
        ? transaction.zraMarkId!
        : 'PENDING';
    final internalDataStr = (transaction.zraInternalData != null && transaction.zraInternalData!.isNotEmpty)
        ? transaction.zraInternalData!
        : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');
    final zraQrData = (transaction.zraQrCode != null && transaction.zraQrCode!.isNotEmpty)
        ? transaction.zraQrCode!
        : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcIdStr&rcpt=$sdcInvNoStr';

    final isFiscalApproved = transaction.zraStatus == 'APPROVED' &&
                             transaction.zraMarkId != null &&
                             transaction.zraMarkId!.isNotEmpty &&
                             transaction.zraMarkId != 'PENDING';
    final receiptTitle = transaction.isCreditNote
        ? 'ZRA FISCAL CREDIT NOTE'
        : (isFiscalApproved ? 'TAX INVOICE / OFFICIAL RECEIPT' : 'CUSTOMER SALES SLIP');

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 4 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              if (logoImage != null)
                pw.Container(
                  height: 35,
                  child: pw.Image(logoImage),
                ),
              pw.SizedBox(height: 3),
              pw.Text(
                (config != null && config.businessName.isNotEmpty) ? config.businessName.toUpperCase() : 'BELEKA POS',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                textAlign: pw.TextAlign.center,
              ),
              if (config?.branchName != null && config!.branchName!.isNotEmpty)
                pw.Text('Branch: ${config.branchName}', style: const pw.TextStyle(fontSize: 8)),
              if (config?.address != null && config!.address!.isNotEmpty)
                pw.Text(config.address!, style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.center),
              if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty)
                pw.Text('Tel: ${config.contactNumber}', style: const pw.TextStyle(fontSize: 7.5)),
              if (config?.tpin != null && config!.tpin!.isNotEmpty)
                pw.Text('TPIN: ${config.tpin}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),

              pw.SizedBox(height: 4),
              pw.Text('================================'),
              pw.Text(receiptTitle, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text('================================'),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('RECEIPT: #${transaction.id.toString().padLeft(8, '0')}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text('$dateOnlyStr $timeOnlyStr', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Cashier: ${transaction.cashierName}', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('Terminal: ${transaction.terminalName ?? config?.terminalName ?? "POS-01"}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              pw.Divider(thickness: 0.5),

              // Line Items
              ...items.map((i) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1),
                  child: pw.Row(
                    children: [
                      pw.Expanded(flex: 5, child: pw.Text(i.productName.toUpperCase(), style: const pw.TextStyle(fontSize: 7.5))),
                      pw.Expanded(flex: 2, child: pw.Text('${i.quantity}x', style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.center)),
                      pw.Expanded(flex: 4, child: pw.Text('$currency${(i.priceAtSale * i.quantity).toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 7.5), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                );
              }),
              pw.Divider(thickness: 0.5),

              // Totals Breakdown
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('SUBTOTAL (NET):', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text('$currency${transaction.subtotal.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                ],
              ),
              if (transaction.discountAmount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('DISCOUNT:', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('-$currency${transaction.discountAmount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              if (transaction.taxAmount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text((config?.businessTaxType == 'TURNOVER_TAX') ? 'TURNOVER TAX:' : 'TOTAL VAT (INCL):', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('$currency${transaction.taxAmount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              if (transaction.serviceChargeAmount > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SERVICE CHARGE (${transaction.serviceChargeRate.toStringAsFixed(0)}% UNTAXED):', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('$currency${transaction.serviceChargeAmount.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL DUE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                  pw.Text('$currency${transaction.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                ],
              ),
              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Payment Method:', style: const pw.TextStyle(fontSize: 7.5)),
                  pw.Text(transaction.paymentMethod.toUpperCase(), style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              if (transaction.paymentMethod.toUpperCase() == 'CASH') ...[
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Cash Tendered:', style: const pw.TextStyle(fontSize: 7.5)),
                    pw.Text('$currency${(transaction.tenderedAmount > 0 ? transaction.tenderedAmount : transaction.totalAmount).toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 7.5)),
                  ],
                ),
                if (transaction.changeAmount > 0)
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Change:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
                      pw.Text('$currency${transaction.changeAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
                    ],
                  ),
              ],

              pw.SizedBox(height: 3),
              pw.Text('TAX SUMMARY BREAKDOWN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('CODE / RATE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  pw.Text('TAX AMT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  pw.Text('TOTAL', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                ],
              ),
              ...(() {
                final Map<double, Map<String, double>> exportBreakdown = {};
                for (var item in items) {
                  final rate = item.taxRateAtSale;
                  final total = double.parse((item.priceAtSale * item.quantity).toStringAsFixed(2));
                  double vat = 0;
                  if (item.isTaxInclusiveAtSale) {
                    if (rate > 0) {
                      final taxable = double.parse((total / (1 + (rate / 100))).toStringAsFixed(2));
                      vat = double.parse((total - taxable).toStringAsFixed(2));
                    } else {
                      vat = 0.0;
                    }
                  } else {
                    vat = double.parse((total * (rate / 100)).toStringAsFixed(2));
                  }
                  if (!exportBreakdown.containsKey(rate)) {
                    exportBreakdown[rate] = {'vat': 0.0, 'total': 0.0};
                  }
                  exportBreakdown[rate]!['vat'] = double.parse((exportBreakdown[rate]!['vat']! + vat).toStringAsFixed(2));
                  exportBreakdown[rate]!['total'] = double.parse((exportBreakdown[rate]!['total']! + total).toStringAsFixed(2));
                }
                return exportBreakdown.entries.map((entry) {
                  final letter = entry.key >= 16.0 ? 'A' : (entry.key > 0 ? 'B' : 'C');
                  final vatFormatted = '$currency${entry.value['vat']!.toStringAsFixed(2)}';
                  final totFormatted = '$currency${entry.value['total']!.toStringAsFixed(2)}';
                  return pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('$letter (${entry.key.toStringAsFixed(0)}%)', style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(vatFormatted, style: const pw.TextStyle(fontSize: 7)),
                      pw.Text(totFormatted, style: const pw.TextStyle(fontSize: 7)),
                    ],
                  );
                }).toList();
              })(),

              pw.SizedBox(height: 3),
              pw.Text('--------------------------------'),
              if (isFiscalApproved) ...[
                pw.Text('*** ZRA FISCAL CONTROL DATA ***', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                pw.Text('--------------------------------'),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Date:', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(dateOnlyStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Time:', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(timeOnlyStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SDC Id:', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(sdcIdStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('SDC Invoice No:', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(sdcInvNoStr, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Signature:', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(signatureStr, style: const pw.TextStyle(fontSize: 6.5)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Internal Data:', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(internalDataStr, style: const pw.TextStyle(fontSize: 6.5)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Invoice Type:', style: const pw.TextStyle(fontSize: 7)),
                    pw.Text(transaction.zraInvoiceType ?? 'Normal Sale', style: const pw.TextStyle(fontSize: 6.5)),
                  ],
                ),
                
                pw.SizedBox(height: 2),
                pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: zraQrData,
                  width: 55,
                  height: 55,
                ),
                pw.SizedBox(height: 1),
                pw.Text('Scan QR Code to Verify on ZRA Portal', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 6.5)),
              ] else ...[
                pw.Text('*** OFFLINE TRANSACTION - FISCAL PENDING ***', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)),
                pw.Text('Official ZRA Smart Invoice will sync automatically', style: const pw.TextStyle(fontSize: 6.5)),
                pw.Text('--------------------------------'),
              ],

              pw.SizedBox(height: 3),
              pw.Text('================================'),
              pw.Text('THANK YOU FOR SHOPPING WITH US!', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
              pw.Text('PLEASE VISIT US AGAIN', style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
              if (config?.contactNumber != null && config!.contactNumber!.isNotEmpty) 
                pw.Text('Helpline: ${config.contactNumber!}', style: const pw.TextStyle(fontSize: 6)),
              pw.Text('*** BELEKA POS RETAIL OS ***', style: const pw.TextStyle(fontSize: 6)),
              pw.Text('================================'),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Receipt #${transaction.id}', 'receipt_${transaction.id}.pdf', printDirectly: printDirectly);
  }

  pw.Widget _buildSummaryRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9.5)),
          pw.Text(value, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  // --- Excel Transaction Export ---

  Future<void> exportTransactionsToExcel(List<SaleTransaction> transactions, {StoreConfig? config}) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Transactions'];
    final currency = config?.currencySymbol ?? 'ZK';
    
    // Summary data
    double totalCash = 0;
    double totalCard = 0;
    double totalMomo = 0;
    double grandTotal = 0;

    sheet.appendRow([TextCellValue(config?.businessName.toUpperCase() ?? 'BELEKA PRO POS')]);
    if (config?.branchName != null) {
      sheet.appendRow([TextCellValue('Branch: ${config!.branchName!}')]);
    }
    if (config?.address != null) {
      sheet.appendRow([TextCellValue('Address: ${config!.address!}')]);
    }
    if (config?.tpin != null) {
      sheet.appendRow([TextCellValue('TPIN: ${config!.tpin!}')]);
    }
    sheet.appendRow([TextCellValue('Transaction Report - ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue('Date & Time'),
      TextCellValue('Transaction ID'),
      TextCellValue('Cashier'),
      TextCellValue('Payment Method'),
      TextCellValue('Subtotal ($currency)'),
      TextCellValue('Tax ($currency)'),
      TextCellValue('Total ($currency)'),
    ]);

    for (var tx in transactions) {
      final total = tx.totalAmount.isNaN ? 0.0 : tx.totalAmount;
      final subtotal = tx.subtotal.isNaN ? 0.0 : tx.subtotal;
      final tax = tx.taxAmount.isNaN ? 0.0 : tx.taxAmount;

      sheet.appendRow([
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(tx.timestamp)),
        TextCellValue(tx.id.toString()),
        TextCellValue(tx.cashierName),
        TextCellValue(tx.paymentMethod.toUpperCase()),
        DoubleCellValue(subtotal),
        DoubleCellValue(tax),
        DoubleCellValue(total),
      ]);

      grandTotal += total;
      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash')) {
        totalCash += total;
      } else if (method.contains('card')) {
        totalCard += total;
      } else if (method.contains('mobile') || method.contains('momo')) {
        totalMomo += total;
      }
    }

    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('FINANCIAL SUMMARY')]);
    sheet.appendRow([TextCellValue('Total Cash'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), DoubleCellValue(totalCash)]);
    sheet.appendRow([TextCellValue('Total Card'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), DoubleCellValue(totalCard)]);
    sheet.appendRow([TextCellValue('Total Mobile Money'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), DoubleCellValue(totalMomo)]);
    sheet.appendRow([TextCellValue('GRAND TOTAL'), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), DoubleCellValue(grandTotal)]);

    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile(bytes, 'transactions_${DateTime.now().millisecondsSinceEpoch}.xlsx', extensions: ['xlsx']);
  }

  // --- Inventory CSV Export ---

  Future<void> exportInventoryToCsv(List<Product> products, {StoreConfig? config}) async {
    List<List<dynamic>> rows = [];
    final currency = config?.currencySymbol ?? 'ZK';

    if (config != null) {
      rows.add(['COMPANY', config.businessName.toUpperCase()]);
      if (config.branchName != null && config.branchName!.isNotEmpty) {
        rows.add(['BRANCH', config.branchName!]);
      }
      if (config.address != null && config.address!.isNotEmpty) {
        rows.add(['ADDRESS', config.address!]);
      }
      if (config.tpin != null && config.tpin!.isNotEmpty) {
        rows.add(['TPIN', config.tpin!]);
      }
      rows.add(['REPORT', 'Inventory Stock Master Report']);
      rows.add(['GENERATED', DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())]);
      rows.add([]);
    }

    rows.add([
      'SKU',
      'Product Name',
      'Category ID',
      'Selling Price ($currency)',
      'Cost Price ($currency)',
      'Stock Level',
      'Stock Valuation ($currency)',
      'Status'
    ]);

    for (var p in products) {
      final valuation = p.unitCost * p.stockLevel;
      rows.add([
        p.sku,
        p.name,
        p.categoryId.toString(),
        p.price.toStringAsFixed(2),
        p.unitCost.toStringAsFixed(2),
        p.stockLevel.toString(),
        valuation.toStringAsFixed(2),
        p.isArchived ? 'Archived' : 'Active'
      ]);
    }

    String csvData = const ListToCsvConverter().convert(rows);
    await _saveFile(Uint8List.fromList(csvData.codeUnits), 'inventory_${DateTime.now().millisecondsSinceEpoch}.csv', extensions: ['csv']);
  }

  // --- Inventory PDF Export ---

  Future<void> exportInventoryToPdf(List<Product> products, {StoreConfig? config}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'ZK';

    double totalValuation = 0.0;
    int totalItemsInStock = 0;
    for (var p in products) {
      if (!p.isArchived) {
        totalItemsInStock += p.stockLevel;
        totalValuation += (p.unitCost * p.stockLevel);
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (context) => _buildDocumentHeader(
          config,
          title: 'Inventory Stock Report',
          brandColor: brandColor,
          logoImage: logoImage,
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['SKU', 'Product Name', 'Price ($currency)', 'Cost ($currency)', 'Stock', 'Status'],
            data: products.map((p) => [
              p.sku,
              p.name,
              p.price.toStringAsFixed(2),
              p.unitCost.toStringAsFixed(2),
              p.stockLevel.toString(),
              p.isArchived ? 'Archived' : 'Active'
            ]).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
              fontSize: 9.5,
            ),
            headerDecoration: pw.BoxDecoration(
              color: brandColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            cellHeight: 24,
            cellStyle: const pw.TextStyle(fontSize: 8.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.center,
            },
          ),
          pw.SizedBox(height: 24),
          pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              width: 250,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: brandColor, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    'STOCK VALUATION SUMMARY',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: brandColor),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(thickness: 1, color: brandColor),
                  _buildSummaryRow('Total Product SKUs:', '${products.length}'),
                  _buildSummaryRow('Total Units In Stock:', '$totalItemsInStock'),
                  pw.Divider(thickness: 1),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL VALUATION:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text(
                        CurrencyFormatter.format(totalValuation, currency),
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: brandColor),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 16),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}   •   Beleka Pro POS Document Export',
            style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey),
          ),
        ),
      ),
    );

    final bytes = await pdf.save();
    await _saveFile(bytes, 'inventory_${DateTime.now().millisecondsSinceEpoch}.pdf', extensions: ['pdf']);
  }

  // --- Daily Summary PDF Export ---

  Future<void> exportDailySummaryToPdf({
    required Map<String, double> stats,
    required List<Map<String, dynamic>> topProducts,
    required Map<String, double> paymentDist,
    StoreConfig? config,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'ZK';

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildDocumentHeader(
              config,
              title: 'Daily Sales Summary',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.Text(
              'FINANCIAL OVERVIEW',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                children: [
                  _buildSummaryRow('Total Revenue:', CurrencyFormatter.format(stats['todayRevenue'] ?? 0.0, currency)),
                  _buildSummaryRow('Gross Profit:', CurrencyFormatter.format(stats['todayProfit'] ?? 0.0, currency)),
                  _buildSummaryRow('Transactions Count:', '${(stats['todayCount'] ?? 0).toInt()} sales'),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'TOP SELLING PRODUCTS',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: ['Product Name', 'Quantity Sold'],
              data: topProducts.map((p) => [p['name'], p['quantity'].toString()]).toList(),
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                fontSize: 9.5,
              ),
              headerDecoration: pw.BoxDecoration(
                color: brandColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              cellHeight: 24,
              cellStyle: const pw.TextStyle(fontSize: 8.5),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'PAYMENT DISTRIBUTION',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                children: paymentDist.entries.map((e) {
                  final val = e.value.isNaN ? 0.0 : e.value;
                  return _buildSummaryRow(e.key.toUpperCase(), CurrencyFormatter.format(val, currency));
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );

    final bytes = await pdf.save();
    await _saveFile(bytes, 'daily_summary_${DateTime.now().millisecondsSinceEpoch}.pdf', extensions: ['pdf']);
  }

  // --- Financial Summary PDF Export (Full A4 Executive Document) ---
  Future<void> exportFinancialSummaryToPdf({
    required String periodTitle,
    required String dateRangeLabel,
    required Map<String, double> stats,
    List<Map<String, dynamic>>? topProducts,
    StoreConfig? config,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'ZK';

    final revenue = stats['revenue'] ?? 0.0;
    final profit = stats['profit'] ?? 0.0;
    final tax = stats['tax'] ?? 0.0;
    final count = (stats['count'] ?? 0.0).toInt();
    final cash = stats['cash'] ?? 0.0;
    final card = stats['card'] ?? 0.0;
    final mobileMoney = stats['mobile_money'] ?? 0.0;
    final profitMargin = revenue > 0 ? ((profit / revenue) * 100).toStringAsFixed(1) : '0.0';
    final avgSale = count > 0 ? (revenue / count) : 0.0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildDocumentHeader(
              config,
              title: periodTitle,
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 8),

            // Period Subtitle Bar
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('REPORTING PERIOD: $dateRangeLabel', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                  pw.Text('GENERATED: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Financial KPI Overview Banner
            pw.Text(
              'EXECUTIVE FINANCIAL OVERVIEW',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                children: [
                  _buildSummaryRow('Total Revenue (Gross Sales):', CurrencyFormatter.format(revenue, currency)),
                  _buildSummaryRow('Cost of Goods Sold (COGS):', CurrencyFormatter.format(revenue - profit, currency)),
                  _buildSummaryRow('Gross Profit:', CurrencyFormatter.format(profit, currency)),
                  _buildSummaryRow('Profit Margin (%):', '$profitMargin%'),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                  _buildSummaryRow('Total Tax / VAT Collected:', CurrencyFormatter.formatTaxPrecision(tax, currency)),
                  _buildSummaryRow('Total Completed Transactions:', '$count sales'),
                  _buildSummaryRow('Average Transaction Value:', CurrencyFormatter.format(avgSale, currency)),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Payment Methods Breakdown Table
            pw.Text(
              'PAYMENT METHODS BREAKDOWN',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Payment Method', 'Amount ($currency)', '% of Total'],
              data: [
                ['Cash Payments', CurrencyFormatter.format(cash, currency), revenue > 0 ? '${((cash / revenue) * 100).toStringAsFixed(1)}%' : '0%'],
                ['Card / POS Payments', CurrencyFormatter.format(card, currency), revenue > 0 ? '${((card / revenue) * 100).toStringAsFixed(1)}%' : '0%'],
                ['Mobile Money (Airtel / MTN / Zamtel)', CurrencyFormatter.format(mobileMoney, currency), revenue > 0 ? '${((mobileMoney / revenue) * 100).toStringAsFixed(1)}%' : '0%'],
                ['TOTAL COLLECTED', CurrencyFormatter.format(revenue, currency), '100.0%'],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                fontSize: 8.5,
              ),
              headerDecoration: pw.BoxDecoration(
                color: brandColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              cellHeight: 22,
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 14),

            // Top Products Table (if present)
            if (topProducts != null && topProducts.isNotEmpty) ...[
              pw.Text(
                'TOP PERFORMING PRODUCTS',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: brandColor),
              ),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: ['Rank', 'Product Name', 'Quantity Sold'],
                data: topProducts.take(8).toList().asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final p = entry.value;
                  return [
                    '#$idx',
                    p['name']?.toString() ?? 'Product',
                    p['quantity']?.toString() ?? '0',
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                  fontSize: 8.5,
                ),
                headerDecoration: pw.BoxDecoration(
                  color: brandColor,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                cellHeight: 20,
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignments: {
                  0: pw.Alignment.center,
                  1: pw.Alignment.centerLeft,
                  2: pw.Alignment.centerRight,
                },
              ),
            ],

            pw.Spacer(),
            _buildDocumentFooter(config),
          ],
        ),
      ),
    );

    final cleanFileName = '${periodTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    final bytes = await pdf.save();
    await _saveFile(bytes, cleanFileName, extensions: ['pdf']);
  }

  // --- Financial Summary 80mm Slip PDF ---
  Future<void> exportFinancialSummarySlipToPdf({
    required String periodTitle,
    required String dateRangeLabel,
    required Map<String, double> stats,
    StoreConfig? config,
  }) async {
    final doc = pw.Document();
    final currency = config?.currencySymbol ?? 'ZK';

    final revenue = stats['revenue'] ?? 0.0;
    final profit = stats['profit'] ?? 0.0;
    final tax = stats['tax'] ?? 0.0;
    final count = (stats['count'] ?? 0.0).toInt();
    final cash = stats['cash'] ?? 0.0;
    final card = stats['card'] ?? 0.0;
    final mobileMoney = stats['mobile_money'] ?? 0.0;
    final profitMargin = revenue > 0 ? ((profit / revenue) * 100).toStringAsFixed(1) : '0.0';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(5 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(periodTitle.toUpperCase(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text(config?.businessName ?? 'BELEKA POS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              if (config?.address != null && config!.address!.isNotEmpty)
                pw.Text(config.address!, style: const pw.TextStyle(fontSize: 7.5)),
              if (config?.tpin != null && config!.tpin!.isNotEmpty)
                pw.Text('TPIN: ${config.tpin}', style: const pw.TextStyle(fontSize: 7.5)),
              pw.Text('Period: $dateRangeLabel', style: const pw.TextStyle(fontSize: 7.5)),
              pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 7)),
              pw.SizedBox(height: 2 * PdfPageFormat.mm),
              pw.Divider(thickness: 1),

              pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('FINANCIAL TOTALS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
              pw.SizedBox(height: 1 * PdfPageFormat.mm),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('Transactions', style: const pw.TextStyle(fontSize: 7.5)), pw.Text('$count sales', style: const pw.TextStyle(fontSize: 7.5))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Total Revenue', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text(CurrencyFormatter.format(revenue, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Gross Profit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text(CurrencyFormatter.format(profit, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                ],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('Profit Margin', style: const pw.TextStyle(fontSize: 7.5)), pw.Text('$profitMargin%', style: const pw.TextStyle(fontSize: 7.5))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('Total Tax / VAT', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.formatTaxPrecision(tax, currency), style: const pw.TextStyle(fontSize: 7.5))],
              ),

              pw.SizedBox(height: 2 * PdfPageFormat.mm),
              pw.Divider(thickness: 0.5),
              pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('PAYMENT BREAKDOWN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
              pw.SizedBox(height: 1 * PdfPageFormat.mm),
              if (cash > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Cash', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(cash, currency), style: const pw.TextStyle(fontSize: 7.5))],
                ),
              if (card > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Card', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(card, currency), style: const pw.TextStyle(fontSize: 7.5))],
                ),
              if (mobileMoney > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('Mobile Money', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(mobileMoney, currency), style: const pw.TextStyle(fontSize: 7.5))],
                ),
              pw.Divider(thickness: 0.5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL COLLECTED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                  pw.Text(CurrencyFormatter.format(revenue, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)),
                ],
              ),
              pw.SizedBox(height: 3 * PdfPageFormat.mm),
              pw.Text('*** END OF SUMMARY SLIP ***', style: const pw.TextStyle(fontSize: 7)),
            ],
          );
        },
      ),
    );

    final cleanFileName = '${periodTitle.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}_Slip_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    final bytes = await doc.save();
    await _saveFile(bytes, cleanFileName, extensions: ['pdf']);
  }

  // --- ZRA Fiscal Z-Report PDF Export (Full A4 Executive Document) ---
  Future<void> exportZraFiscalZReportToPdf({
    required Map<String, dynamic> reportData,
    StoreConfig? config,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'ZK';

    final date = (reportData['date'] is DateTime) ? reportData['date'] as DateTime : DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(date);
    final dateFileStr = DateFormat('yyyyMMdd').format(date);

    final taxATaxable = (reportData['taxA16Taxable'] as num?)?.toDouble() ?? 0.0;
    final taxAVat = (reportData['taxA16Vat'] as num?)?.toDouble() ?? 0.0;
    final taxBTaxable = (reportData['taxB0Taxable'] as num?)?.toDouble() ?? 0.0;
    final taxCTaxable = (reportData['taxCExportTaxable'] as num?)?.toDouble() ?? 0.0;
    final taxDTaxable = (reportData['taxDExemptTaxable'] as num?)?.toDouble() ?? 0.0;
    
    final grossSales = (reportData['grossSales'] as num?)?.toDouble() ?? 0.0;
    final totalTax = (reportData['totalTax'] as num?)?.toDouble() ?? 0.0;
    final netSales = (reportData['netSales'] as num?)?.toDouble() ?? 0.0;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildDocumentHeader(
              config,
              title: 'ZRA Fiscal Day Summary (Z-Report)',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 8),

            // SDC & Fiscal Identification Banner
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('REPORT DATE: ${DateFormat('dd MMMM yyyy').format(date).toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.SizedBox(height: 3),
                      pw.Text('GENERATION TIME: $dateStr', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                      pw.SizedBox(height: 3),
                      pw.Text('BRANCH CODE (bhfId): ${config?.bhfId ?? "00"}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('SDC ID: ${config?.sdcId ?? "SDC00300000014"}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
                      pw.SizedBox(height: 3),
                      pw.Text('ZRA TPIN: ${config?.tpin ?? "N/A"}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                      pw.SizedBox(height: 3),
                      pw.Text('TERMINAL: ${config?.terminalName ?? "POS-01"}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Invoices Range & Counters
            pw.Text(
              'SDC INVOICE COUNTERS & RANGE',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Column(
                children: [
                  _buildSummaryRow('Total Transactions Processed:', '${reportData["totalTransactions"] ?? 0}'),
                  _buildSummaryRow('Normal Sales Invoices:', '${reportData["normalInvoicesCount"] ?? 0}'),
                  _buildSummaryRow('Credit Notes (Refunds):', '${reportData["creditNotesCount"] ?? 0}'),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey300),
                  _buildSummaryRow('First SDC Receipt No:', '${reportData["firstSdcReceipt"] ?? "N/A"}'),
                  _buildSummaryRow('Last SDC Receipt No:', '${reportData["lastSdcReceipt"] ?? "N/A"}'),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // ZRA Tax Categorization Breakdown Table
            pw.Text(
              'TAX CATEGORIZATION BREAKDOWN',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: brandColor),
            ),
            pw.SizedBox(height: 6),
            pw.TableHelper.fromTextArray(
              headers: ['Tax Category', 'Tax Rate', 'Taxable Amount ($currency)', 'Tax / VAT Amount ($currency)', 'Gross Total ($currency)'],
              data: [
                [
                  'Tax A (Standard 16% VAT)',
                  '16.0000%',
                  CurrencyFormatter.format(taxATaxable, currency),
                  CurrencyFormatter.formatTaxPrecision(taxAVat, currency),
                  CurrencyFormatter.format(taxATaxable + taxAVat, currency),
                ],
                [
                  'Tax B (Zero-Rated 0%)',
                  '0.0000%',
                  CurrencyFormatter.format(taxBTaxable, currency),
                  CurrencyFormatter.formatTaxPrecision(0.0, currency),
                  CurrencyFormatter.format(taxBTaxable, currency),
                ],
                if (taxCTaxable > 0)
                  [
                    'Tax C (Export 0%)',
                    '0.0000%',
                    CurrencyFormatter.format(taxCTaxable, currency),
                    CurrencyFormatter.formatTaxPrecision(0.0, currency),
                    CurrencyFormatter.format(taxCTaxable, currency),
                  ],
                if (taxDTaxable > 0)
                  [
                    'Tax D (Exempt 0%)',
                    '0.0000%',
                    CurrencyFormatter.format(taxDTaxable, currency),
                    CurrencyFormatter.formatTaxPrecision(0.0, currency),
                    CurrencyFormatter.format(taxDTaxable, currency),
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                fontSize: 8.5,
              ),
              headerDecoration: pw.BoxDecoration(
                color: brandColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
              ),
              cellHeight: 22,
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
              },
            ),
            pw.SizedBox(height: 14),

            // Financial Totals Box
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: brandColor, width: 1.5),
              ),
              child: pw.Column(
                children: [
                  _buildSummaryRow('NET TAXABLE SALES:', CurrencyFormatter.format(netSales, currency)),
                  _buildSummaryRow('TOTAL TAX COLLECTED:', CurrencyFormatter.formatTaxPrecision(totalTax, currency)),
                  pw.Divider(thickness: 1, color: brandColor),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('GROSS SALES (TAX INCL):', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text(CurrencyFormatter.format(grossSales, currency), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: brandColor)),
                    ],
                  ),
                ],
              ),
            ),
            pw.Spacer(),
            _buildDocumentFooter(config),
          ],
        ),
      ),
    );

    final bytes = await pdf.save();
    await _saveFile(bytes, 'ZRA_Fiscal_Z_Report_$dateFileStr.pdf', extensions: ['pdf']);
  }

  // --- ZRA Fiscal Z-Report 80mm Slip PDF ---
  Future<void> exportZraFiscalZReportSlipToPdf({
    required Map<String, dynamic> reportData,
    StoreConfig? config,
  }) async {
    final pdfDoc = pw.Document();
    final currency = config?.currencySymbol ?? 'ZK';
    final date = (reportData['date'] is DateTime) ? reportData['date'] as DateTime : DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(date);
    final dateFileStr = DateFormat('yyyyMMdd').format(date);

    final taxATaxable = (reportData['taxA16Taxable'] as num?)?.toDouble() ?? 0.0;
    final taxAVat = (reportData['taxA16Vat'] as num?)?.toDouble() ?? 0.0;
    final taxBTaxable = (reportData['taxB0Taxable'] as num?)?.toDouble() ?? 0.0;
    final taxCTaxable = (reportData['taxCExportTaxable'] as num?)?.toDouble() ?? 0.0;
    final taxDTaxable = (reportData['taxDExemptTaxable'] as num?)?.toDouble() ?? 0.0;
    
    final grossSales = (reportData['grossSales'] as num?)?.toDouble() ?? 0.0;
    final totalTax = (reportData['totalTax'] as num?)?.toDouble() ?? 0.0;
    final netSales = (reportData['netSales'] as num?)?.toDouble() ?? 0.0;

    pdfDoc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(5 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(config?.businessName ?? 'BELEKA RETAIL STORE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              if (config?.tpin != null && config!.tpin!.isNotEmpty)
                pw.Text('TPIN: ${config.tpin}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('SDC ID: ${config?.sdcId ?? "SDC00300000014"}', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('BRANCH CODE (bhfId): ${config?.bhfId ?? "00"}', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 2 * PdfPageFormat.mm),
              pw.Divider(thickness: 1),
              pw.Text('ZRA FISCAL DAY SUMMARY (Z-REPORT)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text('REPORT DATE: $dateStr', style: const pw.TextStyle(fontSize: 7.5)),
              pw.Divider(thickness: 1),

              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('TOTAL TRANSACTIONS', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["totalTransactions"] ?? 0}', style: const pw.TextStyle(fontSize: 8))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('NORMAL INVOICES', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["normalInvoicesCount"] ?? 0}', style: const pw.TextStyle(fontSize: 8))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('CREDIT NOTES (REFUNDS)', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["creditNotesCount"] ?? 0}', style: const pw.TextStyle(fontSize: 8))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('FIRST SDC INVOICE', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["firstSdcReceipt"] ?? "N/A"}', style: const pw.TextStyle(fontSize: 8))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('LAST SDC INVOICE', style: const pw.TextStyle(fontSize: 8)), pw.Text('${reportData["lastSdcReceipt"] ?? "N/A"}', style: const pw.TextStyle(fontSize: 8))],
              ),

              pw.Divider(thickness: 0.5),
              pw.Align(alignment: pw.Alignment.centerLeft, child: pw.Text('TAX CATEGORIZATION BREAKDOWN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))),
              pw.SizedBox(height: 1 * PdfPageFormat.mm),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('TAX A (16.0%) TAXABLE', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(taxATaxable, currency), style: const pw.TextStyle(fontSize: 7.5))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('TAX A (16.0%) TAX AMT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5)), pw.Text(CurrencyFormatter.formatTaxPrecision(taxAVat, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7.5))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('TAX B (0.0% ZERO-RATED)', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(taxBTaxable, currency), style: const pw.TextStyle(fontSize: 7.5))],
              ),
              if (taxCTaxable > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('TAX C (EXPORT)', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(taxCTaxable, currency), style: const pw.TextStyle(fontSize: 7.5))],
                ),
              if (taxDTaxable > 0)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [pw.Text('TAX D (EXEMPT)', style: const pw.TextStyle(fontSize: 7.5)), pw.Text(CurrencyFormatter.format(taxDTaxable, currency), style: const pw.TextStyle(fontSize: 7.5))],
                ),

              pw.Divider(thickness: 1),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('NET TAXABLE SALES', style: const pw.TextStyle(fontSize: 8)), pw.Text(CurrencyFormatter.format(netSales, currency), style: const pw.TextStyle(fontSize: 8))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('TOTAL TAX COLLECTED', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8)), pw.Text(CurrencyFormatter.formatTaxPrecision(totalTax, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8))],
              ),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [pw.Text('GROSS SALES (INCL)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5)), pw.Text(CurrencyFormatter.format(grossSales, currency), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))],
              ),

              pw.SizedBox(height: 3 * PdfPageFormat.mm),
              pw.Text('*** END OF ZRA FISCAL Z-REPORT ***', style: const pw.TextStyle(fontSize: 7.5)),
            ],
          );
        },
      ),
    );

    final bytes = await pdfDoc.save();
    await _saveFile(bytes, 'ZRA_Z_Report_Slip_$dateFileStr.pdf', extensions: ['pdf']);
  }

  // --- Excel Exports ---

  Future<void> exportInventoryToExcel(List<Product> products, {StoreConfig? config}) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Inventory'];
    final currency = config?.currencySymbol ?? 'ZK';
    
    sheet.appendRow([TextCellValue(config?.businessName.toUpperCase() ?? 'BELEKA PRO POS')]);
    if (config?.branchName != null) {
      sheet.appendRow([TextCellValue('Branch: ${config!.branchName!}')]);
    }
    if (config?.address != null) {
      sheet.appendRow([TextCellValue('Address: ${config!.address!}')]);
    }
    if (config?.tpin != null) {
      sheet.appendRow([TextCellValue('TPIN: ${config!.tpin!}')]);
    }
    sheet.appendRow([TextCellValue('Inventory Report - ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);

    sheet.appendRow([
      TextCellValue('SKU'),
      TextCellValue('Product Name'),
      TextCellValue('Price ($currency)'),
      TextCellValue('Cost ($currency)'),
      TextCellValue('Stock Level'),
      TextCellValue('Status'),
    ]);

    for (var p in products) {
      sheet.appendRow([
        TextCellValue(p.sku),
        TextCellValue(p.name),
        DoubleCellValue(p.price),
        DoubleCellValue(p.unitCost),
        IntCellValue(p.stockLevel),
        TextCellValue(p.isArchived ? 'Archived' : 'Active'),
      ]);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile(bytes, 'inventory_${DateTime.now().millisecondsSinceEpoch}.xlsx', extensions: ['xlsx']);
  }

  Future<void> exportDailySummaryToExcel({
    required Map<String, double> stats,
    required List<Map<String, dynamic>> topProducts,
    required Map<String, double> paymentDist,
    StoreConfig? config,
  }) async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Daily Summary'];

    sheet.appendRow([TextCellValue(config?.businessName.toUpperCase() ?? 'BELEKA PRO POS')]);
    if (config?.branchName != null) {
      sheet.appendRow([TextCellValue('Branch: ${config!.branchName!}')]);
    }
    if (config?.tpin != null) {
      sheet.appendRow([TextCellValue('TPIN: ${config!.tpin!}')]);
    }
    sheet.appendRow([TextCellValue('Daily Sales Summary - ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Metric'), TextCellValue('Value')]);
    sheet.appendRow([TextCellValue('Total Revenue'), DoubleCellValue(stats['todayRevenue'] ?? 0.0)]);
    sheet.appendRow([TextCellValue('Total Profit'), DoubleCellValue(stats['todayProfit'] ?? 0.0)]);
    sheet.appendRow([TextCellValue('Transaction Count'), IntCellValue(stats['todayCount']?.toInt() ?? 0)]);
    
    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Top Products')]);
    sheet.appendRow([TextCellValue('Product'), TextCellValue('Quantity')]);
    for (var p in topProducts) {
      sheet.appendRow([TextCellValue(p['name']), IntCellValue(p['quantity'])]);
    }

    sheet.appendRow([]);
    sheet.appendRow([TextCellValue('Payment Methods')]);
    for (var e in paymentDist.entries) {
      sheet.appendRow([TextCellValue(e.key.toUpperCase()), DoubleCellValue(e.value)]);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile(bytes, 'daily_summary_${DateTime.now().millisecondsSinceEpoch}.xlsx', extensions: ['xlsx']);
  }

  // =========================================================================
  // --- PURCHASES MODULE (PO, GRN, BILLS, RETURNS, SUPPLIERS) ---
  // =========================================================================

  /// Export or Print Single Purchase Order (PO)
  Future<void> exportPurchaseOrderToPdf(PurchaseOrder po, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'PURCHASE ORDER',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 16),
              
              // PO Metadata Box
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('PO Number: ${po.poNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Text('Date Created: ${dateFormat.format(po.createdAt)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        if (po.expectedDeliveryDate != null)
                          pw.Text('Expected Delivery: ${DateFormat('dd/MM/yyyy').format(po.expectedDeliveryDate!)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Supplier: ${po.supplierName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 4),
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                            color: brandColor,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                          ),
                          child: pw.Text(
                            'STATUS: ${po.status.toUpperCase()}',
                            style: pw.TextStyle(
                              color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Items Table
              pw.Text('ORDER ITEMS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: brandColor)),
              pw.SizedBox(height: 6),
              pw.TableHelper.fromTextArray(
                headers: ['#', 'Item Description / SKU', 'Qty Ordered', 'Unit Cost', 'Total Cost'],
                data: List<List<dynamic>>.generate(po.items.length, (index) {
                  final item = po.items.elementAt(index);
                  final lineTotal = item.unitCost * item.quantityOrdered;
                  return [
                    '${index + 1}',
                    item.productName,
                    '${item.quantityOrdered}',
                    '$currency${item.unitCost.toStringAsFixed(2)}',
                    '$currency${lineTotal.toStringAsFixed(2)}',
                  ];
                }),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white, fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: brandColor),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                },
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              ),
              pw.SizedBox(height: 12),

              // Totals
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 200,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL ORDER AMOUNT:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('$currency${po.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: brandColor)),
                    ],
                  ),
                ),
              ),

              if (po.notes != null && po.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 14),
                pw.Text('Special Instructions / Notes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text(po.notes!, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ],

              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 4),
                      pw.Text('Authorized Purchasing Officer', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 4),
                      pw.Text('Supplier Acceptance / Signature', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _buildDocumentFooter(config),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Purchase Order ${po.poNumber}', 'po_${po.poNumber}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Purchase Orders List (PDF)
  Future<void> exportPurchaseOrdersListToPdf(List<PurchaseOrder> pos, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy');

    final double grandTotal = pos.fold(0.0, (sum, item) => sum + item.totalAmount);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildDocumentHeader(
          config,
          title: 'PURCHASE ORDERS REPORT',
          brandColor: brandColor,
          logoImage: logoImage,
        ),
        footer: (context) => _buildDocumentFooter(config),
        build: (pw.Context context) => [
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['PO #', 'Date', 'Supplier', 'Expected', 'Status', 'Total ($currency)'],
            data: pos.map((po) => [
              po.poNumber,
              dateFormat.format(po.createdAt),
              po.supplierName,
              po.expectedDeliveryDate != null ? dateFormat.format(po.expectedDeliveryDate!) : '-',
              po.status.toUpperCase(),
              po.totalAmount.toStringAsFixed(2),
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white, fontSize: 8.5),
            headerDecoration: pw.BoxDecoration(color: brandColor),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {5: pw.Alignment.centerRight},
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('TOTAL PO COMMITMENT: $currency${grandTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Purchase Orders Report', 'purchase_orders_${DateTime.now().millisecondsSinceEpoch}.pdf', printDirectly: printDirectly);
  }

  /// Export Purchase Orders List to Excel
  Future<void> exportPurchaseOrdersListToExcel(List<PurchaseOrder> pos, {StoreConfig? config}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Purchase Orders'];
    excel.delete('Sheet1');

    sheet.appendRow([TextCellValue('PO Number'), TextCellValue('Date'), TextCellValue('Supplier'), TextCellValue('Expected Delivery'), TextCellValue('Status'), TextCellValue('Total Amount')]);
    for (var po in pos) {
      sheet.appendRow([
        TextCellValue(po.poNumber),
        TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(po.createdAt)),
        TextCellValue(po.supplierName),
        TextCellValue(po.expectedDeliveryDate != null ? DateFormat('yyyy-MM-dd').format(po.expectedDeliveryDate!) : ''),
        TextCellValue(po.status),
        DoubleCellValue(po.totalAmount),
      ]);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile(bytes, 'purchase_orders_${DateTime.now().millisecondsSinceEpoch}.xlsx', extensions: ['xlsx']);
  }

  /// Export or Print Single Goods Received Note (GRN)
  Future<void> exportGoodsReceivedNoteToPdf(GoodsReceivedNote grn, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'GOODS RECEIVED NOTE (GRN)',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('GRN Number: ${grn.grnNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Text('PO Ref: ${grn.poNumber}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('Warehouse Branch: ${grn.warehouseBranch}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Supplier: ${grn.supplierName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Text('Date Received: ${dateFormat.format(grn.receivedDate)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('Received By: ${grn.receivedBy ?? "Store Officer"}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('Total Items: ${grn.totalItemsReceived}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: brandColor)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              if (grn.notes != null && grn.notes!.isNotEmpty) ...[
                pw.Text('Delivery & Inspection Notes:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text(grn.notes!, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ],
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 4),
                      pw.Text('Warehouse Receiving Officer', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 140, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 4),
                      pw.Text('Delivering Driver / Transporter', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _buildDocumentFooter(config),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'GRN ${grn.grnNumber}', 'grn_${grn.grnNumber}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Goods Received Notes List (PDF)
  Future<void> exportGoodsReceivedNotesToPdf(List<GoodsReceivedNote> grns, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final dateFormat = DateFormat('dd/MM/yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildDocumentHeader(
          config,
          title: 'GOODS RECEIVED NOTES (GRN) REPORT',
          brandColor: brandColor,
          logoImage: logoImage,
        ),
        footer: (context) => _buildDocumentFooter(config),
        build: (pw.Context context) => [
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['GRN #', 'Date', 'Supplier', 'PO Ref', 'Received By', 'Items Received'],
            data: grns.map((g) => [
              g.grnNumber,
              dateFormat.format(g.receivedDate),
              g.supplierName,
              g.poNumber,
              g.receivedBy ?? '-',
              '${g.totalItemsReceived}',
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white, fontSize: 8.5),
            headerDecoration: pw.BoxDecoration(color: brandColor),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {5: pw.Alignment.centerRight},
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'GRN Report', 'grn_report_${DateTime.now().millisecondsSinceEpoch}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Single Purchase Invoice / Bill
  Future<void> exportPurchaseInvoiceToPdf(PurchaseInvoice invoice, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'PURCHASE INVOICE / BILL',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Invoice #: ${invoice.invoiceNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Text('Supplier Ref: ${invoice.supplierInvoiceNumber ?? "N/A"}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('PO Ref: ${invoice.poNumber}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        if (invoice.dueDate != null)
                          pw.Text('Due Date: ${dateFormat.format(invoice.dueDate!)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Supplier: ${invoice.supplierName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Text('Date: ${dateFormat.format(invoice.createdAt)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Container(
                          margin: const pw.EdgeInsets.only(top: 4),
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: pw.BoxDecoration(
                            color: brandColor,
                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                          ),
                          child: pw.Text(
                            'STATUS: ${invoice.paymentStatus.toUpperCase()}',
                            style: pw.TextStyle(
                              color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 220,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('TOTAL INVOICE:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          pw.Text('$currency${invoice.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: brandColor)),
                        ],
                      ),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Amount Paid:', style: const pw.TextStyle(fontSize: 9, color: PdfColors.green800)),
                          pw.Text('$currency${invoice.amountPaid.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.green800)),
                        ],
                      ),
                      pw.Divider(color: PdfColors.grey300),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('Balance Due:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.red800)),
                          pw.Text('$currency${invoice.balanceDue.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.red800)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              pw.Spacer(),
              _buildDocumentFooter(config),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Purchase Invoice ${invoice.invoiceNumber}', 'invoice_${invoice.invoiceNumber}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Purchase Invoices List (PDF)
  Future<void> exportPurchaseInvoicesToPdf(List<PurchaseInvoice> invoices, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy');

    final double totalBilled = invoices.fold(0.0, (sum, i) => sum + i.totalAmount);
    final double totalPaid = invoices.fold(0.0, (sum, i) => sum + i.amountPaid);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildDocumentHeader(
          config,
          title: 'PURCHASE INVOICES & BILLS REPORT',
          brandColor: brandColor,
          logoImage: logoImage,
        ),
        footer: (context) => _buildDocumentFooter(config),
        build: (pw.Context context) => [
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Invoice #', 'Date', 'Supplier', 'Status', 'Total ($currency)', 'Paid ($currency)', 'Balance ($currency)'],
            data: invoices.map((inv) => [
              inv.invoiceNumber,
              dateFormat.format(inv.createdAt),
              inv.supplierName,
              inv.paymentStatus.toUpperCase(),
              inv.totalAmount.toStringAsFixed(2),
              inv.amountPaid.toStringAsFixed(2),
              inv.balanceDue.toStringAsFixed(2),
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white, fontSize: 8.5),
            headerDecoration: pw.BoxDecoration(color: brandColor),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
            },
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Total Invoiced: $currency${totalBilled.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text('Total Paid: $currency${totalPaid.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.green800)),
              pw.Text('Outstanding Payables: $currency${(totalBilled - totalPaid).toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.red800)),
            ],
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Purchase Invoices Report', 'invoices_report_${DateTime.now().millisecondsSinceEpoch}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Single Purchase Return / Debit Note
  Future<void> exportPurchaseReturnToPdf(PurchaseReturn ret, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'PURCHASE RETURN / DEBIT NOTE',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Return #: ${ret.returnNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Text('PO Ref: ${ret.poNumber ?? "N/A"}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('Date: ${dateFormat.format(ret.createdAt)}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Supplier: ${ret.supplierName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Text('Reason: ${ret.reason}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('Method: ${ret.refundMethod}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: brandColor)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TOTAL DEBIT CREDIT AMOUNT:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text('$currency${ret.totalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: brandColor)),
                ],
              ),
              pw.Spacer(),
              _buildDocumentFooter(config),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Debit Note ${ret.returnNumber}', 'debit_note_${ret.returnNumber}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Purchase Returns List (PDF)
  Future<void> exportPurchaseReturnsToPdf(List<PurchaseReturn> returns, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy');

    final double totalReturnAmount = returns.fold(0.0, (sum, r) => sum + r.totalAmount);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildDocumentHeader(
              config,
              title: 'PURCHASE RETURNS & DEBIT NOTES REPORT',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: ['Return #', 'Supplier', 'PO Ref', 'Date', 'Reason', 'Refund Method', 'Amount ($currency)'],
              data: returns.map((r) => [
                r.returnNumber,
                r.supplierName,
                r.poNumber ?? '-',
                dateFormat.format(r.createdAt),
                r.reason,
                r.refundMethod,
                r.totalAmount.toStringAsFixed(2),
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: brandColor),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 12),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Text('Total Returns Value: $currency${totalReturnAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: brandColor)),
            ),
            pw.SizedBox(height: 16),
            _buildDocumentFooter(config),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Purchase Returns Report', 'purchase_returns_report.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Supplier Statement (PDF)
  Future<void> exportSupplierStatementToPdf(
    Supplier supplier, {
    List<PurchaseInvoice>? invoices,
    StoreConfig? config,
    bool printDirectly = false,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd MMM yyyy');

    final suppInvoices = invoices?.where((i) => i.supplierName == supplier.name).toList() ?? [];
    final totalInvoiced = suppInvoices.fold<double>(0.0, (sum, i) => sum + i.totalAmount);
    final totalPaid = suppInvoices.fold<double>(0.0, (sum, i) => sum + i.amountPaid);
    final totalDue = supplier.balance;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildDocumentHeader(
              config,
              title: 'SUPPLIER ACCOUNT STATEMENT',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 16),

            // Supplier Information & Summary Box
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('SUPPLIER / VENDOR DETAILS:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
                      pw.SizedBox(height: 4),
                      pw.Text(supplier.name, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                      if (supplier.tpin != null) pw.Text('TPIN: ${supplier.tpin}', style: const pw.TextStyle(fontSize: 9)),
                      if (supplier.phoneNumber != null) pw.Text('Phone: ${supplier.phoneNumber}', style: const pw.TextStyle(fontSize: 9)),
                      if (supplier.email != null) pw.Text('Email: ${supplier.email}', style: const pw.TextStyle(fontSize: 9)),
                      if (supplier.address != null) pw.Text('Address: ${supplier.address}', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('STATEMENT SUMMARY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
                      pw.SizedBox(height: 4),
                      pw.Text('Statement Date: ${dateFormat.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Total Invoiced: $currency${totalInvoiced.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Total Paid: $currency${totalPaid.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 9)),
                      pw.SizedBox(height: 4),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: totalDue > 0 ? PdfColors.red50 : PdfColors.green50,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        ),
                        child: pw.Text(
                          'OUTSTANDING PAYABLE: $currency${totalDue.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                            color: totalDue > 0 ? PdfColors.red800 : PdfColors.green800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Invoices & Bills Table
            pw.Text('TRANSACTION / INVOICE HISTORY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
            pw.SizedBox(height: 8),

            if (suppInvoices.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                alignment: pw.Alignment.center,
                child: pw.Text('No individual invoices recorded for this supplier yet.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              )
            else
              pw.TableHelper.fromTextArray(
                headers: ['Invoice #', 'PO Ref', 'Date', 'Total ($currency)', 'Paid ($currency)', 'Balance ($currency)', 'Status'],
                data: suppInvoices.map((inv) => [
                  inv.invoiceNumber,
                  inv.poNumber,
                  dateFormat.format(inv.createdAt),
                  inv.totalAmount.toStringAsFixed(2),
                  inv.amountPaid.toStringAsFixed(2),
                  inv.balanceDue.toStringAsFixed(2),
                  inv.paymentStatus.toUpperCase(),
                ]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
                headerDecoration: pw.BoxDecoration(color: brandColor),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
              ),

            pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Prepared By: __________________________', style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 4),
                    pw.Text('Accounts Payable Officer', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Authorized Signature: ____________________', style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 4),
                    pw.Text('Finance & Audit Director', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            _buildDocumentFooter(config),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Supplier Statement ${supplier.name}', 'statement_${supplier.name.replaceAll(' ', '_')}.pdf', printDirectly: printDirectly);
  }

  // =========================================================================
  // --- ACCOUNTS & TREASURY MODULE (PAYMENT ACCOUNTS, EXPENSES, TRANSFERS, SHIFTS) ---
  // =========================================================================

  /// Export or Print Payment Accounts & Treasury Summary (PDF)
  Future<void> exportPaymentAccountsToPdf(List<PaymentAccount> accounts, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';

    final double totalLiquidity = accounts.fold(0.0, (sum, a) => sum + a.balance);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'TREASURY & PAYMENT ACCOUNTS',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: ['Account Name', 'Type', 'Account / Phone #', 'Currency', 'Default', 'Balance ($currency)'],
                data: accounts.map((a) => [
                  a.name,
                  a.accountType,
                  a.accountNumber ?? '-',
                  a.currency,
                  a.isDefault ? 'YES' : 'NO',
                  a.balance.toStringAsFixed(2),
                ]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white, fontSize: 9),
                headerDecoration: pw.BoxDecoration(color: brandColor),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {5: pw.Alignment.centerRight},
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 240,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(color: brandColor, width: 1),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('TOTAL LIQUID ASSETS:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('$currency${totalLiquidity.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: brandColor)),
                    ],
                  ),
                ),
              ),
              pw.Spacer(),
              _buildDocumentFooter(config),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Treasury Accounts Summary', 'treasury_accounts_${DateTime.now().millisecondsSinceEpoch}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Single Expense Voucher (PDF)
  Future<void> exportExpenseVoucherToPdf(Expense expense, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'EXPENSE PAYMENT VOUCHER',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 14),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Voucher Ref: ${expense.expenseNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text('Date: ${dateFormat.format(expense.expenseDate)}', style: const pw.TextStyle(fontSize: 8.5)),
                      ],
                    ),
                    pw.Divider(color: PdfColors.grey300),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Category: ${expense.category}', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('Account: ${expense.paymentAccountName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                      ],
                    ),
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Recorded By: ${expense.recordedBy ?? "Cashier"}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                        if (expense.referenceNumber != null)
                          pw.Text('Ref #: ${expense.referenceNumber}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              if (expense.notes != null && expense.notes!.isNotEmpty) ...[
                pw.Text('EXPENSE PARTICULARS & NOTES', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: brandColor)),
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(8),
                  margin: const pw.EdgeInsets.only(top: 4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(expense.notes!, style: const pw.TextStyle(fontSize: 9.5)),
                ),
              ],
              pw.SizedBox(height: 12),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('DISBURSED AMOUNT:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text('$currency${expense.amount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: brandColor)),
                ],
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 100, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 2),
                      pw.Text('Authorized Officer', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 100, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 2),
                      pw.Text('Receiver / Payee Signature', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Expense Voucher ${expense.expenseNumber}', 'expense_${expense.expenseNumber}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Operating Expenses Summary (PDF)
  Future<void> exportExpensesToPdf(List<Expense> expenses, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy');

    final double totalExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildDocumentHeader(
          config,
          title: 'OPERATING EXPENSES REPORT',
          brandColor: brandColor,
          logoImage: logoImage,
        ),
        footer: (context) => _buildDocumentFooter(config),
        build: (pw.Context context) => [
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Expense #', 'Date', 'Category', 'Account', 'Recorded By', 'Amount ($currency)'],
            data: expenses.map((e) => [
              e.expenseNumber,
              dateFormat.format(e.expenseDate),
              e.category,
              e.paymentAccountName,
              e.recordedBy ?? '-',
              e.amount.toStringAsFixed(2),
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white, fontSize: 8.5),
            headerDecoration: pw.BoxDecoration(color: brandColor),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {5: pw.Alignment.centerRight},
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('TOTAL EXPENSES: $currency${totalExpenses.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: brandColor)),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Expenses Report', 'expenses_report_${DateTime.now().millisecondsSinceEpoch}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Single Fund Transfer Voucher (PDF)
  Future<void> exportTransferVoucherToPdf(AccountTransfer transfer, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'TREASURY TRANSFER VOUCHER',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 14),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Transfer Ref: ${transfer.transferNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text('Date: ${dateFormat.format(transfer.transferDate)}', style: const pw.TextStyle(fontSize: 8.5)),
                      ],
                    ),
                    pw.Divider(color: PdfColors.grey300),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Source Account: ${transfer.fromAccountName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                        pw.Text('Destination: ${transfer.toAccountName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: brandColor)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 14),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('TRANSFER AMOUNT:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                  pw.Text('$currency${transfer.amount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: brandColor)),
                ],
              ),
              if (transfer.reference != null && transfer.reference!.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text('Transfer Reference & Purpose:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.Text(transfer.reference!, style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
              ],
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 100, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 2),
                      pw.Text('Initiating Officer', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 100, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 2),
                      pw.Text('Receiving / Approving Officer', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Transfer Voucher ${transfer.transferNumber}', 'transfer_${transfer.transferNumber}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Till Shift Balancing Z-Report (PDF)
  Future<void> exportShiftZReportToPdf(CashShift shift, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'TILL SHIFT Z-REPORT',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Shift #: ${shift.shiftNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text('Terminal: ${shift.terminalId}', style: const pw.TextStyle(fontSize: 8.5)),
                        pw.Text('Cashier: ${shift.cashierName}', style: const pw.TextStyle(fontSize: 8.5)),
                        pw.Text('Branch: ${shift.branchName}', style: const pw.TextStyle(fontSize: 8.5)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Opened: ${dateFormat.format(shift.openingTime)}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('Closed: ${shift.closingTime != null ? dateFormat.format(shift.closingTime!) : "STILL OPEN"}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('Status: ${shift.status}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5, color: brandColor)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 12),
              pw.Text('CASH DRAWER RECONCILIATION', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: brandColor)),
              pw.SizedBox(height: 6),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Opening Cash Float:', style: const pw.TextStyle(fontSize: 8.5)),
                        pw.Text('$currency${shift.openingCash.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Cash Sales (+):', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.green800)),
                        pw.Text('$currency${shift.cashSales.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.green800)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Cash Expenses Paid Out (-):', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.red800)),
                        pw.Text('-$currency${shift.cashExpenses.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.red800)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Cash Refunds (-):', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.red800)),
                        pw.Text('-$currency${shift.cashRefunds.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.red800)),
                      ],
                    ),
                    pw.Divider(color: PdfColors.grey300),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('EXPECTED IN DRAWER:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                        pw.Text('$currency${shift.expectedClosingCash.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('ACTUAL COUNTED CLOSING:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                        pw.Text('$currency${shift.actualClosingCash.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
                      ],
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('CASH VARIANCE (OVER/SHORT):', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                        pw.Text(
                          '$currency${shift.cashVariance.toStringAsFixed(2)}',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 9.5,
                            color: shift.cashVariance == 0.0 ? PdfColors.green800 : (shift.cashVariance > 0 ? PdfColors.blue800 : PdfColors.red800),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Container(width: 100, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 2),
                      pw.Text('Cashier Signature', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Container(width: 100, height: 1, color: PdfColors.grey400),
                      pw.SizedBox(height: 2),
                      pw.Text('Branch Manager Verification', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Shift Z-Report ${shift.shiftNumber}', 'shift_z_report_${shift.shiftNumber}.pdf', printDirectly: printDirectly);
  }

  /// Export or Print Sales Refund Authorization Voucher (PDF)
  Future<void> exportRefundVoucherToPdf(RefundTransaction refund, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final dateFormat = DateFormat('dd MMM yyyy, HH:mm');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'CUSTOMER REFUND VOUCHER',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 12),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Refund Voucher #: ${refund.refundNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text('Date: ${dateFormat.format(refund.refundDate)}', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text('Refund Channel: ${refund.refundType.toUpperCase()}', style: const pw.TextStyle(fontSize: 9)),
                    if (refund.saleTransactionUuid != null) pw.Text('Original Receipt Ref: ${refund.saleTransactionUuid}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    if (refund.authorizedBy != null) pw.Text('Authorized By: ${refund.authorizedBy}', style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 6),
                    pw.Text('Reason for Refund: ${refund.reason}', style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.red50,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                  border: pw.Border.all(color: PdfColors.red200),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('TOTAL AMOUNT REFUNDED:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.red900)),
                    pw.Text('$currency${refund.amount.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: PdfColors.red900)),
                  ],
                ),
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Customer Acceptance: ____________________', style: const pw.TextStyle(fontSize: 8.5)),
                      pw.SizedBox(height: 3),
                      pw.Text('Signature & Date', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Manager Approval: ____________________', style: const pw.TextStyle(fontSize: 8.5)),
                      pw.SizedBox(height: 3),
                      pw.Text('Authorized Cashier / Manager', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _buildDocumentFooter(config),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Refund Voucher ${refund.refundNumber}', 'refund_${refund.refundNumber}.pdf', printDirectly: printDirectly);
  }

  // =========================================================================
  // --- BRANCHES MODULE (MULTI-BRANCH PERFORMANCE & ROSTER) ---
  // =========================================================================

  /// Export or Print Multi-Branch Performance Report (PDF)
  Future<void> exportBranchesReportToPdf(List<StoreBranch> branches, {StoreConfig? config, bool printDirectly = false}) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';

    final double totalNetworkSales = branches.fold(0.0, (sum, b) => sum + b.salesToday);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDocumentHeader(
                config,
                title: 'MULTI-BRANCH PERFORMANCE REPORT',
                brandColor: brandColor,
                logoImage: logoImage,
              ),
              pw.SizedBox(height: 16),
              pw.TableHelper.fromTextArray(
                headers: ['Code', 'Branch Store Name', 'ZRA BHF', 'Assigned Manager', 'Contact Phone', 'Status', 'Sales Today ($currency)'],
                data: branches.map((b) => [
                  b.code,
                  b.name + (b.isHQ ? ' [HQ]' : ''),
                  b.bhfId,
                  b.managerName ?? 'Manager',
                  b.phone ?? b.managerPhone ?? '-',
                  b.status,
                  b.salesToday.toStringAsFixed(2),
                ]).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white, fontSize: 8.5),
                headerDecoration: pw.BoxDecoration(color: brandColor),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {6: pw.Alignment.centerRight},
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              ),
              pw.SizedBox(height: 16),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 240,
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey100,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                    border: pw.Border.all(color: brandColor, width: 1),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('CONSOLIDATED NETWORK SALES:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
                      pw.Text('$currency${totalNetworkSales.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: brandColor)),
                    ],
                  ),
                ),
              ),
              pw.Spacer(),
              _buildDocumentFooter(config),
            ],
          );
        },
      ),
    );

    final bytes = await pdf.save();
    await _outputPdf(bytes, 'Multi-Branch Performance Report', 'branches_report_${DateTime.now().millisecondsSinceEpoch}.pdf', printDirectly: printDirectly);
  }

  /// Export Multi-Branch Performance Report to Excel
  Future<void> exportBranchesReportToExcel(List<StoreBranch> branches, {StoreConfig? config}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Branches Report'];
    excel.delete('Sheet1');

    sheet.appendRow([TextCellValue('Branch Code'), TextCellValue('Branch Name'), TextCellValue('ZRA BHF ID'), TextCellValue('Branch Manager'), TextCellValue('Phone'), TextCellValue('Status'), TextCellValue('Sales Today')]);
    for (var b in branches) {
      sheet.appendRow([
        TextCellValue(b.code),
        TextCellValue(b.name + (b.isHQ ? ' (HQ)' : '')),
        TextCellValue(b.bhfId),
        TextCellValue(b.managerName ?? ''),
        TextCellValue(b.phone ?? b.managerPhone ?? ''),
        TextCellValue(b.status),
        DoubleCellValue(b.salesToday),
      ]);
    }

    final bytes = Uint8List.fromList(excel.encode()!);
    await _saveFile(bytes, 'branches_report_${DateTime.now().millisecondsSinceEpoch}.xlsx', extensions: ['xlsx']);
  }

  // --- Helper Methods ---

  pw.Widget _buildDocumentFooter(StoreConfig? config) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300, thickness: 0.5),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated via Beleka Pro Enterprise POS & Supply Chain System',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
            ),
            pw.Text(
              'Confidential & Official Document',
              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _outputPdf(
    Uint8List bytes,
    String title,
    String defaultFileName, {
    bool printDirectly = false,
  }) async {
    if (printDirectly) {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: title,
      );
    } else {
      await _saveFile(bytes, defaultFileName, extensions: ['pdf']);
    }
  }

  Future<void> _saveFile(Uint8List bytes, String fileName, {List<String>? extensions}) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        // 1. Direct file write to Download or app documents directory
        try {
          Directory? saveDir;
          if (Platform.isAndroid) {
            final downloadDir = Directory('/storage/emulated/0/Download');
            if (await downloadDir.exists()) {
              saveDir = downloadDir;
            } else {
              saveDir = await getExternalStorageDirectory();
            }
          } else {
            saveDir = await getApplicationDocumentsDirectory();
          }

          if (saveDir != null) {
            final file = File('${saveDir.path}/$fileName');
            await file.writeAsBytes(bytes);
            debugPrint('EXPORT_SUCCESS: Export file written to ${file.path}');
          }
        } catch (e) {
          debugPrint('Mobile storage write warning: $e');
        }

        // 2. Open native mobile share/save sheet (Allows saving to Drive, WhatsApp, Files, etc.)
        await Printing.sharePdf(
          bytes: bytes,
          filename: fileName,
        );
        return;
      }

      // Desktop (Windows, macOS, Linux)
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Export',
        fileName: fileName,
        type: extensions != null ? FileType.custom : FileType.any,
        allowedExtensions: extensions,
      );

      if (outputFile != null) {
        final file = File(outputFile);
        await file.writeAsBytes(bytes);
        debugPrint('EXPORT_SUCCESS: Desktop export saved to $outputFile');
      }
    } catch (e) {
      debugPrint('EXPORT_ERROR: Failed to save export: $e');
    }
  }

  PdfColor _getSectorColor(CategorySector sector) {
    switch (sector) {
      case CategorySector.pharmacy: return PdfColors.cyan;
      case CategorySector.stationery: return PdfColors.purple;
      case CategorySector.grocery: return PdfColors.green;
      case CategorySector.food: return PdfColors.orange;
      case CategorySector.restaurant: return PdfColors.amber;
      case CategorySector.other: return PdfColor.fromInt(0xFFC1F11D);
    }
  }

  // ==========================================================================
  // --- STOCK ADJUSTMENT & REASON REPORT (ZRA SAR AUDIT REPORT) ---
  // ==========================================================================

  Future<void> exportStockMovementsToPdf(
    List<StockMovement> movements, {
    StoreConfig? config,
    DateTimeRange? dateRange,
    String? reasonFilter,
    bool printDirectly = false,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final df = DateFormat('yyyy-MM-dd HH:mm');

    // Aggregate statistics
    int totalInItems = 0;
    double totalInValue = 0.0;
    int totalOutItems = 0;
    double totalOutValue = 0.0;
    final Map<String, int> reasonQtyMap = {};
    final Map<String, double> reasonValueMap = {};

    for (final m in movements) {
      final isAdd = m.actionType == 'ADD';
      if (isAdd) {
        totalInItems += m.quantityChanged;
        totalInValue += m.totalCostImpact;
      } else {
        totalOutItems += m.quantityChanged;
        totalOutValue += m.totalCostImpact;
      }

      final key = '${m.reasonCategory} (ZRA ${m.movementType})';
      reasonQtyMap[key] = (reasonQtyMap[key] ?? 0) + m.quantityChanged;
      reasonValueMap[key] = (reasonValueMap[key] ?? 0.0) + m.totalCostImpact;
    }

    final netQty = totalInItems - totalOutItems;
    final netValue = totalInValue - totalOutValue;

    String dateSubtitle = 'All Historical Stock Movements';
    if (dateRange != null) {
      final dFormat = DateFormat('dd MMM yyyy');
      dateSubtitle = '${dFormat.format(dateRange.start)} to ${dFormat.format(dateRange.end)}';
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildDocumentHeader(
              config,
              title: 'INVENTORY STOCK ADJUSTMENTS & REASON AUDIT (ZRA SAR)',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Period: $dateSubtitle ${reasonFilter != null ? " • Filter: $reasonFilter" : ""}',
                  style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic),
                ),
                pw.Text(
                  'Total Adjustments: ${movements.length} records',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                ),
              ],
            ),
            pw.Divider(color: PdfColors.grey400, thickness: 0.8),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated by Beleka Pro POS • ZRA Smart Invoice & DigiTax Compliant',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
        build: (context) => [
          // KPI Summary Cards Box
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
            ),
            child: pw.Row(
              children: [
                // Inflow Summary
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('TOTAL STOCK IN (+)', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                      pw.SizedBox(height: 2),
                      pw.Text('$totalInItems items', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                      pw.Text('Valuation: $currency${totalInValue.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.Container(width: 1, height: 35, color: PdfColors.grey300),
                pw.SizedBox(width: 12),

                // Outflow / Loss Summary
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('TOTAL LOSS & WRITE-OFF (-)', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.red800)),
                      pw.SizedBox(height: 2),
                      pw.Text('$totalOutItems items', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
                      pw.Text('Cost Impact: $currency${totalOutValue.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.Container(width: 1, height: 35, color: PdfColors.grey300),
                pw.SizedBox(width: 12),

                // Net Change
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('NET STOCK CHANGE', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                      pw.SizedBox(height: 2),
                      pw.Text('${netQty >= 0 ? "+" : ""}$netQty items', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                      pw.Text('Net Value: ${netValue >= 0 ? "+" : ""}$currency${netValue.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),

          // Reason Breakdown Summary
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BREAKDOWN BY BUSINESS REASON & ZRA CLASSIFICATION:',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                ),
                pw.SizedBox(height: 4),
                pw.Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: reasonQtyMap.entries.map((e) {
                    final val = reasonValueMap[e.key] ?? 0.0;
                    return pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey100,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                      ),
                      child: pw.Text(
                        '${e.key}: ${e.value} pcs ($currency${val.toStringAsFixed(2)})',
                        style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 14),

          // Itemized Table
          pw.TableHelper.fromTextArray(
            headers: [
              'Date & Time',
              'Product Name & SKU',
              'Action',
              'Qty',
              'Balance',
              'Unit Cost',
              'Cost Impact',
              'ZRA Code & Reason Description',
              'Operator',
              'DigiTax Sync',
            ],
            data: movements.map((m) {
              final isAdd = m.actionType == 'ADD';
              final sign = isAdd ? '+' : '-';
              return [
                df.format(m.timestamp),
                '${m.productName}\nSKU: ${m.sku}',
                m.actionType,
                '$sign${m.quantityChanged}',
                '${m.previousStock} -> ${m.newStock}',
                '$currency${m.unitCost.toStringAsFixed(2)}',
                '$currency${m.totalCostImpact.toStringAsFixed(2)}',
                'ZRA ${m.movementType}: ${m.reasonCategory}${m.reasonNotes != null && m.reasonNotes!.isNotEmpty ? "\nNote: ${m.reasonNotes}" : ""}',
                m.userName ?? 'System',
                m.isSyncedWithDigitax ? 'Synced' : 'Local Queue',
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: _isColorLight(brandColor) ? PdfColors.black : PdfColors.white,
              fontSize: 8,
            ),
            headerDecoration: pw.BoxDecoration(
              color: brandColor,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            rowDecoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            ),
            cellHeight: 22,
            cellStyle: const pw.TextStyle(fontSize: 7.5),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.center,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.center,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerLeft,
              8: pw.Alignment.centerLeft,
              9: pw.Alignment.center,
            },
          ),
        ],
      ),
    );

    if (printDirectly) {
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'stock_adjustments_sar_${DateTime.now().millisecondsSinceEpoch}',
      );
    } else {
      final bytes = await pdf.save();
      await _saveFile(
        bytes,
        'stock_adjustments_sar_${DateTime.now().millisecondsSinceEpoch}.pdf',
        extensions: ['pdf'],
      );
    }
  }

  Future<void> exportStockMovementsToExcel(List<StockMovement> movements, {StoreConfig? config}) async {
    final excel = Excel.createExcel();
    final sheet = excel['Stock Movements SAR'];
    excel.delete('Sheet1');

    final currency = config?.currencySymbol ?? 'K';
    final df = DateFormat('yyyy-MM-dd HH:mm:ss');

    sheet.appendRow([
      TextCellValue('Timestamp'),
      TextCellValue('Product ID'),
      TextCellValue('Product Name'),
      TextCellValue('SKU'),
      TextCellValue('Branch Code'),
      TextCellValue('Action Type'),
      TextCellValue('ZRA SAR Code'),
      TextCellValue('Quantity Changed'),
      TextCellValue('Previous Stock'),
      TextCellValue('New Stock Balance'),
      TextCellValue('Unit Cost ($currency)'),
      TextCellValue('Cost Impact ($currency)'),
      TextCellValue('Reason Category'),
      TextCellValue('Reference Notes'),
      TextCellValue('Operator Name'),
      TextCellValue('DigiTax Synced'),
      TextCellValue('DigiTax SAR No'),
    ]);

    for (final m in movements) {
      sheet.appendRow([
        TextCellValue(df.format(m.timestamp)),
        IntCellValue(m.productId),
        TextCellValue(m.productName),
        TextCellValue(m.sku),
        TextCellValue(m.branchCode),
        TextCellValue(m.actionType),
        TextCellValue(m.movementType),
        IntCellValue(m.quantityChanged),
        IntCellValue(m.previousStock),
        IntCellValue(m.newStock),
        DoubleCellValue(m.unitCost),
        DoubleCellValue(m.totalCostImpact),
        TextCellValue(m.reasonCategory),
        TextCellValue(m.reasonNotes ?? ''),
        TextCellValue(m.userName ?? ''),
        TextCellValue(m.isSyncedWithDigitax ? 'YES' : 'NO'),
        TextCellValue(m.digitaxSarNo ?? ''),
      ]);
    }

    final bytes = excel.encode();
    if (bytes != null) {
      await _saveFile(
        Uint8List.fromList(bytes),
        'stock_movements_sar_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        extensions: ['xlsx'],
      );
    }
  }

  Future<void> exportStockMovementsToCsv(List<StockMovement> movements, {StoreConfig? config}) async {
    final currency = config?.currencySymbol ?? 'K';
    final df = DateFormat('yyyy-MM-dd HH:mm:ss');

    final List<List<dynamic>> rows = [
      [
        'Timestamp',
        'Product ID',
        'Product Name',
        'SKU',
        'Branch Code',
        'Action Type',
        'ZRA SAR Code',
        'Quantity Changed',
        'Previous Stock',
        'New Stock Balance',
        'Unit Cost ($currency)',
        'Cost Impact ($currency)',
        'Reason Category',
        'Reference Notes',
        'Operator Name',
        'DigiTax Synced',
        'DigiTax SAR No',
      ]
    ];

    for (final m in movements) {
      rows.add([
        df.format(m.timestamp),
        m.productId,
        m.productName,
        m.sku,
        m.branchCode,
        m.actionType,
        m.movementType,
        m.quantityChanged,
        m.previousStock,
        m.newStock,
        m.unitCost.toStringAsFixed(2),
        m.totalCostImpact.toStringAsFixed(2),
        m.reasonCategory,
        m.reasonNotes ?? '',
        m.userName ?? '',
        m.isSyncedWithDigitax ? 'YES' : 'NO',
        m.digitaxSarNo ?? '',
      ]);
    }

    final csvData = const ListToCsvConverter().convert(rows);
    await _saveFile(
      Uint8List.fromList(csvData.codeUnits),
      'stock_movements_sar_${DateTime.now().millisecondsSinceEpoch}.csv',
      extensions: ['csv'],
    );
  }

  // ==========================================================================
  // --- ZRA TAX REMITTANCE STATEMENT PDF ---
  // ==========================================================================

  /// Generates a ZRA Tax Remittance Statement PDF listing all upcoming / overdue
  /// tax deadlines for the business.  [deadlines] comes from TaxReminderService.
  Future<void> exportTaxReminderPdf({
    StoreConfig? config,
    required List<dynamic> deadlines, // List<ZraTaxDeadline> — typed as dynamic to avoid circular imports
    String? periodLabel,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final isLight = _isColorLight(brandColor);
    final onBrand = isLight ? PdfColors.black : PdfColors.white;
    final currency = config?.currencySymbol ?? 'K';
    final now = DateTime.now();
    final fmt = NumberFormat('#,##0.00');
    final dateFmt = DateFormat('dd MMMM yyyy');
    final period = periodLabel ?? DateFormat('MMMM yyyy').format(now);

    // Helper: urgency badge colour → PdfColor
    PdfColor urgencyPdf(dynamic urgency) {
      // urgency is TaxUrgency enum from tax_reminder_service.dart
      // We compare the index to avoid importing the enum directly.
      switch (urgency.index as int) {
        case 0: return PdfColors.red700;        // overdue
        case 1: return PdfColors.deepOrange700;  // today
        case 2: return PdfColors.orange700;      // critical
        case 3: return PdfColors.amber700;       // warning
        case 4: return PdfColors.teal500;        // upcoming
        default: return PdfColors.teal500;       // clear
      }
    }

    String urgencyLabel(dynamic d) {
      final days = d.daysUntilDue as int;
      switch (d.urgency.index as int) {
        case 0: return '${(-days)}d OVERDUE';
        case 1: return 'DUE TODAY';
        case 2: return '${days}d LEFT';
        case 3: return '${days}d';
        case 4: return '${days}d';
        default: return 'OK';
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          // ── Header ──────────────────────────────────────────────────────
          _buildDocumentHeader(config, title: 'ZRA Tax Remittance Statement', brandColor: brandColor),
          pw.SizedBox(height: 16),

          // ── Period & Generated date ──────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: pw.BoxDecoration(
              color: brandColor.shade(0.92),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Reporting Period:  $period',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: onBrand,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Generated:  ${dateFmt.format(now)}',
                      style: pw.TextStyle(fontSize: 9, color: onBrand),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (config?.tpin != null)
                      pw.Text(
                        'TPIN: ${config!.tpin!}',
                        style: pw.TextStyle(fontSize: 9, color: onBrand),
                      ),
                    pw.Text(
                      'Tax Authority: ZRA Zambia',
                      style: pw.TextStyle(fontSize: 9, color: onBrand),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 20),

          // ── Deadlines table ──────────────────────────────────────────────
          pw.Text(
            'UPCOMING & OVERDUE TAX OBLIGATIONS',
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.grey700,
              letterSpacing: 1.2,
            ),
          ),
          pw.SizedBox(height: 8),

          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: PdfColors.grey200, width: 0.5),
              bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(3.5),
              1: const pw.FlexColumnWidth(1.8),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(1.5),
              4: const pw.FlexColumnWidth(1.6),
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: pw.BoxDecoration(color: brandColor),
                children: [
                  'TAX TYPE', 'CHARGE PERIOD', 'DUE DATE', 'STATUS', 'AMOUNT'
                ].map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: pw.Text(h,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: onBrand,
                      letterSpacing: 0.5,
                    ),
                  ),
                )).toList(),
              ),

              // Data rows
              ...List.generate(deadlines.length, (i) {
                final d = deadlines[i];
                final isOdd = i.isOdd;
                final statusColor = urgencyPdf(d.urgency);
                final amount = d.amountPayable;

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: isOdd ? PdfColors.grey50 : PdfColors.white,
                  ),
                  children: [
                    // Tax type
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            d.taxName as String,
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                          ),
                          if ((d.description as String?) != null)
                            pw.Text(
                              d.description as String,
                              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                            ),
                        ],
                      ),
                    ),
                    // Charge period
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: pw.Text(
                        DateFormat('MMM yyyy').format(d.chargeMonth as DateTime),
                        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ),
                    // Due date
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: pw.Text(
                        dateFmt.format(d.dueDate as DateTime),
                        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                      ),
                    ),
                    // Status badge
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: statusColor.shade(0.85),
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          urgencyLabel(d),
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ),
                    // Estimated amount
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: pw.Text(
                        amount != null
                            ? '$currency ${fmt.format(amount)}'
                            : '—',
                        style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: amount != null ? PdfColors.grey900 : PdfColors.grey400,
                        ),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),

          pw.SizedBox(height: 20),

          // ── ZRA Official Reminder ────────────────────────────────────────
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const PdfColor(1.0, 0.96, 0.80),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.amber700, width: 0.8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ZRA FILING DEADLINES — QUICK REFERENCE',
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.amber900,
                    letterSpacing: 0.8,
                  ),
                ),
                pw.SizedBox(height: 6),
                ...(() {
                  final taxType = config?.businessTaxType ?? 'VAT_STANDARD';
                  final r = <String>[];
                  if (taxType == 'TURNOVER_TAX' || taxType == 'COMPOSITE') {
                    r.add('14th  →  Turnover Tax (TOT) — 14th of the month following the month of transaction');
                  }
                  if (taxType == 'VAT_STANDARD' || taxType == 'COMPOSITE') {
                    r.add('18th  →  Value Added Tax (VAT Suppliers) — 18th of the month following the month of transaction');
                  }
                  return r;
                })().map((rule) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 3),
                  child: pw.Text(
                    rule,
                    style: const pw.TextStyle(fontSize: 8, color: PdfColors.brown800),
                  ),
                )),
              ],
            ),
          ),

          pw.SizedBox(height: 16),

          // ── Footer ──────────────────────────────────────────────────────
          pw.Text(
            'Taxpayers must maintain business records for at least 6 years. '
            'All returns must be submitted electronically via the ZRA Taxpayer portal. '
            'Generated by Beleka POS — for official filings, visit www.zra.org.zm.',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey500),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final tpin = config?.tpin ?? 'TPIN';
    final monthStr = DateFormat('MMM_yyyy').format(now);
    await _saveFile(bytes, 'ZRA_Tax_Remittance_${tpin}_$monthStr.pdf', extensions: ['pdf']);
  }

  // ==========================================================================
  // --- TILL FINANCIAL & HANDOVER REPORT (PER TILL PDF) ---
  // ==========================================================================

  /// Generates a Per-Till Revenue & Float Handover Report (PDF / Print)
  Future<void> exportTillReportToPdf({
    required PosTerminal terminal,
    CashShift? currentShift,
    required List<SaleTransaction> todayTransactions,
    StoreConfig? config,
    bool printDirectly = false,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final now = DateTime.now();

    // Calculations
    double totalGrossSales = 0.0;
    double cashSales = 0.0;
    double airtelSales = 0.0;
    double mtnSales = 0.0;
    double cardBankSales = 0.0;
    double otherSales = 0.0;
    int transactionCount = 0;

    for (final tx in todayTransactions) {
      if (tx.status == 'refunded' && !tx.isCreditNote) continue;
      final amount = tx.isCreditNote ? -tx.totalAmount : tx.totalAmount;
      totalGrossSales += amount;
      transactionCount += tx.isCreditNote ? -1 : 1;

      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash')) {
        cashSales += amount;
      } else if (method.contains('airtel')) {
        airtelSales += amount;
      } else if (method.contains('mtn')) {
        mtnSales += amount;
      } else if (method.contains('card') || method.contains('bank') || method.contains('visa')) {
        cardBankSales += amount;
      } else {
        otherSales += amount;
      }
    }

    final double openingFloat = currentShift?.openingCash ?? 0.0;
    final double cashExpenses = currentShift?.cashExpenses ?? 0.0;
    final double cashRefunds = currentShift?.cashRefunds ?? 0.0;
    final double totalCashToHandIn = openingFloat + cashSales - cashExpenses - cashRefunds;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildDocumentHeader(
              config,
              title: 'TILL FINANCIAL & HANDOVER REPORT',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 14),

            // Till & Shift Metadata Box
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('TILL CODE: ${terminal.terminalCode}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.Text('Till Name: ${terminal.name}', style: const pw.TextStyle(fontSize: 9.5)),
                      pw.Text('Branch: ${terminal.branchName} (ZRA bhfId: ${terminal.digitaxBhfId})', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Assigned Cashier: ${currentShift?.cashierName ?? terminal.assignedCashierName ?? "Open Access Cashier"}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: brandColor)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Report Date: ${DateFormat('dd MMMM yyyy').format(now)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Generated At: ${DateFormat('HH:mm:ss').format(now)}', style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text('Shift Status: ${currentShift != null ? currentShift.status : "NO OPEN SHIFT"}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: currentShift?.status == 'OPEN' ? PdfColors.green700 : PdfColors.grey700)),
                      if (currentShift != null)
                        pw.Text('Shift #: ${currentShift.shiftNumber}', style: const pw.TextStyle(fontSize: 8.5)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Financial Summary Cards
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: PdfColors.blue200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL TILL SALES TODAY', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                        pw.SizedBox(height: 4),
                        pw.Text('$currency ${totalGrossSales.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.Text('$transactionCount Completed Transactions', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.amber50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: PdfColors.amber200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('OPENING CASH FLOAT', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                        pw.SizedBox(height: 4),
                        pw.Text('$currency ${openingFloat.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                        pw.Text('Issued Float at Start of Shift', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: PdfColors.green300),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL CASH TO HAND IN', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        pw.SizedBox(height: 4),
                        pw.Text('$currency ${totalCashToHandIn.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        pw.Text('Float + Cash Inflow (- Outflows)', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Cash Drawer Flow & Handover Breakdown
            pw.Text('CASH DRAWER RECONCILIATION & HANDOVER AUDIT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('CASH ITEM / RECONCILIATION LINE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('TYPE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('AMOUNT ($currency)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Opening Till Float (Starting Balance)', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Starting Base', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$currency ${openingFloat.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Cash Sales Collected Today (+)', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Inflow', style: const pw.TextStyle(fontSize: 8, color: PdfColors.green700))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('+$currency ${cashSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green700))),
                  ],
                ),
                if (cashExpenses > 0)
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Cash Paid Out / Expenses (-)', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Outflow', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('-$currency ${cashExpenses.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, color: PdfColors.red700))),
                    ],
                  ),
                if (cashRefunds > 0)
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Customer Cash Refunds (-)', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Outflow', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('-$currency ${cashRefunds.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, color: PdfColors.red700))),
                    ],
                  ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('EXACT CASH TO HAND IN TO MANAGER', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('TOTAL DUE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$currency ${totalCashToHandIn.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5, color: PdfColors.green900))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Payment Methods Breakdown Table
            pw.Text('ALL PAYMENT METHODS REVENUE BREAKDOWN', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('PAYMENT METHOD', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('CATEGORY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('TOTAL SALES ($currency)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Cash Payment', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Cash in Drawer', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${cashSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Airtel Money', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Mobile Money Wallet', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${airtelSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('MTN MoMo', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Mobile Money Wallet', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${mtnSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Debit / Credit Card & Bank POS', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Direct Banking / Card POS', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${cardBankSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
                if (otherSales > 0)
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Other Tender Methods', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Miscellaneous', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${otherSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                    ],
                  ),
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('TOTAL TILL REVENUE TODAY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('ALL METHODS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${totalGrossSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Signatures Section
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 180, height: 1, color: PdfColors.grey600),
                    pw.SizedBox(height: 4),
                    pw.Text('Cashier Handover Signature', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Name: ${currentShift?.cashierName ?? terminal.assignedCashierName ?? "Cashier"}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text('Date: ________________________', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 180, height: 1, color: PdfColors.grey600),
                    pw.SizedBox(height: 4),
                    pw.Text('Manager / Receiver Signature', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Verified Cash Float & Handover', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text('Date: ________________________', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    if (printDirectly) {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Till_Report_${terminal.terminalCode}_${DateFormat('ddMMyyyy').format(now)}.pdf',
      );
    } else {
      final bytes = await pdf.save();
      await _saveFile(bytes, 'Till_Report_${terminal.terminalCode}_${DateFormat('ddMMyyyy').format(now)}.pdf', extensions: ['pdf']);
    }
  }

  // ==========================================================================
  // --- DAILY BRANCH PERFORMANCE REPORT (HQ / OWNER PDF) ---
  // ==========================================================================

  /// Generates a Daily Branch Performance Report for Corporate Headquarters & Business Owner
  Future<void> exportBranchDailyReportToPdf({
    required StoreBranch branch,
    required List<SaleTransaction> branchTodayTransactions,
    required List<PosTerminal> branchTerminals,
    StoreConfig? config,
    bool printDirectly = false,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final now = DateTime.now();

    double totalRevenue = 0.0;
    double totalTax = 0.0;
    double totalProfit = 0.0;
    double cashSales = 0.0;
    double momoSales = 0.0;
    double cardSales = 0.0;
    int transactionCount = 0;

    for (final tx in branchTodayTransactions) {
      if (tx.status == 'refunded' && !tx.isCreditNote) continue;
      final factor = tx.isCreditNote ? -1.0 : 1.0;
      final amt = (tx.totalAmount.isNaN ? 0.0 : tx.totalAmount) * factor;
      totalRevenue += amt;
      totalTax += (tx.taxAmount.isNaN ? 0.0 : tx.taxAmount) * factor;
      totalProfit += (tx.grossProfit.isNaN ? 0.0 : (tx.isCreditNote ? -(tx.grossProfit.abs()) : tx.grossProfit));
      transactionCount += tx.isCreditNote ? -1 : 1;

      final method = tx.paymentMethod.toLowerCase();
      if (method.contains('cash')) {
        cashSales += amt;
      } else if (method.contains('airtel') || method.contains('mtn') || method.contains('momo') || method.contains('money')) {
        momoSales += amt;
      } else {
        cardSales += amt;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            _buildDocumentHeader(
              config,
              title: 'DAILY BRANCH PERFORMANCE REPORT',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 14),

            // Branch Details Box
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('STORE BRANCH: ${branch.name.toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.Text('Branch Code: ${branch.code} • ZRA bhfId: ${branch.bhfId}', style: const pw.TextStyle(fontSize: 9.5)),
                      pw.Text('Manager: ${branch.managerName ?? "Unassigned"} ${branch.managerPhone != null ? "(${branch.managerPhone})" : ""}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: brandColor)),
                      pw.Text('Physical Location: ${branch.address ?? "Location not specified"}', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Date: ${DateFormat('dd MMMM yyyy').format(now)}', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Reporting Entity: Corporate HQ', style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text('Status: ${branch.status} • Fiscal: ${branch.zraStatus}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                      pw.Text('${branchTerminals.length} Configured Till Registers', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // KPI Grid
            pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.green50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: PdfColors.green300),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TOTAL BRANCH SALES TODAY', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        pw.SizedBox(height: 4),
                        pw.Text('$currency ${totalRevenue.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                        pw.Text('$transactionCount Transactions', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.purple50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: PdfColors.purple200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('ESTIMATED GROSS PROFIT', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                        pw.SizedBox(height: 4),
                        pw.Text('$currency ${totalProfit.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.purple900)),
                        pw.Text('Revenue minus costs', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.blue50,
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                      border: pw.Border.all(color: PdfColors.blue200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('TAX / VAT COLLECTED', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.SizedBox(height: 4),
                        pw.Text('$currency ${totalTax.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                        pw.Text('ZRA Smart Invoice Tax', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Tills Performance Table for this Branch
            pw.Text('BRANCH TILL REGISTERS PERFORMANCE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('TILL REGISTER', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('ASSIGNED CASHIER', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('STATUS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('SALES TODAY ($currency)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                  ],
                ),
                if (branchTerminals.isEmpty)
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Default Checkout Counter', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Branch Cashiers', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('ACTIVE', style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.green700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('$currency ${totalRevenue.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                    ],
                  )
                else
                  ...branchTerminals.map((t) => pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${t.terminalCode} - ${t.name}', style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(t.assignedCashierName ?? "Unassigned", style: const pw.TextStyle(fontSize: 8.5))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text(t.status, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: t.status == 'ACTIVE' ? PdfColors.green700 : PdfColors.grey700))),
                      pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${t.salesToday.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold))),
                    ],
                  )),
              ],
            ),
            pw.SizedBox(height: 16),

            // Payment Methods Summary
            pw.Text('PAYMENT TENDER METHODS AT BRANCH', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: brandColor)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('METHOD', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('TOTAL AMOUNT ($currency)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Cash', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${cashSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Mobile Money (Airtel / MTN)', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${momoSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Card & Bank Transfers', style: const pw.TextStyle(fontSize: 8.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${cardSales.toStringAsFixed(2)}', textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 8.5))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 180, height: 1, color: PdfColors.grey600),
                    pw.SizedBox(height: 4),
                    pw.Text('Branch Manager Sign-off', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Manager: ${branch.managerName ?? "Branch Manager"}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text('Date: ________________________', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 180, height: 1, color: PdfColors.grey600),
                    pw.SizedBox(height: 4),
                    pw.Text('Corporate HQ / Owner Acceptance', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Headquarters Audit & Approval', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text('Date: ________________________', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    if (printDirectly) {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Branch_Daily_${branch.code}_${DateFormat('ddMMyyyy').format(now)}.pdf',
      );
    } else {
      final bytes = await pdf.save();
      await _saveFile(bytes, 'Branch_Daily_${branch.code}_${DateFormat('ddMMyyyy').format(now)}.pdf', extensions: ['pdf']);
    }
  }

  /// Export or Print Comprehensive Branch Performance, Profitability & Inventory Audit Report (PDF)
  Future<void> exportBranchComprehensiveReportToPdf({
    required StoreBranch branch,
    required String periodLabel,
    required DateTime startDate,
    required DateTime endDate,
    required List<SaleTransaction> transactions,
    required List<Expense> expenses,
    required List<StockMovement> stockMovements,
    required List<Product> products,
    StoreConfig? config,
    bool printDirectly = false,
  }) async {
    final pdf = pw.Document();
    final brandColor = _getBrandColor(config);
    final logoImage = await _loadLogoImage(config);
    final currency = config?.currencySymbol ?? 'K';
    final now = DateTime.now();
    final dateFmt = DateFormat('dd MMM yyyy');

    // 1. Sales metrics
    double grossSales = 0.0;
    double refundsAndVoids = 0.0;
    double discountsGiven = 0.0;
    double cogs = 0.0;
    double cashSales = 0.0;
    double cardSales = 0.0;
    double momoSales = 0.0;
    double creditSales = 0.0;
    int completedTxCount = 0;
    int refundTxCount = 0;

    // Fast-moving & items sold calculation
    final Map<int, Map<String, dynamic>> productSalesMap = {};

    for (final tx in transactions) {
      if (tx.status == 'refunded' || tx.isCreditNote) {
        refundTxCount++;
        refundsAndVoids += tx.totalAmount.abs();
      } else {
        completedTxCount++;
        grossSales += tx.totalAmount;
        discountsGiven += tx.discountAmount;
        cogs += tx.totalCost;

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

        // Aggregate items sold
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

    final double netSales = (grossSales - refundsAndVoids).clamp(0.0, double.infinity);
    final double grossProfit = (netSales - cogs);
    final double grossProfitMargin = netSales > 0 ? (grossProfit / netSales * 100) : 0.0;
    final double avgTxValue = completedTxCount > 0 ? (netSales / completedTxCount) : 0.0;

    // 2. Profitability & Expenses
    final double totalBranchExpenses = expenses.fold(0.0, (sum, e) => sum + e.amount);
    final double netProfitEstimate = grossProfit - totalBranchExpenses;
    final double netProfitMargin = netSales > 0 ? (netProfitEstimate / netSales * 100) : 0.0;

    // Expenses breakdown by category
    final Map<String, double> expensesByCategory = {};
    for (final exp in expenses) {
      expensesByCategory[exp.category] = (expensesByCategory[exp.category] ?? 0.0) + exp.amount;
    }

    // 3. Inventory metrics
    int totalItemsSold = 0;
    for (final p in productSalesMap.values) {
      totalItemsSold += (p['qty'] as int);
    }

    double currentStockCostVal = 0.0;
    double currentStockRetailVal = 0.0;
    int lowStockCount = 0;
    int outOfStockCount = 0;

    for (final prod in products) {
      if (!prod.isArchived) {
        final qty = prod.stockLevel;
        currentStockCostVal += (qty * prod.unitCost);
        currentStockRetailVal += (qty * prod.price);
        if (qty <= 0) {
          outOfStockCount++;
        } else if (qty < 10) {
          lowStockCount++;
        }
      }
    }

    // Stock movements metrics
    int stockReceivedQty = 0;
    double stockReceivedCost = 0.0;
    int stockTransferredInQty = 0;
    int stockTransferredOutQty = 0;
    int stockDamagedExpiredQty = 0;
    double stockDamagedExpiredCost = 0.0;
    int stockAdjustmentsQty = 0;

    for (final sm in stockMovements) {
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

    // Sort fast-moving items
    final sortedFastMoving = productSalesMap.entries.toList()
      ..sort((a, b) => (b.value['qty'] as int).compareTo(a.value['qty'] as int));

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (pw.Context context) {
          return [
            _buildDocumentHeader(
              config,
              title: 'HEADQUARTERS BRANCH AUDIT & PERFORMANCE REPORT',
              brandColor: brandColor,
              logoImage: logoImage,
            ),
            pw.SizedBox(height: 10),

            // Branch Details Header
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('BRANCH: ${branch.name.toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                      pw.Text('Branch Code: ${branch.code} | DigiTax bhfId: ${branch.bhfId}', style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text('Manager: ${branch.managerName ?? "Unassigned"} (${branch.managerPhone ?? "No contact"})', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: brandColor)),
                      pw.Text('Address: ${branch.address ?? "Not specified"}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Audit Period: $periodLabel', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: brandColor)),
                      pw.Text('${dateFmt.format(startDate)} - ${dateFmt.format(endDate)}', style: const pw.TextStyle(fontSize: 8.5)),
                      pw.Text('Generated: ${DateFormat('dd MMM yyyy, HH:mm').format(now)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.Text('Status: ${branch.status} • Fiscal: ${branch.zraStatus}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.green800)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // Section 1: Sales Performance
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(color: brandColor, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Text('1. SALES PERFORMANCE', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Gross Sales', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Discounts Given', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Refunds / Voids', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('NET SALES', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Transactions', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Avg Ticket (ATV)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${grossSales.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${discountsGiven.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('-$currency ${refundsAndVoids.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${netSales.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.green900))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$completedTxCount ($refundTxCount ret)', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${avgTxValue.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Text('Payment Channel Breakdown:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey50),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Cash Sales: $currency ${cashSales.toStringAsFixed(2)} (${netSales > 0 ? (cashSales / netSales * 100).toStringAsFixed(1) : "0"}%)', style: const pw.TextStyle(fontSize: 7.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Card/POS: $currency ${cardSales.toStringAsFixed(2)} (${netSales > 0 ? (cardSales / netSales * 100).toStringAsFixed(1) : "0"}%)', style: const pw.TextStyle(fontSize: 7.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Mobile Money: $currency ${momoSales.toStringAsFixed(2)} (${netSales > 0 ? (momoSales / netSales * 100).toStringAsFixed(1) : "0"}%)', style: const pw.TextStyle(fontSize: 7.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Credit/Invoice: $currency ${creditSales.toStringAsFixed(2)} (${netSales > 0 ? (creditSales / netSales * 100).toStringAsFixed(1) : "0"}%)', style: const pw.TextStyle(fontSize: 7.5))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Section 2: Profitability
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(color: brandColor, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Text('2. PROFITABILITY & EXPENSE STATEMENT', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Cost of Goods (COGS)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Gross Profit', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Gross Margin %', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Branch Expenses', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('NET PROFIT ESTIMATE', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Net Margin %', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${cogs.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${grossProfit.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${grossProfitMargin.toStringAsFixed(1)}%', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${totalBranchExpenses.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.orange800))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${netProfitEstimate.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: netProfitEstimate >= 0 ? PdfColors.green900 : PdfColors.red800))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('${netProfitMargin.toStringAsFixed(1)}%', style: const pw.TextStyle(fontSize: 8))),
                  ],
                ),
              ],
            ),
            if (expensesByCategory.isNotEmpty) ...[
              pw.SizedBox(height: 6),
              pw.Text('Allocated Branch Expenses by Category:', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Wrap(
                spacing: 8,
                runSpacing: 4,
                children: expensesByCategory.entries.map((e) => pw.Text('${e.key}: $currency ${e.value.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800))).toList(),
              ),
            ],
            pw.SizedBox(height: 12),

            // Section 3: Inventory
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(color: brandColor, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Text('3. INVENTORY VALUATION & STOCK MOVEMENTS', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Stock Value (Cost)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Stock Value (Retail)', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Units Sold', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Low Stock Items', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('Out of Stock Items', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${currentStockCostVal.toStringAsFixed(2)}', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$currency ${currentStockRetailVal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$totalItemsSold units', style: const pw.TextStyle(fontSize: 8))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$lowStockCount products', style: const pw.TextStyle(fontSize: 8, color: PdfColors.orange800))),
                    pw.Padding(padding: const pw.EdgeInsets.all(5), child: pw.Text('$outOfStockCount products', style: const pw.TextStyle(fontSize: 8, color: PdfColors.red800))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey50),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Received: $stockReceivedQty units ($currency ${stockReceivedCost.toStringAsFixed(2)})', style: const pw.TextStyle(fontSize: 7.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Transfers: In $stockTransferredInQty | Out $stockTransferredOutQty units', style: const pw.TextStyle(fontSize: 7.5))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Damaged/Expired: $stockDamagedExpiredQty units ($currency ${stockDamagedExpiredCost.toStringAsFixed(2)})', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.red800))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Audit Adjustments: $stockAdjustmentsQty units', style: const pw.TextStyle(fontSize: 7.5))),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),

            // Top Fast-Moving Products
            if (sortedFastMoving.isNotEmpty) ...[
              pw.Text('Top Fast-Moving Products (by Quantity Sold):', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 3),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('#', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Product Name', style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Units Sold', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('Revenue ($currency)', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold))),
                    ],
                  ),
                  ...sortedFastMoving.take(5).map((entry) {
                    final rank = sortedFastMoving.indexOf(entry) + 1;
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text('$rank', style: const pw.TextStyle(fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(entry.value['name'] as String, style: const pw.TextStyle(fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text(entry.value['qty'].toString(), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5))),
                        pw.Padding(padding: const pw.EdgeInsets.all(3.5), child: pw.Text((entry.value['revenue'] as double).toStringAsFixed(2), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: 7.5))),
                      ],
                    );
                  }),
                ],
              ),
            ],
            pw.SizedBox(height: 18),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 170, height: 1, color: PdfColors.grey600),
                    pw.SizedBox(height: 3),
                    pw.Text('Branch Manager Verification', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text(branch.managerName ?? 'Branch Manager', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                    pw.Text('Date: ________________________', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Container(width: 170, height: 1, color: PdfColors.grey600),
                    pw.SizedBox(height: 3),
                    pw.Text('Corporate HQ / Owner Acceptance', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Executive Audit Review', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                    pw.Text('Date: ________________________', style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    if (printDirectly) {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'HQ_Branch_Report_${branch.code}_${DateFormat('ddMMyyyy').format(now)}.pdf',
      );
    } else {
      final bytes = await pdf.save();
      await _saveFile(bytes, 'HQ_Branch_Report_${branch.code}_${DateFormat('ddMMyyyy').format(now)}.pdf', extensions: ['pdf']);
    }
  }
}

