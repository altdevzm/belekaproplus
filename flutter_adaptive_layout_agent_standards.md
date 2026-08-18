# Flutter Adaptive Layout — AI Agent Build Standards
### Complete Instruction Set for Mobile, Tablet, Web & Desktop

> **Agent Rule #0 — Non-Negotiable:** Every screen, widget, dialog, form, and component built in this codebase must be adaptive by default. No UI is considered complete unless it renders correctly and intentionally across all six target surfaces listed below. This rule cannot be overridden by any feature request, time constraint, or scope comment.

---

## 0. Target Surface Matrix

| Surface ID | Device Class | OS | Typical Resolution | Input Model |
|------------|-------------|----|--------------------|-------------|
| `S1` | Smartphone | Android / iOS | 360×640 → 430×932 | Touch |
| `S2` | Tablet (Small) | Android / iPadOS | 600×960 → 768×1024 | Touch |
| `S3` | Tablet (Large) | Android / iPadOS | 1024×1366 | Touch + Keyboard |
| `S4` | POS Terminal / Large Android Screen | Android (e.g. Sunmi T2, PAX A920) | 1080×1920 (portrait) or 1920×1080 (landscape) | Touch (gloved/stylus) |
| `S5` | Laptop / Desktop PC | Windows / macOS / Linux | 1280×720 → 2560×1440 | Mouse + Keyboard |
| `S6` | Web Browser | Chrome / Safari / Firefox | 320px → 4K | Mouse + Keyboard + Touch |

---

## 1. Breakpoint System

### 1.1 Canonical Breakpoints

```dart
// lib/core/layout/breakpoints.dart

abstract class AppBreakpoints {
  // Width thresholds (logical pixels)
  static const double mobileMax    = 599;
  static const double tabletMin    = 600;
  static const double tabletMax    = 1023;
  static const double desktopMin   = 1024;

  // Compact form factor (POS portrait, small phones)
  static const double compactMax   = 399;

  // Ultra-wide (large desktops, 4K)
  static const double ultraWideMin = 1920;
}
```

### 1.2 ScreenClass Enum

```dart
// lib/core/layout/screen_class.dart

enum ScreenClass { compact, mobile, tablet, desktop, ultraWide }

ScreenClass getScreenClass(double width) {
  if (width <= AppBreakpoints.compactMax)   return ScreenClass.compact;
  if (width <= AppBreakpoints.mobileMax)    return ScreenClass.mobile;
  if (width <= AppBreakpoints.tabletMax)    return ScreenClass.tablet;
  if (width < AppBreakpoints.ultraWideMin)  return ScreenClass.desktop;
  return ScreenClass.ultraWide;
}
```

### 1.3 AdaptiveLayout Widget (Agent Entry Point)

```dart
// lib/core/layout/adaptive_layout.dart

import 'package:flutter/material.dart';
import 'breakpoints.dart';
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
  final WidgetBuilder? compact;   // override for very small / POS portrait
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
```

> **Agent Rule:** Never use `MediaQuery.of(context).size.width` directly in widget `build()` methods for layout decisions. Always use `LayoutBuilder` or the `AdaptiveLayout` widget. `MediaQuery` is only permitted for font scaling, padding/insets, and orientation queries.

---

## 2. Navigation Architecture

### 2.1 Navigation Decision Tree

```
Screen width < 600px  →  BottomNavigationBar  (S1, compact S4 portrait)
Screen width 600–1023 →  NavigationRail       (S2, S3, landscape S4)
Screen width ≥ 1024   →  Permanent Sidebar    (S5, S6, wide S4 landscape)
```

### 2.2 Adaptive Shell Implementation

```dart
// lib/core/layout/app_shell.dart

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.destinations, required this.body});
  final List<AppDestination> destinations;
  final Widget Function(int selectedIndex) body;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      compact: (_) => _buildBottomNavShell(compact: true),
      mobile:  (_) => _buildBottomNavShell(),
      tablet:  (_) => _buildRailShell(),
      desktop: (_) => _buildSidebarShell(),
    );
  }

  // ── Mobile: Bottom Navigation Bar ────────────────────────────────────────
  Widget _buildBottomNavShell({bool compact = false}) {
    return Scaffold(
      body: widget.body(_selectedIndex),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        labelBehavior: compact
            ? NavigationDestinationLabelBehavior.alwaysHide
            : NavigationDestinationLabelBehavior.onlyShowSelected,
        destinations: widget.destinations
            .map((d) => NavigationDestination(icon: d.icon, label: d.label))
            .toList(),
      ),
    );
  }

  // ── Tablet: Navigation Rail ───────────────────────────────────────────────
  Widget _buildRailShell() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
            labelType: NavigationRailLabelType.selected,
            leading: const AppLogo(size: 36),
            destinations: widget.destinations
                .map((d) => NavigationRailDestination(
                      icon: d.icon,
                      label: Text(d.label),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: widget.body(_selectedIndex)),
        ],
      ),
    );
  }

  // ── Desktop / Web: Permanent Sidebar ─────────────────────────────────────
  Widget _buildSidebarShell() {
    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            destinations: widget.destinations,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (i) => setState(() => _selectedIndex = i),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: widget.body(_selectedIndex)),
        ],
      ),
    );
  }
}
```

### 2.3 Sidebar Width Rules

```dart
// lib/core/layout/sidebar_constants.dart

abstract class SidebarMetrics {
  static const double collapsed  = 72;   // icon-only rail equivalent
  static const double standard   = 240;  // label + icon
  static const double expanded   = 280;  // label + icon + badge/avatar space

  static double forWidth(double screenWidth) {
    if (screenWidth < 1280) return standard;
    if (screenWidth < 1920) return expanded;
    return expanded; // never grow beyond this; use the saved space for content
  }
}
```

### 2.4 POS-Specific Navigation Notes

- On `S4` (POS terminals in portrait), treat as `compact` — hidden labels, large touch targets (≥ 56px height per rail item).
- On `S4` in landscape (kiosk / cashier mode), use a top `AppBar` + persistent action strip instead of sidebar. Sidebar navigation is confusing for timed cashier workflows.
- All tappable navigation items on `S4` must have a **minimum touch target of 56×56px** regardless of visual size.

---

## 3. Grid & Spacing System

### 3.1 Column Grid Per Breakpoint

| ScreenClass | Columns | Gutter | Margin |
|-------------|---------|--------|--------|
| compact | 4 | 8px | 12px |
| mobile | 4 | 16px | 16px |
| tablet | 8 | 24px | 24px |
| desktop | 12 | 24px | 32px |
| ultraWide | 12 | 32px | auto (max content width 1440px) |

### 3.2 Spacing Tokens

```dart
// lib/core/design/spacing.dart

abstract class AppSpacing {
  static const double xs   = 4.0;
  static const double sm   = 8.0;
  static const double md   = 16.0;
  static const double lg   = 24.0;
  static const double xl   = 32.0;
  static const double xxl  = 48.0;
  static const double xxxl = 64.0;

  // Responsive padding: call inside LayoutBuilder
  static EdgeInsets screenPadding(ScreenClass sc) => switch (sc) {
    ScreenClass.compact   => const EdgeInsets.all(12),
    ScreenClass.mobile    => const EdgeInsets.all(16),
    ScreenClass.tablet    => const EdgeInsets.all(24),
    ScreenClass.desktop   => const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
    ScreenClass.ultraWide => const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
  };
}
```

### 3.3 Max Content Width Guard

```dart
// lib/core/layout/constrained_content.dart

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
```

> **Agent Rule:** Any full-page layout on `desktop` or `ultraWide` must be wrapped in `ConstrainedContent`. Never let `Row`/`Column` content stretch to raw screen edges on large monitors.

---

## 4. Responsive Widget Patterns

### 4.1 Responsive Grid (Cards / Tiles)

```dart
// lib/core/layout/responsive_grid.dart

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.mobileColumns    = 1,
    this.tabletColumns    = 2,
    this.desktopColumns   = 3,
    this.ultraWideColumns = 4,
    this.spacing          = 16,
  });

  final List<Widget> children;
  final int mobileColumns, tabletColumns, desktopColumns, ultraWideColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sc = getScreenClass(constraints.maxWidth);
      final cols = switch (sc) {
        ScreenClass.compact || ScreenClass.mobile => mobileColumns,
        ScreenClass.tablet                        => tabletColumns,
        ScreenClass.desktop                       => desktopColumns,
        ScreenClass.ultraWide                     => ultraWideColumns,
      };
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: 1.4,
        ),
        itemCount: children.length,
        itemBuilder: (_, i) => children[i],
      );
    });
  }
}
```

### 4.2 Two-Column Split (Detail View)

```dart
// lib/core/layout/master_detail_layout.dart

/// Mobile: shows list XOR detail (push navigation)
/// Tablet+: shows list | detail side-by-side
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
      mobile: (_) => master, // detail pushed via Navigator
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
```

### 4.3 Responsive Form Layout

```dart
// lib/core/layout/responsive_form.dart

/// Stacks fields vertically on mobile; renders in 2–3 columns on wider screens.
class ResponsiveForm extends StatelessWidget {
  const ResponsiveForm({super.key, required this.fields});
  final List<Widget> fields;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final sc = getScreenClass(constraints.maxWidth);
      final cols = switch (sc) {
        ScreenClass.compact || ScreenClass.mobile => 1,
        ScreenClass.tablet                        => 2,
        _                                         => 3,
      };
      if (cols == 1) {
        return Column(children: fields.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: f,
        )).toList());
      }
      // Wrap into rows of `cols`
      final rows = <Widget>[];
      for (var i = 0; i < fields.length; i += cols) {
        final rowFields = fields.sublist(i, (i + cols).clamp(0, fields.length));
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowFields.map((f) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: rowFields.last == f ? 0 : AppSpacing.md,
                bottom: AppSpacing.md,
              ),
              child: f,
            ),
          )).toList(),
        ));
      }
      return Column(children: rows);
    });
  }
}
```

### 4.4 Responsive Data Table

```dart
// lib/core/layout/responsive_table.dart

/// Desktop: full DataTable with all columns
/// Tablet: DataTable with reduced columns
/// Mobile: ListView of cards (one card per row)
class ResponsiveDataTable<T> extends StatelessWidget {
  const ResponsiveDataTable({
    super.key,
    required this.rows,
    required this.desktopColumns,
    required this.tabletColumns,
    required this.mobileCardBuilder,
  });

  final List<T> rows;
  final List<DataColumn> desktopColumns;
  final List<DataColumn> tabletColumns;
  final Widget Function(T row) mobileCardBuilder;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      mobile: (_) => ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) => mobileCardBuilder(rows[i]),
      ),
      tablet: (_) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(columns: tabletColumns, rows: _buildRows(rows)),
      ),
      desktop: (_) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(columns: desktopColumns, rows: _buildRows(rows)),
      ),
    );
  }

  List<DataRow> _buildRows(List<T> data) =>
      data.map((r) => DataRow(cells: [])).toList(); // agent fills cells
}
```

### 4.5 Adaptive Dialog & Bottom Sheet

```dart
// lib/core/layout/adaptive_dialog.dart

Future<T?> showAdaptiveAppDialog<T>({
  required BuildContext context,
  required Widget child,
  bool isDismissible = true,
}) {
  final sc = getScreenClass(MediaQuery.of(context).size.width);

  if (sc == ScreenClass.mobile || sc == ScreenClass.compact) {
    // Modal bottom sheet on mobile
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) =>
            SingleChildScrollView(controller: controller, child: child),
      ),
    );
  }

  // Centered dialog on tablet / desktop
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: sc == ScreenClass.tablet ? 520 : 640,
        ),
        child: child,
      ),
    ),
  );
}
```

---

## 5. Touch Target & Accessibility Standards

### 5.1 Minimum Touch Target Sizes

| Surface | Min Touch Target | Rationale |
|---------|-----------------|-----------|
| S1 (Smartphone) | 48×48px | Material Design 3 |
| S2 / S3 (Tablet) | 48×48px | Material Design 3 |
| S4 (POS / Large Android) | 56×56px | Gloved hands, fast cashier use |
| S5 (Desktop) | 32×32px | Mouse precision |
| S6 (Web) | 44×44px | WCAG 2.5.5 |

```dart
// Utility: enforce minimum tap area without changing visual size
Widget minTapArea(Widget child, {double size = 48}) => SizedBox(
  width: size,
  height: size,
  child: Center(child: child),
);
```

### 5.2 Typography Scale

```dart
// lib/core/design/typography.dart

class AppTextStyles {
  static TextStyle display(BuildContext ctx)  => Theme.of(ctx).textTheme.displaySmall!;
  static TextStyle heading(BuildContext ctx)  => Theme.of(ctx).textTheme.headlineMedium!;
  static TextStyle title(BuildContext ctx)    => Theme.of(ctx).textTheme.titleLarge!;
  static TextStyle body(BuildContext ctx)     => Theme.of(ctx).textTheme.bodyLarge!;
  static TextStyle label(BuildContext ctx)    => Theme.of(ctx).textTheme.labelLarge!;
  static TextStyle caption(BuildContext ctx)  => Theme.of(ctx).textTheme.bodySmall!;

  // Scale body font up on POS (larger viewing distance)
  static double bodySize(ScreenClass sc) => switch (sc) {
    ScreenClass.compact => 14,
    ScreenClass.mobile  => 14,
    ScreenClass.tablet  => 15,
    ScreenClass.desktop => 14,
    ScreenClass.ultraWide => 15,
  };
}
```

### 5.3 Accessibility Checklist (Agent Must Verify)

- [ ] All interactive widgets have `Semantics` labels or `tooltip` properties.
- [ ] Color contrast ratio ≥ 4.5:1 for body text; ≥ 3:1 for large text (WCAG AA).
- [ ] No information conveyed by color alone.
- [ ] All images have `semanticLabel` or `excludeFromSemantics: true`.
- [ ] `FocusNode` traversal order is logical (top-left → bottom-right for LTR).
- [ ] `TextField` inputs have `textInputAction` set for correct keyboard flow.
- [ ] Error states are announced via `Semantics(liveRegion: true)`.

---

## 6. Platform-Specific Behavior

### 6.1 Input Model Detection

```dart
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
```

### 6.2 Hover & Focus States

```dart
// Only apply hover on non-touch platforms
Widget withHoverEffect(Widget child) {
  if (primaryInput(context) == InputModel.touch) return child;
  return MouseRegion(
    cursor: SystemMouseCursors.click,
    child: child,
  );
}
```

### 6.3 Scrollbar Behavior

```dart
// Always show scrollbar on desktop/web; auto-hide on mobile
ScrollbarThemeData adaptiveScrollbar(ScreenClass sc) => ScrollbarThemeData(
  thumbVisibility: WidgetStateProperty.all(
    sc == ScreenClass.desktop || sc == ScreenClass.ultraWide,
  ),
);
```

### 6.4 Keyboard Shortcut Layer (Desktop & Web only)

```dart
// lib/core/platform/keyboard_shortcuts.dart

/// Wrap the app's root with this on desktop/web only
class AppKeyboardShortcuts extends StatelessWidget {
  const AppKeyboardShortcuts({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS):
            const SaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape):
            const DismissIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const NewItemIntent(),
      },
      child: Actions(
        actions: {
          SaveIntent:    CallbackAction<SaveIntent>(onInvoke: (_) => _onSave(context)),
          DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) => _onDismiss(context)),
          NewItemIntent: CallbackAction<NewItemIntent>(onInvoke: (_) => _onNew(context)),
        },
        child: child,
      ),
    );
  }
}
```

### 6.5 POS Terminal (S4) Specific Rules

- **Portrait POS (Sunmi T2 / PAX series):** treat as `compact`. Use `ScreenClass.compact` overrides. Larger buttons (min 56px), high-contrast theme, no hover states.
- **Landscape POS / Kiosk:** use a fixed `Row`-based layout with an action panel on the right (cart/summary) and product grid on the left. Do not use standard navigation shell.
- **No system back button reliance** — POS apps must have explicit in-app back/cancel controls because some POS hardware has no capacitive back button.
- **Lock orientation** when deploying to POS:
  ```dart
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  ```
- **Disable text scaling** on POS screens to prevent layout overflow from accessibility font scaling:
  ```dart
  MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaleFactor: 1.0),
    child: child,
  )
  ```

---

## 7. State Management Integration

### 7.1 Architecture Rule

```
UI Layer       → AdaptiveLayout / Widgets (presentation only)
ViewModel      → platform-agnostic (Riverpod / Bloc / Provider)
Repository     → platform-agnostic
Data Sources   → Supabase / SQLite / API
```

No layout decision logic lives inside a ViewModel or Repository. No API calls live in a widget `build()` method.

### 7.2 Screen State with Responsive Awareness

```dart
// Responsive state selectors: same ViewModel, different UI
class ProductListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productListProvider);
    return AdaptiveLayout(
      mobile:  (_) => ProductListView(products: products),
      tablet:  (_) => ProductGridView(products: products, columns: 2),
      desktop: (_) => ProductGridView(products: products, columns: 4),
    );
  }
}
```

---

## 8. Theme System

### 8.1 Dual Theme Setup (Light + Dark)

```dart
// lib/core/design/app_theme.dart

class AppTheme {
  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A73E8), // replace with project seed
      brightness: Brightness.light,
    ),
    // Agent: do NOT hardcode colors in widgets. Always use colorScheme tokens.
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A73E8),
      brightness: Brightness.dark,
    ),
  );
}

// In MaterialApp:
MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: ThemeMode.system, // respects OS setting
);
```

### 8.2 Color Usage Rule

```dart
// CORRECT — semantic color tokens
Container(color: Theme.of(context).colorScheme.surface)
Text('Hello', style: TextStyle(color: Theme.of(context).colorScheme.onSurface))

// WRONG — hardcoded colors
Container(color: Colors.white)
Text('Hello', style: TextStyle(color: Colors.black87))
```

---

## 9. Image & Asset Handling

### 9.1 Responsive Images

```dart
// lib/core/widgets/responsive_image.dart

class ResponsiveImage extends StatelessWidget {
  const ResponsiveImage({super.key, required this.asset, this.fit = BoxFit.cover});
  final String asset;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (_, constraints) {
      return Image.asset(
        asset,
        width: constraints.maxWidth,
        fit: fit,
        // Use higher-res variant on retina / large screens
        scale: MediaQuery.of(context).devicePixelRatio > 2.0 ? 0.5 : 1.0,
      );
    });
  }
}
```

### 9.2 Icon Sizing

```dart
abstract class AppIconSize {
  static const double sm  = 16.0;
  static const double md  = 24.0;  // Material default
  static const double lg  = 32.0;
  static const double xl  = 48.0;  // POS / hero icons

  static double forScreen(ScreenClass sc) => switch (sc) {
    ScreenClass.compact   => lg,    // POS: always larger
    ScreenClass.mobile    => md,
    ScreenClass.tablet    => md,
    ScreenClass.desktop   => md,
    ScreenClass.ultraWide => lg,
  };
}
```

---

## 10. Performance Rules

### 10.1 Rebuild Minimization

```dart
// Use const constructors wherever possible
const AppLogo(size: 36);           // CORRECT
AppLogo(size: 36);                  // triggers rebuild unnecessarily

// Avoid building inside build()
// WRONG:
@override
Widget build(BuildContext ctx) {
  final items = _buildItems(); // rebuilds every frame
  return ListView(children: items);
}

// CORRECT: build items once, pass as field or use ListView.builder
ListView.builder(
  itemCount: items.length,
  itemBuilder: (_, i) => ItemWidget(item: items[i]),
);
```

### 10.2 Lazy Loading

```dart
// Always use ListView.builder / GridView.builder for long lists
// Never use ListView(children: [...allItems])

GridView.builder(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3),
  itemCount: products.length,
  itemBuilder: (_, i) => ProductCard(product: products[i]),
);
```

### 10.3 Image Caching

```dart
// Use cached_network_image for all remote images
CachedNetworkImage(
  imageUrl: product.imageUrl,
  placeholder: (_, __) => const ShimmerBox(),
  errorWidget: (_, __, ___) => const PlaceholderAsset(),
);
```

### 10.4 Widget Deduplication Rule

Before creating any new widget, the agent must check `lib/core/widgets/` and `lib/shared/widgets/` for an existing component. Do not create `ProductCardMobile`, `ProductCardTablet`, `ProductCardDesktop` as three separate widgets. Create one `ProductCard` that adapts internally.

---

## 11. File & Folder Structure

```
lib/
├── core/
│   ├── layout/
│   │   ├── adaptive_layout.dart       ← Primary adaptive widget
│   │   ├── app_shell.dart             ← Navigation shell
│   │   ├── breakpoints.dart
│   │   ├── screen_class.dart
│   │   ├── responsive_grid.dart
│   │   ├── master_detail_layout.dart
│   │   ├── responsive_form.dart
│   │   ├── constrained_content.dart
│   │   └── adaptive_dialog.dart
│   ├── design/
│   │   ├── app_theme.dart
│   │   ├── spacing.dart
│   │   └── typography.dart
│   └── platform/
│       ├── input_detector.dart
│       └── keyboard_shortcuts.dart
├── shared/
│   ├── widgets/                       ← Reusable adaptive widgets
│   ├── models/
│   ├── repositories/
│   └── services/
├── features/
│   └── [feature_name]/
│       ├── data/
│       ├── domain/
│       └── presentation/
│           ├── screens/               ← One screen file per feature
│           ├── widgets/               ← Feature-specific widgets
│           └── [feature]_viewmodel.dart
└── main.dart
```

> **Agent Rule:** One screen file per feature. Never create `mobile_product_screen.dart` + `desktop_product_screen.dart`. Use `AdaptiveLayout` inside a single `product_screen.dart`.

---

## 12. New Screen Checklist (Agent Must Complete Before Marking Done)

Every screen submitted by the agent must pass this checklist:

```
[ ] Wrapped in AdaptiveLayout with mobile, tablet, and desktop builders
[ ] Uses LayoutBuilder — no raw MediaQuery width checks in build()
[ ] No hardcoded pixel widths or heights (except icon/asset sizes)
[ ] Navigation integrates with AppShell — no standalone Scaffold navigation
[ ] Theme colors only from Theme.of(context).colorScheme
[ ] Supports Light Mode and Dark Mode
[ ] Touch targets ≥ 48px (≥ 56px on POS surfaces)
[ ] All interactive elements have Semantics or tooltip
[ ] Lists use ListView.builder or GridView.builder (not .children[])
[ ] Images use ResponsiveImage or CachedNetworkImage
[ ] Dialogs use showAdaptiveAppDialog()
[ ] Forms use ResponsiveForm
[ ] Tables use ResponsiveDataTable
[ ] Tested at widths: 360, 600, 768, 1024, 1280, 1920
[ ] No logic (API calls, business rules) inside build() method
[ ] ViewModel / state is platform-agnostic
[ ] const constructors used wherever possible
```

---

## 13. Prohibited Patterns

The agent must never produce the following:

```dart
// ❌ Fixed widths
Container(width: 375)
SizedBox(width: 400)

// ❌ Raw MediaQuery in layout decisions
if (MediaQuery.of(context).size.width < 600) { ... }

// ❌ Platform checks for UI layout
if (Platform.isAndroid) { ... }
if (kIsWeb) { showWebLayout(); }   // use LayoutBuilder instead

// ❌ Separate screen files per platform
mobile_home_screen.dart
desktop_home_screen.dart

// ❌ Hardcoded colors
color: Colors.blue
color: Color(0xFF1A73E8)           // in widget — must be in theme

// ❌ Rebuild-heavy patterns
ListView(children: items.map(...).toList())   // on long lists

// ❌ Ignoring safe areas
Scaffold(body: MyContent())        // without SafeArea on notched devices
// CORRECT:
Scaffold(body: SafeArea(child: MyContent()))
```

---

## 14. Testing Targets

| Test Type | Widths to Verify |
|-----------|-----------------|
| Unit tests | n/a |
| Widget tests | 360, 600, 768, 1024, 1440 |
| Integration tests | All 5 widths on physical/emulated device |
| POS-specific | 1080×1920 portrait, 1920×1080 landscape |
| Accessibility | TalkBack (Android), VoiceOver (iOS), keyboard-only (desktop) |

```dart
// Widget test scaffold for adaptive testing
testWidgets('HomeScreen renders on tablet', (tester) async {
  tester.binding.window.physicalSizeTestValue = const Size(768, 1024);
  tester.binding.window.devicePixelRatioTestValue = 1.0;
  addTearDown(tester.binding.window.clearPhysicalSizeTestValue);

  await tester.pumpWidget(const MyApp());
  await tester.pumpAndSettle();

  expect(find.byType(NavigationRail), findsOneWidget);
  expect(find.byType(NavigationBar), findsNothing);
});
```

---

*End of Flutter Adaptive Layout Agent Standards — v1.0*
*All screens, pages, dialogs, forms, widgets, and components built in this codebase are bound by these standards without exception.*
