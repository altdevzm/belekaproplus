import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/local_sql_service.dart';
import 'package:beleka_pos/services/api_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:beleka_pos/services/printer_service.dart';
import 'package:beleka_pos/services/license_service.dart';
import 'package:beleka_pos/screens/settings/license_info_modal.dart';
import 'package:beleka_pos/utils/formatters.dart';

// --- DATA PROVIDERS ---

final cashShiftsProvider = FutureProvider<List<CashShift>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.cashShifts.where().sortByOpeningTimeDesc().findAll();
});

final activeShiftProvider = FutureProvider<CashShift?>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.cashShifts.filter().statusEqualTo('OPEN').findFirst();
});

final activeShiftsListProvider = FutureProvider<List<CashShift>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.cashShifts.filter().statusEqualTo('OPEN').findAll();
});

final paymentAccountsProvider = FutureProvider<List<PaymentAccount>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.paymentAccounts.where().sortByCreatedAt().findAll();
});

final refundsProvider = FutureProvider<List<RefundTransaction>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.refundTransactions.where().sortByRefundDateDesc().findAll();
});

class TerminalsScreen extends ConsumerStatefulWidget {
  const TerminalsScreen({super.key});

  @override
  ConsumerState<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends ConsumerState<TerminalsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildTopBreadcrumbBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              'Workspace',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
            Text(
              'Tills & Cashier Terminals',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF059669),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Master POS Host Hub Live',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 13, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('E, MMM d, yyyy').format(DateTime.now()),
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final isOwner = ref.watch(isOwnerProvider);
    final currentUser = ref.watch(authProvider);
    final storeConfig = ref.watch(storeConfigProvider).value;
    final currency = storeConfig?.currencySymbol ?? 'K';
    final allTerminals = ref.watch(posTerminalsProvider).value ?? [];
    final apiService = ref.watch(apiServiceProvider);

    final String? effectiveBranchCode = !isOwner
        ? (storeConfig?.bhfId.isNotEmpty == true ? storeConfig!.bhfId : (currentUser?.branchCode ?? '00'))
        : null;

    final terminals = effectiveBranchCode != null
        ? allTerminals.where((t) => t.branchCode == effectiveBranchCode || t.digitaxBhfId == effectiveBranchCode).toList()
        : allTerminals;

    final branches = ref.watch(storeBranchesProvider).value ?? [];
    final users = ref.watch(allUsersProvider).value ?? [];
    final activeShifts = ref.watch(activeShiftsListProvider).value ?? [];

    final activeTerminalsCount = terminals.where((t) => t.status == 'ACTIVE').length;
    final totalSalesToday = terminals.fold(0.0, (sum, t) => sum + t.salesToday);

    final activeLicense = ref.watch(licenseServiceProvider).activeLicense;
    final maxAllowedTills = activeLicense?.maxTills ?? 3;

    final hostIp = apiService.hostIp ?? '127.0.0.1';
    final hostPort = apiService.port;

    return LayoutBuilder(
      builder: (context, rootConstraints) {
        final isPhone = rootConstraints.maxWidth < 700;
    return Padding(
      padding: EdgeInsets.all(isPhone ? 14 : 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb Bar
          _buildTopBreadcrumbBar(context),
          const SizedBox(height: 16),

          // Header Bar – responsive
          if (isPhone) ...
            [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TILLS & CASHIER TERMINALS',
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monitor registers, shifts and reconcile till floats.',
                    style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditTerminalDialog(context, primaryColor, branches, users),
                    icon: const Icon(Icons.add_to_queue_rounded, size: 16),
                    label: Text('+ Pre-Authorize Till', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ]
          else ...
            [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TILLS & CASHIER TERMINALS MANAGEMENT',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Monitor connected cashier registers, assign cashier shifts, generate per-till PDF reports, and balance till floats.',
                          style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditTerminalDialog(context, primaryColor, branches, users),
                        icon: const Icon(Icons.add_to_queue_rounded, size: 18),
                        label: Text('+ Pre-Authorize Till', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          const SizedBox(height: 16),

          // Master POS Host Hub Status Card
          _buildMasterHubBanner(context, storeConfig, hostIp, hostPort, primaryColor),
          const SizedBox(height: 16),

          // Tab Bar for Terminals vs Shift Balancing
          Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151F32) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: primaryColor,
              indicatorWeight: 3,
              labelColor: primaryColor,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: [
                Tab(
                  icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                  text: 'Tills & Cashier Terminals (${terminals.length})',
                ),
                Tab(
                  icon: const Icon(Icons.calculate_rounded, size: 18),
                  text: 'Till & Shift Balancing (${activeShifts.length} Active)',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: TILLS & CASHIER TERMINALS
                _buildTillsTab(
                  context: context,
                  terminals: terminals,
                  maxAllowedTills: maxAllowedTills,
                  activeTerminalsCount: activeTerminalsCount,
                  activeShifts: activeShifts,
                  branches: branches,
                  users: users,
                  totalSalesToday: totalSalesToday,
                  currency: currency,
                  accentColor: primaryColor,
                  apiService: apiService,
                  hostIp: hostIp,
                  hostPort: hostPort,
                ),

                // TAB 2: TILL & SHIFT BALANCING
                _buildShiftBalancingTab(
                  context: context,
                  terminals: terminals,
                  users: users,
                  activeShifts: activeShifts,
                  currency: currency,
                  accentColor: primaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    },
  );
  }

  // =========================================================================
  // TAB 1: TILLS & CASHIER TERMINALS
  // =========================================================================
  Widget _buildTillsTab({
    required BuildContext context,
    required List<PosTerminal> terminals,
    required int maxAllowedTills,
    required int activeTerminalsCount,
    required List<CashShift> activeShifts,
    required List<StoreBranch> branches,
    required List<User> users,
    required double totalSalesToday,
    required String currency,
    required Color accentColor,
    required ApiService apiService,
    required String hostIp,
    required int hostPort,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Column(
      children: [
        // KPI Stats Overview Bar – responsive 2x2 on phones
        LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 700;
            final card1 = Expanded(child: _buildMetricCard(title: 'CONNECTED TILLS', value: '${terminals.length} / $maxAllowedTills', subtitle: '$activeTerminalsCount Active (Max $maxAllowedTills on License)', icon: Icons.point_of_sale_rounded, color: primaryColor));
            final card2 = Expanded(child: _buildMetricCard(title: 'ACTIVE SHIFT TILLS', value: '${activeShifts.length}', subtitle: '${activeShifts.length} Cashiers Live On Shift', icon: Icons.person_pin_circle_rounded, color: const Color(0xFF059669)));
            final card3 = Expanded(child: _buildMetricCard(title: 'CONNECTED BRANCHES', value: '${branches.length}', subtitle: 'ZRA Fiscal Branches Linked', icon: Icons.storefront_rounded, color: const Color(0xFF0284C7)));
            final card4 = Expanded(child: _buildMetricCard(title: 'TERMINAL SALES TODAY', value: CurrencyFormatter.format(totalSalesToday, currency), subtitle: 'Aggregate Live Till Revenue', icon: Icons.payments_rounded, color: const Color(0xFFD97706)));
            if (narrow) {
              return Column(
                children: [
                  Row(children: [card1, const SizedBox(width: 16), card2]),
                  const SizedBox(height: 14),
                  Row(children: [card3, const SizedBox(width: 16), card4]),
                ],
              );
            }
            return Row(
              children: [
                card1,
                const SizedBox(width: 16),
                card2,
                const SizedBox(width: 16),
                card3,
                const SizedBox(width: 16),
                card4,
              ],
            );
          },
        ),
        const SizedBox(height: 20),

        // Terminals Grid / List
        Expanded(
          child: terminals.isEmpty
              ? _buildEmptyTillsState(context, hostIp, hostPort, primaryColor, branches, users)
              : GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 450,
                    mainAxisExtent: 310,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: terminals.length,
                  itemBuilder: (context, index) {
                    final t = terminals[index];
                    final isLiveConnected = apiService.activeTerminals.containsKey(t.terminalCode) ||
                        DateTime.now().difference(t.lastActive).inMinutes < 5;
                    final matchingShift = activeShifts.where((s) =>
                        s.terminalId == '${t.terminalCode} - ${t.name}' ||
                        s.terminalId == t.terminalCode ||
                        s.terminalId == t.name).firstOrNull;
                    final isShiftOpen = matchingShift != null;
                    final isActive = t.status == 'ACTIVE';

                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF151F32) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isShiftOpen
                              ? const Color(0xFF059669)
                              : (isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                          width: isShiftOpen ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Row: Code, Status & Actions Menu
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isShiftOpen
                                          ? const Color(0xFFECFDF5)
                                          : (isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.point_of_sale_rounded,
                                      color: isShiftOpen ? const Color(0xFF059669) : primaryColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.terminalCode.toUpperCase(),
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            t.name,
                                            style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                          ),
                                          if (t.deviceIp != null && t.deviceIp!.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              '• ${t.deviceIp}',
                                              style: GoogleFonts.inter(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isShiftOpen
                                          ? const Color(0xFFECFDF5)
                                          : (isLiveConnected
                                              ? const Color(0xFFECFDF5)
                                              : (isActive
                                                  ? const Color(0xFFEFF6FF)
                                                  : const Color(0xFFFFFBEB))),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isShiftOpen
                                          ? 'LIVE SHIFT'
                                          : (isLiveConnected
                                              ? 'CONNECTED'
                                              : t.status),
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isShiftOpen
                                            ? const Color(0xFF059669)
                                            : (isLiveConnected
                                                ? const Color(0xFF059669)
                                                : (isActive
                                                    ? primaryColor
                                                    : const Color(0xFFD97706))),
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                                    onSelected: (val) async {
                                      if (val == 'report_pdf') {
                                        _generateTillReport(context, t, matchingShift, printDirectly: false);
                                      } else if (val == 'report_print') {
                                        _generateTillReport(context, t, matchingShift, printDirectly: true);
                                      } else if (val == 'edit') {
                                        _showAddEditTerminalDialog(context, primaryColor, branches, users, terminal: t);
                                      } else if (val == 'toggle_status') {
                                        await _toggleTerminalStatus(t);
                                      } else if (val == 'delete') {
                                        await _deleteTerminal(context, t);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'report_pdf',
                                        child: Row(
                                          children: [
                                            Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 16),
                                            SizedBox(width: 8),
                                            Text('Till Report (PDF)'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'report_print',
                                        child: Row(
                                          children: [
                                            Icon(Icons.print_rounded, color: Color(0xFF059669), size: 16),
                                            SizedBox(width: 8),
                                            Text('Print Till Report'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuDivider(),
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.edit_rounded, size: 16),
                                            SizedBox(width: 8),
                                            Text('Edit Till Details'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem(
                                        value: 'toggle_status',
                                        child: Row(
                                          children: [
                                            Icon(Icons.toggle_on_rounded, size: 16),
                                            SizedBox(width: 8),
                                            Text(isActive ? 'Set Inactive' : 'Set Active'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 16),
                                            SizedBox(width: 8),
                                            Text('Delete Till', style: TextStyle(color: Color(0xFFDC2626))),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 16),

                          // Branch & DigiTax bhfId Info
                          Row(
                            children: [
                              Icon(Icons.storefront_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  t.branchName,
                                  style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F9FF),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'ZRA bhfId: ${t.digitaxBhfId}',
                                  style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w600, color: const Color(0xFF0284C7)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Assigned Cashier Info
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: isShiftOpen ? const Color(0xFFECFDF5) : (isDark ? const Color(0xFF151F32) : Colors.white),
                                  child: Icon(Icons.person, size: 14, color: isShiftOpen ? const Color(0xFF059669) : theme.colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isShiftOpen
                                            ? '${matchingShift.cashierName} (Active Shift)'
                                            : (t.assignedCashierName != null && t.assignedCashierName!.isNotEmpty)
                                                ? t.assignedCashierName!
                                                : 'Unassigned Cashier',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: isShiftOpen ? const Color(0xFF059669) : theme.colorScheme.onSurface,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        isShiftOpen
                                            ? 'Shift #: ${matchingShift.shiftNumber}'
                                            : (t.assignedCashierId != null && t.assignedCashierId!.isNotEmpty)
                                                ? 'Assigned ID: ${t.assignedCashierId}'
                                                : 'Cashier can log in directly',
                                        style: GoogleFonts.inter(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),

                          // Bottom Row: Sales Today & Action Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('TILL REVENUE TODAY', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurfaceVariant, letterSpacing: 0.5)),
                                  Text(
                                    CurrencyFormatter.format(t.salesToday, currency),
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => _generateTillReport(context, t, matchingShift, printDirectly: false),
                                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFDC2626)),
                                    tooltip: 'Generate Till Report (PDF)',
                                    splashRadius: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  ElevatedButton.icon(
                                    onPressed: isShiftOpen
                                        ? () => _showCloseShiftModal(context, matchingShift, currency)
                                        : () => _openShiftForTerminal(context, t, users, primaryColor),
                                    icon: Icon(isShiftOpen ? Icons.calculate_rounded : Icons.login_rounded, size: 13),
                                    label: Text(
                                      isShiftOpen ? 'Reconcile' : 'Assign Shift',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isShiftOpen ? const Color(0xFFFEF2F2) : primaryColor,
                                      foregroundColor: isShiftOpen ? const Color(0xFFDC2626) : Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      elevation: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // =========================================================================
  // TAB 2: TILL & SHIFT BALANCING
  // =========================================================================
  Widget _buildShiftBalancingTab({
    required BuildContext context,
    required List<PosTerminal> terminals,
    required List<User> users,
    required List<CashShift> activeShifts,
    required String currency,
    required Color accentColor,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final shifts = ref.watch(cashShiftsProvider).value ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Active Tills Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ACTIVE TILLS & CASHIER SHIFT BALANCING',
                    style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${activeShifts.length} active cashier till${activeShifts.length == 1 ? "" : "s"} currently live on shift',
                    style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showQuickAssignShiftModal(context, terminals, users, primaryColor),
                icon: const Icon(Icons.person_pin_circle_rounded, size: 16),
                label: Text('+ Assign Cashier to a Till', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Active Tills List
          if (activeShifts.isEmpty)
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.point_of_sale_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text('No Active Till Shifts Operating', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('Assign a cashier to a specific till and set their opening float to begin a shift.', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activeShifts.length,
              itemBuilder: (context, index) {
                final shift = activeShifts[index];
                final expectedInDrawer = shift.openingCash + shift.cashSales - shift.cashExpenses - shift.cashRefunds;

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF151F32) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF059669), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0F9FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.point_of_sale_rounded, color: Color(0xFF0284C7), size: 14),
                                    const SizedBox(width: 6),
                                    Text(shift.terminalId.toUpperCase(), style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF0284C7))),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6)),
                                child: Text('SHIFT ACTIVE', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 10, color: const Color(0xFF059669))),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportShiftZReportToPdf(shift, config: config, printDirectly: false);
                                },
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
                                tooltip: 'Export Interim Z-Report PDF',
                              ),
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportShiftZReportToPdf(shift, config: config, printDirectly: true);
                                },
                                icon: Icon(Icons.print_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                                tooltip: 'Print Interim Slip',
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showCloseShiftModal(context, shift, currency),
                                icon: const Icon(Icons.calculate_rounded, size: 16),
                                label: const Text('Reconcile & Close Till'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFDC2626),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                            radius: 18,
                            child: Text(
                              shift.cashierName.isNotEmpty ? shift.cashierName[0].toUpperCase() : 'C',
                              style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Assigned Cashier: ${shift.cashierName} (ID: ${shift.cashierId ?? "1001"})',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface),
                              ),
                              Text(
                                '${shift.branchName} • Opened at ${DateFormat('HH:mm, dd MMM yyyy').format(shift.openingTime)}',
                                style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _buildShiftStat('Opening Float', '$currency ${shift.openingCash.toStringAsFixed(2)}'),
                          const SizedBox(width: 24),
                          _buildShiftStat('Cash Sales (+)', '$currency ${shift.cashSales.toStringAsFixed(2)}'),
                          const SizedBox(width: 24),
                          _buildShiftStat('Cash Expenses (-)', '$currency ${shift.cashExpenses.toStringAsFixed(2)}'),
                          const SizedBox(width: 24),
                          _buildShiftStat('Cash Refunds (-)', '$currency ${shift.cashRefunds.toStringAsFixed(2)}'),
                          const SizedBox(width: 24),
                          _buildShiftStat('Expected in Till Drawer', '$currency ${expectedInDrawer.toStringAsFixed(2)}', isHighlight: true),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 24),

          // Shift History Table
          Text(
            'PAST SHIFTS & VARIANCE RECONCILIATION AUDIT',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 12),

          if (shifts.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Center(child: Text('No past shift reconciliation records available', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant))),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shifts.length,
              itemBuilder: (context, index) {
                final s = shifts[index];
                final isOver = s.cashVariance > 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF151F32) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: s.status == 'OPEN'
                            ? const Color(0xFFECFDF5)
                            : (s.cashVariance == 0 ? const Color(0xFFEFF6FF) : const Color(0xFFFEF2F2)),
                        child: Icon(
                          s.status == 'OPEN'
                              ? Icons.access_time_filled
                              : (s.cashVariance == 0 ? Icons.check_circle : Icons.warning_rounded),
                          color: s.status == 'OPEN'
                              ? const Color(0xFF059669)
                              : (s.cashVariance == 0 ? primaryColor : const Color(0xFFDC2626)),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(s.shiftNumber, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                                const SizedBox(width: 10),
                                Text('Cashier: ${s.cashierName} (${s.terminalId})', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Opened: ${DateFormat('dd MMM yyyy, HH:mm').format(s.openingTime)} ${s.closingTime != null ? "• Closed: ${DateFormat('HH:mm').format(s.closingTime!)}" : ""}',
                              style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Expected: $currency ${s.expectedClosingCash.toStringAsFixed(2)} | Actual: $currency ${s.actualClosingCash.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurface),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.status == 'OPEN'
                                ? 'SHIFT ACTIVE'
                                : (s.cashVariance == 0
                                    ? 'PERFECT MATCH (K0.00)'
                                    : (isOver
                                        ? 'OVER: +$currency ${s.cashVariance.toStringAsFixed(2)}'
                                        : 'SHORT: -$currency ${s.cashVariance.abs().toStringAsFixed(2)}')),
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: s.status == 'OPEN'
                                  ? const Color(0xFF059669)
                                  : (s.cashVariance == 0 ? const Color(0xFF059669) : (isOver ? const Color(0xFF0284C7) : const Color(0xFFDC2626))),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportShiftZReportToPdf(s, config: config, printDirectly: true);
                            },
                            icon: Icon(Icons.print_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                            tooltip: 'Print Shift Z-Report',
                          ),
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportShiftZReportToPdf(s, config: config, printDirectly: false);
                            },
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
                            tooltip: 'Export Z-Report to PDF',
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildShiftStat(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isHighlight ? Colors.greenAccent : Colors.white,
          ),
        ),
      ],
    );
  }

  Future<void> _generateTillReport(BuildContext context, PosTerminal terminal, CashShift? currentShift, {required bool printDirectly}) async {
    final db = ref.read(databaseServiceProvider);
    final export = ref.read(exportServiceProvider);
    final config = ref.read(storeConfigProvider).value;

    final todayTransactions = await db.getTodayTransactionsForTerminal(
      terminal.terminalCode,
      terminalName: terminal.name,
      cashierId: terminal.assignedCashierId,
    );

    await export.exportTillReportToPdf(
      terminal: terminal,
      currentShift: currentShift,
      todayTransactions: todayTransactions,
      config: config,
      printDirectly: printDirectly,
    );

    if (context.mounted && !printDirectly) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Till Report for ${terminal.terminalCode} exported to PDF!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Widget _buildMasterHubBanner(
    BuildContext context,
    StoreConfig? config,
    String hostIp,
    int hostPort,
    Color accentColor,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final businessName = config?.businessName ?? 'Beleka Master Store';
    final branchName = config?.branchName ?? 'Headquarters (HQ)';
    final bhfId = config?.bhfId ?? '00';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.hub_rounded, color: primaryColor, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFF059669),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'MASTER POS SERVER (HOST HUB)',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: primaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'HOST RUNNING',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF059669),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$businessName • $branchName (bhfId: $bhfId)',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Secondary Cashier Tills connect using Master IP: $hostIp on Port $hostPort',
                  style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          ElevatedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: hostIp));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Master POS IP "$hostIp" copied to clipboard!'),
                  backgroundColor: const Color(0xFF059669),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: Text(
              'IP: $hostIp:$hostPort',
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
              foregroundColor: theme.colorScheme.onSurface,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTillsState(
    BuildContext context,
    String hostIp,
    int hostPort,
    Color accentColor,
    List<StoreBranch> branches,
    List<User> users,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151F32) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.point_of_sale_rounded, size: 40, color: primaryColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Waiting for Secondary Cashier Tills to Connect',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You do not need to register a till under the Owner. When you install Beleka POS on cashier machines in your shop, they will automatically handshake and appear here.',
              style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QUICK CLIENT TILL LINKING INSTRUCTIONS:',
                    style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: primaryColor, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: 8),
                  _buildStepRow('1', 'Launch Beleka POS on another PC or tablet in your shop.'),
                  const SizedBox(height: 6),
                  _buildStepRow('2', 'On the setup screen, select "Link LAN Client Till".'),
                  const SizedBox(height: 6),
                  _buildStepRow('3', 'Enter Master Host IP "$hostIp", test connection, and connect.'),
                  const SizedBox(height: 6),
                  _buildStepRow('4', 'The till will automatically register and appear on this dashboard!'),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showAddEditTerminalDialog(context, primaryColor, branches, users),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('+ Pre-Authorize Till Manually', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(String number, String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            number,
            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, height: 1.3),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTerminalStatus(PosTerminal t) async {
    final isar = ref.read(isarProvider);
    final newStatus = t.status == 'ACTIVE' ? 'INACTIVE' : 'ACTIVE';
    await isar.writeTxn(() async {
      t.status = newStatus;
      await isar.posTerminals.put(t);
    });
    ref.invalidate(posTerminalsProvider);
  }

  Future<void> _deleteTerminal(BuildContext context, PosTerminal t) async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        title: Text('Delete Till Register?', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
        content: Text('Are you sure you want to permanently delete "${t.terminalCode} - ${t.name}"?', style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        await isar.posTerminals.delete(t.id);
      });
      ref.invalidate(posTerminalsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted till ${t.terminalCode} successfully.')),
        );
      }
    }
  }

  void _openShiftForTerminal(BuildContext context, PosTerminal terminal, List<User> users, Color accentColor) {
    showDialog(
      context: context,
      builder: (context) => _AssignShiftModal(
        terminal: terminal,
        users: users,
        accentColor: accentColor,
      ),
    );
  }

  void _showQuickAssignShiftModal(BuildContext context, List<PosTerminal> terminals, List<User> users, Color accentColor) {
    if (terminals.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please register or connect a till first.')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => _AssignShiftModal(
        terminal: terminals.first,
        allTerminals: terminals,
        users: users,
        accentColor: accentColor,
      ),
    );
  }

  void _showCloseShiftModal(BuildContext context, CashShift shift, String currency) {
    showDialog(
      context: context,
      builder: (context) => _CloseShiftModal(
        shift: shift,
        currency: currency,
      ),
    );
  }

  void _showAddEditTerminalDialog(
    BuildContext context,
    Color accentColor,
    List<StoreBranch> branches,
    List<User> users, {
    PosTerminal? terminal,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final isEditing = terminal != null;
    final allTills = ref.read(posTerminalsProvider).value ?? [];
    final activeLicense = ref.read(licenseServiceProvider).activeLicense;
    final maxAllowedTills = activeLicense?.maxTills ?? 3;

    if (!isEditing && allTills.length >= maxAllowedTills) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lock_rounded, color: Color(0xFFD97706), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TILL CAPACITY LIMIT (MAX $maxAllowedTills TILLS)',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your current installation is licensed for up to $maxAllowedTills checkout tills (Currently registered: ${allTills.length} tills).',
                style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  'To connect and register additional checkout terminals (Till #${allTills.length + 1} and beyond), please upgrade your system license or contact Beleka Support to activate more tills.',
                  style: GoogleFonts.inter(color: const Color(0xFFB45309), fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                showDialog(
                  context: context,
                  builder: (_) => const LicenseInfoModal(),
                );
              },
              icon: const Icon(Icons.verified_user_rounded, size: 16),
              label: Text('View License & Upgrade', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
            ),
          ],
        ),
      );
      return;
    }

    final isOwner = ref.read(isOwnerProvider);
    final currentUser = ref.read(authProvider);
    final storeConfig = ref.read(storeConfigProvider).value;

    final userBranchCode = (!isOwner && currentUser?.branchCode != null && currentUser!.branchCode!.isNotEmpty && currentUser.branchCode != '00')
        ? currentUser.branchCode!
        : ((!isOwner && storeConfig != null && storeConfig.bhfId.isNotEmpty && storeConfig.bhfId != '00')
            ? storeConfig.bhfId
            : (isOwner ? '00' : '01'));

    final userBranchName = (!isOwner && currentUser?.branchName != null && currentUser!.branchName!.isNotEmpty)
        ? currentUser.branchName!
        : ((!isOwner && storeConfig != null && storeConfig.branchName != null && storeConfig.branchName!.isNotEmpty)
            ? storeConfig.branchName!
            : (isOwner ? 'Main Store (HQ)' : 'Branch $userBranchCode'));

    final Map<String, Map<String, String>> uniqueBranches = {};
    if (isOwner) {
      uniqueBranches['00'] = {'code': '00', 'name': 'Main Store (HQ)', 'bhfId': '00'};
      for (final b in branches) {
        uniqueBranches[b.code] = {'code': b.code, 'name': b.name, 'bhfId': b.bhfId};
      }
    } else {
      final matchingBranch = branches.where((b) => b.bhfId == userBranchCode || b.code == userBranchCode).firstOrNull;
      if (matchingBranch != null) {
        uniqueBranches[matchingBranch.code] = {'code': matchingBranch.code, 'name': matchingBranch.name, 'bhfId': matchingBranch.bhfId};
      } else {
        uniqueBranches[userBranchCode] = {'code': userBranchCode, 'name': userBranchName, 'bhfId': userBranchCode};
      }
    }

    if (terminal != null && terminal.branchCode.isNotEmpty) {
      if (!uniqueBranches.containsKey(terminal.branchCode)) {
        uniqueBranches[terminal.branchCode] = {
          'code': terminal.branchCode,
          'name': terminal.branchName.isNotEmpty ? terminal.branchName : 'Branch ${terminal.branchCode}',
          'bhfId': terminal.digitaxBhfId.isNotEmpty ? terminal.digitaxBhfId : terminal.branchCode,
        };
      }
    }

    final List<Map<String, String>> branchOptions = uniqueBranches.values.toList();
    if (branchOptions.isEmpty) {
      branchOptions.add({'code': '00', 'name': 'Main Store (HQ)', 'bhfId': '00'});
    }

    final codeCtrl = TextEditingController(text: terminal?.terminalCode ?? 'TILL-0${(ref.read(posTerminalsProvider).value?.length ?? 0) + 1}');
    final nameCtrl = TextEditingController(text: terminal?.name ?? 'Main Checkout Counter');
    final ipCtrl = TextEditingController(text: terminal?.deviceIp ?? '');
    final serialCtrl = TextEditingController(text: terminal?.serialNumber ?? '');

    String selectedBranchCode = (terminal != null && uniqueBranches.containsKey(terminal.branchCode))
        ? terminal.branchCode
        : branchOptions.first['code']!;
    String selectedBranchName = uniqueBranches[selectedBranchCode]?['name'] ?? branchOptions.first['name']!;
    String selectedBhfId = uniqueBranches[selectedBranchCode]?['bhfId'] ?? branchOptions.first['bhfId']!;

    final Map<String, User> uniqueUsersMap = {};
    for (final u in users) {
      if (u.numericId.isNotEmpty) {
        uniqueUsersMap[u.numericId] = u;
      }
    }
    final List<User> uniqueUsers = uniqueUsersMap.values.toList();

    String selectedCashierId = (terminal?.assignedCashierId != null && uniqueUsersMap.containsKey(terminal?.assignedCashierId))
        ? terminal!.assignedCashierId!
        : '';
    String? selectedCashierName = uniqueUsersMap[selectedCashierId]?.name;
    String status = terminal?.status ?? 'ACTIVE';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final inputFillColor = isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC);
          final inputBorderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);

          return AlertDialog(
            backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: inputBorderColor),
            ),
            title: Text(
              isEditing ? 'EDIT TILL / POS TERMINAL' : 'REGISTER NEW TILL / POS TERMINAL',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Configure this cashier checkout point and link it to your store branch:', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 16),

                    // Terminal Code & Name
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: codeCtrl,
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Till Code *',
                              hintText: 'e.g. TILL-01',
                              filled: true,
                              fillColor: inputFillColor,
                              labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: nameCtrl,
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Till Name *',
                              hintText: 'e.g. Counter 1 Express',
                              filled: true,
                              fillColor: inputFillColor,
                              labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Store Branch Selection
                    DropdownButtonFormField<String>(
                      initialValue: uniqueBranches.containsKey(selectedBranchCode) ? selectedBranchCode : branchOptions.first['code'],
                      dropdownColor: isDark ? const Color(0xFF1C283D) : Colors.white,
                      style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: isOwner ? 'Assigned Store Branch *' : 'Assigned Store Branch (Locked to your Branch)',
                        filled: true,
                        fillColor: inputFillColor,
                        labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                        prefixIcon: Icon(Icons.storefront_rounded, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      items: branchOptions.map((b) => DropdownMenuItem(
                        value: b['code'],
                        child: Text('${b['name']} (ZRA bhfId: ${b['bhfId']})'),
                      )).toList(),
                      onChanged: isOwner ? (code) {
                        if (code != null) {
                          setModalState(() {
                            selectedBranchCode = code;
                            final matching = branchOptions.where((b) => b['code'] == code).firstOrNull;
                            if (matching != null) {
                              selectedBranchName = matching['name']!;
                              selectedBhfId = matching['bhfId']!;
                            }
                          });
                        }
                      } : null,
                    ),
                    const SizedBox(height: 14),

                    // Default Assigned Cashier
                    DropdownButtonFormField<String>(
                      initialValue: (selectedCashierId.isEmpty || uniqueUsersMap.containsKey(selectedCashierId)) ? selectedCashierId : '',
                      dropdownColor: isDark ? const Color(0xFF1C283D) : Colors.white,
                      style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Default Assigned Cashier (Optional)',
                        filled: true,
                        fillColor: inputFillColor,
                        labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                        prefixIcon: Icon(Icons.person_rounded, color: theme.colorScheme.onSurfaceVariant),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('None (Assign on shift open)')),
                        ...uniqueUsers.map((u) => DropdownMenuItem(
                          value: u.numericId,
                          child: Text('${u.name} (ID: ${u.numericId} • ${u.role.toUpperCase()})'),
                        )),
                      ],
                      onChanged: (id) {
                        setModalState(() {
                          selectedCashierId = id ?? '';
                          final matchingUser = uniqueUsersMap[selectedCashierId];
                          selectedCashierName = matchingUser?.name;
                        });
                      },
                    ),
                    const SizedBox(height: 14),

                    // Status & IP
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: status,
                            dropdownColor: isDark ? const Color(0xFF1C283D) : Colors.white,
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Status',
                              filled: true,
                              fillColor: inputFillColor,
                              labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'ACTIVE', child: Text('ACTIVE')),
                              DropdownMenuItem(value: 'MAINTENANCE', child: Text('MAINTENANCE')),
                              DropdownMenuItem(value: 'INACTIVE', child: Text('INACTIVE')),
                            ],
                            onChanged: (val) {
                              if (val != null) setModalState(() => status = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: ipCtrl,
                            style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'Device IP / Serial',
                              hintText: 'e.g. 192.168.1.105',
                              filled: true,
                              fillColor: inputFillColor,
                              labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant)),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (codeCtrl.text.trim().isEmpty || nameCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter Till Code and Till Name.')),
                    );
                    return;
                  }

                  final isar = ref.read(isarProvider);
                  final localSql = ref.read(localSqlServiceProvider);

                  final posTerminal = terminal ?? PosTerminal();
                  posTerminal
                    ..terminalCode = codeCtrl.text.trim().toUpperCase()
                    ..name = nameCtrl.text.trim()
                    ..branchCode = selectedBranchCode
                    ..branchName = selectedBranchName
                    ..digitaxBhfId = selectedBhfId
                    ..assignedCashierId = selectedCashierId
                    ..assignedCashierName = selectedCashierName
                    ..deviceIp = ipCtrl.text.trim().isNotEmpty ? ipCtrl.text.trim() : null
                    ..serialNumber = serialCtrl.text.trim().isNotEmpty ? serialCtrl.text.trim() : null
                    ..status = status
                    ..lastActive = DateTime.now();

                  await isar.writeTxn(() async {
                    await isar.posTerminals.put(posTerminal);
                  });

                  try {
                    await localSql.db.insert(
                      'pos_terminals',
                      {
                        'terminal_code': posTerminal.terminalCode,
                        'name': posTerminal.name,
                        'branch_code': posTerminal.branchCode,
                        'branch_name': posTerminal.branchName,
                        'device_ip': posTerminal.deviceIp,
                        'serial_number': posTerminal.serialNumber,
                        'assigned_cashier_id': posTerminal.assignedCashierId,
                        'assigned_cashier_name': posTerminal.assignedCashierName,
                        'status': posTerminal.status,
                        'digitax_bhf_id': posTerminal.digitaxBhfId,
                        'sales_today': posTerminal.salesToday,
                        'last_active': posTerminal.lastActive.toIso8601String(),
                        'created_at': posTerminal.createdAt.toIso8601String(),
                      },
                      conflictAlgorithm: ConflictAlgorithm.replace,
                    );
                  } catch (e) {
                    debugPrint('Local SQLite terminal sync error: $e');
                  }

                  ref.invalidate(posTerminalsProvider);

                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEditing ? 'Till ${posTerminal.terminalCode} updated.' : 'Till ${posTerminal.terminalCode} registered successfully!'),
                        backgroundColor: const Color(0xFF059669),
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(isEditing ? 'Save Changes' : 'Register Till', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AssignShiftModal extends ConsumerStatefulWidget {
  final PosTerminal terminal;
  final List<PosTerminal>? allTerminals;
  final List<User> users;
  final Color accentColor;

  const _AssignShiftModal({
    required this.terminal,
    this.allTerminals,
    required this.users,
    required this.accentColor,
  });

  @override
  ConsumerState<_AssignShiftModal> createState() => _AssignShiftModalState();
}

class _AssignShiftModalState extends ConsumerState<_AssignShiftModal> {
  final _floatCtrl = TextEditingController(text: '1000.00');
  late PosTerminal _currentTerminal;
  String? _selectedCashierId;

  @override
  void initState() {
    super.initState();
    _currentTerminal = widget.terminal;
    _selectedCashierId = widget.terminal.assignedCashierId ??
        (widget.users.isNotEmpty ? widget.users.first.numericId : null);
  }

  @override
  void dispose() {
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _openShift() async {
    final floatVal = double.tryParse(_floatCtrl.text) ?? 0.0;
    final isar = ref.read(isarProvider);
    final currentUser = ref.read(authProvider);

    final selectedUser = widget.users.firstWhere(
      (u) => u.numericId == _selectedCashierId,
      orElse: () => currentUser ?? widget.users.first,
    );

    final cashierName = selectedUser.name;
    final cashierId = selectedUser.numericId;
    final tillName = '${_currentTerminal.terminalCode} - ${_currentTerminal.name}';
    final branchName = _currentTerminal.branchName;

    // Verify if already open
    final existingShift = await isar.cashShifts
        .filter()
        .terminalIdEqualTo(tillName)
        .and()
        .statusEqualTo('OPEN')
        .findFirst();

    if (existingShift != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Warning: $tillName is already open under ${existingShift.cashierName}!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    await isar.writeTxn(() async {
      final shift = CashShift()
        ..shiftNumber = 'SHIFT-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
        ..cashierId = cashierId
        ..cashierName = cashierName
        ..terminalId = tillName
        ..branchName = branchName
        ..openingCash = floatVal
        ..status = 'OPEN';
      await isar.cashShifts.put(shift);

      // Adjust cash drawer balance
      final cashAccount = await isar.paymentAccounts.filter().accountTypeEqualTo('CASH').findFirst();
      if (cashAccount != null) {
        cashAccount.balance += floatVal;
        await isar.paymentAccounts.put(cashAccount);
      }

      // Update terminal last active and default cashier
      _currentTerminal
        ..assignedCashierId = cashierId
        ..assignedCashierName = cashierName
        ..lastActive = DateTime.now();
      await isar.posTerminals.put(_currentTerminal);
    });

    ref.invalidate(posTerminalsProvider);
    ref.invalidate(activeShiftProvider);
    ref.invalidate(activeShiftsListProvider);
    ref.invalidate(cashShiftsProvider);
    ref.invalidate(paymentAccountsProvider);

    // Pop open cash drawer for float deposit
    try {
      ref.read(printerServiceProvider).openCashDrawer();
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assigned $cashierName to ${_currentTerminal.terminalCode} with K${floatVal.toStringAsFixed(2)} float!'),
          backgroundColor: Colors.green[800],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final inputFillColor = isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC);
    final inputBorderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: inputBorderColor),
      ),
      title: Text(
        'ASSIGN CASHIER & OPEN SHIFT',
        style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.allTerminals != null && widget.allTerminals!.length > 1) ...[
                DropdownButtonFormField<PosTerminal>(
                  initialValue: _currentTerminal,
                  dropdownColor: isDark ? const Color(0xFF1C283D) : Colors.white,
                  style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Select Till Register *',
                    filled: true,
                    fillColor: inputFillColor,
                    labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                    prefixIcon: Icon(Icons.point_of_sale_rounded, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  items: widget.allTerminals!.map((t) => DropdownMenuItem(
                    value: t,
                    child: Text('${t.terminalCode} - ${t.name} (${t.branchName})'),
                  )).toList(),
                  onChanged: (t) {
                    if (t != null) {
                      setState(() {
                        _currentTerminal = t;
                        if (t.assignedCashierId != null && t.assignedCashierId!.isNotEmpty) {
                          _selectedCashierId = t.assignedCashierId;
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: inputFillColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: inputBorderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.point_of_sale_rounded, color: theme.colorScheme.onSurfaceVariant, size: 20),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_currentTerminal.terminalCode} - ${_currentTerminal.name}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                          Text('${_currentTerminal.branchName} • ZRA: ${_currentTerminal.digitaxBhfId}', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              Builder(
                builder: (context) {
                  final uniqueUsersMap = <String, User>{};
                  for (final u in widget.users) {
                    if (u.numericId.isNotEmpty) {
                      uniqueUsersMap[u.numericId] = u;
                    }
                  }
                  final uniqueUsersList = uniqueUsersMap.values.toList();
                  final safeCashierId = (_selectedCashierId != null && uniqueUsersMap.containsKey(_selectedCashierId))
                      ? _selectedCashierId
                      : (uniqueUsersList.isNotEmpty ? uniqueUsersList.first.numericId : null);

                  return DropdownButtonFormField<String>(
                    initialValue: safeCashierId,
                    dropdownColor: isDark ? const Color(0xFF1C283D) : Colors.white,
                    style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Select Cashier / Staff *',
                      filled: true,
                      fillColor: inputFillColor,
                      labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                      prefixIcon: Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    items: uniqueUsersList.map((u) => DropdownMenuItem(
                      value: u.numericId,
                      child: Text('${u.name} (ID: ${u.numericId} • ${u.role.toUpperCase()})'),
                    )).toList(),
                    onChanged: (id) => setState(() => _selectedCashierId = id),
                  );
                },
              ),
              const SizedBox(height: 14),

              TextField(
                controller: _floatCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Opening Cash Float (K) *',
                  filled: true,
                  fillColor: inputFillColor,
                  labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: primaryColor, width: 1.5)),
                  prefixIcon: Icon(Icons.money_rounded, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant)),
        ),
        ElevatedButton(
          onPressed: _openShift,
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text('Start Shift & Log In', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _CloseShiftModal extends ConsumerStatefulWidget {
  final CashShift shift;
  final String currency;
  const _CloseShiftModal({required this.shift, required this.currency});

  @override
  ConsumerState<_CloseShiftModal> createState() => _CloseShiftModalState();
}

class _CloseShiftModalState extends ConsumerState<_CloseShiftModal> {
  final _actualCashCtrl = TextEditingController();
  double _expected = 0.0;
  double _variance = 0.0;

  @override
  void initState() {
    super.initState();
    final totalExpected = widget.shift.openingCash +
        widget.shift.cashSales +
        widget.shift.cashDeposits -
        widget.shift.cashExpenses -
        widget.shift.cashRefunds -
        widget.shift.cashWithdrawals;
    _expected = double.parse(totalExpected.toStringAsFixed(2));
    _actualCashCtrl.text = _expected.toStringAsFixed(2);
    _variance = 0.0;
  }

  @override
  void dispose() {
    _actualCashCtrl.dispose();
    super.dispose();
  }

  void _calcVariance(String val) {
    final actual = double.tryParse(val) ?? 0.0;
    setState(() {
      _variance = double.parse((actual - _expected).toStringAsFixed(2));
    });
  }

  Future<void> _close() async {
    final actual = double.tryParse(_actualCashCtrl.text) ?? 0.0;
    final cleanActual = double.parse(actual.toStringAsFixed(2));
    final cleanVariance = double.parse((cleanActual - _expected).toStringAsFixed(2));
    final isar = ref.read(isarProvider);

    await isar.writeTxn(() async {
      widget.shift.closingTime = DateTime.now();
      widget.shift.expectedClosingCash = _expected;
      widget.shift.actualClosingCash = cleanActual;
      widget.shift.cashVariance = cleanVariance;
      widget.shift.status = 'CLOSED';
      await isar.cashShifts.put(widget.shift);
    });

    ref.invalidate(activeShiftProvider);
    ref.invalidate(activeShiftsListProvider);
    ref.invalidate(cashShiftsProvider);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Till shift ${widget.shift.shiftNumber} closed! Cash variance: ${widget.currency}${_variance.toStringAsFixed(2)}'),
          backgroundColor: _variance == 0 ? const Color(0xFF059669) : (_variance > 0 ? const Color(0xFF0284C7) : const Color(0xFFDC2626)),
          action: SnackBarAction(
            label: 'Print Z-Report',
            textColor: Colors.white,
            onPressed: () {
              final config = ref.read(storeConfigProvider).value;
              ref.read(exportServiceProvider).exportShiftZReportToPdf(widget.shift, config: config, printDirectly: true);
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final inputFillColor = isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC);
    final inputBorderColor = isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0);

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: inputBorderColor),
      ),
      title: Text('RECONCILE & CLOSE TILL SHIFT', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: inputFillColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: inputBorderColor),
              ),
              child: Column(
                children: [
                  _row('Shift Number:', widget.shift.shiftNumber),
                  _row('Terminal / Till:', widget.shift.terminalId),
                  _row('Cashier Name:', widget.shift.cashierName),
                  _row('Opening Float:', '${widget.currency} ${widget.shift.openingCash.toStringAsFixed(2)}'),
                  _row('Cash Sales (+):', '${widget.currency} ${widget.shift.cashSales.toStringAsFixed(2)}', color: const Color(0xFF059669)),
                  _row('Cash Expenses (-):', '${widget.currency} ${widget.shift.cashExpenses.toStringAsFixed(2)}', color: const Color(0xFFDC2626)),
                  _row('Cash Refunds (-):', '${widget.currency} ${widget.shift.cashRefunds.toStringAsFixed(2)}', color: const Color(0xFFDC2626)),
                  Divider(color: inputBorderColor),
                  _row('Expected in Drawer:', '${widget.currency} ${_expected.toStringAsFixed(2)}', isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _actualCashCtrl,
              keyboardType: TextInputType.number,
              style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold),
              onChanged: _calcVariance,
              decoration: InputDecoration(
                labelText: 'Actual Cash Counted in Drawer (${widget.currency}) *',
                filled: true,
                fillColor: inputFillColor,
                labelStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: inputBorderColor)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _variance == 0 ? const Color(0xFFECFDF5) : (_variance > 0 ? const Color(0xFFF0F9FF) : const Color(0xFFFEF2F2)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _variance == 0 ? const Color(0xFFA7F3D0) : (_variance > 0 ? const Color(0xFFBAE6FD) : const Color(0xFFFECACA)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cash Variance / Reconciliation:', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                  Text(
                    _variance == 0
                        ? 'BALANCED (0.00)'
                        : (_variance > 0
                            ? 'OVER: +${widget.currency}${_variance.toStringAsFixed(2)}'
                            : 'SHORT: -${widget.currency}${_variance.abs().toStringAsFixed(2)}'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _variance == 0 ? const Color(0xFF059669) : (_variance > 0 ? const Color(0xFF0284C7) : const Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant))),
        ElevatedButton(
          onPressed: _close,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFDC2626),
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text('Confirm Reconciliation & Close Shift', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Widget _row(String l, String v, {Color? color, bool isBold = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
          Text(
            v,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
