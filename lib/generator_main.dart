// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

// Master Keys
const String kBelekaMasterPublicKeyBase64 = 'eFFG+hL3UcctF/FWifPtxhgBcTtFTo49pH2Svds09x8=';
const String kBelekaMasterPrivateKeyBase64 = 'ogb6D2/rGh4ybjl/EJuuF3P3mpvdKZKroYvIs9qTCEo=';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BelekaLicenseGeneratorApp());
}

class BelekaLicenseGeneratorApp extends StatelessWidget {
  const BelekaLicenseGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beleka POS - License Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFC1F11D),
          onPrimary: Color(0xFF0F172A),
          surface: Color(0xFF1E293B),
          onSurface: Color(0xFFF8FAFC),
          secondary: Color(0xFF38BDF8),
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0F172A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF334155)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFC1F11D), width: 2),
          ),
          labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
          hintStyle: const TextStyle(color: Color(0xFF64748B)),
        ),
      ),
      home: const GeneratorHomeScreen(),
    );
  }
}

class GeneratorHomeScreen extends StatefulWidget {
  const GeneratorHomeScreen({super.key});

  @override
  State<GeneratorHomeScreen> createState() => _GeneratorHomeScreenState();
}

class _GeneratorHomeScreenState extends State<GeneratorHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF334155).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.vpn_key_rounded, color: Color(0xFFC1F11D), size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BELEKA POS LICENSE MANAGER',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.5,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Official Cryptographic License Issuer & Verifier',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFC1F11D),
          indicatorWeight: 3,
          labelColor: const Color(0xFFC1F11D),
          unselectedLabelColor: const Color(0xFF94A3B8),
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(icon: Icon(Icons.add_moderator_rounded), text: 'Issue License'),
            Tab(icon: Icon(Icons.verified_rounded), text: 'Verify Token'),
            Tab(icon: Icon(Icons.security_rounded), text: 'Master Deployer'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          IssueLicenseTab(),
          VerifyLicenseTab(),
          MasterKeyTab(),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TAB 1: ISSUE LICENSE
// -----------------------------------------------------------------------------

class IssueLicenseTab extends StatefulWidget {
  const IssueLicenseTab({super.key});

  @override
  State<IssueLicenseTab> createState() => _IssueLicenseTabState();
}

class _IssueLicenseTabState extends State<IssueLicenseTab> {
  final _customerCtrl = TextEditingController(text: 'Valued Client');
  final _hwidCtrl = TextEditingController();
  final _customDaysCtrl = TextEditingController(text: '30');

  String _durationOption = '1 Month'; // '1 Month', '3 Months', '6 Months', '12 Months', 'Custom Days'
  int _maxTills = 3;
  int _branches = 1;
  bool _isGenerating = false;

  String? _generatedToken;
  Map<String, dynamic>? _generatedPayload;
  bool _copied = false;

  @override
  void dispose() {
    _customerCtrl.dispose();
    _hwidCtrl.dispose();
    _customDaysCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteHwid() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() {
        _hwidCtrl.text = data!.text!.trim().toUpperCase();
      });
    }
  }

  Future<void> _generateLicense() async {
    final customer = _customerCtrl.text.trim();
    final hwid = _hwidCtrl.text.trim().toUpperCase();

    if (hwid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter or paste the target Hardware ID (HWID)!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _generatedToken = null;
      _generatedPayload = null;
      _copied = false;
    });

    try {
      final now = DateTime.now().toUtc();
      DateTime? expiresAt;
      String term = 'Custom Period';
      int? months;

      if (_durationOption == '1 Month') {
        months = 1;
        expiresAt = _addMonths(now, 1);
        term = '1 Month License';
      } else if (_durationOption == '3 Months') {
        months = 3;
        expiresAt = _addMonths(now, 3);
        term = '3 Months License';
      } else if (_durationOption == '6 Months') {
        months = 6;
        expiresAt = _addMonths(now, 6);
        term = '6 Months License';
      } else if (_durationOption == '12 Months') {
        months = 12;
        expiresAt = _addMonths(now, 12);
        term = '12 Months (1 Year) License';
      } else {
        // Custom Days
        final days = int.tryParse(_customDaysCtrl.text.trim()) ?? 30;
        expiresAt = now.add(Duration(days: days));
        term = '$days Days License';
      }

      final randomId = 'BP-${now.millisecondsSinceEpoch.toString().substring(7)}';

      final payloadMap = {
        'product': 'Beleka Pro POS',
        'customer': customer.isEmpty ? 'Valued Client' : customer,
        'installationId': randomId,
        'hardwareId': hwid,
        'branches': _branches,
        'term': term,
        'months': months,
        'maxTills': _maxTills,
        'issuedAt': now.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'features': [
          'offline_pos',
          'inventory_management',
          'category_allocation',
          'thermal_receipt_printing',
          'escpos_drivers',
          'backup_and_restore',
          'unlimited_transactions',
          'multi_till_lan'
        ],
      };

      // Ed25519 Cryptographic Signing
      final algorithm = Ed25519();
      final canonicalJson = jsonEncode(payloadMap);
      final dataBytes = utf8.encode(canonicalJson);

      final privBytes = base64Decode(kBelekaMasterPrivateKeyBase64);
      final keyPair = await algorithm.newKeyPairFromSeed(privBytes);
      final signature = await algorithm.sign(dataBytes, keyPair: keyPair);
      final signatureBase64 = base64Encode(signature.bytes);

      final fullLicenseMap = {
        ...payloadMap,
        'signature': signatureBase64,
      };

      final tokenBase64 = 'BELEKA-LIC-${base64Encode(utf8.encode(jsonEncode(fullLicenseMap)))}';

      setState(() {
        _generatedToken = tokenBase64;
        _generatedPayload = fullLicenseMap;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generation failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  DateTime _addMonths(DateTime date, int months) {
    int newYear = date.year;
    int newMonth = date.month + months;
    while (newMonth > 12) {
      newYear += 1;
      newMonth -= 12;
    }
    return DateTime.utc(newYear, newMonth, date.day, date.hour, date.minute, date.second);
  }

  Future<void> _exportLicFile() async {
    if (_generatedPayload == null) return;

    try {
      final jsonStr = const JsonEncoder.withIndent('  ').convert(_generatedPayload);
      final bytes = utf8.encode(jsonStr);

      String fileName = '${(_generatedPayload!['customer'] as String).replaceAll(' ', '_')}_license.lic';

      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes);
        
        // Also try writing to standard downloads if available
        final downloadsDir = Directory('/storage/emulated/0/Download');
        if (await downloadsDir.exists()) {
          final dlFile = File('${downloadsDir.path}/$fileName');
          await dlFile.writeAsBytes(bytes);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('License saved to Downloads: $fileName'),
              backgroundColor: const Color(0xFF059669),
            ),
          );
        }
      } else {
        // Desktop / Windows
        if (!mounted) return;
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Beleka License File',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['lic'],
        );

        if (result != null) {
          final file = File(result.endsWith('.lic') ? result : '$result.lic');
          await file.writeAsBytes(bytes);

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Saved to: ${file.path}'),
                backgroundColor: const Color(0xFF059669),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 700;

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Client & Hardware Input Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person_pin_rounded, color: Color(0xFFC1F11D), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'CUSTOMER & HARDWARE SPECIFICATIONS',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: const Color(0xFFF8FAFC),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _customerCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Customer / Store Name',
                          hintText: 'e.g. Modern Retail Supermarket',
                          prefixIcon: Icon(Icons.storefront_rounded, color: Color(0xFF94A3B8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _hwidCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Target Hardware ID (HWID)',
                                hintText: 'e.g. BP-B259-9E44-682F-A143',
                                prefixIcon: Icon(Icons.memory_rounded, color: Color(0xFF94A3B8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _pasteHwid,
                            icon: const Icon(Icons.content_paste_rounded, size: 18),
                            label: const Text('PASTE HWID'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF334155),
                              foregroundColor: const Color(0xFFC1F11D),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Duration & Subscription Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.timer_outlined, color: Color(0xFFC1F11D), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'LICENSE DURATION & TERM',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: const Color(0xFFF8FAFC),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildDurationChip('1 Month'),
                          _buildDurationChip('3 Months'),
                          _buildDurationChip('6 Months'),
                          _buildDurationChip('12 Months'),
                          _buildDurationChip('Custom Days'),
                        ],
                      ),
                      if (_durationOption == 'Custom Days') ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _customDaysCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Number of Days',
                            hintText: 'e.g. 14, 45, 90',
                            prefixIcon: Icon(Icons.calendar_today_rounded, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Divider(color: Color(0xFF334155)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Max Tills Allowed', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<int>(
                                  initialValue: _maxTills,
                                  dropdownColor: const Color(0xFF1E293B),
                                  items: [1, 2, 3, 5, 10, 20, 50].map((e) {
                                    return DropdownMenuItem(value: e, child: Text('$e Till${e > 1 ? 's' : ''}'));
                                  }).toList(),
                                  onChanged: (v) => setState(() => _maxTills = v ?? 3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Authorized Branches', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                                const SizedBox(height: 6),
                                DropdownButtonFormField<int>(
                                  initialValue: _branches,
                                  dropdownColor: const Color(0xFF1E293B),
                                  items: [1, 2, 3, 5, 10].map((e) {
                                    return DropdownMenuItem(value: e, child: Text('$e Branch${e > 1 ? 'es' : ''}'));
                                  }).toList(),
                                  onChanged: (v) => setState(() => _branches = v ?? 1),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Generate Action Button
              ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateLicense,
                icon: _isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0F172A)))
                    : const Icon(Icons.electric_bolt_rounded, size: 22),
                label: Text(
                  _isGenerating ? 'SIGNING LICENSE...' : 'GENERATE & SIGN ACTIVATION LICENSE',
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC1F11D),
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 4,
                ),
              ),

              if (_generatedToken != null) ...[
                const SizedBox(height: 24),
                // Generated Result Card
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Color(0xFFC1F11D), width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFFC1F11D), size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'ACTIVATION TOKEN READY',
                                    style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFFC1F11D)),
                                  ),
                                  Text(
                                    _generatedPayload?['term'] ?? '',
                                    style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
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
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: SelectableText(
                            _generatedToken!,
                            style: GoogleFonts.firaCode(fontSize: 11, color: const Color(0xFFE2E8F0)),
                            maxLines: 4,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _generatedToken!));
                                  setState(() => _copied = true);
                                  Future.delayed(const Duration(seconds: 3), () {
                                    if (mounted) setState(() => _copied = false);
                                  });
                                },
                                icon: Icon(_copied ? Icons.done_all_rounded : Icons.copy_rounded, size: 18),
                                label: Text(_copied ? 'COPIED TO CLIPBOARD!' : 'COPY ACTIVATION CODE'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _copied ? const Color(0xFF059669) : const Color(0xFFC1F11D),
                                  foregroundColor: const Color(0xFF0F172A),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: _exportLicFile,
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: const Text('EXPORT .LIC FILE'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF334155),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDurationChip(String label) {
    final isSelected = _durationOption == label;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5)),
      selected: isSelected,
      selectedColor: const Color(0xFFC1F11D),
      backgroundColor: const Color(0xFF0F172A),
      labelStyle: TextStyle(
        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF94A3B8),
      ),
      side: BorderSide(
        color: isSelected ? const Color(0xFFC1F11D) : const Color(0xFF334155),
      ),
      onSelected: (selected) {
        if (selected) setState(() => _durationOption = label);
      },
    );
  }
}

// -----------------------------------------------------------------------------
// TAB 2: VERIFY LICENSE
// -----------------------------------------------------------------------------

class VerifyLicenseTab extends StatefulWidget {
  const VerifyLicenseTab({super.key});

  @override
  State<VerifyLicenseTab> createState() => _VerifyLicenseTabState();
}

class _VerifyLicenseTabState extends State<VerifyLicenseTab> {
  final _tokenCtrl = TextEditingController();
  Map<String, dynamic>? _decodedLicense;
  bool _isValid = false;
  String? _verificationStatus;
  bool _isChecking = false;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyToken() async {
    final rawInput = _tokenCtrl.text.trim();
    if (rawInput.isEmpty) return;

    setState(() {
      _isChecking = true;
      _decodedLicense = null;
      _verificationStatus = null;
    });

    try {
      String jsonStr = rawInput;
      if (rawInput.startsWith('BELEKA-LIC-')) {
        final b64 = rawInput.substring('BELEKA-LIC-'.length);
        jsonStr = utf8.decode(base64Decode(b64));
      }

      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final signature = map['signature'] as String?;

      if (signature == null || signature.isEmpty) {
        setState(() {
          _isValid = false;
          _verificationStatus = 'Invalid format: Signature missing.';
        });
        return;
      }

      // Reconstruct payload
      final payloadMap = Map<String, dynamic>.from(map)..remove('signature');
      final canonicalJson = jsonEncode(payloadMap);
      final dataBytes = utf8.encode(canonicalJson);

      // Verify Ed25519 signature
      final algorithm = Ed25519();
      final pubBytes = base64Decode(kBelekaMasterPublicKeyBase64);
      final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
      final sigBytes = base64Decode(signature);

      final isSigValid = await algorithm.verify(
        dataBytes,
        signature: Signature(sigBytes, publicKey: publicKey),
      );

      if (!isSigValid) {
        setState(() {
          _isValid = false;
          _verificationStatus = 'CRYPTOGRAPHIC SIGNATURE INVALID (TAMPERED)';
        });
        return;
      }

      // Check Expiration
      bool isExpired = false;
      if (payloadMap['expiresAt'] != null) {
        final exp = DateTime.tryParse(payloadMap['expiresAt'] as String);
        if (exp != null && DateTime.now().toUtc().isAfter(exp)) {
          isExpired = true;
        }
      }

      setState(() {
        _isValid = !isExpired;
        _decodedLicense = map;
        _verificationStatus = isExpired ? 'VALID SIGNATURE BUT EXPIRED' : 'GENUINE & AUTHENTIC BELEKA LICENSE';
      });
    } catch (e) {
      setState(() {
        _isValid = false;
        _verificationStatus = 'Decoding error: $e';
      });
    } finally {
      setState(() => _isChecking = false);
    }
  }

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['lic', 'json', 'txt'],
    );
    if (result?.files.single.path != null) {
      final file = File(result!.files.single.path!);
      final content = await file.readAsString();
      _tokenCtrl.text = content;
      await _verifyToken();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.verified_user_outlined, color: Color(0xFFC1F11D), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'PASTE TOKEN OR IMPORT LICENSE FILE',
                            style: GoogleFonts.manrope(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: const Color(0xFFF8FAFC),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _tokenCtrl,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Paste BELEKA-LIC-... or JSON license content here',
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _isChecking ? null : _verifyToken,
                            icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                            label: const Text('VERIFY SIGNATURE'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFC1F11D),
                              foregroundColor: const Color(0xFF0F172A),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: _importFile,
                            icon: const Icon(Icons.folder_open_rounded, size: 18),
                            label: const Text('IMPORT .LIC FILE'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF334155)),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              if (_verificationStatus != null) ...[
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: _isValid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _isValid ? Icons.verified_rounded : Icons.warning_amber_rounded,
                              color: _isValid ? const Color(0xFF059669) : const Color(0xFFDC2626),
                              size: 26,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _verificationStatus!,
                                style: GoogleFonts.manrope(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                  color: _isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_decodedLicense != null) ...[
                          const SizedBox(height: 16),
                          const Divider(color: Color(0xFF334155)),
                          const SizedBox(height: 12),
                          _buildDetailRow('Customer Name', _decodedLicense!['customer'] ?? 'Unknown'),
                          _buildDetailRow('Target HWID', _decodedLicense!['hardwareId'] ?? 'N/A'),
                          _buildDetailRow('Product', _decodedLicense!['product'] ?? 'Beleka POS'),
                          _buildDetailRow('License Term', _decodedLicense!['term'] ?? 'Timed License'),
                          _buildDetailRow('Max Tills', '${_decodedLicense!['maxTills'] ?? 3} Tills'),
                          _buildDetailRow('Expires At', _decodedLicense!['expiresAt'] ?? 'Not Set (Invalid)'),
                          _buildDetailRow('Issued At', _decodedLicense!['issuedAt'] ?? 'N/A'),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String title, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8))),
          SelectableText(val, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// TAB 3: MASTER DEPLOYER KEY
// -----------------------------------------------------------------------------

class MasterKeyTab extends StatefulWidget {
  const MasterKeyTab({super.key});

  @override
  State<MasterKeyTab> createState() => _MasterKeyTabState();
}

class _MasterKeyTabState extends State<MasterKeyTab> {
  String? _masterToken;
  bool _copied = false;

  Future<void> _generateMasterKey() async {
    final now = DateTime.now().toUtc();
    final payloadMap = {
      'product': 'Beleka Pro POS Master',
      'customer': 'Beleka Master Deployer',
      'installationId': 'BP-MASTER-UNIVERSAL',
      'hardwareId': 'BP-UNIVERSAL-MASTER-KEY',
      'branches': 999,
      'term': 'Universal Master Deployment',
      'issuedAt': now.toIso8601String(),
      'expiresAt': null,
      'features': [
        'offline_pos',
        'inventory_management',
        'category_allocation',
        'thermal_receipt_printing',
        'escpos_drivers',
        'backup_and_restore',
        'unlimited_transactions',
        'universal_deployer_mode',
      ],
    };

    final algorithm = Ed25519();
    final canonicalJson = jsonEncode(payloadMap);
    final dataBytes = utf8.encode(canonicalJson);

    final privBytes = base64Decode(kBelekaMasterPrivateKeyBase64);
    final keyPair = await algorithm.newKeyPairFromSeed(privBytes);
    final signature = await algorithm.sign(dataBytes, keyPair: keyPair);
    final signatureBase64 = base64Encode(signature.bytes);

    final fullLicenseMap = {
      ...payloadMap,
      'signature': signatureBase64,
    };

    final tokenBase64 = 'BELEKA-LIC-${base64Encode(utf8.encode(jsonEncode(fullLicenseMap)))}';

    setState(() {
      _masterToken = tokenBase64;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFFC1F11D), size: 24),
                          const SizedBox(width: 10),
                          Text(
                            'UNIVERSAL MASTER DEPLOYMENT KEY',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: const Color(0xFFF8FAFC),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Generates an on-site universal activation token that activates any physical POS hardware without needing the specific HWID upfront. Use for authorized technicians only.',
                        style: GoogleFonts.inter(fontSize: 12.5, color: const Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _generateMasterKey,
                        icon: const Icon(Icons.vpn_key_rounded, size: 18),
                        label: const Text('GENERATE MASTER KEY'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFC1F11D),
                          foregroundColor: const Color(0xFF0F172A),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_masterToken != null) ...[
                const SizedBox(height: 16),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Color(0xFFC1F11D), width: 1.5),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'MASTER ACTIVATION TOKEN',
                          style: GoogleFonts.manrope(fontWeight: FontWeight.w900, fontSize: 13, color: const Color(0xFFC1F11D)),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: SelectableText(
                            _masterToken!,
                            style: GoogleFonts.firaCode(fontSize: 11, color: const Color(0xFFE2E8F0)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _masterToken!));
                            setState(() => _copied = true);
                            Future.delayed(const Duration(seconds: 3), () {
                              if (mounted) setState(() => _copied = false);
                            });
                          },
                          icon: Icon(_copied ? Icons.done_all_rounded : Icons.copy_rounded, size: 18),
                          label: Text(_copied ? 'COPIED!' : 'COPY MASTER TOKEN'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _copied ? const Color(0xFF059669) : const Color(0xFFC1F11D),
                            foregroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
