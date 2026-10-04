/// L3 展示级 · 表面桥（Surface Bridge）与装配根。
///
/// ## 分层纪律
/// 本文件是**展示层的装配根**，和 `DomainLayerModule` 同级，因此它可以跨层
/// import 底座桥（就像中枢层那样）。除此之外，
/// **所有页面与控件一律只通过 [SurfaceBridge] 取用**，不得直接 import base/domain。
///
/// ## 它把两件事接到一起
/// 1. **设置落盘**：`OgLSettingsController` ↔ L1 的 KV（`base.disk.kv`）；
/// 2. **DNS 即时生效**：设置里的 DNS 选择 → `base.net.applyDnsSelection`。
///
/// 主题编译（`themeFor`）也在这里收口：
/// 设置里的明暗偏好 + 系统亮度 → 唯一一次 `ThemeData` 编译。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../base/base_bridge.dart';
import '../base/disk/app_dirs.dart';
import '../base/disk/disk_cache.dart';
import '../base/disk/disk_store.dart';
import '../base/net/net_bridge.dart';
import '../domain/domain_bridge.dart';
import '../kernel/bridge_registry.dart';
import '../kernel/contract/module.dart';
import 'app/error_surface.dart';
import 'i18n/og_l_i18n.dart';
import 'settings.dart';
import 'theme.dart';
import 'types.dart';
import 'util/accel.dart';

/// 表面桥：展示层对外的唯一入口。
class SurfaceBridge {
  /// 创建桥。
  SurfaceBridge({
    required this.settings,
    required this.domain,
    this.net,
    this.cache,
    this.storageProbe,
  });

  /// 从内核桥表解析（展示层的标准取用方式）。
  static SurfaceBridge of(KernelBridgeRegistry bridges) =>
      bridges.resolve<SurfaceBridge>(ModuleLayer.surface.key);

  /// 设置控制器。
  final OgLSettingsController settings;

  /// 中枢桥（页面需要业务数据时通过它取）。
  final DomainBridge domain;

  /// 网络门面（**仅供设置页应用 DNS 用**；页面不得直接使用）。
  final NetBridge? net;

  /// 一致性缓存（**仅供账号切换时清空**，页面不得直接读写）。
  final RepositoryCache? cache;

  /// 存储可用性探针（由装配层注入；返回是否可写）。
  ///
  /// 展示层不直接依赖底座，因此以函数形式注入。
  final Future<bool> Function()? storageProbe;

  /// 探测存储是否可用（无探针时按可用处理）。
  Future<bool> ensureStorage() async {
    final probe = storageProbe;
    if (probe == null) {
      return true;
    }
    try {
      return await probe();
    } catch (_) {
      return false;
    }
  }

  /// 应用根目录展示串（供"关于"等处展示实际落盘位置）。
  Future<String> appRootPath() async {
    try {
      return await OgLAppDirs.root();
    } catch (_) {
      return OgLI18n.instance.t('common', 'unknown');
    }
  }

  /// 清空本机仓库缓存。
  ///
  /// **多用户安全**：缓存按仓库维度存放，不含账号信息。若切换账号后不清理，
  /// 就可能出现"用 B 账号看到 A 账号私有仓库缓存"的串台。因此切换账号时
  /// 由设置/账户页显式调用本方法。
  Future<int> clearRepositoryCache() async => await cache?.purge() ?? 0;

  /// 清空**全部**本机缓存（仓库缓存 + DNS 缓存 + 页面分页快照）。
  ///
  /// 用户要求：**切换 / 移除账号时必须清除所有缓存**。
  /// 页面级快照由调用方额外调用 `clearOgLRepoPageCaches()`（避免桥依赖页面）。
  Future<int> clearAllCaches() async {
    final int removed = await clearRepositoryCache();
    try {
      // 只读端点缓存（releases / branches / issues …）同样按账号隔离，
      // 切号必须一并清空，否则会出现"用 B 账号看到 A 账号缓存"的串台。
      await domain.api.invalidateReadCache();
      net?.dns?.cache.clear();
    } catch (error) {
      // 不允许静默：清不掉也要留痕（通知中心可见）。
      OgLAppLog.instance.add(
        '缓存',
        '清空 DNS 缓存失败：$error',
        severity: OgLNoticeSeverity.warning,
      );
    }
    return removed;
  }

  /// DNS 可选服务器（id → 展示名）。
  Map<String, String> get dnsServerChoices =>
      net?.dnsServerChoices ?? const <String, String>{};

  /// 当前 DNS 策略摘要（UI 必须向用户展示，不得让用户猜）。
  String get dnsSummary => net?.dnsSummary ?? OgLI18n.instance.t('common', 'systemResolve');

  /// 把当前设置里的 DNS 选择应用到网络底座（策略对象可变 → 即时生效）。
  void applyDns() {
    final OgLSettings current = settings.settings;
    net?.applyDnsSelection(
      custom: current.dnsMode == 'custom',
      serverId: current.dnsServerId,
      preferDoh: current.dnsPreferDoh,
    );
  }

  /// 便捷：改 DNS 模式并即刻应用。
  Future<void> setDnsMode(String mode) async {
    await settings.setDnsMode(mode);
    applyDns();
  }

  /// 便捷：换 DNS 服务器并即刻应用。
  Future<void> setDnsServer(String serverId) async {
    await settings.setDnsServer(serverId);
    applyDns();
  }

  /// 便捷：切换 DoH 优先并即刻应用。
  Future<void> setDnsPreferDoh(bool enabled) async {
    await settings.setDnsPreferDoh(enabled);
    applyDns();
  }

  // ── Release 下载加速通道（总开关 / 通道增删选 / 协议同意）───────────────

  /// 便捷：Release 附件是否走加速通道（总开关）。
  Future<void> setReleaseProxyEnabled(bool enabled) =>
      settings.setReleaseProxyEnabled(enabled);

  /// 便捷：选择生效的加速通道。
  Future<void> setReleaseProxySelected(String channelId) =>
      settings.setReleaseProxySelected(channelId);

  /// 便捷：新增 / 更新一个自定义加速通道。
  Future<void> upsertAccelChannel(OgLAccelChannel channel) =>
      settings.upsertAccelChannel(channel);

  /// 便捷：删除一个自定义加速通道（内置通道不可删）。
  Future<void> removeAccelChannel(String channelId) =>
      settings.removeAccelChannel(channelId);

  /// 便捷：记录"已同意当前版本协议"（含时间凭据）。
  Future<void> acceptAccelConsent() => settings.acceptAccelConsent();

  // ── 下载能力（交互层**通过桥取用**，不接触逻辑层的管理器实现）──────────

  /// 下载状态监听（任务增删 / 进度变化）。
  Listenable get downloadsListenable => domain.downloads;

  /// 全部下载任务快照。
  List<IxDownloadTask> get downloadTasks => domain.downloads.tasks;

  /// 清除已完成任务。
  void clearFinishedDownloads() => domain.downloads.clearFinished();

  /// 暂停某个下载。
  Future<void> pauseDownload(String id) => domain.downloads.pause(id);

  /// 继续某个下载。
  Future<void> resumeDownload(String id) => domain.downloads.resume(id);

  /// 重试某个失败下载。
  Future<void> retryDownload(String id) => domain.downloads.retry(id);

  /// 取消某个下载。
  Future<void> cancelDownload(String id) => domain.downloads.cancel(id);

  /// 从列表移除某个下载记录。
  Future<void> removeDownload(String id) => domain.downloads.remove(id);

  /// 设置下载并发连接数（非法档位由 `settings` 回落默认）。
  Future<void> setDownloadConnections(int value) =>
      settings.setDownloadConnections(value);

  /// 切换界面语言：先落盘设置，再加载对应语言分片。
  ///
  /// 非法代码由 `settings.setLanguage` 回落 `zh`；加载失败由 i18n 内部兜底英文。
  Future<void> setLanguage(String code) async {
    await settings.setLanguage(code);
    await OgLI18n.instance.load(settings.settings.languageCode);
  }

  /// 解析明暗：用户偏好优先，`system` 时跟随系统。
  Brightness brightnessFor(Brightness systemBrightness) =>
      switch (settings.settings.mode) {
        OgLThemeMode.light => Brightness.light,
        OgLThemeMode.dark => Brightness.dark,
        OgLThemeMode.system => systemBrightness,
      };

  /// 按当前设置编译主题（全应用唯一的一次编译）。
  ThemeData themeFor(Brightness systemBrightness) {
    final OgLSettings current = settings.settings;
    return buildOgLTheme(
      brightnessFor(systemBrightness),
      seedColor: ogLSeedColorOf(current.seedColorId),
      density: ogLDensityOf(current.density),
    );
  }

  @override
  String toString() =>
      'SurfaceBridge(mode=${settings.settings.mode.name}, '
      'dns=${settings.settings.dnsMode})';
}

/// 用 L1 的 KV 实现设置持久化（**唯一**允许把 L3 的存储需求接到 L1 的地方）。
class KvSettingsPersistence implements OgLSettingsPersistence {
  /// 创建。
  const KvSettingsPersistence(this._kv, {this.key = OgLSettingsController.storageKey});

  final DiskKv _kv;

  /// 存储键。
  final String key;

  @override
  Future<String?> read() => _kv.read(key);

  @override
  Future<void> write(String raw) => _kv.write(key, raw);

  @override
  Future<void> clear() => _kv.remove(key);
}

/// 展示层模块（`surface.layer`）。
///
/// 依赖 `domain.layer`：展示层**永远**通过中枢层拿业务数据，
/// 不允许自己去碰 API。
class SurfaceLayerModule extends OgLModule {
  /// 装配出的桥（[onRegister] 后可用）。
  late final SurfaceBridge bridge;

  /// 设置控制器（UI 根节点监听它来重建主题）。
  late final OgLSettingsController settings;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'surface.layer',
        layer: ModuleLayer.surface,
        version: '0.2.0',
        requires: <String>['domain.layer'],
        provides: <String>['surface.bridge'],
        description: '展示·Material3 页面/主题/设置 的装配入口',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    final BaseBridge base = BaseBridge.of(context.bridges);

    settings = OgLSettingsController(
      persistence: KvSettingsPersistence(base.disk.kv),
    );
    // 设置读取失败也必须让应用起来（load 内部已兜底，这里再包一层是双保险）。
    await settings.load();
    // 把持久化的 DNS 选择应用到网络底座（策略为可变设计，即刻生效）。
    final OgLSettings persisted = settings.settings;
    base.net.applyDnsSelection(
      custom: persisted.dnsMode == 'custom',
      serverId: persisted.dnsServerId,
      preferDoh: persisted.dnsPreferDoh,
    );
    // i18n：按持久化语言加载 JSON 分片（英文基线 + 当前语言）。
    // **失败不阻断启动**：i18n 内部兜底英文/键名。
    await OgLI18n.instance.load(persisted.languageCode);

    bridge = SurfaceBridge(
      settings: settings,
      domain: DomainBridge.of(context.bridges),
      net: base.net,
      cache: base.disk.cache,
      storageProbe: _probeStorage,
    );
    context.bridges.register(ModuleLayer.surface.key, bridge);

    context.diagnostics.info(
      'SURFACE',
      '展示层地基就绪',
      code: 'OGL-SURFACE-001',
      data: <String, Object?>{
        'framework': 'material3',
        'settingsLoaded': settings.isLoaded,
        'settingsError': settings.lastError != null,
      },
    );
  }

  @override
  Future<void> onStart() async {
    // 展示层没有后台任务：它的"启动"就是设置加载完成（上一步已完成）。
  }
}

/// 组装 L3 全部模块（供 `main` 一行接入，与 L1/L2 的装配入口保持同构）。
///
/// **只暴露一个模块**：展示层的所有能力都从 [SurfaceBridge] 出去，
/// 不像 L1/L2 那样需要按子系统拆分——因为 UI 本来就是"一张皮"。
List<OgLModule> surfaceLayerModules() => <OgLModule>[
      SurfaceLayerModule(),
    ];

/// 真实写入探针：能写删应用根目录下的探针文件即视为可用。
Future<bool> _probeStorage() async {
  try {
    final String root = await OgLAppDirs.root();
    final File probe = File('$root/.ogl_probe_ui');
    await probe.writeAsString('ok', flush: true);
    await probe.delete();
    return true;
  } catch (_) {
    return false;
  }
}