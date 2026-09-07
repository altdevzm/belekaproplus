import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/scale_service.dart';
import 'package:beleka_pos/utils/formatters.dart';

class WeightScaleModal extends ConsumerStatefulWidget {
  final Product product;
  final String currency;
  final double? initialWeight;

  const WeightScaleModal({
    super.key,
    required this.product,
    required this.currency,
    this.initialWeight,
  });

  @override
  ConsumerState<WeightScaleModal> createState() => _WeightScaleModalState();
}

class _WeightScaleModalState extends ConsumerState<WeightScaleModal> {
  late TextEditingController _manualWeightController;
  StreamSubscription<ScaleWeightReading>? _scaleSubscription;
  
  double _currentNetWeight = 0.0;
  double _currentTareWeight = 0.0;
  bool _isScaleStable = true;
  bool _isScaleConnected = false;
  bool _isManualInput = false;

  @override
  void initState() {
    super.initState();
    _currentTareWeight = widget.product.tareWeight;
    _currentNetWeight = widget.initialWeight ?? 0.0;
    _manualWeightController = TextEditingController(
      text: _currentNetWeight > 0 ? _currentNetWeight.toStringAsFixed(3) : '',
    );

    // Subscribe to live hardware scale readings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scaleService = ref.read(scaleServiceProvider);
      
      _isScaleConnected = scaleService.isConnected;
      if (!_isManualInput && scaleService.isConnected && scaleService.currentReading.netWeight > 0) {
        setState(() {
          _currentNetWeight = scaleService.currentReading.netWeight;
          _isScaleStable = scaleService.currentReading.isStable;
          _isScaleConnected = scaleService.currentReading.isConnected;
          _manualWeightController.text = _currentNetWeight.toStringAsFixed(3);
        });
      }

      _scaleSubscription = scaleService.weightStream.listen((reading) {
        if (!_isManualInput && mounted) {
          setState(() {
            _currentNetWeight = reading.netWeight;
            _isScaleStable = reading.isStable;
            _isScaleConnected = reading.isConnected;
            _manualWeightController.text = _currentNetWeight > 0 ? _currentNetWeight.toStringAsFixed(3) : '';
          });
        }
      });
    });
  }

  @override
  void dispose() {
    _scaleSubscription?.cancel();
    _manualWeightController.dispose();
    super.dispose();
  }

  void _setTare(double tare) {
    setState(() {
      _currentTareWeight = tare;
    });
    ref.read(scaleServiceProvider).tare(tare);
  }

  void _setManualWeight(double weight) {
    setState(() {
      _isManualInput = true;
      _currentNetWeight = weight;
      _manualWeightController.text = weight.toStringAsFixed(3);
    });
    ref.read(scaleServiceProvider).setManualWeight(weight);
  }

  void _appendKeypad(String key) {
    _isManualInput = true;
    String current = _manualWeightController.text;
    if (key == 'C') {
      current = '';
    } else if (key == '⌫') {
      if (current.isNotEmpty) current = current.substring(0, current.length - 1);
    } else if (key == '.') {
      if (!current.contains('.')) current = current.isEmpty ? '0.' : '$current.';
    } else {
      if (current == '0') current = '';
      current = '$current$key';
    }

    final parsed = double.tryParse(current) ?? 0.0;
    setState(() {
      _currentNetWeight = parsed;
      _manualWeightController.text = current;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF151F32) : Colors.white;
    final borderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);
    final innerBg = isDark ? const Color(0xFF0B1220) : const Color(0xFFF8FAFC);
    const primaryAccent = Color(0xFF1D4ED8);

    final unit = widget.product.unitOfMeasure.toLowerCase().trim();
    final unitLabel = unit.isEmpty ? 'kg' : unit;
    final unitPrice = widget.product.price;
    final totalComputedPrice = _currentNetWeight * unitPrice;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: 580,
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.08),
              blurRadius: 36,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.scale_rounded, color: primaryAccent, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product.name,
                            style: GoogleFonts.inter(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            'Unit Price: ${CurrencyFormatter.format(unitPrice, widget.currency)} / $unitLabel',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Digital Scale LED Display Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isScaleStable ? const Color(0xFF059669) : const Color(0xFFD97706),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _isScaleConnected
                                    ? (_isScaleStable ? const Color(0xFF059669) : const Color(0xFFD97706))
                                    : const Color(0xFF94A3B8),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isScaleConnected 
                                  ? (_isScaleStable ? 'LIVE SCALE • STABLE' : 'LIVE SCALE • STABILIZING...') 
                                  : 'MANUAL WEIGHT / NO HARDWARE SCALE',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: _isScaleConnected
                                    ? (_isScaleStable ? const Color(0xFF059669) : const Color(0xFFD97706))
                                    : theme.colorScheme.onSurfaceVariant,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        if (_currentTareWeight > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: primaryAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'TARE: ${_currentTareWeight.toStringAsFixed(3)} $unitLabel',
                              style: GoogleFonts.jetBrainsMono(fontSize: 10, color: primaryAccent, fontWeight: FontWeight.w800),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _currentNetWeight.toStringAsFixed(3),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 46,
                            fontWeight: FontWeight.w900,
                            color: primaryAccent,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          unitLabel.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Live Math & Calculation Summary Box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL COMPUTED AMOUNT',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_currentNetWeight.toStringAsFixed(3)} $unitLabel × ${CurrencyFormatter.format(unitPrice, widget.currency)}',
                          style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      CurrencyFormatter.format(totalComputedPrice, widget.currency),
                      style: GoogleFonts.inter(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF059669),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Quick Weight Presets & Tare Controls
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildTareButton(context, 'Zero', () => _setTare(0.0)),
                          const SizedBox(width: 6),
                          _buildTareButton(context, 'Bag (15g)', () => _setTare(0.015)),
                          const SizedBox(width: 6),
                          _buildTareButton(context, 'Tray (50g)', () => _setTare(0.050)),
                          const SizedBox(width: 10),
                          Container(width: 1, height: 24, color: borderColor),
                          const SizedBox(width: 10),
                          _buildPresetButton(context, '0.25 $unitLabel', () => _setManualWeight(0.25)),
                          const SizedBox(width: 6),
                          _buildPresetButton(context, '0.50 $unitLabel', () => _setManualWeight(0.50)),
                          const SizedBox(width: 6),
                          _buildPresetButton(context, '1.00 $unitLabel', () => _setManualWeight(1.00)),
                          const SizedBox(width: 6),
                          _buildPresetButton(context, '2.00 $unitLabel', () => _setManualWeight(2.00)),
                          const SizedBox(width: 6),
                          _buildPresetButton(context, '5.00 $unitLabel', () => _setManualWeight(5.00)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Numeric Keypad Grid
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: innerBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildKeypadKey(context, '1'),
                        _buildKeypadKey(context, '2'),
                        _buildKeypadKey(context, '3'),
                        _buildKeypadKey(context, 'C', color: const Color(0xFFD97706)),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeypadKey(context, '4'),
                        _buildKeypadKey(context, '5'),
                        _buildKeypadKey(context, '6'),
                        _buildKeypadKey(context, '⌫', color: const Color(0xFFDC2626)),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeypadKey(context, '7'),
                        _buildKeypadKey(context, '8'),
                        _buildKeypadKey(context, '9'),
                        _buildKeypadKey(context, '.'),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeypadKey(context, '0', flex: 2),
                        _buildKeypadKey(context, '00'),
                        _buildScaleReReadKey(context),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Confirm Button
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _currentNetWeight > 0
                      ? () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(context, _currentNetWeight);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFE2E8F0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_shopping_cart_rounded, size: 18, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(
                        _currentNetWeight > 0
                            ? 'ADD TO CART  •  ${CurrencyFormatter.format(totalComputedPrice, widget.currency)}'
                            : 'PLACE ITEM ON SCALE',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTareButton(BuildContext context, String label, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C283D) : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: theme.colorScheme.onSurface),
        ),
      ),
    );
  }

  Widget _buildPresetButton(BuildContext context, String label, VoidCallback onTap) {
    const primaryAccent = Color(0xFF1D4ED8);

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: primaryAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: primaryAccent.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: primaryAccent),
        ),
      ),
    );
  }

  Widget _buildKeypadKey(BuildContext context, String key, {int flex = 1, Color? color}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final itemBg = isDark ? const Color(0xFF151F32) : Colors.white;
    final borderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);

    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _appendKeypad(key);
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: itemBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Text(
              key,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: color ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScaleReReadKey(BuildContext context) {
    const primaryAccent = Color(0xFF1D4ED8);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: InkWell(
          onTap: () async {
            HapticFeedback.mediumImpact();
            setState(() => _isManualInput = false);
            final scaleService = ref.read(scaleServiceProvider);
            if (scaleService.isConnected) {
              final reading = scaleService.currentReading;
              if (reading.netWeight > 0) {
                setState(() {
                  _currentNetWeight = reading.netWeight;
                  _isScaleStable = reading.isStable;
                  _isScaleConnected = true;
                  _manualWeightController.text = reading.netWeight.toStringAsFixed(3);
                });
              }
            } else {
              // Attempt reconnect
              await scaleService.connect();
              setState(() => _isScaleConnected = scaleService.isConnected);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primaryAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: primaryAccent.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.refresh_rounded, color: primaryAccent, size: 20),
          ),
        ),
      ),
    );
  }
}
