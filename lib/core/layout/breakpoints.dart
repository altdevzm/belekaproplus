// lib/core/layout/breakpoints.dart

abstract class AppBreakpoints {
  // Width thresholds (logical pixels)
  static const double mobileMax = 599;
  static const double tabletMin = 600;
  static const double tabletMax = 1023;
  static const double desktopMin = 1024;

  // Compact form factor (POS portrait, small phones)
  static const double compactMax = 399;

  // Ultra-wide (large desktops, 4K)
  static const double ultraWideMin = 1920;

  /// Returns true if the screen aspect ratio indicates a square or near-square monitor
  /// (e.g. 4:3 = 1.33, 5:4 = 1.25, 1:1 = 1.0). Typical widescreen is 16:9 (1.78) or 16:10 (1.6).
  static bool isSquare(double width, double height) {
    if (height <= 0) return false;
    final ratio = width / height;
    return ratio <= 1.42;
  }
}

