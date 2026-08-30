import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class CameraBarcodeScannerModal extends StatefulWidget {
  final String title;
  final ValueChanged<String> onScanned;

  const CameraBarcodeScannerModal({
    super.key,
    this.title = 'Scan Product Barcode / QR',
    required this.onScanned,
  });

  static Future<String?> show(BuildContext context, {String title = 'Scan Product Barcode / QR'}) async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CameraBarcodeScannerModal(
        title: title,
        onScanned: (code) {
          Navigator.of(ctx).pop(code);
        },
      ),
    );
  }

  @override
  State<CameraBarcodeScannerModal> createState() => _CameraBarcodeScannerModalState();
}

class _CameraBarcodeScannerModalState extends State<CameraBarcodeScannerModal> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  final TextEditingController _manualInputCtrl = TextEditingController();
  bool _hasDetected = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    _manualInputCtrl.dispose();
    super.dispose();
  }

  void _handleBarcode(String rawValue) {
    if (_hasDetected) return;
    _hasDetected = true;
    HapticFeedback.heavyImpact();
    widget.onScanned(rawValue.trim());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isMobile = media.size.width < 600;

    return Container(
      height: media.size.height * (isMobile ? 0.85 : 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFF141418),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC1F11D).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Color(0xFFC1F11D),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'Point camera at product barcode or QR code',
                          style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        color: _torchOn ? const Color(0xFFC1F11D) : Colors.white70,
                      ),
                      tooltip: 'Toggle Flashlight',
                      onPressed: () async {
                        await _controller.toggleTorch();
                        setState(() => _torchOn = !_torchOn);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white70),
                      tooltip: 'Switch Camera',
                      onPressed: () => _controller.switchCamera(),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),

          // Scanner View Port
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        final val = barcode.rawValue;
                        if (val != null && val.isNotEmpty) {
                          _handleBarcode(val);
                          break;
                        }
                      }
                    },
                    errorBuilder: (context, error) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.videocam_off_rounded, size: 48, color: Colors.white38),
                              const SizedBox(height: 12),
                              Text(
                                'Camera Access Unavailable',
                                style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Check camera permissions or use manual barcode entry below.',
                                style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Scanner Reticle Overlay
                Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFC1F11D), width: 2),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Stack(
                    children: [
                      // Target corners
                      Positioned(top: 0, left: 0, child: _corner(true, true)),
                      Positioned(top: 0, right: 0, child: _corner(true, false)),
                      Positioned(bottom: 0, left: 0, child: _corner(false, true)),
                      Positioned(bottom: 0, right: 0, child: _corner(false, false)),
                      Center(
                        child: Container(
                          height: 2,
                          color: const Color(0xFFC1F11D).withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Manual Entry Fallback Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1B1B20),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualInputCtrl,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Or enter Barcode / SKU manually...',
                      hintStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.keyboard_alt_outlined, color: Colors.white38, size: 18),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _handleBarcode(val.trim());
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    final val = _manualInputCtrl.text.trim();
                    if (val.isNotEmpty) {
                      _handleBarcode(val);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC1F11D),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    'Lookup',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner(bool top, bool left) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        border: Border(
          top: top ? const BorderSide(color: Color(0xFFC1F11D), width: 4) : BorderSide.none,
          bottom: !top ? const BorderSide(color: Color(0xFFC1F11D), width: 4) : BorderSide.none,
          left: left ? const BorderSide(color: Color(0xFFC1F11D), width: 4) : BorderSide.none,
          right: !left ? const BorderSide(color: Color(0xFFC1F11D), width: 4) : BorderSide.none,
        ),
      ),
    );
  }
}
