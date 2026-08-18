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
}
