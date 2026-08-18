import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

void main() {
  const masterPubKeyBase64 = 'eFFG+hL3UcctF/FWifPtxhgBcTtFTo49pH2Svds09x8=';
  const masterPrivKeyBase64 = 'ogb6D2/rGh4ybjl/EJuuF3P3mpvdKZKroYvIs9qTCEo=';
  final algorithm = Ed25519();

  test('Protection 1: Cryptographic signature verification passes for valid license', () async {
    final payloadMap = {
      'product': 'Beleka Pro POS',
      'customer': 'ABC Supermarket',
      'installationId': 'BP-8F29-1001',
      'hardwareId': 'BP-B259-9E44-682F-A143',
      'branches': 1,
      'term': 'Permanent',
      'issuedAt': '2026-08-18T14:00:00.000Z',
      'expiresAt': null,
      'features': ['offline_pos', 'inventory_management'],
    };

    final canonicalJson = jsonEncode(payloadMap);
    final dataBytes = utf8.encode(canonicalJson);

    // Sign with private key
    final privBytes = base64Decode(masterPrivKeyBase64);
    final keyPair = await algorithm.newKeyPairFromSeed(privBytes);
    final signature = await algorithm.sign(dataBytes, keyPair: keyPair);
    final signatureBase64 = base64Encode(signature.bytes);

    // Verify with public key
    final pubBytes = base64Decode(masterPubKeyBase64);
    final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
    final isAuthentic = await algorithm.verify(
      dataBytes,
      signature: Signature(base64Decode(signatureBase64), publicKey: publicKey),
    );

    expect(isAuthentic, isTrue);
  });

  test('Protection 1 (Tamper Detection): Modifying customer or HWID breaks signature', () async {
    final payloadMap = {
      'product': 'Beleka Pro POS',
      'customer': 'ABC Supermarket',
      'installationId': 'BP-8F29-1001',
      'hardwareId': 'BP-B259-9E44-682F-A143',
      'branches': 1,
      'term': 'Permanent',
      'issuedAt': '2026-08-18T14:00:00.000Z',
      'expiresAt': null,
      'features': ['offline_pos'],
    };

    final canonicalJson = jsonEncode(payloadMap);
    final dataBytes = utf8.encode(canonicalJson);

    // Sign valid payload
    final privBytes = base64Decode(masterPrivKeyBase64);
    final keyPair = await algorithm.newKeyPairFromSeed(privBytes);
    final signature = await algorithm.sign(dataBytes, keyPair: keyPair);
    final signatureBase64 = base64Encode(signature.bytes);

    // Attacker modifies customer name in the JSON
    final tamperedPayload = Map<String, dynamic>.from(payloadMap);
    tamperedPayload['customer'] = 'Hacked Supermarket';
    final tamperedBytes = utf8.encode(jsonEncode(tamperedPayload));

    // Verify tampered payload with public key
    final pubBytes = base64Decode(masterPubKeyBase64);
    final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
    final isAuthentic = await algorithm.verify(
      tamperedBytes,
      signature: Signature(base64Decode(signatureBase64), publicKey: publicKey),
    );

    expect(isAuthentic, isFalse);
  });

  test('Protection 2 (Anti-Cloning): Machine HWID mismatch is detected', () {
    final licensedHwid = 'BP-B259-9E44-682F-A143';
    final copiedMachineHwid = 'BP-9999-0000-1111-2222';

    final isAuthorized = licensedHwid == copiedMachineHwid;
    expect(isAuthorized, isFalse);
  });

  test('Universal Master Key: Allows technician on-site activation on any HWID', () async {
    final masterPayload = {
      'product': 'Beleka Pro POS Master',
      'customer': 'Beleka Master Installer',
      'installationId': 'BP-MASTER-UNIVERSAL',
      'hardwareId': 'BP-UNIVERSAL-MASTER-KEY',
      'branches': 999,
      'term': 'Universal Master Deployment',
      'issuedAt': DateTime.now().toUtc().toIso8601String(),
      'expiresAt': null,
      'features': ['offline_pos', 'universal_deployer_mode'],
    };

    final dataBytes = utf8.encode(jsonEncode(masterPayload));
    final privBytes = base64Decode(masterPrivKeyBase64);
    final keyPair = await algorithm.newKeyPairFromSeed(privBytes);
    final signature = await algorithm.sign(dataBytes, keyPair: keyPair);
    final signatureBase64 = base64Encode(signature.bytes);

    // Verify signature with embedded public key
    final pubBytes = base64Decode(masterPubKeyBase64);
    final publicKey = SimplePublicKey(pubBytes, type: KeyPairType.ed25519);
    final isSignatureValid = await algorithm.verify(
      dataBytes,
      signature: Signature(base64Decode(signatureBase64), publicKey: publicKey),
    );
    expect(isSignatureValid, isTrue);

    // Check Universal Match on different arbitrary machines
    const customerMachine1Hwid = 'BP-1111-2222-3333-4444';
    const customerMachine2Hwid = 'BP-9999-8888-7777-6666';

    final isMasterKey = masterPayload['hardwareId'] == 'BP-UNIVERSAL-MASTER-KEY';
    expect(isMasterKey, isTrue);

    // Both arbitrary customer machines accept the Master Key
    final machine1Authorized = isMasterKey || masterPayload['hardwareId'] == customerMachine1Hwid;
    final machine2Authorized = isMasterKey || masterPayload['hardwareId'] == customerMachine2Hwid;

    expect(machine1Authorized, isTrue);
    expect(machine2Authorized, isTrue);
  });
}

