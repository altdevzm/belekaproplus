import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/screens/settings/store_config_modal.dart';
import 'package:beleka_pos/screens/settings/user_management_modal.dart';
import 'package:beleka_pos/screens/settings/printer_settings_modal.dart';
import 'package:beleka_pos/screens/settings/loyalty_settings_modal.dart';
import 'package:beleka_pos/screens/settings/backup_settings_modal.dart';
import 'package:beleka_pos/screens/settings/license_info_modal.dart';
import 'package:beleka_pos/screens/settings/network_sync_modal.dart';
import 'package:beleka_pos/widgets/zra_tax_config_modal.dart';
import 'package:beleka_pos/screens/settings/scale_settings_modal.dart';
import 'package:beleka_pos/providers/auth_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final isOwner = ref.watch(isOwnerProvider);
    final isManager = ref.watch(isManagerProvider);
    final todayStr = DateFormat('EEE, dd MMM yyyy').format(DateTime.now());

    return Container(
      color: theme.scaffoldBackgroundColor,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Enterprise Breadcrumb & Status Bar (Overflow-Protected)
          LayoutBuilder(
            builder: (context, headerConstraints) {
              final isCompact = headerConstraints.maxWidth < 650;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text('Workspace', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: theme.colorScheme.onSurfaceVariant)),
                        Icon(Icons.chevron_right_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
                        Flexible(
                          child: Text(
                            isCompact ? 'System Settings' : 'Store Configuration & System Settings',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: primaryColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!isCompact) ...[
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFA7F3D0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF059669), shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text('Healthy', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF059669))),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF151F32) : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                          ),
                          child: Text(todayStr, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),

          // Main Header Title
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (isOwner || isManager) ? 'STORE & SYSTEM CONFIGURATION CENTER' : 'HARDWARE & TILL SETTINGS',
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                (isOwner || isManager)
                    ? 'Manage store profile, ZRA tax compliance, hardware peripherals, network sync, security and licensing'
                    : 'Configure local thermal receipt printers, cash drawers, scales and barcode scanners for this active terminal',
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GridView(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 185,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                  ),
                  children: [
                    // Printers & Hardware (Accessible to Cashiers & Managers)
                    _buildSettingsCard(
                      context,
                      'Printers & Hardware',
                      'Manage thermal receipt printers, cash drawer kick pulse, serial ports and scanners',
                      Icons.print_rounded,
                      const Color(0xFF059669),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const PrinterSettingsModal(),
                      ),
                    ),
                    // Electronic Scale (Accessible to Cashiers & Managers)
                    _buildSettingsCard(
                      context,
                      'Electronic Scale',
                      'Configure RS232 serial COM, USB and TCP/IP POS weight scale integrations',
                      Icons.scale_rounded,
                      primaryColor,
                      onPressed: () => showDialog(
                        context: context,
                        builder: (context) => const ScaleSettingsModal(),
                      ),
                      buttonLabel: 'Configure Scale',
                    ),
                    // Administrative / Manager-Only Settings
                    if (isOwner || isManager) ...[
                      _buildSettingsCard(
                        context,
                        'System License & Tier',
                        'View system hardware ID, subscription tier, activation key and expiry date',
                        Icons.verified_user_rounded,
                        const Color(0xFF0284C7),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const LicenseInfoModal(),
                        ),
                        buttonLabel: 'View License',
                      ),
                      _buildSettingsCard(
                        context,
                        'Tax & Compliance',
                        'Configure VAT rates, TPIN registration, tax type and ZRA smart invoicing rules',
                        Icons.account_balance_rounded,
                        primaryColor,
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const StoreConfigModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'User Management & Security',
                        'Add or edit staff accounts, role permissions, passcodes and cashier access',
                        Icons.people_rounded,
                        const Color(0xFF0284C7),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const UserManagementModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'Store Profile & Contact',
                        'Update business name, physical address, branch details and primary currency symbol',
                        Icons.storefront_rounded,
                        primaryColor,
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const StoreConfigModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'Data Export & Reports',
                        'Export raw transaction history, customer catalogs and inventory to CSV files',
                        Icons.download_rounded,
                        const Color(0xFF059669),
                        onPressed: () async {
                          final db = ref.read(databaseServiceProvider);
                          final transactions = await db.getRecentTransactions(limit: 10000);
                          await ref.read(exportServiceProvider).exportTransactionsToCsv(transactions);
                        },
                        buttonLabel: 'Export CSV',
                      ),
                      _buildSettingsCard(
                        context,
                        'Loyalty & Rewards',
                        'Setup customer points system, reward tiers and automated checkout discounts',
                        Icons.loyalty_rounded,
                        const Color(0xFFD97706),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const LoyaltySettingsModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'Database Backup & Restore',
                        'Export encrypted Isar database snapshots, cloud backups and restore points',
                        Icons.backup_rounded,
                        const Color(0xFF059669),
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const BackupSettingsModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'DigiTax & ZRA Smart Invoice',
                        'Configure DigiTax API Key, Branch ID, Device Serial & Live Fiscal Tax Rates',
                        Icons.receipt_long_rounded,
                        const Color(0xFF059669),
                        buttonLabel: 'Configure ZRA',
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const ZraTaxConfigModal(),
                        ),
                      ),
                      _buildSettingsCard(
                        context,
                        'Master POS Host & LAN Sync',
                        'Configure Master Server IP, Cashier Client Tills & Realtime Multi-POS Sync',
                        Icons.hub_rounded,
                        primaryColor,
                        onPressed: () => showDialog(
                          context: context,
                          builder: (context) => const NetworkSyncModal(),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(
    BuildContext context,
    String title,
    String description,
    IconData icon,
    Color accent, {
    VoidCallback? onPressed,
    String buttonLabel = 'Configure',
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? accent.withValues(alpha: 0.15) : accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: ElevatedButton(
              onPressed: onPressed ?? () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: Text(
                buttonLabel,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
