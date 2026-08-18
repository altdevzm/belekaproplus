// lib/core/layout/adaptive_layout.dart

import 'package:flutter/material.dart';
import 'screen_class.dart';

class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.mobile,
    this.compact,
    this.tablet,
    this.desktop,
    this.ultraWide,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder? compact; // override for very small / POS portrait
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;
  final WidgetBuilder? ultraWide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sc = getScreenClass(constraints.maxWidth);
        switch (sc) {
          case ScreenClass.compact:
            return (compact ?? mobile)(context);
          case ScreenClass.mobile:
            return mobile(context);
          case ScreenClass.tablet:
            return (tablet ?? mobile)(context);
          case ScreenClass.desktop:
            return (desktop ?? tablet ?? mobile)(context);
          case ScreenClass.ultraWide:
            return (ultraWide ?? desktop ?? tablet ?? mobile)(context);
        }
      },
    );
  }
}
