import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/providers/theme_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/local_sql_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:beleka_pos/screens/accounts_screen.dart';
import 'package:beleka_pos/utils/formatters.dart';

class TerminalsScreen extends ConsumerStatefulWidget {
  const TerminalsScreen({super.key});

  @override
  ConsumerState<TerminalsScreen> createState() => _TerminalsScreenState();
}

class _TerminalsScreenState extends ConsumerState<TerminalsScreen> {
  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(accentColorProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final currentUser = ref.watch(authProvider);
    final storeConfig = ref.watch(storeConfigProvider).value;
    final currency = storeConfig?.currencySymbol ?? 'K';
    final allTerminals = ref.watch(posTerminalsProvider).value ?? [];

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
                    'Register POS till registers, link with store branches (bhfId), and assign cashiers to specific tills.',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditTerminalDialog(context, accentColor, branches, users),
                    icon: const Icon(Icons.add_to_queue_rounded, size: 18),
                    label: Text('+ Register New Till', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
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
          const SizedBox(height: 24),

          // KPI Stats Overview Bar
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'REGISTERED TILLS',
                  value: '${terminals.length}',
                  subtitle: '$activeTerminalsCount Active in Network',
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
                  subtitle: 'Aggregate Till Revenue',
                  icon: Icons.payments_rounded,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Terminals Grid / List
          Expanded(
            child: terminals.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.point_of_sale_outlined, size: 64, color: Colors.white.withAlpha(40)),
                        const SizedBox(height: 16),
                        Text('No POS Tills Registered Yet', style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white70)),
                        const SizedBox(height: 8),
                        Text('Click "+ Register New Till" above to create and configure your checkout registers.', style: GoogleFonts.inter(fontSize: 13, color: Colors.white38)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () => _showAddEditTerminalDialog(context, accentColor, branches, users),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Register First Till'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 440,
                      mainAxisExtent: 290,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: terminals.length,
                    itemBuilder: (context, index) {
                      final t = terminals[index];
                      final matchingShift = activeShifts.where((s) => s.terminalId == '${t.terminalCode} - ${t.name}' || s.terminalId == t.terminalCode || s.terminalId == t.name).firstOrNull;
                      final isShiftOpen = matchingShift != null;
                      final isActive = t.status == 'ACTIVE';

                      return Container(
                        padding: const EdgeInsets.all(20),
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
                                        Text(
                                          t.name,
                                          style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
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
                                            : isActive
                                                ? Colors.blue.withAlpha(30)
                                                : Colors.orange.withAlpha(30),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: isShiftOpen
                                              ? Colors.green.withAlpha(80)
                                              : isActive
                                                  ? Colors.blue.withAlpha(80)
                                                  : Colors.orange.withAlpha(80),
                                        ),
                                      ),
                                      child: Text(
                                        isShiftOpen ? 'LIVE SHIFT' : t.status,
                                        style: GoogleFonts.jetBrainsMono(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isShiftOpen
                                              ? Colors.green
                                              : isActive
                                                  ? Colors.blue
                                                  : Colors.orange,
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.white54),
                                      onSelected: (val) async {
                                        if (val == 'edit') {
                                          _showAddEditTerminalDialog(context, accentColor, branches, users, terminal: t);
                                        } else if (val == 'toggle_status') {
                                          await _toggleTerminalStatus(t);
                                        } else if (val == 'delete') {
                                          await _deleteTerminal(context, t);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 8), Text('Edit Till')])),
                                        PopupMenuItem(value: 'toggle_status', child: Row(children: [Icon(Icons.toggle_on_rounded, size: 16), SizedBox(width: 8), Text(isActive ? 'Set Inactive' : 'Set Active')])),
                                        const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text('Delete Till', style: TextStyle(color: Colors.redAccent))])),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const Divider(color: Colors.white10, height: 20),

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
                            const SizedBox(height: 10),

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
                                                  : 'Click "Assign Shift" to launch till',
                                          style: GoogleFonts.inter(fontSize: 10, color: Colors.white38),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),

                            // Bottom Row: Sales Today & Action Button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('TILL REVENUE', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white38, letterSpacing: 1)),
                                    Text(
                                      CurrencyFormatter.format(t.salesToday, currency),
                                      style: GoogleFonts.jetBrainsMono(fontSize: 14, fontWeight: FontWeight.bold, color: accentColor),
                                    ),
                                  ],
                                ),
                                ElevatedButton.icon(
                                  onPressed: isShiftOpen
                                      ? () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('${t.name} currently has an open shift under ${matchingShift.cashierName}. Reconcile under Accounts > Shifts.')),
                                          );
                                        }
                                      : () => _openShiftForTerminal(context, t, users, accentColor),
                                  icon: Icon(isShiftOpen ? Icons.check_circle_outline : Icons.login_rounded, size: 14),
                                  label: Text(isShiftOpen ? 'Shift Active' : 'Assign & Open Shift', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isShiftOpen ? Colors.white.withAlpha(15) : accentColor,
                                    foregroundColor: isShiftOpen ? Colors.white70 : Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    elevation: 0,
                                  ),
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
      ),
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
        title: const Text('Delete Till Register?'),
        content: Text('Are you sure you want to permanently delete "${t.terminalCode} - ${t.name}"?'),
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

  void _showAddEditTerminalDialog(
    BuildContext context,
    Color accentColor,
    List<StoreBranch> branches,
    List<User> users, {
    PosTerminal? terminal,
  }) {
    final isEditing = terminal != null;
    final codeCtrl = TextEditingController(text: terminal?.terminalCode ?? 'TILL-0${(ref.read(posTerminalsProvider).value?.length ?? 0) + 1}');
    final nameCtrl = TextEditingController(text: terminal?.name ?? 'Main Checkout Counter');
    final ipCtrl = TextEditingController(text: terminal?.deviceIp ?? '');
    final serialCtrl = TextEditingController(text: terminal?.serialNumber ?? '');

    String selectedBranchCode = terminal?.branchCode ?? (branches.isNotEmpty ? branches.first.code : '00');
    String selectedBranchName = terminal?.branchName ?? (branches.isNotEmpty ? branches.first.name : 'Main Store (HQ)');
    String selectedBhfId = terminal?.digitaxBhfId ?? (branches.isNotEmpty ? branches.first.bhfId : '00');
    String? selectedCashierId = terminal?.assignedCashierId ?? (users.isNotEmpty ? users.first.numericId : null);
    String? selectedCashierName = terminal?.assignedCashierName ?? (users.isNotEmpty ? users.first.name : null);
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
                      initialValue: selectedBranchCode,
                      dropdownColor: const Color(0xFF222228),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Assigned Store Branch *',
                        labelStyle: TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.storefront_rounded, color: Colors.white60),
                      ),
                      items: branches.isEmpty
                          ? [
                              const DropdownMenuItem(
                                value: '00',
                                child: Text('Main Store (HQ) • ZRA: 00'),
                              )
                            ]
                          : branches.map((b) => DropdownMenuItem(
                              value: b.code,
                              child: Text('${b.name} (ZRA bhfId: ${b.bhfId})'),
                            )).toList(),
                      onChanged: (code) {
                        if (code != null) {
                          setModalState(() {
                            selectedBranchCode = code;
                            final matchingBranch = branches.where((b) => b.code == code).firstOrNull;
                            if (matchingBranch != null) {
                              selectedBranchName = matchingBranch.name;
                              selectedBhfId = matchingBranch.bhfId;
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Default Assigned Cashier
                    DropdownButtonFormField<String>(
                      initialValue: selectedCashierId,
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
                        ...users.map((u) => DropdownMenuItem(
                          value: u.numericId,
                          child: Text('${u.name} (ID: ${u.numericId} • ${u.role.toUpperCase()})'),
                        )),
                      ],
                      onChanged: (id) {
                        setModalState(() {
                          selectedCashierId = id;
                          final matchingUser = users.where((u) => u.numericId == id).firstOrNull;
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

                  // Sync to local SQLite SQL
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
  final List<User> users;
  final Color accentColor;

  const _AssignShiftModal({
    required this.terminal,
    required this.users,
    required this.accentColor,
  });

  @override
  ConsumerState<_AssignShiftModal> createState() => _AssignShiftModalState();
}

class _AssignShiftModalState extends ConsumerState<_AssignShiftModal> {
  final _floatCtrl = TextEditingController(text: '1000.00');
  String? _selectedCashierId;

  @override
  void initState() {
    super.initState();
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
    final tillName = '${widget.terminal.terminalCode} - ${widget.terminal.name}';
    final branchName = widget.terminal.branchName;

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
      widget.terminal
        ..assignedCashierId = cashierId
        ..assignedCashierName = cashierName
        ..lastActive = DateTime.now();
      await isar.posTerminals.put(widget.terminal);
    });

    ref.invalidate(posTerminalsProvider);
    ref.invalidate(activeShiftProvider);
    ref.invalidate(activeShiftsListProvider);
    ref.invalidate(cashShiftsProvider);
    ref.invalidate(paymentAccountsProvider);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assigned $cashierName to ${widget.terminal.terminalCode} with K${floatVal.toStringAsFixed(2)} float!'),
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
                        Text('${widget.terminal.terminalCode} - ${widget.terminal.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('${widget.terminal.branchName} • ZRA: ${widget.terminal.digitaxBhfId}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                initialValue: _selectedCashierId,
                dropdownColor: const Color(0xFF222228),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Select Cashier / Staff *',
                  labelStyle: TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person, color: Colors.white60),
                ),
                items: widget.users.map((u) => DropdownMenuItem(
                  value: u.numericId,
                  child: Text('${u.name} (ID: ${u.numericId} • ${u.role.toUpperCase()})'),
                )).toList(),
                onChanged: (id) => setState(() => _selectedCashierId = id),
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
