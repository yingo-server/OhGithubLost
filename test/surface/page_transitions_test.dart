/// 展示层 · 页面过渡的性能约定（5.0 修「页面过渡卡顿」的回归护栏）。
///
/// 用户实测：**页面过渡**卡，而其它动画不卡。根因是整页缩放过渡
/// （Flutter 默认 `ZoomPageTransitionsBuilder`）要求整页在过渡期间反复
/// 重新光栅化。因此这里把两条约定固定成测试：
/// 1. 过渡必须包 `RepaintBoundary`（过渡期间只重合成，不重绘页面）；
/// 2. 过渡默认**不带缩放**；只有档位 3（拉满）允许 0.99 级别的轻微缩放，
///    且同样必须包在 `RepaintBoundary` 里。不得引用 Flutter 默认的整页缩放过渡。
///
/// 档位 `0`（关闭动画）例外：直接返回 child，不做任何包装。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/motion.dart';

/// 取某个档位在 Android 上实际生效的过渡构建器。
PageTransitionsBuilder _builderFor(int level) {
  final PageTransitionsTheme theme = OgLMotion.pageTransitions(level);
  return theme.builders[TargetPlatform.android]!;
}

/// 用构建器产出一次过渡的 widget 树（[t] 为动画进度）。
Widget _transition(
  PageTransitionsBuilder builder,
  BuildContext context,
  double t,
) {
  final MaterialPageRoute<void> route = MaterialPageRoute<void>(
    builder: (BuildContext _) => const SizedBox.shrink(),
  );
  return builder.buildTransitions<void>(
    route,
    context,
    AlwaysStoppedAnimation<double>(t),
    const AlwaysStoppedAnimation<double>(0),
    const Text('page'),
  );
}

void main() {
  testWidgets('档位 0：不做任何包装（回到 Flutter 之外的"瞬时切换"）',
      (WidgetTester tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) {
            context = ctx;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final Widget result = _transition(_builderFor(0), context, 0.5);
    expect(result, isA<Text>(), reason: '档位 0 必须原样返回 child');
  });

  for (final int level in <int>[1, 2, 3]) {
    testWidgets('档位 $level：必须包 RepaintBoundary，且不含任何缩放',
        (WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext ctx) {
              context = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final Widget result = _transition(_builderFor(level), context, 0.5);
      // ① 最外层就是 RepaintBoundary：过渡只做图层合成。
      expect(result, isA<RepaintBoundary>(),
          reason: '档位 $level 的过渡最外层必须是 RepaintBoundary');
      // ② 真的挂进树里跑一遍：只有拉满档允许缩放。
      await tester.pumpWidget(MaterialApp(home: result));
      if (level == 3) {
        expect(find.byType(ScaleTransition), findsOneWidget,
            reason: '拉满档允许 0.99 级轻微缩放');
      } else {
        expect(find.byType(ScaleTransition), findsNothing,
            reason: '档位 $level 不应使用缩放过渡（整页重光栅化的根源）');
      }
      expect(find.byType(RepaintBoundary), findsWidgets);
      // ③ 也不得回退到 Flutter 的整页缩放过渡。
      expect(_builderFor(level), isNot(isA<ZoomPageTransitionsBuilder>()));
    });
  }

  test('所有档位都覆盖全部平台（避免某平台漏配而回落到默认缩放过渡）', () {
    for (final int level in <int>[0, 1, 2, 3]) {
      final PageTransitionsTheme theme = OgLMotion.pageTransitions(level);
      for (final TargetPlatform platform in TargetPlatform.values) {
        expect(theme.builders.containsKey(platform), isTrue,
            reason: '档位 $level 缺少平台 $platform 的过渡配置');
      }
    }
  });
}