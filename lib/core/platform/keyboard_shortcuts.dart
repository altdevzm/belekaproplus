// lib/core/platform/keyboard_shortcuts.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class QuickSearchIntent extends Intent {
  const QuickSearchIntent();
}

class NewSaleIntent extends Intent {
  const NewSaleIntent();
}

class DismissModalIntent extends Intent {
  const DismissModalIntent();
}

/// Wraps the application root with standard desktop/web POS shortcuts
class AppKeyboardShortcuts extends StatelessWidget {
  const AppKeyboardShortcuts({
    super.key,
    required this.child,
    this.onQuickSearch,
    this.onNewSale,
    this.onDismiss,
  });

  final Widget child;
  final VoidCallback? onQuickSearch;
  final VoidCallback? onNewSale;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF): const QuickSearchIntent(),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN): const NewSaleIntent(),
        LogicalKeySet(LogicalKeyboardKey.escape): const DismissModalIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          QuickSearchIntent: CallbackAction<QuickSearchIntent>(
            onInvoke: (_) {
              onQuickSearch?.call();
              return null;
            },
          ),
          NewSaleIntent: CallbackAction<NewSaleIntent>(
            onInvoke: (_) {
              onNewSale?.call();
              return null;
            },
          ),
          DismissModalIntent: CallbackAction<DismissModalIntent>(
            onInvoke: (_) {
              onDismiss?.call();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
