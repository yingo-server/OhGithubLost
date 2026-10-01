/// L3 展示级 · 导航组件测试：UnderlineNav（水平标签）与 Segmented。
///
/// 历史缺陷：仓库页标签曾用 Wrap + Button 拼装，视觉退化成"竖排链接堆"。
/// 本测试锁死两件事：**水平性**与**回调值正确**。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/kit/kit.dart';
import 'package:ohgithublost/surface/layout/adaptive.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/theme/theme_pack.dart';

/// 把组件挂到真实主题编译产物上（与生产同一条路径）。
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
  group('OgLUnderlineNav', () {
    testWidgets('水平渲染全部标签，点击切换且回调值正确', (WidgetTester tester) async {
      var value = 'a';
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) =>
            OgLUnderlineNav<String>(
          items: const <OgLUnderlineNavItem<String>>[
            OgLUnderlineNavItem<String>(value: 'a', label: '代码'),
            OgLUnderlineNavItem<String>(value: 'b', label: '议题'),
            OgLUnderlineNavItem<String>(value: 'c', label: '设置'),
          ],
          value: value,
          onChanged: (String v) => setState(() => value = v),
        ),
      )));

      expect(find.text('代码'), findsOneWidget);
      expect(find.text('议题'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);

      final double y1 = tester.getCenter(find.text('代码')).dy;
      final double y2 = tester.getCenter(find.text('议题')).dy;
      final double y3 = tester.getCenter(find.text('设置')).dy;
      expect((y1 - y2).abs() < 0.5 && (y2 - y3).abs() < 0.5, isTrue,
          reason: '标签必须水平排布（竖排 = 历史缺陷形态）');

      await tester.tap(find.text('议题'));
      await tester.pump();
      expect(value, 'b');
    });
  });

  group('OgLSegmented', () {
    testWidgets('渲染并切换（模式切换语义）', (WidgetTester tester) async {
      var value = 0;
      await tester.pumpWidget(_host(StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) =>
            OgLSegmented<int>(
          items: const <OgLSegmentedItem<int>>[
            OgLSegmentedItem<int>(value: 0, label: '仓库'),
            OgLSegmentedItem<int>(value: 1, label: '代码'),
          ],
          value: value,
          onChanged: (int v) => setState(() => value = v),
        ),
      )));

      expect(find.text('仓库'), findsOneWidget);
      expect(find.text('代码'), findsOneWidget);

      await tester.tap(find.text('代码'));
      await tester.pump();
      expect(value, 1);
    });
  });
}