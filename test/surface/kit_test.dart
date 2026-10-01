/// OGL Kit · 冒烟测试：按钮 / 横幅 / 标签 / 骨架 / 进度。
///
/// 只验证"语义行为"（点击、禁用、加载中、渲染存在），
/// 像素层由渲染快照流水线负责。
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
          size: Size(400, 800),
          devicePixelRatio: 2,
          textScale: 1,
          padding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
          platform: OgLPlatformKind.android,
          pointer: OgLPointerKind.touch,
        ),
      ),
    ),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('OGL Kit · 按钮', () {
    testWidgets('可点击并回调一次', (WidgetTester tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(OgLButton(
        label: 'Primary',
        variant: OgLButtonVariant.primary,
        onPressed: () => taps++,
      )));
      await tester.tap(find.text('Primary'));
      expect(taps, 1);
    });

    testWidgets('禁用（onPressed = null）点击无回调', (WidgetTester tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(const OgLButton(label: 'Disabled')));
      await tester.tap(find.text('Disabled'), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('加载中：显示指示器且点击被阻断', (WidgetTester tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(OgLButton(
        label: 'Saving',
        loading: true,
        onPressed: () => taps++,
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(OgLButton), warnIfMissed: false);
      expect(taps, 0);
    });
  });

  group('OGL Kit · 横幅', () {
    testWidgets('渲染文本与标题', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const OgLBanner(
        variant: OgLBannerVariant.warning,
        title: '注意',
        text: '网络抖动，请求已重试',
      )));
      expect(find.text('注意'), findsOneWidget);
      expect(find.text('网络抖动，请求已重试'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('OGL Kit · 标签', () {
    testWidgets('三种标签同时渲染', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const Wrap(
        spacing: 8,
        children: <Widget>[
          OgLLabel(text: 'Public', variant: OgLLabelVariant.success),
          OgLCounterLabel(count: 12),
          OgLStateLabel(kind: OgLStateKind.open, text: 'Open'),
        ],
      )));
      expect(find.text('Public'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('OGL Kit · 骨架与进度', () {
    testWidgets('骨架屏能渲染（呼吸动画不阻塞测试）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const Column(
        children: <Widget>[
          OgLSkeletonAvatar(),
          OgLSkeletonText(lines: 2),
        ],
      )));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(OgLSkeletonBox), findsWidgets);
      // 显式卸载：停掉循环动画。
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('进度条显示百分比', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const OgLProgressBar(
        value: 0.42,
        showLabel: true,
      )));
      expect(find.text('42%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
