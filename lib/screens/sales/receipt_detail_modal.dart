import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/widgets/manager_auth_dialog.dart';
import 'package:beleka_pos/screens/dashboard_screen.dart';
import 'package:beleka_pos/screens/sales_screen.dart';
import 'package:beleka_pos/screens/terminals_screen.dart';
import 'package:beleka_pos/screens/reports_screen.dart';

class ReceiptDetailModal extends ConsumerStatefulWidget {
  final SaleTransaction transaction;

  const ReceiptDetailModal({
    super.key,
    required this.transaction,
  });

  @override
  ConsumerState<ReceiptDetailModal> createState() => _ReceiptDetailModalState();
}

class _ReceiptDetailModalState extends ConsumerState<ReceiptDetailModal> {
  bool _isPrinting = false;
  bool _isRefundMode = false;
  final Set<int> _selectedItemIds = {};

  // Common refund reasons per ZRA requirement
  static const _refundReasons = [
    'Customer Returned Goods',
    'Goods Damaged / Defective',
    'Wrong Item Delivered',
    'Pricing Error',
    'Duplicate Charge',
    'Order Cancelled',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(digitaxInventoryServiceProvider).refreshTransactionFiscalData(widget.transaction).then((updated) {
        if (updated && mounted) setState(() {});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(transactionItemsProvider(widget.transaction.id));
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final screenHeight = MediaQuery.of(context).size.height;
    final maxModalHeight = (screenHeight * 0.88).clamp(420.0, 780.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: 500,
        constraints: BoxConstraints(maxHeight: maxModalHeight),
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 50,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sticky / Fixed Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
              child: _buildHeader(context),
            ),
            const Divider(color: Colors.white10, height: 1),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildSummary(),
                    const SizedBox(height: 18),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 16),

                    // Items Header with Select All button in Refund Mode
                    itemsAsync.when(
                      data: (items) => _buildItemsHeader(items),
                      loading: () => _buildItemsHeader([]),
                      error: (_, _) => _buildItemsHeader([]),
                    ),
                    const SizedBox(height: 12),

                    // Transaction Items List
                    itemsAsync.when(
                      data: (items) => _buildItemList(items, currency),
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(color: Color(0xFF1D4ED8))),
                      ),
                      error: (err, stack) => Text('Error: $err', style: const TextStyle(color: Colors.redAccent)),
                    ),
                    const SizedBox(height: 18),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 18),

                    // Totals Section
                    _buildTotalSection(currency, itemsAsync.value ?? []),
                    const SizedBox(height: 20),

                    // ZRA Smart Invoice Fiscal Card
                    _buildZraFiscalCard(ref.watch(storeConfigProvider).value),
                  ],
                ),
              ),
            ),

            // Sticky / Fixed Footer Actions
            const Divider(color: Colors.white10, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              child: _buildFooterActions(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isRefunded = widget.transaction.status == 'refunded' || widget.transaction.isCreditNote;
    final isCN = widget.transaction.isCreditNote;
    final title = isCN ? 'ZRA FISCAL CREDIT NOTE' : 'OFFICIAL RECEIPT';
    final receiptNum = isCN
        ? 'CN-#${widget.transaction.id.toString().padLeft(6, '0')}'
        : '#${widget.transaction.id.toString().padLeft(6, '0')}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isRefunded ? const Color(0xFFDC2626) : const Color(0xFF059669),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                      color: isRefunded ? const Color(0xFFDC2626) : const Color(0xFF059669),
                    ),
                  ),
                  if (isRefunded) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        'REFUNDED',
                        style: GoogleFonts.manrope(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.redAccent,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                receiptNum,
                style: GoogleFonts.inter(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final dateStr = DateFormat('MMM dd, yyyy • HH:mm').format(widget.transaction.timestamp);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildSummaryItem('TRANSACTION DATE', dateStr),
        _buildSummaryItem('PAYMENT METHOD', widget.transaction.paymentMethod.toUpperCase()),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 9,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsHeader(List<SaleItem> items) {
    final availableItems = items.where((i) => !i.isRefunded).toList();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _isRefundMode ? 'SELECT ITEMS TO REFUND' : 'TRANSACTION ITEMS',
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: _isRefundMode ? Colors.redAccent : Colors.white.withValues(alpha: 0.35),
          ),
        ),
        if (_isRefundMode && availableItems.isNotEmpty)
          InkWell(
            onTap: () {
              setState(() {
                if (_selectedItemIds.length == availableItems.length) {
                  _selectedItemIds.clear();
                } else {
                  _selectedItemIds.clear();
                  _selectedItemIds.addAll(availableItems.map((i) => i.id));
                }
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                _selectedItemIds.length == availableItems.length ? 'DESELECT ALL' : 'SELECT ALL',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1D4ED8),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItemList(List<SaleItem> items, String currency) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            'NO ITEMS RECORDED',
            style: GoogleFonts.manrope(fontSize: 11, color: Colors.white30, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Column(
      children: items.map((item) {
        final isSelected = _selectedItemIds.contains(item.id);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF1D4ED8).withValues(alpha: 0.12)
                : (item.isRefunded ? const Color(0xFFDC2626).withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF1D4ED8).withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
          child: InkWell(
            onTap: _isRefundMode && !item.isRefunded
                ? () {
                    setState(() {
                      if (isSelected) {
                        _selectedItemIds.remove(item.id);
                      } else {
                        _selectedItemIds.add(item.id);
                      }
                    });
                  }
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  if (_isRefundMode) ...[
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: item.isRefunded
                            ? null
                            : (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedItemIds.add(item.id);
                                  } else {
                                    _selectedItemIds.remove(item.id);
                                  }
                                });
                              },
                        activeColor: const Color(0xFF1D4ED8),
                        checkColor: Colors.white,
                        side: const BorderSide(color: Colors.white30),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: item.isRefunded
                          ? const Color(0xFFDC2626).withValues(alpha: 0.15)
                          : const Color(0xFF1D4ED8).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${item.quantity}×',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: item.isRefunded ? const Color(0xFFDC2626) : const Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: item.isRefunded ? Colors.white24 : Colors.white,
                            decoration: item.isRefunded ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        if (item.isRefunded)
                          Text(
                            'REFUNDED',
                            style: GoogleFonts.manrope(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.redAccent,
                              letterSpacing: 1,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    '$currency${(item.priceAtSale * item.quantity).toStringAsFixed(2)}',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: item.isRefunded ? Colors.white24 : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTotalSection(String currency, List<SaleItem> items) {
    double refundTotal = 0.0;
    if (_isRefundMode && _selectedItemIds.isNotEmpty) {
      for (final item in items) {
        if (_selectedItemIds.contains(item.id)) {
          refundTotal += (item.priceAtSale * item.quantity);
        }
      }
    }

    return Column(
      children: [
        _buildTotalRow('SUBTOTAL', widget.transaction.subtotal, currency),
        const SizedBox(height: 10),
        if (widget.transaction.discountAmount > 0) ...[
          _buildTotalRow('DISCOUNT', -widget.transaction.discountAmount, currency, isDiscount: true),
          const SizedBox(height: 10),
        ],
        _buildTotalRow('SALES TAX', widget.transaction.taxAmount, currency),
        const SizedBox(height: 16),
        _buildTotalRow(
          'GRAND TOTAL',
          widget.transaction.totalAmount,
          currency,
          isMain: true,
        ),
        if (_isRefundMode && refundTotal > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SELECTED FOR REFUND (${_selectedItemIds.length} ITEMS)',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: Colors.redAccent,
                    letterSpacing: 1,
                  ),
                ),
                Text(
                  '$currency${refundTotal.toStringAsFixed(2)}',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount, String currency, {bool isMain = false, bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: isMain ? 12 : 10,
            fontWeight: isMain ? FontWeight.w900 : FontWeight.w800,
            letterSpacing: 1.5,
            color: isMain ? Colors.white : Colors.white.withValues(alpha: 0.35),
          ),
        ),
        Text(
          '$currency${amount.toStringAsFixed(2)}',
          style: GoogleFonts.inter(
            fontSize: isMain ? 28 : 14,
            fontWeight: FontWeight.w900,
            color: isMain ? const Color(0xFF059669) : (isDiscount ? const Color(0xFFDC2626) : Colors.white),
            letterSpacing: isMain ? -0.5 : 0,
          ),
        ),
      ],
    );
  }

  Widget _buildZraFiscalCard(StoreConfig? config) {
    final dateFormatted = DateFormat('dd/MM/yyyy').format(widget.transaction.timestamp);
    final timeFormatted = DateFormat('HH:mm:ss').format(widget.transaction.timestamp);
    
    String formatZraInvoiceNo(String? raw, {String? sdcId}) {
      if (raw == null || raw.trim().isEmpty || raw.trim() == 'PENDING' || raw.trim() == 'null') return 'PENDING';
      final trimmed = raw.trim();
      if (trimmed.toUpperCase().startsWith('INV0') || trimmed.toUpperCase().startsWith('INV1/') || trimmed.toUpperCase().startsWith('INV/') || trimmed.toUpperCase().startsWith('CN')) return trimmed;
      final clean = trimmed.replaceFirst(RegExp(r'^(INV|CN)-0*'), '').replaceFirst(RegExp(r'^(INV|CN)-'), '');
      final sdcClean = (sdcId ?? '').replaceAll(RegExp(r'^SDC', caseSensitive: false), '');
      if (sdcClean.isNotEmpty) {
        return 'INV$sdcClean/$clean';
      }
      return 'INV1/$clean';
    }

    String sdcIdStr = (widget.transaction.zraSdcId != null && widget.transaction.zraSdcId!.isNotEmpty && widget.transaction.zraSdcId != 'PENDING')
        ? widget.transaction.zraSdcId!
        : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : '');
    if (sdcIdStr.isEmpty && widget.transaction.zraReceiptNumber != null) {
      final match = RegExp(r'INV(\d+)/', caseSensitive: false).firstMatch(widget.transaction.zraReceiptNumber!);
      if (match != null && match.group(1) != null && match.group(1) != '1') {
        sdcIdStr = 'SDC${match.group(1)}';
      }
    }
    if (sdcIdStr.isEmpty) sdcIdStr = 'PENDING';
    final sdcInvNoStr = formatZraInvoiceNo(widget.transaction.zraReceiptNumber, sdcId: sdcIdStr);
    final signatureStr = (widget.transaction.zraMarkId != null && widget.transaction.zraMarkId!.isNotEmpty)
        ? widget.transaction.zraMarkId!
        : 'PENDING';
    final internalDataStr = (widget.transaction.zraInternalData != null && widget.transaction.zraInternalData!.isNotEmpty)
        ? widget.transaction.zraInternalData!
        : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');

    final isApproved = widget.transaction.zraStatus == 'APPROVED' || 
        (widget.transaction.zraMarkId != null && widget.transaction.zraMarkId!.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'ZRA SMART INVOICE FISCAL CONTROL',
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isApproved ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: isApproved ? const Color(0xFF10B981).withValues(alpha: 0.4) : Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Text(
                  isApproved ? 'APPROVED' : 'PENDING',
                  style: GoogleFonts.manrope(
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    color: isApproved ? const Color(0xFF10B981) : Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFiscalRow('Date & Time', '$dateFormatted  $timeFormatted'),
          _buildFiscalRow('SDC Id', sdcIdStr),
          _buildFiscalRow('SDC Invoice No', sdcInvNoStr),
          _buildFiscalRow('Signature', signatureStr),
          _buildFiscalRow('Internal Data', internalDataStr),
          _buildFiscalRow('Invoice Type', widget.transaction.zraInvoiceType ?? (widget.transaction.isCreditNote ? 'Credit Note' : 'Normal Sale'), isMono: false),
          _buildFiscalRow('QR Verify URL', widget.transaction.zraQrCode ?? 'https://smartinvoice.zra.org.zm/verify', isUrl: true),
        ],
      ),
    );
  }

  Widget _buildFiscalRow(String label, String value, {bool isMono = true, bool isUrl = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: isUrl
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 10,
                            color: const Color(0xFF10B981),
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: value));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('ZRA QR Verification URL copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF10B981)),
                      ),
                    ],
                  )
                : Text(
                    value,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: isMono
                        ? GoogleFonts.ibmPlexMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)
                        : GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context) {
    final isRefunded = widget.transaction.status == 'refunded';

    if (_isRefundMode) {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _isRefundMode = false;
                    _selectedItemIds.clear();
                  });
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'CANCEL',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white70,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _selectedItemIds.isEmpty ? null : () => _executeRefund(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.redAccent.withValues(alpha: 0.3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.undo_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'CONFIRM REFUND (${_selectedItemIds.length})',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        if (!isRefunded) ...[
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () => setState(() => _isRefundMode = true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                  foregroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                  ),
                  elevation: 0,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.undo_rounded, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        'REFUND',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: (_isPrinting || isRefunded) ? null : () => _executeReprint(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                foregroundColor: isRefunded ? Colors.white24 : Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.02),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isPrinting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.print_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            isRefunded ? 'REPRINT BLOCKED' : 'REPRINT',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRefunded ? const Color(0xFFDC2626) : const Color(0xFF1D4ED8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'DONE',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _executeRefund(BuildContext context) async {
    if (_selectedItemIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select items to refund')),
      );
      return;
    }

    // 1. Manager Authentication Check
    final isManager = ref.read(isManagerProvider) || ref.read(isAdminProvider);
    bool authorized = isManager;

    if (!isManager) {
      authorized = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const ManagerAuthDialog(
          title: 'REFUND AUTHORIZATION',
          message: 'Manager or Admin PIN is required to process refunds.',
        ),
      ) ?? false;
    }

    if (!authorized || !context.mounted) return;

    // 2. Reason for Refund — required for ZRA credit note compliance
    final reason = await _showRefundReasonDialog(context);
    if (reason == null || !context.mounted) return;

    // 3. Final Confirmation showing items + reason
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141418),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.undo_rounded, color: Colors.redAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'CONFIRM REFUND',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w900,
                color: Colors.white,
                fontSize: 15,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Refunding ${_selectedItemIds.length} item(s) will:\n\u2022 Restore stock\n\u2022 Issue a ZRA fiscal credit note\n\u2022 Deduct from drawer/account',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('REASON', style: GoogleFonts.manrope(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white38, letterSpacing: 1)),
                        const SizedBox(height: 2),
                        Text(reason, style: GoogleFonts.inter(fontSize: 12, color: Colors.amber, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('CANCEL', style: GoogleFonts.manrope(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('PROCESS REFUND', style: GoogleFonts.manrope(fontWeight: FontWeight.w900)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      try {
        final db = ref.read(databaseServiceProvider);

        // 1. Fetch actual items from database
        final allItems = await db.getTransactionItems(widget.transaction.id);
        final refundedItems = allItems.where((i) => _selectedItemIds.contains(i.id)).toList();

        if (refundedItems.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No valid items selected for refund.')),
            );
          }
          return;
        }

        // 2. Perform DB refund (stock restore, shift & account deductions, audit records)
        await db.refundItems(widget.transaction.id, _selectedItemIds.toList());

        // 3. Generate & Persist official ZRA Credit Note
        // Use the original trader_invoice_number (the one that was sent to DigiTax during the sale)
        final origTraderInvNo = widget.transaction.zraReceiptNumber?.isNotEmpty == true
            ? widget.transaction.zraReceiptNumber!
            : 'INV-${widget.transaction.id}';
        final refundAmount = double.parse(refundedItems.fold(0.0, (s, i) => s + (i.priceAtSale * i.quantity)).toStringAsFixed(2));
        final refundCost = double.parse(refundedItems.fold(0.0, (s, i) => s + (i.unitCostAtSale * i.quantity)).toStringAsFixed(2));
        final taxableRefund = double.parse((refundAmount / 1.16).toStringAsFixed(2));
        final refundTax = double.parse((refundAmount - taxableRefund).toStringAsFixed(2));

        final refundTx = SaleTransaction(
          totalAmount: refundAmount,
          subtotal: taxableRefund,
          taxAmount: refundTax,
          grossProfit: -(refundAmount - refundCost),
          paymentMethod: widget.transaction.paymentMethod,
          cashierName: widget.transaction.cashierName,
          status: 'refunded',
          isCreditNote: true,
          orgInvoiceNo: origTraderInvNo,
          creditNoteReason: reason,
          customerTpin: widget.transaction.customerTpin,
          customerBusinessName: widget.transaction.customerBusinessName,
        );

        // Save refund transaction to Isar first so it gets a valid ID and attaches items
        await db.isar.writeTxn(() async {
          await db.isar.saleTransactions.put(refundTx);
          refundTx.items.addAll(refundedItems);
          await refundTx.items.save();
        });

        // 4. Submit to DigiTax online — fire and wait, show status in snackbar
        bool digitaxSuccess = false;
        try {
          digitaxSuccess = await ref.read(digitaxInventoryServiceProvider).submitCreditNoteToDigitax(
            refundTx,
            items: refundedItems,
            originalSdcInvoiceNo: origTraderInvNo,
            reason: reason,
          );
        } catch (e) {
          debugPrint('DIGITAX_CN_SUBMIT_ERROR: $e');
        }

        // 5. Print ZRA Fiscal Credit Note
        try {
          final config = ref.read(storeConfigProvider).value;
          await ref.read(printerServiceProvider).printReceipt(
            refundTx,
            refundedItems,
            config: config,
          );
        } catch (e) {
          debugPrint('PRINTER_CN_ERROR: $e');
        }

        // 6. Invalidate all dashboard, sales, account, and shift providers
        ref.invalidate(transactionItemsProvider(widget.transaction.id));
        ref.invalidate(recentTransactionsProvider);
        ref.invalidate(dashboardStatsProvider);
        ref.invalidate(cashierDashboardStatsProvider);
        ref.invalidate(activeShiftProvider);
        ref.invalidate(activeShiftsListProvider);
        ref.invalidate(paymentAccountsProvider);
        ref.invalidate(refundsProvider);
        ref.invalidate(productsProvider);
        ref.invalidate(reportTransactionsProvider);

        if (context.mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                digitaxSuccess
                    ? '\u2713 ZRA Credit Note submitted & refund processed!'
                    : 'Refund processed locally. ZRA credit note submission pending.',
              ),
              backgroundColor: digitaxSuccess ? const Color(0xFF10B981) : Colors.amber.shade700,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Refund failed: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  /// Prompts user to pick or type a reason for the refund (ZRA compliance)
  Future<String?> _showRefundReasonDialog(BuildContext context) async {
    String? selectedReason = _refundReasons.first;
    final customController = TextEditingController();
    bool isCustom = false;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REASON FOR REFUND',
                style: GoogleFonts.manrope(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  fontSize: 14,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Required by ZRA Smart Invoice for credit notes',
                style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reason chips
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _refundReasons.map((r) {
                    final isSelected = !isCustom && selectedReason == r;
                    return GestureDetector(
                      onTap: () => setModalState(() {
                        selectedReason = r;
                        isCustom = r == 'Other';
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.redAccent.withValues(alpha: 0.2)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? Colors.redAccent : Colors.white12,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          r,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                            color: isSelected ? Colors.redAccent : Colors.white60,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // Custom text field when 'Other' is selected
                if (isCustom) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: customController,
                    autofocus: true,
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Describe the reason...',
                      hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.redAccent),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('CANCEL', style: GoogleFonts.manrope(color: Colors.white38)),
            ),
            ElevatedButton(
              onPressed: () {
                final finalReason = isCustom
                    ? (customController.text.trim().isEmpty ? null : customController.text.trim())
                    : selectedReason;
                if (finalReason == null) return;
                Navigator.pop(ctx, finalReason);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('CONFIRM REASON', style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeReprint(BuildContext context) async {
    // Manager/Admin authorization check for reprinting
    final isManager = ref.read(isManagerProvider) || ref.read(isAdminProvider);
    bool authorized = isManager;

    if (!isManager) {
      authorized = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const ManagerAuthDialog(
          title: 'REPRINT AUTHORIZATION',
          message: 'Manager or Admin PIN is required to reprint receipts.',
        ),
      ) ?? false;
    }

    if (!authorized || !context.mounted) return;

    setState(() => _isPrinting = true);
    try {
      final selectedConfig = ref.read(selectedPrinterProvider);
      final items = await ref.read(transactionItemsProvider(widget.transaction.id).future);
      final config = ref.read(storeConfigProvider).value;

      if (selectedConfig == null) {
        await ref.read(exportServiceProvider).exportReceiptToPdf(
          widget.transaction,
          items,
          config: config,
          printDirectly: true,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Receipt sent to system print dialog')),
          );
        }
        return;
      }

      if (config?.digitaxApiKey?.isNotEmpty == true &&
          (widget.transaction.zraReceiptNumber == null || widget.transaction.zraReceiptNumber!.isEmpty)) {
        await ref.read(digitaxInventoryServiceProvider).refreshTransactionFiscalData(widget.transaction);
      }

      final printerService = ref.read(printerServiceProvider);

      if (!printerService.isConnected) {
        await printerService.connect(selectedConfig.device, selectedConfig.type);
      }

      if (printerService.isConnected) {
        final success = await printerService.printReceipt(
          widget.transaction,
          items,
          config: config,
        );
        if (success && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Receipt sent to printer')),
          );
        }
      } else {
        await ref.read(exportServiceProvider).exportReceiptToPdf(
          widget.transaction,
          items,
          config: config,
          printDirectly: true,
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('POS printer unavailable. Opened system print dialog.')),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Printing failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }
}

final transactionItemsProvider = FutureProvider.family<List<SaleItem>, int>((ref, id) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getTransactionItems(id);
});
