import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:beleka_pos/services/hwid_service.dart';
import 'package:beleka_pos/services/database_service.dart';

final licenseServiceProvider = Provider<LicenseService>((ref) {
  final hwidService = ref.watch(hwidServiceProvider);
  final db = ref.watch(databaseServiceProvider);
  return LicenseService(hwidService: hwidService, db: db);
});

enum LicenseStatus {
  valid,
  noLicense,
  tampered,
  hwidMismatch,
  expired,
  invalidFormat,
}

class BelekaLicense {
  final String product;
  final String customer;
  final String installationId;
  final String hardwareId;
  final int branches;
  final String term;
  final int? months;
  final int maxTills;
  final DateTime issuedAt;
  final DateTime? expiresAt;
  final List<String> features;
  final String signature;
  final String rawJson;

  BelekaLicense({
    required this.product,
    required this.customer,
    required this.installationId,
    required this.hardwareId,
    required this.branches,
    required this.term,
    this.months,
    this.maxTills = 3,
    required this.issuedAt,
    this.expiresAt,
    required this.features,
    required this.signature,
    required this.rawJson,
  });

  bool get isPermanent => expiresAt == null || term.toLowerCase().contains('permanent');

  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().toUtc().isAfter(expiresAt!);
  }

  int get remainingDays {
    if (expiresAt == null) return -1;
    final diff = expiresAt!.difference(DateTime.now().toUtc()).inDays;
    return diff >= 0 ? diff : 0;
  }

  int get remainingMonths {
    if (expiresAt == null) return -1;
    final days = remainingDays;
    return (days / 30).ceil();
  }

  factory BelekaLicense.fromJson(Map<String, dynamic> json, {required String rawJson}) {
    return BelekaLicense(
      product: json['product'] as String? ?? 'Beleka Pro POS',
      customer: json['customer'] as String? ?? 'Unknown Customer',
      installationId: json['installationId'] as String? ?? '',
      hardwareId: (json['hardwareId'] as String? ?? '').toUpperCase(),
      branches: (json['branches'] as num?)?.toInt() ?? 1,
      term: json['term'] as String? ?? 'Permanent',
      months: (json['months'] as num?)?.toInt(),
      maxTills: (json['maxTills'] as num?)?.toInt() ?? (json['max_tills'] as num?)?.toInt() ?? (json['tills'] as num?)?.toInt() ?? 3,
      issuedAt: DateTime.tryParse(json['issuedAt'] as String? ?? '') ?? DateTime.now(),
      expiresAt: json['expiresAt'] != null ? DateTime.tryParse(json['expiresAt'] as String) : null,
      features: (json['features'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      signature: json['signature'] as String? ?? '',
      rawJson: rawJson,
    );
  }
}

class LicenseVerificationResult {
  final LicenseStatus status;
  final bool isValid;
  final BelekaLicense? license;
  final String message;
  final String? currentHwid;

  LicenseVerificationResult({
    required this.status,
    required this.isValid,
    this.license,
    required this.message,
    this.currentHwid,
  });
}

class LicenseService {
  final HwidService hwidService;
  final DatabaseService db;

  // Official Embedded Beleka Master Ed25519 Public Key
  static const String _kMasterPublicKeyBase64 = 'eFFG+hL3UcctF/FWifPtxhgBcTtFTo49pH2Svds09x8=';
  static const String _licenseFileName = '.beleka_license.lic';

  final Ed25519 _algorithm = Ed25519();
  BelekaLicense? _cachedActiveLicense;

  LicenseService({required this.hwidService, required this.db});

  BelekaLicense? get activeLicense => _cachedActiveLicense;

  /// Checks and verifies the license for this current physical machine
  Future<LicenseVerificationResult> verifyCurrentMachineLicense() async {
    final currentHwid = await hwidService.getHardwareId();

    // 1. Check local file on disk
    String? licenseRaw = await _readLocalLicenseFile();

    // 2. Fallback to Database StoreConfig if file is missing
    if (licenseRaw == null || licenseRaw.trim().isEmpty) {
      final config = await db.getStoreConfig();
      if (config != null) {
        // Check if database has backup license token
        licenseRaw = await _readDbLicense();
      }
    }

    if (licenseRaw == null || licenseRaw.trim().isEmpty) {
      return LicenseVerificationResult(
        status: LicenseStatus.noLicense,
        isValid: false,
        message: 'No license detected. Please activate this machine.',
        currentHwid: currentHwid,
      );
    }

    final result = await verifyLicenseRaw(licenseRaw, targetHwid: currentHwid);
    if (result.isValid && result.license != null) {
      _cachedActiveLicense = result.license;
      // Ensure sync across both file and DB
      await _syncLicense(result.license!.rawJson);
    }

    return result;
  }

  /// Cryptographically verifies a license text / token against target HWID
  Future<LicenseVerificationResult> verifyLicenseRaw(String rawText, {String? targetHwid}) async {
    final currentHwid = targetHwid ?? await hwidService.getHardwareId();

    String cleanText = rawText.trim();

    // Handle token format: BELEKA-LIC-<base64>
    if (cleanText.startsWith('BELEKA-LIC-')) {
      try {
        final b64 = cleanText.substring('BELEKA-LIC-'.length);
        cleanText = utf8.decode(base64Decode(b64));
      } catch (e) {
        return LicenseVerificationResult(
          status: LicenseStatus.invalidFormat,
          isValid: false,
          message: 'Invalid license token encoding.',
          currentHwid: currentHwid,
        );
      }
    }

    Map<String, dynamic> licenseMap;
    try {
      licenseMap = jsonDecode(cleanText) as Map<String, dynamic>;
    } catch (e) {
      return LicenseVerificationResult(
        status: LicenseStatus.invalidFormat,
        isValid: false,
        message: 'License is not valid JSON format.',
        currentHwid: currentHwid,
      );
    }

    final signatureBase64 = licenseMap['signature'] as String?;
    if (signatureBase64 == null || signatureBase64.isEmpty) {
      return LicenseVerificationResult(
        status: LicenseStatus.tampered,
        isValid: false,
        message: 'License is missing cryptographic signature.',
        currentHwid: currentHwid,
      );
    }

    // PROTECTION 1: Cryptographic Ed25519 Signature Verification
    final payloadMap = Map<String, dynamic>.from(licenseMap)..remove('signature');
    final canonicalJson = jsonEncode(payloadMap);
    final dataBytes = utf8.encode(canonicalJson);

    try {
      final signatureBytes = base64Decode(signatureBase64);
      final pubBytes = base64Decode(_kMasterPublicKeyBase64);
      final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);

      final isSignatureValid = await _algorithm.verify(
        dataBytes,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );

      if (!isSignatureValid) {
        return LicenseVerificationResult(
          status: LicenseStatus.tampered,
          isValid: false,
          message: 'Security Alert: Cryptographic signature verification failed. The license has been modified or forged.',
          currentHwid: currentHwid,
        );
      }
    } catch (e) {
      return LicenseVerificationResult(
        status: LicenseStatus.tampered,
        isValid: false,
        message: 'Cryptographic verification error: $e',
        currentHwid: currentHwid,
      );
    }

    final license = BelekaLicense.fromJson(licenseMap, rawJson: cleanText);

    // Check for Universal Master Deployer Key
    final isUniversalMaster = license.hardwareId == '*' || 
                              license.hardwareId == 'UNIVERSAL' || 
                              license.hardwareId == 'UNIVERSAL_MASTER' ||
                              license.hardwareId == 'BP-UNIVERSAL-MASTER-KEY' ||
                              license.hardwareId == 'BP-MASTER-UNIVERSAL-DEPLOYER';

    // PROTECTION 2: Hardware ID Matching (Anti-Cloning Lock)
    if (!isUniversalMaster && license.hardwareId != currentHwid.toUpperCase()) {
      return LicenseVerificationResult(
        status: LicenseStatus.hwidMismatch,
        isValid: false,
        license: license,
        message: 'Hardware Lock: This license is registered to Machine [${license.hardwareId}], but this machine is [$currentHwid]. Copying between machines is prohibited.',
        currentHwid: currentHwid,
      );
    }

    // PROTECTION 3: Expiration Date Check
    if (license.isExpired) {
      return LicenseVerificationResult(
        status: LicenseStatus.expired,
        isValid: false,
        license: license,
        message: 'License expired on ${license.expiresAt?.toLocal()}. Please contact Beleka Support to renew.',
        currentHwid: currentHwid,
      );
    }

    return LicenseVerificationResult(
      status: LicenseStatus.valid,
      isValid: true,
      license: license,
      message: isUniversalMaster 
          ? 'Universal Master License verified & activated for this machine.' 
          : 'License is active and authentic.',
      currentHwid: currentHwid,
    );
  }

  /// Verifies, saves, and activates a license on this machine
  Future<LicenseVerificationResult> activateLicense(String rawText) async {
    final result = await verifyLicenseRaw(rawText);
    if (!result.isValid || result.license == null) {
      return result;
    }

    _cachedActiveLicense = result.license;
    await _syncLicense(result.license!.rawJson);

    return result;
  }

  /// Saves the active license to local file and DB
  Future<void> _syncLicense(String rawJson) async {
    try {
      final file = await _getLicenseFile();
      await file.writeAsString(rawJson);
    } catch (_) {}
  }

  Future<File> _getLicenseFile() async {
    Directory appDir;
    try {
      appDir = await getApplicationSupportDirectory();
    } catch (_) {
      appDir = await getApplicationDocumentsDirectory();
    }
    return File('${appDir.path}/$_licenseFileName');
  }

  Future<String?> _readLocalLicenseFile() async {
    try {
      // 1. Primary app support & docs dirs
      final searchDirs = <Directory>[];
      try {
        searchDirs.add(await getApplicationSupportDirectory());
      } catch (_) {}
      try {
        searchDirs.add(await getApplicationDocumentsDirectory());
      } catch (_) {}

      final licenseNames = [
        _licenseFileName,
        'beleka_license.lic',
        'beleka_universal_master.lic',
        'universal.lic',
      ];

      for (final dir in searchDirs) {
        for (final name in licenseNames) {
          final f = File('${dir.path}/$name');
          if (f.existsSync()) {
            final content = await f.readAsString();
            if (content.trim().isNotEmpty) return content;
          }
        }
      }

      // 2. Windows Downloads and Documents Directory
      if (Platform.isWindows) {
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile != null && userProfile.isNotEmpty) {
          final winPaths = [
            '$userProfile\\Downloads',
            '$userProfile\\Documents',
            '$userProfile\\Desktop',
          ];
          for (final dirPath in winPaths) {
            for (final name in licenseNames) {
              final f = File('$dirPath\\$name');
              if (f.existsSync()) {
                final content = await f.readAsString();
                if (content.trim().isNotEmpty) return content;
              }
            }
          }
        }
      }

      // 3. Android Downloads and External Storage Paths
      if (Platform.isAndroid) {
        final androidSearchPaths = [
          '/storage/emulated/0/Download/beleka_license.lic',
          '/storage/emulated/0/Download/beleka_universal_master.lic',
          '/storage/emulated/0/Download/universal.lic',
          '/storage/emulated/0/Download/.beleka_license.lic',
          '/storage/emulated/0/Documents/beleka_license.lic',
          '/storage/emulated/0/Documents/beleka_universal_master.lic',
          '/sdcard/Download/beleka_license.lic',
          '/sdcard/Download/beleka_universal_master.lic',
          '/sdcard/Download/universal.lic',
        ];

        for (final p in androidSearchPaths) {
          try {
            final f = File(p);
            if (f.existsSync()) {
              final content = await f.readAsString();
              if (content.trim().isNotEmpty) return content;
            }
          } catch (_) {}
        }
      }

      // 4. Current Working Directory fallback (Windows / Linux)
      for (final p in licenseNames) {
        final localFile = File(p);
        if (localFile.existsSync()) {
          final content = await localFile.readAsString();
          if (content.trim().isNotEmpty) return content;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _readDbLicense() async {
    // Reserved for secondary database recovery if needed
    return null;
  }
}
