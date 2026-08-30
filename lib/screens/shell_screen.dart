import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/screens/dashboard_screen.dart';
import 'package:beleka_pos/screens/inventory_screen.dart';
import 'package:beleka_pos/screens/sales_screen.dart';
import 'package:beleka_pos/screens/settings_screen.dart';
import 'package:beleka_pos/screens/reports_screen.dart';
import 'package:beleka_pos/screens/terminals_screen.dart';
import 'package:beleka_pos/screens/purchases_screen.dart';
import 'package:beleka_pos/screens/branches_screen.dart';
import 'package:beleka_pos/providers/auth_provider.dart';
import 'package:beleka_pos/providers/theme_provider.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/models/models.dart';
import 'dart:io';

import 'package:beleka_pos/services/network_client.dart';
import 'package:beleka_pos/core/core.dart';
import 'package:beleka_pos/widgets/update_banner.dart';
import 'package:beleka_pos/widgets/tax_reminder_banner.dart';
import 'package:beleka_pos/widgets/camera_barcode_scanner_modal.dart';
import 'package:beleka_pos/providers/cart_provider.dart';
import 'package:beleka_pos/services/database_service.dart';

enum ScreenType { dashboard, sales, inventory, purchases, branches, terminals, settings, reports }

final navigationProvider = StateProvider<ScreenType>((ref) {
  // Cashiers default to Sales screen
  final user = ref.watch(authProvider);
  if (user?.role == 'cashier') return ScreenType.sales;
  return ScreenType.dashboard;
});

class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentScreen = ref.watch(navigationProvider);
    final theme = Theme.of(context);
    final isManager = ref.watch(isManagerProvider);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: AdaptiveLayout(
        compact: (ctx) => _buildMobileLayout(context, ref, currentScreen, isManager, isCompact: true),
        mobile: (ctx) => _buildMobileLayout(context, ref, currentScreen, isManager, isCompact: true),
        tablet: (ctx) => _buildTabletLayout(context, ref, currentScreen, isManager),
        desktop: (ctx) => _buildDesktopLayout(context, ref, currentScreen, isManager, isUltraWide: false),
        ultraWide: (ctx) => _buildDesktopLayout(context, ref, currentScreen, isManager, isUltraWide: true),
      ),
    );
  }

  Widget _buildMobileLayout(
    BuildContext context,
    WidgetRef ref,
    ScreenType current,
    bool isManager, {
    required bool isCompact,
  }) {
    final user = ref.watch(authProvider);
    final accentColor = ref.watch(accentColorProvider);
    final role = user?.role.toLowerCase().trim() ?? 'cashier';
    final isCashier = role == 'cashier';

    return Column(
      children: [
        _buildStatusBar(ref, isCompact: isCompact),
        const UpdateBanner(),
        Expanded(child: _buildMainContent(current)),
        
        // Ergonomic Mobile Lower Navigation Bar
        Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF111115),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: isCashier
                ? [
                    // Cashier Tab 1: Sales
                    _buildMobileNavItem(
                      icon: Icons.point_of_sale_rounded,
                      label: 'Sales',
                      isSelected: current == ScreenType.sales,
                      accentColor: accentColor,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(navigationProvider.notifier).state = ScreenType.sales;
                      },
                    ),

                    // Cashier Center Action: Camera Scanner
                    _buildCenterScanButton(context, ref, accentColor),

                    // Cashier Tab 2: Settings
                    _buildMobileNavItem(
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      isSelected: current == ScreenType.settings,
                      accentColor: accentColor,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(navigationProvider.notifier).state = ScreenType.settings;
                      },
                    ),

                    // Cashier Tab 3: Logout
                    _buildMobileNavItem(
                      icon: Icons.logout_rounded,
                      label: 'Logout',
                      isSelected: false,
                      accentColor: Colors.redAccent,
                      iconColor: Colors.redAccent.withValues(alpha: 0.8),
                      onTap: () => _confirmLogout(context, ref),
                    ),
                  ]
                : [
                    // Admin/Manager Tab 1: Overview
                    _buildMobileNavItem(
                      icon: Icons.dashboard_rounded,
                      label: 'Overview',
                      isSelected: current == ScreenType.dashboard,
                      accentColor: accentColor,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(navigationProvider.notifier).state = ScreenType.dashboard;
                      },
                    ),

                    // Admin/Manager Tab 2: Stock
                    _buildMobileNavItem(
                      icon: Icons.inventory_2_rounded,
                      label: 'Stock',
                      isSelected: current == ScreenType.inventory,
                      accentColor: accentColor,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(navigationProvider.notifier).state = ScreenType.inventory;
                      },
                    ),

                    // Admin/Manager Center: Scanner
                    _buildCenterScanButton(context, ref, accentColor),

                    // Admin/Manager Tab 3: Reports
                    _buildMobileNavItem(
                      icon: Icons.assessment_rounded,
                      label: 'Reports',
                      isSelected: current == ScreenType.reports,
                      accentColor: accentColor,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(navigationProvider.notifier).state = ScreenType.reports;
                      },
                    ),

                    // Admin/Manager Tab 4: Settings
                    _buildMobileNavItem(
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      isSelected: current == ScreenType.settings,
                      accentColor: accentColor,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ref.read(navigationProvider.notifier).state = ScreenType.settings;
                      },
                    ),
                  ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileNavItem({
    required IconData icon,
    required String label,
    required bool isSelected,
    required Color accentColor,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? accentColor : (iconColor ?? Colors.white54),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? accentColor : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterScanButton(BuildContext context, WidgetRef ref, Color accentColor) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.heavyImpact();
        _handleGlobalScan(context, ref);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner_rounded, color: Colors.black, size: 20),
            const SizedBox(width: 6),
            Text(
              'SCAN',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.black,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGlobalScan(BuildContext context, WidgetRef ref) async {
    final scannedCode = await CameraBarcodeScannerModal.show(context);
    if (scannedCode != null && scannedCode.isNotEmpty) {
      ref.read(navigationProvider.notifier).state = ScreenType.sales;

      final db = ref.read(databaseServiceProvider);
      final product = await db.getProductBySku(scannedCode);

      if (product != null) {
        ref.read(cartProvider.notifier).addProduct(product);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFFC1F11D), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Added "${product.name}" to cart (K${product.price.toStringAsFixed(2)})'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E1E24),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('No product found matching code "$scannedCode"'),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1E1E24),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Sign Out Cashier?',
          style: GoogleFonts.manrope(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to end your session and log out?',
          style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              HapticFeedback.heavyImpact();
              ref.read(authProvider.notifier).logout(ref);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(
    BuildContext context,
    WidgetRef ref,
    ScreenType current,
    bool isManager,
  ) {
    return Row(
      children: [
        _buildSidebar(context, ref, current, isCompactRail: true),
        Expanded(
          child: Column(
            children: [
              _buildStatusBar(ref, isCompact: false),
              const UpdateBanner(),
              Expanded(child: _buildMainContent(current)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout(
    BuildContext context,
    WidgetRef ref,
    ScreenType current,
    bool isManager, {
    required bool isUltraWide,
  }) {
    return Row(
      children: [
        _buildSidebar(context, ref, current, isCompactRail: false),
        Expanded(
          child: Column(
            children: [
              _buildStatusBar(ref, isCompact: false),
              const UpdateBanner(),
              Expanded(
                child: isUltraWide
                    ? ConstrainedContent(child: _buildMainContent(current))
                    : _buildMainContent(current),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<_NavDestination> _getNavigationDestinations(User? user) {
    if (user == null) return const [];
    
    final role = user.role.toLowerCase().trim();
    final isOwner = role == 'owner' || role == 'admin' || role == 'super_admin';

    if (isOwner) {
      // Headquarters / Corporate Owner (Can manage branches & multi-stores)
      return const [
        _NavDestination(ScreenType.dashboard, Icons.dashboard_rounded, 'Overview'),
        _NavDestination(ScreenType.inventory, Icons.inventory_2_rounded, 'Stock'),
        _NavDestination(ScreenType.purchases, Icons.shopping_bag_rounded, 'Purchases'),
        _NavDestination(ScreenType.branches, Icons.store_rounded, 'Branches'),
        _NavDestination(ScreenType.terminals, Icons.monitor_rounded, 'Terminals'),
        _NavDestination(ScreenType.reports, Icons.assessment_rounded, 'Reports'),
        _NavDestination(ScreenType.settings, Icons.settings_rounded, 'Settings'),
      ];
    } else if (role == 'branch_manager' || role == 'manager') {
      // Branch Manager (STRICTLY NO access to branches tab)
      return const [
        _NavDestination(ScreenType.dashboard, Icons.dashboard_rounded, 'Overview'),
        _NavDestination(ScreenType.inventory, Icons.inventory_2_rounded, 'Stock'),
        _NavDestination(ScreenType.purchases, Icons.shopping_bag_rounded, 'Purchases'),
        _NavDestination(ScreenType.terminals, Icons.monitor_rounded, 'Terminals'),
        _NavDestination(ScreenType.reports, Icons.assessment_rounded, 'Reports'),
        _NavDestination(ScreenType.settings, Icons.settings_rounded, 'Settings'),
      ];
    } else {
      // Cashier role (Sales + Hardware/Printer Settings)
      return const [
        _NavDestination(ScreenType.sales, Icons.point_of_sale_rounded, 'Sales'),
        _NavDestination(ScreenType.settings, Icons.settings_rounded, 'Settings'),
      ];
    }
  }

  Widget _buildSidebar(
    BuildContext context,
    WidgetRef ref,
    ScreenType current, {
    required bool isCompactRail,
  }) {
    final user = ref.watch(authProvider);
    final width = isCompactRail ? 72.0 : 140.0;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  ..._getNavigationDestinations(user).map(
                    (dest) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildSidebarItem(
                        ref,
                        dest.type,
                        dest.icon,
                        dest.label,
                        current,
                        isCompactRail: isCompactRail,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Logo
          if (!isCompactRail)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Consumer(
                builder: (context, ref, child) {
                  final config = ref.watch(storeConfigProvider).value;
                  final logoPath = config?.logoPath;
                  
                  if (logoPath != null && File(logoPath).existsSync()) {
                    return Image.file(
                      File(logoPath),
                      width: 90,
                      height: 90,
                      fit: BoxFit.contain,
                    );
                  }
                  
                  for (final p in ['assets/images/logo.png', 'beleka logo icon.png', '${Directory.current.path}/assets/images/logo.png', '/home/mrm/Documents/programs/beleka-pos-main/beleka logo icon.png']) {
                    if (File(p).existsSync()) {
                      return Image.file(
                        File(p),
                        width: 90,
                        height: 90,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(Icons.bolt_rounded, color: ref.watch(accentColorProvider), size: 32),
                      );
                    }
                  }
                  
                  return Opacity(
                    opacity: 0.6,
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 90,
                      errorBuilder: (context, error, stackTrace) => Icon(Icons.bolt_rounded, color: ref.watch(accentColorProvider), size: 32),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required Color color,
    bool showLoading = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLoading)
            SizedBox(
              width: 10, height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          else
            Icon(icon, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(
    WidgetRef ref,
    ScreenType type,
    IconData icon,
    String label,
    ScreenType current, {
    required bool isCompactRail,
  }) {
    final isActive = current == type;
    final itemWidth = isCompactRail ? 56.0 : 120.0;
    final itemHeight = isCompactRail ? 56.0 : 96.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.mediumImpact();
          ref.read(navigationProvider.notifier).state = type;
        },
        child: Container(
          width: itemWidth,
          height: itemHeight,
          decoration: BoxDecoration(
            color: isActive ? ref.watch(accentColorProvider).withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? ref.watch(accentColorProvider) : Colors.white.withValues(alpha: 0.25),
                size: isCompactRail ? 24 : 36,
              ),
              if (!isCompactRail) ...[
                const SizedBox(height: 6),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? ref.watch(accentColorProvider) : Colors.white.withValues(alpha: 0.25),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBar(WidgetRef ref, {required bool isCompact}) {
    final user = ref.watch(authProvider);
    final accentColor = ref.watch(accentColorProvider);

    return Container(
      height: isCompact ? 48 : 54,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 20),
      decoration: BoxDecoration(
        color: const Color(0xFF111114),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Text(
            isCompact ? 'BELEKA' : 'BELEKA TERMINAL',
            style: GoogleFonts.manrope(
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w900,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(width: 20),
            // Date/Time
            StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapshot) {
                final now = DateTime.now();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${now.day}/${now.month}/${now.year}  ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      color: accentColor.withValues(alpha: 0.7),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(width: 10),
          // Connection Status
          Consumer(
            builder: (context, ref, child) {
              final config = ref.watch(storeConfigProvider).value;
              if (config == null) return const SizedBox.shrink();

              if (config.isManagerMode) {
                return _buildStatusChip(
                  icon: Icons.lan_rounded,
                  label: isCompact ? 'SRV' : 'SERVER ACTIVE',
                  color: accentColor,
                );
              }

              final isOnlineAsync = ref.watch(networkOnlineProvider);
              return isOnlineAsync.when(
                data: (online) => _buildStatusChip(
                  icon: online ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                  label: online ? 'ONLINE' : 'OFFLINE',
                  color: online ? Colors.green : Colors.red,
                ),
                loading: () => _buildStatusChip(
                  icon: Icons.sync_rounded,
                  label: isCompact ? '...' : 'CHECKING...',
                  color: Colors.white.withValues(alpha: 0.3),
                ),
                error: (_, _) => _buildStatusChip(
                  icon: Icons.error_outline_rounded,
                  label: isCompact ? 'OFF' : 'NO CONNECTION',
                  color: Colors.red,
                ),
              );
            },
          ),
          const Spacer(),
          if (!isCompact) ...[
            // Tax reminder — shown when deadlines are within 14 days
            const TaxReminderBanner(),
            const SizedBox(width: 8),
          ],
          // Staff
          Flexible(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 12, vertical: 5),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_outline_rounded, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      (user?.name ?? 'STAFF').toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w800,
                        color: accentColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isCompact) ...[
            const SizedBox(width: 12),
            // Logout
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
              onPressed: () {
                HapticFeedback.heavyImpact();
                ref.read(authProvider.notifier).logout(ref);
              },
              tooltip: 'Sign Out',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMainContent(ScreenType screen) {
    switch (screen) {
      case ScreenType.dashboard:
        return const DashboardScreen();
      case ScreenType.sales:
        return const SalesScreen();
      case ScreenType.inventory:
        return const InventoryScreen();
      case ScreenType.purchases:
        return const PurchasesScreen();
      case ScreenType.branches:
        return const BranchesScreen();
      case ScreenType.terminals:
        return const TerminalsScreen();
      case ScreenType.settings:
        return const SettingsScreen();
      case ScreenType.reports:
        return const ReportsScreen();
    }
  }
}

class _NavDestination {
  final ScreenType type;
  final IconData icon;
  final String label;

  const _NavDestination(this.type, this.icon, this.label);
}

