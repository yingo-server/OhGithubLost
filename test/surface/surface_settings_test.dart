/// L3 展示级 · 权限策略 + 设置/开发者选项测试。
///
/// 这两个模块的共同职责是"**替用户把住门**"，所以测试重点不是"能不能跑通"，
/// 而是把几条不可违背的约定钉死：
/// 1. 每一条权限都必须说清"失去它会怎样"（不允许"点了没反应"）；
/// 2. **没有任何权限是核心流程的硬阻塞**（主功能永远可用）；
/// 3. 未知情报一律按"没有"处理（状态未知≠已授权、未知平台≠需要权限）；
/// 4. **手改配置文件也不能把应用置于危险状态**（开发者开关受总闸控制）。
library;

import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/layout/adaptive.dart';
import 'package:ohgithublost/surface/perm/permission_policy.dart';
import 'package:ohgithublost/surface/settings/settings_model.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';

/// 读取必抛的持久化（模拟磁盘故障）。
class _ThrowingReadPersistence implements OgLSettingsPersistence {
  @override
  Future<String?> read() async => throw StateError('磁盘读取失败（模拟）');

  @override
  Future<void> write(String raw) async {}

  @override
  Future<void> clear() async {}
}

/// 写入必抛的持久化（模拟磁盘满）。
class _ThrowingWritePersistence implements OgLSettingsPersistence {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String raw) async => throw StateError('磁盘满（模拟）');

  @override
  Future<void> clear() async => throw StateError('清理失败（模拟）');
}

void main() {
  group('权限策略矩阵', () {
    test('每一条规则都必须写清"失去它会怎样"（不允许点了没反应）', () {
      for (final platform in OgLPlatformKind.values) {
        final policy = OgLPermissionPolicy.forPlatform(platform);
        for (final rule in policy.rules) {
          expect(
            rule.consequence.trim(),
            isNotEmpty,
            reason: '${platform.name}/${rule.permission.name} 缺少后果说明',
          );
        }
      }
    });

    test('核心流程永不被权限硬阻塞（没有任何 block 规则）', () {
      for (final platform in OgLPlatformKind.values) {
        final policy = OgLPermissionPolicy.forPlatform(platform);
        expect(
          policy.rules.every(
            (OgLPermissionRule r) => r.denyBehavior == OgLDenyBehavior.degrade,
          ),
          isTrue,
          reason: '${platform.name} 上有权限会阻塞主功能——浏览公开仓库必须始终可用',
        );
      }
    });

    test('同一平台上权限项不重复（重复会让 UI 出现两行同一开关）', () {
      for (final platform in OgLPlatformKind.values) {
        final policy = OgLPermissionPolicy.forPlatform(platform);
        final seen = policy.rules.map((OgLPermissionRule r) => r.permission);
        expect(seen.toSet().length, policy.rules.length);
      }
    });

    test('未知平台：不假装知道，一律"不需要"', () {
      for (final platform in <OgLPlatformKind>[
        OgLPlatformKind.web,
        OgLPlatformKind.other,
      ]) {
        final policy = OgLPermissionPolicy.forPlatform(platform);
        expect(policy.rules, isEmpty);
        expect(policy.promptable, isEmpty);
        for (final permission in OgLPermission.values) {
          expect(
            policy.ruleFor(permission).askKind,
            OgLAskKind.notRequired,
            reason: '未知平台绝不能凭空索要权限',
          );
        }
      }
    });

    test('矩阵里没有的权限项 ⇒ 视为"不需要"而不是"需要"', () {
      // Windows 上没有"相册"这个概念。
      final policy = OgLPermissionPolicy.forPlatform(OgLPlatformKind.windows);
      final rule = policy.ruleFor(OgLPermission.photos);
      expect(rule.askKind, OgLAskKind.notRequired);
      expect(rule.needsPrompt, isFalse);
    });

    test('系统选择器类权限不弹窗（能靠系统 UI 解决就不该要权限）', () {
      final policy = OgLPermissionPolicy.forPlatform(OgLPlatformKind.iOS);
      final fileRule = policy.ruleFor(OgLPermission.fileSystem);
      expect(fileRule.askKind, OgLAskKind.systemPicker);
      expect(fileRule.needsPrompt, isFalse);
    });

    test('需要引导去系统设置的规则，必须给出具体路径', () {
      for (final platform in OgLPlatformKind.values) {
        final policy = OgLPermissionPolicy.forPlatform(platform);
        for (final rule in policy.rules) {
          if (rule.askKind == OgLAskKind.systemSettingsOnly) {
            expect(
              rule.settingsHint,
              isNotNull,
              reason: '${platform.name}/${rule.permission.name} 说要"去设置里开"却没给路径',
            );
          }
        }
      }
    });
  });

  group('权限状态快照', () {
    final policy = OgLPermissionPolicy.forPlatform(OgLPlatformKind.android);

    test('状态未知时按"不可用"处理，绝不能当"已授权"', () {
      final snapshot = OgLPermissionSnapshot.empty(OgLPlatformKind.android);
      expect(
        snapshot.statusOf(OgLPermission.camera),
        OgLPermissionStatus.denied,
      );
      expect(snapshot.isUsable(OgLPermission.camera), isFalse);
      expect(snapshot.isUsable(OgLPermission.biometric), isFalse);
    });

    test('授权后可用；部分授权（limited）也算可用', () {
      var snapshot = OgLPermissionSnapshot.empty(OgLPlatformKind.android)
          .withStatus(OgLPermission.photos, OgLPermissionStatus.granted)
          .withStatus(OgLPermission.camera, OgLPermissionStatus.limited);
      expect(snapshot.isUsable(OgLPermission.photos), isTrue);
      expect(snapshot.isUsable(OgLPermission.camera), isTrue);
      snapshot = snapshot.withStatus(
        OgLPermission.photos,
        OgLPermissionStatus.permanentlyDenied,
      );
      expect(snapshot.isUsable(OgLPermission.photos), isFalse);
      expect(snapshot.needsSettingsTrip(OgLPermission.photos), isTrue);
    });

    test('已授权不再询问；被拒才询问', () {
      final granted = OgLPermissionSnapshot.empty(OgLPlatformKind.android)
          .withStatus(OgLPermission.notifications, OgLPermissionStatus.granted);
      expect(granted.shouldPrompt(OgLPermission.notifications), isFalse);

      final denied = granted.withStatus(
        OgLPermission.notifications,
        OgLPermissionStatus.denied,
      );
      expect(denied.shouldPrompt(OgLPermission.notifications), isTrue);

      // 需要系统选择器的项，即使"拒绝"也不该弹自家弹窗。
      expect(denied.shouldPrompt(OgLPermission.camera), isFalse);
    });

    test('后果文案直接从策略取（避免每个页面自己编）', () {
      final snapshot = OgLPermissionSnapshot.empty(OgLPlatformKind.android);
      expect(
        snapshot.consequenceText(OgLPermission.notifications),
        policy.ruleFor(OgLPermission.notifications).consequence,
      );
    });

    test('withStatus 不污染其它项', () {
      final snapshot = OgLPermissionSnapshot.empty(OgLPlatformKind.android)
          .withStatus(OgLPermission.camera, OgLPermissionStatus.granted);
      expect(snapshot.statusOf(OgLPermission.photos), OgLPermissionStatus.denied);
      expect(snapshot.statuses.length, 1);
    });
  });

  group('设置：默认值必须是最保守的那一档', () {
    test('默认每次批量都询问、通道为"每次问"、开发者模式关闭', () {
      const settings = OgLSettings.defaults;
      expect(settings.batchConfirmAlways, isTrue);
      expect(settings.writeChannel, OgLWriteChannelChoice.ask);
      expect(settings.developerMode, isFalse);
      expect(settings.dev, OgLDevOptions.none);
      expect(settings.dev.activeDangerous, isEmpty);
    });

    test('密度/动效默认"跟随设备与系统"', () {
      expect(OgLSettings.defaults.density, OgLDensityChoice.auto);
      expect(OgLSettings.defaults.motion, OgLMotionSetting.auto);
      expect(OgLSettings.defaults.mode, OgLThemeMode.system);
    });
  });

  group('设置护栏：手改配置文件也不能进入危险状态', () {
    test('未开开发者模式时，危险开关被强制拧回关闭', () {
      final hostile = jsonDecode(jsonEncode(<String, Object?>{
        'themeId': 'vscode.geek',
        'developerMode': false,
        'dev': <String, Object?>{
          'skipConfirmations': true,
          'forceOverwriteDefault': true,
        },
      })) as Map<String, dynamic>;

      final settings = OgLSettings.fromJson(hostile);
      expect(settings.dev, OgLDevOptions.none);
      expect(settings.dev.activeDangerous, isEmpty);
      expect(settings.lastRepairs, isNotEmpty, reason: '修正过什么必须留痕，不能静默');
    });

    test('开了开发者模式才允许生效', () {
      final allowed = OgLSettings.fromJson(jsonDecode(jsonEncode(<String, Object?>{
        'developerMode': true,
        'dev': <String, Object?>{'skipConfirmations': true},
      })));
      expect(allowed.dev.skipConfirmations, isTrue);
      expect(allowed.dev.activeDangerous, <OgLDevFlag>[
        OgLDevFlag.skipConfirmations,
      ]);
    });

    test('关掉开发者总闸会连带清空所有开关（避免"看着关了其实还开着"）', () async {
      final controller = OgLSettingsController();
      await controller.setDeveloperMode(true);
      await controller.setDevFlag(OgLDevFlag.skipConfirmations, true);
      expect(controller.settings.dev.skipConfirmations, isTrue);

      await controller.setDeveloperMode(false);
      expect(controller.settings.dev, OgLDevOptions.none);
    });

    test('未开总闸时设置开关不生效（而不是偷偷生效）', () {
      const settings = OgLSettings.defaults;
      final attempted = settings.withDevFlag(OgLDevFlag.skipConfirmations, true);
      expect(attempted.dev.skipConfirmations, isFalse);
    });

    test('数值项被夹紧到合法区间', () {
      final tooSmall = OgLSettings.fromJson(<String, dynamic>{
        'cacheMaxEntries': 0,
        'cacheTtlDays': -5,
      });
      expect(tooSmall.cacheMaxEntries, OgLSettings.minCacheEntries);
      expect(tooSmall.cacheTtlDays, 0);

      final tooLarge = OgLSettings.fromJson(<String, dynamic>{
        'cacheMaxEntries': 99999999,
        'cacheTtlDays': 999999,
      });
      expect(tooLarge.cacheMaxEntries, OgLSettings.maxCacheEntries);
      expect(tooLarge.cacheTtlDays, OgLSettings.maxCacheTtlDays);
    });

    test('未知主题 / 图标 ID 被清空回落（脏 ID 不能一路带到渲染层）', () {
      final settings = OgLSettings.fromJson(<String, dynamic>{
        'themeId': 'my-self-made-theme',
        'iconSetId': '不存在的图标包',
      });
      expect(settings.themeId, isEmpty);
      expect(settings.iconSetId, isEmpty);
      expect(settings.lastRepairs.length, greaterThanOrEqualTo(2));
    });

    test('合法 ID 原样保留（护栏不能误伤正常值）', () {
      final settings = OgLSettings.fromJson(<String, dynamic>{
        'themeId': 'winui3',
        'iconSetId': 'material.filled',
      });
      expect(settings.themeId, 'winui3');
      expect(settings.iconSetId, 'material.filled');
      expect(settings.lastRepairs, isEmpty);
    });
  });

  group('设置反序列化：永不抛', () {
    test('非法枚举名回落默认', () {
      final settings = OgLSettings.fromJson(<String, dynamic>{
        'mode': 'rainbow',
        'density': '巨大',
        'motion': '',
        'writeChannel': 'teleport',
      });
      expect(settings.mode, OgLThemeMode.system);
      expect(settings.density, OgLDensityChoice.auto);
      expect(settings.motion, OgLMotionSetting.auto);
      expect(settings.writeChannel, OgLWriteChannelChoice.ask);
    });

    test('错误类型回落默认且不抛', () {
      final settings = OgLSettings.fromJson(<String, dynamic>{
        'themeId': 12345,
        'cacheMaxEntries': 'many',
        'batchConfirmAlways': 'yes',
        'acknowledgedWarnings': <Object?>['ok', 42, null],
      });
      expect(settings.themeId, isEmpty);
      expect(settings.cacheMaxEntries, OgLSettings.defaults.cacheMaxEntries);
      expect(settings.batchConfirmAlways, isTrue);
      expect(settings.acknowledgedWarnings, <String>{'ok'});
    });

    test('模糊：随机垃圾输入不得抛异常', () {
      final random = Random(20261001);
      final samples = <Object?>[
        null,
        'raw string',
        42,
        <int>[1, 2, 3],
        <String, dynamic>{},
        <String, dynamic>{'dev': 'not a map'},
        <String, dynamic>{'dev': <int>[1, 2]},
      ];
      for (final sample in samples) {
        expect(() => OgLSettings.fromJson(sample), returnsNormally);
      }
      for (var round = 0; round < 200; round++) {
        final map = <String, dynamic>{
          'mode': random.nextInt(100),
          'cacheMaxEntries': random.nextInt(1000000) - 500000,
          'dev': <String, dynamic>{'skipConfirmations': random.nextBool()},
          'acknowledgedWarnings': random.nextBool() ? 'oops' : <Object?>[],
        };
        expect(() => OgLSettings.fromJson(map), returnsNormally);
      }
    });

    test('编码—解码往返恒等', () {
      const settings = OgLSettings(
        themeId: 'winui3',
        mode: OgLThemeMode.dark,
        density: OgLDensityChoice.compact,
        iconSetId: 'minimal.line',
        motion: OgLMotionSetting.subtle,
        cacheMaxEntries: 1024,
        cacheTtlDays: 7,
        batchConfirmAlways: false,
        writeChannel: OgLWriteChannelChoice.mirror,
        developerMode: true,
        dev: OgLDevOptions(verboseDiagnostics: true),
        acknowledgedWarnings: <String>{'OGL-MOD-001'},
      );
      final restored = OgLSettings.fromJson(jsonDecode(settings.encode()));
      expect(restored.encode(), settings.encode());
    });
  });

  group('设置控制器：既不吞错，也不丢用户操作', () {
    test('保存成功 ⇒ 可被读到', () async {
      final persistence = OgLInMemorySettingsPersistence();
      final controller = OgLSettingsController(persistence: persistence);
      await controller.load();
      expect(controller.isLoaded, isTrue);

      await controller.setTheme('winui3');
      await controller.setIconSet('material.filled');

      final reloaded = OgLSettingsController(persistence: persistence);
      await reloaded.load();
      expect(reloaded.settings.themeId, 'winui3');
      expect(reloaded.settings.iconSetId, 'material.filled');
    });

    test('读取失败 ⇒ 回落默认并上报错误（绝不抛）', () async {
      final controller = OgLSettingsController(
        persistence: _ThrowingReadPersistence(),
      );
      await controller.load();
      expect(controller.settings, OgLSettings.defaults);
      expect(controller.lastError, isNotNull);
      expect(controller.isLoaded, isTrue);
    });

    test('保存失败 ⇒ 本次改动仍然生效，但如实告知重启会丢', () async {
      final controller = OgLSettingsController(
        persistence: _ThrowingWritePersistence(),
      );
      await controller.setTheme('material3');
      expect(
        controller.settings.themeId,
        'material3',
        reason: '点了没反应比"提示会丢"更糟',
      );
      expect(controller.lastError, isNotNull);
    });

    test('重置会把持久化也清掉', () async {
      final persistence = OgLInMemorySettingsPersistence();
      final controller = OgLSettingsController(persistence: persistence);
      await controller.setMode(OgLThemeMode.dark);
      await controller.reset();
      expect(controller.settings, OgLSettings.defaults);
      // reset 的语义是"回到出厂"：先写入默认值、再把持久化整条抹掉。
      expect(await persistence.read(), isNull);
      final reloaded = OgLSettingsController(persistence: persistence);
      await reloaded.load();
      expect(reloaded.settings, OgLSettings.defaults);
    });

    test('确认告警只累加、幂等', () async {
      final controller = OgLSettingsController();
      await controller.acknowledgeWarning('OGL-MOD-001');
      await controller.acknowledgeWarning('OGL-MOD-001');
      expect(controller.settings.acknowledgedWarnings, <String>{'OGL-MOD-001'});
    });
  });

  group('偏好解析', () {
    test('密度"自动"按设备形态解析', () {
      expect(
        OgLDensityChoice.auto.resolve(OgLDensity.compact),
        OgLDensity.compact,
      );
      expect(
        OgLDensityChoice.comfortable.resolve(OgLDensity.compact),
        OgLDensity.comfortable,
      );
    });

    test('系统的"减少动态效果"优先于用户偏好', () {
      expect(
        OgLMotionSetting.full.resolve(systemReduced: true),
        OgLMotionPolicy.none,
        reason: '无障碍开关必须凌驾于审美偏好',
      );
      expect(
        OgLMotionSetting.subtle.resolve(systemReduced: false),
        OgLMotionPolicy.subtle,
      );
    });

    test('每个开发者开关都有说明与风险级别', () {
      for (final flag in OgLDevFlag.values) {
        expect(flag.description.trim(), isNotEmpty);
        expect(OgLRisk.values.contains(flag.risk), isTrue);
      }
      expect(OgLDevFlag.skipConfirmations.risk, OgLRisk.dangerous);
      expect(OgLDevFlag.showLayoutBounds.risk, OgLRisk.safe);
    });
  });
}