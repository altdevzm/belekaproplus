import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/screens/inventory/category_management_modal.dart';
import 'package:beleka_pos/screens/inventory/add_stock_modal.dart';

class ProductEditorModal extends ConsumerStatefulWidget {
  final Product? product;

  const ProductEditorModal({
    super.key,
    this.product,
  });

  @override
  ConsumerState<ProductEditorModal> createState() => _ProductEditorModalState();
}

class _ProductEditorModalState extends ConsumerState<ProductEditorModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _skuController;
  late TextEditingController _priceController;
  late TextEditingController _unitCostController;
  late TextEditingController _stockController;
  late TextEditingController _discountPriceController;
  late TextEditingController _discountDurationController;
  late TextEditingController _tareWeightController;
  late TextEditingController _scalePluController;
  late TextEditingController _taxRateController;
  bool _hasDiscount = false;
  bool _isTaxInclusive = true;
  bool _isWeighted = false;
  bool _isDigitaxSyncEnabled = true;
  String _unitOfMeasure = 'kg';
  int? _selectedCategoryId;
  String? _imagePath;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.product?.name ?? '');
    _skuController = TextEditingController(text: widget.product?.sku ?? '');
    _priceController = TextEditingController(text: widget.product?.price.toString() ?? '');
    _unitCostController = TextEditingController(text: widget.product?.unitCost.toString() ?? '');
    _stockController = TextEditingController(text: widget.product?.stockLevel.toString() ?? '');
    _discountPriceController = TextEditingController(text: widget.product?.discountPrice?.toString() ?? '');
    
    // Scale properties
    _isWeighted = widget.product?.isWeighted ?? false;
    _unitOfMeasure = widget.product?.unitOfMeasure ?? 'kg';
    _tareWeightController = TextEditingController(
      text: (widget.product?.tareWeight ?? 0.0) > 0 ? widget.product!.tareWeight.toString() : '',
    );
    _scalePluController = TextEditingController(text: widget.product?.scalePlu ?? '');

    // Calculate remaining days if editing
    int durationDays = 0;
    if (widget.product?.discountEndDate != null) {
      durationDays = widget.product!.discountEndDate!.difference(DateTime.now()).inDays;
      if (durationDays < 0) durationDays = 0;
    }
    _discountDurationController = TextEditingController(text: durationDays > 0 ? durationDays.toString() : '');
    _hasDiscount = widget.product?.discountPrice != null;
    
    _isTaxInclusive = widget.product?.isTaxInclusive ?? true;
    _isDigitaxSyncEnabled = widget.product?.isDigitaxSyncEnabled ?? true;
    _taxRateController = TextEditingController(
      text: (widget.product?.taxRate ?? 16.0).toStringAsFixed(1).replaceAll('.0', ''),
    );
    
    _selectedCategoryId = widget.product?.categoryId;
    _imagePath = widget.product?.imagePath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _priceController.dispose();
    _unitCostController.dispose();
    _stockController.dispose();
    _discountPriceController.dispose();
    _discountDurationController.dispose();
    _tareWeightController.dispose();
    _scalePluController.dispose();
    _taxRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final accentColor = primaryColor;
    final currencySymbol = ref.watch(storeConfigProvider).value?.currencySymbol ?? r'$';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 540,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151F32) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
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
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.inventory_2_rounded, size: 16, color: primaryColor),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          widget.product == null ? 'ADD NEW PRODUCT' : 'EDIT PRODUCT DETAILS',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildImagePicker(),
                const SizedBox(height: 24),
                _buildTextField(
                  controller: _nameController,
                  label: 'PRODUCT NAME',
                  hint: 'e.g. Ignite Pro Runner',
                  validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                  accentColor: accentColor,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _skuController,
                        label: 'SKU / BARCODE',
                        hint: 'PRO-RUN-01',
                        autofocus: widget.product == null,
                        validator: (v) => v?.isEmpty ?? true ? 'Required' : null,
                        accentColor: accentColor,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildCategoryDropdown(accentColor),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _unitCostController,
                        label: _isWeighted ? 'COST (PER ${_unitOfMeasure.toUpperCase()})' : 'COST PRICE',
                        hint: '0.00',
                        keyboardType: TextInputType.number,
                        prefix: currencySymbol,
                        accentColor: accentColor,
                        validator: (v) => (v != null && v.isNotEmpty && double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildTextField(
                        controller: _priceController,
                        label: _isWeighted ? 'PRICE (PER ${_unitOfMeasure.toUpperCase()})' : 'SELLING PRICE',
                        hint: '0.00',
                        keyboardType: TextInputType.number,
                        prefix: currencySymbol,
                        accentColor: accentColor,
                        validator: (v) => (v != null && double.tryParse(v) == null) ? 'Invalid' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _buildStockSection(accentColor),
                const SizedBox(height: 20),
                _buildDigitaxComplianceSection(accentColor),
                const SizedBox(height: 20),
                _buildScaleSection(accentColor),
                const SizedBox(height: 20),
                _buildTaxSection(accentColor),
                const SizedBox(height: 32),
                _buildDiscountSection(accentColor, currencySymbol),
                const SizedBox(height: 40),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: Text(
                      widget.product == null ? 'CREATE PRODUCT' : 'SAVE CHANGES',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRODUCT IMAGE',
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                image: (_imagePath != null && File(_imagePath!).existsSync())
                  ? DecorationImage(
                      image: FileImage(File(_imagePath!)),
                      fit: BoxFit.cover,
                    )
                  : null,
              ),
              child: (_imagePath == null || !File(_imagePath!).existsSync())
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, color: Colors.white.withValues(alpha: 0.2), size: 32),
                      const SizedBox(height: 8),
                      Text('UPLOAD', 
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white.withValues(alpha: 0.2))),
                    ],
                  )
                : Stack(
                    children: [
                      Positioned(
                        right: 8,
                        top: 8,
                        child: GestureDetector(
                          onTap: () => setState(() => _imagePath = null),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final String originalPath = result.files.single.path!;
      
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'product_${DateTime.now().millisecondsSinceEpoch}${path.extension(originalPath)}';
      final String imagesDirPath = path.join(directory.path, 'product_images');
      final String newPath = path.join(imagesDirPath, fileName);
      
      final imagesDir = Directory(imagesDirPath);
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }
      
      await File(originalPath).copy(newPath);
      setState(() => _imagePath = newPath);
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required Color accentColor,
    String? prefix,
    TextInputType? keyboardType,
    bool autofocus = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: Colors.white.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            autofocus: autofocus,
            validator: validator,
            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              prefixText: prefix,
              prefixStyle: GoogleFonts.inter(color: accentColor, fontWeight: FontWeight.bold),
              hintText: hint,
              hintStyle: GoogleFonts.inter(color: Colors.white10),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: InputBorder.none,
              errorStyle: const TextStyle(height: 0),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(Color accentColor) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'CATEGORY',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    final created = await showQuickCreateCategoryDialog(context, ref);
                    if (created != null && mounted) {
                      setState(() => _selectedCategoryId = created.id);
                    }
                  },
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, size: 12, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        'NEW',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: accentColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => showDialog(
                    context: context,
                    builder: (context) => const CategoryManagementModal(),
                  ),
                  child: Text(
                    'MANAGE',
                    style: GoogleFonts.inter(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.white.withValues(alpha: 0.4),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: categoriesAsync.when(
            data: (categories) {
              if (categories.isEmpty) {
                return InkWell(
                  onTap: () async {
                    final created = await showQuickCreateCategoryDialog(context, ref);
                    if (created != null && mounted) {
                      setState(() => _selectedCategoryId = created.id);
                    }
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '+ CREATE FIRST CATEGORY',
                        style: GoogleFonts.inter(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      Icon(Icons.add_rounded, color: accentColor, size: 18),
                    ],
                  ),
                );
              }

              if (_selectedCategoryId == null || !categories.any((c) => c.id == _selectedCategoryId)) {
                _selectedCategoryId = categories.first.id;
              }

              return DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _selectedCategoryId,
                  dropdownColor: const Color(0xFF141418),
                  isExpanded: true,
                  icon: const Icon(Icons.expand_more, color: Colors.white24),
                  items: categories.map((cat) {
                    return DropdownMenuItem<int>(
                      value: cat.id,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: _getSectorColor(cat.sector),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            cat.name.toUpperCase(),
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedCategoryId = val),
                ),
              );
            },
            loading: () => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            error: (_, _) => const Text('Error loading categories', style: TextStyle(color: Colors.red)),
          ),
        ),
      ],
    );
  }

  Color _getSectorColor(CategorySector sector) {
    switch (sector) {
      case CategorySector.pharmacy: return const Color(0xFF00D1FF);
      case CategorySector.stationery: return const Color(0xFFB565FF);
      case CategorySector.grocery: return const Color(0xFF00FF85);
      case CategorySector.food: return const Color(0xFFFF5C00);
      case CategorySector.restaurant: return const Color(0xFFF39C12);
      case CategorySector.other: return const Color(0xFFC1F11D);
    }
  }

  Widget _buildStockSection(Color accentColor) {
    final isEditing = widget.product != null;

    if (isEditing) {
      final currentStock = widget.product!.stockLevel;
      final unitLabel = _isWeighted ? _unitOfMeasure.toUpperCase() : 'UNITS';

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.lock_outline_rounded, color: Colors.amber, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Text(
                        'CURRENT STOCK LEVEL (LOCKED)',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Colors.white54,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ZRA / DigiTax Protected',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$currentStock $unitLabel',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Direct quantity edits are locked for ZRA audit compliance. Use the "Adjust" button to record additions or deductions with reason codes.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: Colors.white38,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await showDialog<bool>(
                  context: context,
                  builder: (context) => StockAdjustmentModal(
                    product: widget.product!,
                  ),
                );
              },
              icon: const Icon(Icons.tune_rounded, size: 14, color: Color(0xFF4ADE80)),
              label: Text('Adjust', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF4ADE80))),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF4ADE80), width: 1),
                backgroundColor: const Color(0xFF4ADE80).withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      );
    }

    return _buildTextField(
      controller: _stockController,
      label: _isWeighted ? 'INITIAL OPENING STOCK (${_unitOfMeasure.toUpperCase()})' : 'INITIAL OPENING STOCK (UNITS)',
      hint: '0',
      keyboardType: TextInputType.number,
      accentColor: accentColor,
      validator: (v) => int.tryParse(v ?? '') == null ? 'Please enter a valid initial stock' : null,
    );
  }

  Widget _buildScaleSection(Color accentColor) {
    final units = [
      {'id': 'kg', 'name': 'kg (Kilograms)'},
      {'id': 'g', 'name': 'g (Grams)'},
      {'id': 'lb', 'name': 'lb (Pounds)'},
      {'id': 'pcs', 'name': 'pcs (Pieces)'},
      {'id': 'ltr', 'name': 'ltr (Litres)'},
      {'id': 'unit', 'name': 'unit (Units)'},
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isWeighted ? const Color(0xFFC1F11D).withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isWeighted ? const Color(0xFFC1F11D).withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.scale_rounded,
                    color: _isWeighted ? const Color(0xFFC1F11D) : Colors.white38,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SOLD BY WEIGHT (SCALE ITEM)',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: _isWeighted ? Colors.white : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isWeighted
                            ? 'Requires weighing scale at checkout (Price per ${_unitOfMeasure.toUpperCase()})'
                            : 'Standard fixed-quantity product',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _isWeighted ? const Color(0xFFC1F11D) : Colors.white38,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: _isWeighted,
                onChanged: (v) => setState(() => _isWeighted = v),
                activeThumbColor: const Color(0xFFC1F11D),
              ),
            ],
          ),
          if (_isWeighted) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UNIT OF MEASURE',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: units.any((u) => u['id'] == _unitOfMeasure) ? _unitOfMeasure : units.first['id'],
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1A1A20),
                            items: units.map((u) {
                              return DropdownMenuItem<String>(
                                value: u['id'],
                                child: Text(
                                  u['name']!,
                                  style: GoogleFonts.inter(fontSize: 13, color: Colors.white),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _unitOfMeasure = val);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: _buildTextField(
                    controller: _tareWeightController,
                    label: 'TARE WEIGHT (${_unitOfMeasure.toUpperCase()})',
                    hint: '0.000',
                    keyboardType: TextInputType.number,
                    accentColor: accentColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildTextField(
              controller: _scalePluController,
              label: 'SCALE PLU / BARCODE CODE (OPTIONAL)',
              hint: 'e.g. 00123 (for embedded barcode scales)',
              accentColor: accentColor,
            ),
            Builder(
              builder: (context) {
                final currencySymbol = ref.watch(storeConfigProvider).value?.currencySymbol ?? r'$';
                final costPerUnit = double.tryParse(_unitCostController.text.trim()) ?? 0.0;
                final pricePerUnit = double.tryParse(_priceController.text.trim()) ?? 0.0;
                final stockQty = double.tryParse(_stockController.text.trim()) ?? (widget.product?.stockLevel.toDouble() ?? 100.0);
                final totalCost = stockQty * costPerUnit;
                final totalRevenue = stockQty * pricePerUnit;
                final projectedProfit = totalRevenue - totalCost;
                final profitPerUnit = pricePerUnit - costPerUnit;
                final markupPercent = costPerUnit > 0 ? ((pricePerUnit - costPerUnit) / costPerUnit * 100) : 0.0;

                return Container(
                  margin: const EdgeInsets.only(top: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFC1F11D).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.analytics_rounded, color: Color(0xFFC1F11D), size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'SCALE VALUATION & PROFIT PROJECTION',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFC1F11D),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Stock Batch Weight:', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                          Text('${stockQty.toStringAsFixed(0)} ${_unitOfMeasure.toUpperCase()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Unit Purchase Cost:', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                          Text('$currencySymbol${costPerUnit.toStringAsFixed(2)} / $_unitOfMeasure', style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Selling Price per ${_unitOfMeasure.toUpperCase()}:', style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                          Text('$currencySymbol${pricePerUnit.toStringAsFixed(2)} / $_unitOfMeasure', style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total Stock Cost (${stockQty.toStringAsFixed(0)} $_unitOfMeasure × $currencySymbol${costPerUnit.toStringAsFixed(2)}):', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          Text('$currencySymbol${totalCost.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total Sales Value (${stockQty.toStringAsFixed(0)} $_unitOfMeasure × $currencySymbol${pricePerUnit.toStringAsFixed(2)}):', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          Text('$currencySymbol${totalRevenue.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                      const Divider(color: Colors.white12, height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('PROJECTED PROFIT:', style: GoogleFonts.manrope(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                          Text(
                            '${projectedProfit >= 0 ? "+" : ""}$currencySymbol${projectedProfit.toStringAsFixed(2)} (${markupPercent.toStringAsFixed(1)}% markup)',
                            style: GoogleFonts.manrope(
                              color: projectedProfit >= 0 ? const Color(0xFFC1F11D) : Colors.redAccent,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Profit per $_unitOfMeasure: Selling at $currencySymbol${pricePerUnit.toStringAsFixed(2)} - cost $currencySymbol${costPerUnit.toStringAsFixed(2)} = +$currencySymbol${profitPerUnit.toStringAsFixed(2)} profit per 1 $_unitOfMeasure.',
                        style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white60, height: 1.3),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDigitaxComplianceSection(Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isDigitaxSyncEnabled
            ? const Color(0xFF10B981).withValues(alpha: 0.04)
            : Colors.blue.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isDigitaxSyncEnabled
              ? const Color(0xFF10B981).withValues(alpha: 0.25)
              : Colors.blue.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isDigitaxSyncEnabled ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                    color: _isDigitaxSyncEnabled ? const Color(0xFF10B981) : Colors.blueAccent,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DIGITAX & ZRA SMART INVOICE SYNC',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: _isDigitaxSyncEnabled ? Colors.white : Colors.blue.shade100,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isDigitaxSyncEnabled
                            ? 'Active in ZRA Smart Invoice • Cloud Synced'
                            : 'Offline-only product • Will NOT sync to DigiTax',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _isDigitaxSyncEnabled ? const Color(0xFF10B981) : Colors.blueAccent,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: _isDigitaxSyncEnabled,
                onChanged: (v) {
                  setState(() {
                    _isDigitaxSyncEnabled = v;
                    if (!v) {
                      _taxRateController.text = '0'; // Default untaxed for offline private items
                    } else {
                      _taxRateController.text = '16';
                    }
                  });
                },
                activeThumbColor: const Color(0xFF10B981),
                inactiveThumbColor: Colors.blueAccent,
              ),
            ],
          ),
          if (!_isDigitaxSyncEnabled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Private Offline Item: Stored locally only on this computer. Excluded from DigiTax cloud stock and ZRA fiscal sales payloads.',
                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTaxSection(Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isTaxInclusive ? accentColor.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isTaxInclusive ? accentColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _isTaxInclusive ? Icons.percent_rounded : Icons.money_off_csred_rounded,
                    color: _isTaxInclusive ? accentColor : Colors.white38,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TAX INCLUSIVE',
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isTaxInclusive
                            ? 'Price includes tax'
                            : 'Price is tax exclusive',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: _isTaxInclusive ? accentColor : Colors.white38,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Switch(
                value: _isTaxInclusive,
                onChanged: (v) => setState(() => _isTaxInclusive = v),
                activeThumbColor: accentColor,
              ),
            ],
          ),
          if (!_isDigitaxSyncEnabled) ...[
            const SizedBox(height: 16),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TAX RATE (%) - OFFLINE ITEM',
                        style: GoogleFonts.manrope(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: Colors.white54,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose 0% for untaxed or enter custom rate',
                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 110,
                  height: 42,
                  child: TextFormField(
                    controller: _taxRateController,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      suffixText: '%',
                      suffixStyle: const TextStyle(color: Colors.white60),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscountSection(Color accentColor, String currencySymbol) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _hasDiscount ? accentColor.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hasDiscount ? accentColor.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.label_important_outline, color: _hasDiscount ? accentColor : Colors.white24, size: 18),
                  const SizedBox(width: 12),
                  Text(
                    'PROMOTIONAL DISCOUNT',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: _hasDiscount ? Colors.white : Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                ],
              ),
              Switch(
                value: _hasDiscount,
                onChanged: (v) => setState(() => _hasDiscount = v),
                activeThumbColor: accentColor,
              ),
            ],
          ),
          if (_hasDiscount) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildTextField(
                    controller: _discountPriceController,
                    label: 'DISCOUNT PRICE',
                    hint: '0.00',
                    keyboardType: TextInputType.number,
                    prefix: currencySymbol,
                    accentColor: accentColor,
                    validator: (v) => (_hasDiscount && (v == null || double.tryParse(v) == null)) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildTextField(
                    controller: _discountDurationController,
                    label: 'DURATION (DAYS)',
                    hint: 'e.g. 2',
                    keyboardType: TextInputType.number,
                    accentColor: accentColor,
                    validator: (v) => (_hasDiscount && (v == null || int.tryParse(v) == null)) ? 'Required' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Price will automatically revert after this duration.',
              style: GoogleFonts.inter(fontSize: 10, fontStyle: FontStyle.italic, color: Colors.white24),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() ?? false) {
      final db = ref.read(databaseServiceProvider);
      final currentUser = ref.read(authProvider);
      final discountPrice = _hasDiscount ? double.tryParse(_discountPriceController.text) : null;
      final durationDays = _hasDiscount ? int.tryParse(_discountDurationController.text) : null;
      final tareWeight = double.tryParse(_tareWeightController.text.trim()) ?? 0.0;
      final scalePlu = _scalePluController.text.trim().isNotEmpty ? _scalePluController.text.trim() : null;
      
      final storeConfig = ref.read(storeConfigProvider).value;
      final isOwner = ref.read(isOwnerProvider);
      final branchBhfId = (currentUser?.branchCode != null && currentUser!.branchCode!.isNotEmpty && currentUser.branchCode != '00')
          ? currentUser.branchCode!
          : ((storeConfig != null && storeConfig.bhfId.isNotEmpty && storeConfig.bhfId != '00')
              ? storeConfig.bhfId
              : (isOwner ? '00' : '01'));
      final branchName = (storeConfig != null && storeConfig.branchName != null && storeConfig.branchName!.isNotEmpty)
          ? storeConfig.branchName!
          : (currentUser?.branchName ?? (isOwner ? 'Headquarters (HQ)' : 'Main Branch'));

      final initialStock = (widget.product != null)
          ? widget.product!.stockLevel
          : (int.tryParse(_stockController.text.trim()) ?? 0);

      final parsedTaxRate = double.tryParse(_taxRateController.text.trim()) ?? (_isTaxInclusive ? 16.0 : 0.0);
      final zraTaxCode = !_isDigitaxSyncEnabled ? 'EXEMPT' : (parsedTaxRate == 0 ? 'C' : 'A');

      final product = widget.product ?? Product(
        name: _nameController.text.trim(),
        sku: _skuController.text.trim(),
        price: double.parse(_priceController.text),
        stockLevel: initialStock,
        categoryId: _selectedCategoryId ?? 0,
        unitCost: double.tryParse(_unitCostController.text) ?? 0.0,
        imagePath: _imagePath,
        discountPrice: discountPrice,
        discountStartDate: _hasDiscount ? DateTime.now() : null,
        discountEndDate: (_hasDiscount && durationDays != null) ? DateTime.now().add(Duration(days: durationDays)) : null,
        isTaxInclusive: _isTaxInclusive,
        taxRate: parsedTaxRate,
        zraTaxCode: zraTaxCode,
        branchCode: branchBhfId,
        branchName: branchName,
        isSyncedWithDigitax: false,
        isDigitaxSyncEnabled: _isDigitaxSyncEnabled,
        lastDigitaxSyncDate: null,
        isWeighted: _isWeighted,
        unitOfMeasure: _unitOfMeasure,
        tareWeight: tareWeight,
        scalePlu: scalePlu,
      );
      
      final previousStock = widget.product?.stockLevel;

      if (widget.product != null) {
        product.name = _nameController.text.trim();
        product.sku = _skuController.text.trim();
        product.price = double.parse(_priceController.text);
        product.unitCost = double.tryParse(_unitCostController.text) ?? 0.0;
        product.stockLevel = widget.product!.stockLevel; // Stock quantity is locked in edit mode
        product.categoryId = _selectedCategoryId ?? 0;
        product.imagePath = _imagePath;
        product.discountPrice = discountPrice;
        product.discountStartDate = _hasDiscount ? (product.discountStartDate ?? DateTime.now()) : null;
        product.discountEndDate = (_hasDiscount && durationDays != null) ? DateTime.now().add(Duration(days: durationDays)) : null;
        product.isTaxInclusive = _isTaxInclusive;
        product.taxRate = parsedTaxRate;
        product.zraTaxCode = zraTaxCode;
        product.isDigitaxSyncEnabled = _isDigitaxSyncEnabled;
        product.branchCode = branchBhfId;
        product.branchName = branchName;
        product.isWeighted = _isWeighted;
        product.unitOfMeasure = _unitOfMeasure;
        product.tareWeight = tareWeight;
        product.scalePlu = scalePlu;
      }

      await db.saveProduct(product);

      final diff = (previousStock != null) ? (product.stockLevel - previousStock) : product.stockLevel;
      final movementType = previousStock == null ? '01' : (diff > 0 ? '06' : '16');

      // Record stock movement audit entry if stock changed
      if (previousStock == null && product.stockLevel > 0) {
        await db.recordStockMovement(
          product: product,
          actionType: 'ADD',
          movementType: '01',
          quantityChanged: product.stockLevel,
          newStockLevel: product.stockLevel,
          reasonCategory: 'Initial Inventory Opening',
          reasonNotes: 'New product registered in catalog',
          userId: currentUser?.numericId ?? '1001',
          userName: currentUser?.name ?? 'Manager',
          branchCode: branchBhfId,
          branchName: branchName,
          isSyncedWithDigitax: false,
        );
      } else if (previousStock != null && diff != 0) {
        await db.recordStockMovement(
          product: product,
          actionType: diff > 0 ? 'ADD' : 'DEDUCT',
          movementType: diff > 0 ? '06' : '16',
          quantityChanged: diff.abs(),
          newStockLevel: product.stockLevel,
          reasonCategory: diff > 0 ? 'Manual Inventory Adjustment In' : 'Manual Inventory Adjustment Out',
          reasonNotes: 'Adjusted in Product Editor',
          userId: currentUser?.numericId ?? '1001',
          userName: currentUser?.name ?? 'Manager',
          branchCode: branchBhfId,
          branchName: branchName,
          isSyncedWithDigitax: false,
        );
      }

      // Push product to DigiTax VSDC Cloud ONLY if enabled for DigiTax sync
      bool digitaxSynced = false;
      String? syncErr;
      if (product.isDigitaxSyncEnabled) {
        try {
          digitaxSynced = await ref.read(digitaxInventoryServiceProvider).syncSingleProductToDigitax(
            product,
            previousStock: previousStock,
            branchCode: branchBhfId,
            movementType: movementType,
            reasonNotes: 'Product Editor update',
          );
        } catch (e) {
          syncErr = e.toString();
          debugPrint('DigiTax product push notice: $e');
        }
      }

      if (mounted) {
        if (!product.isDigitaxSyncEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.shield_rounded, color: Colors.blueAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('${product.name} saved offline (Exempt from DigiTax/ZRA sync)'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E293B),
            ),
          );
        } else if (digitaxSynced) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${product.name} saved & registered with DigiTax!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        } else if (syncErr != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Product saved locally. DigiTax: $syncErr'),
              backgroundColor: const Color(0xFFF59E0B),
            ),
          );
        }
        Navigator.pop(context, true);
      }
    }
  }
}
