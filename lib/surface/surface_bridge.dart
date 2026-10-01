/// L3 展示级 · 表面桥（Surface Bridge）与装配根。
///
/// ## 分层纪律
/// 本文件是**展示层的装配根**，和 `DomainLayerModule` 同级，因此它可以跨层
/// import 底座桥（就像中枢层那样）。除此之外，
/// **所有页面与控件一律只通过 [SurfaceBridge] 取用**，不得直接 import base/domain。
///
/// ## 它把三件事接到一起
/// 1. **设置落盘**：`OgLSettingsController` ↔ L1 的 KV（`base.disk.kv`）；
/// 2. **环境事实**：`MediaQueryData`（DPI / 安全区 / 文字缩放 / 窗口尺寸）
///    + 平台 → `OgLViewport` → `OgLLayoutSpec`；
/// 3. **主题编译**：设置 + 视口 → `ThemeData`（全应用唯一的一次编译）。
///
/// 三件事都在这里收口，页面里就不会再出现 `MediaQuery.of(context).size.width > 600`
/// 这类散落的判断。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../base/base_bridge.dart';
import '../base/disk/disk_store.dart';
import '../domain/domain_bridge.dart';
import '../kernel/bridge_registry.dart';
import '../kernel/contract/module.dart';
import 'layout/adaptive.dart';
import 'perm/permission_policy.dart';
import 'settings/settings_model.dart';
import 'theme/design_tokens.dart';
import 'theme/theme_pack.dart';

/// 表面桥：展示层对外的唯一入口。
class SurfaceBridge {
  /// 创建桥。
  const SurfaceBridge({
    required this.settings,
    required this.platform,
    required this.domain,
    this.permissionGateway,
  });

  /// 从内核桥表解析（展示层的标准取用方式）。
  static SurfaceBridge of(KernelBridgeRegistry bridges) =>
      bridges.resolve<SurfaceBridge>(ModuleLayer.surface.key);

  /// 设置控制器。
  final OgLSettingsController settings;

  /// 运行平台。
  final OgLPlatformKind platform;

  /// 中枢桥（页面需要业务数据时通过它取）。
  final DomainBridge domain;

  /// 权限网关（平台实现层注入；未注入时权限一律"不可用"而不是"已授权"）。
  final OgLPermissionGateway? permissionGateway;

  /// 权限策略矩阵。
  OgLPermissionPolicy get permissionPolicy =>
      OgLPermissionPolicy.forPlatform(platform);

  /// 采集权限状态；无网关时返回"全部未知"的安全快照。
  Future<OgLPermissionSnapshot> refreshPermissions() async {
    final gateway = permissionGateway;
    if (gateway == null) {
      return OgLPermissionSnapshot.empty(platform);
    }
    try {
      return OgLPermissionSnapshot(
        policy: permissionPolicy,
        statuses: await gateway.snapshot(permissionPolicy),
      );
    } catch (_) {
      // 采集失败 ⇒ 按"未知"处理（绝不猜成已授权），并保持界面可用。
      return OgLPermissionSnapshot.empty(platform);
    }
  }

  /// 由 `MediaQueryData` 解析视口（把系统"减少动态效果"也一并读进来）。
  OgLViewport viewportOf(MediaQueryData query) => OgLViewport.fromMediaQuery(
        query,
        platform: platform,
        reducedMotion: _reducedMotionOf(query),
      );

  /// 当前设置下的实际密度。
  OgLDensity densityFor(OgLViewport viewport) =>
      settings.settings.density.resolve(viewport.suggestedDensity);

  /// 当前设置下的令牌。
  OgLTokens tokensFor(OgLViewport viewport) => OgLTokens.resolve(
        density: densityFor(viewport),
        textScale: viewport.textScale,
        pointer: viewport.pointer,
        hairline: viewport.hairline,
        reducedMotion: _reducedMotionOf(null, fallback: viewport.reducedMotion),
      );

  /// 当前设置下的主题包。
  OgLThemePack themePack() {
    final id = settings.settings.themeId;
    return id.isEmpty ? OgLThemePacks.fallback : OgLThemePacks.byId(id);
  }

  /// 解析明暗：用户偏好优先，`system` 时跟随系统。
  OgLBrightness brightnessFor(Brightness systemBrightness) =>
      switch (settings.settings.mode) {
        OgLThemeMode.light => OgLBrightness.light,
        OgLThemeMode.dark => OgLBrightness.dark,
        OgLThemeMode.system => systemBrightness == Brightness.dark
            ? OgLBrightness.dark
            : OgLBrightness.light,
      };

  /// 编译出当前应使用的 [ThemeData]。
  ThemeData themeFor({
    required MediaQueryData query,
    required Brightness systemBrightness,
  }) {
    final viewport = viewportOf(query);
    final pack = themePack();
    return buildOgLTheme(
      pack: pack,
      brightness: brightnessFor(systemBrightness),
      tokens: tokensFor(viewport),
      layout: viewport.spec,
      motion: settings.settings.motion.resolve(
        systemReduced: _reducedMotionOf(query),
      ),
    );
  }

  /// 图标包（设置为空 ⇒ 主题包自带的默认图标包）。
  String effectiveIconSetId() {
    final explicit = settings.settings.iconSetId;
    if (explicit.isNotEmpty) {
      return explicit;
    }
    return themePack().iconSetId;
  }

  /// 平台探测。
  static OgLPlatformKind detectPlatform({
    TargetPlatform? target,
    bool isWeb = kIsWeb,
  }) {
    if (isWeb) {
      return OgLPlatformKind.web;
    }
    switch (target ?? defaultTargetPlatform) {
      case TargetPlatform.android:
        return OgLPlatformKind.android;
      case TargetPlatform.iOS:
        return OgLPlatformKind.iOS;
      case TargetPlatform.windows:
        return OgLPlatformKind.windows;
      case TargetPlatform.linux:
        return OgLPlatformKind.linux;
      case TargetPlatform.macOS:
        return OgLPlatformKind.macOS;
      case TargetPlatform.fuchsia:
        return OgLPlatformKind.other;
    }
  }

  static bool _reducedMotionOf(MediaQueryData? query, {bool fallback = false}) {
    if (query == null) {
      return fallback;
    }
    // Flutter 的无障碍开关；旧版本没有该字段时读到 null，按"未开启"处理。
    return query.disableAnimations;
  }

  @override
  String toString() => 'SurfaceBridge(${platform.name}, '
      'theme=${settings.settings.themeId.isEmpty ? '默认' : settings.settings.themeId}, '
      '权限网关=${permissionGateway == null ? '未注入' : '已注入'})';
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
  /// 创建模块。
  SurfaceLayerModule({this.gateway, this.platform});

  /// 权限网关（由平台实现层注入）。
  final OgLPermissionGateway? gateway;

  /// 平台覆盖（测试 / 桌面端可显式指定）。
  final OgLPlatformKind? platform;

  /// 装配出的桥（[onRegister] 后可用）。
  late final SurfaceBridge bridge;

  /// 设置控制器（UI 根节点监听它来重建主题）。
  late final OgLSettingsController settings;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'surface.layer',
        layer: ModuleLayer.surface,
        version: '0.1.0',
        requires: <String>['domain.layer'],
        provides: <String>['surface.bridge'],
        description: '展示·布局/主题/图标/权限/设置 的装配与编译入口',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    final base = BaseBridge.of(context.bridges);
    final platformKind = platform ?? SurfaceBridge.detectPlatform();

    settings = OgLSettingsController(
      persistence: KvSettingsPersistence(base.disk.kv),
    );
    // 设置读取失败也必须让应用起来（load 内部已兜底，这里再包一层是双保险）。
    await settings.load();

    bridge = SurfaceBridge(
      settings: settings,
      platform: platformKind,
      domain: DomainBridge.of(context.bridges),
      permissionGateway: gateway,
    );
    context.bridges.register(ModuleLayer.surface.key, bridge);

    context.diagnostics.info(
      'SURFACE',
      '展示层地基就绪',
      code: 'OGL-SURFACE-001',
      data: <String, Object?>{
        'platform': platformKind.name,
        'themePacks': OgLThemePacks.all.length,
        'iconSets': OgLIconSets.all.length,
        'permissionRules': bridge.permissionPolicy.rules.length,
        'settingsLoaded': settings.isLoaded,
        'settingsError': settings.lastError != null,
      },
    );
  }

  @override
  Future<void> onStart() async {
    // 展示层没有后台任务：它的"启动"就是主题编译完成（上一步已完成）。
  }
}