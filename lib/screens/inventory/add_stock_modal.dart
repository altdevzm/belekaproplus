import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';

class AddStockModal extends ConsumerStatefulWidget {
  final Product product;

  const AddStockModal({
    super.key,
    required this.product,
  });

  @override
  ConsumerState<AddStockModal> createState() => _AddStockModalState();
}

class _AddStockModalState extends ConsumerState<AddStockModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 400,
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RECEIVE STOCK',
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                      color: const Color(0xFFC1F11D),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Add inventory quantity for ${widget.product.name} (SKU: ${widget.product.sku}).',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              _buildTextField(
                controller: _quantityController,
                label: 'QUANTITY TO ADD',
                hint: 'e.g. 50',
                autofocus: true,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (int.tryParse(v) == null || int.parse(v) <= 0) return 'Must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC1F11D),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    'UPDATE INVENTORY',
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
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
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
            style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.inter(color: Colors.white10, fontWeight: FontWeight.normal),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: InputBorder.none,
              errorStyle: const TextStyle(height: 0),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() ?? false) {
      final quantityToAdd = int.parse(_quantityController.text);
      final previousStock = widget.product.stockLevel;
      final newStockLevel = previousStock + quantityToAdd;
      
      final db = ref.read(databaseServiceProvider);
      
      widget.product.stockLevel = newStockLevel;
      await db.saveProduct(widget.product);

      final storeConfig = ref.read(storeConfigProvider).value;
      final branchCode = (storeConfig != null && storeConfig.bhfId.isNotEmpty)
          ? storeConfig.bhfId
          : widget.product.branchCode;

      // Push stock update directly to DigiTax
      bool digitaxSynced = false;
      String? syncErr;
      try {
        digitaxSynced = await ref.read(digitaxInventoryServiceProvider).syncSingleProductToDigitax(
          widget.product,
          previousStock: previousStock,
          branchCode: branchCode,
        );
      } catch (e) {
        syncErr = e.toString();
        debugPrint('DigiTax stock push notice: $e');
      }

      if (mounted) {
        if (digitaxSynced) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Stock updated & synced with DigiTax (${widget.product.name}: $newStockLevel)'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        } else if (syncErr != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Stock updated locally. DigiTax: $syncErr'),
              backgroundColor: const Color(0xFFF59E0B),
            ),
          );
        }
        Navigator.pop(context, true);
      }
    }
  }
}
