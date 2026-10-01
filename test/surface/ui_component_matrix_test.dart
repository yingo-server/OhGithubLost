/// L3 展示级 · **组件快照矩阵**（W4）：两主题 × 明暗 × 全部 Kit 组件 → 真实 PNG。
///
/// 产物：`build/ui_shots/matrix_<themeId>__<brightness>.png`（只进 CI 工件，不进仓库）。
///
/// 为什么要有它：静态分析与单测都回答不了"这一屏到底长什么样"。
/// 有了矩阵图，"控件配色 / 间距 / 状态色是否成体系"变成**可看的事实**，
/// 也让"大面积灰色块"这类缺陷在下一次一眼可见。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/kit/kit.dart';
import 'package:ohgithublost/surface/layout/adaptive.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/theme/icon_pack.dart';
import 'package:ohgithublost/surface/theme/theme_pack.dart';

const Size _canvas = Size(420, 2000);

final GlobalKey _key = GlobalKey();

/// 小节标题。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final scale = const OgLTypeScale.standard();
    return Padding(
      padding: EdgeInsets.only(
        top: ogL.tokens.space(OgLSpacing.lg),
        bottom: ogL.tokens.space(OgLSpacing.sm),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: kOgLMonoFamily,
          fontSize: ogL.tokens.fontSize(scale.label),
          color: ogL.palette.textDim,
        ),
      ),
    );
  }
}

/// 组件画廊（一屏看全）。
Widget _gallery(OgLThemePack pack, OgLBrightness brightness) {
  final viewport = OgLViewport(
    size: _canvas,
    devicePixelRatio: 2,
    textScale: 1,
    padding: EdgeInsets.zero,
    viewInsets: EdgeInsets.zero,
    platform: OgLPlatformKind.android,
    pointer: OgLPointerKind.touch,
  );
  return RepaintBoundary(
    key: _key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const OgLScrollBehavior(),
      theme: buildOgLTheme(
        pack: pack,
        brightness: brightness,
        tokens: OgLTokens.resolve(),
        layout: viewport.spec,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Builder(
            builder: (BuildContext context) {
              final ogL = OgLTheme.of(context);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const _SectionTitle('按钮 / Button'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      OgLButton(
                        label: 'Primary',
                        variant: OgLButtonVariant.primary,
                        onPressed: () {},
                      ),
                      OgLButton(label: 'Standard', onPressed: () {}),
                      OgLButton(
                        label: 'Danger',
                        variant: OgLButtonVariant.danger,
                        onPressed: () {},
                      ),
                      OgLButton(
                        label: 'Invisible',
                        variant: OgLButtonVariant.invisible,
                        onPressed: () {},
                      ),
                      OgLButton(
                        label: 'Small',
                        size: OgLButtonSize.small,
                        leadingIcon: OgLIconName.add,
                        onPressed: () {},
                      ),
                      OgLButton(label: 'Loading', loading: true, onPressed: () {}),
                      const OgLButton(label: 'Disabled'),
                    ],
                  ),
                  const _SectionTitle('标签 / Label · Counter · State'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const <Widget>[
                      OgLLabel(text: 'Public', variant: OgLLabelVariant.success),
                      OgLLabel(text: 'Dart', variant: OgLLabelVariant.accent),
                      OgLLabel(text: '私有', variant: OgLLabelVariant.attention),
                      OgLLabel(text: 'main', variant: OgLLabelVariant.done),
                      OgLCounterLabel(count: 12),
                      OgLStateLabel(kind: OgLStateKind.open, text: 'Open'),
                      OgLStateLabel(kind: OgLStateKind.closed, text: 'Closed'),
                    ],
                  ),
                  const _SectionTitle('输入框 / TextField'),
                  const OgLTextField(label: '仓库名', hint: 'my-repo'),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
                  const OgLTextField(label: '令牌', error: '令牌不能为空'),
                  const _SectionTitle('横幅 / Banner'),
                  const OgLBanner(
                    variant: OgLBannerVariant.info,
                    title: '信息',
                    text: '这是一条提示（底色 = 面板色，不是半透明色块）。',
                  ),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
                  const OgLBanner(
                    variant: OgLBannerVariant.success,
                    title: '成功',
                    text: '已保存基本信息。',
                  ),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
                  const OgLBanner(
                    variant: OgLBannerVariant.danger,
                    title: '失败',
                    text: '目录读取失败：连接超时。',
                  ),
                  const _SectionTitle('空态 / Blankslate'),
                  OgLBlankslate(
                    icon: OgLIconName.issue,
                    title: '没有打开的议题',
                    body: '议题用来跟踪缺陷与任务；可以从这里直接新建一个。',
                    action: OgLButton(
                      label: '新建议题',
                      leadingIcon: OgLIconName.add,
                      onPressed: () {},
                    ),
                  ),
                  const _SectionTitle('分区容器 / Box · ToggleSwitch'),
                  OgLBox(
                    title: '基本设置',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        const OgLTextField(label: '仓库名'),
                        SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
                        OgLToggleSwitch(
                          label: '私有仓库',
                          description: '只有你与协作者可见。',
                          value: true,
                          onChanged: (bool _) {},
                        ),
                        OgLToggleSwitch(
                          label: '归档',
                          value: false,
                          onChanged: (bool _) {},
                        ),
                      ],
                    ),
                  ),
                  const _SectionTitle('导航 / UnderlineNav · Segmented'),
                  OgLUnderlineNav<int>(
                    items: const <OgLUnderlineNavItem<int>>[
                      OgLUnderlineNavItem<int>(value: 0, label: '代码'),
                      OgLUnderlineNavItem<int>(value: 1, label: '议题'),
                      OgLUnderlineNavItem<int>(value: 2, label: 'PR'),
                      OgLUnderlineNavItem<int>(value: 3, label: '设置'),
                    ],
                    value: 0,
                    onChanged: (int _) {},
                  ),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
                  OgLSegmented<int>(
                    items: const <OgLSegmentedItem<int>>[
                      OgLSegmentedItem<int>(value: 0, label: '仓库'),
                      OgLSegmentedItem<int>(value: 1, label: '代码'),
                    ],
                    value: 0,
                    onChanged: (int _) {},
                  ),
                  const _SectionTitle('列表行 / ActionRow'),
                  OgLActionRow(
                    leading: const OgLIcon(name: OgLIconName.file, size: 20),
                    title: 'README.md',
                    subtitle: '文件 · 2.1 KB',
                    showDivider: true,
                    showChevron: true,
                    onTap: () {},
                  ),
                  OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.folder,
                      size: 20,
                      color: ogL.palette.accent,
                    ),
                    title: 'lib',
                    subtitle: '目录',
                    showDivider: true,
                    showChevron: true,
                    onTap: () {},
                  ),
                  OgLActionRow(
                    leading: const OgLIcon(name: OgLIconName.issue, size: 20),
                    title: '#12 修复解码错误',
                    subtitle: 'by yingo · 3 条评论',
                    trailing: OgLButton(
                      label: '关闭',
                      variant: OgLButtonVariant.invisible,
                      size: OgLButtonSize.small,
                      onPressed: () {},
                    ),
                    onTap: () {},
                  ),
                  const _SectionTitle('加载 / Skeleton · Spinner · Progress'),
                  const OgLSkeletonText(lines: 2),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
                  Row(
                    children: <Widget>[
                      const OgLSpinner(label: '读取中…'),
                      SizedBox(width: ogL.tokens.space(OgLSpacing.md)),
                      const Expanded(
                        child: OgLProgressBar(value: 0.6, showLabel: true),
                      ),
                    ],
                  ),
                  const _SectionTitle('图标 / Icons（自绘矢量，24 网格）'),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final OgLIconName name in OgLIconName.values)
                        OgLIcon(name: name, size: 22),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('组件矩阵：两主题 × 明暗 → 真实 PNG', (WidgetTester tester) async {
    final Directory dir = Directory('build/ui_shots');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    int produced = 0;
    for (final OgLThemePack pack in OgLThemePacks.all) {
      for (final OgLBrightness brightness in OgLBrightness.values) {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = Size(_canvas.width * 2, _canvas.height * 2);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_gallery(pack, brightness));
        // 与既有截图流水线一致：**不用 pumpAndSettle**（有持续调度帧的元素），
        // 固定推进 350ms 走完入场动画且必然返回。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        await tester.runAsync(() async {
          final RenderRepaintBoundary boundary =
              _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final ui.Image image = await boundary.toImage();
          final ByteData? data =
              await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          File('build/ui_shots/matrix_${pack.id}__${brightness.name}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
        });
        produced++;
      }
    }

    expect(
      produced,
      OgLThemePacks.all.length * OgLBrightness.values.length,
      reason: '两主题 × 明暗 = 4 张矩阵图',
    );
    for (final OgLThemePack pack in OgLThemePacks.all) {
      for (final OgLBrightness brightness in OgLBrightness.values) {
        final File file =
            File('build/ui_shots/matrix_${pack.id}__${brightness.name}.png');
        expect(file.existsSync(), isTrue, reason: '缺少 ${file.path}');
        expect(file.lengthSync(), greaterThan(1000), reason: '图画出来是空的？');
      }
    }
  });
}