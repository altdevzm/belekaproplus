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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator(color: primaryColor));
    }
    
    return Dialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? primaryColor.withValues(alpha: 0.15) : primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.loyalty_rounded, color: primaryColor, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Loyalty & Rewards Program',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 16),
            
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Enable Customer Loyalty Program',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              subtitle: Text(
                'Allow registered customers to earn and redeem reward points at checkout',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              activeThumbColor: primaryColor,
              value: _loyaltyEnabled,
              onChanged: (val) {
                setState(() => _loyaltyEnabled = val);
              },
            ),
            
            const SizedBox(height: 16),
            
            if (_loyaltyEnabled) ...[
              _buildField(
                context: context,
                label: 'EARNING RATE (POINTS PER CURRENCY UNIT)',
                controller: _earnRateController,
                hint: 'e.g. 1.0',
              ),
              const SizedBox(height: 6),
              Text(
                'Example: If set to 1, a K100 purchase earns 100 reward points.',
                style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              _buildField(
                context: context,
                label: 'REDEMPTION VALUE (CURRENCY VALUE PER POINT)',
                controller: _redemptionValueController,
                hint: 'e.g. 0.01',
              ),
              const SizedBox(height: 6),
              Text(
                'Example: If set to 0.01, redeeming 100 points deducts K1.00 from order total.',
                style: GoogleFonts.inter(fontSize: 11.5, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            
            const SizedBox(height: 24),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _saveConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    'Save Settings',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold),
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
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: primaryColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
          style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 13),
            filled: true,
            fillColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: primaryColor),
            ),
          ),
        ),
      ],
    );
  }
}
