/// L3 · 渲染快照测试：把主壳**真实渲染成 PNG**，由 CI 作为产物上传。
///
/// 静态分析保证"代码没错"，单测保证"逻辑对"，但它们都回答不了
/// "界面到底长什么样"。本测试补上这一环：
/// 三套主题 × 四种屏幕形态 = 12 张真实渲染图，
/// 于是"有没有溢出、主题有没有生效、分栏对不对"都变成**可看的事实**。
///
/// 产物：`build/ui_shots/*.png`（只进 CI 工件，不进仓库）。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/app/shell.dart';
import 'package:ohgithublost/surface/layout/adaptive.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/theme/icon_pack.dart';
import 'package:ohgithublost/surface/theme/theme_pack.dart';

const Map<String, Size> _forms = <String, Size>{
  'phone': Size(390, 844),
  'phone_land': Size(844, 390),
  'tablet': Size(834, 1112),
  'desktop': Size(1440, 900),
};

final GlobalKey _key = GlobalKey();

void main() {
  testWidgets('主壳 × 三套主题 × 四种形态', (WidgetTester tester) async {
    final dir = Directory('build/ui_shots');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    for (final pack in OgLThemePacks.all) {
      for (final entry in _forms.entries) {
        final viewport = OgLViewport(
          size: entry.value,
          devicePixelRatio: 2,
          textScale: 1,
          padding: EdgeInsets.zero,
          viewInsets: EdgeInsets.zero,
          platform: OgLPlatformKind.android,
          pointer: OgLPointerKind.touch,
        );
        final layout = viewport.spec;

        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = Size(
          entry.value.width * 2,
          entry.value.height * 2,
        );
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          RepaintBoundary(
            key: _key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              scrollBehavior: const OgLScrollBehavior(),
              theme: buildOgLTheme(
                pack: pack,
                brightness: OgLBrightness.dark,
                tokens: OgLTokens.resolve(),
                layout: layout,
              ),
              home: OgLShellFrame(
                pages: _pages,
                onRefresh: () async {},
                listPane: const _ListPane(),
                detailPane: const _DetailPane(),
                auxPane: const _DetailPane(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final boundary =
            _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        File('build/ui_shots/${pack.id}__${entry.key}.png')
            .writeAsBytesSync(data!.buffer.asUint8List());
      }
    }

    final count = dir.listSync().whereType<File>().length;
    expect(
      count,
      OgLThemePacks.all.length * _forms.length,
      reason: '每个主题 × 每种形态都要出一张图（防止"看起来跑了其实没写"）',
    );
  });
}

final List<OgLPageSpec> _pages = <OgLPageSpec>[
  OgLPageSpec(
    id: 'overview',
    title: '概览',
    icon: OgLIconName.repository,
    usesPanes: true,
    builder: (BuildContext context) => const _ListPane(),
  ),
  OgLPageSpec(
    id: 'settings',
    title: '设置',
    icon: OgLIconName.settings,
    builder: (BuildContext context) => const _DetailPane(),
  ),
  OgLPageSpec(
    id: 'diagnostics',
    title: '诊断',
    icon: OgLIconName.bug,
    builder: (BuildContext context) => const _DetailPane(),
  ),
];

class _ListPane extends StatelessWidget {
  const _ListPane();

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    return ListView.builder(
      itemCount: 32,
      itemBuilder: (BuildContext context, int index) => ListTile(
        dense: true,
        selected: index == 0,
        leading: Icon(ogL.icon(OgLIconName.folder)),
        title: Text('仓库条目 $index'),
        subtitle: Text(
          '用于检查行距与选中态',
          style: TextStyle(color: ogL.palette.textDim),
        ),
        trailing: Icon(ogL.icon(OgLIconName.chevronRight)),
      ),
    );
  }
}

class _DetailPane extends StatelessWidget {
  const _DetailPane();

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    return ListView(
      padding: EdgeInsets.all(ogL.tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        Text('详情面板', style: Theme.of(context).textTheme.titleMedium),
        SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
        for (var i = 0; i < 10; i++)
          Padding(
            padding: EdgeInsets.only(bottom: ogL.tokens.space(OgLSpacing.sm)),
            child: Text('第 $i 行：检查长文本在窄栏中的换行与行距是否稳定。'),
          ),
      ],
    );
  }
}