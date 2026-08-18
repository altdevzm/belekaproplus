// lib/core/design/spacing.dart

import 'package:flutter/material.dart';
import '../layout/screen_class.dart';

abstract class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  static const double xxxl = 64.0;

  // Responsive padding: call inside LayoutBuilder
  static EdgeInsets screenPadding(ScreenClass sc) => switch (sc) {
        ScreenClass.compact => const EdgeInsets.all(12),
        ScreenClass.mobile => const EdgeInsets.all(16),
        ScreenClass.tablet => const EdgeInsets.all(24),
        ScreenClass.desktop => const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        ScreenClass.ultraWide => const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      };
}
