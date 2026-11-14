import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/product_exchange_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/widgets/manager_auth_dialog.dart';
import 'package:beleka_pos/utils/formatters.dart';
import 'package:beleka_pos/screens/dashboard_screen.dart';
import 'package:beleka_pos/screens/sales_screen.dart';
import 'package:beleka_pos/screens/terminals_screen.dart';
import 'package:beleka_pos/screens/reports_screen.dart';

class ProductExchangeModal extends ConsumerStatefulWidget {
  final SaleTransaction? initialInvoice;

  const ProductExchangeModal({super.key, this.initialInvoice});

  @override
  ConsumerState<ProductExchangeModal> createState() =>
      _ProductExchangeModalState();
}

class _ProductExchangeModalState extends ConsumerState<ProductExchangeModal> {
  final TextEditingController _invoiceSearchCtrl = TextEditingController();
  final TextEditingController _catalogueSearchCtrl = TextEditingController();
  final TextEditingController _customerNameCtrl = TextEditingController();
  final TextEditingController _customerPhoneCtrl = TextEditingController();
  final TextEditingController _customerTpinCtrl = TextEditingController();
  final TextEditingController _customReasonCtrl = TextEditingController();

  List<SaleTransaction> _invoiceSearchResults = [];
  bool _isSearchingInvoices = false;

  SaleTransaction? _selectedInvoice;
  List<ExchangeReturnLine> _returnLines = [];
  final List<ExchangeReplacementLine> _replacementLines = [];
  List<Product> _allProducts = [];
  bool _isLoadingInvoiceItems = false;
  bool _isSubmitting = false;

  static const List<String> _exchangeReasons = [
    'Wrong Size / Specification',
    'Product Defective / Faulty',
    'Customer Changed Mind',
    'Wrong Item Delivered',
    'Damaged Packaging',
    'Other',
  ];

  String _selectedReason = _exchangeReasons.first;
  String _settlementMode = 'CUSTOMER_CREDIT'; // 'CUSTOMER_CREDIT' or 'CASH_REFUND' when replacement < return
  String _paymentMethod = 'CASH'; // 'CASH', 'CARD / BANK', 'AIRTEL MONEY', 'MTN MONEY'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    _invoiceSearchCtrl.dispose();
    _catalogueSearchCtrl.dispose();
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _customerTpinCtrl.dispose();
    _customReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final db = ref.read(databaseServiceProvider);
    final products = await db.getAllProducts();
    if (!mounted) {
      return;
    }
    setState(() {
      _allProducts = products;
    });

    if (widget.initialInvoice != null) {
      await _selectInvoice(widget.initialInvoice!);
    } else {
      await _searchInvoices('');
    }
  }

  Future<void> _searchInvoices(String query) async {
    setState(() {
      _isSearchingInvoices = true;
    });
    try {
      final svc = ref.read(productExchangeServiceProvider);
      final list = await svc.searchEligibleSalesInvoices(query);
      if (mounted) {
        setState(() {
          _invoiceSearchResults = list;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingInvoices = false;
        });
      }
    }
  }

  Future<void> _selectInvoice(SaleTransaction invoice) async {
    setState(() {
      _selectedInvoice = invoice;
      _isLoadingInvoiceItems = true;
      _customerNameCtrl.text = invoice.customerBusinessName ?? '';
      _customerTpinCtrl.text = invoice.customerTpin ?? '';
    });

    try {
      final svc = ref.read(productExchangeServiceProvider);
      final lines = await svc.buildReturnLinesForInvoice(invoice);
      if (invoice.customerId != null) {
        final cust = await ref
            .read(databaseServiceProvider)
            .getCustomerById(invoice.customerId!);
        if (cust != null && mounted) {
          if (_customerNameCtrl.text.trim().isEmpty) {
            _customerNameCtrl.text = cust.name;
          }
          _customerPhoneCtrl.text = cust.phoneNumber;
        }
      }
      if (mounted) {
        setState(() {
          _returnLines = lines;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingInvoiceItems = false;
        });
      }
    }
  }

  void _updateReturnQty(int index, int delta) {
    final line = _returnLines[index];
    final nextQty = (line.returnQuantity + delta).clamp(
      0,
      line.maxReturnableQty,
    );
    if (nextQty != line.returnQuantity) {
      HapticFeedback.selectionClick();
      setState(() {
        _returnLines[index] = line.copyWith(returnQuantity: nextQty);
      });
    }
  }

  void _updateReturnCondition(int index, ReturnedItemCondition condition) {
    setState(() {
      _returnLines[index] = _returnLines[index].copyWith(condition: condition);
    });
  }

  void _addReplacementProduct(Product product) {
    HapticFeedback.lightImpact();
    setState(() {
      final existingIdx = _replacementLines.indexWhere(
        (l) => l.product.id == product.id,
      );
      if (existingIdx >= 0) {
        final existing = _replacementLines[existingIdx];
        if (existing.quantity < product.stockLevel || product.stockLevel <= 0) {
          _replacementLines[existingIdx] = existing.copyWith(
            quantity: existing.quantity + 1,
          );
        }
      } else {
        _replacementLines.add(
          ExchangeReplacementLine(
            product: product,
            quantity: 1,
            unitPrice: product.price,
          ),
        );
      }
    });
  }

  void _updateReplacementQty(int index, int delta) {
    final line = _replacementLines[index];
    final nextQty = line.quantity + delta;
    HapticFeedback.selectionClick();
    setState(() {
      if (nextQty <= 0) {
        _replacementLines.removeAt(index);
      } else {
        _replacementLines[index] = line.copyWith(quantity: nextQty);
      }
    });
  }

  /// Manager-authorized discount or price adjustment on a replacement item (Rule C)
  Future<void> _authorizeReplacementDiscountOrPrice(int index) async {
    final activeBranchCode =
        ref.read(authProvider)?.branchCode ??
        ref.read(storeConfigProvider).value?.bhfId;
    final approver = await ManagerAuthDialog.ensureBranchAuthorized(
      context: context,
      ref: ref,
      title: 'PRICE / DISCOUNT OVERRIDE',
      message:
          'HQ requires Owner PIN. Sub-branches require the assigned Branch Manager PIN.',
      branchCode: activeBranchCode,
    );
    if (approver == null || !mounted) {
      return;
    }

    final line = _replacementLines[index];
    final priceCtrl = TextEditingController(
      text: line.unitPrice.toStringAsFixed(2),
    );
    final discountCtrl = TextEditingController(
      text: line.discountAmount.toStringAsFixed(2),
    );

    final updated = await showDialog<ExchangeReplacementLine>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151F32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'ADJUST REPLACEMENT LINE (${line.product.name})',
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Authorized Unit Price',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: discountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Line Discount Amount',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final newPrice =
                  double.tryParse(priceCtrl.text.trim()) ?? line.unitPrice;
              final newDisc =
                  double.tryParse(discountCtrl.text.trim()) ?? 0.0;
              Navigator.pop(
                ctx,
                line.copyWith(
                  unitPrice: newPrice > 0 ? newPrice : line.unitPrice,
                  discountAmount: newDisc >= 0 ? newDisc : 0.0,
                ),
              );
            },
            child: const Text('APPLY'),
          ),
        ],
      ),
    );

    if (updated != null && mounted) {
      setState(() {
        _replacementLines[index] = updated;
      });
    }
  }

  double get _totalReturnedValue => double.parse(
    _returnLines.fold(0.0, (s, l) => s + l.lineTotal).toStringAsFixed(2),
  );

  double get _totalReplacementValue => double.parse(
    _replacementLines.fold(0.0, (s, l) => s + l.lineTotal).toStringAsFixed(2),
  );

  double get _differenceAmount => double.parse(
    (_totalReplacementValue - _totalReturnedValue).toStringAsFixed(2),
  );

  Future<void> _submitExchange() async {
    if (_selectedInvoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an original sales invoice first.'),
        ),
      );
      return;
    }

    final activeReturns = _returnLines
        .where((l) => l.returnQuantity > 0)
        .toList();
    if (activeReturns.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please specify at least 1 returned item quantity from the original invoice.',
          ),
        ),
      );
      return;
    }

    if (_replacementLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select at least 1 replacement product from the catalogue.',
          ),
        ),
      );
      return;
    }

    final finalReason = _selectedReason == 'Other'
        ? _customReasonCtrl.text.trim()
        : _selectedReason;
    if (finalReason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the reason for exchange.')),
      );
      return;
    }

    // If retaining customer credit, ensure customer name is provided
    final diff = _differenceAmount;
    if (diff < -0.009 &&
        _settlementMode == 'CUSTOMER_CREDIT' &&
        _customerNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter the Customer Name and Phone to retain Customer Credit.',
          ),
        ),
      );
      return;
    }

    // Branch-Aware Approval Check (Section C: HQ requires Owner PIN; Sub-Branches require assigned Branch Manager PIN)
    final currentUser = ref.read(authProvider);
    final activeBranchCode =
        currentUser?.branchCode ??
        ref.read(storeConfigProvider).value?.bhfId;
    final approver = await ManagerAuthDialog.ensureBranchAuthorized(
      context: context,
      ref: ref,
      title: 'EXCHANGE APPROVAL',
      message:
          'HQ exchanges require Owner PIN. Sub-branch exchanges require the assigned Branch Manager PIN.',
      branchCode: activeBranchCode,
    );
    if (approver == null || !mounted) {
      return;
    }

    final approverRoleTag =
        (approver.role.toLowerCase() == 'owner' ||
            approver.role.toLowerCase() == 'admin' ||
            approver.role.toLowerCase() == 'super_admin')
        ? 'OWNER'
        : 'BRANCH MANAGER';
    final approverLabel = '${approver.name} ($approverRoleTag)';

    setState(() {
      _isSubmitting = true;
    });

    try {
      final svc = ref.read(productExchangeServiceProvider);
      final String effectiveSettlement;
      final String effectivePaymentMethod;
      if (diff > 0.009) {
        effectiveSettlement = 'ADDITIONAL_PAYMENT';
        effectivePaymentMethod = _paymentMethod;
      } else if (diff < -0.009) {
        effectiveSettlement = _settlementMode;
        effectivePaymentMethod = _settlementMode == 'CUSTOMER_CREDIT'
            ? 'CUSTOMER CREDIT'
            : _paymentMethod;
      } else {
        effectiveSettlement = 'EVEN_EXCHANGE';
        effectivePaymentMethod = 'EVEN EXCHANGE';
      }

      final record = await svc.processProductExchange(
        originalInvoice: _selectedInvoice!,
        returnedLines: _returnLines,
        replacementLines: _replacementLines,
        reason: finalReason,
        settlementMode: effectiveSettlement,
        paymentMethod: effectivePaymentMethod,
        cashierName: currentUser?.name ?? 'Cashier',
        cashierId: currentUser?.numericId,
        approvingManagerName: approverLabel,
        approvingManagerId: approver.numericId,
        customerName: _customerNameCtrl.text.trim(),
        customerPhone: _customerPhoneCtrl.text.trim(),
        customerTpin: _customerTpinCtrl.text.trim(),
      );

      // Invalidate providers so Sales, Inventory, Reports, and Shifts refresh live
      ref.invalidate(productsProvider);
      ref.invalidate(recentTransactionsProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(cashierDashboardStatsProvider);
      ref.invalidate(activeShiftProvider);
      ref.invalidate(activeShiftsListProvider);
      ref.invalidate(paymentAccountsProvider);
      ref.invalidate(refundsProvider);
      ref.invalidate(reportTransactionsProvider);
      ref.invalidate(exchangeReportProvider);

      if (!mounted) {
        return;
      }
      final navigatorContext = Navigator.of(context).context;
      Navigator.pop(context, record);

      if (!navigatorContext.mounted) {
        return;
      }
      await showDialog<void>(
        context: navigatorContext,
        builder: (ctx) => ExchangeReceiptDialog(record: record),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exchange failed: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final panelBg = isDark ? const Color(0xFF151F32) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF293548)
        : const Color(0xFFE2E8F0);
    final currency =
        ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: (size.width * 0.94).clamp(680.0, 1240.0),
        height: (size.height * 0.90).clamp(540.0, 860.0),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 36,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildTopBar(context, borderColor),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // LEFT PANEL: Original Invoice & Returned Products
                  Expanded(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(right: BorderSide(color: borderColor)),
                      ),
                      child: _buildLeftReturnPanel(
                        context,
                        panelBg,
                        borderColor,
                        currency,
                      ),
                    ),
                  ),

                  // RIGHT PANEL: Replacement Catalogue & Financial Settlement
                  Expanded(
                    flex: 6,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      child: _buildRightReplacementPanel(
                        context,
                        panelBg,
                        borderColor,
                        currency,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, Color borderColor) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF1D4ED8).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.swap_horiz_rounded,
                  color: Color(0xFF3B82F6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRODUCT EXCHANGE MANAGEMENT',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    'Linked Credit Note + Replacement Sale • Condition Assessment • ZRA Compliant',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftReturnPanel(
    BuildContext context,
    Color panelBg,
    Color borderColor,
    String currency,
  ) {
    final theme = Theme.of(context);
    final df = DateFormat('dd MMM yyyy • HH:mm');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Step 1 Header: Original Invoice Selection
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '1. ORIGINAL SALES INVOICE & RETURN ITEMS',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF3B82F6),
                letterSpacing: 0.8,
              ),
            ),
            if (_selectedInvoice != null && widget.initialInvoice == null)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedInvoice = null;
                    _returnLines = [];
                  });
                  _searchInvoices(_invoiceSearchCtrl.text);
                },
                icon: const Icon(Icons.search_rounded, size: 14),
                label: Text(
                  'CHANGE INVOICE',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (_selectedInvoice == null) ...[
          TextField(
            controller: _invoiceSearchCtrl,
            onChanged: _searchInvoices,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: theme.colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              hintText:
                  'Search Invoice # (e.g. 000012), ZRA Receipt #, Customer or Cashier...',
              prefixIcon: const Icon(Icons.receipt_long_rounded, size: 18),
              filled: true,
              fillColor: panelBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: borderColor),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isSearchingInvoices
                ? const Center(child: CircularProgressIndicator())
                : _invoiceSearchResults.isEmpty
                ? Center(
                    child: Text(
                      'No matching sales invoices found.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _invoiceSearchResults.length,
                    itemBuilder: (ctx, i) {
                      final inv = _invoiceSearchResults[i];
                      final invNo =
                          '#${inv.id.toString().padLeft(6, '0')}';
                      return Card(
                        color: panelBg,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: borderColor),
                        ),
                        child: ListTile(
                          onTap: () => _selectInvoice(inv),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Invoice $invNo',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                CurrencyFormatter.format(
                                  inv.totalAmount,
                                  currency,
                                ),
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: const Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${df.format(inv.timestamp)} • ${inv.paymentMethod} • Cashier: ${inv.cashierName}'
                              '${inv.zraReceiptNumber != null ? " • ZRA: ${inv.zraReceiptNumber}" : ""}',
                              style: GoogleFonts.inter(fontSize: 11),
                            ),
                          ),
                          trailing: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ] else ...[
          // Selected Invoice Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ORIGINAL INVOICE #${_selectedInvoice!.id.toString().padLeft(6, '0')}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${df.format(_selectedInvoice!.timestamp)} • Paid via ${_selectedInvoice!.paymentMethod}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Text(
                  CurrencyFormatter.format(
                    _selectedInvoice!.totalAmount,
                    currency,
                  ),
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Returnable Items List with Quantity Stepper & Condition Assessment
          Expanded(
            child: _isLoadingInvoiceItems
                ? const Center(child: CircularProgressIndicator())
                : _returnLines.isEmpty
                ? Center(
                    child: Text(
                      'No items found on this invoice.',
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _returnLines.length,
                    itemBuilder: (ctx, idx) {
                      final line = _returnLines[idx];
                      final isSelected = line.returnQuantity > 0;
                      final canReturn = line.maxReturnableQty > 0;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1D4ED8).withValues(alpha: 0.10)
                              : panelBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF3B82F6)
                                : borderColor,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        line.productName,
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      Text(
                                        'Purchased: ${line.originalPurchasedQty} • Already Returned: ${line.alreadyReturnedOrExchangedQty} • Max Returnable: ${line.maxReturnableQty}',
                                        style: GoogleFonts.inter(
                                          fontSize: 10.5,
                                          color: theme
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                      Text(
                                        'Price at Sale: ${CurrencyFormatter.format(line.effectiveUnitPrice, currency)}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF3B82F6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (!canReturn)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'ALREADY RETURNED',
                                      style: GoogleFonts.inter(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.redAccent,
                                      ),
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      IconButton(
                                        onPressed: line.returnQuantity > 0
                                            ? () => _updateReturnQty(idx, -1)
                                            : null,
                                        icon: const Icon(
                                          Icons.remove_circle_outline_rounded,
                                          size: 20,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                      Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 28,
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${line.returnQuantity}',
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed:
                                            line.returnQuantity <
                                                line.maxReturnableQty
                                            ? () => _updateReturnQty(idx, 1)
                                            : null,
                                        icon: const Icon(
                                          Icons.add_circle_outline_rounded,
                                          size: 20,
                                        ),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            if (isSelected) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<
                                      ReturnedItemCondition
                                    >(
                                      initialValue: line.condition,
                                      isDense: true,
                                      decoration: InputDecoration(
                                        labelText: 'Condition Assessment',
                                        labelStyle: GoogleFonts.inter(
                                          fontSize: 10.5,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      items: ReturnedItemCondition.values
                                          .map(
                                            (c) => DropdownMenuItem(
                                              value: c,
                                              child: Text(
                                                c.label,
                                                style: GoogleFonts.inter(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          _updateReturnCondition(idx, val);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Return Value: ${CurrencyFormatter.format(line.lineTotal, currency)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFD97706),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
          ),

          const SizedBox(height: 8),
          // Reason for Exchange & Customer Details
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedReason,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Reason for Exchange *',
                    labelStyle: GoogleFonts.inter(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: _exchangeReasons
                      .map(
                        (r) => DropdownMenuItem(
                          value: r,
                          child: Text(
                            r,
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedReason = val;
                      });
                    }
                  },
                ),
                if (_selectedReason == 'Other') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _customReasonCtrl,
                    style: GoogleFonts.inter(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Specify exchange reason...',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customerNameCtrl,
                        style: GoogleFonts.inter(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Customer Name',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _customerPhoneCtrl,
                        style: GoogleFonts.inter(fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Customer Phone',
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRightReplacementPanel(
    BuildContext context,
    Color panelBg,
    Color borderColor,
    String currency,
  ) {
    final theme = Theme.of(context);
    final q = _catalogueSearchCtrl.text.trim().toLowerCase();
    final filteredCatalogue = _allProducts.where((p) {
      if (q.isEmpty) {
        return true;
      }
      return p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
    }).take(30).toList();

    final diff = _differenceAmount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '2. SELECT REPLACEMENT PRODUCTS FROM CATALOGUE',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF059669),
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _catalogueSearchCtrl,
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.inter(fontSize: 12.5),
          decoration: InputDecoration(
            hintText: 'Search replacement product by name or SKU...',
            prefixIcon: const Icon(Icons.inventory_2_outlined, size: 18),
            filled: true,
            fillColor: panelBg,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Compact Catalogue Picker
        SizedBox(
          height: 150,
          child: Container(
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor),
            ),
            child: ListView.separated(
              padding: const EdgeInsets.all(6),
              itemCount: filteredCatalogue.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: borderColor),
              itemBuilder: (ctx, i) {
                final prod = filteredCatalogue[i];
                return InkWell(
                  onTap: () => _addReplacementProduct(prod),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                prod.name,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'SKU: ${prod.sku} • Stock: ${prod.stockLevel}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Text(
                              CurrencyFormatter.format(prod.price, currency),
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF059669),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.add_circle_rounded,
                              color: Color(0xFF059669),
                              size: 18,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Selected Replacement Products List
        Text(
          'SELECTED REPLACEMENT ITEMS (${_replacementLines.length})',
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _replacementLines.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: panelBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: borderColor),
                  ),
                  child: Center(
                    child: Text(
                      'Tap any product above to add it as a replacement item.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _replacementLines.length,
                  itemBuilder: (ctx, idx) {
                    final rep = _replacementLines[idx];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: panelBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  rep.product.name,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  '${CurrencyFormatter.format(rep.unitPrice, currency)} × ${rep.quantity}'
                                  '${rep.discountAmount > 0 ? " (-${CurrencyFormatter.format(rep.discountAmount, currency)} disc)" : ""}',
                                  style: GoogleFonts.inter(
                                    fontSize: 10.5,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Tooltip(
                            message: 'Manager Price / Discount Override',
                            child: IconButton(
                              onPressed: () =>
                                  _authorizeReplacementDiscountOrPrice(idx),
                              icon: const Icon(
                                Icons.lock_person_outlined,
                                size: 17,
                                color: Color(0xFFD97706),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _updateReplacementQty(idx, -1),
                            icon: const Icon(
                              Icons.remove_circle_outline_rounded,
                              size: 19,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          Text(
                            '${rep.quantity}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          IconButton(
                            onPressed: () => _updateReplacementQty(idx, 1),
                            icon: const Icon(
                              Icons.add_circle_outline_rounded,
                              size: 19,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            CurrencyFormatter.format(rep.lineTotal, currency),
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 8),

        // Financial Difference & Settlement Box (Scenarios 1, 2, 3)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panelBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: diff > 0.009
                  ? const Color(0xFF3B82F6)
                  : (diff < -0.009
                        ? const Color(0xFFD97706)
                        : const Color(0xFF059669)),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Returned Product Value (Credit Note):',
                    style: GoogleFonts.inter(fontSize: 11.5),
                  ),
                  Text(
                    CurrencyFormatter.format(_totalReturnedValue, currency),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Replacement Product Value (New Sale):',
                    style: GoogleFonts.inter(fontSize: 11.5),
                  ),
                  Text(
                    CurrencyFormatter.format(_totalReplacementValue, currency),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
              const Divider(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    diff > 0.009
                        ? 'SCENARIO 1: CUSTOMER PAYS ADDITIONAL'
                        : (diff < -0.009
                              ? 'SCENARIO 2: REFUNDABLE / CUSTOMER CREDIT'
                              : 'SCENARIO 3: EQUAL VALUE (NO PAYMENT DUE)'),
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: diff > 0.009
                          ? const Color(0xFF3B82F6)
                          : (diff < -0.009
                                ? const Color(0xFFD97706)
                                : const Color(0xFF059669)),
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(diff.abs(), currency),
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: diff > 0.009
                          ? const Color(0xFF3B82F6)
                          : (diff < -0.009
                                ? const Color(0xFFD97706)
                                : const Color(0xFF059669)),
                    ),
                  ),
                ],
              ),

              if (diff < -0.009) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: Text(
                          'Retain as Customer Credit',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        selected: _settlementMode == 'CUSTOMER_CREDIT',
                        onSelected: (_) => setState(
                          () => _settlementMode = 'CUSTOMER_CREDIT',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: Text(
                          'Refund Difference Now',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        selected: _settlementMode == 'CASH_REFUND',
                        onSelected: (_) =>
                            setState(() => _settlementMode = 'CASH_REFUND'),
                      ),
                    ),
                  ],
                ),
              ],

              if (diff > 0.009 ||
                  (diff < -0.009 && _settlementMode == 'CASH_REFUND')) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: diff > 0.009
                        ? 'Payment Method for Additional Amount'
                        : 'Refund Payout Method',
                    labelStyle: GoogleFonts.inter(fontSize: 11),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'CASH', child: Text('CASH')),
                    DropdownMenuItem(
                      value: 'CARD / BANK',
                      child: Text('CARD / BANK'),
                    ),
                    DropdownMenuItem(
                      value: 'AIRTEL MONEY',
                      child: Text('AIRTEL MONEY'),
                    ),
                    DropdownMenuItem(
                      value: 'MTN MONEY',
                      child: Text('MTN MONEY'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _paymentMethod = val);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _submitExchange,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified_rounded, size: 18),
            label: Text(
              _isSubmitting
                  ? 'PROCESSING EXCHANGE...'
                  : 'AUTHORIZE & COMPLETE PRODUCT EXCHANGE',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog displaying the generated Exchange Receipt with Print / PDF export buttons (Section E)
class ExchangeReceiptDialog extends ConsumerWidget {
  final ProductExchangeRecord record;

  const ExchangeReceiptDialog({super.key, required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency =
        ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final df = DateFormat('dd MMM yyyy • HH:mm');

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF10B981),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'EXCHANGE RECEIPT',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              _metaRow('Exchange No:', record.exchangeNumber),
              _metaRow('Original Invoice:', record.originalInvoiceNo),
              if (record.creditNoteSaleId != null)
                _metaRow(
                  'ZRA Credit Note:',
                  record.zraCreditNoteReceiptNo?.isNotEmpty == true
                      ? '${record.zraCreditNoteReceiptNo} (CN-#${record.creditNoteSaleId.toString().padLeft(6, '0')})'
                      : 'CN-#${record.creditNoteSaleId.toString().padLeft(6, '0')}',
                ),
              if (record.replacementSaleId != null)
                _metaRow(
                  'ZRA New Sale:',
                  record.zraReplacementReceiptNo?.isNotEmpty == true
                      ? '${record.zraReplacementReceiptNo} (INV-#${record.replacementSaleId.toString().padLeft(6, '0')})'
                      : 'INV-#${record.replacementSaleId.toString().padLeft(6, '0')}',
                ),
              _metaRow(
                'DigiTax Fiscal Status:',
                record.digitaxSynced
                    ? '✓ SYNCED TO ZRA DIGITAX'
                    : 'QUEUED FOR DIGITAX SYNC',
              ),
              _metaRow('Customer:', record.customerName),
              if (record.customerPhone.isNotEmpty)
                _metaRow('Customer Phone:', record.customerPhone),
              _metaRow('Reason:', record.reason),
              _metaRow('Cashier:', record.cashierName),
              _metaRow('Approving Manager:', record.approvingManagerName),
              _metaRow('Date & Time:', df.format(record.createdAt)),
              const Divider(color: Colors.white12, height: 18),
              Text(
                'RETURNED PRODUCTS',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFD97706),
                ),
              ),
              const SizedBox(height: 4),
              ...record.returnedItems.map(
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${i['quantity']}x ${i['product_name']} [${i['condition_status']}]',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      Text(
                        '-${CurrencyFormatter.format((i['line_total'] as num?)?.toDouble() ?? 0.0, currency)}',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'REPLACEMENT PRODUCTS',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 4),
              ...record.replacementItems.map(
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${i['quantity']}x ${i['product_name']}',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      Text(
                        CurrencyFormatter.format(
                          (i['line_total'] as num?)?.toDouble() ?? 0.0,
                          currency,
                        ),
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(color: Colors.white12, height: 18),
              _metaRow(
                'Returned Product Value:',
                CurrencyFormatter.format(record.returnedValue, currency),
              ),
              _metaRow(
                'Replacement Product Value:',
                CurrencyFormatter.format(record.replacementValue, currency),
              ),
              _metaRow(
                record.differenceAmount > 0.009
                    ? 'Additional Paid (${record.paymentMethod}):'
                    : (record.differenceAmount < -0.009
                          ? (record.settlementMode == 'CUSTOMER_CREDIT'
                                ? 'Retained Customer Credit:'
                                : 'Refunded (${record.paymentMethod}):')
                          : 'Difference (Equal Value):'),
                CurrencyFormatter.format(
                  record.differenceAmount.abs(),
                  currency,
                ),
              ),
              const SizedBox(height: 16),
              if (record.creditNoteSaleId != null) ...[
                SizedBox(
                  height: 38,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final db = ref.read(databaseServiceProvider);
                      final cnTx = await db.isar.saleTransactions.get(
                        record.creditNoteSaleId!,
                      );
                      if (cnTx != null) {
                        final cnItems = await db.getTransactionItems(cnTx.id);
                        final config = ref.read(storeConfigProvider).value;
                        await ref
                            .read(printerServiceProvider)
                            .printReceipt(cnTx, cnItems, config: config);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD97706),
                      side: const BorderSide(color: Color(0xFFD97706)),
                    ),
                    icon: const Icon(Icons.receipt_long_rounded, size: 15),
                    label: Text(
                      'PRINT ZRA CREDIT NOTE (RETURNED ITEM)',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('CLOSE'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(productExchangeServiceProvider)
                            .printOrExportExchangeReceipt(record);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D4ED8),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.print_rounded, size: 16),
                      label: const Text('PRINT EXCHANGE RECEIPT'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white54),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

