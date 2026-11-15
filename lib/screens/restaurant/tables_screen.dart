import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/restaurant_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/screens/restaurant/restaurant_modal_widgets.dart';
import 'package:beleka_pos/screens/shell_screen.dart';
import 'package:beleka_pos/services/restaurant_service.dart';

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key});

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  String _selectedSection = 'ALL';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandColor = theme.colorScheme.primary;
    final tablesAsync = ref.watch(restaurantTablesProvider);
    final ordersAsync = ref.watch(activeRestaurantOrdersProvider);
    final isManager = ref.watch(isManagerProvider);
    final config = ref.watch(storeConfigProvider).valueOrNull;
    final currency = config?.currencySymbol ?? 'ZK';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.18),
                ),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: brandColor.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.table_restaurant_rounded,
                          color: brandColor,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Floor Plan & Tables',
                              style: GoogleFonts.manrope(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Tap any table to seat guests, manage orders, transfer or merge bills',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (isManager)
                    ElevatedButton.icon(
                      onPressed: () => _showTableEditorDialog(context),
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('Add Table'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandColor,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            tablesAsync.when(
              loading: () => const Expanded(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Expanded(
                child: Center(child: Text('Error loading tables: $e')),
              ),
              data: (tables) {
                final orders = ordersAsync.valueOrNull ?? [];
                final orderById = {for (final o in orders) o.id: o};
                final sections = <String>{
                  'ALL',
                  ...tables.map((t) => t.section),
                }.toList();

                final filtered = _selectedSection == 'ALL'
                    ? tables
                    : tables
                        .where((t) => t.section == _selectedSection)
                        .toList();

                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: sections.map((sec) {
                                  final selected = sec == _selectedSection;
                                  return Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: InkWell(
                                      onTap: () =>
                                          setState(() => _selectedSection = sec),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 18,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? brandColor.withValues(alpha: 0.18)
                                              : theme.colorScheme.surface,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: selected
                                                ? brandColor
                                                : theme.colorScheme.outline
                                                    .withValues(alpha: 0.25),
                                          ),
                                        ),
                                        child: Text(
                                          sec,
                                          style: GoogleFonts.manrope(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: selected
                                                ? brandColor
                                                : theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        children: RestaurantTableStatus.values.map((s) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _statusColor(s),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _statusLabel(s),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      if (filtered.isEmpty)
                        Expanded(
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.table_bar_outlined,
                                  size: 64,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No tables configured yet',
                                  style: GoogleFonts.manrope(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  isManager
                                      ? 'Click "Add Table" to build your floor plan.'
                                      : 'Ask a manager to configure restaurant tables.',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Expanded(
                          child: GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 310,
                              mainAxisExtent: 235,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final table = filtered[index];
                              final activeOrder = table.activeOrderId != null
                                  ? orderById[table.activeOrderId!]
                                  : null;
                              return _buildTableCard(
                                context,
                                table,
                                activeOrder,
                                tables,
                                currency,
                                isManager,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard(
    BuildContext context,
    RestaurantTable table,
    RestaurantOrder? activeOrder,
    List<RestaurantTable> allTables,
    String currency,
    bool isManager,
  ) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(table.status);
    final hasSession = table.activeOrderId != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: statusColor.withValues(alpha: hasSession ? 0.75 : 0.35),
          width: hasSession ? 1.8 : 1.1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Status Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _statusLabel(table.status).toUpperCase(),
                  style: GoogleFonts.manrope(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
                const Spacer(),
                Text(
                  '${table.capacity} seats',
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (isManager)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz, size: 20),
                    onSelected: (action) => _handleTableAction(
                      action,
                      table,
                      allTables,
                      isManager,
                    ),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit Table'),
                      ),
                      if (!hasSession)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete Table',
                            style: TextStyle(color: Colors.redAccent),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),

          // Table Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          table.name,
                          style: GoogleFonts.manrope(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasSession && activeOrder != null)
                        Text(
                          '$currency ${activeOrder.totalAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.ibmPlexMono(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    table.section,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (hasSession && activeOrder != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${activeOrder.orderNumber}  •  Waiter: ${table.assignedWaiterName ?? 'Staff'}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const Spacer(),

                  // Large Touch-Friendly Action Row
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasSession
                                ? statusColor
                                : theme.colorScheme.primary,
                            foregroundColor:
                                hasSession ? Colors.white : Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => _onTableTap(table),
                          icon: Icon(
                            hasSession
                                ? Icons.receipt_long_rounded
                                : Icons.play_arrow_rounded,
                            size: 18,
                          ),
                          label: Text(
                            hasSession ? 'Open Order' : 'Seat & Order',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Assign Waiter',
                        onPressed: () => _handleTableAction(
                          'waiter',
                          table,
                          allTables,
                          isManager,
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      ),
                      if (hasSession) ...[
                        const SizedBox(width: 4),
                        IconButton.outlined(
                          tooltip: 'Transfer Table',
                          onPressed: () => _handleTableAction(
                            'transfer',
                            table,
                            allTables,
                            isManager,
                          ),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        ),
                        const SizedBox(width: 4),
                        IconButton.outlined(
                          tooltip: 'Merge Into Table',
                          onPressed: () => _handleTableAction(
                            'merge',
                            table,
                            allTables,
                            isManager,
                          ),
                          icon: const Icon(Icons.merge_type_rounded, size: 18),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onTableTap(RestaurantTable table) async {
    final user = ref.read(authProvider);
    final svc = ref.read(restaurantServiceProvider);
    final order = await svc.openTableSession(
      table: table,
      waiterId: user?.id,
      waiterName: user?.name ?? 'Staff',
    );
    ref.read(selectedRestaurantOrderIdProvider.notifier).state = order.id;
    ref.read(navigationProvider.notifier).state = ScreenType.restaurantOrders;
  }

  Future<void> _handleTableAction(
    String action,
    RestaurantTable table,
    List<RestaurantTable> allTables,
    bool isManager,
  ) async {
    final svc = ref.read(restaurantServiceProvider);
    if (action == 'open') {
      await _onTableTap(table);
    } else if (action == 'waiter') {
      await _showAssignWaiterDialog(table);
    } else if (action == 'transfer') {
      final candidates = allTables
          .where((t) => t.id != table.id && t.activeOrderId == null)
          .toList();
      await _showTargetTableDialog(
        title: 'Transfer ${table.name} to:',
        candidates: candidates,
        onConfirm: (target) async {
          final err = await svc.transferTable(
            fromTableId: table.id,
            toTableId: target.id,
          );
          if (mounted && err != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(err), backgroundColor: Colors.redAccent),
            );
          }
        },
      );
    } else if (action == 'merge') {
      final candidates = allTables
          .where((t) => t.id != table.id && t.activeOrderId != null)
          .toList();
      await _showTargetTableDialog(
        title: 'Merge ${table.name} into:',
        candidates: candidates,
        onConfirm: (target) async {
          final err = await svc.mergeTables(
            sourceTableId: table.id,
            targetTableId: target.id,
          );
          if (mounted && err != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(err), backgroundColor: Colors.redAccent),
            );
          }
        },
      );
    } else if (action == 'edit' && isManager) {
      await _showTableEditorDialog(context, existing: table);
    } else if (action == 'delete' && isManager) {
      final ok = await svc.deleteTable(table.id);
      if (mounted && !ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot delete a table with an active session.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _showAssignWaiterDialog(RestaurantTable table) async {
    final users = ref.read(allUsersProvider).valueOrNull ?? [];
    if (users.isEmpty) {
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => RestaurantModalShell(
        icon: Icons.person_add_alt_1_rounded,
        title: 'Assign Waiter',
        subtitle: 'Select staff member for ${table.name}',
        width: 440,
        child: Column(
          children: users.map((u) {
            final isAssigned = table.assignedWaiterId == u.id;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: isAssigned
                    ? Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.12)
                    : Theme.of(ctx)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isAssigned
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(
                  u.name,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(u.role.toUpperCase()),
                trailing: isAssigned
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                onTap: () async {
                  await ref.read(restaurantServiceProvider).assignWaiterToTable(
                        table: table,
                        waiterId: u.id,
                        waiterName: u.name,
                      );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showTargetTableDialog({
    required String title,
    required List<RestaurantTable> candidates,
    required Future<void> Function(RestaurantTable) onConfirm,
  }) async {
    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No eligible tables available.')),
        );
      }
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => RestaurantModalShell(
        icon: Icons.swap_horiz_rounded,
        title: title,
        subtitle: 'Choose destination table',
        width: 440,
        child: Column(
          children: candidates.map((t) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Theme.of(ctx)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      Theme.of(ctx).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: ListTile(
                leading: const Icon(Icons.table_restaurant_rounded),
                title: Text(
                  t.name,
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('${t.section} • ${t.capacity} seats'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 15),
                onTap: () async {
                  Navigator.pop(ctx);
                  await onConfirm(t);
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _showTableEditorDialog(
    BuildContext context, {
    RestaurantTable? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final sectionCtrl = TextEditingController(
      text: existing?.section ?? 'Main Hall',
    );
    final capCtrl = TextEditingController(
      text: (existing?.capacity ?? 4).toString(),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => RestaurantModalShell(
        icon: Icons.table_restaurant_rounded,
        title: existing == null ? 'Add Table' : 'Edit Table',
        subtitle: 'Configure table name, floor section & seating capacity',
        width: 460,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Save Table'),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildModalFieldLabel(ctx, 'Table Name / Number'),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: restaurantInputDecoration(
                ctx,
                hintText: 'e.g. Table 1, VIP-A',
              ),
            ),
            const SizedBox(height: 16),
            buildModalFieldLabel(ctx, 'Section / Floor'),
            TextField(
              controller: sectionCtrl,
              decoration: restaurantInputDecoration(
                ctx,
                hintText: 'e.g. Main Hall, Patio, VIP',
              ),
            ),
            const SizedBox(height: 16),
            buildModalFieldLabel(ctx, 'Seating Capacity'),
            TextField(
              controller: capCtrl,
              keyboardType: TextInputType.number,
              decoration: restaurantInputDecoration(ctx, hintText: '4'),
            ),
          ],
        ),
      ),
    );

    if (saved == true && nameCtrl.text.trim().isNotEmpty) {
      final svc = ref.read(restaurantServiceProvider);
      final branchCode = ref.read(activeRestaurantBranchProvider);
      final table = existing ?? RestaurantTable(name: nameCtrl.text.trim());
      table.name = nameCtrl.text.trim();
      table.section = sectionCtrl.text.trim().isEmpty
          ? 'Main Hall'
          : sectionCtrl.text.trim();
      table.capacity = int.tryParse(capCtrl.text.trim()) ?? 4;
      table.branchCode = branchCode;
      await svc.saveTable(table);
    }

    nameCtrl.dispose();
    sectionCtrl.dispose();
    capCtrl.dispose();
  }

  Color _statusColor(RestaurantTableStatus s) {
    return switch (s) {
      RestaurantTableStatus.available => const Color(0xFF10B981),
      RestaurantTableStatus.occupied => const Color(0xFF3B82F6),
      RestaurantTableStatus.ordering => const Color(0xFFF59E0B),
      RestaurantTableStatus.served => const Color(0xFF8B5CF6),
      RestaurantTableStatus.billing => const Color(0xFFEF4444),
      RestaurantTableStatus.reserved => const Color(0xFF06B6D4),
    };
  }

  String _statusLabel(RestaurantTableStatus s) {
    return switch (s) {
      RestaurantTableStatus.available => 'Available',
      RestaurantTableStatus.occupied => 'Occupied',
      RestaurantTableStatus.ordering => 'Ordering',
      RestaurantTableStatus.served => 'Served',
      RestaurantTableStatus.billing => 'Billing',
      RestaurantTableStatus.reserved => 'Reserved',
    };
  }
}
