// lib/core/layout/sidebar_constants.dart

abstract class SidebarMetrics {
  static const double collapsed = 72; // icon-only rail equivalent
  static const double standard = 140; // POS compact icon + label
  static const double expanded = 220; // Full sidebar

  static double forWidth(double screenWidth) {
    if (screenWidth < 1024) return collapsed;
    if (screenWidth < 1440) return standard;
    return expanded;
  }
}
