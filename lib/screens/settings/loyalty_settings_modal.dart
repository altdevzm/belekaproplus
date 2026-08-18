import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/models/models.dart';

class LoyaltySettingsModal extends ConsumerStatefulWidget {
  const LoyaltySettingsModal({super.key});

  @override
  ConsumerState<LoyaltySettingsModal> createState() => _LoyaltySettingsModalState();
}

class _LoyaltySettingsModalState extends ConsumerState<LoyaltySettingsModal> {
  final _earnRateController = TextEditingController();
  final _redemptionValueController = TextEditingController();
  
  bool _loyaltyEnabled = false;
  StoreConfig? _currentConfig;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final db = ref.read(databaseServiceProvider);
    final config = await db.getStoreConfig();
    
    if (config != null && mounted) {
      setState(() {
        _currentConfig = config;
        _loyaltyEnabled = config.loyaltyEnabled;
        _earnRateController.text = config.loyaltyEarnRate.toString();
        _redemptionValueController.text = config.loyaltyRedemptionValue.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _earnRateController.dispose();
    _redemptionValueController.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    if (_currentConfig == null) return;
    
    final earnRate = double.tryParse(_earnRateController.text) ?? 1.0;
    final redemptionValue = double.tryParse(_redemptionValueController.text) ?? 0.01;

    _currentConfig!
      ..loyaltyEnabled = _loyaltyEnabled
      ..loyaltyEarnRate = earnRate
      ..loyaltyRedemptionValue = redemptionValue;

    final db = ref.read(databaseServiceProvider);
    await db.saveStoreConfig(_currentConfig!);
    
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Loyalty settings updated successfully',
            style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFFC1F11D),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D)));
    }
    
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Loyalty Program Configuration',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 32),
            
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Enable Loyalty Program',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              subtitle: Text(
                'Allow customers to earn and redeem points',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white54,
                ),
              ),
              activeThumbColor: const Color(0xFFC1F11D),
              value: _loyaltyEnabled,
              onChanged: (val) {
                setState(() => _loyaltyEnabled = val);
              },
            ),
            
            const SizedBox(height: 24),
            
            if (_loyaltyEnabled) ...[
              _buildField(
                label: 'EARNING RATE (POINTS PER CURRENCY UNIT)',
                controller: _earnRateController,
                hint: 'e.g. 1.0',
              ),
              const SizedBox(height: 16),
              Text(
                'Example: If set to 1, a \$100 purchase earns 100 points.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
              ),
              const SizedBox(height: 24),
              _buildField(
                label: 'REDEMPTION VALUE (CURRENCY VALUE PER POINT)',
                controller: _redemptionValueController,
                hint: 'e.g. 0.01',
              ),
              const SizedBox(height: 16),
              Text(
                'Example: If set to 0.01, redeeming 100 points subtracts \$1.00 from the order.',
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.4)),
              ),
            ],
            
            const SizedBox(height: 48),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                  child: Text('CANCEL', style: GoogleFonts.manrope(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _saveConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC1F11D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    'SAVE CHANGES',
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: Colors.white.withValues(alpha: 0.4),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(color: Colors.white.withValues(alpha: 0.1), fontSize: 15),
            filled: true,
            fillColor: Colors.black.withValues(alpha: 0.2),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFC1F11D), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
