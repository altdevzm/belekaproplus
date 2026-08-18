// lib/core/layout/adaptive_dialog.dart

import 'package:flutter/material.dart';
import 'screen_class.dart';

Future<T?> showAdaptiveAppDialog<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
}) {
  final sc = getScreenClass(MediaQuery.of(context).size.width);

  if (sc == ScreenClass.mobile || sc == ScreenClass.compact) {
    // Modal bottom sheet on mobile & compact portrait POS
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          child: child,
        ),
      ),
    );
  }

  // Centered dialog on tablet / desktop / ultrawide
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: sc == ScreenClass.tablet ? 540 : 640,
        ),
        child: child,
      ),
    ),
  );
}
