import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart' show debugPrint;
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:printing/printing.dart';
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

    final sdcIdStr = (transaction.zraSdcId != null && transaction.zraSdcId!.isNotEmpty)
        ? transaction.zraSdcId!
        : (config?.sdcId ?? 'SDC00300000014');
    final sdcInvNoStr = (transaction.zraReceiptNumber != null && transaction.zraReceiptNumber!.isNotEmpty)
        ? transaction.zraReceiptNumber!
        : 'INV-${transaction.id.toString().padLeft(8, '0')}';
    final signatureStr = (transaction.zraMarkId != null && transaction.zraMarkId!.isNotEmpty)
        ? transaction.zraMarkId!
        : 'MARK-${transaction.id.hashCode.toRadixString(16).toUpperCase()}';
    final internalDataStr = (transaction.zraInternalData != null && transaction.zraInternalData!.isNotEmpty)
        ? transaction.zraInternalData!
        : (config?.mrcNo ?? 'WIS00013845');
    final zraQrData = (transaction.zraQrCode != null && transaction.zraQrCode!.isNotEmpty)
        ? transaction.zraQrCode!
        : 'https://smartinvoice.zra.org.zm/verify?tpin=${config?.tpin ?? "1000000000"}&sdc=$sdcIdStr&rcpt=$sdcInvNoStr';

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
              pw.Text('TAX INVOICE / OFFICIAL RECEIPT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
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
              pw.Text('--------------------------------'),
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
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Export',
      fileName: fileName,
      type: extensions != null ? FileType.custom : FileType.any,
      allowedExtensions: extensions,
    );

    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(bytes);
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
}
