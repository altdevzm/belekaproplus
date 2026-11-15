import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/restaurant_provider.dart';
import 'package:beleka_pos/services/restaurant_service.dart';

class KitchenDisplayScreen extends ConsumerStatefulWidget {
  const KitchenDisplayScreen({super.key});

  @override
  ConsumerState<KitchenDisplayScreen> createState() =>
      _KitchenDisplayScreenState();
}

class _KitchenDisplayScreenState extends ConsumerState<KitchenDisplayScreen> {
  int? _selectedStationId;
  String _statusFilter = 'ACTIVE'; // ACTIVE | READY | SERVED
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandColor = theme.colorScheme.primary;
    final stations = ref.watch(kitchenStationsProvider).valueOrNull ?? [];
    final ordersAsync = ref.watch(activeRestaurantOrdersProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Professional Header Bar
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
                runSpacing: 14,
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
                          Icons.soup_kitchen_rounded,
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
                              'Kitchen Display System',
                              style: GoogleFonts.manrope(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Station ticket routing, live prep timers & bump controls',
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<String>(
                      style: ButtonStyle(
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                      segments: const [
                        ButtonSegment(
                          value: 'ACTIVE',
                          icon: Icon(Icons.local_fire_department_rounded, size: 18),
                          label: Text('Active Queue'),
                        ),
                        ButtonSegment(
                          value: 'READY',
                          icon: Icon(Icons.notifications_active_rounded, size: 18),
                          label: Text('Ready'),
                        ),
                        ButtonSegment(
                          value: 'SERVED',
                          icon: Icon(Icons.done_all_rounded, size: 18),
                          label: Text('Served'),
                        ),
                      ],
                      selected: {_statusFilter},
                      onSelectionChanged: (s) =>
                          setState(() => _statusFilter = s.first),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Station Filter Pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _stationChip(
                    label: 'All Stations',
                    selected: _selectedStationId == null,
                    brandColor: brandColor,
                    onTap: () => setState(() => _selectedStationId = null),
                  ),
                  const SizedBox(width: 10),
                  ...stations.map(
                    (stn) => Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _stationChip(
                        label: stn.name,
                        selected: _selectedStationId == stn.id,
                        brandColor: brandColor,
                        onTap: () =>
                            setState(() => _selectedStationId = stn.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Ticket Grid
            Expanded(
              child: ordersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error loading KDS: $e')),
                data: (orders) {
                  final submitted = orders
                      .where((o) => o.status != RestaurantOrderStatus.draft)
                      .toList();
                  if (submitted.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 64,
                            color: const Color(0xFF10B981).withValues(alpha: 0.6),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'All Caught Up — Kitchen Queue is Clear',
                            style: GoogleFonts.manrope(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 430,
                      mainAxisExtent: 430,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: submitted.length,
                    itemBuilder: (context, idx) {
                      return _KitchenTicketCard(
                        order: submitted[idx],
                        selectedStationId: _selectedStationId,
                        statusFilter: _statusFilter,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stationChip({
    required String label,
    required bool selected,
    required Color brandColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? brandColor.withValues(alpha: 0.18)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? brandColor
                : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
            width: selected ? 1.6 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: selected
                ? brandColor
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _KitchenTicketCard extends ConsumerWidget {
  const _KitchenTicketCard({
    required this.order,
    required this.selectedStationId,
    required this.statusFilter,
  });

  final RestaurantOrder order;
  final int? selectedStationId;
  final String statusFilter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final svc = ref.watch(restaurantServiceProvider);

    return StreamBuilder<List<RestaurantOrderItem>>(
      stream: svc.watchOrderItems(order.id),
      builder: (context, snap) {
        final allItems = snap.data ?? [];
        final filteredItems = allItems.where((item) {
          if (item.kitchenStatus == KitchenItemStatus.cancelled) {
            return false;
          }
          if (selectedStationId != null &&
              item.kitchenStationId != selectedStationId) {
            return false;
          }
          if (statusFilter == 'ACTIVE') {
            return item.kitchenStatus == KitchenItemStatus.newTicket ||
                item.kitchenStatus == KitchenItemStatus.accepted ||
                item.kitchenStatus == KitchenItemStatus.preparing;
          } else if (statusFilter == 'READY') {
            return item.kitchenStatus == KitchenItemStatus.ready;
          } else {
            return item.kitchenStatus == KitchenItemStatus.served;
          }
        }).toList();

        if (filteredItems.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.15),
              ),
            ),
            child: Center(
              child: Text(
                '${order.tableName ?? 'Takeaway'} • ${order.orderNumber}\nNo items in "$statusFilter" view',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        final startedAt = order.submittedAt ?? order.createdAt;
        final elapsedMins = DateTime.now().difference(startedAt).inMinutes;
        const maxPrep = 15;
        final timerColor = elapsedMins >= maxPrep
            ? const Color(0xFFEF4444)
            : (elapsedMins >= 10
                ? const Color(0xFFF59E0B)
                : const Color(0xFF10B981));

        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: timerColor.withValues(alpha: 0.6),
              width: 1.8,
            ),
          ),
          child: Column(
            children: [
              // Ticket Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: timerColor.withValues(alpha: 0.14),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(14),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      order.tableName != null
                          ? Icons.table_restaurant_rounded
                          : Icons.shopping_bag_rounded,
                      color: timerColor,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            order.tableName != null
                                ? '${order.tableName} • ${order.orderNumber}'
                                : 'Takeaway ${order.orderNumber}',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            'Staff: ${order.waiterName ?? 'Staff'}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: timerColor.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 15, color: timerColor),
                          const SizedBox(width: 4),
                          Text(
                            '${elapsedMins}m',
                            style: GoogleFonts.ibmPlexMono(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: timerColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Item List with Large Action Buttons
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(14),
                  itemCount: filteredItems.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (_, idx) {
                    final item = filteredItems[idx];
                    final mods =
                        RestaurantService.decodeModifiers(item.modifiersJson);
                    final nextAction = _nextActionFor(item.kitchenStatus);

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${item.quantity}x',
                            style: GoogleFonts.ibmPlexMono(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                style: GoogleFonts.manrope(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                              if (mods.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Text(
                                    '+ ${mods.map((m) => m['name']).join(', ')}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.amber,
                                    ),
                                  ),
                                ),
                              if (item.specialInstructions != null &&
                                  item.specialInstructions!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'Note: ${item.specialInstructions}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: Colors.lightBlueAccent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (nextAction != null)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: nextAction.$3,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              svc.updateKitchenItemStatus(
                                itemId: item.id,
                                nextStatus: nextAction.$2,
                              );
                            },
                            icon: Icon(nextAction.$4, size: 16),
                            label: Text(
                              nextAction.$1,
                              style: GoogleFonts.manrope(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),

              // Ticket-Wide Bump Footer
              if (statusFilter != 'SERVED')
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: statusFilter == 'ACTIVE'
                            ? const Color(0xFF10B981)
                            : const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        final target = statusFilter == 'ACTIVE'
                            ? KitchenItemStatus.ready
                            : KitchenItemStatus.served;
                        for (final item in filteredItems) {
                          await svc.updateKitchenItemStatus(
                            itemId: item.id,
                            nextStatus: target,
                          );
                        }
                      },
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: Text(
                        statusFilter == 'ACTIVE'
                            ? 'MARK ALL READY'
                            : 'MARK ALL SERVED',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  (String, KitchenItemStatus, Color, IconData)? _nextActionFor(
    KitchenItemStatus status,
  ) {
    return switch (status) {
      KitchenItemStatus.newTicket => (
          'Accept',
          KitchenItemStatus.accepted,
          const Color(0xFF3B82F6),
          Icons.thumb_up_alt_rounded,
        ),
      KitchenItemStatus.accepted => (
          'Cook',
          KitchenItemStatus.preparing,
          const Color(0xFFF59E0B),
          Icons.local_fire_department_rounded,
        ),
      KitchenItemStatus.preparing => (
          'Ready',
          KitchenItemStatus.ready,
          const Color(0xFF10B981),
          Icons.check_circle_rounded,
        ),
      KitchenItemStatus.ready => (
          'Serve',
          KitchenItemStatus.served,
          const Color(0xFF8B5CF6),
          Icons.room_service_rounded,
        ),
      KitchenItemStatus.served || KitchenItemStatus.cancelled => null,
    };
  }
}
