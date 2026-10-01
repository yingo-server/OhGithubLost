/// L3 展示级 · 设置：用户偏好 + 开发者/测试选项（含安全护栏）。
///
/// ## 三层设置
/// | 层 | 面向谁 | 例子 | 是否可持久化 |
/// | --- | --- | --- | --- |
/// | 外观 | 所有人 | 主题包 / 明暗 / 密度 / 图标包 / 动效 | ✅ |
/// | 行为 | 所有人 | 批量前是否必问、默认通道、缓存上限 | ✅ |
/// | **开发者 / 测试** | 调试者 | 默认强制覆盖、跳过二次确认、模拟弱网 | ✅ **但受护栏限制** |
///
/// ## 安全护栏（本文件存在的核心理由）
/// 危险开关**不允许静默生效**：
/// 1. 任一 [OgLRisk.dangerous] 开关只有在 [OgLSettings.developerMode] 打开时
///    才会被采纳；否则在 [OgLSettings.sanitize] 里被**强制拧回关闭**。
/// 2. 数值项一律**夹紧**到合法区间（缓存条目 / TTL），不接受"手改 JSON"越界。
/// 3. 反序列化**永不抛异常**：坏字段回落默认值，未知枚举回落默认，
///    并把被修正的字段记进 [OgLSettings.lastRepairs] 供诊断页展示。
///
/// 换句话说：用户手改配置文件也**不能**把应用置于"会覆盖别人代码"的状态。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 明暗模式偏好。
enum OgLThemeMode {
  /// 跟随系统。
  system,

  /// 强制亮色。
  light,

  /// 强制暗色。
  dark;

  /// 解析（坏值回落 [OgLThemeMode.system]）。
  static OgLThemeMode parse(Object? raw) => _byName(values, raw) ?? system;
}

/// 密度偏好（含"自动"）。
enum OgLDensityChoice {
  /// 跟随设备形态（桌面紧凑 / 手机标准 / 大屏宽松）。
  auto,
  compact,
  standard,
  comfortable;

  /// 解析。
  static OgLDensityChoice parse(Object? raw) =>
      _byName(values, raw) ?? OgLDensityChoice.auto;

  /// 解析为具体密度。
  OgLDensity resolve(OgLDensity fallback) => switch (this) {
        OgLDensityChoice.auto => fallback,
        OgLDensityChoice.compact => OgLDensity.compact,
        OgLDensityChoice.standard => OgLDensity.standard,
        OgLDensityChoice.comfortable => OgLDensity.comfortable,
      };
}

/// 动效偏好（含"跟随系统"）。
enum OgLMotionSetting {
  /// 跟随系统无障碍开关。
  auto,
  full,
  subtle,
  none;

  /// 解析。
  static OgLMotionSetting parse(Object? raw) =>
      _byName(values, raw) ?? OgLMotionSetting.auto;

  /// 解析为具体策略（[systemReduced] 为系统"减少动态效果"）。
  OgLMotionPolicy resolve({required bool systemReduced}) {
    if (systemReduced) {
      return OgLMotionPolicy.none;
    }
    return switch (this) {
      OgLMotionSetting.auto => OgLMotionPolicy.full,
      OgLMotionSetting.full => OgLMotionPolicy.full,
      OgLMotionSetting.subtle => OgLMotionPolicy.subtle,
      OgLMotionSetting.none => OgLMotionPolicy.none,
    };
  }
}

/// 批量写入的默认通道偏好（**每次仍会询问，除非用户显式勾选"不再问"**）。
///
/// 这里刻意不复用 domain 层的 `IxChannel`：跨层引用会把展示层钉死在中枢层上。
/// 由表面桥负责把本枚举映射成真实的通道决策。
enum OgLWriteChannelChoice {
  /// 每次都问（默认，最安全）。
  ask,

  /// 直连（用户自认为网络无污染）。
  direct,

  /// 自动（镜像优先，失败回落）。
  auto,

  /// 指定镜像通道。
  mirror;

  /// 解析。
  static OgLWriteChannelChoice parse(Object? raw) =>
      _byName(values, raw) ?? OgLWriteChannelChoice.ask;
}

/// 风险级别。
enum OgLRisk {
  /// 无风险。
  safe,

  /// 会改变行为，但不会丢数据。
  caution,

  /// **可能导致覆盖他人提交 / 丢失数据**。
  dangerous,
}

/// 开发者 / 测试开关。
enum OgLDevFlag {
  /// 默认勾选"强制覆盖"。
  forceOverwriteDefault,

  /// 跳过危险操作二次确认（**只应在自建仓库上使用**）。
  skipConfirmations,

  /// 诊断面板显示详细日志。
  verboseDiagnostics,

  /// 模拟弱网（延迟 / 抖动）。
  simulateSlowNetwork,

  /// 显示布局边界（排查自适应问题）。
  showLayoutBounds,

  /// 强制禁用所有镜像通道（验证"直连是否可用"）。
  disableMirrors;

  /// 风险级别。
  OgLRisk get risk => switch (this) {
        OgLDevFlag.forceOverwriteDefault ||
        OgLDevFlag.skipConfirmations =>
          OgLRisk.dangerous,
        OgLDevFlag.simulateSlowNetwork ||
        OgLDevFlag.disableMirrors =>
          OgLRisk.caution,
        OgLDevFlag.verboseDiagnostics || OgLDevFlag.showLayoutBounds =>
          OgLRisk.safe,
      };

  /// 一句话说明（设置页直接展示）。
  String get description => switch (this) {
        OgLDevFlag.forceOverwriteDefault => '新建写入时默认勾选"强制覆盖"',
        OgLDevFlag.skipConfirmations => '跳过删除 / 强推的二次确认（可能覆盖他人提交）',
        OgLDevFlag.verboseDiagnostics => '诊断面板输出详细日志',
        OgLDevFlag.simulateSlowNetwork => '模拟弱网：人为延迟与抖动',
        OgLDevFlag.showLayoutBounds => '给布局加可视边框，排查自适应问题',
        OgLDevFlag.disableMirrors => '禁用全部加速通道，强制直连验证',
      };
}

/// 开发者选项集合。
@immutable
class OgLDevOptions {
  /// 创建选项。
  const OgLDevOptions({
    this.forceOverwriteDefault = false,
    this.skipConfirmations = false,
    this.verboseDiagnostics = false,
    this.simulateSlowNetwork = false,
    this.showLayoutBounds = false,
    this.disableMirrors = false,
  });

  /// 由 JSON 构造（容错）。
  factory OgLDevOptions.fromJson(Object? raw) {
    if (raw is! Map) {
      return const OgLDevOptions();
    }
    bool flag(OgLDevFlag which) => raw[which.name] == true;
    return OgLDevOptions(
      forceOverwriteDefault: flag(OgLDevFlag.forceOverwriteDefault),
      skipConfirmations: flag(OgLDevFlag.skipConfirmations),
      verboseDiagnostics: flag(OgLDevFlag.verboseDiagnostics),
      simulateSlowNetwork: flag(OgLDevFlag.simulateSlowNetwork),
      showLayoutBounds: flag(OgLDevFlag.showLayoutBounds),
      disableMirrors: flag(OgLDevFlag.disableMirrors),
    );
  }

  /// 默认（全关）。
  static const OgLDevOptions none = OgLDevOptions();

  /// 默认强制覆盖。
  final bool forceOverwriteDefault;

  /// 跳过二次确认。
  final bool skipConfirmations;

  /// 详细诊断。
  final bool verboseDiagnostics;

  /// 模拟弱网。
  final bool simulateSlowNetwork;

  /// 显示布局边界。
  final bool showLayoutBounds;

  /// 禁用镜像。
  final bool disableMirrors;

  /// 读取某开关。
  bool isOn(OgLDevFlag flag) => switch (flag) {
        OgLDevFlag.forceOverwriteDefault => forceOverwriteDefault,
        OgLDevFlag.skipConfirmations => skipConfirmations,
        OgLDevFlag.verboseDiagnostics => verboseDiagnostics,
        OgLDevFlag.simulateSlowNetwork => simulateSlowNetwork,
        OgLDevFlag.showLayoutBounds => showLayoutBounds,
        OgLDevFlag.disableMirrors => disableMirrors,
      };

  /// 当前打开的危险开关（设置页需要显著警示）。
  List<OgLDevFlag> get activeDangerous => <OgLDevFlag>[
        for (final flag in OgLDevFlag.values)
          if (flag.risk == OgLRisk.dangerous && isOn(flag)) flag,
      ];

  /// 复制并覆盖单个开关。
  OgLDevOptions withFlag(OgLDevFlag flag, bool value) => OgLDevOptions(
        forceOverwriteDefault: flag == OgLDevFlag.forceOverwriteDefault
            ? value
            : forceOverwriteDefault,
        skipConfirmations:
            flag == OgLDevFlag.skipConfirmations ? value : skipConfirmations,
        verboseDiagnostics:
            flag == OgLDevFlag.verboseDiagnostics ? value : verboseDiagnostics,
        simulateSlowNetwork:
            flag == OgLDevFlag.simulateSlowNetwork ? value : simulateSlowNetwork,
        showLayoutBounds:
            flag == OgLDevFlag.showLayoutBounds ? value : showLayoutBounds,
        disableMirrors:
            flag == OgLDevFlag.disableMirrors ? value : disableMirrors,
      );

  /// 全部关闭。
  OgLDevOptions get cleared => const OgLDevOptions();

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        for (final flag in OgLDevFlag.values) flag.name: isOn(flag),
      };

  @override
  bool operator ==(Object other) =>
      other is OgLDevOptions &&
      other.forceOverwriteDefault == forceOverwriteDefault &&
      other.skipConfirmations == skipConfirmations &&
      other.verboseDiagnostics == verboseDiagnostics &&
      other.simulateSlowNetwork == simulateSlowNetwork &&
      other.showLayoutBounds == showLayoutBounds &&
      other.disableMirrors == disableMirrors;

  @override
  int get hashCode => Object.hash(
        forceOverwriteDefault,
        skipConfirmations,
        verboseDiagnostics,
        simulateSlowNetwork,
        showLayoutBounds,
        disableMirrors,
      );
}

/// 用户设置（不可变值对象）。
@immutable
class OgLSettings {
  /// 创建设置。
  const OgLSettings({
    this.themeId = '',
    this.mode = OgLThemeMode.system,
    this.density = OgLDensityChoice.auto,
    this.iconSetId = '',
    this.motion = OgLMotionSetting.auto,
    this.accentOverride,
    this.cacheMaxEntries = 512,
    this.cacheTtlDays = 30,
    this.batchConfirmAlways = true,
    this.writeChannel = OgLWriteChannelChoice.ask,
    this.localeTag,
    this.developerMode = false,
    this.dev = OgLDevOptions.none,
    this.acknowledgedWarnings = const <String>{},
    this.lastRepairs = const <String>[],
  });

  /// 默认值。
  static const OgLSettings defaults = OgLSettings();

  /// 缓存条目上限（护栏区间）。
  static const int minCacheEntries = 64;

  /// 缓存条目上限上界。
  static const int maxCacheEntries = 8192;

  /// 缓存 TTL 上界（天）。
  static const int maxCacheTtlDays = 3650;

  /// 主题包 ID（空 ⇒ 用默认包）。
  final String themeId;

  /// 明暗模式。
  final OgLThemeMode mode;

  /// 密度偏好。
  final OgLDensityChoice density;

  /// 图标包 ID。
  final String iconSetId;

  /// 动效偏好。
  final OgLMotionSetting motion;

  /// 强调色覆盖（ARGB；`null` ⇒ 用主题包自带）。
  final int? accentOverride;

  /// 缓存条目上限。
  final int cacheMaxEntries;

  /// 缓存 TTL（天；0 表示不过期）。
  final int cacheTtlDays;

  /// 批量操作是否总是询问（**默认 true**，与"批量必须先问用户"的约定一致）。
  final bool batchConfirmAlways;

  /// 默认写入通道。
  final OgLWriteChannelChoice writeChannel;

  /// 语言标签（`null` ⇒ 跟随系统）。
  final String? localeTag;

  /// 开发者模式总开关。
  final bool developerMode;

  /// 开发者选项。
  final OgLDevOptions dev;

  /// 已确认过的告警码（避免每次启动都弹同一个 Mod 告警）。
  final Set<String> acknowledgedWarnings;

  /// 反序列化时被修正过的字段（诊断页展示，**不静默**）。
  final List<String> lastRepairs;

  /// 反序列化（**永不抛**）。
  factory OgLSettings.fromJson(Object? raw) {
    if (raw is! Map) {
      return defaults;
    }
    final repairs = <String>[];

    int intOf(String key, int fallback) {
      final value = raw[key];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      if (value != null) {
        repairs.add('$key: 非法数值已回落默认');
      }
      return fallback;
    }

    String stringOf(String key, String fallback) {
      final value = raw[key];
      if (value is String) {
        return value;
      }
      if (value != null) {
        repairs.add('$key: 非法字符串已回落默认');
      }
      return fallback;
    }

    final acknowledged = <String>{};
    final rawAck = raw['acknowledgedWarnings'];
    if (rawAck is List) {
      for (final item in rawAck) {
        if (item is String) {
          acknowledged.add(item);
        }
      }
    }

    final developerMode = raw['developerMode'] == true;

    final settings = OgLSettings(
      themeId: stringOf('themeId', ''),
      mode: OgLThemeMode.parse(raw['mode']),
      density: OgLDensityChoice.parse(raw['density']),
      iconSetId: stringOf('iconSetId', ''),
      motion: OgLMotionSetting.parse(raw['motion']),
      accentOverride: raw['accentOverride'] is int
          ? raw['accentOverride'] as int
          : null,
      cacheMaxEntries: intOf('cacheMaxEntries', defaults.cacheMaxEntries),
      cacheTtlDays: intOf('cacheTtlDays', defaults.cacheTtlDays),
      batchConfirmAlways: raw['batchConfirmAlways'] != false,
      writeChannel: OgLWriteChannelChoice.parse(raw['writeChannel']),
      localeTag: raw['localeTag'] is String ? raw['localeTag'] as String : null,
      developerMode: developerMode,
      dev: OgLDevOptions.fromJson(raw['dev']),
      acknowledgedWarnings: acknowledged,
    );

    final sanitized = settings.sanitize(repairs: repairs);
    return sanitized.copyWith(lastRepairs: repairs);
  }

  /// 安全护栏：**把不合法 / 不安全的组合拧回安全区**。
  ///
  /// 这是"手改配置文件也不能让应用进入危险状态"的执行点。
  OgLSettings sanitize({List<String>? repairs}) {
    final log = repairs ?? <String>[];
    var next = this;

    if (!developerMode && dev != OgLDevOptions.none) {
      next = next.copyWith(dev: OgLDevOptions.none);
      log.add('dev: 未开启开发者模式，所有开发者开关已强制关闭');
    }

    final clampedEntries = cacheMaxEntries.clamp(minCacheEntries, maxCacheEntries);
    if (clampedEntries != cacheMaxEntries) {
      next = next.copyWith(cacheMaxEntries: clampedEntries);
      log.add('cacheMaxEntries: 已夹紧到 $clampedEntries');
    }

    final clampedTtl = cacheTtlDays.clamp(0, maxCacheTtlDays);
    if (clampedTtl != cacheTtlDays) {
      next = next.copyWith(cacheTtlDays: clampedTtl);
      log.add('cacheTtlDays: 已夹紧到 $clampedTtl');
    }

    // 未知主题 / 图标 ID 归零（回落内置默认），避免脏 ID 一路带到渲染层。
    if (themeId.isNotEmpty && OgLThemePacks.byId(themeId).id != themeId) {
      next = next.copyWith(themeId: '');
      log.add('themeId: 未知主题包，已回落默认');
    }
    if (iconSetId.isNotEmpty && OgLIconSets.byId(iconSetId).id != iconSetId) {
      next = next.copyWith(iconSetId: '');
      log.add('iconSetId: 未知图标包，已回落默认');
    }

    return next;
  }

  /// 复制并覆盖。
  OgLSettings copyWith({
    String? themeId,
    OgLThemeMode? mode,
    OgLDensityChoice? density,
    String? iconSetId,
    OgLMotionSetting? motion,
    int? accentOverride,
    bool clearAccentOverride = false,
    int? cacheMaxEntries,
    int? cacheTtlDays,
    bool? batchConfirmAlways,
    OgLWriteChannelChoice? writeChannel,
    String? localeTag,
    bool? developerMode,
    OgLDevOptions? dev,
    Set<String>? acknowledgedWarnings,
    List<String>? lastRepairs,
  }) =>
      OgLSettings(
        themeId: themeId ?? this.themeId,
        mode: mode ?? this.mode,
        density: density ?? this.density,
        iconSetId: iconSetId ?? this.iconSetId,
        motion: motion ?? this.motion,
        accentOverride: clearAccentOverride
            ? null
            : (accentOverride ?? this.accentOverride),
        cacheMaxEntries: cacheMaxEntries ?? this.cacheMaxEntries,
        cacheTtlDays: cacheTtlDays ?? this.cacheTtlDays,
        batchConfirmAlways: batchConfirmAlways ?? this.batchConfirmAlways,
        writeChannel: writeChannel ?? this.writeChannel,
        localeTag: localeTag ?? this.localeTag,
        developerMode: developerMode ?? this.developerMode,
        dev: dev ?? this.dev,
        acknowledgedWarnings: acknowledgedWarnings ?? this.acknowledgedWarnings,
        lastRepairs: lastRepairs ?? this.lastRepairs,
      );

  /// 应用一个开发者开关（自动套用护栏）。
  OgLSettings withDevFlag(OgLDevFlag flag, bool value) {
    if (!developerMode) {
      // 没开开发者模式：开关**不生效**，但仍如实记录（UI 会提示需先开总闸）。
      return this;
    }
    return copyWith(dev: dev.withFlag(flag, value)).sanitize();
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'themeId': themeId,
        'mode': mode.name,
        'density': density.name,
        'iconSetId': iconSetId,
        'motion': motion.name,
        if (accentOverride != null) 'accentOverride': accentOverride,
        'cacheMaxEntries': cacheMaxEntries,
        'cacheTtlDays': cacheTtlDays,
        'batchConfirmAlways': batchConfirmAlways,
        'writeChannel': writeChannel.name,
        if (localeTag != null) 'localeTag': localeTag,
        'developerMode': developerMode,
        'dev': dev.toJson(),
        'acknowledgedWarnings': acknowledgedWarnings.toList(),
      };

  /// 编码为可持久化字符串。
  String encode() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is OgLSettings && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;

  @override
  String toString() => 'OgLSettings(theme=$themeId, ${mode.name}, '
      '${density.name}, dev=${developerMode ? 'on' : 'off'}, '
      'dangerous=${dev.activeDangerous.length})';
}

/// 设置持久化接口（由表面桥用 L1 的 KV 实现；L3 不直接依赖底座）。
abstract class OgLSettingsPersistence {
  /// 读取原始 JSON（无记录返回 `null`）。
  Future<String?> read();

  /// 写入原始 JSON。
  Future<void> write(String raw);

  /// 清空。
  Future<void> clear();
}

/// 内存实现（测试 / 纯内存模式）。
class OgLInMemorySettingsPersistence implements OgLSettingsPersistence {
  /// 创建。
  OgLInMemorySettingsPersistence([this._raw]);

  String? _raw;

  @override
  Future<String?> read() async => _raw;

  @override
  Future<void> write(String raw) async {
    _raw = raw;
  }

  @override
  Future<void> clear() async {
    _raw = null;
  }
}

/// 设置控制器（UI 唯一读取设置的入口）。
class OgLSettingsController extends ChangeNotifier {
  /// 创建控制器。
  OgLSettingsController({
    OgLSettingsPersistence? persistence,
    OgLSettings initial = OgLSettings.defaults,
    VoidCallback? onChanged,
  })  : _persistence = persistence ?? OgLInMemorySettingsPersistence(),
        _settings = initial,
        _onChanged = onChanged;

  /// 存储键（由表面桥绑定到 L1 KV）。
  static const String storageKey = 'ogl.settings';

  final OgLSettingsPersistence _persistence;
  final VoidCallback? _onChanged;

  OgLSettings _settings;
  String? _lastError;
  bool _loaded = false;

  /// 当前设置。
  OgLSettings get settings => _settings;

  /// 最近一次加载 / 保存错误（**不吞**，UI 可提示）。
  String? get lastError => _lastError;

  /// 是否已完成一次加载。
  bool get isLoaded => _loaded;

  /// 加载（**永不抛**：坏数据回落默认并记录）。
  Future<void> load() async {
    try {
      final raw = await _persistence.read();
      _settings = OgLSettings.fromJson(raw == null ? null : jsonDecode(raw));
      _lastError = null;
    } catch (error) {
      _settings = OgLSettings.defaults;
      _lastError = '设置读取失败，已回落默认：$error';
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  /// 应用一份新设置（**先过护栏，再落盘**）。
  ///
  /// 落盘失败时**保留内存中的新值**并记录错误——
  /// 让用户的这次点击立刻生效，而不是"点了没反应"。
  Future<void> apply(OgLSettings next) async {
    final repairs = <String>[];
    final guarded = next.sanitize(repairs: repairs)
        .copyWith(lastRepairs: repairs);
    _settings = guarded;
    notifyListeners();
    try {
      await _persistence.write(guarded.encode());
      _lastError = null;
    } catch (error) {
      _lastError = '设置保存失败（本次改动仍然生效，但重启后会丢失）：$error';
    }
    _onChanged?.call();
  }

  /// 便捷：切换主题包。
  Future<void> setTheme(String themeId) =>
      apply(_settings.copyWith(themeId: themeId));

  /// 便捷：切换明暗。
  Future<void> setMode(OgLThemeMode mode) =>
      apply(_settings.copyWith(mode: mode));

  /// 便捷：切换图标包。
  Future<void> setIconSet(String iconSetId) =>
      apply(_settings.copyWith(iconSetId: iconSetId));

  /// 便捷：切换密度偏好。
  Future<void> applyDensity(OgLDensityChoice density) =>
      apply(_settings.copyWith(density: density));

  /// 便捷：切换动效偏好。
  Future<void> applyMotion(OgLMotionSetting motion) =>
      apply(_settings.copyWith(motion: motion));

  /// 便捷：切换批量写入通道偏好。
  Future<void> applyWriteChannel(OgLWriteChannelChoice channel) =>
      apply(_settings.copyWith(writeChannel: channel));

  /// 便捷：开发者总闸。
  ///
  /// **关掉总闸会自动清空所有开发者开关**——避免"看起来关了其实还开着"。
  Future<void> setDeveloperMode(bool enabled) => apply(
        _settings.copyWith(
          developerMode: enabled,
          dev: enabled ? _settings.dev : OgLDevOptions.none,
        ),
      );

  /// 便捷：设置开发者开关。
  Future<void> setDevFlag(OgLDevFlag flag, bool value) =>
      apply(_settings.withDevFlag(flag, value));

  /// 便捷：确认某个告警（不再重复弹）。
  Future<void> acknowledgeWarning(String code) => apply(
        _settings.copyWith(
          acknowledgedWarnings: <String>{
            ..._settings.acknowledgedWarnings,
            code,
          },
        ),
      );

  /// 重置为默认（并清空持久化）。
  Future<void> reset() async {
    await apply(OgLSettings.defaults);
    try {
      await _persistence.clear();
    } catch (error) {
      _lastError = '重置失败：$error';
    }
  }
}

/// 按名称解析枚举（坏值返回 `null`，**不抛**）。
T? _byName<T extends Enum>(List<T> values, Object? raw) {
  if (raw is! String) {
    return null;
  }
  for (final value in values) {
    if (value.name == raw) {
      return value;
    }
  }
  return null;
}