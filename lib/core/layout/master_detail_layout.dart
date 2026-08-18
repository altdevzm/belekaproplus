// lib/core/layout/master_detail_layout.dart

import 'package:flutter/material.dart';
import 'adaptive_layout.dart';

/// Mobile: shows master view (detail pushed via navigation or bottom sheet)
/// Tablet+: shows master | detail side-by-side
class MasterDetailLayout extends StatelessWidget {
  const MasterDetailLayout({
    super.key,
    required this.master,
    required this.detail,
    this.masterFlex = 1,
    this.detailFlex = 2,
  });

  final Widget master;
  final Widget detail;
  final int masterFlex, detailFlex;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      mobile: (_) => master,
      tablet: (_) => Row(children: [
        Flexible(flex: masterFlex, child: master),
        const VerticalDivider(width: 1),
        Flexible(flex: detailFlex, child: detail),
      ]),
      desktop: (_) => Row(children: [
        Flexible(flex: masterFlex, child: master),
        const VerticalDivider(width: 1),
        Flexible(flex: detailFlex, child: detail),
      ]),
    );
  }
}
