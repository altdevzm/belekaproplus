import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/providers/theme_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/users_provider.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';

class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(accentColorProvider);
    final currentConfig = ref.watch(storeConfigProvider).value;
    final branches = ref.watch(storeBranchesProvider).value ?? [];
    final users = ref.watch(usersProvider).value ?? [];
    final currency = currentConfig?.currencySymbol ?? 'K';

    return Padding(
      padding: const EdgeInsets.all(24),
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
                    'MULTI-BRANCH MANAGEMENT & BRANCH MANAGERS',
                    style: GoogleFonts.manrope(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Create store branches, assign Branch Managers from your user list, and configure ZRA DigiTax codes (bhfId)',
                    style: GoogleFonts.inter(fontSize: 13, color: Colors.white54),
                  ),
                ],
              ),
              Row(
                children: [
                  // Export & Reports Dropdown
                  PopupMenuButton<String>(
                    onSelected: (value) async {
                      final export = ref.read(exportServiceProvider);
                      final config = ref.read(storeConfigProvider).value;
                      final branchesList = await ref.read(storeBranchesProvider.future);

                      switch (value) {
                        case 'pdf':
                          export.exportBranchesReportToPdf(branchesList, config: config);
                          break;
                        case 'excel':
                          export.exportBranchesReportToExcel(branchesList, config: config);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 16),
                            SizedBox(width: 8),
                            Text('Export Branches (PDF)'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'excel',
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_rounded, color: Colors.green, size: 16),
                            SizedBox(width: 8),
                            Text('Export Branches (Excel)'),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withAlpha(20)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.download_rounded, size: 16, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text('Export & Print', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditBranchDialog(context, accentColor, users),
                    icon: const Icon(Icons.add_business_rounded, size: 18),
                    label: Text('+ Create New Branch', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
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

          // Active Branch Card Highlight
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor.withAlpha(40), Colors.purple.withAlpha(30)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accentColor.withAlpha(60)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.storefront_rounded, color: accentColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HEADQUARTERS & ACTIVE TERMINAL BRANCH',
                        style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor, letterSpacing: 1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentConfig?.businessName ?? 'Lusaka Main Branch (HQ)',
                        style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ZRA Branch Code (bhfId): ${currentConfig?.bhfId ?? "00"} • TPIN: ${currentConfig?.tpin ?? "1002948192"}',
                        style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withAlpha(40),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 14),
                      SizedBox(width: 6),
                      Text('ZRA DIGITAX ACTIVE', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Branches Grid
          Expanded(
            child: branches.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.store_mall_directory_rounded, size: 48, color: Colors.white.withAlpha(30)),
                        const SizedBox(height: 12),
                        Text('No Branches Created Yet', style: GoogleFonts.manrope(fontSize: 16, color: Colors.white54)),
                        const SizedBox(height: 8),
                        Text('Click "+ Create New Branch" to expand your store network.', style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
                      ],
                    ),
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 420,
                      mainAxisExtent: 260,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: branches.length,
                    itemBuilder: (context, index) {
                      final b = branches[index];
                      final isOnline = b.status == 'ONLINE' || b.status == 'ACTIVE';
                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withAlpha(20)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withAlpha(40),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${b.code} (bhfId: ${b.bhfId})',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue[300]),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: (isOnline ? Colors.green : Colors.grey).withAlpha(40),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        b.isHQ ? 'HQ STORE' : (isOnline ? 'ONLINE' : 'OFFLINE'),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOnline ? Colors.green : Colors.white60),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    PopupMenuButton<String>(
                                      icon: const Icon(Icons.more_vert_rounded, size: 18, color: Colors.white54),
                                      padding: EdgeInsets.zero,
                                      onSelected: (val) async {
                                        if (val == 'edit') {
                                          _showAddEditBranchDialog(context, accentColor, users, branch: b);
                                        } else if (val == 'toggle_status') {
                                          final isar = ref.read(isarProvider);
                                          await isar.writeTxn(() async {
                                            b.status = isOnline ? 'OFFLINE' : 'ONLINE';
                                            await isar.storeBranchs.put(b);
                                          });
                                          ref.invalidate(storeBranchesProvider);
                                        } else if (val == 'delete') {
                                          _deleteBranch(context, b);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 8), Text('Edit Branch')]),
                                        ),
                                        PopupMenuItem(
                                          value: 'toggle_status',
                                          child: Row(children: [Icon(Icons.toggle_on_rounded, size: 16), SizedBox(width: 8), Text(isOnline ? 'Set Offline' : 'Set Online')]),
                                        ),
                                        if (!b.isHQ)
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(children: [Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16), SizedBox(width: 8), Text('Delete Branch', style: TextStyle(color: Colors.redAccent))]),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              b.name,
                              style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              b.address?.isNotEmpty == true ? b.address! : 'Location details not set',
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.white54),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            // Branch Manager Card
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(8),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.person_pin_rounded, size: 16, color: accentColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Manager: ${b.managerName ?? "Unassigned"}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                                        if (b.managerPhone != null && b.managerPhone!.isNotEmpty)
                                          Text('Contact: ${b.managerPhone}', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            const Divider(color: Colors.white10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Sales Today', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                                    Text('$currency ${b.salesToday.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: accentColor)),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('ZRA SDC ID', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38)),
                                    Text(b.sdcId ?? 'SDC-ZM-AUTO', style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
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
      ),
    );
  }

  Future<void> _deleteBranch(BuildContext context, StoreBranch branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Delete Branch?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete "${branch.name}" (${branch.code})?', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final isar = ref.read(isarProvider);
      await isar.writeTxn(() async {
        await isar.storeBranchs.delete(branch.id);
      });
      ref.invalidate(storeBranchesProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Branch ${branch.name} deleted.')),
        );
      }
    }
  }

  void _showAddEditBranchDialog(
    BuildContext context, 
    Color accentColor, 
    List<User> users, {
    StoreBranch? branch,
  }) {
    final isEditing = branch != null;
    final nameCtrl = TextEditingController(text: branch?.name ?? '');
    final bhfIdCtrl = TextEditingController(text: branch?.bhfId ?? '0${(ref.read(storeBranchesProvider).value?.length ?? 0) + 1}');
    final addressCtrl = TextEditingController(text: branch?.address ?? '');
    final phoneCtrl = TextEditingController(text: branch?.phone ?? '');
    final emailCtrl = TextEditingController(text: branch?.email ?? '');

    // User selection state
    String? selectedUserId = branch?.managerId;
    bool isCreateNewUser = false;

    // Check if initial managerId matches an existing user
    if (selectedUserId != null && !users.any((u) => u.numericId == selectedUserId)) {
      selectedUserId = null;
    }

    final newMgrNameCtrl = TextEditingController();
    final newMgrIdCtrl = TextEditingController(text: '${3000 + (users.length + 1)}');
    final newMgrPinCtrl = TextEditingController(text: '1234');
    final newMgrPhoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 540,
              constraints: const BoxConstraints(maxHeight: 750),
              decoration: BoxDecoration(
                color: const Color(0xFF141418),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withAlpha(25)),
              ),
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: accentColor.withAlpha(35),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.add_business_rounded, color: accentColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isEditing ? 'EDIT STORE BRANCH' : 'CREATE NEW BRANCH',
                              style: GoogleFonts.manrope(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          icon: const Icon(Icons.close_rounded, color: Colors.white54),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 16),

                    // Branch Store Details Section
                    Text('BRANCH STORE DETAILS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor, letterSpacing: 1)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Branch Name *',
                        hintText: 'e.g. Ndola Central Store, Kitwe Mall Branch',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF1E1E24),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bhfIdCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'ZRA Branch Code (bhfId) *',
                              hintText: '01, 02, 03...',
                              hintStyle: const TextStyle(color: Colors.white24),
                              filled: true,
                              fillColor: const Color(0xFF1E1E24),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: phoneCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Branch Phone',
                              hintText: '+260 97...',
                              hintStyle: const TextStyle(color: Colors.white24),
                              filled: true,
                              fillColor: const Color(0xFF1E1E24),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Physical Address',
                        hintText: 'Plot 123, Cairo Road, Lusaka',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF1E1E24),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Branch Email Address',
                        hintText: 'branch@company.com',
                        hintStyle: const TextStyle(color: Colors.white24),
                        filled: true,
                        fillColor: const Color(0xFF1E1E24),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Branch Manager Assignment Section
                    Text('ASSIGN BRANCH MANAGER', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor, letterSpacing: 1)),
                    const SizedBox(height: 8),
                    Text('Select a manager from your existing users, or provision a new user account.', style: GoogleFonts.inter(fontSize: 11.5, color: Colors.white54)),
                    const SizedBox(height: 12),

                    // USER SELECTION DROPDOWN
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E24),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: isCreateNewUser ? '__CREATE_NEW__' : selectedUserId,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1E1E24),
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                          hint: const Text('Select Existing User as Manager', style: TextStyle(color: Colors.white38)),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('-- No Manager Assigned --', style: TextStyle(color: Colors.white54)),
                            ),
                            ...users.map((u) => DropdownMenuItem<String?>(
                              value: u.numericId,
                              child: Row(
                                children: [
                                  Icon(Icons.person_outline_rounded, size: 16, color: accentColor),
                                  const SizedBox(width: 8),
                                  Text('${u.name} (Role: ${u.role.toUpperCase()}) - ID: ${u.numericId}'),
                                ],
                              ),
                            )),
                            DropdownMenuItem<String?>(
                              value: '__CREATE_NEW__',
                              child: Row(
                                children: [
                                  const Icon(Icons.person_add_alt_1_rounded, size: 16, color: Color(0xFF10B981)),
                                  const SizedBox(width: 8),
                                  Text('+ Provision New Manager User', style: TextStyle(color: Colors.greenAccent[200], fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setModalState(() {
                              if (val == '__CREATE_NEW__') {
                                isCreateNewUser = true;
                                selectedUserId = null;
                              } else {
                                isCreateNewUser = false;
                                selectedUserId = val;
                              }
                            });
                          },
                        ),
                      ),
                    ),

                    // If "Create New User" is chosen, show inputs for new manager credentials
                    if (isCreateNewUser) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withAlpha(40)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('NEW BRANCH MANAGER CREDENTIALS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.greenAccent, letterSpacing: 1)),
                            const SizedBox(height: 10),
                            TextField(
                              controller: newMgrNameCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Manager Full Name *',
                                hintText: 'e.g. John Mwila',
                                filled: true,
                                fillColor: const Color(0xFF141418),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: newMgrIdCtrl,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Manager Login ID *',
                                      hintText: '3001',
                                      filled: true,
                                      fillColor: const Color(0xFF141418),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: newMgrPinCtrl,
                                    obscureText: true,
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: 'Manager PIN *',
                                      hintText: '1234',
                                      filled: true,
                                      fillColor: const Color(0xFF141418),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: newMgrPhoneCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Phone / WhatsApp',
                                hintText: '+260 97...',
                                filled: true,
                                fillColor: const Color(0xFF141418),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    // Action Buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: () async {
                            final branchName = nameCtrl.text.trim();
                            if (branchName.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please enter a Branch Name.')),
                              );
                              return;
                            }

                            final isar = ref.read(isarProvider);
                            final bhfId = bhfIdCtrl.text.trim().isEmpty ? '01' : bhfIdCtrl.text.trim();

                            String? finalMgrName;
                            String? finalMgrId;
                            String? finalMgrPhone;

                            // Resolve manager
                            if (isCreateNewUser) {
                              final name = newMgrNameCtrl.text.trim();
                              final id = newMgrIdCtrl.text.trim();
                              final pin = newMgrPinCtrl.text.trim();
                              if (name.isNotEmpty && id.isNotEmpty) {
                                finalMgrName = name;
                                finalMgrId = id;
                                finalMgrPhone = newMgrPhoneCtrl.text.trim();

                                await isar.writeTxn(() async {
                                  final newMgr = User()
                                    ..numericId = id
                                    ..name = name
                                    ..role = 'branch_manager'
                                    ..branchName = branchName
                                    ..branchCode = bhfId
                                    ..passwordHash = hashPin(pin.isNotEmpty ? pin : '1234')
                                    ..phone = finalMgrPhone
                                    ..isActive = true;
                                  await isar.users.put(newMgr);
                                });
                                ref.invalidate(usersProvider);
                              }
                            } else if (selectedUserId != null) {
                              final matchedUser = users.firstWhere((u) => u.numericId == selectedUserId);
                              finalMgrName = matchedUser.name;
                              finalMgrId = matchedUser.numericId;
                              finalMgrPhone = matchedUser.phone;

                              // Update this user's branch assignment
                              await isar.writeTxn(() async {
                                matchedUser.branchName = branchName;
                                matchedUser.branchCode = bhfId;
                                if (matchedUser.role != 'owner' && matchedUser.role != 'admin') {
                                  matchedUser.role = 'branch_manager';
                                }
                                await isar.users.put(matchedUser);
                              });
                              ref.invalidate(usersProvider);
                            }

                            // Save or Update Branch
                            final targetBranch = branch ?? StoreBranch();
                            await isar.writeTxn(() async {
                              targetBranch.code = 'BR-00$bhfId';
                              targetBranch.name = branchName;
                              targetBranch.bhfId = bhfId;
                              targetBranch.address = addressCtrl.text.trim();
                              targetBranch.phone = phoneCtrl.text.trim();
                              targetBranch.email = emailCtrl.text.trim();
                              targetBranch.managerName = finalMgrName ?? branch?.managerName;
                              targetBranch.managerId = finalMgrId ?? branch?.managerId;
                              targetBranch.managerPhone = finalMgrPhone ?? branch?.managerPhone;
                              targetBranch.status = branch?.status ?? 'ONLINE';
                              targetBranch.zraStatus = 'FISCALIZED';
                              await isar.storeBranchs.put(targetBranch);
                            });

                            ref.invalidate(storeBranchesProvider);

                            // Sync to Cloud PostgreSQL Database
                            try {
                              ref.read(postgresSyncServiceProvider).syncBranch(targetBranch);
                              if (selectedUserId != null) {
                                final matchedUser = users.firstWhere((u) => u.numericId == selectedUserId);
                                ref.read(postgresSyncServiceProvider).syncUser(matchedUser);
                              }
                            } catch (_) {}

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isEditing ? 'Branch "$branchName" updated successfully.' : 'Branch "$branchName" created successfully!'),
                                  backgroundColor: const Color(0xFF10B981),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: Text(
                            isEditing ? 'Save Changes' : 'Create Branch',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
