// lib/core/layout/responsive_table.dart

import 'package:flutter/material.dart';
import 'adaptive_layout.dart';

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
    required this.rowBuilder,
  });

  final List<T> rows;
  final List<DataColumn> desktopColumns;
  final List<DataColumn> tabletColumns;
  final Widget Function(T row) mobileCardBuilder;
  final DataRow Function(T row) rowBuilder;

  @override
  Widget build(BuildContext context) {
    return AdaptiveLayout(
      mobile: (_) => ListView.separated(
        itemCount: rows.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) => mobileCardBuilder(rows[i]),
      ),
      tablet: (_) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: tabletColumns,
          rows: rows.map(rowBuilder).toList(),
        ),
      ),
      desktop: (_) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: desktopColumns,
          rows: rows.map(rowBuilder).toList(),
        ),
      ),
    );
  }
}
