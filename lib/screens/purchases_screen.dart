import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:isar/isar.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/services/export_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/services/local_sql_service.dart';
import 'package:beleka_pos/services/digitax_inventory_service.dart';

// --- DATA PROVIDERS ---

final purchaseOrdersProvider = FutureProvider<List<PurchaseOrder>>((ref) async {
  final isar = ref.watch(isarProvider);
  final pos = await isar.purchaseOrders.where().sortByCreatedAtDesc().findAll();
  for (var po in pos) {
    await po.items.load();
  }
  return pos;
});

final suppliersProvider = StreamProvider<List<Supplier>>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.suppliers.where().sortByName().watch(fireImmediately: true);
});

final grnListProvider = FutureProvider<List<GoodsReceivedNote>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.goodsReceivedNotes.where().sortByCreatedAtDesc().findAll();
});

final purchaseInvoicesProvider = FutureProvider<List<PurchaseInvoice>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.purchaseInvoices.where().sortByCreatedAtDesc().findAll();
});

final purchaseReturnsProvider = FutureProvider<List<PurchaseReturn>>((ref) async {
  final isar = ref.watch(isarProvider);
  return await isar.purchaseReturns.where().sortByCreatedAtDesc().findAll();
});

final purchasesProductsProvider = StreamProvider<List<Product>>((ref) {
  final isar = ref.watch(isarProvider);
  return isar.products.filter().isArchivedEqualTo(false).sortByName().watch(fireImmediately: true);
});

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({super.key});

  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final accentColor = primaryColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 700;

        return Container(
          color: theme.scaffoldBackgroundColor,
          padding: EdgeInsets.all(isPhone ? 14 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBreadcrumbBar(context),
              const SizedBox(height: 16),
              // Header Bar – adaptive
              if (isPhone)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SUPPLY CHAIN & PURCHASES',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'POs, goods receipt (GRN), supplier bills, and returns',
                      style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        PopupMenuButton<String>(
                          onSelected: (value) async {
                            final export = ref.read(exportServiceProvider);
                            final config = ref.read(storeConfigProvider).value;
                            final pos = await ref.read(purchaseOrdersProvider.future);
                            final grns = await ref.read(grnListProvider.future);
                            final invoices = await ref.read(purchaseInvoicesProvider.future);
                            final returns = await ref.read(purchaseReturnsProvider.future);

                            switch (value) {
                              case 'po_pdf':
                                export.exportPurchaseOrdersListToPdf(pos, config: config);
                                break;
                              case 'po_excel':
                                export.exportPurchaseOrdersListToExcel(pos, config: config);
                                break;
                              case 'grn_pdf':
                                export.exportGoodsReceivedNotesToPdf(grns, config: config);
                                break;
                              case 'invoices_pdf':
                                export.exportPurchaseInvoicesToPdf(invoices, config: config);
                                break;
                              case 'returns_pdf':
                                export.exportPurchaseReturnsToPdf(returns, config: config);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'po_pdf', child: Row(children: [Icon(Icons.picture_as_pdf, color: Color(0xFFDC2626), size: 16), SizedBox(width: 8), Text('Export POs (PDF)')])),
                            const PopupMenuItem(value: 'po_excel', child: Row(children: [Icon(Icons.table_chart_rounded, color: Color(0xFF059669), size: 16), SizedBox(width: 8), Text('Export POs (Excel)')])),
                            const PopupMenuItem(value: 'grn_pdf', child: Row(children: [Icon(Icons.inventory_2_rounded, color: Color(0xFF0284C7), size: 16), SizedBox(width: 8), Text('Export GRNs (PDF)')])),
                            const PopupMenuItem(value: 'invoices_pdf', child: Row(children: [Icon(Icons.receipt_long_rounded, color: Color(0xFFD97706), size: 16), SizedBox(width: 8), Text('Export Invoices & Bills (PDF)')])),
                            const PopupMenuItem(value: 'returns_pdf', child: Row(children: [Icon(Icons.assignment_return_rounded, color: Color(0xFF0284C7), size: 16), SizedBox(width: 8), Text('Export Returns (PDF)')])),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.download_rounded, size: 15, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 5),
                                Text('Export', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: theme.colorScheme.onSurface)),
                              ],
                            ),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showAddSupplierDialog(context, ref, accentColor),
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 15),
                          label: Text('+ Supplier', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9),
                            foregroundColor: theme.colorScheme.onSurface,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showCreatePoDialog(context, ref, accentColor),
                          icon: const Icon(Icons.add_shopping_cart_rounded, size: 15, color: Colors.white),
                          label: Text('+ Create PO', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.white)),
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
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SUPPLY CHAIN & PURCHASES',
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Purchase orders, goods receipt (GRN), supplier billing, returns, and inventory restocking',
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
                            final pos = await ref.read(purchaseOrdersProvider.future);
                            final grns = await ref.read(grnListProvider.future);
                            final invoices = await ref.read(purchaseInvoicesProvider.future);
                            final returns = await ref.read(purchaseReturnsProvider.future);

                            switch (value) {
                              case 'po_pdf':
                                export.exportPurchaseOrdersListToPdf(pos, config: config);
                                break;
                              case 'po_excel':
                                export.exportPurchaseOrdersListToExcel(pos, config: config);
                                break;
                              case 'grn_pdf':
                                export.exportGoodsReceivedNotesToPdf(grns, config: config);
                                break;
                              case 'invoices_pdf':
                                export.exportPurchaseInvoicesToPdf(invoices, config: config);
                                break;
                              case 'returns_pdf':
                                export.exportPurchaseReturnsToPdf(returns, config: config);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'po_pdf', child: Row(children: [Icon(Icons.picture_as_pdf, color: Color(0xFFDC2626), size: 16), SizedBox(width: 8), Text('Export POs (PDF)')])),
                            const PopupMenuItem(value: 'po_excel', child: Row(children: [Icon(Icons.table_chart_rounded, color: Color(0xFF059669), size: 16), SizedBox(width: 8), Text('Export POs (Excel)')])),
                            const PopupMenuItem(value: 'grn_pdf', child: Row(children: [Icon(Icons.inventory_2_rounded, color: Color(0xFF0284C7), size: 16), SizedBox(width: 8), Text('Export GRNs (PDF)')])),
                            const PopupMenuItem(value: 'invoices_pdf', child: Row(children: [Icon(Icons.receipt_long_rounded, color: Color(0xFFD97706), size: 16), SizedBox(width: 8), Text('Export Invoices & Bills (PDF)')])),
                            const PopupMenuItem(value: 'returns_pdf', child: Row(children: [Icon(Icons.assignment_return_rounded, color: Color(0xFF0284C7), size: 16), SizedBox(width: 8), Text('Export Returns (PDF)')])),
                          ],
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.download_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Text('Export & Print', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: theme.colorScheme.onSurface)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showAddSupplierDialog(context, ref, accentColor),
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                          label: Text('New Supplier', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF293548) : const Color(0xFFF1F5F9),
                            foregroundColor: theme.colorScheme.onSurface,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showCreatePoDialog(context, ref, accentColor),
                          icon: const Icon(Icons.add_shopping_cart_rounded, size: 16, color: Colors.white),
                          label: Text('Create Purchase Order', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
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
              const SizedBox(height: 16),

              // Tab Bar
              Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF151F32) : const Color(0xFFFFFFFF),
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
                  tabs: const [
                    Tab(icon: Icon(Icons.dashboard_rounded, size: 18), text: 'Dashboard'),
                    Tab(icon: Icon(Icons.people_alt_rounded, size: 18), text: 'Suppliers'),
                    Tab(icon: Icon(Icons.shopping_bag_rounded, size: 18), text: 'Purchase Orders'),
                    Tab(icon: Icon(Icons.move_to_inbox_rounded, size: 18), text: 'Goods Received (GRN)'),
                    Tab(icon: Icon(Icons.receipt_long_rounded, size: 18), text: 'Invoices & Bills'),
                    Tab(icon: Icon(Icons.assignment_return_rounded, size: 18), text: 'Returns'),
                    Tab(icon: Icon(Icons.handshake_rounded, size: 18), text: 'Consignment & Commission'),
                    Tab(icon: Icon(Icons.analytics_rounded, size: 18), text: 'Reports'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Tab View Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDashboardTab(accentColor),
                    _buildSuppliersTab(accentColor),
                    _buildPurchaseOrdersTab(accentColor),
                    _buildGrnTab(accentColor),
                    _buildInvoicesTab(accentColor),
                    _buildReturnsTab(accentColor),
                    _buildConsignmentTab(accentColor),
                    _buildReportsTab(accentColor),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==========================================
  // TAB 1: DASHBOARD
  // ==========================================
  Widget _buildDashboardTab(Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final pos = ref.watch(purchaseOrdersProvider).value ?? [];
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final grns = ref.watch(grnListProvider).value ?? [];
    final invoices = ref.watch(purchaseInvoicesProvider).value ?? [];
    final returns = ref.watch(purchaseReturnsProvider).value ?? [];

    final totalPurchases = pos.fold<double>(0.0, (s, p) => s + p.totalAmount);
    final pendingCount = pos.where((p) => p.status == 'pending' || p.status == 'draft').length;
    final receivedCount = grns.length;
    final unpaidBalance = invoices.fold<double>(0.0, (s, i) => s + i.balanceDue);
    final returnsTotal = returns.fold<double>(0.0, (s, r) => s + r.totalAmount);

    return LayoutBuilder(
      builder: (context, c) {
        final isPhone = c.maxWidth < 700;

        final topSuppliersCard = Container(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('TOP SUPPLIERS', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
                  Icon(Icons.star_rounded, color: primaryColor, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              if (suppliers.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: Text('No suppliers recorded yet', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant))),
                )
              else
                ...suppliers.take(4).map((s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                    radius: 16,
                    child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  title: Text(s.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                  subtitle: Text('Balance: $currency ${s.balance.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 11, color: s.balance > 0 ? Colors.redAccent : Colors.green)),
                )),
            ],
          ),
        );

        final recentPoCard = Container(
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
                  Text('RECENT PURCHASE ORDERS', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
                  Text('View all in PO Tab', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: primaryColor)),
                ],
              ),
              const SizedBox(height: 16),
              if (pos.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No purchase orders created yet', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant))),
                )
              else
                ...pos.take(4).map((po) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(po.poNumber, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                          Text('${po.supplierName} • ${DateFormat('dd MMM yyyy').format(po.createdAt)}', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: po.status == 'approved' || po.status == 'received' ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              po.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: po.status == 'approved' || po.status == 'received' ? const Color(0xFF059669) : const Color(0xFFD97706),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text('$currency ${po.totalAmount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: primaryColor)),
                        ],
                      ),
                    ],
                  ),
                )),
            ],
          ),
        );

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // KPI Metric Cards – responsive
              GridView.count(
                crossAxisCount: isPhone ? 2 : (c.maxWidth < 1100 ? 3 : 6),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: isPhone ? 1.65 : 2.3,
                children: [
                  _buildKpiCard('TOTAL PURCHASES', '$currency ${totalPurchases.toStringAsFixed(2)}', '${pos.length} Orders Placed', Icons.account_balance_wallet_rounded, Colors.blue),
                  _buildKpiCard('PENDING APPROVAL', '$pendingCount Orders', 'Awaiting authorization', Icons.pending_actions_rounded, Colors.amber),
                  _buildKpiCard('GOODS RECEIVED (GRN)', '$receivedCount GRNs', 'Restocked into inventory', Icons.inventory_rounded, Colors.green),
                  _buildKpiCard('UNPAID BILLS', '$currency ${unpaidBalance.toStringAsFixed(2)}', '${invoices.where((i) => i.balanceDue > 0).length} Unpaid', Icons.money_off_rounded, Colors.redAccent),
                  _buildKpiCard('PURCHASE RETURNS', '$currency ${returnsTotal.toStringAsFixed(2)}', '${returns.length} Credits', Icons.assignment_return_rounded, Colors.purpleAccent),
                  _buildKpiCard('ACTIVE SUPPLIERS', '${suppliers.length} Vendors', 'Trade partners', Icons.handshake_rounded, accentColor),
                ],
              ),
              const SizedBox(height: 20),

              // Top Suppliers & Recent Activity
              if (isPhone)
                Column(
                  children: [
                    topSuppliersCard,
                    const SizedBox(height: 16),
                    recentPoCard,
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 1, child: topSuppliersCard),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: recentPoCard),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopBreadcrumbBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Workspace',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'Supply Chain & Purchases',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
                    'DigiTax Supplier Sync Active',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF059669),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF151F32) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151F32) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? color.withValues(alpha: 0.15) : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: SUPPLIERS
  // ==========================================
  Widget _buildSuppliersTab(Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final suppliersAsync = ref.watch(suppliersProvider);

    return suppliersAsync.when(
      data: (suppliers) {
        if (suppliers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_outline_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('No Suppliers Found', style: GoogleFonts.inter(fontSize: 16, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _showAddSupplierDialog(context, ref, accentColor),
                  style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
                  child: const Text('Add First Supplier'),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 450,
            mainAxisExtent: 220,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: suppliers.length,
          itemBuilder: (context, index) {
            final s = suppliers[index];
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
                    children: [
                      CircleAvatar(
                        backgroundColor: isDark ? primaryColor.withValues(alpha: 0.15) : const Color(0xFFEFF6FF),
                        radius: 20,
                        child: Text(s.name.isNotEmpty ? s.name[0].toUpperCase() : 'S', style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15, color: theme.colorScheme.onSurface)),
                            Text('TPIN: ${s.tpin ?? "N/A"} • ${s.phoneNumber ?? "No Phone"}', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(s.address ?? 'Zambia Address', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const Spacer(),
                  Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Outstanding Balance', style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                          Text('$currency ${s.balance.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: s.balance > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669))),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              final invoices = ref.read(purchaseInvoicesProvider).value ?? [];
                              ref.read(exportServiceProvider).exportSupplierStatementToPdf(s, invoices: invoices, config: config, printDirectly: true);
                            },
                            icon: Icon(Icons.print_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                            tooltip: 'Print Statement',
                          ),
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              final invoices = ref.read(purchaseInvoicesProvider).value ?? [];
                              ref.read(exportServiceProvider).exportSupplierStatementToPdf(s, invoices: invoices, config: config, printDirectly: false);
                            },
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
                            tooltip: 'Export Statement PDF',
                          ),
                          const SizedBox(width: 4),
                          TextButton.icon(
                            onPressed: () => _showSupplierStatement(context, s, currency),
                            icon: const Icon(Icons.receipt_rounded, size: 14),
                            label: const Text('View'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  // ==========================================
  // TAB 3: PURCHASE ORDERS
  // ==========================================
  Widget _buildPurchaseOrdersTab(Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final poAsync = ref.watch(purchaseOrdersProvider);

    return poAsync.when(
      data: (orders) {
        if (orders.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('No Purchase Orders Found', style: GoogleFonts.inter(fontSize: 16, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final po = orders[index];
            final isApproved = po.status == 'approved' || po.status == 'received';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                      color: isApproved ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isApproved ? Icons.check_circle_rounded : Icons.pending_actions_rounded,
                      color: isApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(po.poNumber, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isApproved ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                po.status.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isApproved ? const Color(0xFF059669) : const Color(0xFFD97706),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Supplier: ${po.supplierName} ${po.supplierTpin != null ? "(TPIN: ${po.supplierTpin})" : ""}',
                          style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ordered on ${DateFormat('dd MMM yyyy, HH:mm').format(po.createdAt)} • ${po.items.length} Line Items',
                          style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$currency ${po.totalAmount.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: primaryColor),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportPurchaseOrderToPdf(po, config: config, printDirectly: true);
                            },
                            icon: Icon(Icons.print_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                            tooltip: 'Print PO Document',
                          ),
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportPurchaseOrderToPdf(po, config: config, printDirectly: false);
                            },
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
                            tooltip: 'Export PO to PDF',
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            onPressed: () => _syncPoToDigitax(context, ref, po),
                            icon: const Icon(Icons.cloud_upload_rounded, size: 18, color: Color(0xFF0284C7)),
                            tooltip: 'Sync PO to DigiTax VSDC Cloud',
                          ),
                          const SizedBox(width: 6),
                          if (po.status == 'pending' || po.status == 'draft')
                            ElevatedButton.icon(
                              onPressed: () => _approvePo(context, ref, po),
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text('Approve PO'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF059669),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            )
                          else if (po.status == 'approved')
                            ElevatedButton.icon(
                              onPressed: () => _showReceiveGrnModal(context, ref, po),
                              icon: const Icon(Icons.move_to_inbox_rounded, size: 16),
                              label: const Text('Receive Goods (GRN)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            )
                          else
                            Row(
                              children: [
                                const Icon(Icons.verified_rounded, color: Color(0xFF059669), size: 16),
                                const SizedBox(width: 4),
                                Text('Fully Received', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF059669))),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  // ==========================================
  // TAB 4: GOODS RECEIVED (GRN)
  // ==========================================
  Widget _buildGrnTab(Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final grnsAsync = ref.watch(grnListProvider);

    return grnsAsync.when(
      data: (grns) {
        if (grns.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.move_to_inbox_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('No Goods Received Notes (GRN) Recorded', style: GoogleFonts.inter(fontSize: 16, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Text('Approve a Purchase Order and click "Receive Goods (GRN)" to log arriving shipments.', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: grns.length,
          itemBuilder: (context, index) {
            final g = grns[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.check_box_rounded, color: Color(0xFF059669), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(g.grnNumber, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                        const SizedBox(height: 4),
                        Text('Linked PO: ${g.poNumber} • Supplier: ${g.supplierName}', style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text('Received at ${g.warehouseBranch} on ${DateFormat('dd MMM yyyy').format(g.receivedDate)} • ${g.totalItemsReceived} Units Restocked', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          final config = ref.read(storeConfigProvider).value;
                          ref.read(exportServiceProvider).exportGoodsReceivedNoteToPdf(g, config: config, printDirectly: true);
                        },
                        icon: Icon(Icons.print_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                        tooltip: 'Print GRN',
                      ),
                      IconButton(
                        onPressed: () {
                          final config = ref.read(storeConfigProvider).value;
                          ref.read(exportServiceProvider).exportGoodsReceivedNoteToPdf(g, config: config, printDirectly: false);
                        },
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
                        tooltip: 'Export GRN to PDF',
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('STOCK UPDATED', style: TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 10)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  // ==========================================
  // TAB 5: INVOICES & BILLS
  // ==========================================
  Widget _buildInvoicesTab(Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final invoicesAsync = ref.watch(purchaseInvoicesProvider);

    return invoicesAsync.when(
      data: (invoices) {
        if (invoices.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 16),
                Text('No Supplier Invoices Recorded', style: GoogleFonts.inter(fontSize: 16, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: invoices.length,
          itemBuilder: (context, index) {
            final inv = invoices[index];
            final isPaid = inv.paymentStatus == 'paid';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
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
                      color: isPaid ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(isPaid ? Icons.check_circle_outline : Icons.receipt_rounded, color: isPaid ? const Color(0xFF059669) : const Color(0xFFDC2626), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(inv.invoiceNumber, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                        const SizedBox(height: 4),
                        Text('Supplier: ${inv.supplierName} • Ref: ${inv.supplierInvoiceNumber ?? "N/A"}', style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text('PO: ${inv.poNumber} • Due: ${inv.dueDate != null ? DateFormat('dd MMM yyyy').format(inv.dueDate!) : "Upon Receipt"}', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$currency ${inv.totalAmount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      Text('Balance Due: $currency ${inv.balanceDue.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: inv.balanceDue > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669))),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportPurchaseInvoiceToPdf(inv, config: config, printDirectly: true);
                            },
                            icon: Icon(Icons.print_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                            tooltip: 'Print Invoice / Bill',
                          ),
                          IconButton(
                            onPressed: () {
                              final config = ref.read(storeConfigProvider).value;
                              ref.read(exportServiceProvider).exportPurchaseInvoiceToPdf(inv, config: config, printDirectly: false);
                            },
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
                            tooltip: 'Export Invoice to PDF',
                          ),
                          if (inv.balanceDue > 0) ...[
                            const SizedBox(width: 6),
                            ElevatedButton(
                              onPressed: () => _showRecordPaymentModal(context, ref, inv),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                              child: const Text('Record Payment'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
    );
  }

  // ==========================================
  // TAB 6: RETURNS
  // ==========================================
  Widget _buildReturnsTab(Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final returnsAsync = ref.watch(purchaseReturnsProvider);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              onPressed: () => _showCreateReturnDialog(context, ref, accentColor),
              icon: const Icon(Icons.assignment_return_rounded, size: 16),
              label: const Text('Create Purchase Return'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: returnsAsync.when(
            data: (returns) {
              if (returns.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_return_rounded, size: 64, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
                      const SizedBox(height: 16),
                      Text('No Purchase Returns Recorded', style: GoogleFonts.inter(fontSize: 16, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                itemCount: returns.length,
                itemBuilder: (context, index) {
                  final ret = returns[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
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
                            color: const Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.assignment_return_rounded, color: Color(0xFF0284C7), size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(ret.returnNumber, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                              const SizedBox(height: 4),
                              Text('Supplier: ${ret.supplierName} • Reason: ${ret.reason}', style: GoogleFonts.inter(fontSize: 12.5, color: theme.colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 4),
                              Text('Refund: ${ret.refundMethod} on ${DateFormat('dd MMM yyyy').format(ret.createdAt)}', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            Text('$currency ${ret.totalAmount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0284C7))),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                final config = ref.read(storeConfigProvider).value;
                                ref.read(exportServiceProvider).exportPurchaseReturnToPdf(ret, config: config, printDirectly: true);
                              },
                              icon: Icon(Icons.print_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
                              tooltip: 'Print Debit Note',
                            ),
                            IconButton(
                              onPressed: () {
                                final config = ref.read(storeConfigProvider).value;
                                ref.read(exportServiceProvider).exportPurchaseReturnToPdf(ret, config: config, printDirectly: false);
                              },
                              icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
                              tooltip: 'Export Debit Note to PDF',
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 7: REPORTS
  // ==========================================
  Widget _buildReportsTab(Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final pos = ref.watch(purchaseOrdersProvider).value ?? [];
    final suppliers = ref.watch(suppliersProvider).value ?? [];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PURCHASE ANALYTICS & TAX BREAKDOWN', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151F32) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Purchases Summary by Supplier', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                const SizedBox(height: 12),
                if (suppliers.isEmpty)
                  Text('No purchase records available for report generation', style: GoogleFonts.inter(color: theme.colorScheme.onSurfaceVariant))
                else
                  ...suppliers.map((s) {
                    final supPos = pos.where((p) => p.supplierName == s.name);
                    final totalVal = supPos.fold<double>(0.0, (sum, p) => sum + p.totalAmount);
                    return ListTile(
                      title: Text(s.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                      subtitle: Text('${supPos.length} Orders Placed • TPIN: ${s.tpin ?? "N/A"}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      trailing: Text('$currency ${totalVal.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 7: CONSIGNMENT & COMMISSION
  // ==========================================
  Widget _buildConsignmentTab(Color accentColor) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final productsAsync = ref.watch(purchasesProductsProvider);
    final products = productsAsync.value ?? [];

    final consignmentProducts = products.where((p) => p.isConsignment).toList();

    // Consignment suppliers: either suppliers with balance or linked to consignment products
    final consignmentSupplierIds = consignmentProducts.map((p) => p.consignmentSupplierId).whereType<int>().toSet();
    final consignmentSupplierNames = consignmentProducts.map((p) => (p.consignmentSupplierName ?? '').toLowerCase()).where((name) => name.isNotEmpty).toSet();

    final activeConsignmentSuppliers = suppliers.where((s) {
      final matchesId = consignmentSupplierIds.contains(s.id);
      final matchesName = s.name.isNotEmpty && consignmentSupplierNames.contains(s.name.toLowerCase());
      final hasBalance = s.balance > 0;
      return matchesId || matchesName || hasBalance;
    }).toList();

    final totalPayable = activeConsignmentSuppliers.fold<double>(0.0, (sum, s) => sum + (s.balance > 0 ? s.balance : 0.0));
    final totalInStockUnits = consignmentProducts.fold<int>(0, (sum, p) => sum + p.stockLevel);
    final totalConsignmentRetailValue = consignmentProducts.fold<double>(0.0, (sum, p) => sum + (p.price * p.stockLevel));
    
    final totalVendorStockValue = consignmentProducts.fold<double>(0.0, (sum, p) {
      final unitPayout = (p.consignmentSupplierPayoutPrice > 0)
          ? p.consignmentSupplierPayoutPrice
          : (p.price * (1.0 - ((p.consignmentCommissionRate > 0 ? p.consignmentCommissionRate : 15.0) / 100.0))).clamp(0.0, p.price);
      return sum + (unitPayout * p.stockLevel);
    });

    final potentialStoreCommission = consignmentProducts.fold<double>(0.0, (sum, p) {
      final unitPayout = (p.consignmentSupplierPayoutPrice > 0)
          ? p.consignmentSupplierPayoutPrice
          : (p.price * (1.0 - ((p.consignmentCommissionRate > 0 ? p.consignmentCommissionRate : 15.0) / 100.0))).clamp(0.0, p.price);
      final unitProfit = (p.price - unitPayout).clamp(0.0, p.price);
      return sum + (unitProfit * p.stockLevel);
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final isPhone = constraints.maxWidth < 600;
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Summary Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CONSIGNMENT & SUPPLIER COMMISSION', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
                        const SizedBox(height: 2),
                        Text('Products sold on behalf of vendors, pass-through liabilities & commission earnings', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // KPI Cards
              GridView.count(
                crossAxisCount: isPhone ? 2 : 4,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: isPhone ? 1.65 : 2.2,
                children: [
                  _buildKpiCard('TOTAL PAYABLE TO VENDORS', '$currency ${totalPayable.toStringAsFixed(2)}', 'Accumulated liability for sold items', Icons.account_balance_wallet_rounded, const Color(0xFFEF4444)),
                  _buildKpiCard('ACTIVE CONSIGNED ITEMS', '${consignmentProducts.length} Items', '$totalInStockUnits units currently in inventory', Icons.inventory_2_rounded, const Color(0xFF3B82F6)),
                  _buildKpiCard('IN-STOCK RETAIL VALUE', '$currency ${totalConsignmentRetailValue.toStringAsFixed(2)}', 'Vendor Share: $currency ${totalVendorStockValue.toStringAsFixed(2)}', Icons.storefront_rounded, const Color(0xFF10B981)),
                  _buildKpiCard('POTENTIAL COMMISSION', '$currency ${potentialStoreCommission.toStringAsFixed(2)}', 'Store margin on remaining stock', Icons.percent_rounded, const Color(0xFF8B5CF6)),
                ],
              ),
              const SizedBox(height: 20),

          // Consignment Suppliers Table
          Container(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.handshake_rounded, size: 20, color: accentColor),
                        const SizedBox(width: 8),
                        Text('Consignment Suppliers & Balances Owed', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: theme.colorScheme.onSurface)),
                      ],
                    ),
                    Text('${activeConsignmentSuppliers.length} Suppliers', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                if (activeConsignmentSuppliers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 36, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                          const SizedBox(height: 8),
                          Text('No consignment suppliers found.', style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 4),
                          Text('To enable consignment, edit or add a product in Inventory and enable "Sell on Behalf of Supplier (Consignment)".', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: activeConsignmentSuppliers.length,
                    separatorBuilder: (_, _) => Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                    itemBuilder: (context, index) {
                      final s = activeConsignmentSuppliers[index];
                      final supplierProducts = consignmentProducts.where((p) => p.consignmentSupplierId == s.id || ((p.consignmentSupplierName ?? '').toLowerCase() == s.name.toLowerCase())).toList();
                      final totalUnits = supplierProducts.fold<int>(0, (sum, p) => sum + p.stockLevel);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: s.balance > 0 ? const Color(0xFFEF4444).withValues(alpha: 0.15) : const Color(0xFF10B981).withValues(alpha: 0.15),
                              child: Icon(
                                s.balance > 0 ? Icons.monetization_on_outlined : Icons.check_circle_outline_rounded,
                                color: s.balance > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${s.phoneNumber ?? "No phone"} • ${s.email ?? "No email"} • TPIN: ${s.tpin ?? "N/A"}',
                                    style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${supplierProducts.length} Consigned Items', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: theme.colorScheme.onSurface)),
                                  const SizedBox(height: 2),
                                  Text('$totalUnits units in stock', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('Balance Due', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurfaceVariant)),
                                  Text(
                                    '$currency ${s.balance.toStringAsFixed(2)}',
                                    style: GoogleFonts.manrope(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                      color: s.balance > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final isar = ref.read(isarProvider);
                                    final transactions = await isar.saleTransactions.where().findAll();
                                    for (final tx in transactions) {
                                      if (!tx.items.isLoaded) {
                                        await tx.items.load();
                                      }
                                    }
                                    final config = ref.read(storeConfigProvider).value;
                                    if (context.mounted) {
                                      await ref.read(exportServiceProvider).exportConsignmentStatementToPdf(
                                        supplier: s,
                                        consignmentProducts: supplierProducts,
                                        transactions: transactions,
                                        config: config,
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 15, color: Color(0xFFEF4444)),
                                  label: Text('Statement', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: s.balance <= 0
                                      ? null
                                      : () => _showConsignmentSettlementModal(context, ref, s, currency),
                                  icon: const Icon(Icons.payments_rounded, size: 15),
                                  label: Text('Settle / Pay', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Consignment Products List Table
          Container(
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.inventory_2_rounded, size: 20, color: const Color(0xFF3B82F6)),
                        const SizedBox(width: 8),
                        Text('Consignment Products Catalog & Commission Split', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: theme.colorScheme.onSurface)),
                      ],
                    ),
                    Text('${consignmentProducts.length} Items', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 12),
                if (consignmentProducts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('No consignment products registered.', style: GoogleFonts.inter(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                      columns: [
                        DataColumn(label: Text('Product Name', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Supplier', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Stock', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Retail Price', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Supplier Payout', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Commission Rate', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                        DataColumn(label: Text('Store Profit / Unit', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                      ],
                      rows: consignmentProducts.map((prod) {
                        final unitPayout = (prod.consignmentSupplierPayoutPrice > 0)
                            ? prod.consignmentSupplierPayoutPrice
                            : (prod.price * (1.0 - ((prod.consignmentCommissionRate > 0 ? prod.consignmentCommissionRate : 15.0) / 100.0))).clamp(0.0, prod.price);
                        final profitPerUnit = (prod.price - unitPayout).clamp(0.0, prod.price);

                        return DataRow(
                          cells: [
                            DataCell(
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(prod.name, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                                  if (prod.sku.isNotEmpty)
                                    Text(prod.sku, style: GoogleFonts.inter(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            DataCell(Text(prod.consignmentSupplierName ?? 'Unassigned', style: GoogleFonts.inter(fontSize: 12))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: prod.stockLevel > 0 ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFFEF4444).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${prod.stockLevel}',
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: prod.stockLevel > 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  ),
                                ),
                              ),
                            ),
                            DataCell(Text('$currency ${prod.price.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12))),
                            DataCell(Text('$currency ${unitPayout.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 12, color: const Color(0xFFD97706)))),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${prod.consignmentCommissionRate.toStringAsFixed(1)}%',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11, color: const Color(0xFF8B5CF6)),
                                ),
                              ),
                            ),
                            DataCell(Text('$currency ${profitPerUnit.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: const Color(0xFF10B981)))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
      },
    );
  }

  void _showConsignmentSettlementModal(BuildContext context, WidgetRef ref, Supplier supplier, String currency) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ConsignmentSettlementModal(supplier: supplier, currency: currency),
    );
  }

  // --- ACTIONS & MODALS ---

  Future<void> _approvePo(BuildContext context, WidgetRef ref, PurchaseOrder po) async {
    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      po.status = 'approved';
      po.approvedAt = DateTime.now();
      await isar.purchaseOrders.put(po);
    });
    ref.invalidate(purchaseOrdersProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchase Order ${po.poNumber} Approved! Ready for Goods Receipt (GRN).'), backgroundColor: Colors.green[800]),
      );
    }
  }

  Future<void> _syncPoToDigitax(BuildContext context, WidgetRef ref, PurchaseOrder po) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 12),
            Text('Submitting ${po.poNumber} to DigiTax VSDC Cloud...'),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    final isar = ref.read(isarProvider);
    final supplier = await isar.suppliers.filter().nameEqualTo(po.supplierName).findFirst();

    final success = await ref.read(digitaxInventoryServiceProvider).syncPurchaseIntake(
      poNumber: po.poNumber,
      supplierName: po.supplierName,
      supplierTin: supplier?.tpin,
      items: po.items.map((i) => {
        'productId': i.productId,
        'sku': 'SKU-${i.productId}',
        'name': i.productName,
        'qty': i.quantityOrdered > 0 ? i.quantityOrdered : 1,
        'cost': i.unitCost,
      }).toList(),
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Successfully synced ${po.poNumber} & cloud stock to DigiTax!'
              : 'Sync completed locally. (Check DigiTax API Key / Products if not in cloud dashboard)'),
          backgroundColor: success ? Colors.green[800] : Colors.blueGrey[800],
        ),
      );
    }
  }

  void _showReceiveGrnModal(BuildContext context, WidgetRef ref, PurchaseOrder po) {
    showDialog(
      context: context,
      builder: (context) => _ReceiveGrnModal(po: po),
    );
  }

  void _showRecordPaymentModal(BuildContext context, WidgetRef ref, PurchaseInvoice invoice) {
    showDialog(
      context: context,
      builder: (context) => _RecordPaymentModal(invoice: invoice),
    );
  }

  void _showAddSupplierDialog(BuildContext context, WidgetRef ref, Color accentColor) {
    showDialog(
      context: context,
      builder: (context) => _AddSupplierModal(accentColor: accentColor),
    );
  }

  void _showCreatePoDialog(BuildContext context, WidgetRef ref, Color accentColor) {
    showDialog(
      context: context,
      builder: (context) => _CreatePoModal(accentColor: accentColor),
    );
  }

  void _showCreateReturnDialog(BuildContext context, WidgetRef ref, Color accentColor) {
    showDialog(
      context: context,
      builder: (context) => _CreateReturnModal(accentColor: accentColor),
    );
  }

  void _showSupplierStatement(BuildContext context, Supplier s, String currency) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final invoices = ref.read(purchaseInvoicesProvider).value ?? [];
    final suppInvoices = invoices.where((i) => i.supplierName == s.name).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        title: Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: Color(0xFF059669), size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text('STATEMENT: ${s.name}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: theme.colorScheme.onSurface))),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C283D) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TPIN: ${s.tpin ?? "N/A"} • Phone: ${s.phoneNumber ?? "N/A"}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                    Text('Email: ${s.email ?? "N/A"}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                    Text('Address: ${s.address ?? "N/A"}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: s.balance > 0 ? const Color(0xFFFEF2F2) : const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Outstanding Payable Balance:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)),
                    Text('$currency ${s.balance.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: s.balance > 0 ? const Color(0xFFDC2626) : const Color(0xFF059669))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Recent Invoices (${suppInvoices.length})', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.onSurface)),
              const SizedBox(height: 6),
              if (suppInvoices.isEmpty)
                Text('No invoices found.', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant))
              else
                ...suppInvoices.take(3).map((inv) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(inv.invoiceNumber, style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface)),
                      Text('$currency ${inv.totalAmount.toStringAsFixed(2)} (${inv.paymentStatus})', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
          OutlinedButton.icon(
            onPressed: () {
              final config = ref.read(storeConfigProvider).value;
              ref.read(exportServiceProvider).exportSupplierStatementToPdf(s, invoices: invoices, config: config, printDirectly: false);
            },
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 16, color: Color(0xFFDC2626)),
            label: const Text('Export PDF'),
            style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.onSurface),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final config = ref.read(storeConfigProvider).value;
              ref.read(exportServiceProvider).exportSupplierStatementToPdf(s, invoices: invoices, config: config, printDirectly: true);
            },
            icon: const Icon(Icons.print_rounded, size: 16),
            label: const Text('Print Statement'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}

// --- MODAL DIALOGS ---

class _AddSupplierModal extends ConsumerStatefulWidget {
  final Color accentColor;
  const _AddSupplierModal({required this.accentColor});

  @override
  ConsumerState<_AddSupplierModal> createState() => _AddSupplierModalState();
}

class _AddSupplierModalState extends ConsumerState<_AddSupplierModal> {
  final _nameCtrl = TextEditingController();
  final _tpinCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tpinCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    final isar = ref.read(isarProvider);
    final localSql = ref.read(localSqlServiceProvider);

    final supplier = Supplier()
      ..name = _nameCtrl.text.trim()
      ..tpin = _tpinCtrl.text.trim()
      ..contactPerson = _contactCtrl.text.trim()
      ..phoneNumber = _phoneCtrl.text.trim()
      ..email = _emailCtrl.text.trim()
      ..address = _addressCtrl.text.trim();

    await isar.writeTxn(() async {
      await isar.suppliers.put(supplier);
    });

    await localSql.insert('suppliers', {
      'name': supplier.name,
      'tpin': supplier.tpin,
      'contact_person': supplier.contactPerson,
      'phone_number': supplier.phoneNumber,
      'email': supplier.email,
      'address': supplier.address,
      'balance': 0.0,
      'total_purchases': 0.0,
      'created_at': DateTime.now().toIso8601String(),
    });

    ref.invalidate(suppliersProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      title: Text('ADD NEW SUPPLIER', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: theme.colorScheme.onSurface)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Supplier / Company Name', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _tpinCtrl, decoration: const InputDecoration(labelText: 'ZRA TPIN Number', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _contactCtrl, decoration: const InputDecoration(labelText: 'Contact Person', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _emailCtrl, decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _addressCtrl, decoration: const InputDecoration(labelText: 'Physical Address', border: OutlineInputBorder())),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
        ElevatedButton(
          onPressed: _save,
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
          child: const Text('Save Supplier'),
        ),
      ],
    );
  }
}

class _CreatePoModal extends ConsumerStatefulWidget {
  final Color accentColor;
  const _CreatePoModal({required this.accentColor});

  @override
  ConsumerState<_CreatePoModal> createState() => _CreatePoModalState();
}

class _CreatePoModalState extends ConsumerState<_CreatePoModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _poNumberController;
  int? _selectedSupplierId;
  final _notesController = TextEditingController();

  int? _selectedProductId;
  final _qtyController = TextEditingController(text: '10');
  final _costController = TextEditingController();
  final List<Map<String, dynamic>> _poItems = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _poNumberController = TextEditingController(
      text: 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
    );
  }

  @override
  void dispose() {
    _poNumberController.dispose();
    _notesController.dispose();
    _qtyController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _addItem(List<Product> products) {
    if (_selectedProductId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a product from the list!'), backgroundColor: Colors.amber),
      );
      return;
    }
    final prod = products.firstWhere((p) => p.id == _selectedProductId);
    final qty = int.tryParse(_qtyController.text) ?? 1;
    final cost = double.tryParse(_costController.text) ?? prod.unitCost;

    setState(() {
      _poItems.add({
        'product': prod,
        'quantity': qty,
        'unit_cost': cost,
      });
      _selectedProductId = null;
      _costController.clear();
      _qtyController.text = '10';
    });
  }

  Future<void> _savePo(List<Supplier> suppliers, List<Product> products) async {
    // 1. Auto-add pending product if filled
    if (_selectedProductId != null) {
      _addItem(products);
    }

    // 2. Validate form
    if (!_formKey.currentState!.validate()) return;

    if (_selectedSupplierId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or add a supplier for this order!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    if (_poItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one line item to the order!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final isar = ref.read(isarProvider);
      final localSql = ref.read(localSqlServiceProvider);
      final supplier = suppliers.firstWhere((s) => s.id == _selectedSupplierId);
      final total = _poItems.fold<double>(0.0, (sum, i) => sum + ((i['unit_cost'] as num) * (i['quantity'] as num)));

      final po = PurchaseOrder()
        ..poNumber = _poNumberController.text.trim()
        ..storeId = 1
        ..supplierId = supplier.id
        ..supplierName = supplier.name
        ..supplierTpin = supplier.tpin
        ..totalAmount = total
        ..notes = _notesController.text.trim()
        ..status = 'pending';

      await isar.writeTxn(() async {
        await isar.purchaseOrders.put(po);

        for (var itemData in _poItems) {
          final Product prod = itemData['product'];
          final item = PurchaseOrderItem()
            ..productId = prod.id
            ..productName = prod.name
            ..unitCost = (itemData['unit_cost'] as num).toDouble()
            ..quantityOrdered = itemData['quantity'] as int
            ..quantityReceived = 0;

          await isar.purchaseOrderItems.put(item);
          po.items.add(item);
        }
        await po.items.save();
      });

      // Also persist to local SQLite database
      try {
        final poId = await localSql.insert('purchase_orders', {
          'po_number': po.poNumber,
          'store_id': 1,
          'supplier_id': supplier.id,
          'supplier_name': supplier.name,
          'supplier_tpin': supplier.tpin,
          'status': 'pending',
          'total_amount': total,
          'notes': po.notes,
          'created_at': DateTime.now().toIso8601String(),
        });

        for (var itemData in _poItems) {
          final Product prod = itemData['product'];
          await localSql.insert('purchase_order_items', {
            'purchase_order_id': poId,
            'product_id': prod.id,
            'product_name': prod.name,
            'unit_cost': itemData['unit_cost'],
            'quantity_ordered': itemData['quantity'],
            'quantity_received': 0,
          });
        }
      } catch (sqlErr) {
        debugPrint('Local SQLite PO insert note: $sqlErr');
      }

      ref.invalidate(purchaseOrdersProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase Order ${po.poNumber} created successfully!'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving PO: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showQuickAddSupplier() {
    showDialog(
      context: context,
      builder: (ctx) => _AddSupplierModal(accentColor: widget.accentColor),
    ).then((_) {
      ref.invalidate(suppliersProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final productsAsync = ref.watch(purchasesProductsProvider);
    final suppliersAsync = ref.watch(suppliersProvider);
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? 'K';

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF151F32) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
        ),
        child: Form(
          key: _formKey,
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
                        child: Icon(Icons.add_shopping_cart_rounded, color: primaryColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CREATE PURCHASE ORDER', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: theme.colorScheme.onSurface)),
                          Text('Issue official restocking order to vendor', style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                  IconButton(icon: Icon(Icons.close_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 14),
              Divider(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
              const SizedBox(height: 10),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // PO Number & Supplier Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _poNumberController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'PO Number',
                                labelStyle: const TextStyle(color: Colors.white70),
                                filled: true,
                                fillColor: Colors.white.withValues(alpha: 0.04),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 3,
                            child: suppliersAsync.when(
                              data: (suppliers) {
                                if (_selectedSupplierId == null && suppliers.isNotEmpty) {
                                  _selectedSupplierId = suppliers.first.id;
                                }

                                return Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<int>(
                                        initialValue: (_selectedSupplierId != null && suppliers.any((s) => s.id == _selectedSupplierId)) ? _selectedSupplierId : null,
                                        dropdownColor: const Color(0xFF222228),
                                        style: const TextStyle(color: Colors.white),
                                        decoration: InputDecoration(
                                          labelText: 'Select Supplier',
                                          labelStyle: const TextStyle(color: Colors.white70),
                                          filled: true,
                                          fillColor: Colors.white.withValues(alpha: 0.04),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        items: suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))).toList(),
                                        onChanged: (id) => setState(() => _selectedSupplierId = id),
                                        validator: (v) => v == null ? 'Select a supplier' : null,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      onPressed: _showQuickAddSupplier,
                                      icon: const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF10B981)),
                                      tooltip: 'Quick Add Supplier',
                                    ),
                                  ],
                                );
                              },
                              loading: () => const Center(child: LinearProgressIndicator()),
                              error: (_, _) => const Text('Error loading suppliers'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Add Line Items Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ADD PRODUCTS TO ORDER', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: widget.accentColor, letterSpacing: 1)),
                            const SizedBox(height: 10),

                            productsAsync.when(
                              data: (prods) {
                                if (prods.isEmpty) {
                                  return Text('No products found in inventory. Please add products first.', style: GoogleFonts.inter(color: Colors.amber, fontSize: 12));
                                }

                                return Column(
                                  children: [
                                    DropdownButtonFormField<int>(
                                      initialValue: (_selectedProductId != null && prods.any((p) => p.id == _selectedProductId)) ? _selectedProductId : null,
                                      dropdownColor: const Color(0xFF222228),
                                      style: const TextStyle(color: Colors.white),
                                      decoration: InputDecoration(
                                        labelText: 'Select Inventory Product',
                                        labelStyle: const TextStyle(color: Colors.white70),
                                        filled: true,
                                        fillColor: Colors.white.withValues(alpha: 0.04),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      items: prods.map((p) => DropdownMenuItem(value: p.id, child: Text('${p.name} (SKU: ${p.sku})'))).toList(),
                                      onChanged: (id) {
                                        setState(() {
                                          _selectedProductId = id;
                                          if (id != null) {
                                            final p = prods.firstWhere((prod) => prod.id == id);
                                            _costController.text = p.unitCost > 0 ? p.unitCost.toString() : p.price.toString();
                                          }
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: _costController,
                                            style: const TextStyle(color: Colors.white),
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            decoration: InputDecoration(
                                              labelText: 'Unit Cost ($currency)',
                                              labelStyle: const TextStyle(color: Colors.white70),
                                              filled: true,
                                              fillColor: Colors.white.withValues(alpha: 0.04),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _qtyController,
                                            style: const TextStyle(color: Colors.white),
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                              labelText: 'Ordered Qty',
                                              labelStyle: const TextStyle(color: Colors.white70),
                                              filled: true,
                                              fillColor: Colors.white.withValues(alpha: 0.04),
                                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        ElevatedButton.icon(
                                          onPressed: () => _addItem(prods),
                                          icon: const Icon(Icons.add_rounded, size: 16),
                                          label: const Text('Add Item'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: widget.accentColor,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                              loading: () => const Center(child: LinearProgressIndicator()),
                              error: (_, _) => const Text('Error loading products'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // PO Items Table
                      if (_poItems.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(20),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Text('No items added yet. Select a product and click "Add Item".', style: GoogleFonts.inter(fontSize: 12, color: Colors.white38)),
                        )
                      else ...[
                        Text('ORDER ITEMS (${_poItems.length})', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
                        const SizedBox(height: 8),
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _poItems.length,
                          itemBuilder: (context, index) {
                            final item = _poItems[index];
                            final Product p = item['product'];
                            final num sub = (item['quantity'] as num) * (item['unit_cost'] as num);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1E24),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(p.name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                        Text('${item['quantity']} units @ $currency${(item['unit_cost'] as num).toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 11, color: Colors.white54)),
                                      ],
                                    ),
                                  ),
                                  Text('$currency${sub.toStringAsFixed(2)}', style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 14, color: widget.accentColor)),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                    onPressed: () => setState(() => _poItems.removeAt(index)),
                                    tooltip: 'Remove Item',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Notes Input
                      TextFormField(
                        controller: _notesController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 2,
                        decoration: InputDecoration(
                          labelText: 'Notes / Delivery Instructions (Optional)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.04),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
              const Divider(color: Colors.white12),
              const SizedBox(height: 10),

              // Actions Row with Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ESTIMATED ORDER TOTAL', style: GoogleFonts.inter(fontSize: 10, color: Colors.white38, fontWeight: FontWeight.bold)),
                      Text(
                        '$currency ${_poItems.fold<double>(0.0, (sum, i) => sum + ((i['unit_cost'] as num) * (i['quantity'] as num))).toStringAsFixed(2)}',
                        style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w900, color: widget.accentColor),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isSaving
                            ? null
                            : () {
                                final suppliers = suppliersAsync.value ?? [];
                                final products = productsAsync.value ?? [];
                                _savePo(suppliers, products);
                              },
                        icon: _isSaving
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(_isSaving ? 'Creating...' : 'Create Purchase Order'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.accentColor,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                          textStyle: GoogleFonts.inter(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiveGrnModal extends ConsumerStatefulWidget {
  final PurchaseOrder po;
  const _ReceiveGrnModal({required this.po});

  @override
  ConsumerState<_ReceiveGrnModal> createState() => _ReceiveGrnModalState();
}

class _ReceiveGrnModalState extends ConsumerState<_ReceiveGrnModal> {
  final _branchCtrl = TextEditingController(text: 'Main Branch');

  Future<void> _processGrn() async {
    final isar = ref.read(isarProvider);
    final localSql = ref.read(localSqlServiceProvider);

    await isar.writeTxn(() async {
      widget.po.status = 'received';
      await isar.purchaseOrders.put(widget.po);

      int totalUnits = 0;
      for (final item in widget.po.items) {
        item.quantityReceived = item.quantityOrdered;
        totalUnits += item.quantityReceived;
        await isar.purchaseOrderItems.put(item);

        // Auto-increment inventory stock in Isar
        if (item.productId != null) {
          final product = await isar.products.get(item.productId!);
          if (product != null) {
            product.stockLevel += item.quantityReceived;
            product.unitCost = item.unitCost;
            await isar.products.put(product);

            // Auto-increment inventory stock in local SQLite SQL DB
            await localSql.update(
              'products',
              {
                'stock_level': product.stockLevel,
                'unit_cost': product.unitCost,
              },
              where: 'id = ?',
              whereArgs: [product.id],
            );
          }
        }
      }

      // Create Goods Received Note record
      final grn = GoodsReceivedNote()
        ..grnNumber = 'GRN-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
        ..poNumber = widget.po.poNumber
        ..supplierName = widget.po.supplierName
        ..warehouseBranch = _branchCtrl.text.trim()
        ..totalItemsReceived = totalUnits;
      await isar.goodsReceivedNotes.put(grn);

      // Create Linked Purchase Invoice (Unpaid)
      final inv = PurchaseInvoice()
        ..invoiceNumber = 'INV-${widget.po.poNumber}'
        ..supplierInvoiceNumber = 'SUP-${widget.po.poNumber}'
        ..poNumber = widget.po.poNumber
        ..supplierName = widget.po.supplierName
        ..totalAmount = widget.po.totalAmount
        ..amountPaid = 0.0
        ..balanceDue = widget.po.totalAmount
        ..paymentStatus = 'unpaid';
      await isar.purchaseInvoices.put(inv);

      // Update Supplier balance
      final supplier = await isar.suppliers.filter().nameEqualTo(widget.po.supplierName).findFirst();
      if (supplier != null) {
        supplier.balance += widget.po.totalAmount;
        supplier.totalPurchases += widget.po.totalAmount;
        await isar.suppliers.put(supplier);
      }
    });

    final isarDb = ref.read(isarProvider);
    final supplier = await isarDb.suppliers.filter().nameEqualTo(widget.po.supplierName).findFirst();

    // Sync purchase stock intake to DigiTax VSDC Cloud
    final syncSuccess = await ref.read(digitaxInventoryServiceProvider).syncPurchaseIntake(
      poNumber: widget.po.poNumber,
      supplierName: widget.po.supplierName,
      supplierTin: supplier?.tpin,
      items: widget.po.items.map((i) => {
        'productId': i.productId,
        'sku': 'SKU-${i.productId}',
        'name': i.productName,
        'qty': i.quantityReceived,
        'cost': i.unitCost,
      }).toList(),
    );

    ref.invalidate(purchaseOrdersProvider);
    ref.invalidate(grnListProvider);
    ref.invalidate(purchaseInvoicesProvider);
    ref.invalidate(suppliersProvider);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(syncSuccess
              ? 'GRN Created, Restocked & Synced to DigiTax for ${widget.po.poNumber}!'
              : 'GRN Created & Inventory Restocked locally for ${widget.po.poNumber}!'),
          backgroundColor: syncSuccess ? Colors.green[800] : Colors.blueGrey[800],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      title: Text('RECEIVE GOODS (GRN): ${widget.po.poNumber}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: theme.colorScheme.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supplier: ${widget.po.supplierName}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          Text('Line Items to Receive: ${widget.po.items.length}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(controller: _branchCtrl, decoration: const InputDecoration(labelText: 'Receiving Branch / Warehouse', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          Text('All ordered quantities will be automatically incremented into product stock.', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
        ElevatedButton(
          onPressed: _processGrn,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
          child: const Text('Confirm & Restock'),
        ),
      ],
    );
  }
}

class _RecordPaymentModal extends ConsumerStatefulWidget {
  final PurchaseInvoice invoice;
  const _RecordPaymentModal({required this.invoice});

  @override
  ConsumerState<_RecordPaymentModal> createState() => _RecordPaymentModalState();
}

class _RecordPaymentModalState extends ConsumerState<_RecordPaymentModal> {
  late TextEditingController _payAmountCtrl;
  String _payMethod = 'BANK_TRANSFER';

  @override
  void initState() {
    super.initState();
    _payAmountCtrl = TextEditingController(text: widget.invoice.balanceDue.toString());
  }

  @override
  void dispose() {
    _payAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final paidVal = double.tryParse(_payAmountCtrl.text) ?? 0.0;
    if (paidVal <= 0) return;

    final isar = ref.read(isarProvider);
    await isar.writeTxn(() async {
      widget.invoice.amountPaid += paidVal;
      widget.invoice.balanceDue = (widget.invoice.totalAmount - widget.invoice.amountPaid).clamp(0.0, double.infinity);
      widget.invoice.paymentStatus = widget.invoice.balanceDue == 0 ? 'paid' : 'partial';
      await isar.purchaseInvoices.put(widget.invoice);

      final supplier = await isar.suppliers.filter().nameEqualTo(widget.invoice.supplierName).findFirst();
      if (supplier != null) {
        supplier.balance = (supplier.balance - paidVal).clamp(0.0, double.infinity);
        await isar.suppliers.put(supplier);
      }
    });

    ref.invalidate(purchaseInvoicesProvider);
    ref.invalidate(suppliersProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      title: Text('RECORD SUPPLIER PAYMENT', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: theme.colorScheme.onSurface)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Invoice: ${widget.invoice.invoiceNumber} • ${widget.invoice.supplierName}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          TextField(controller: _payAmountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Payment Amount (K)', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _payMethod,
            decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'BANK_TRANSFER', child: Text('Bank Wire / EFT')),
              DropdownMenuItem(value: 'CASH', child: Text('Cash')),
              DropdownMenuItem(value: 'CHEQUE', child: Text('Cheque')),
              DropdownMenuItem(value: 'MOBILE_MONEY', child: Text('Airtel / MTN Mobile Money')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _payMethod = v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
        ElevatedButton(
          onPressed: _pay,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
          child: const Text('Record Payment'),
        ),
      ],
    );
  }
}

class _CreateReturnModal extends ConsumerStatefulWidget {
  final Color accentColor;
  const _CreateReturnModal({required this.accentColor});

  @override
  ConsumerState<_CreateReturnModal> createState() => _CreateReturnModalState();
}

class _CreateReturnModalState extends ConsumerState<_CreateReturnModal> {
  int? _selectedSupplierId;
  int? _selectedProductId;
  final _qtyCtrl = TextEditingController(text: '1');
  String _reason = 'Damaged Goods';

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitReturn(List<Supplier> suppliers, List<Product> products) async {
    if (_selectedSupplierId == null || _selectedProductId == null) return;
    final supplier = suppliers.firstWhere((s) => s.id == _selectedSupplierId);
    final product = products.firstWhere((p) => p.id == _selectedProductId);
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final total = qty * product.unitCost;

    final isar = ref.read(isarProvider);
    final localSql = ref.read(localSqlServiceProvider);

    await isar.writeTxn(() async {
      // Auto-decrement inventory stock for returned goods
      product.stockLevel = (product.stockLevel - qty).clamp(0, 9999999);
      await isar.products.put(product);

      await localSql.update(
        'products',
        {'stock_level': product.stockLevel},
        where: 'id = ?',
        whereArgs: [product.id],
      );

      final ret = PurchaseReturn()
        ..returnNumber = 'RET-${DateTime.now().millisecondsSinceEpoch.toString().substring(6)}'
        ..supplierName = supplier.name
        ..totalAmount = total
        ..reason = _reason;
      await isar.purchaseReturns.put(ret);

      // Deduct supplier balance
      supplier.balance = (supplier.balance - total).clamp(0.0, double.infinity);
      await isar.suppliers.put(supplier);
    });

    ref.invalidate(purchaseReturnsProvider);
    ref.invalidate(suppliersProvider);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    final productsAsync = ref.watch(databaseServiceProvider).getAllProducts();

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      title: Text('CREATE PURCHASE RETURN', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16, color: theme.colorScheme.onSurface)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              initialValue: (_selectedSupplierId != null && suppliers.any((s) => s.id == _selectedSupplierId)) ? _selectedSupplierId : null,
              decoration: const InputDecoration(labelText: 'Select Supplier', border: OutlineInputBorder()),
              items: suppliers.map((s) => DropdownMenuItem(value: s.id, child: Text(s.name))).toList(),
              onChanged: (id) => setState(() => _selectedSupplierId = id),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Product>>(
              future: productsAsync,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final prods = snapshot.data!;
                return DropdownButtonFormField<int>(
                  initialValue: (_selectedProductId != null && prods.any((p) => p.id == _selectedProductId)) ? _selectedProductId : null,
                  decoration: const InputDecoration(labelText: 'Select Product to Return', border: OutlineInputBorder()),
                  items: prods.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (id) => setState(() => _selectedProductId = id),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: _qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Return Quantity', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              decoration: const InputDecoration(labelText: 'Return Reason', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'Damaged Goods', child: Text('Damaged Goods')),
                DropdownMenuItem(value: 'Expired Stock', child: Text('Expired Stock')),
                DropdownMenuItem(value: 'Wrong Item Received', child: Text('Wrong Item Received')),
                DropdownMenuItem(value: 'Excess Delivery', child: Text('Excess Delivery')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _reason = v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
        FutureBuilder<List<Product>>(
          future: productsAsync,
          builder: (context, snapshot) {
            final prods = snapshot.data ?? [];
            return ElevatedButton(
              onPressed: () => _submitReturn(suppliers, prods),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7), foregroundColor: Colors.white),
              child: const Text('Submit Return'),
            );
          },
        ),
      ],
    );
  }
}

class _ConsignmentSettlementModal extends ConsumerStatefulWidget {
  final Supplier supplier;
  final String currency;

  const _ConsignmentSettlementModal({
    required this.supplier,
    required this.currency,
  });

  @override
  ConsumerState<_ConsignmentSettlementModal> createState() => _ConsignmentSettlementModalState();
}

class _ConsignmentSettlementModalState extends ConsumerState<_ConsignmentSettlementModal> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountCtrl;
  final _refCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _paymentMethod = 'Cash';
  bool _deductFromTill = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.supplier.balance.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _refCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _processSettlement() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (amount <= 0) return;

    setState(() => _isSaving = true);

    try {
      final db = ref.read(databaseServiceProvider);
      final expense = await db.recordConsignmentSettlement(
        supplier: widget.supplier,
        amountPaid: amount,
        paymentMethod: _paymentMethod,
        referenceNumber: _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      ref.invalidate(suppliersProvider);
      ref.invalidate(purchaseInvoicesProvider);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settlement of ${widget.currency} ${amount.toStringAsFixed(2)} paid to ${widget.supplier.name} recorded! Voucher: ${expense.expenseNumber}'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error recording settlement: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF151F32) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isDark ? const Color(0xFF293548) : const Color(0xFFE2E8F0)),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.payments_rounded, color: Color(0xFF10B981), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SETTLE CONSIGNMENT PAYOUT',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: theme.colorScheme.onSurface),
                ),
                Text(
                  'Vendor: ${widget.supplier.name}',
                  style: GoogleFonts.inter(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Outstanding Balance Banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('CURRENT UNPAID BALANCE', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444))),
                          const SizedBox(height: 2),
                          Text('Pass-through sales liability', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      Text(
                        '${widget.currency} ${widget.supplier.balance.toStringAsFixed(2)}',
                        style: GoogleFonts.manrope(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFFEF4444)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Amount to Pay
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Settlement Amount to Pay',
                    prefixText: '${widget.currency} ',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter payout amount';
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed <= 0) return 'Enter a valid amount > 0';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Payment Method
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method / Channel',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer (EFT)')),
                    DropdownMenuItem(value: 'Airtel Money', child: Text('Airtel Money')),
                    DropdownMenuItem(value: 'MTN Money', child: Text('MTN Money')),
                    DropdownMenuItem(value: 'Zamtel Kwacha', child: Text('Zamtel Kwacha')),
                    DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _paymentMethod = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Deduct from till switch (only for cash)
                if (_paymentMethod == 'Cash') ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Deduct from Active Cash Drawer Till', style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: theme.colorScheme.onSurface)),
                    subtitle: Text('Records payout in current register shift session', style: GoogleFonts.inter(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                    value: _deductFromTill,
                    activeThumbColor: const Color(0xFF10B981),
                    onChanged: (v) => setState(() => _deductFromTill = v),
                  ),
                  const SizedBox(height: 8),
                ],

                // Payment Reference
                TextFormField(
                  controller: _refCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Payment Reference # / Transaction ID (Optional)',
                    hintText: 'e.g. EFT-9921, Mobile Money Ref',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // Settlement Notes
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Voucher Notes / Memo (Optional)',
                    hintText: 'e.g. Full settlement for sales through 15 Sep',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving ? null : _processSettlement,
          icon: _isSaving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_rounded, size: 18),
          label: Text(_isSaving ? 'Processing...' : 'Confirm & Record Payout'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    );
  }
}
