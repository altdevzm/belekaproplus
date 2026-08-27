// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as crypto;

// Master Beleka POS Ed25519 Public Key (Embedded in Client App)
// 32-byte Ed25519 Public Key (Base64)
const String kBelekaMasterPublicKeyBase64 = 'eFFG+hL3UcctF/FWifPtxhgBcTtFTo49pH2Svds09x8=';

// Master Beleka POS Ed25519 Private Key (Used ONLY by Vendor / Licensing Server)
// 32-byte Ed25519 Private Key (Base64)
const String kBelekaMasterPrivateKeyBase64 = 'ogb6D2/rGh4ybjl/EJuuF3P3mpvdKZKroYvIs9qTCEo=';

void main(List<String> args) async {
  final algorithm = Ed25519();

  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final command = args[0];

  switch (command) {
    case 'hwid':
    case 'get-hwid':
      await _showCurrentMachineHwid();
      break;

    case 'gen-keys':
      await _generateNewKeys(algorithm);
      break;

    case 'issue':
      await _issueLicense(algorithm, args.sublist(1));
      break;

    case 'issue-master':
    case 'master':
      await _issueMasterLicense(algorithm, args.sublist(1));
      break;

    case 'verify':
      await _verifyLicenseFile(algorithm, args.sublist(1));
      break;

    default:
      print('Unknown command: $command');
      _printUsage();
  }
}

void _printUsage() {
  print('''
==================================================================
           BELEKA POS - CRYPTOGRAPHIC LICENSE GENERATOR           
==================================================================
Usage:
  dart run tool/generate_license.dart <command> [options]

Commands:
  hwid          Show Hardware ID and diagnostics for this machine
  master        Generate a Universal Master Deployer .lic file for on-site activations
                Options:
                  --name <name>         (Default: "Beleka Master Installer")
                  --out <path>          (Default: "beleka_universal_master.lic")

  issue         Generate and cryptographically sign a license for a customer
                Options:
                  --customer <name>     (e.g. "ABC Supermarket")
                  --hwid <hwid>         (e.g. "BP-8F29-C4B2-9A1D-E703")
                  --months <1-12>       (Duration in months: 1 to 12 months)
                  --max-tills <count>   (Default: 3 tills)
                  --term <term>         (Default: "Permanent", or "X Months")
                  --branches <count>    (Default: 1)
                  --days <count>        (e.g. 30, 60, 90, 365 for custom days)
                  --out <path>          (Default: "beleka_license.lic")

  verify        Verify a .lic file against the master public key
                Options:
                  --file <path>         (Path to .lic file)
                  --hwid <hwid>         (Optional: test with target HWID)

  gen-keys      Generate a fresh Ed25519 Master KeyPair
==================================================================
''');
}

Future<void> _generateNewKeys(Ed25519 algorithm) async {
  final keyPair = await algorithm.newKeyPair();
  final publicKey = await keyPair.extractPublicKey();
  final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

  final pubBase64 = base64Encode(publicKey.bytes);
  final privBase64 = base64Encode(privateKeyBytes);

  print('\n=== NEW MASTER ED25519 KEYPAIR GENERATED ===');
  print('Public Key (Embed in App):  $pubBase64');
  print('Private Key (Keep Secure):   $privBase64\n');
}

Future<void> _issueLicense(Ed25519 algorithm, List<String> args) async {
  String customer = 'Valued Customer';
  String hwid = '';
  String term = 'Permanent';
  int branches = 1;
  String outPath = 'beleka_license.lic';
  int? durationDays;
  int? months;
  int maxTills = 3;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--customer' && i + 1 < args.length) customer = args[++i];
    if (args[i] == '--hwid' && i + 1 < args.length) hwid = args[++i];
    if (args[i] == '--term' && i + 1 < args.length) term = args[++i];
    if (args[i] == '--branches' && i + 1 < args.length) branches = int.tryParse(args[++i]) ?? 1;
    if (args[i] == '--months' && i + 1 < args.length) months = int.tryParse(args[++i]);
    if (args[i] == '--days' && i + 1 < args.length) durationDays = int.tryParse(args[++i]);
    if ((args[i] == '--max-tills' || args[i] == '--tills') && i + 1 < args.length) {
      maxTills = int.tryParse(args[++i]) ?? 3;
    }
    if (args[i] == '--out' && i + 1 < args.length) outPath = args[++i];
  }

  if (hwid.isEmpty) {
    print('Error: --hwid is required. Example: --hwid BP-8F29-C4B2-9A1D-E703');
    return;
  }

  if (months != null && (months < 1 || months > 12)) {
    print('Warning: --months should typically be between 1 and 12 months.');
  }

  final now = DateTime.now().toUtc();
  DateTime? expiresAt;

  if (months != null) {
    // Add exact calendar months
    int newYear = now.year;
    int newMonth = now.month + months;
    while (newMonth > 12) {
      newYear += 1;
      newMonth -= 12;
    }
    expiresAt = DateTime.utc(newYear, newMonth, now.day, now.hour, now.minute, now.second);
    term = '$months Month${months > 1 ? 's' : ''} License';
  } else if (durationDays != null) {
    expiresAt = now.add(Duration(days: durationDays));
  }

  final randomId = 'BP-${now.millisecondsSinceEpoch.toString().substring(7)}';

  final payloadMap = {
    'product': 'Beleka Pro POS',
    'customer': customer,
    'installationId': randomId,
    'hardwareId': hwid.trim().toUpperCase(),
    'branches': branches,
    'term': term,
    'months': months,
    'maxTills': maxTills,
    'issuedAt': now.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
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

  // Canonical JSON representation for signing
  final canonicalJson = jsonEncode(payloadMap);
  final dataBytes = utf8.encode(canonicalJson);

  // Sign using Master Private Key
  final privBytes = base64Decode(kBelekaMasterPrivateKeyBase64);
  final keyPair = await algorithm.newKeyPairFromSeed(privBytes);
  final signature = await algorithm.sign(dataBytes, keyPair: keyPair);
  final signatureBase64 = base64Encode(signature.bytes);

  final fullLicenseMap = {
    ...payloadMap,
    'signature': signatureBase64,
  };

  final licenseJson = const JsonEncoder.withIndent('  ').convert(fullLicenseMap);
  final tokenBase64 = 'BELEKA-LIC-${base64Encode(utf8.encode(jsonEncode(fullLicenseMap)))}';

  // Save .lic file
  final outFile = File(outPath);
  await outFile.writeAsString(licenseJson);

  print('''
==================================================================
                  LICENSE ISSUED SUCCESSFULLY!                   
==================================================================
Customer:        $customer
Product:         Beleka Pro POS
Installation ID: $randomId
Hardware ID:     ${payloadMap['hardwareId']}
Branches:        $branches
Max Tills:       $maxTills Tills
Duration:        ${months != null ? "$months Months" : term}
Term:            $term (${expiresAt != null ? "Expires: $expiresAt" : "Never Expires"})
Status:          ACTIVE & CRYPTOGRAPHICALLY SIGNED

Saved File:      ${outFile.absolute.path}

Activation Token (Single Line Code):
$tokenBase64
==================================================================
''');
}

Future<void> _issueMasterLicense(Ed25519 algorithm, List<String> args) async {
  String name = 'Beleka Master Installer';
  String outPath = 'beleka_universal_master.lic';

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--name' && i + 1 < args.length) name = args[++i];
    if (args[i] == '--out' && i + 1 < args.length) outPath = args[++i];
  }

  final randomId = 'BP-MASTER-UNIVERSAL';

  final payloadMap = {
    'product': 'Beleka Pro POS Master',
    'customer': name,
    'installationId': randomId,
    'hardwareId': 'BP-UNIVERSAL-MASTER-KEY',
    'branches': 999,
    'term': 'Universal Master Deployment',
    'issuedAt': DateTime.now().toUtc().toIso8601String(),
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

  final licenseJson = const JsonEncoder.withIndent('  ').convert(fullLicenseMap);
  final tokenBase64 = 'BELEKA-LIC-${base64Encode(utf8.encode(jsonEncode(fullLicenseMap)))}';

  final outFile = File(outPath);
  await outFile.writeAsString(licenseJson);

  print('''
==================================================================
       UNIVERSAL MASTER LICENSE GENERATED SUCCESSFULLY!           
==================================================================
Type:            UNIVERSAL MASTER ON-SITE DEPLOYER KEY
Technician:      $name
Target HWID:     BP-UNIVERSAL-MASTER-KEY (Works on ANY machine)
Status:          AUTHENTIC & CRYPTOGRAPHICALLY SIGNED

Saved Master File:
${outFile.absolute.path}

Master Activation Token:
$tokenBase64

How to use:
Keep "${outFile.uri.pathSegments.last}" on your USB drive. When you install
Beleka POS on ANY customer machine, simply import this file or paste
the token to activate the machine instantly on-site!
==================================================================
''');
}

Future<void> _verifyLicenseFile(Ed25519 algorithm, List<String> args) async {
  String filePath = 'beleka_license.lic';
  String? testHwid;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--file' && i + 1 < args.length) filePath = args[++i];
    if (args[i] == '--hwid' && i + 1 < args.length) testHwid = args[++i];
  }

  final file = File(filePath);
  if (!file.existsSync()) {
    print('Error: File $filePath does not exist.');
    return;
  }

  final content = await file.readAsString();
  Map<String, dynamic> licenseMap;
  try {
    licenseMap = jsonDecode(content);
  } catch (e) {
    print('Error: Invalid JSON license format.');
    return;
  }

  final signatureBase64 = licenseMap['signature'] as String?;
  if (signatureBase64 == null) {
    print('Error: License missing cryptographic signature.');
    return;
  }

  final payloadMap = Map<String, dynamic>.from(licenseMap)..remove('signature');
  final canonicalJson = jsonEncode(payloadMap);
  final dataBytes = utf8.encode(canonicalJson);
  final signatureBytes = base64Decode(signatureBase64);

  final pubBytes = base64Decode(kBelekaMasterPublicKeyBase64);
  final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);

  final isValid = await algorithm.verify(
    dataBytes,
    signature: Signature(signatureBytes, publicKey: publicKey),
  );

  print('\n=== LICENSE VERIFICATION RESULT ===');
  print('Cryptographic Signature: ${isValid ? "VALID (Authentic Beleka License)" : "INVALID (TAMPERED OR FAKE)"}');
  print('Customer:                ${licenseMap['customer']}');
  print('Licensed HWID:           ${licenseMap['hardwareId']}');
  print('Term:                    ${licenseMap['term']}');

  if (testHwid != null) {
    final hwidMatches = (licenseMap['hardwareId'] as String).toUpperCase() == testHwid.toUpperCase();
    print('Hardware Match Check:    ${hwidMatches ? "MATCHED (Authorized on this machine)" : "MISMATCH (LOCKED - WRONG MACHINE)"}');
  }
  print('===================================\n');
}

Future<void> _showCurrentMachineHwid() async {
  // Read characteristics directly
  final components = <String, String>{};

  String readFirstAvailable(List<String> paths) {
    for (final p in paths) {
      try {
        final f = File(p);
        if (f.existsSync()) {
          final c = f.readAsStringSync().trim();
          if (c.isNotEmpty) return c;
        }
      } catch (_) {}
    }
    return '';
  }

  if (Platform.isLinux) {
    components['machine_id'] = readFirstAvailable(['/etc/machine-id', '/var/lib/dbus/machine-id']);
    components['product_uuid'] = readFirstAvailable(['/sys/class/dmi/id/product_uuid']);
    components['board_serial'] = readFirstAvailable(['/sys/class/dmi/id/board_serial', '/sys/class/dmi/id/product_serial']);
  }
  components['hostname'] = Platform.localHostname;
  components['os'] = Platform.operatingSystemVersion;

  final rawEntropy = components.entries.map((e) => '${e.key}=${e.value}').join('|');
  final key = utf8.encode('BELEKA_POS_HARDWARE_FINGERPRINT_V1_SECURE_SALT');
  final bytes = utf8.encode(rawEntropy);
  final hmac = crypto.Hmac(crypto.sha256, key);
  final digest = hmac.convert(bytes);
  final hex = digest.toString().toUpperCase();

  final chunk1 = hex.substring(0, 4);
  final chunk2 = hex.substring(4, 8);
  final chunk3 = hex.substring(8, 12);
  final chunk4 = hex.substring(12, 16);
  final hwid = 'BP-$chunk1-$chunk2-$chunk3-$chunk4';

  print('''
==================================================================
                 CURRENT MACHINE HARDWARE ID (HWID)               
==================================================================
Hardware ID:    $hwid
OS:             ${Platform.operatingSystem} (${Platform.operatingSystemVersion})
Hostname:       ${Platform.localHostname}
Machine UUID:   ${components['product_uuid'] ?? components['machine_id']}
==================================================================
''');
}
