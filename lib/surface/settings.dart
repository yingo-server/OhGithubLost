/// L3 展示级 · 设置（保守版：只保留真正影响行为的选项）。
///
/// ## 旧版为什么被砍掉
/// 旧设置模型有 700+ 行：主题包 / 图标包 / 密度 / 动效 / 强调色 / 开发者开关……
/// 其中大多数选项只是"被存起来"，并没有接到任何真实行为上
/// （假选项比没有选项更糟：用户以为改了，实际什么都没发生）。
///
/// 重写后只保留两类**真选项**：
/// 1. 外观：明暗（跟随系统 / 亮 / 暗）——直接决定 `ThemeData`；
/// 2. 网络：DNS 解析模式 / 服务器 / DoH——直接作用到底座网络（即时生效）。
///
/// ## 两条纪律
/// - 反序列化**永不抛异常**：坏字段回落默认值（用户手改配置文件不会炸应用）；
/// - 存储键沿用 `ogl.settings`：老配置文件可平滑读取（多余字段被忽略）。
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
@immutable
class OgLSettings {
  /// 创建设置。
  const OgLSettings({
    this.mode = OgLThemeMode.system,
    this.dnsMode = 'system',
    this.dnsServerId = 'alidns',
    this.dnsPreferDoh = true,
  });

  /// 默认值。
  static const OgLSettings defaults = OgLSettings();

  /// 由 JSON 构造（**永不抛**：坏数据回落默认）。
  factory OgLSettings.fromJson(Object? raw) {
    if (raw is! Map) {
      return defaults;
    }
    final Object? serverId = raw['dnsServerId'];
    return OgLSettings(
      mode: OgLThemeMode.parse(raw['mode']),
      dnsMode: raw['dnsMode'] == 'custom' ? 'custom' : 'system',
      dnsServerId:
          serverId is String && serverId.isNotEmpty ? serverId : 'alidns',
      dnsPreferDoh: raw['dnsPreferDoh'] is bool ? raw['dnsPreferDoh'] as bool : true,
    );
  }

  /// 明暗模式。
  final OgLThemeMode mode;

  /// DNS 解析模式（`system` / `custom`）。
  final String dnsMode;

  /// 自定义模式下的内置 DNS 服务器 id。
  final String dnsServerId;

  /// 是否优先 DoH（加密解析）。
  final bool dnsPreferDoh;

  /// 复制并覆盖部分字段。
  OgLSettings copyWith({
    OgLThemeMode? mode,
    String? dnsMode,
    String? dnsServerId,
    bool? dnsPreferDoh,
  }) =>
      OgLSettings(
        mode: mode ?? this.mode,
        dnsMode: dnsMode ?? this.dnsMode,
        dnsServerId: dnsServerId ?? this.dnsServerId,
        dnsPreferDoh: dnsPreferDoh ?? this.dnsPreferDoh,
      );

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.name,
        'dnsMode': dnsMode,
        'dnsServerId': dnsServerId,
        'dnsPreferDoh': dnsPreferDoh,
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