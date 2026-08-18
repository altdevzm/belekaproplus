// lib/core/layout/constrained_content.dart

import 'package:flutter/material.dart';

/// Prevents content from stretching beyond a readable width on ultrawide screens.
class ConstrainedContent extends StatelessWidget {
  const ConstrainedContent({super.key, required this.child, this.maxWidth = 1440});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
