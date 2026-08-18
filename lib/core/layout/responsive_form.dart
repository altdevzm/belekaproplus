// lib/core/layout/responsive_form.dart

import 'package:flutter/material.dart';
import 'screen_class.dart';
import '../design/spacing.dart';

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
        ScreenClass.tablet => 2,
        _ => 3,
      };
      if (cols == 1) {
        return Column(
          children: fields
              .map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: f,
                  ))
              .toList(),
        );
      }
      // Wrap into rows of `cols`
      final rows = <Widget>[];
      for (var i = 0; i < fields.length; i += cols) {
        final rowFields = fields.sublist(i, (i + cols).clamp(0, fields.length));
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rowFields
              .map((f) => Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: rowFields.last == f ? 0 : AppSpacing.md,
                        bottom: AppSpacing.md,
                      ),
                      child: f,
                    ),
                  ))
              .toList(),
        ));
      }
      return Column(children: rows);
    });
  }
}
