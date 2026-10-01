/// L3 展示级 · 主题与自适应地基测试。
///
/// 这一层是"所有界面的物理法则"，所以它的测试也必须覆盖
/// **设备形态的整个取值空间**，而不是只测一两个样例：
/// 横竖屏 × 大小屏 × 平板 × 桌面窗口 × 高 DPI × 大字体 × 三套主题 × 三套图标。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/layout/adaptive.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/theme/icon_pack.dart';
import 'package:ohgithublost/surface/theme/theme_pack.dart';

/// 造一个视口。
OgLViewport _viewport({
  required double width,
  double height = 800,
  double dpr = 2,
  double textScale = 1,
  OgLPlatformKind platform = OgLPlatformKind.android,
  OgLPointerKind? pointer,
  double bottomInset = 0,
}) =>
    OgLViewport(
      size: Size(width, height),
      devicePixelRatio: dpr,
      textScale: textScale,
      padding: EdgeInsets.zero,
      viewInsets: EdgeInsets.only(bottom: bottomInset),
      platform: platform,
      pointer: pointer ??
          (platform.isDesktop ? OgLPointerKind.mouse : OgLPointerKind.touch),
    );

void main() {
  group('屏幕尺寸等级（断点必须是硬的）', () {
    test('600 / 840 / 1200 三个断点两侧不串档', () {
      expect(OgLScreenSize.fromWidth(320), OgLScreenSize.compact);
      expect(OgLScreenSize.fromWidth(599.9), OgLScreenSize.compact);
      expect(OgLScreenSize.fromWidth(600), OgLScreenSize.medium);
      expect(OgLScreenSize.fromWidth(839.9), OgLScreenSize.medium);
      expect(OgLScreenSize.fromWidth(840), OgLScreenSize.expanded);
      expect(OgLScreenSize.fromWidth(1199.9), OgLScreenSize.expanded);
      expect(OgLScreenSize.fromWidth(1200), OgLScreenSize.large);
      expect(OgLScreenSize.fromWidth(3840), OgLScreenSize.large);
    });
  });

  group('设备形态：靠物理对角线，而不是逻辑宽度', () {
    test('5.8 寸手机（1080×2340 @2.75）判为手机', () {
      final viewport = _viewport(width: 393, height: 851, dpr: 2.75);
      expect(viewport.diagonalInches, closeTo(5.85, 0.1));
      expect(viewport.formFactor, OgLFormFactor.phone);
    });

    test('10 寸平板（1600×2560 @2）判为平板', () {
      final viewport = _viewport(width: 800, height: 1280, dpr: 2);
      expect(viewport.diagonalInches, closeTo(9.43, 0.1));
      expect(viewport.formFactor, OgLFormFactor.tablet);
    });

    test('同样的逻辑宽度，DPR 不同 ⇒ 形态判定不同（这正是 DPI 必须参与的原因）', () {
      final highDpi = _viewport(width: 800, height: 1280, dpr: 4);
      final lowDpi = _viewport(width: 800, height: 1280, dpr: 1);
      // DPR=4 时物理尺寸只有 DPR=1 的 1/4，自然不该被判成平板。
      expect(highDpi.diagonalInches, lessThan(lowDpi.diagonalInches));
      expect(lowDpi.formFactor, OgLFormFactor.tablet);
      expect(highDpi.formFactor, OgLFormFactor.phone);
    });

    test('桌面平台永远是桌面（不因为外接大屏就变成"电视"以外的东西）', () {
      final viewport = _viewport(
        width: 1440,
        height: 900,
        dpr: 1,
        platform: OgLPlatformKind.windows,
      );
      expect(viewport.formFactor, OgLFormFactor.desktop);
    });
  });

  group('DPI：发丝线永远只占 1 物理像素', () {
    test('各 DPR 下的计算值', () {
      expect(OgLAdaptive.hairlineFor(1), 1);
      expect(OgLAdaptive.hairlineFor(2), 0.5);
      expect(OgLAdaptive.hairlineFor(3), closeTo(0.3333, 0.001));
      expect(OgLAdaptive.hairlineFor(4), 0.25);
      // 异常值不得让线消失。
      expect(OgLAdaptive.hairlineFor(0), greaterThan(0));
      expect(OgLAdaptive.hairlineFor(double.nan), greaterThan(0));
      expect(OgLAdaptive.hairlineFor(100), 0.25);
    });
  });

  group('布局结论：横竖屏 / 平板 / 桌面窗口', () {
    test('手机竖屏：底部栏 + 单栏', () {
      final spec = _viewport(width: 393, height: 851).spec;
      expect(spec.navigation, OgLNavKind.bottomBar);
      expect(spec.panes, OgLPaneLayout.single);
      expect(spec.showNavLabels, isFalse);
    });

    test('手机横屏：侧边窄轨 + 列表详情', () {
      final spec = _viewport(width: 851, height: 393).spec;
      expect(spec.navigation, OgLNavKind.navRail);
      expect(spec.panes, OgLPaneLayout.listDetail);
      expect(spec.isLandscape, isTrue);
    });

    test('12 寸平板横屏：宽轨 + 三栏', () {
      final spec = _viewport(width: 1366, height: 1024, dpr: 2).spec;
      expect(spec.navigation, OgLNavKind.extendedRail);
      expect(spec.showNavLabels, isTrue);
      expect(spec.panes, OgLPaneLayout.threePane);
      expect(spec.navigationWidth, 220);
    });

    test('桌面被拖到 380px 宽：用抽屉而不是底部栏', () {
      final spec = _viewport(
        width: 380,
        height: 700,
        platform: OgLPlatformKind.linux,
      ).spec;
      expect(
        spec.navigation,
        OgLNavKind.drawer,
        reason: '把移动端的底部栏塞进桌面窗口是习惯误用',
      );
      expect(spec.navigationWidth, 0);
    });

    test('桌面 1920：宽轨 + 三栏 + 内容限宽', () {
      final viewport = _viewport(
        width: 1920,
        height: 1080,
        dpr: 1,
        platform: OgLPlatformKind.windows,
      );
      final spec = viewport.spec;
      expect(spec.navigation, OgLNavKind.extendedRail);
      expect(spec.panes, OgLPaneLayout.threePane);
      expect(spec.contentMaxWidth, 1120);
      expect(
        spec.contentWidth(1920),
        1700,
        reason: '导航占掉的宽度必须从可用宽度里扣掉',
      );
    });

    test('单调性：宽度增加时，栏数/列数只增不减（拖窗口不闪）', () {
      var lastPanes = 0;
      var lastColumns = 0;
      for (var width = 320.0; width <= 2000; width += 20) {
        final spec = _viewport(width: width, height: 900).spec;
        expect(spec.panes.paneCount, greaterThanOrEqualTo(lastPanes));
        expect(spec.gridColumns, greaterThanOrEqualTo(lastColumns));
        lastPanes = spec.panes.paneCount;
        lastColumns = spec.gridColumns;
      }
    });

    test('网格列数始终落在 [2, 6]', () {
      for (var width = 200.0; width <= 4000; width += 37) {
        for (final form in OgLFormFactor.values) {
          final columns = OgLAdaptive.gridColumns(
            width: width,
            formFactor: form,
          );
          expect(columns, inInclusiveRange(2, 6));
        }
      }
    });
  });

  group('设计令牌', () {
    test('文字缩放被夹紧在 [0.85, 2.0]', () {
      expect(OgLTokens.resolve(textScale: 3).textScale, 2);
      expect(OgLTokens.resolve(textScale: 0.5).textScale, 0.85);
      expect(OgLTokens.resolve(textScale: 1.3).textScale, 1.3);
    });

    test('触摸设备的最小点击目标永不低于 44（即使选了紧凑）', () {
      for (final density in OgLDensity.values) {
        final tokens = OgLTokens.resolve(
          density: density,
          pointer: OgLPointerKind.touch,
        );
        expect(
          tokens.targetSize,
          greaterThanOrEqualTo(44),
          reason: '可访问性底线，不给"紧凑"让路',
        );
      }
    });

    test('鼠标场景才允许压小目标', () {
      final tokens = OgLTokens.resolve(
        density: OgLDensity.compact,
        pointer: OgLPointerKind.mouse,
      );
      expect(tokens.targetSize, 28);
    });

    test('减少动效 ⇒ 所有时长归零', () {
      final tokens = OgLTokens.resolve(reducedMotion: true);
      expect(tokens.motion(OgLDuration.slower), Duration.zero);
      expect(tokens.motion(OgLDuration.fast), Duration.zero);
    });

    test('紧凑密度让动效更快一档，但不改变瞬时档', () {
      final compact = OgLTokens.resolve(density: OgLDensity.compact);
      expect(compact.motion(OgLDuration.base).inMilliseconds, lessThan(160));
      expect(compact.motion(OgLDuration.fast), OgLDuration.fast);
    });

    test('大字体下建议行数收紧（迫使界面截断而不是溢出）', () {
      expect(OgLTokens.resolve(textScale: 1).maxLinesHint, 3);
      expect(OgLTokens.resolve(textScale: 1.8).maxLinesHint, 2);
    });
  });

  group('图标包：三套 × 全部语义都必须齐全', () {
    test('每一套图标包都能解析每一个语义名', () {
      for (final set in OgLIconSets.all) {
        for (final name in OgLIconName.values) {
          final icon = set.resolve(name);
          expect(
            icon.codePoint,
            greaterThan(0),
            reason: '${set.id} 缺少语义 ${name.name}',
          );
        }
      }
    });

    test('ID 唯一，未知 ID 回落默认包（设置里的脏值不该让界面崩）', () {
      final ids = OgLIconSets.all.map((OgLIconSet s) => s.id).toSet();
      expect(ids.length, OgLIconSets.all.length);
      expect(OgLIconSets.byId('不存在的包').id, OgLIconSets.fallback.id);
      expect(OgLIconSets.byId(null).id, OgLIconSets.fallback.id);
    });
  });

  group('主题包', () {
    test('ID 唯一；未知 ID 回落默认包', () {
      final ids = OgLThemePacks.all.map((OgLThemePack p) => p.id).toSet();
      expect(ids.length, OgLThemePacks.all.length);
      expect(OgLThemePacks.byId('nope').id, OgLThemePacks.fallback.id);
      expect(OgLThemePacks.byId(null).id, OgLThemePacks.fallback.id);
    });

    test('每一套主题包在明暗两种模式下都能给出完整调色板', () {
      for (final pack in OgLThemePacks.all) {
        for (final brightness in OgLBrightness.values) {
          final palette = pack.paletteFor(brightness);
          expect(palette.background.alpha, greaterThan(0));
          expect(
            palette.accent,
            isNot(palette.background),
            reason: '强调色不能等于背景（否则选中态不可见）',
          );
        }
      }
    });

    test('亮暗两套确实是不同的配色（而不是复制粘贴）', () {
      final pack = OgLThemePacks.vscode;
      final light = pack.paletteFor(OgLBrightness.light);
      final dark = pack.paletteFor(OgLBrightness.dark);
      expect(light.background, isNot(dark.background));
      // 亮色底应比暗色底亮。
      expect(
        light.background.computeLuminance(),
        greaterThan(dark.background.computeLuminance()),
      );
    });

    test('编译出的 ThemeData 带上我们的扩展，且分割线是发丝线', () {
      final tokens = OgLTokens.resolve(hairline: 1 / 3);
      final theme = buildOgLTheme(
        pack: OgLThemePacks.vscode,
        brightness: OgLBrightness.dark,
        tokens: tokens,
        layout: _viewport(width: 800).spec,
      );

      final extension = theme.extension<OgLTheme>();
      expect(extension, isNotNull);
      expect(extension!.themeId, OgLThemePacks.vscode.id);
      expect(theme.dividerTheme.thickness, closeTo(1 / 3, 0.0001));
      expect(theme.useMaterial3, isTrue);
      // 极客风不要水波纹。
      expect(theme.splashFactory, NoSplash.splashFactory);
    });

    test('色板插值：中点既不是起点也不是终点', () {
      final theme = OgLTheme.fallback;
      final mid = theme.lerp(
        theme.copyWith(palette: OgLThemePacks.winui3.paletteFor(OgLBrightness.dark)),
        0.5,
      );
      expect(mid.palette.background, isNot(theme.palette.background));
    });
  });
}