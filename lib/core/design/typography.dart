// lib/core/design/typography.dart

import 'package:flutter/material.dart';
import '../layout/screen_class.dart';

class AppTextStyles {
  static TextStyle display(BuildContext ctx) => Theme.of(ctx).textTheme.displaySmall!;
  static TextStyle heading(BuildContext ctx) => Theme.of(ctx).textTheme.headlineMedium!;
  static TextStyle title(BuildContext ctx) => Theme.of(ctx).textTheme.titleLarge!;
  static TextStyle body(BuildContext ctx) => Theme.of(ctx).textTheme.bodyLarge!;
  static TextStyle label(BuildContext ctx) => Theme.of(ctx).textTheme.labelLarge!;
  static TextStyle caption(BuildContext ctx) => Theme.of(ctx).textTheme.bodySmall!;

  // Scale body font up on POS (larger viewing distance)
  static double bodySize(ScreenClass sc) => switch (sc) {
        ScreenClass.compact => 14,
        ScreenClass.mobile => 14,
        ScreenClass.tablet => 15,
        ScreenClass.desktop => 14,
        ScreenClass.ultraWide => 15,
      };
}
