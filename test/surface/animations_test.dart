/// 展示层 · 动效分档与回退检查。
///
/// 覆盖两点：
/// 1. 档位越高，时长越长；
/// 2. 降到 `0` 时动画完全关闭（时长为零、`OgLReveal` 直接显示）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/animations.dart';
import 'package:ohgithublost/surface/app/motion.dart';

/// 用给定档位包一层作用域，并回传 context 供断言。
Future<BuildContext> _pumpAt(WidgetTester tester, int level) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: OgLMotionScope(
        level: level,
        child: Builder(
          builder: (BuildContext context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  testWidgets('档位 0：动画关闭、时长归零', (WidgetTester tester) async {
    final BuildContext context = await _pumpAt(tester, 0);
    expect(OgLAnim.enabled(context), isFalse);
    expect(OgLAnim.fast(context), Duration.zero);
    expect(OgLAnim.medium(context), Duration.zero);
    expect(OgLAnim.slow(context), Duration.zero);
    // 静默档：错峰返回 null（= 该项**不参与**入场动画），而不是"延迟 0"。
    expect(OgLAnim.staggerOf(context, 3), isNull);
  });

  testWidgets('档位 1 / 2 / 3：时长递增', (WidgetTester tester) async {
    final BuildContext c1 = await _pumpAt(tester, 1);
    final Duration m1 = OgLAnim.medium(c1);
    final BuildContext c2 = await _pumpAt(tester, 2);
    final Duration m2 = OgLAnim.medium(c2);
    final BuildContext c3 = await _pumpAt(tester, 3);
    final Duration m3 = OgLAnim.medium(c3);

    expect(OgLAnim.enabled(c1), isTrue);
    expect(m1.inMilliseconds, greaterThan(0));
    expect(m2.inMilliseconds, greaterThan(m1.inMilliseconds));
    expect(m3.inMilliseconds, greaterThan(m2.inMilliseconds));
  });

  testWidgets('从高档降到 0：时长即时回退为零', (WidgetTester tester) async {
    await _pumpAt(tester, 3);
    final BuildContext context = await _pumpAt(tester, 0);
    expect(OgLAnim.enabled(context), isFalse);
    expect(OgLAnim.medium(context), Duration.zero);
  });

  testWidgets('OgLReveal 按档位叠加效果（成本随档位增加）', (WidgetTester tester) async {
    Future<void> pumpAt(int level) async {
      await tester.pumpWidget(
        MaterialApp(
          home: OgLMotionScope(
            level: level,
            child: const OgLReveal(delay: Duration.zero, child: Text('内容')),
          ),
        ),
      );
    }

    // 注意：`delay == null` 表示"该项不参与动画"（长列表尾部按档位限项）。
    // 这里显式给 Duration.zero 以验证**各档位的叠加效果**。

    // 档位 0：无动画层。
    await pumpAt(0);
    expect(find.text('内容'), findsOneWidget);
    expect(find.byType(AnimatedOpacity), findsNothing);

    // 档位 1：仅淡入。
    await pumpAt(1);
    expect(find.byType(AnimatedOpacity), findsOneWidget);
    expect(find.byType(AnimatedSlide), findsNothing);

    // 档位 2：淡入 + 位移。
    await pumpAt(2);
    expect(find.byType(AnimatedSlide), findsOneWidget);
    expect(find.byType(AnimatedScale), findsNothing);

    // 档位 3：淡入 + 位移 + 缩放（拉满）。
    await pumpAt(3);
    expect(find.byType(AnimatedSlide), findsOneWidget);
    expect(find.byType(AnimatedScale), findsOneWidget);
    // 动画期间必须各自带绘制边界（不牵连整列表重绘）。
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  group('档位质量表（降档 = 降质量，而不是砍掉效果）', () {
    test('逐级单调：1 不比 2 重、2 不比 3 重、0 不比 1 重', () {
      for (int level = 0; level <= 2; level++) {
        expect(
          OgLOAnimQuality.of(level)
              .isNotHeavierThan(OgLOAnimQuality.of(level + 1)),
          isTrue,
          reason: '档位 $level 应不比 ${level + 1} 更重',
        );
      }
    });

    test('时长逐档更长（严格递增，而不是"档位相同"）', () {
      final OgLOAnimQuality q1 = OgLOAnimQuality.of(1);
      final OgLOAnimQuality q2 = OgLOAnimQuality.of(2);
      final OgLOAnimQuality q3 = OgLOAnimQuality.of(3);
      expect(q1.medium < q2.medium, isTrue);
      expect(q2.medium < q3.medium, isTrue);
      expect(q1.staggerMaxIndex < q2.staggerMaxIndex, isTrue);
      expect(q2.staggerMaxIndex < q3.staggerMaxIndex, isTrue);
      expect(q1.transitionOffset < q2.transitionOffset, isTrue);
      expect(q2.transitionOffset < q3.transitionOffset, isTrue);
    });

    test('大体积动画：时长逐档增加，但都**比 5.2 更快**', () {
      final OgLOAnimQuality q1 = OgLOAnimQuality.of(1);
      final OgLOAnimQuality q2 = OgLOAnimQuality.of(2);
      final OgLOAnimQuality q3 = OgLOAnimQuality.of(3);
      // 逐档更重（1 < 2 < 3）
      expect(q1.shellDuration < q2.shellDuration, isTrue);
      expect(q2.shellDuration < q3.shellDuration, isTrue);
      expect(q1.stateSwapDuration < q2.stateSwapDuration, isTrue);
      expect(q2.stateSwapDuration < q3.stateSwapDuration, isTrue);
      expect(q1.pageViewDuration < q2.pageViewDuration, isTrue);
      expect(q2.pageViewDuration < q3.pageViewDuration, isTrue);
      expect(q1.sheetDuration < q2.sheetDuration, isTrue);
      expect(q2.sheetDuration < q3.sheetDuration, isTrue);
      // 手感目标：全页 / 半页动画都在 250ms 以内（原先路由默认 300ms 起）
      for (final OgLOAnimQuality q in <OgLOAnimQuality>[q1, q2, q3]) {
        expect(q.shellDuration.inMilliseconds, lessThanOrEqualTo(200));
        expect(q.stateSwapDuration.inMilliseconds, lessThanOrEqualTo(200));
        expect(q.pageViewDuration.inMilliseconds, lessThanOrEqualTo(280));
        expect(q.sheetDuration.inMilliseconds, lessThanOrEqualTo(220));
      }
      // 静默档：全部为零（面板/翻页/memo 都"直接出现"）
      final OgLOAnimQuality q0 = OgLOAnimQuality.of(0);
      expect(q0.shellDuration, Duration.zero);
      expect(q0.stateSwapDuration, Duration.zero);
      expect(q0.pageViewDuration, Duration.zero);
      expect(q0.sheetDuration, Duration.zero);
      expect(q0.transitionWindow, 0);
    });

    test('缩放最保守档不做、模糊只在拉满档', () {
      expect(OgLOAnimQuality.of(1).hasScale, isFalse, reason: '档位 1 不缩放');
      expect(OgLOAnimQuality.of(2).hasScale, isTrue, reason: '档位 2 起给极轻缩放');
      expect(OgLOAnimQuality.of(3).hasScale, isTrue);
      expect(OgLOAnimQuality.of(1).hasBlur, isFalse);
      expect(OgLOAnimQuality.of(2).hasBlur, isFalse);
      expect(OgLOAnimQuality.of(3).hasBlur, isTrue);
    });

    test('档位 0：全静默（时长零、无位移、无缩放）', () {
      final OgLOAnimQuality q0 = OgLOAnimQuality.of(0);
      expect(q0.fast, Duration.zero);
      expect(q0.medium, Duration.zero);
      expect(q0.slow, Duration.zero);
      expect(q0.hasScale, isFalse);
      expect(q0.revealOffset, 0);
      expect(q0.transitionOffset, 0);
    });

    testWidgets('入场错峰按档位限项：超出上限返回 null（该项不参与动画）',
        (WidgetTester tester) async {
      Future<BuildContext> pump(int level) => _pumpAt(tester, level);

      // 档位 1：只让前 3 项动。
      final BuildContext c1 = await pump(1);
      expect(OgLAnim.staggerOf(c1, 0), Duration.zero);
      expect(OgLAnim.staggerOf(c1, 3), isNotNull);
      expect(OgLAnim.staggerOf(c1, 4), isNull);

      final BuildContext c3 = await pump(3);
      expect(OgLAnim.staggerOf(c3, 16), isNotNull);
      expect(OgLAnim.staggerOf(c3, 17), isNull);

      final BuildContext c0 = await pump(0);
      expect(OgLAnim.staggerOf(c0, 0), isNull, reason: '静默档不参与任何入场动画');
    });
  });
}