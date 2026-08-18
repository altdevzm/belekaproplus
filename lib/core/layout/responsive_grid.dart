// lib/core/layout/responsive_grid.dart

import 'package:flutter/material.dart';
import 'screen_class.dart';

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
    this.ultraWideColumns = 4,
    this.spacing = 16,
    this.childAspectRatio = 1.4,
  });

  final List<Widget> children;
  final int mobileColumns, tabletColumns, desktopColumns, ultraWideColumns;
  final double spacing;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sc = getScreenClass(constraints.maxWidth);
      final cols = switch (sc) {
        ScreenClass.compact || ScreenClass.mobile => mobileColumns,
        ScreenClass.tablet => tabletColumns,
        ScreenClass.desktop => desktopColumns,
        ScreenClass.ultraWide => ultraWideColumns,
      };
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: childAspectRatio,
        ),
        itemCount: children.length,
        itemBuilder: (_, i) => children[i],
      );
    });
  }
}
