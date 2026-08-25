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
import 'package:beleka_pos/providers/theme_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/screens/inventory/category_management_modal.dart';

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
  bool _hasDiscount = false;
  bool _isTaxInclusive = true;
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
    
    // Calculate remaining days if editing
    int durationDays = 0;
    if (widget.product?.discountEndDate != null) {
      durationDays = widget.product!.discountEndDate!.difference(DateTime.now()).inDays;
      if (durationDays < 0) durationDays = 0;
    }
    _discountDurationController = TextEditingController(text: durationDays > 0 ? durationDays.toString() : '');
    _hasDiscount = widget.product?.discountPrice != null;
    
    _isTaxInclusive = widget.product?.isTaxInclusive ?? true;
    
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(accentColorProvider);
    final currencySymbol = ref.watch(storeConfigProvider).value?.currencySymbol ?? r'$';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 500,
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
                    Text(
                      widget.product == null ? 'ADD PRODUCT' : 'EDIT PRODUCT',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2,
                        color: accentColor,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.3)),
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
                        label: 'COST PRICE',
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
                        label: 'SELLING PRICE',
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
                _buildTextField(
                  controller: _stockController,
                  label: 'INITIAL STOCK',
                  hint: '0',
                  keyboardType: TextInputType.number,
                  accentColor: accentColor,
                  validator: (v) => int.tryParse(v ?? '') == null ? 'Invalid' : null,
                ),
                const SizedBox(height: 20),
                _buildTaxSection(accentColor),
                const SizedBox(height: 32),
                _buildDiscountSection(accentColor, currencySymbol),
                const SizedBox(height: 40),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: Text(
                      widget.product == null ? 'CREATE PRODUCT' : 'SAVE CHANGES',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 1,
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
  Widget _buildTaxSection(Color accentColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _isTaxInclusive ? accentColor.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _isTaxInclusive ? accentColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                _isTaxInclusive ? Icons.cloud_done_rounded : Icons.inventory_2_outlined,
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
                        ? 'Tax Inclusive • Syncs to DigiTax cloud'
                        : 'Tax Exclusive • Local stock only (won\'t sync)',
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
      
      final storeConfig = ref.read(storeConfigProvider).value;
      final branchBhfId = (storeConfig != null && storeConfig.bhfId.isNotEmpty) 
          ? storeConfig.bhfId 
          : (currentUser?.branchCode ?? '00');
      final branchName = (storeConfig != null && storeConfig.branchName != null && storeConfig.branchName!.isNotEmpty)
          ? storeConfig.branchName!
          : (currentUser?.branchName ?? 'Main Branch');

      final product = widget.product ?? Product(
        name: _nameController.text,
        sku: _skuController.text,
        price: double.parse(_priceController.text),
        stockLevel: int.parse(_stockController.text),
        categoryId: _selectedCategoryId ?? 0,
        unitCost: double.tryParse(_unitCostController.text) ?? 0.0,
        imagePath: _imagePath,
        discountPrice: discountPrice,
        discountStartDate: _hasDiscount ? DateTime.now() : null,
        discountEndDate: (_hasDiscount && durationDays != null) ? DateTime.now().add(Duration(days: durationDays)) : null,
        isTaxInclusive: _isTaxInclusive,
        taxRate: _isTaxInclusive ? 16.0 : 0.0,
        zraTaxCode: 'A',
        branchCode: branchBhfId,
        branchName: branchName,
        isSyncedWithDigitax: false,
        lastDigitaxSyncDate: null,
      );
      
      final previousStock = widget.product?.stockLevel;

      if (widget.product != null) {
        product.name = _nameController.text;
        product.sku = _skuController.text;
        product.price = double.parse(_priceController.text);
        product.unitCost = double.tryParse(_unitCostController.text) ?? 0.0;
        product.stockLevel = int.parse(_stockController.text);
        product.categoryId = _selectedCategoryId ?? 0;
        product.imagePath = _imagePath;
        product.discountPrice = discountPrice;
        product.discountStartDate = _hasDiscount ? (product.discountStartDate ?? DateTime.now()) : null;
        product.discountEndDate = (_hasDiscount && durationDays != null) ? DateTime.now().add(Duration(days: durationDays)) : null;
        product.isTaxInclusive = _isTaxInclusive;
        product.taxRate = _isTaxInclusive ? 16.0 : 0.0;
        product.zraTaxCode = 'A';
        product.branchCode = branchBhfId;
        product.branchName = branchName;
      }

      await db.saveProduct(product);

      // Always push product to DigiTax VSDC Cloud for live ZRA compliance
      bool digitaxSynced = false;
      String? syncErr;
      try {
        digitaxSynced = await ref.read(digitaxInventoryServiceProvider).syncSingleProductToDigitax(
          product,
          previousStock: previousStock,
          branchCode: branchBhfId,
        );
      } catch (e) {
        syncErr = e.toString();
        debugPrint('DigiTax product push notice: $e');
      }

      if (mounted) {
        if (digitaxSynced) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${product.name} saved & registered with DigiTax!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        } else if (syncErr != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Product saved locally. DigiTax: $syncErr'),
              backgroundColor: const Color(0xFFF59E0B),
            ),
          );
        }
        Navigator.pop(context, true);
      }
    }
  }
}
