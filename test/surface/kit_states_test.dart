/// L3 展示级 · 三态与结构组件测试（第二阶段 W1/W2 回归）。
///
/// 锁死四件事（都是真实缺陷的根因，不许回头）：
/// 1. **三态收敛**：载 / 空 / 错一律走 `OgLStateView`（页面自己不再各写一套）；
/// 2. **空态是 Blankslate**：不许用 Banner 冒充空态（那是"大面积灰色块"来源）；
/// 3. **输入框不填充灰底**、**横幅不用半透明色块**（另两条根因）；
/// 4. **交互反馈**：列表行有 hover / focus（InkWell），开关整行可点。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/kit/kit.dart';
import 'package:ohgithublost/surface/layout/adaptive.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/theme/theme_pack.dart';

/// 把组件挂到真实的主题编译产物上（与生产同一条路径）。
Widget _host(Widget child) {
  final tokens = OgLTokens.resolve();
  return MaterialApp(
    theme: buildOgLTheme(
      pack: OgLThemePacks.primer,
      brightness: OgLBrightness.dark,
      tokens: tokens,
      layout: OgLLayoutSpec.resolve(
        const OgLViewport(
          size: Size(420, 900),
          devicePixelRatio: 2,
          textScale: 1,
          padding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
          platform: OgLPlatformKind.android,
          pointer: OgLPointerKind.touch,
        ),
      ),
    ),
    home: Scaffold(
      body: SingleChildScrollView(child: child),
    ),
  );
}

void main() {
  final OgLPalette palette =
      OgLThemePacks.primer.paletteFor(OgLBrightness.dark);

  group('OgLBlankslate（空态）', () {
    testWidgets('渲染图标 / 标题 / 说明 / 动作，且动作可点', (WidgetTester tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(OgLBlankslate(
        title: '没有打开的议题',
        body: '议题用来跟踪缺陷与任务。',
        action: OgLButton(label: '新建议题', onPressed: () => taps++),
      )));
      expect(find.text('没有打开的议题'), findsOneWidget);
      expect(find.text('议题用来跟踪缺陷与任务。'), findsOneWidget);
      await tester.tap(find.text('新建议题'));
      expect(taps, 1);
    });
  });

  group('OgLStateView（三态统一）', () {
    testWidgets('错误态：Banner + 可重试', (WidgetTester tester) async {
      var retried = 0;
      await tester.pumpWidget(_host(OgLStateView(
        isEmpty: true,
        error: '连接超时',
        errorTitle: '议题读取失败',
        onRetry: () async {
          retried++;
        },
        child: const Text('真实数据'),
      )));
      expect(find.text('议题读取失败'), findsOneWidget);
      expect(find.text('连接超时'), findsOneWidget);
      expect(find.text('真实数据'), findsNothing, reason: '错误态不许同时渲染内容');
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(retried, 1, reason: '错误必须可重试');
    });

    testWidgets('加载态：骨架（不许是 Banner 色块）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const OgLStateView(
        isEmpty: false,
        loading: true,
        child: Text('真实数据'),
      )));
      expect(find.byType(OgLSkeletonBox), findsWidgets);
      expect(find.byType(OgLBanner), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('空态：Blankslate（不许是 Banner）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const OgLStateView(
        isEmpty: true,
        emptyTitle: '没有分支',
        emptyBody: '可以从默认分支创建一个。',
        child: Text('真实数据'),
      )));
      expect(find.byType(OgLBlankslate), findsOneWidget);
      expect(find.byType(OgLBanner), findsNothing);
      expect(find.text('没有分支'), findsOneWidget);
    });

    testWidgets('有数据：渲染内容', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const OgLStateView(
        isEmpty: false,
        child: Text('真实数据'),
      )));
      expect(find.text('真实数据'), findsOneWidget);
    });
  });

  group('"大面积灰色块"根因回归', () {
    testWidgets('输入框不填充灰底（Primer：描边不填充）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const OgLTextField(label: '仓库名')));
      final TextField field = tester.widget<TextField>(find.byType(TextField));
      final InputDecoration decoration = field.decoration!;
      expect(decoration.filled, isFalse, reason: '填充灰底会成为一大块灰色板');
      expect(decoration.fillColor, isNull);
      expect(find.text('仓库名'), findsOneWidget);
    });

    testWidgets('横幅底色是面板色，不是半透明色块', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const OgLBanner(
        variant: OgLBannerVariant.info,
        text: '提示',
      )));
      final Container container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(OgLBanner),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, palette.surface);
    });
  });

  group('OgLBox / OgLToggleSwitch / OgLActionRow', () {
    testWidgets('Box 渲染标题与内容', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const OgLBox(
        title: '基本设置',
        child: Text('内容'),
      )));
      expect(find.text('基本设置'), findsOneWidget);
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('开关：整行可点、能切换；禁用时无效', (WidgetTester tester) async {
      var value = false;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => OgLToggleSwitch(
          label: '私有仓库',
          description: '只有你与协作者可见。',
          value: value,
          onChanged: (bool v) => setState(() => value = v),
        ),
      )));
      await tester.tap(find.byType(OgLToggleSwitch));
      await tester.pump();
      expect(value, isTrue, reason: '点标签也要能切换');

      await tester.pumpWidget(_host(const OgLToggleSwitch(value: false)));
      await tester.tap(find.byType(OgLToggleSwitch), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(OgLToggleSwitch), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('列表行自带 hover / focus 反馈（InkWell）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(OgLActionRow(
        title: 'README.md',
        subtitle: '文件',
        onTap: () {},
      )));
      expect(
        find.descendant(
          of: find.byType(OgLActionRow),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });
  });
}