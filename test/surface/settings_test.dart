/// 展示层设置的一致性协议检查。
///
/// 关键纪律：
/// 1. 反序列化**永不抛**：坏数据回落默认值；
/// 2. 保存失败**不静默**：内存值仍生效但 lastError 必须可见；
/// 3. 存储键沿用 `ogl.settings`（老配置文件可平滑读取）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/settings.dart';

/// 读取必抛（模拟磁盘故障）。
class _ThrowingReadPersistence implements OgLSettingsPersistence {
  @override
  Future<String?> read() async => throw StateError('磁盘故障');

  @override
  Future<void> write(String raw) async {}

  @override
  Future<void> clear() async {}
}

/// 写入必抛（模拟只读磁盘）。
class _ThrowingWritePersistence implements OgLSettingsPersistence {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String raw) async => throw StateError('只读磁盘');

  @override
  Future<void> clear() async {}
}

void main() {
  group('OgLSettings 容错反序列化', () {
    test('null / 非 Map → 默认值', () {
      expect(OgLSettings.fromJson(null).mode, OgLThemeMode.system);
      expect(OgLSettings.fromJson(42).dnsMode, 'system');
      expect(OgLSettings.fromJson(<Object?>[]).dnsServerId, 'alidns');
    });

    test('坏字段逐个回落（不抛）', () {
      final OgLSettings s = OgLSettings.fromJson(<String, Object?>{
        'mode': 'bogus',
        'dnsMode': 'weird',
        'dnsServerId': 5,
        'dnsPreferDoh': 'x',
      });
      expect(s.mode, OgLThemeMode.system);
      expect(s.dnsMode, 'system');
      expect(s.dnsServerId, 'alidns');
      expect(s.dnsPreferDoh, isTrue);
    });

    test('往返一致', () {
      const OgLSettings s = OgLSettings(
        mode: OgLThemeMode.dark,
        dnsMode: 'custom',
        dnsServerId: 'cloudflare',
        dnsPreferDoh: false,
      );
      final OgLSettings back = OgLSettings.fromJson(s.toJson());
      expect(back.mode, OgLThemeMode.dark);
      expect(back.dnsMode, 'custom');
      expect(back.dnsServerId, 'cloudflare');
      expect(back.dnsPreferDoh, isFalse);
      final OgLSettings encoded =
          OgLSettings.fromJson(jsonDecode(s.encode()));
      expect(encoded.dnsServerId, 'cloudflare');
    });

    test('新增字段：缺失时回落保守默认', () {
      final OgLSettings s = OgLSettings.fromJson(<String, Object?>{
        'mode': 'dark',
      });
      expect(s.seedColorId, 'github');
      expect(s.fontScale, 1.0);
      expect(s.density, 'comfortable');
      expect(s.reduceMotion, isFalse);
      expect(s.foldersFirst, isTrue);
      expect(s.codeHighlight, isTrue);
      expect(s.codeFontSize, 13);
      expect(s.codeWrap, isFalse);
      expect(s.codeThemePreset, 'theme');
      expect(s.codeColorKeyword, 0xFF569CD6);
      expect(s.onboardingDone, isFalse);
    });

    test('新增字段：坏值与越界被修正（不抛）', () {
      final OgLSettings s = OgLSettings.fromJson(<String, Object?>{
        'seedColorId': '',
        'fontScale': 99,
        'density': 'weird',
        'reduceMotion': 'x',
        'foldersFirst': 1,
        'codeHighlight': 'no',
        'codeFontSize': -5,
        'codeWrap': 'x',
        'onboardingDone': 0,
      });
      expect(s.seedColorId, 'github');
      expect(s.fontScale, OgLSettings.maxFontScale);
      expect(s.density, 'comfortable');
      expect(s.reduceMotion, isFalse);
      expect(s.foldersFirst, isTrue);
      expect(s.codeHighlight, isTrue);
      expect(s.codeFontSize, OgLSettings.minCodeFontSize);
      expect(s.codeWrap, isFalse);
      expect(s.onboardingDone, isFalse);
    });

    test('新增字段往返一致', () {
      const OgLSettings s = OgLSettings(
        seedColorId: 'grape',
        fontScale: 1.2,
        density: 'compact',
        reduceMotion: true,
        foldersFirst: false,
        codeHighlight: false,
        codeFontSize: 18,
        codeWrap: true,
        codeThemePreset: 'custom',
        codeColorKeyword: 0xFF112233,
        onboardingDone: true,
      );
      final OgLSettings back = OgLSettings.fromJson(jsonDecode(s.encode()));
      expect(back.seedColorId, 'grape');
      expect(back.fontScale, 1.2);
      expect(back.density, 'compact');
      expect(back.reduceMotion, isTrue);
      expect(back.foldersFirst, isFalse);
      expect(back.codeHighlight, isFalse);
      expect(back.codeFontSize, 18);
      expect(back.codeWrap, isTrue);
      expect(back.codeThemePreset, 'custom');
      expect(back.codeColorKeyword, 0xFF112233);
      expect(back.onboardingDone, isTrue);
    });
  });

  group('OgLSettingsController', () {
    test('加载 → 修改 → 再加载（持久化往返）', () async {
      final OgLInMemorySettingsPersistence store =
          OgLInMemorySettingsPersistence();
      final OgLSettingsController a = OgLSettingsController(persistence: store);
      await a.load();
      expect(a.isLoaded, isTrue);
      await a.setMode(OgLThemeMode.light);

      final OgLSettingsController b = OgLSettingsController(persistence: store);
      await b.load();
      expect(b.settings.mode, OgLThemeMode.light);
      expect(b.lastError, isNull);
    });

    test('读取失败：回落默认并记录原因', () async {
      final OgLSettingsController c =
          OgLSettingsController(persistence: _ThrowingReadPersistence());
      await c.load();
      expect(c.settings.mode, OgLThemeMode.system);
      expect(c.lastError, isNotNull);
    });

    test('保存失败：内存值仍生效，错误必须可见', () async {
      final OgLSettingsController c =
          OgLSettingsController(persistence: _ThrowingWritePersistence());
      await c.load();
      await c.setDnsMode('custom');
      expect(c.settings.dnsMode, 'custom', reason: '本次点击必须立刻生效');
      expect(c.lastError, isNotNull, reason: '保存失败不许静默');
    });

    test('重置：回到默认值', () async {
      final OgLSettingsController c = OgLSettingsController();
      await c.load();
      await c.setMode(OgLThemeMode.dark);
      await c.reset();
      expect(c.settings.mode, OgLThemeMode.system);
    });
  });
}