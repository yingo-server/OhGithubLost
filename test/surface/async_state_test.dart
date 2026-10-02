/// L3 展示级 · 异步四态语义测试（W7 回归）。
///
/// 锁死一件事：**空结果 ≠ 加载中**。
/// 历史缺陷：页面用 `state.data == null` 当"加载中"，而空结果的 `data`
/// 也是 null ⇒ 零议题 / 零评论 / 零文件 / 空搜索**永远停在骨架屏**，
/// 用户看到的就是"仓库里很多标签失效"。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/async_state.dart';
import 'package:ohgithublost/surface/app/async_view.dart';
import 'package:ohgithublost/surface/kit/kit.dart';
import 'package:ohgithublost/surface/layout/adaptive.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/theme/theme_pack.dart';

/// 把组件挂到真实主题编译产物上。
Widget _host(Widget child) {
  final OgLTokens tokens = OgLTokens.resolve();
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
  group('OgLAsync 四态语义', () {
    test('空结果：isEmptyResult 为真，且**不是**首次加载', () {
      final OgLAsync<List<int>> state =
          const OgLAsync<List<int>>.idle().settle(<int>[], isEmpty: (List<int> v) => v.isEmpty);
      expect(state.phase, OgLAsyncPhase.empty);
      expect(state.isEmptyResult, isTrue);
      expect(state.isFirstLoading, isFalse, reason: '空结果绝不能被当成加载中');
      expect(state.failureMessage, isNull);
      expect(state.data, isNull);
    });

    test('有数据：ready，且不是加载中/不是空', () {
      final OgLAsync<List<int>> state =
          const OgLAsync<List<int>>.idle().settle(<int>[1], isEmpty: (List<int> v) => v.isEmpty);
      expect(state.phase, OgLAsyncPhase.ready);
      expect(state.isEmptyResult, isFalse);
      expect(state.isFirstLoading, isFalse);
      expect(state.data, <int>[1]);
    });

    test('idle / loading 才算首次加载', () {
      expect(const OgLAsync<List<int>>.idle().isFirstLoading, isTrue);
      expect(const OgLAsync<List<int>>.loading().isFirstLoading, isTrue);
    });

    test('失败：failureMessage 非空（错误必须带原因）', () {
      const OgLAsync<List<int>> state = OgLAsync<List<int>>.failed('连接超时');
      expect(state.failureMessage, '连接超时');
      expect(state.isFirstLoading, isFalse);
      expect(state.isEmptyResult, isFalse);
    });

    test('刷新失败：保留旧数据，只记 softError（内容不该被错误页顶掉）', () {
      final OgLAsync<List<int>> ready =
          const OgLAsync<List<int>>.idle().settle(<int>[1, 2], isEmpty: (List<int> v) => v.isEmpty);
      final OgLAsync<List<int>> failed = ready.fail('网络抖动');
      expect(failed.data, <int>[1, 2], reason: '刷新失败必须保留上次结果');
      expect(failed.softError, '网络抖动');
      expect(failed.failureMessage, isNull, reason: '有数据时不该走整页错误态');
    });

    test('控制器：loader 返回空列表 ⇒ 落到 empty（不是 loading）', () async {
      final OgLAsyncController<List<int>> controller = OgLAsyncController<List<int>>(
        label: '议题',
        isEmpty: (List<int> value) => value.isEmpty,
        loader: () async => <int>[],
      );
      expect(controller.state.isFirstLoading, isTrue);
      await controller.load();
      expect(controller.state.isEmptyResult, isTrue);
      expect(controller.state.isFirstLoading, isFalse);
      expect(controller.state.failureMessage, isNull);
    });

    test('控制器：loader 抛错 ⇒ failed 且带原因', () async {
      final OgLAsyncController<List<int>> controller = OgLAsyncController<List<int>>(
        label: '议题',
        isEmpty: (List<int> value) => value.isEmpty,
        loader: () async => throw Exception('boom'),
      );
      await controller.load();
      expect(controller.state.failureMessage, isNotNull);
      expect(controller.state.isFirstLoading, isFalse);
    });
  });

  group('ogLAsyncView 唯一映射点', () {
    testWidgets('空结果 → Blankslate（不是骨架、不是 Banner）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(ogLAsyncView<List<int>>(
        state: const OgLAsync<List<int>>.idle()
            .settle(<int>[], isEmpty: (List<int> v) => v.isEmpty),
        emptyTitle: '没有打开的议题',
        emptyBody: '可以从这里新建一个。',
        child: const Text('真实内容'),
      )));
      expect(find.byType(OgLBlankslate), findsOneWidget);
      expect(find.text('没有打开的议题'), findsOneWidget);
      expect(find.byType(OgLSkeletonBox), findsNothing, reason: '空结果绝不该显示骨架');
      expect(find.text('真实内容'), findsNothing);
    });

    testWidgets('加载中 → 骨架', (WidgetTester tester) async {
      await tester.pumpWidget(_host(ogLAsyncView<List<int>>(
        state: const OgLAsync<List<int>>.loading(),
        child: const Text('真实内容'),
      )));
      expect(find.byType(OgLSkeletonBox), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('失败 → Banner + 重试可点', (WidgetTester tester) async {
      var retried = 0;
      await tester.pumpWidget(_host(ogLAsyncView<List<int>>(
        state: const OgLAsync<List<int>>.failed('连接超时'),
        errorTitle: '议题读取失败',
        onRetry: () async {
          retried++;
        },
        child: const Text('真实内容'),
      )));
      expect(find.text('议题读取失败'), findsOneWidget);
      expect(find.text('连接超时'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('有数据 → 内容；带 softError → 顶部警告但内容仍在', (WidgetTester tester) async {
      final OgLAsync<List<int>> ready =
          const OgLAsync<List<int>>.idle().settle(<int>[1], isEmpty: (List<int> v) => v.isEmpty);
      await tester.pumpWidget(_host(ogLAsyncView<List<int>>(
        state: ready.fail('网络抖动'),
        child: const Text('真实内容'),
      )));
      expect(find.text('真实内容'), findsOneWidget, reason: '刷新失败不该把内容顶掉');
      expect(find.text('刷新失败（显示的是上次结果）'), findsOneWidget);
    });
  });
}