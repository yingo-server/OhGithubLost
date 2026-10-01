/// OGL 应用入口。
///
/// ## 这个文件做三件事
/// 1. **组装四层**：`baseLayerModules()` + `domainLayerModules()` + `SurfaceLayerModule`
///    （顺序即拓扑：L1 → L2 → L3，内核会自己校验依赖）；
/// 2. **零外部资源启动**：引导清单**不读文件、不落盘**——
///    仓库里没有任何 `assets/`，所以清单只能是"缺失"或"由发布流程注入"。
///    调试构建允许缺失（`developmentBypass`，必然产生 `OGL-BOOT-107` 告警）；
///    发布构建要求清单已签名，否则**拒绝启动**（这是信任链条的第一环）。
/// 3. **把启动结果交给 UI**：[OgLApp] 会展示启动报告与信任告警，
///    用户第一次打开就能看见"到底加载了什么"。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'base/base_bridge.dart';
import 'domain/domain_bridge.dart';
import 'kernel/boot/boot_fs.dart';
import 'kernel/boot/boot_loader.dart';
import 'kernel/boot/integrity_verifier.dart';
import 'kernel/boot/trust_policy.dart';
import 'kernel/boot/trust_warnings.dart';
import 'kernel/contract/module.dart';
import 'kernel/diagnostics.dart';
import 'kernel/kernel.dart';
import 'surface/app/og_l_app.dart';
import 'surface/surface_bridge.dart';

/// 应用版本（零外部资源：不读 pubspec，直接内联常量）。
///
/// 与 `pubspec.yaml` 的 `version:` 保持一致，发布流程会做一致性校验。
const String kOgLAppVersion = '0.3.0';

/// 发布构建注入的引导清单路径（由 `--dart-define` 提供；调试构建为空）。
const String kOgLBootManifestPath = String.fromEnvironment('OGL_BOOT_MANIFEST');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final diagnostics = KernelDiagnostics(appVersion: kOgLAppVersion);
  final warnings = TrustWarningCollector();

  // ★ 零外部资源的关键一步：
  // 引导文件系统完全在内存里，仓库不含任何 assets 文件。
  // 发布构建时由 CI 把签名后的清单写进 `kOgLBootManifestPath` 指定的位置
  // （通过 `--dart-define` 传入），调试构建则允许缺失并告警。
  final bootFileSystem = InMemoryBootFileSystem();
  final hasSignedManifest = kReleaseMode && kOgLBootManifestPath.isNotEmpty;

  final kernel = OgLKernel(
    diagnostics: diagnostics,
    appVersion: kOgLAppVersion,
    bootLoader: BootLoader(
      fileSystem: bootFileSystem,
      verifier: BootIntegrityVerifier(
        fileSystem: bootFileSystem,
        // 32 字节 Ed25519 公钥；调试构建下不参与签名校验（清单本就缺失）。
        releasePublicKey: List<int>.filled(
          BootIntegrityVerifier.ed25519PublicKeyLength,
          0,
        ),
      ),
      diagnostics: diagnostics,
      warnings: warnings,
      policy: const BootTrustPolicy(),
      manifestPath: 'boot/manifest.json',
      // 调试放行；发布构建**必须**有已签名清单，否则启动即拒绝。
      developmentBypass: !hasSignedManifest,
    ),
  );

  // 展示层模块单独持有，方便拿到装配好的桥（避免依赖内核内部结构）。
  final surfaceModule = SurfaceLayerModule();

  final List<OgLModule> modules = <OgLModule>[
    ...baseLayerModules(),
    ...domainLayerModules(),
    surfaceModule,
  ];

  try {
    final report = await kernel.boot(modules);
    runApp(OgLApp(surface: surfaceModule.bridge, report: report));
  } on KernelBootException catch (error) {
    // 启动被拒（清单签名失败 / 模块依赖不满足）：**不静默降级**，
    // 直接把原因摊给用户看——这是数据安全产品该有的态度。
    runApp(OgLBootFailureApp(message: error.toString()));
  }
}
