// lib/core/layout/screen_class.dart

import 'breakpoints.dart';

enum ScreenClass { compact, mobile, tablet, desktop, ultraWide }

ScreenClass getScreenClass(double width) {
  if (width <= AppBreakpoints.compactMax) return ScreenClass.compact;
  if (width <= AppBreakpoints.mobileMax) return ScreenClass.mobile;
  if (width <= AppBreakpoints.tabletMax) return ScreenClass.tablet;
  if (width < AppBreakpoints.ultraWideMin) return ScreenClass.desktop;
  return ScreenClass.ultraWide;
}
