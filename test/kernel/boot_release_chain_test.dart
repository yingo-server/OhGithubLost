/// 发布信任链测试：私钥 ↔ 公钥 ↔ 规范化 ↔ 启动校验，一条链端到端。
///
/// 这是"发布包关闭开发旁路"的保险丝：
/// - 仓库私钥签出的清单，必须能被内嵌公钥（`release_trust_root.dart`）验证；
/// - 签名清单 + 旁路关闭 = 干净启动（零告警）；
/// - 篡改清单 = 拒绝启动。
///
/// 任何一环被改动（换密钥、改规范化、改校验逻辑）都会在这里变红。
library;

import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/kernel/boot/boot_fs.dart';
import 'package:ohgithublost/kernel/boot/boot_loader.dart';
import 'package:ohgithublost/kernel/boot/boot_manifest.dart';
import 'package:ohgithublost/kernel/boot/integrity_verifier.dart';
import 'package:ohgithublost/kernel/boot/release_trust_root.dart';
import 'package:ohgithublost/kernel/boot/trust_warnings.dart';
import 'package:ohgithublost/kernel/diagnostics.dart';

const String _keyPath = '.github/signing/ogl-boot-ed25519.key';
const String _manifestPath = 'boot/manifest.json';

Future<SimpleKeyPair> _loadKeyPair() async {
  final file = File(_keyPath);
  expect(file.existsSync(), isTrue, reason: '信任根私钥缺失: $_keyPath');
  final seed = base64.decode(file.readAsStringSync().trim());
  return Ed25519().newKeyPairFromSeed(seed);
}

Future<String> _signPayload(
  Map<String, Object?> payload,
  SimpleKeyPair keyPair,
) async {
  final message = utf8.encode(canonicalJsonEncode(payload));
  final signature = await Ed25519().sign(message, keyPair: keyPair);
  return base64.encode(signature.bytes);
}

Map<String, Object?> _payload() => <String, Object?>{
      'schema': 1,
      'appVersion': '0.0.0-test',
      'buildId': 'chain-test',
      'generatedAt': '2026-01-01T00:00:00Z',
      'modules': <Object?>[],
      'coreDigest': 'test-digest',
    };

void main() {
  test('信任根：私钥签出的清单必须能被内嵌公钥验证', () async {
    final keyPair = await _loadKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    expect(publicKey.bytes, equals(kOgLReleasePublicKey),
        reason: '仓库私钥与内嵌公钥不匹配（信任根脱节）');

    final payload = _payload();
    final signature = await _signPayload(payload, keyPair);
    final manifest = BootManifest.fromJson(<String, Object?>{
      ...payload,
      'signature': signature,
    });

    final verifier = BootIntegrityVerifier(
      fileSystem: InMemoryBootFileSystem(),
      releasePublicKey: kOgLReleasePublicKey,
    );
    expect(await verifier.verifySignature(manifest), isTrue);
  });

  test('启动链：签名清单 + 旁路关闭 = 干净启动（零告警）', () async {
    final keyPair = await _loadKeyPair();
    final payload = _payload();
    final signature = await _signPayload(payload, keyPair);

    final fs = InMemoryBootFileSystem();
    fs.writeText(_manifestPath, jsonEncode(<String, Object?>{
      ...payload,
      'signature': signature,
    }));

    final warnings = TrustWarningCollector();
    final loader = BootLoader(
      fileSystem: fs,
      verifier: BootIntegrityVerifier(
        fileSystem: fs,
        releasePublicKey: kOgLReleasePublicKey,
      ),
      diagnostics: KernelDiagnostics(appVersion: 'test'),
      warnings: warnings,
      manifestPath: _manifestPath,
      developmentBypass: false,
    );

    final result = await loader.run();
    expect(result.succeeded, isTrue);
    expect(result.safeMode, isFalse);
    expect(warnings.count, 0, reason: '正式启动不允许产生任何信任告警');
  });

  test('启动链：清单被篡改 = 拒绝启动', () async {
    final keyPair = await _loadKeyPair();
    final payload = _payload();
    final signature = await _signPayload(payload, keyPair);

    // 篡改：换了 appVersion，签名保持原样 → 必须拒绝。
    final tampered = <String, Object?>{
      ...payload,
      'appVersion': '9.9.9-evil',
      'signature': signature,
    };
    final fs = InMemoryBootFileSystem();
    fs.writeText(_manifestPath, jsonEncode(tampered));

    final loader = BootLoader(
      fileSystem: fs,
      verifier: BootIntegrityVerifier(
        fileSystem: fs,
        releasePublicKey: kOgLReleasePublicKey,
      ),
      diagnostics: KernelDiagnostics(appVersion: 'test'),
      warnings: TrustWarningCollector(),
      manifestPath: _manifestPath,
      developmentBypass: false,
    );

    final result = await loader.run();
    expect(result.succeeded, isFalse);
    expect(result.failureReason, contains('签名'));
  });
}