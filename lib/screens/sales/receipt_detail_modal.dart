import 'package:flutter/material.dart';
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
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? r'$';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 450,
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 50,
              spreadRadius: 10,
            ),
          ],
        ),
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context),
            const SizedBox(height: 24),
            _buildSummary(),
            const Divider(color: Colors.white10, height: 48),
            Text(
              'TRANSACTION ITEMS',
              style: GoogleFonts.manrope(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: itemsAsync.when(
                data: (items) => _buildItemList(items, currency),
                loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D))),
                error: (err, stack) => Text('Error: $err', style: const TextStyle(color: Colors.redAccent)),
              ),
            ),
            const Divider(color: Colors.white10, height: 48),
            _buildTotalSection(currency),
            const SizedBox(height: 24),
            _buildZraFiscalCard(ref.watch(storeConfigProvider).value),
            const SizedBox(height: 24),
            _buildFooterActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isRefunded = widget.transaction.status == 'refunded';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'OFFICIAL RECEIPT',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                    color: isRefunded ? Colors.redAccent : const Color(0xFFC1F11D),
                  ),
                ),
                if (isRefunded) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      'REFUNDED',
                      style: GoogleFonts.manrope(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: Colors.redAccent,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '#${widget.transaction.id.toString().padLeft(6, '0')}',
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.3), size: 24),
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
            color: Colors.white.withValues(alpha: 0.25),
          ),
        ),
        const SizedBox(height: 6),
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

  Widget _buildItemList(List<SaleItem> items, String currency) {
    if (items.isEmpty) return const Text('NO ITEMS RECORDED', style: TextStyle(color: Colors.white24));
    
    return ListView.separated(
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, _) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 32),
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = _selectedItemIds.contains(item.id);
        
        return InkWell(
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
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                if (_isRefundMode) ...[
                  SizedBox(
                    width: 24,
                    height: 24,
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
                      activeColor: const Color(0xFFC1F11D),
                      checkColor: Colors.black,
                      side: const BorderSide(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.isRefunded 
                        ? Colors.redAccent.withValues(alpha: 0.1)
                        : const Color(0xFFC1F11D).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${item.quantity}×',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: item.isRefunded ? Colors.redAccent : const Color(0xFFC1F11D),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.productName.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: item.isRefunded 
                              ? Colors.white.withValues(alpha: 0.2) 
                              : Colors.white.withValues(alpha: 0.8),
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
                  '$currency${item.priceAtSale.toStringAsFixed(2)}',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: item.isRefunded ? Colors.white24 : Colors.white,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTotalSection(String currency) {
    return Column(
      children: [
        _buildTotalRow('SUBTOTAL', widget.transaction.subtotal, currency),
        const SizedBox(height: 12),
        if (widget.transaction.discountAmount > 0) ...[
          _buildTotalRow('DISCOUNT', -widget.transaction.discountAmount, currency, isDiscount: true),
          const SizedBox(height: 12),
        ],
        _buildTotalRow('SALES TAX', widget.transaction.taxAmount, currency, isTax: true),
        const SizedBox(height: 20),
        _buildTotalRow(
          'GRAND TOTAL', 
          widget.transaction.totalAmount, 
          currency,
          isMain: true,
        ),
      ],
    );
  }

  Widget _buildTotalRow(String label, double amount, String currency, {bool isMain = false, bool isDiscount = false, bool isTax = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.manrope(
            fontSize: isMain ? 12 : 10,
            fontWeight: isMain ? FontWeight.w900 : FontWeight.w800,
            letterSpacing: 2,
            color: isMain ? Colors.white : Colors.white.withValues(alpha: 0.3),
          ),
        ),
        Text(
          '$currency${amount.toStringAsFixed(isTax ? 4 : 2)}',
          style: GoogleFonts.inter(
            fontSize: isMain ? 36 : 16,
            fontWeight: FontWeight.w900,
            color: isMain ? const Color(0xFFC1F11D) : (isDiscount ? Colors.redAccent : Colors.white),
            letterSpacing: -1,
          ),
        ),
      ],
    );
  }

  Widget _buildZraFiscalCard(StoreConfig? config) {
    final dateFormatted = DateFormat('dd/MM/yyyy').format(widget.transaction.timestamp);
    final timeFormatted = DateFormat('HH:mm:ss').format(widget.transaction.timestamp);
    String formatZraInvoiceNo(String? raw) {
      if (raw == null || raw.trim().isEmpty || raw.trim() == 'PENDING' || raw.trim() == 'null') return 'PENDING';
      final trimmed = raw.trim();
      if (trimmed.toUpperCase().startsWith('INV1/') || trimmed.toUpperCase().startsWith('INV/') || trimmed.toUpperCase().startsWith('CN')) return trimmed;
      final clean = trimmed.replaceFirst(RegExp(r'^(INV|CN)-0*'), '').replaceFirst(RegExp(r'^(INV|CN)-'), '');
      return 'INV1/$clean';
    }

    final sdcIdStr = (widget.transaction.zraSdcId != null && widget.transaction.zraSdcId!.isNotEmpty)
        ? widget.transaction.zraSdcId!
        : (config?.sdcId?.isNotEmpty == true ? config!.sdcId! : 'PENDING');
    final sdcInvNoStr = formatZraInvoiceNo(widget.transaction.zraReceiptNumber);
    final signatureStr = (widget.transaction.zraMarkId != null && widget.transaction.zraMarkId!.isNotEmpty)
        ? widget.transaction.zraMarkId!
        : 'PENDING';
    final internalDataStr = (widget.transaction.zraInternalData != null && widget.transaction.zraInternalData!.isNotEmpty)
        ? widget.transaction.zraInternalData!
        : (config?.mrcNo?.isNotEmpty == true ? config!.mrcNo! : 'PENDING');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 12),
          _buildFiscalRow('Date & Time', '$dateFormatted  $timeFormatted'),
          _buildFiscalRow('SDC Id', sdcIdStr),
          _buildFiscalRow('SDC Invoice No', sdcInvNoStr),
          _buildFiscalRow('Signature', signatureStr),
          _buildFiscalRow('Internal Data', internalDataStr),
          _buildFiscalRow('Invoice Type', widget.transaction.zraInvoiceType ?? 'Normal Sale'),
          _buildFiscalRow('QR Verify URL', widget.transaction.zraQrCode ?? 'https://smartinvoice.zra.org.zm/verify...'),
        ],
      ),
    );
  }

  Widget _buildFiscalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
          ),
          Text(
            value,
            style: GoogleFonts.ibmPlexMono(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context) {
    final isRefunded = widget.transaction.status == 'refunded';
    
    return Row(
      children: [
        if (!isRefunded) ...[
          Expanded(
            child: SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: () async {
                  if (!_isRefundMode) {
                    setState(() => _isRefundMode = true);
                    return;
                  }

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

                  if (!authorized) return;

                  if (!context.mounted) return;

                  // 2. Final Confirmation
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      backgroundColor: const Color(0xFF141418),
                      title: Text(
                        'CONFIRM PARTIAL REFUND',
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                      content: Text(
                        'Refund ${_selectedItemIds.length} selected item(s)? This will restore stock and adjust customer loyalty points.',
                        style: GoogleFonts.inter(color: Colors.white70),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text('CANCEL', style: GoogleFonts.manrope(color: Colors.white38)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                          child: const Text('PROCEED'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true && context.mounted) {
                    try {
                      final db = ref.read(databaseServiceProvider);
                      await db.refundItems(widget.transaction.id, _selectedItemIds.toList());

                      // Generate & Submit official ZRA Credit Note to DigiTax
                      final origSdcNo = widget.transaction.zraReceiptNumber ?? 'INV-${widget.transaction.id}';
                      final refundedItems = widget.transaction.items.where((i) => _selectedItemIds.contains(i.id)).toList();
                      
                      final refundTx = SaleTransaction(
                        totalAmount: refundedItems.fold(0.0, (s, i) => s + (i.priceAtSale * i.quantity)),
                        paymentMethod: widget.transaction.paymentMethod,
                        cashierName: widget.transaction.cashierName,
                        status: 'refunded',
                        isCreditNote: true,
                        orgInvoiceNo: origSdcNo,
                        creditNoteReason: 'Customer Returned Goods',
                        customerTpin: widget.transaction.customerTpin,
                        customerBusinessName: widget.transaction.customerBusinessName,
                      );
                      refundTx.items.addAll(refundedItems);

                      // Submit to DigiTax in background/online
                      try {
                        await ref.read(digitaxInventoryServiceProvider).submitCreditNoteToDigitax(
                          refundTx,
                          originalSdcInvoiceNo: origSdcNo,
                          reason: 'Customer Returned Goods',
                        );
                      } catch (_) {}

                      // Print ZRA Fiscal Credit Note
                      try {
                        final config = ref.read(storeConfigProvider).value;
                        await ref.read(printerServiceProvider).printReceipt(
                          refundTx,
                          refundedItems,
                          config: config,
                        );
                      } catch (_) {}
                      
                      if (context.mounted) {
                        Navigator.pop(context); // Close receipt modal
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('ZRA Credit Note & Refund processed successfully!'),
                            backgroundColor: Color(0xFF10B981),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Refund failed: $e')),
                        );
                      }
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRefundMode ? Colors.redAccent : Colors.redAccent.withValues(alpha: 0.1),
                  foregroundColor: _isRefundMode ? Colors.white : Colors.redAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.redAccent, width: _isRefundMode ? 0 : 1),
                  ),
                  elevation: 0,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _isRefundMode ? 'CONFIRM REFUND (${_selectedItemIds.length})' : 'REFUND',
                    maxLines: 1,
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
          const SizedBox(width: 8),
        ],
        Expanded(
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: (_isPrinting || isRefunded) ? null : () async {
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

                if (!authorized) return;

                setState(() => _isPrinting = true);
                try {
                  final selectedConfig = ref.read(selectedPrinterProvider);
                  final items = await ref.read(transactionItemsProvider(widget.transaction.id).future);
                  final config = ref.read(storeConfigProvider).value;

                  if (selectedConfig == null) {
                    // Fallback to desktop system printer / PDF layout dialog
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

                  // Refresh from DigiTax first if fiscal data has not yet arrived
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
                    // Fallback to desktop layoutPdf if POS printer connection failed
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
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                foregroundColor: isRefunded ? Colors.white24 : Colors.white,
                disabledBackgroundColor: Colors.white.withValues(alpha: 0.02),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: _isPrinting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isRefunded ? 'REPRINT BLOCKED' : 'REPRINT',
                        maxLines: 1,
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
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: isRefunded ? Colors.redAccent : const Color(0xFFC1F11D),
                foregroundColor: isRefunded ? Colors.white : Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'DONE',
                  maxLines: 1,
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
}

final transactionItemsProvider = FutureProvider.family<List<SaleItem>, int>((ref, id) async {
  final db = ref.watch(databaseServiceProvider);
  return db.getTransactionItems(id);
});
