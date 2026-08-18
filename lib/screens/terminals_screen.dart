import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:beleka_pos/services/api_service.dart';
import 'package:beleka_pos/providers/store_provider.dart';
import 'package:beleka_pos/utils/formatters.dart';

final terminalsStreamProvider = StreamProvider<List<TerminalInfo>>((ref) async* {
  final api = ref.watch(apiServiceProvider);
  yield api.activeTerminals.values.toList();
  yield* api.terminalsStream;
});

class TerminalsScreen extends ConsumerWidget {
  const TerminalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terminalsAsync = ref.watch(terminalsStreamProvider);
    final currency = ref.watch(storeConfigProvider).value?.currencySymbol ?? '\$';

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Terminals Monitor', style: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 8),
          Text('Live overview of connected cashier terminals and active revenue.', style: GoogleFonts.inter(fontSize: 14, color: Colors.white.withValues(alpha: 0.5))),
          const SizedBox(height: 32),
          
          Expanded(
            child: terminalsAsync.when(
              data: (terminals) {
                if (terminals.isEmpty) {
                  return const Center(child: Text('No active terminals connected.', style: TextStyle(color: Colors.white54)));
                }

                final activeTerminals = terminals.where((t) => DateTime.now().difference(t.lastHeartbeat).inMinutes < 5).toList();
                final totalActiveSales = activeTerminals.fold(0.0, (sum, t) => sum + t.salesToday);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Overview Stats Card
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [const Color(0xFFC1F11D).withValues(alpha: 0.15), const Color(0xFFC1F11D).withValues(alpha: 0.05)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFC1F11D).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: const BoxDecoration(color: Color(0xFFC1F11D), shape: BoxShape.circle),
                            child: const Icon(Icons.bolt_rounded, color: Colors.black, size: 32),
                          ),
                          const SizedBox(width: 24),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('TOTAL ACTIVE REVENUE',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D), letterSpacing: 1.5)),
                              Text(CurrencyFormatter.format(totalActiveSales, currency),
                                  style: GoogleFonts.plusJakartaSans(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
                            ],
                          ),
                          const Spacer(),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('LIVE TERMINALS',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white.withValues(alpha: 0.5), letterSpacing: 1.5)),
                              Text('${activeTerminals.length}',
                                  style: GoogleFonts.plusJakartaSans(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // Terminals Grid
                    Expanded(
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.5,
                        ),
                        itemCount: terminals.length,
                        itemBuilder: (context, index) {
                          final t = terminals[index];
                          final isOnline = DateTime.now().difference(t.lastHeartbeat).inMinutes < 2;
                          
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A1E),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: isOnline ? const Color(0xFFC1F11D).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t.terminalName.toUpperCase(),
                                        style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isOnline ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isOnline ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2)),
                                      ),
                                      child: Text(
                                        isOnline ? 'ONLINE' : 'OFFLINE',
                                        style: GoogleFonts.jetBrainsMono(fontSize: 10, fontWeight: FontWeight.bold, color: isOnline ? Colors.green : Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                                      child: const Icon(Icons.person, size: 16, color: Colors.white54),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            t.cashierName,
                                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            'ID: ${t.cashierId}',
                                            style: GoogleFonts.jetBrainsMono(fontSize: 10, color: Colors.white54),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.02),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('SALES TODAY', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white54)),
                                      Text(
                                        CurrencyFormatter.format(t.salesToday, currency),
                                        style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFFC1F11D)),
                                      ),
                                    ],
                                  ),
                                )
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: Color(0xFFC1F11D))),
              error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: Colors.red))),
            ),
          ),
        ],
      ),
    );
  }
}
