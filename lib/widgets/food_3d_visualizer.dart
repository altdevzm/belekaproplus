import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Displays the restaurant's uploaded dish PNG as the main hero visual,
/// with selected extras popping in below it as circular product bubbles.
/// Never renders hardcoded stock food images when no image is uploaded.
class Food3DVisualizer extends StatefulWidget {
  final String productName;
  final String? productImagePath;
  final double basePrice;
  final String currency;
  final List<Map<String, dynamic>> extras;
  final String? lastAddedExtraName;
  final int animationTrigger;
  final double height;
  final bool showPriceTag;

  const Food3DVisualizer({
    super.key,
    required this.productName,
    this.productImagePath,
    required this.basePrice,
    required this.currency,
    this.extras = const [],
    this.lastAddedExtraName,
    this.animationTrigger = 0,
    this.height = 280,
    this.showPriceTag = true,
  });

  @override
  State<Food3DVisualizer> createState() => _Food3DVisualizerState();
}

class _Food3DVisualizerState extends State<Food3DVisualizer>
    with TickerProviderStateMixin {
  late final AnimationController _idleController;
  late final AnimationController _popController;

  double _dragYaw = 0.0;
  double _dragPitch = -0.04;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
  }

  @override
  void didUpdateWidget(covariant Food3DVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animationTrigger != oldWidget.animationTrigger &&
        widget.animationTrigger > 0) {
      _popController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _popController.dispose();
    super.dispose();
  }

  double get _totalPrice {
    final extrasTotal = widget.extras.fold<double>(
      0.0,
      (sum, e) => sum + ((e['price'] as num?)?.toDouble() ?? 0.0),
    );
    return widget.basePrice + extrasTotal;
  }

  bool get _hasProductImage {
    final p = widget.productImagePath;
    return p != null && p.isNotEmpty && File(p).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    final hasDishImg = _hasProductImage;

    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _dragYaw = (_dragYaw + details.delta.dx * 0.012).clamp(-0.55, 0.55);
          _dragPitch =
              (_dragPitch - details.delta.dy * 0.008).clamp(-0.3, 0.3);
        });
      },
      onDoubleTap: () {
        setState(() {
          _dragYaw = 0.0;
          _dragPitch = -0.04;
        });
      },
      child: Container(
        height: widget.height,
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const RadialGradient(
            center: Alignment(0, -0.15),
            radius: 0.95,
            colors: [
              Color(0xFF1E293B),
              Color(0xFF0F172A),
              Color(0xFF070B14),
            ],
          ),
          border: Border.all(
            color: const Color(0xFF334155).withValues(alpha: 0.6),
          ),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // Top area: Main Meal PNG (only if restaurant uploaded one)
                Expanded(
                  child: hasDishImg
                      ? AnimatedBuilder(
                          animation: Listenable.merge([
                            _idleController,
                            _popController,
                          ]),
                          builder: (context, _) {
                            final idlePhase =
                                _idleController.value * 2 * math.pi;
                            final floatY = math.sin(idlePhase) * 4.0;
                            final autoYaw = math.sin(idlePhase * 0.5) * 0.08;
                            final bounce = _popController.isAnimating
                                ? 1.0 +
                                    math.sin(_popController.value * math.pi) *
                                        0.05
                                : 1.0;

                            final matrix = Matrix4.identity()
                              ..setEntry(3, 2, 0.0014)
                              ..rotateX(_dragPitch)
                              ..rotateY(_dragYaw + autoYaw)
                              ..scaleByDouble(bounce, bounce, 1.0, 1.0);

                            return Transform.translate(
                              offset: Offset(0, floatY),
                              child: Transform(
                                alignment: Alignment.center,
                                transform: matrix,
                                child: Image.file(
                                  File(widget.productImagePath!),
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            );
                          },
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.productName,
                                style: GoogleFonts.plusJakartaSans(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Upload a Dish PNG under Menu to preview photo here',
                                style: GoogleFonts.inter(
                                  color: const Color(0xFF64748B),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),

                // Below the main meal: Circular extra product bubbles
                if (widget.extras.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 82,
                    child: Center(
                      child: ListView.separated(
                        shrinkWrap: true,
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.extras.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final ex = widget.extras[index];
                          final name = ex['name']?.toString() ?? 'Extra';
                          final price =
                              (ex['price'] as num?)?.toDouble() ?? 0.0;
                          final imgPath = ex['imagePath']?.toString();
                          final hasExtraImg = imgPath != null &&
                              imgPath.isNotEmpty &&
                              File(imgPath).existsSync();
                          final isLatest =
                              name == widget.lastAddedExtraName &&
                                  _popController.isAnimating;

                          return TweenAnimationBuilder<double>(
                            key: ValueKey('extra_circle_${name}_$index'),
                            tween: Tween(begin: 0.4, end: 1.0),
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.elasticOut,
                            builder: (context, scale, child) {
                              final popBoost = isLatest
                                  ? 1.0 +
                                      math.sin(_popController.value * math.pi) *
                                          0.14
                                  : 1.0;
                              return Transform.scale(
                                scale: scale * popBoost,
                                child: child,
                              );
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF141E33),
                                    border: Border.all(
                                      color: const Color(0xFF34D399),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.35),
                                        blurRadius: 10,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: hasExtraImg
                                        ? Image.file(
                                            File(imgPath),
                                            fit: BoxFit.cover,
                                            filterQuality: FilterQuality.high,
                                          )
                                        : Center(
                                            child: Text(
                                              '+',
                                              style: GoogleFonts.plusJakartaSans(
                                                color: const Color(0xFF34D399),
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  price > 0
                                      ? '$name (+${widget.currency}${price.toStringAsFixed(0)})'
                                      : name,
                                  style: GoogleFonts.inter(
                                    color: const Color(0xFFE2E8F0),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Top-right live total price badge
            if (widget.showPriceTag)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF10B981), Color(0xFF059669)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF10B981).withValues(alpha: 0.35),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: Text(
                    '${widget.currency} ${_totalPrice.toStringAsFixed(2)}',
                    style: GoogleFonts.plusJakartaSans(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
