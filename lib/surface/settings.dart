/// L3 展示级 · 设置（外观 / 代码与文件 / 网络 → 真实行为）。
///
/// ## 只留"真选项"
/// 每个字段都必须接到真实行为上，否则就是"假选项"（比没有选项更糟）：
/// - 外观：`mode` / `seedColorId` / `fontScale` / `density` / `reduceMotion`
///   → 直接决定 `ThemeData`、文字缩放与动效；
/// - 代码与文件：`codeHighlight` / `codeFontSize` / `codeWrap` / `foldersFirst`
///   → 直接作用于仓库代码查看器与目录排序；
/// - 网络：`dnsMode` / `dnsServerId` / `dnsPreferDoh` → 即时作用到底座网络；
/// - 引导：`onboardingDone` → 是否展示首次权限引导。
///
/// ## 两条纪律
/// - 反序列化**永不抛异常**：坏字段回落默认值，数值越界一律夹紧
///   （用户手改配置文件不会炸应用）；
/// - 存储键沿用 `ogl.settings`：老配置文件可平滑读取（多余字段被忽略，
///   缺失的新字段回落**等于旧行为**的保守默认值）。
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 明暗模式偏好。
enum OgLThemeMode {
  /// 跟随系统。
  system,

  /// 强制亮色。
  light,

  /// 强制暗色。
  dark;

  /// 解析（坏值回落 [OgLThemeMode.system]）。
  static OgLThemeMode parse(Object? raw) {
    if (raw is String) {
      for (final OgLThemeMode value in values) {
        if (value.name == raw) {
          return value;
        }
      }
    }
    return system;
  }
}

/// 用户设置（不可变；容错反序列化）。
///
/// 新增字段一律给**保守默认值**（等于旧行为），保证老配置文件升级后
/// 不会因为"新字段缺失"而改变用户已有的体验。
@immutable
class OgLSettings {
  /// 创建设置。
  const OgLSettings({
    this.mode = OgLThemeMode.system,
    this.seedColorId = 'github',
    this.fontScale = 1.0,
    this.density = 'comfortable',
    this.reduceMotion = false,
    this.dnsMode = 'system',
    this.dnsServerId = 'alidns',
    this.dnsPreferDoh = true,
    this.foldersFirst = true,
    this.codeHighlight = true,
    this.codeFontSize = 13,
    this.codeWrap = false,
    this.onboardingDone = false,
  });

  /// 默认值。
  static const OgLSettings defaults = OgLSettings();

  /// 字号缩放上下限（与 `og_l_app` 的文字缩放夹紧一致）。
  static const double minFontScale = 0.8;
  static const double maxFontScale = 1.6;

  /// 代码字号上下限。
  static const double minCodeFontSize = 10;
  static const double maxCodeFontSize = 22;

  /// 由 JSON 构造（**永不抛**：坏数据回落默认）。
  factory OgLSettings.fromJson(Object? raw) {
    if (raw is! Map) {
      return defaults;
    }
    final Object? serverId = raw['dnsServerId'];
    final Object? seed = raw['seedColorId'];
    return OgLSettings(
      mode: OgLThemeMode.parse(raw['mode']),
      seedColorId: seed is String && seed.isNotEmpty ? seed : 'github',
      fontScale: _clampDouble(
        raw['fontScale'],
        fallback: 1.0,
        min: minFontScale,
        max: maxFontScale,
      ),
      density: raw['density'] == 'compact' ? 'compact' : 'comfortable',
      reduceMotion: _asBool(raw['reduceMotion'], fallback: false),
      dnsMode: raw['dnsMode'] == 'custom' ? 'custom' : 'system',
      dnsServerId:
          serverId is String && serverId.isNotEmpty ? serverId : 'alidns',
      dnsPreferDoh: _asBool(raw['dnsPreferDoh'], fallback: true),
      foldersFirst: _asBool(raw['foldersFirst'], fallback: true),
      codeHighlight: _asBool(raw['codeHighlight'], fallback: true),
      codeFontSize: _clampDouble(
        raw['codeFontSize'],
        fallback: 13,
        min: minCodeFontSize,
        max: maxCodeFontSize,
      ),
      codeWrap: _asBool(raw['codeWrap'], fallback: false),
      onboardingDone: _asBool(raw['onboardingDone'], fallback: false),
    );
  }

  static bool _asBool(Object? value, {required bool fallback}) =>
      value is bool ? value : fallback;

  static double _clampDouble(
    Object? value, {
    required double fallback,
    required double min,
    required double max,
  }) {
    if (value is! num) {
      return fallback;
    }
    final double v = value.toDouble();
    if (v.isNaN) {
      return fallback;
    }
    return v.clamp(min, max).toDouble();
  }

  /// 明暗模式。
  final OgLThemeMode mode;

  /// 主题种子色 id（映射见展示层 `theme.dart`）。
  final String seedColorId;

  /// 全局文字缩放（相对系统字号的额外倍数）。
  final double fontScale;

  /// 界面密度（`comfortable` / `compact`）。
  final String density;

  /// 是否减少动效（无障碍）。
  final bool reduceMotion;

  /// DNS 解析模式（`system` / `custom`）。
  final String dnsMode;

  /// 自定义模式下的内置 DNS 服务器 id。
  final String dnsServerId;

  /// 是否优先 DoH（加密解析）。
  final bool dnsPreferDoh;

  /// 仓库浏览器是否**目录优先**。
  final bool foldersFirst;

  /// 代码查看是否启用语法高亮。
  final bool codeHighlight;

  /// 代码字号。
  final double codeFontSize;

  /// 代码是否自动换行。
  final bool codeWrap;

  /// 是否已完成首次引导（含权限说明）。
  final bool onboardingDone;

  /// 复制并覆盖部分字段。
  OgLSettings copyWith({
    OgLThemeMode? mode,
    String? seedColorId,
    double? fontScale,
    String? density,
    bool? reduceMotion,
    String? dnsMode,
    String? dnsServerId,
    bool? dnsPreferDoh,
    bool? foldersFirst,
    bool? codeHighlight,
    double? codeFontSize,
    bool? codeWrap,
    bool? onboardingDone,
  }) =>
      OgLSettings(
        mode: mode ?? this.mode,
        seedColorId: seedColorId ?? this.seedColorId,
        fontScale: fontScale ?? this.fontScale,
        density: density ?? this.density,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        dnsMode: dnsMode ?? this.dnsMode,
        dnsServerId: dnsServerId ?? this.dnsServerId,
        dnsPreferDoh: dnsPreferDoh ?? this.dnsPreferDoh,
        foldersFirst: foldersFirst ?? this.foldersFirst,
        codeHighlight: codeHighlight ?? this.codeHighlight,
        codeFontSize: codeFontSize ?? this.codeFontSize,
        codeWrap: codeWrap ?? this.codeWrap,
        onboardingDone: onboardingDone ?? this.onboardingDone,
      );

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.name,
        'seedColorId': seedColorId,
        'fontScale': fontScale,
        'density': density,
        'reduceMotion': reduceMotion,
        'dnsMode': dnsMode,
        'dnsServerId': dnsServerId,
        'dnsPreferDoh': dnsPreferDoh,
        'foldersFirst': foldersFirst,
        'codeHighlight': codeHighlight,
        'codeFontSize': codeFontSize,
        'codeWrap': codeWrap,
        'onboardingDone': onboardingDone,
      };

  /// 编码为 JSON 文本。
  String encode() => jsonEncode(toJson());
}

/// 设置持久化接口（由表面桥用底座 KV 实现；展示层不直接依赖底座）。
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
  OgLSettingsController({OgLSettingsPersistence? persistence})
      : _persistence = persistence ?? OgLInMemorySettingsPersistence();

  /// 存储键（由表面桥绑定到底座 KV）。
  static const String storageKey = 'ogl.settings';

  final OgLSettingsPersistence _persistence;

  OgLSettings _settings = OgLSettings.defaults;
  String? _lastError;
  bool _loaded = false;

  /// 当前设置。
  OgLSettings get settings => _settings;

  /// 最近一次加载 / 保存错误（**不吞**，UI 可提示）。
  String? get lastError => _lastError;

  /// 是否已完成一次加载。
  bool get isLoaded => _loaded;

  /// 加载（**永不抛**：坏数据回落默认并记录原因）。
  Future<void> load() async {
    try {
      final String? raw = await _persistence.read();
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

  /// 应用一份新设置（**先落盘**；失败保留内存新值并记录，绝不静默）。
  Future<void> apply(OgLSettings next) async {
    _settings = next;
    notifyListeners();
    try {
      await _persistence.write(next.encode());
      _lastError = null;
    } catch (error) {
      _lastError = '设置保存失败（本次改动仍然生效，但重启后会丢失）：$error';
    }
  }

  /// 便捷：切换明暗。
  Future<void> setMode(OgLThemeMode mode) =>
      apply(_settings.copyWith(mode: mode));

  /// 便捷：设置 DNS 解析模式（`system` / `custom`）。
  Future<void> setDnsMode(String mode) =>
      apply(_settings.copyWith(dnsMode: mode == 'custom' ? 'custom' : 'system'));

  /// 便捷：设置自定义模式下的内置 DNS。
  Future<void> setDnsServer(String serverId) =>
      apply(_settings.copyWith(dnsServerId: serverId));

  /// 便捷：设置 DoH 优先。
  Future<void> setDnsPreferDoh(bool enabled) =>
      apply(_settings.copyWith(dnsPreferDoh: enabled));

  /// 便捷：设置主题色。
  Future<void> setSeedColor(String id) =>
      apply(_settings.copyWith(seedColorId: id));

  /// 便捷：设置全局文字缩放。
  Future<void> setFontScale(double scale) => apply(_settings.copyWith(
        fontScale: scale
            .clamp(
              OgLSettings.minFontScale,
              OgLSettings.maxFontScale,
            )
            .toDouble(),
      ));

  /// 便捷：设置界面密度（`comfortable` / `compact`）。
  Future<void> setDensity(String density) => apply(
        _settings.copyWith(
          density: density == 'compact' ? 'compact' : 'comfortable',
        ),
      );

  /// 便捷：设置减少动效。
  Future<void> setReduceMotion(bool enabled) =>
      apply(_settings.copyWith(reduceMotion: enabled));

  /// 便捷：设置目录优先。
  Future<void> setFoldersFirst(bool enabled) =>
      apply(_settings.copyWith(foldersFirst: enabled));

  /// 便捷：设置代码高亮。
  Future<void> setCodeHighlight(bool enabled) =>
      apply(_settings.copyWith(codeHighlight: enabled));

  /// 便捷：设置代码字号。
  Future<void> setCodeFontSize(double size) => apply(_settings.copyWith(
        codeFontSize: size
            .clamp(
              OgLSettings.minCodeFontSize,
              OgLSettings.maxCodeFontSize,
            )
            .toDouble(),
      ));

  /// 便捷：设置代码自动换行。
  Future<void> setCodeWrap(bool enabled) =>
      apply(_settings.copyWith(codeWrap: enabled));

  /// 便捷：标记首次引导已完成。
  Future<void> setOnboardingDone(bool done) =>
      apply(_settings.copyWith(onboardingDone: done));

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