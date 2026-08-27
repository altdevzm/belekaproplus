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
      
      // Auto-trigger read or simulation if no weight
      if (_currentNetWeight == 0.0) {
        scaleService.startSimulation(targetWeight: 1.250);
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
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 50,
              spreadRadius: 10,
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
                          color: const Color(0xFFC1F11D).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.scale_rounded, color: Color(0xFFC1F11D), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.product.name,
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Unit Price: ${CurrencyFormatter.format(unitPrice, widget.currency)} / $unitLabel',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Digital Scale LED Display Box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isScaleStable ? const Color(0xFF10B981) : Colors.orangeAccent,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isScaleStable ? const Color(0xFF10B981) : Colors.orangeAccent).withValues(alpha: 0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isScaleStable ? const Color(0xFF10B981) : Colors.orangeAccent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isManualInput
                                  ? 'MANUAL KEYPAD INPUT'
                                  : (_isScaleConnected
                                      ? (_isScaleStable ? 'SCALE STABLE' : 'READING SCALE...')
                                      : 'SCALE SIMULATOR / DISCONNECTED'),
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1,
                                color: _isScaleStable ? const Color(0xFF10B981) : Colors.orangeAccent,
                              ),
                            ),
                          ],
                        ),
                        if (_currentTareWeight > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'TARE: ${_currentTareWeight.toStringAsFixed(3)} $unitLabel',
                              style: GoogleFonts.inter(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.bold),
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
                          style: GoogleFonts.robotoMono(
                            fontSize: 46,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFC1F11D),
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          unitLabel.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white54,
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
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TOTAL COMPUTED AMOUNT',
                          style: GoogleFonts.manrope(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_currentNetWeight.toStringAsFixed(3)} $unitLabel × ${CurrencyFormatter.format(unitPrice, widget.currency)}',
                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                    Text(
                      CurrencyFormatter.format(totalComputedPrice, widget.currency),
                      style: GoogleFonts.manrope(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFFC1F11D),
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
                          _buildTareButton('Zero', () => _setTare(0.0)),
                          const SizedBox(width: 6),
                          _buildTareButton('Bag (15g)', () => _setTare(0.015)),
                          const SizedBox(width: 6),
                          _buildTareButton('Tray (50g)', () => _setTare(0.050)),
                          const SizedBox(width: 10),
                          Container(width: 1, height: 24, color: Colors.white24),
                          const SizedBox(width: 10),
                          _buildPresetButton('0.25 $unitLabel', () => _setManualWeight(0.25)),
                          const SizedBox(width: 6),
                          _buildPresetButton('0.50 $unitLabel', () => _setManualWeight(0.50)),
                          const SizedBox(width: 6),
                          _buildPresetButton('1.00 $unitLabel', () => _setManualWeight(1.00)),
                          const SizedBox(width: 6),
                          _buildPresetButton('2.00 $unitLabel', () => _setManualWeight(2.00)),
                          const SizedBox(width: 6),
                          _buildPresetButton('5.00 $unitLabel', () => _setManualWeight(5.00)),
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
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildKeypadKey('1'),
                        _buildKeypadKey('2'),
                        _buildKeypadKey('3'),
                        _buildKeypadKey('C', color: Colors.orangeAccent),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeypadKey('4'),
                        _buildKeypadKey('5'),
                        _buildKeypadKey('6'),
                        _buildKeypadKey('⌫', color: Colors.redAccent),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeypadKey('7'),
                        _buildKeypadKey('8'),
                        _buildKeypadKey('9'),
                        _buildKeypadKey('.'),
                      ],
                    ),
                    Row(
                      children: [
                        _buildKeypadKey('0', flex: 2),
                        _buildKeypadKey('00'),
                        _buildScaleReReadKey(),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action Confirm Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _currentNetWeight > 0
                      ? () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(context, _currentNetWeight);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC1F11D),
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_shopping_cart_rounded, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        _currentNetWeight > 0
                            ? 'ADD TO CART  •  ${CurrencyFormatter.format(totalComputedPrice, widget.currency)}'
                            : 'PLACE ITEM ON SCALE',
                        style: GoogleFonts.manrope(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
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

  Widget _buildTareButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _buildPresetButton(String label, VoidCallback onTap) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFC1F11D).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFFC1F11D)),
        ),
      ),
    );
  }

  Widget _buildKeypadKey(String key, {int flex = 1, Color? color}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            _appendKeypad(key);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Text(
              key,
              style: GoogleFonts.robotoMono(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color ?? Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScaleReReadKey() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            setState(() => _isManualInput = false);
            ref.read(scaleServiceProvider).startSimulation(targetWeight: 1.450);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.refresh_rounded, color: Color(0xFFC1F11D), size: 20),
          ),
        ),
      ),
    );
  }
}
