import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/models/models.dart';
import 'package:beleka_pos/services/database_service.dart';
import 'package:beleka_pos/providers/cart_provider.dart';

class CustomerSelectionModal extends ConsumerStatefulWidget {
  const CustomerSelectionModal({super.key});

  @override
  ConsumerState<CustomerSelectionModal> createState() => _CustomerSelectionModalState();
}

class _CustomerSelectionModalState extends ConsumerState<CustomerSelectionModal> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addQuickCustomer() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A20),
        title: Text('Quick Add Customer', style: GoogleFonts.inter(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Name', labelStyle: TextStyle(color: Colors.white54)),
            ),
            TextField(
              controller: phoneController,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone Number', labelStyle: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC1F118)),
            child: const Text('Add', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (result == true && nameController.text.isNotEmpty && phoneController.text.isNotEmpty) {
      final customer = Customer(
        name: nameController.text,
        phoneNumber: phoneController.text,
      );
      await ref.read(databaseServiceProvider).saveCustomer(customer);
      setState(() {}); // Refresh list
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersStream = ref.watch(databaseServiceProvider).watchAllCustomers();

    return Dialog(
      backgroundColor: const Color(0xFF141418),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SELECT CUSTOMER',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search by name or phone...',
                hintStyle: const TextStyle(color: Colors.white24),
                prefixIcon: const Icon(Icons.search, color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<List<Customer>>(
                stream: customersStream,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final filtered = snapshot.data!.where((c) =>
                      c.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      c.phoneNumber.contains(_searchQuery)).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text('No customers found',
                          style: GoogleFonts.inter(color: Colors.white24)),
                    );
                  }

                  return ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(color: Colors.white10),
                    itemBuilder: (context, index) {
                      final customer = filtered[index];
                      return ListTile(
                        onTap: () {
                          ref.read(cartProvider.notifier).setCustomer(customer);
                          Navigator.pop(context);
                        },
                        title: Text(customer.name,
                            style: GoogleFonts.inter(
                                color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text(customer.phoneNumber,
                            style: GoogleFonts.inter(color: Colors.white38, fontSize: 12)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${customer.accumulatedPoints} pts',
                                style: GoogleFonts.inter(
                                    color: const Color(0xFFC1F118),
                                    fontWeight: FontWeight.bold)),
                            Text('Balance',
                                style: GoogleFonts.inter(color: Colors.white24, fontSize: 10)),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _addQuickCustomer,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('ADD NEW CUSTOMER'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC1F118),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
