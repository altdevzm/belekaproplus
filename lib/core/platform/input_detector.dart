// lib/core/platform/input_detector.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum InputModel { touch, mouse, keyboard }

InputModel primaryInput(BuildContext context) {
  if (kIsWeb) return InputModel.mouse; // conservative default
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
    case TargetPlatform.iOS:
      return InputModel.touch;
    case TargetPlatform.windows:
    case TargetPlatform.macOS:
    case TargetPlatform.linux:
      return InputModel.mouse;
    default:
      return InputModel.touch;
  }
}

Widget withHoverEffect(BuildContext context, Widget child) {
  if (primaryInput(context) == InputModel.touch) return child;
  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: child,
  );
}
