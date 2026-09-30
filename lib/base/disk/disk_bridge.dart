/// L1 底座级 · 硬盘逻辑：门面与模块装配。
///
/// 硬盘逻辑对外只暴露一个门面 [DiskBridge]：
/// KV、保险库、文件、路径规划、**一致性缓存**都在它后面。
/// 上层拿不到 `Dio`，也拿不到任何平台通道——这是"底座可替换"的前提。
library;

import '../../kernel/contract/module.dart';
import 'disk_cache.dart';
import 'disk_store.dart';

/// 硬盘逻辑门面。
class DiskBridge {
  /// 创建门面。
  const DiskBridge({
    required this.kv,
    required this.vault,
    required this.files,
    required this.paths,
    required this.cache,
  });

  /// 键值存储。
  final DiskKv kv;

  /// 安全保险库。
  final DiskVault vault;

  /// 文件存储。
  final DiskFileStore files;

  /// 路径规划。
  final DiskPaths paths;

  /// 一致性缓存（**致命区**，见 `docs/CONSISTENCY.md`）。
  final RepositoryCache cache;

  @override
  String toString() => 'DiskBridge(kv=${kv.runtimeType}, '
      'files=${files.runtimeType}, vault=${vault.runtimeType})';
}

/// 硬盘逻辑模块（`base.disk`）。
///
/// 依赖：无。
/// 提供：`disk.kv` / `disk.vault` / `disk.files` / `disk.cache`。
class DiskModule extends OgLModule {
  /// 创建模块。
  ///
  /// 所有依赖都可注入，缺省走内存实现：这样**同一份代码**
  /// 既能跑在 CI 的内存环境，也能在真机上换成平台实现。
  DiskModule({
    DiskKv? kv,
    DiskVault? vault,
    DiskFileStore? files,
    DiskPaths? paths,
    RepositoryCache? cache,
  })  : kv = kv ?? InMemoryKv(),
        vault = vault ?? InMemoryVault(),
        files = files ?? InMemoryFileStore(),
        paths = paths ?? const InMemoryPaths(),
        cache = cache ?? RepositoryCache();

  /// 键值存储。
  final DiskKv kv;

  /// 安全保险库。
  final DiskVault vault;

  /// 文件存储。
  final DiskFileStore files;

  /// 路径规划。
  final DiskPaths paths;

  /// 一致性缓存。
  final RepositoryCache cache;

  /// 门面实例（[onRegister] 后可用）。
  late final DiskBridge bridge;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'base.disk',
        layer: ModuleLayer.base,
        version: '0.1.0',
        provides: <String>[
          'disk.kv',
          'disk.vault',
          'disk.files',
          'disk.cache',
        ],
        description: '底座·硬盘逻辑（KV / 保险库 / 文件 / 缓存一致性 D1–D7）',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    // 缓存引擎与诊断中枢接线：让 D1–D7 的每一次拒绝都进入审计日志。
    final repositoryCache = cache;
    bridge = DiskBridge(
      kv: kv,
      vault: vault,
      files: files,
      paths: paths,
      cache: repositoryCache,
    );
    context.di.register<DiskBridge>(bridge);
    context.di.register<RepositoryCache>(repositoryCache);
    context.diagnostics.info(
      'DISK',
      '硬盘逻辑就绪',
      code: 'OGL-DISK-001',
      data: <String, Object?>{
        'kv': kv.runtimeType.toString(),
        'files': files.runtimeType.toString(),
        'vault': vault.runtimeType.toString(),
      },
    );
  }
}