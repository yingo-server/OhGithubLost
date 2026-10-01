/// L3 展示级 · 自绘矢量图标测试（W3 回归）。
///
/// 锁死四件事：
/// 1. **语义全覆盖**：每个 `OgLIconName` 都必须有手写矢量（少一个就红）；
/// 2. **可解析**：所有 `d` 字符串都能解析、边界落在 24 网格内；
/// 3. **语义唯一**：不允许两个语义共用同一段路径（那是"图标没换"的变体）；
/// 4. **零 Material 字形**：全仓库不再出现 `Icons.xxx` 与 `Icon(ogL.icon(...))`
///    —— 这是用户报告的"图标没有更换"的结构性保证。
library;

import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/icons/og_l_vector_icon.dart';
import 'package:ohgithublost/surface/kit/kit.dart';
import 'package:ohgithublost/surface/layout/adaptive.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/theme/icon_pack.dart';
import 'package:ohgithublost/surface/theme/theme_pack.dart';

/// 把组件挂到真实的主题编译产物上。
Widget _host(Widget child, {OgLThemePack? pack}) {
  final tokens = OgLTokens.resolve();
  return MaterialApp(
    theme: buildOgLTheme(
      pack: pack ?? OgLThemePacks.primer,
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
  group('矢量图标数据', () {
    test('每个语义都有手写矢量（无缺口）', () {
      final missing = <OgLIconName>[];
      for (final OgLIconName name in OgLIconName.values) {
        if (!OgLVectorIconData.paths.containsKey(name)) {
          missing.add(name);
        }
      }
      expect(
        missing,
        isEmpty,
        reason: '这些语义还没有矢量：${missing.map((OgLIconName n) => n.name).join(', ')}',
      );
      expect(OgLVectorIconData.paths.length, OgLIconName.values.length);
    });

    test('每段路径都能解析，且边界落在 24 网格内', () {
      for (final MapEntry<OgLIconName, String> entry
          in OgLVectorIconData.paths.entries) {
        final Path path = ogLParseVectorPath(entry.value);
        final Rect bounds = path.getBounds();
        expect(
          bounds.isEmpty,
          isFalse,
          reason: '${entry.key.name} 解析出空路径：${entry.value}',
        );
        expect(
          bounds.left >= -1 && bounds.top >= -1,
          isTrue,
          reason: '${entry.key.name} 越出网格左上：$bounds',
        );
        expect(
          bounds.right <= 25 && bounds.bottom <= 25,
          isTrue,
          reason: '${entry.key.name} 越出网格右下：$bounds',
        );
      }
    });

    test('语义唯一：没有两个语义共用同一段路径', () {
      final Map<String, OgLIconName> seen = <String, OgLIconName>{};
      for (final MapEntry<OgLIconName, String> entry
          in OgLVectorIconData.paths.entries) {
        final OgLIconName? other = seen[entry.value];
        expect(
          other,
          isNull,
          reason: '${entry.key.name} 与 ${other?.name} 的矢量完全相同（语义重复）',
        );
        seen[entry.value] = entry.key;
      }
    });

    test('解析器：矩形路径的边界正确', () {
      final Rect bounds = ogLParseVectorPath('M0 0 H24 V24 H0 Z').getBounds();
      expect(bounds.left, 0);
      expect(bounds.top, 0);
      expect(bounds.right, 24);
      expect(bounds.bottom, 24);
    });

    test('未知语义返回空路径（不抛）', () {
      expect(() => ogLParseVectorPath('M1 1'), returnsNormally);
    });
  });

  group('OgLIcon 渲染', () {
    testWidgets('全部语义都能画出来（不抛、尺寸正确）', (WidgetTester tester) async {
      await tester.pumpWidget(_host(Column(
        children: <Widget>[
          for (final OgLIconName name in OgLIconName.values)
            OgLIcon(name: name, size: 20),
        ],
      )));
      expect(find.byType(OgLIcon), findsNWidgets(OgLIconName.values.length));
      final Size size = tester.getSize(find.byType(OgLIcon).first);
      expect(size.width, 20);
      expect(size.height, 20);
    });

    testWidgets('三种图标风格都能渲染（细线 / 标准 / 实心）', (WidgetTester tester) async {
      for (final OgLIconSet set in OgLIconSets.all) {
        final OgLTheme base = OgLTheme.fallback;
        await tester.pumpWidget(MaterialApp(
          theme: buildOgLTheme(
            pack: OgLThemePacks.primer,
            brightness: OgLBrightness.dark,
            tokens: OgLTokens.resolve(),
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
          home: Builder(
            builder: (BuildContext context) => Theme(
              data: Theme.of(context).copyWith(
                extensions: <ThemeExtension<dynamic>>[
                  base.copyWith(iconSet: set),
                ],
              ),
              child: const Scaffold(
                body: Center(child: OgLIcon(name: OgLIconName.star, size: 24)),
              ),
            ),
          ),
        ));
        expect(
          find.byType(OgLIcon),
          findsOneWidget,
          reason: '风格 ${set.id} 渲染失败',
        );
        expect(OgLTheme.of(tester.element(find.byType(OgLIcon))).iconStyle,
            set.style);
      }
      expect(OgLIconSets.byId(null).id, OgLIconSets.fallback.id);
      expect(OgLIconSets.byId('不存在').id, OgLIconSets.fallback.id);
    });
  });

  group('"图标没有更换"结构性回归', () {
    test('lib 下不再出现 Material 字形图标与旧取图标方式', () {
      final List<String> offenders = <String>[];
      final Directory lib = Directory('lib');
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final List<String> lines =
            entity.readAsLinesSync();
        for (int i = 0; i < lines.length; i++) {
          final String line = lines[i];
          final String trimmed = line.trimLeft();
          if (trimmed.startsWith('//')) {
            continue; // 注释里可以谈 `Icons.xxx`（那是留档）
          }
          if (line.contains('Icons.') || line.contains('ogL.icon(')) {
            offenders.add('${entity.path}:${i + 1}');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '仍有 Material 字形图标调用：${offenders.join(', ')}',
      );
    });
  });
}