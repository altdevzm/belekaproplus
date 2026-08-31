import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/services/local_sql_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

enum AdjustType {
  addStock,
  reduceStock,
}

class DigiTaxMovementType {
  final String name;
  final String zraCode;
  final String description;

  const DigiTaxMovementType({
    required this.name,
    required this.zraCode,
    required this.description,
  });
}

class StockAdjustmentModal extends ConsumerStatefulWidget {
  final Product product;
  final AdjustType initialAdjustType;

  const StockAdjustmentModal({
    super.key,
    required this.product,
    this.initialAdjustType = AdjustType.addStock,
  });

  @override
  ConsumerState<StockAdjustmentModal> createState() => _StockAdjustmentModalState();
}

// Backward compatibility alias
typedef AddStockModal = StockAdjustmentModal;

class _StockAdjustmentModalState extends ConsumerState<StockAdjustmentModal> {
  final _formKey = GlobalKey<FormState>();
  late AdjustType _adjustType;
  DigiTaxMovementType? _selectedMovementType;
  late TextEditingController _quantityController;
  late TextEditingController _notesController;
  bool _isProcessing = false;
  String? _movementTypeError;

  // Exact DigiTax Movement Types for "Add stock"
  static const List<DigiTaxMovementType> _addMovementTypes = [
    DigiTaxMovementType(name: 'Purchase', zraCode: '02', description: 'Incoming stock from vendor / supplier GRN'),
    DigiTaxMovementType(name: 'Import', zraCode: '03', description: 'Stock received from international import shipments'),
    DigiTaxMovementType(name: 'Stock Movement', zraCode: '03', description: 'Stock received from branch or store transfer'),
    DigiTaxMovementType(name: 'Processing', zraCode: '05', description: 'Finished goods produced / manufactured in-house'),
    DigiTaxMovementType(name: 'Adjustment', zraCode: '06', description: 'Physical audit count surplus / found stock reconciliation'),
    DigiTaxMovementType(name: 'Return', zraCode: '04', description: 'Customer returned items restocked to active inventory'),
  ];

  // Exact DigiTax Movement Types for "Reduce stock"
  static const List<DigiTaxMovementType> _reduceMovementTypes = [
    DigiTaxMovementType(name: 'Damage', zraCode: '11', description: 'Broken, spoiled, or damaged goods write-off'),
    DigiTaxMovementType(name: 'Expired', zraCode: '12', description: 'Perishable or expired inventory write-off'),
    DigiTaxMovementType(name: 'Theft', zraCode: '13', description: 'Stolen, pilfered, or unaccounted missing goods'),
    DigiTaxMovementType(name: 'Processing', zraCode: '14', description: 'Raw materials or items consumed for internal store use / production'),
    DigiTaxMovementType(name: 'Return', zraCode: '15', description: 'Defective or unwanted goods returned to supplier'),
    DigiTaxMovementType(name: 'Adjustment', zraCode: '16', description: 'Physical count discrepancy shortage / stock shrinkage'),
    DigiTaxMovementType(name: 'Stock Movement', zraCode: '04', description: 'Stock dispatched / transferred out to another branch'),
  ];

  int? _digitaxCloudStock;
  bool _isLoadingCloudStock = false;

  @override
  void initState() {
    super.initState();
    _adjustType = widget.initialAdjustType;
    _quantityController = TextEditingController();
    _notesController = TextEditingController();
    _fetchCloudStock();
  }

  Future<void> _fetchCloudStock() async {
    setState(() => _isLoadingCloudStock = true);
    try {
      final digitaxService = ref.read(digitaxInventoryServiceProvider);
      final remoteMap = await digitaxService.fetchRemoteStockMap();
      if (remoteMap.isNotEmpty) {
        final p = widget.product;
        Map<String, dynamic>? remoteItem;
        if (p.itemClsCd.isNotEmpty && remoteMap.containsKey(p.itemClsCd)) {
          remoteItem = remoteMap[p.itemClsCd];
        } else if (remoteMap.containsKey(p.name.trim().toLowerCase())) {
          remoteItem = remoteMap[p.name.trim().toLowerCase()];
        } else if (p.sku.isNotEmpty && remoteMap.containsKey(p.sku.trim())) {
          remoteItem = remoteMap[p.sku.trim()];
        }

        if (remoteItem != null && mounted) {
          setState(() {
            _digitaxCloudStock = (remoteItem?['stock'] as num?)?.toInt();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingCloudStock = false);
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _onAdjustTypeChanged(AdjustType newType) {
    setState(() {
      _adjustType = newType;
      _selectedMovementType = null;
      _movementTypeError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentStock = widget.product.stockLevel;
    final isAdd = _adjustType == AdjustType.addStock;
    final activeGreen = const Color(0xFF4ADE80); // DigiTax accent green

    // Live calculation for preview
    int qtyInput = int.tryParse(_quantityController.text.trim()) ?? 0;
    int afterStock = isAdd ? (currentStock + qtyInput) : (currentStock - qtyInput).clamp(0, 9999999);

    final availableTypes = isAdd ? _addMovementTypes : _reduceMovementTypes;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 480,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151F32) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Tab & Close Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Adjust stock',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: activeGreen,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 82,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: activeGreen,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurfaceVariant, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Product Name
                Text(
                  widget.product.name,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 18),

                // Adjust Type Dropdown / Selector
                Text(
                  'Adjust type',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: activeGreen.withValues(alpha: 0.6), width: 1.5),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AdjustType>(
                      value: _adjustType,
                      dropdownColor: const Color(0xFF1E1E24),
                      isExpanded: true,
                      icon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close, size: 14, color: Colors.white38),
                          const SizedBox(width: 6),
                          Container(width: 1, height: 14, color: Colors.white24),
                          const SizedBox(width: 6),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 20),
                        ],
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: AdjustType.addStock,
                          child: Text('Add stock', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                        DropdownMenuItem(
                          value: AdjustType.reduceStock,
                          child: Text('Reduce stock', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                        ),
                      ],
                      onChanged: (type) {
                        if (type != null) _onAdjustTypeChanged(type);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Movement Type Dropdown
                Text(
                  'Movement type',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _movementTypeError != null
                          ? Colors.redAccent
                          : (_selectedMovementType != null
                              ? activeGreen.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.15)),
                      width: 1.5,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<DigiTaxMovementType>(
                      value: _selectedMovementType,
                      dropdownColor: const Color(0xFF1E1E24),
                      isExpanded: true,
                      hint: Text(
                        'Select...',
                        style: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                      ),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54, size: 20),
                      items: availableTypes.map((mt) {
                        return DropdownMenuItem<DigiTaxMovementType>(
                          value: mt,
                          child: Row(
                            children: [
                              Text(
                                mt.name,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(ZRA ${mt.zraCode})',
                                style: GoogleFonts.ibmPlexMono(
                                  fontSize: 11,
                                  color: Colors.white38,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedMovementType = val;
                          _movementTypeError = null;
                        });
                      },
                    ),
                  ),
                ),
                if (_movementTypeError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _movementTypeError!,
                    style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 11),
                  ),
                ],
                const SizedBox(height: 18),

                // Quantity Input
                Text(
                  widget.product.isWeighted
                      ? 'Quantity (${widget.product.unitOfMeasure.toUpperCase()})*'
                      : 'Quantity*',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: TextFormField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: InputBorder.none,
                      hintText: widget.product.isWeighted ? 'e.g. 100 or 300' : 'Enter quantity',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                      suffixText: widget.product.isWeighted ? widget.product.unitOfMeasure.toUpperCase() : null,
                      suffixStyle: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Please enter a quantity';
                      final parsed = int.tryParse(v.trim());
                      if (parsed == null || parsed <= 0) return 'Please enter a valid positive quantity';
                      if (!isAdd && parsed > currentStock) {
                        return 'Cannot deduct more than current stock ($currentStock)';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Current Quantity & Cloud Stock Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.product.isWeighted
                          ? 'Current quantity: $currentStock ${widget.product.unitOfMeasure.toUpperCase()}'
                          : 'Current quantity: $currentStock',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    if (_isLoadingCloudStock)
                      Row(
                        children: [
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF60A5FA)),
                          ),
                          const SizedBox(width: 6),
                          Text('Checking Cloud...', style: GoogleFonts.inter(fontSize: 11, color: Colors.white38)),
                        ],
                      )
                    else if (_digitaxCloudStock != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _digitaxCloudStock == currentStock
                              ? const Color(0xFF4ADE80).withValues(alpha: 0.1)
                              : Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _digitaxCloudStock == currentStock
                                ? const Color(0xFF4ADE80).withValues(alpha: 0.3)
                                : Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _digitaxCloudStock == currentStock ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded,
                              size: 12,
                              color: _digitaxCloudStock == currentStock ? const Color(0xFF4ADE80) : Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.product.isWeighted
                                  ? 'DigiTax Cloud: $_digitaxCloudStock ${widget.product.unitOfMeasure.toUpperCase()}'
                                  : 'DigiTax Cloud: $_digitaxCloudStock',
                              style: GoogleFonts.ibmPlexMono(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _digitaxCloudStock == currentStock ? const Color(0xFF4ADE80) : Colors.amber,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2C322C), // Subtle grey-green pill box
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      widget.product.isWeighted
                          ? 'Quantity after adjustment $afterStock ${widget.product.unitOfMeasure.toUpperCase()}'
                          : 'Quantity after adjustment $afterStock',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                if (widget.product.isWeighted && qtyInput > 0) ...[
                  const SizedBox(height: 10),
                  Builder(
                    builder: (context) {
                      final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? r'$';
                      final costPerUnit = widget.product.unitCost;
                      final pricePerUnit = widget.product.price;
                      final batchCost = qtyInput * costPerUnit;
                      final batchRevenue = qtyInput * pricePerUnit;
                      final batchProfit = batchRevenue - batchCost;
                      final profitPerUnit = pricePerUnit - costPerUnit;

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFC1F11D).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Batch Valuation ($qtyInput ${widget.product.unitOfMeasure.toUpperCase()}):', style: const TextStyle(color: Color(0xFFC1F11D), fontSize: 11, fontWeight: FontWeight.bold)),
                                Text('Cost: $currency${costPerUnit.toStringAsFixed(2)} | Sell: $currency${pricePerUnit.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white60, fontSize: 10.5)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Batch Cost: $currency${batchCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                Text('Projected Sales: $currency${batchRevenue.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Expected Profit: +$currency${batchProfit.toStringAsFixed(2)} (+$currency${profitPerUnit.toStringAsFixed(2)} / ${widget.product.unitOfMeasure})',
                              style: const TextStyle(color: Color(0xFF4ADE80), fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 14),

                // Optional Notes
                Text(
                  'Remarks / Audit Reference (Optional)',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: TextFormField(
                    controller: _notesController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: isAdd ? 'e.g. PO-891 Supplier Delivery' : 'e.g. Broken packaging write-off',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Bottom Action Buttons: Cancel and Continue
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: activeGreen,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: activeGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                              )
                            : Text(
                                'Continue',
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
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

  Future<void> _submit() async {
    setState(() {
      _movementTypeError = _selectedMovementType == null ? 'Please select a movement type' : null;
    });

    if (!(_formKey.currentState?.validate() ?? false) || _selectedMovementType == null) {
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final db = ref.read(databaseServiceProvider);
      final localSql = ref.read(localSqlServiceProvider);
      final digitaxService = ref.read(digitaxInventoryServiceProvider);
      final currentUser = ref.read(authProvider);
      final isOwner = ref.read(isOwnerProvider);
      final storeConfig = ref.read(storeConfigProvider).value;

      final branchCode = (currentUser?.branchCode != null && currentUser!.branchCode!.isNotEmpty && currentUser.branchCode != '00')
          ? currentUser.branchCode!
          : ((storeConfig != null && storeConfig.bhfId.isNotEmpty && storeConfig.bhfId != '00')
              ? storeConfig.bhfId
              : (widget.product.branchCode.isNotEmpty ? widget.product.branchCode : (isOwner ? '00' : '01')));

      final int currentStock = widget.product.stockLevel;
      final int qtyInput = int.parse(_quantityController.text.trim());
      final isAdd = _adjustType == AdjustType.addStock;

      final actionType = isAdd ? 'ADD' : 'DEDUCT';
      final quantityChanged = qtyInput;
      final newStockLevel = isAdd ? (currentStock + qtyInput) : (currentStock - qtyInput).clamp(0, 9999999);
      final movementType = _selectedMovementType!.zraCode;
      final reasonCategory = _selectedMovementType!.name;
      final notes = _notesController.text.trim();
      final sarNo = 'SAR-$branchCode-${DateTime.now().millisecondsSinceEpoch}';

      // 1. Record stock movement locally in Isar
      final movement = await db.recordStockMovement(
        product: widget.product,
        actionType: actionType,
        movementType: movementType,
        quantityChanged: quantityChanged,
        newStockLevel: newStockLevel,
        reasonCategory: reasonCategory,
        reasonNotes: notes.isNotEmpty ? notes : null,
        userId: currentUser?.numericId ?? '1001',
        userName: currentUser?.name ?? 'Manager',
        branchCode: branchCode,
        branchName: storeConfig?.branchName ?? 'Main Store',
        isSyncedWithDigitax: false,
        digitaxSarNo: sarNo,
      );

      // 2. Cache in local SQLite table for offline durability
      try {
        await localSql.insert('stock_movements', {
          'product_id': widget.product.id,
          'product_name': widget.product.name,
          'sku': widget.product.sku,
          'branch_code': branchCode,
          'branch_name': storeConfig?.branchName ?? 'Main Store',
          'movement_type': movementType,
          'action_type': actionType,
          'previous_stock': currentStock,
          'quantity_changed': quantityChanged,
          'new_stock': newStockLevel,
          'unit_cost': widget.product.unitCost,
          'total_cost_impact': widget.product.unitCost * quantityChanged,
          'reason_category': reasonCategory,
          'reason_notes': notes.isNotEmpty ? notes : null,
          'user_id': currentUser?.numericId ?? '1001',
          'user_name': currentUser?.name ?? 'Manager',
          'is_synced_with_digitax': 0,
          'digitax_sar_no': sarNo,
          'timestamp': DateTime.now().toIso8601String(),
        });
      } catch (sqlErr) {
        debugPrint('SQLite stock_movements insert notice: $sqlErr');
      }

      // 3. Push real-time SAR adjustment directly to DigiTax Cloud API
      bool digitaxSynced = false;
      try {
        digitaxSynced = await digitaxService.pushStockMovementAdjustment(
          product: widget.product,
          action: actionType,
          movementType: movementType,
          quantity: quantityChanged,
          remarks: '$reasonCategory${notes.isNotEmpty ? " • $notes" : ""}',
          branchCode: branchCode,
        );

        if (digitaxSynced) {
          movement.isSyncedWithDigitax = true;
          await db.isar.writeTxn(() async {
            await db.isar.stockMovements.put(movement);
          });
        }
      } catch (e) {
        debugPrint('DigiTax stock adjustment push notice: $e');
      }

      if (mounted) {
        final actionText = isAdd ? 'added (+$quantityChanged)' : 'deducted (-$quantityChanged)';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(digitaxSynced ? Icons.cloud_done_rounded : Icons.check_circle_outline_rounded,
                    color: digitaxSynced ? const Color(0xFF4ADE80) : Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Stock $actionText • New: $newStockLevel • $reasonCategory (ZRA $movementType)${digitaxSynced ? " • Synced with DigiTax!" : ""}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF141418),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving adjustment: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}
