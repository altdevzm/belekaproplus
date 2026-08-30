import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/theme_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(accentColorProvider);
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

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TILLS & CASHIER TERMINALS MANAGEMENT',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Monitor connected cashier registers, assign cashier shifts, generate per-till PDF reports, and balance till floats.',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditTerminalDialog(context, accentColor, branches, users),
                    icon: const Icon(Icons.add_to_queue_rounded, size: 18),
                    label: Text('+ Pre-Authorize Till', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Master POS Host Hub Status Card
          _buildMasterHubBanner(context, storeConfig, hostIp, hostPort, accentColor),
          const SizedBox(height: 18),

          // Tab Bar for Terminals vs Shift Balancing
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141417),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withAlpha(15)),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: accentColor,
              indicatorWeight: 3,
              labelColor: accentColor,
              unselectedLabelColor: Colors.white60,
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
          const SizedBox(height: 18),

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
                  accentColor: accentColor,
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
                  accentColor: accentColor,
                ),
              ],
            ),
          ),
        ],
      ),
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
    return Column(
      children: [
        // KPI Stats Overview Bar
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                title: 'CONNECTED TILLS',
                value: '${terminals.length} / $maxAllowedTills',
                subtitle: '$activeTerminalsCount Active (Max $maxAllowedTills on License)',
                icon: Icons.point_of_sale_rounded,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                title: 'ACTIVE SHIFT TILLS',
                value: '${activeShifts.length}',
                subtitle: '${activeShifts.length} Cashiers Live On Shift',
                icon: Icons.person_pin_circle_rounded,
                color: Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                title: 'CONNECTED BRANCHES',
                value: '${branches.length}',
                subtitle: 'ZRA Fiscal Branches Linked',
                icon: Icons.storefront_rounded,
                color: Colors.purpleAccent,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildMetricCard(
                title: 'TERMINAL SALES TODAY',
                value: CurrencyFormatter.format(totalSalesToday, currency),
                subtitle: 'Aggregate Live Till Revenue',
                icon: Icons.payments_rounded,
                color: Colors.amber,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Terminals Grid / List
        Expanded(
          child: terminals.isEmpty
              ? _buildEmptyTillsState(context, hostIp, hostPort, accentColor, branches, users)
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
                        color: const Color(0xFF161619),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isShiftOpen
                              ? Colors.green.withAlpha(120)
                              : isActive
                                  ? Colors.white.withAlpha(20)
                                  : Colors.redAccent.withAlpha(60),
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
                                          ? Colors.green.withAlpha(40)
                                          : accentColor.withAlpha(30),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      Icons.point_of_sale_rounded,
                                      color: isShiftOpen ? Colors.green : accentColor,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.terminalCode.toUpperCase(),
                                        style: GoogleFonts.manrope(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 1,
                                          color: Colors.white,
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            t.name,
                                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                                          ),
                                          if (t.deviceIp != null && t.deviceIp!.isNotEmpty) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              '• ${t.deviceIp}',
                                              style: GoogleFonts.ibmPlexMono(fontSize: 10, color: Colors.white38),
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
                                          ? Colors.green.withAlpha(30)
                                          : isLiveConnected
                                              ? const Color(0xFF10B981).withAlpha(30)
                                              : isActive
                                                  ? Colors.blue.withAlpha(30)
                                                  : Colors.orange.withAlpha(30),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isShiftOpen
                                            ? Colors.green.withAlpha(80)
                                            : isLiveConnected
                                                ? const Color(0xFF10B981).withAlpha(80)
                                                : isActive
                                                    ? Colors.blue.withAlpha(80)
                                                    : Colors.orange.withAlpha(80),
                                      ),
                                    ),
                                    child: Text(
                                      isShiftOpen
                                          ? 'LIVE SHIFT'
                                          : isLiveConnected
                                              ? 'CONNECTED'
                                              : t.status,
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isShiftOpen
                                            ? Colors.green
                                            : isLiveConnected
                                                ? const Color(0xFF10B981)
                                                : isActive
                                                    ? Colors.blue
                                                    : Colors.orange,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.white54),
                                    onSelected: (val) async {
                                      if (val == 'report_pdf') {
                                        _generateTillReport(context, t, matchingShift, printDirectly: false);
                                      } else if (val == 'report_print') {
                                        _generateTillReport(context, t, matchingShift, printDirectly: true);
                                      } else if (val == 'edit') {
                                        _showAddEditTerminalDialog(context, accentColor, branches, users, terminal: t);
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
                                            Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 16),
                                            SizedBox(width: 8),
                                            Text('Till Report (PDF)'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'report_print',
                                        child: Row(
                                          children: [
                                            Icon(Icons.print_rounded, color: Colors.greenAccent, size: 16),
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
                                            Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                            SizedBox(width: 8),
                                            Text('Delete Till', style: TextStyle(color: Colors.redAccent)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 16),

                          // Branch & DigiTax bhfId Info
                          Row(
                            children: [
                              const Icon(Icons.storefront_rounded, size: 14, color: Colors.white38),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  t.branchName,
                                  style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(10),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'ZRA bhfId: ${t.digitaxBhfId}',
                                  style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white54),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // Assigned Cashier Info
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: isShiftOpen ? Colors.green.withAlpha(40) : Colors.white.withAlpha(20),
                                  child: Icon(Icons.person, size: 14, color: isShiftOpen ? Colors.green : Colors.white70),
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
                                          color: isShiftOpen ? Colors.green : Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        isShiftOpen
                                            ? 'Shift #: ${matchingShift.shiftNumber}'
                                            : (t.assignedCashierId != null && t.assignedCashierId!.isNotEmpty)
                                                ? 'Assigned ID: ${t.assignedCashierId}'
                                                : 'Cashier can log in directly',
                                        style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
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
                                  Text('TILL REVENUE TODAY', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white38, letterSpacing: 1)),
                                  Text(
                                    CurrencyFormatter.format(t.salesToday, currency),
                                    style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold, color: accentColor),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => _generateTillReport(context, t, matchingShift, printDirectly: false),
                                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.redAccent),
                                    tooltip: 'Generate Till Report (PDF)',
                                    splashRadius: 18,
                                  ),
                                  const SizedBox(width: 4),
                                  ElevatedButton.icon(
                                    onPressed: isShiftOpen
                                        ? () => _showCloseShiftModal(context, matchingShift, currency)
                                        : () => _openShiftForTerminal(context, t, users, accentColor),
                                    icon: Icon(isShiftOpen ? Icons.calculate_rounded : Icons.login_rounded, size: 13),
                                    label: Text(
                                      isShiftOpen ? 'Reconcile' : 'Assign Shift',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isShiftOpen ? Colors.redAccent.withAlpha(40) : accentColor,
                                      foregroundColor: isShiftOpen ? Colors.redAccent : Colors.black,
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
                  Text('ACTIVE TILLS & CASHIER SHIFT BALANCING', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('${activeShifts.length} active cashier till${activeShifts.length == 1 ? "" : "s"} currently live on shift', style: GoogleFonts.inter(fontSize: 12, color: Colors.white54)),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => _showQuickAssignShiftModal(context, terminals, users, accentColor),
                icon: const Icon(Icons.person_pin_circle_rounded, size: 16),
                label: const Text('+ Assign Cashier to a Till'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                color: const Color(0xFF1A1A1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withAlpha(15)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.point_of_sale_rounded, size: 48, color: Colors.white.withAlpha(40)),
                    const SizedBox(height: 12),
                    Text('No Active Till Shifts Operating', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text('Assign a cashier to a specific till and set their opening float to begin a shift.', style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
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
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.green.withAlpha(80)),
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
                                  color: Colors.blue.withAlpha(40),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.point_of_sale_rounded, color: Colors.blue, size: 14),
                                    const SizedBox(width: 6),
                                    Text(shift.terminalId.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.green.withAlpha(30), borderRadius: BorderRadius.circular(6)),
                                child: const Text('SHIFT ACTIVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.greenAccent)),
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
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
                                tooltip: 'Export Interim Z-Report PDF',
                              ),
                              IconButton(
                                onPressed: () {
                                  final config = ref.read(storeConfigProvider).value;
                                  ref.read(exportServiceProvider).exportShiftZReportToPdf(shift, config: config, printDirectly: true);
                                },
                                icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white70),
                                tooltip: 'Print Interim Slip',
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showCloseShiftModal(context, shift, currency),
                                icon: const Icon(Icons.calculate_rounded, size: 16),
                                label: const Text('Reconcile & Close Till'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                            backgroundColor: accentColor.withAlpha(40),
                            radius: 18,
                            child: Text(
                              shift.cashierName.isNotEmpty ? shift.cashierName[0].toUpperCase() : 'C',
                              style: TextStyle(color: accentColor, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Assigned Cashier: ${shift.cashierName} (ID: ${shift.cashierId ?? "1001"})',
                                style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
                              ),
                              Text(
                                '${shift.branchName} • Opened at ${DateFormat('HH:mm, dd MMM yyyy').format(shift.openingTime)}',
                                style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white10),
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
          Text('PAST SHIFTS & VARIANCE RECONCILIATION AUDIT', style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 12),

          if (shifts.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(color: const Color(0xFF1A1A1E), borderRadius: BorderRadius.circular(16)),
              child: Center(child: Text('No past shift reconciliation records available', style: GoogleFonts.inter(color: Colors.white38))),
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
                    color: const Color(0xFF1A1A1E),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withAlpha(15)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: s.status == 'OPEN'
                            ? Colors.green.withAlpha(30)
                            : (s.cashVariance == 0 ? Colors.blue.withAlpha(30) : Colors.red.withAlpha(30)),
                        child: Icon(
                          s.status == 'OPEN'
                              ? Icons.access_time_filled
                              : (s.cashVariance == 0 ? Icons.check_circle : Icons.warning_rounded),
                          color: s.status == 'OPEN'
                              ? Colors.green
                              : (s.cashVariance == 0 ? Colors.blue : Colors.redAccent),
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
                                Text(s.shiftNumber, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                                const SizedBox(width: 10),
                                Text('Cashier: ${s.cashierName} (${s.terminalId})', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Opened: ${DateFormat('dd MMM yyyy, HH:mm').format(s.openingTime)} ${s.closingTime != null ? "• Closed: ${DateFormat('HH:mm').format(s.closingTime!)}" : ""}',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white38),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Expected: $currency ${s.expectedClosingCash.toStringAsFixed(2)} | Actual: $currency ${s.actualClosingCash.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
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
                                  ? Colors.green
                                  : (s.cashVariance == 0 ? Colors.green : (isOver ? Colors.blue : Colors.redAccent)),
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
                            icon: const Icon(Icons.print_rounded, size: 18, color: Colors.white70),
                            tooltip: 'Print Shift Z-Report',
                          ),
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportShiftZReportToPdf(s, config: config, printDirectly: false);
                            },
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
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
    final businessName = config?.businessName ?? 'Beleka Master Store';
    final branchName = config?.branchName ?? 'Headquarters (HQ)';
    final bhfId = config?.bhfId ?? '00';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF141418),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withAlpha(60)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlpha(15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.hub_rounded, color: accentColor, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'MASTER POS SERVER (HOST HUB)',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF10B981).withAlpha(80)),
                      ),
                      child: Text(
                        'HOST RUNNING',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$businessName • $branchName (bhfId: $bhfId)',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Secondary Cashier Tills connect using Master IP: $hostIp on Port $hostPort',
                  style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white60),
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
                  backgroundColor: accentColor,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 14),
            label: Text(
              'IP: $hostIp:$hostPort',
              style: GoogleFonts.ibmPlexMono(fontSize: 11, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white10,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: const Color(0xFF141418),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withAlpha(15)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentColor.withAlpha(20),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.point_of_sale_rounded, size: 40, color: accentColor),
            ),
            const SizedBox(height: 16),
            Text(
              'Waiting for Secondary Cashier Tills to Connect',
              style: GoogleFonts.manrope(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'You do not need to register a till under the Owner. When you install Beleka POS on cashier machines in your shop, they will automatically handshake and appear here.',
              style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white60, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withAlpha(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QUICK CLIENT TILL LINKING INSTRUCTIONS:',
                    style: GoogleFonts.ibmPlexMono(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor, letterSpacing: 1),
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
                  onPressed: () => _showAddEditTerminalDialog(context, accentColor, branches, users),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('+ Pre-Authorize Till Manually'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            number,
            style: GoogleFonts.ibmPlexMono(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(fontSize: 12, color: Colors.white70, height: 1.3),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161619),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withAlpha(15)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white38, letterSpacing: 1)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white), overflow: TextOverflow.ellipsis),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 10.5, color: Colors.white54)),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Delete Till Register?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to permanently delete "${t.terminalCode} - ${t.name}"?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
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
    final isEditing = terminal != null;
    final allTills = ref.read(posTerminalsProvider).value ?? [];
    final activeLicense = ref.read(licenseServiceProvider).activeLicense;
    final maxAllowedTills = activeLicense?.maxTills ?? 3;

    if (!isEditing && allTills.length >= maxAllowedTills) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(40),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.lock_rounded, color: Colors.amber, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'TILL CAPACITY LIMIT (MAX $maxAllowedTills TILLS)',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: Colors.white,
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
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withAlpha(60)),
                ),
                child: Text(
                  'To connect and register additional checkout terminals (Till #${allTills.length + 1} and beyond), please upgrade your system license or contact Beleka Support to activate more tills.',
                  style: GoogleFonts.inter(color: Colors.amber.shade200, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: GoogleFonts.inter(color: Colors.white54)),
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
              label: Text('View License & Upgrade', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
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
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              isEditing ? 'EDIT TILL / POS TERMINAL' : 'REGISTER NEW TILL / POS TERMINAL',
              style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Configure this cashier checkout point and link it to your store branch:', style: GoogleFonts.inter(fontSize: 12, color: Colors.white60)),
                    const SizedBox(height: 16),

                    // Terminal Code & Name
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: codeCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Till Code *',
                              hintText: 'e.g. TILL-01',
                              labelStyle: TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: nameCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Till Name *',
                              hintText: 'e.g. Counter 1 Express',
                              labelStyle: TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Store Branch Selection
                    DropdownButtonFormField<String>(
                      initialValue: uniqueBranches.containsKey(selectedBranchCode) ? selectedBranchCode : branchOptions.first['code'],
                      dropdownColor: const Color(0xFF222228),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: isOwner ? 'Assigned Store Branch *' : 'Assigned Store Branch (Locked to your Branch)',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.storefront_rounded, color: Colors.white60),
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
                      dropdownColor: const Color(0xFF222228),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Default Assigned Cashier (Optional)',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_rounded, color: Colors.white60),
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
                            dropdownColor: const Color(0xFF222228),
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Status',
                              labelStyle: TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(),
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
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Device IP / Serial',
                              hintText: 'e.g. 192.168.1.105',
                              labelStyle: TextStyle(color: Colors.white70),
                              border: OutlineInputBorder(),
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
                child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
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
                        backgroundColor: Colors.green[800],
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: Text(isEditing ? 'Save Changes' : 'Register Till', style: const TextStyle(fontWeight: FontWeight.bold)),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'ASSIGN CASHIER & OPEN SHIFT',
        style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
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
                  dropdownColor: const Color(0xFF222228),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Select Till Register *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.point_of_sale_rounded, color: Colors.white60),
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
                    color: Colors.white.withAlpha(8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.point_of_sale_rounded, color: Colors.white70, size: 20),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${_currentTerminal.terminalCode} - ${_currentTerminal.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                          Text('${_currentTerminal.branchName} • ZRA: ${_currentTerminal.digitaxBhfId}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
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
                    dropdownColor: const Color(0xFF222228),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Select Cashier / Staff *',
                      labelStyle: TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person, color: Colors.white60),
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
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Opening Cash Float (K) *',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.money_rounded, color: Colors.white60),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton(
          onPressed: _openShift,
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.accentColor,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: const Text('Start Shift & Log In', style: TextStyle(fontWeight: FontWeight.bold)),
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
          backgroundColor: _variance == 0 ? Colors.green : (_variance > 0 ? Colors.blue : Colors.redAccent),
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
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('RECONCILE & CLOSE TILL SHIFT', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withAlpha(8), borderRadius: BorderRadius.circular(8)),
              child: Column(
                children: [
                  _row('Shift Number:', widget.shift.shiftNumber),
                  _row('Terminal / Till:', widget.shift.terminalId),
                  _row('Cashier Name:', widget.shift.cashierName),
                  _row('Opening Float:', '${widget.currency} ${widget.shift.openingCash.toStringAsFixed(2)}'),
                  _row('Cash Sales (+):', '${widget.currency} ${widget.shift.cashSales.toStringAsFixed(2)}', color: Colors.greenAccent),
                  _row('Cash Expenses (-):', '${widget.currency} ${widget.shift.cashExpenses.toStringAsFixed(2)}', color: Colors.redAccent),
                  _row('Cash Refunds (-):', '${widget.currency} ${widget.shift.cashRefunds.toStringAsFixed(2)}', color: Colors.redAccent),
                  const Divider(color: Colors.white24),
                  _row('Expected in Drawer:', '${widget.currency} ${_expected.toStringAsFixed(2)}', isBold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _actualCashCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              onChanged: _calcVariance,
              decoration: InputDecoration(
                labelText: 'Actual Cash Counted in Drawer (${widget.currency}) *',
                labelStyle: const TextStyle(color: Colors.white70),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _variance == 0 ? Colors.green.withAlpha(20) : (_variance > 0 ? Colors.blue.withAlpha(20) : Colors.red.withAlpha(20)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _variance == 0 ? Colors.green.withAlpha(50) : (_variance > 0 ? Colors.blue.withAlpha(50) : Colors.red.withAlpha(50)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Cash Variance / Reconciliation:', style: GoogleFonts.inter(fontSize: 12, color: Colors.white70)),
                  Text(
                    _variance == 0
                        ? 'BALANCED (0.00)'
                        : (_variance > 0
                            ? 'OVER: +${widget.currency}${_variance.toStringAsFixed(2)}'
                            : 'SHORT: -${widget.currency}${_variance.abs().toStringAsFixed(2)}'),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _variance == 0 ? Colors.greenAccent : (_variance > 0 ? Colors.blueAccent : Colors.redAccent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
        ElevatedButton(
          onPressed: _close,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
          child: const Text('Confirm Reconciliation & Close Shift'),
        ),
      ],
    );
  }

  Widget _row(String l, String v, {Color? color, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(l, style: GoogleFonts.inter(fontSize: 12, color: Colors.white60)),
          Text(
            v,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
