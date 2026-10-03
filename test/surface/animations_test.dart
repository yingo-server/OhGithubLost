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
    expect(OgLAnim.stagger(context, 3), Duration.zero);
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
            child: const OgLReveal(child: Text('内容')),
          ),
        ),
      );
    }

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

    // 档位 3：淡入 + 位移 + 缩放。
    await pumpAt(3);
    expect(find.byType(AnimatedSlide), findsOneWidget);
    expect(find.byType(AnimatedScale), findsOneWidget);
  });
}