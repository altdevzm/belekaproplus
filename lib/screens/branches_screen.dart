import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/providers/users_provider.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/services/postgres_sync_service.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
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
              'Multi-Branch & Store Network',
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
                    'ZRA DigiTax Multi-Location Active',
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

  Widget _buildKpiCard(String label, String value, String subtitle, IconData icon, Color color) {
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
                  label,
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
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final isOwner = ref.watch(isOwnerProvider);
    if (!isOwner) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF151F32) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_rounded, size: 56, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(
                'ACCESS RESTRICTED',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Multi-Branch Management is restricted to Corporate Owners and Super Admins.',
                style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final currentConfig = ref.watch(storeConfigProvider).value;
    final branches = ref.watch(storeBranchesProvider).value ?? [];
    final users = ref.watch(usersProvider).value ?? [];
    final currency = currentConfig?.currencySymbol ?? 'K';

    final totalNetworkSales = branches.fold<double>(0.0, (sum, b) => sum + b.salesToday);
    final activeCount = branches.where((b) => b.status == 'ONLINE' || b.status == 'ACTIVE').length;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Breadcrumb Bar
          _buildTopBreadcrumbBar(context),
          const SizedBox(height: 16),

          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MULTI-BRANCH & STORE NETWORK',
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Create store branches, assign Branch Managers from your user list, and configure ZRA DigiTax codes (bhfId)',
                    style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
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
                            Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 16),
                            SizedBox(width: 8),
                            Text('Export Branches (PDF)'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'excel',
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_rounded, color: Color(0xFF059669), size: 16),
                            SizedBox(width: 8),
                            Text('Export Branches (Excel)'),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF151F32) : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.download_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Text('Export & Print', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: theme.colorScheme.onSurface)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showAddEditBranchDialog(context, primaryColor, users),
                    icon: const Icon(Icons.add_business_rounded, size: 18),
                    label: Text('+ Create New Branch', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
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
          const SizedBox(height: 20),

          // Top Executive Metric Cards Grid
          GridView.count(
            crossAxisCount: 4,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 2.5,
            children: [
              _buildKpiCard('TOTAL BRANCHES', '${branches.length} Locations', 'Store network size', Icons.store_mall_directory_rounded, primaryColor),
              _buildKpiCard('ACTIVE HQ STORE', currentConfig?.businessName ?? 'Main HQ Branch', 'bhfId: ${currentConfig?.bhfId ?? "00"}', Icons.storefront_rounded, const Color(0xFF0284C7)),
              _buildKpiCard('NETWORK SALES TODAY', '$currency ${totalNetworkSales.toStringAsFixed(2)}', 'Combined daily revenue', Icons.payments_rounded, const Color(0xFF059669)),
              _buildKpiCard('ZRA DIGITAX CONNECTED', '$activeCount / ${branches.length} Online', 'Fiscalized locations', Icons.verified_rounded, const Color(0xFFD97706)),
            ],
          ),
          const SizedBox(height: 20),

          // Active HQ Branch Highlight Card
          Container(
            padding: const EdgeInsets.all(20),
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
                  child: Icon(Icons.storefront_rounded, color: primaryColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HEADQUARTERS & ACTIVE TERMINAL BRANCH',
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: primaryColor, letterSpacing: 0.8),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentConfig?.businessName ?? 'Lusaka Main Branch (HQ)',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ZRA Branch Code (bhfId): ${currentConfig?.bhfId ?? "00"} • TPIN: ${currentConfig?.tpin ?? "1002948192"}',
                        style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(20),
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
                      Text('ZRA DIGITAX ACTIVE', style: GoogleFonts.inter(color: const Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Branches Grid
          Expanded(
            child: branches.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.store_mall_directory_rounded, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text('No Branches Created Yet', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 8),
                        Text('Click "+ Create New Branch" to expand your store network.', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
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
                          color: isDark ? const Color(0xFF151F32) : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
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
                                    color: const Color(0xFFF0F9FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${b.code} (bhfId: ${b.bhfId})',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF0284C7)),
                                  ),
                                ),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isOnline ? const Color(0xFFECFDF5) : (isDark ? const Color(0xFF1C283D) : const Color(0xFFF1F5F9)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        b.isHQ ? 'HQ STORE' : (isOnline ? 'ONLINE' : 'OFFLINE'),
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOnline ? const Color(0xFF059669) : theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                                      padding: EdgeInsets.zero,
                                      onSelected: (val) async {
                                        if (val == 'daily_report_pdf') {
                                          _generateBranchDailyReport(context, b, printDirectly: false);
                                        } else if (val == 'daily_report_print') {
                                          _generateBranchDailyReport(context, b, printDirectly: true);
                                        } else if (val == 'edit') {
                                          _showAddEditBranchDialog(context, primaryColor, users, branch: b);
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
                                          value: 'daily_report_pdf',
                                          child: Row(
                                            children: [
                                              Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 16),
                                              SizedBox(width: 8),
                                              Text('Daily Branch Report (PDF)'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'daily_report_print',
                                          child: Row(
                                            children: [
                                              Icon(Icons.print_rounded, color: Color(0xFF059669), size: 16),
                                              SizedBox(width: 8),
                                              Text('Print Daily Report'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuDivider(),
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
                                            child: Row(children: [Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 16), SizedBox(width: 8), Text('Delete Branch', style: TextStyle(color: Color(0xFFDC2626)))]),
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
                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              b.address?.isNotEmpty == true ? b.address! : 'Location details not set',
                              style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 12),
                            // Branch Manager Card
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.person_pin_rounded, size: 18, color: primaryColor),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Manager: ${b.managerName ?? "Unassigned"}', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                                        if (b.managerPhone != null && b.managerPhone!.isNotEmpty)
                                          Text('Contact: ${b.managerPhone}', style: GoogleFonts.inter(fontSize: 10.5, color: theme.colorScheme.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Sales Today', style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                                    Text('$currency ${b.salesToday.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: primaryColor)),
                                  ],
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => _generateBranchDailyReport(context, b, printDirectly: false),
                                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFDC2626)),
                                      tooltip: 'Generate Daily Report (PDF)',
                                      splashRadius: 18,
                                    ),
                                    IconButton(
                                      onPressed: () => _generateBranchDailyReport(context, b, printDirectly: true),
                                      icon: Icon(Icons.print_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                      tooltip: 'Print Daily Report',
                                      splashRadius: 18,
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
      ),
    );
  }

  Future<void> _generateBranchDailyReport(BuildContext context, StoreBranch branch, {required bool printDirectly}) async {
    final db = ref.read(databaseServiceProvider);
    final export = ref.read(exportServiceProvider);
    final config = ref.read(storeConfigProvider).value;

    final branchTransactions = await db.getTodayTransactionsForBranch(
      branch.code,
      branchBhfId: branch.bhfId,
      branchName: branch.name,
    );

    final allTerminals = ref.read(posTerminalsProvider).value ?? [];
    final branchTerminals = allTerminals.where((t) =>
      t.branchCode == branch.code ||
      t.digitaxBhfId == branch.bhfId ||
      t.branchCode == branch.bhfId ||
      t.branchName.trim().toUpperCase() == branch.name.trim().toUpperCase()
    ).toList();

    await export.exportBranchDailyReportToPdf(
      branch: branch,
      branchTodayTransactions: branchTransactions,
      branchTerminals: branchTerminals,
      config: config,
      printDirectly: printDirectly,
    );

    if (context.mounted && !printDirectly) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Daily Performance Report for ${branch.name} exported to PDF!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
  }

  Future<void> _deleteBranch(BuildContext context, StoreBranch branch) async {
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
        title: Text('Delete Branch?', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.onSurface)),
        content: Text('Are you sure you want to delete "${branch.name}" (${branch.code})?', style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
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
    final bhfIdCtrl = TextEditingController(text: branch?.bhfId ?? '${(ref.read(storeBranchesProvider).value?.length ?? 0) + 1}'.padLeft(2, '0'));
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
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;
          final primaryColor = theme.colorScheme.primary;

          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: 540,
              constraints: const BoxConstraints(maxHeight: 750),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
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
                                color: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.add_business_rounded, color: primaryColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              isEditing ? 'EDIT STORE BRANCH' : 'CREATE NEW BRANCH',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(dialogCtx),
                          icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurfaceVariant, size: 18),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0), height: 1),
                    const SizedBox(height: 16),

                    // Branch Store Details Section
                    Text('BRANCH STORE DETAILS', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: primaryColor, letterSpacing: 0.8)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Branch Name *',
                        hintText: 'e.g. Ndola Central Store, Kitwe Mall Branch',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: bhfIdCtrl,
                            decoration: const InputDecoration(
                              labelText: 'ZRA Branch Code (bhfId) *',
                              hintText: '01, 02, 03...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: phoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Branch Phone',
                              hintText: '+260 97...',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Physical Address',
                        hintText: 'Plot 123, Cairo Road, Lusaka',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Branch Email Address',
                        hintText: 'branch@company.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Branch Manager Assignment Section
                    Text('ASSIGN BRANCH MANAGER', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: primaryColor, letterSpacing: 0.8)),
                    const SizedBox(height: 4),
                    Text('Select a manager from your existing users, or provision a new user account.', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),

                    Builder(
                      builder: (context) {
                        final uniqueUsers = <String, User>{};
                        for (final u in users) {
                          uniqueUsers[u.numericId] = u;
                        }
                        final safeSelectedUserId = (selectedUserId != null && uniqueUsers.containsKey(selectedUserId))
                            ? selectedUserId
                            : null;

                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: isCreateNewUser ? '__CREATE_NEW__' : safeSelectedUserId,
                              isExpanded: true,
                              dropdownColor: isDark ? const Color(0xFF151F32) : Colors.white,
                              style: GoogleFonts.inter(color: theme.colorScheme.onSurface, fontSize: 13),
                              hint: Text('Select Existing User as Manager', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                              items: [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('-- No Manager Assigned --', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                                ),
                                ...uniqueUsers.values.map((u) => DropdownMenuItem<String?>(
                                  value: u.numericId,
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_outline_rounded, size: 16, color: primaryColor),
                                      const SizedBox(width: 8),
                                      Text('${u.name} (Role: ${u.role.toUpperCase()}) - ID: ${u.numericId}'),
                                    ],
                                  ),
                                )),
                                const DropdownMenuItem<String?>(
                                  value: '__CREATE_NEW__',
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_add_alt_1_rounded, size: 16, color: Color(0xFF059669)),
                                      SizedBox(width: 8),
                                      Text('+ Provision New Manager User', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold)),
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
                        );
                      },
                    ),

                    // If "Create New User" is chosen, show inputs for new manager credentials
                    if (isCreateNewUser) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFA7F3D0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('NEW BRANCH MANAGER CREDENTIALS', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF059669), letterSpacing: 0.8)),
                            const SizedBox(height: 10),
                            TextField(
                              controller: newMgrNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Manager Full Name *',
                                hintText: 'e.g. John Mwila',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: newMgrIdCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Manager Login ID *',
                                      hintText: '3001',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: newMgrPinCtrl,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'Manager PIN *',
                                      hintText: '1234',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: newMgrPhoneCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Phone / WhatsApp',
                                hintText: '+260 97...',
                                border: OutlineInputBorder(),
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
                          child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
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
                            final formattedBhfId = bhfId.padLeft(2, '0');
                            await isar.writeTxn(() async {
                              targetBranch.code = 'BR-$formattedBhfId';
                              targetBranch.name = branchName;
                              targetBranch.bhfId = formattedBhfId;
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
                              if (isCreateNewUser && finalMgrId != null) {
                                final db = ref.read(databaseServiceProvider);
                                final newMgr = await db.getUserByNumericId(finalMgrId);
                                if (newMgr != null) {
                                  ref.read(postgresSyncServiceProvider).syncUser(newMgr, plainPin: newMgrPinCtrl.text.trim());
                                }
                              } else if (selectedUserId != null) {
                                final matchedUser = users.firstWhere((u) => u.numericId == selectedUserId);
                                ref.read(postgresSyncServiceProvider).syncUser(matchedUser);
                              }
                            } catch (_) {}

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isEditing ? 'Branch "$branchName" updated successfully.' : 'Branch "$branchName" created successfully!'),
                                  backgroundColor: const Color(0xFF059669),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
