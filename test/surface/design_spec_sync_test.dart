/// L3 展示级 · UI 设计规范一致性测试：`DESIGN.md` ↔ 代码令牌 / 控件清单。
///
/// W0（规范先行）的机器护栏，锁死两件事：
/// 1. `DESIGN.md`（design-md 格式）里的颜色 / 间距 / 圆角令牌，
///    逐项对上 `theme_pack.dart` 与 `design_tokens.dart` —— 规范或代码
///    任何一边漂移，这里立刻红；
/// 2. `docs/UI_SYSTEM_V3.md` 的逐控件清单必须覆盖 `lib/surface/kit/`
///    全部组件文件 —— 不许"实现了但没进规范"。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ohgithublost/surface/theme/design_tokens.dart';
import 'package:ohgithublost/surface/theme/theme_pack.dart';

/// 把颜色写成 CSS 形式（`#RRGGBB`；带透明度时 `#RRGGBBAA`）。
String _cssHex(Color color) {
  final int argb = color.toARGB32();
  final int a = (argb >> 24) & 0xFF;
  final int r = (argb >> 16) & 0xFF;
  final int g = (argb >> 8) & 0xFF;
  final int b = argb & 0xFF;
  String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  final String rgb = '#${h(r)}${h(g)}${h(b)}';
  return a == 0xFF ? rgb : '$rgb${h(a)}';
}

/// 尺寸令牌写成像素字面量（整数不带小数点）。
String _dim(double value) {
  final String s = value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
  return '${s}px';
}

/// 取出 YAML 顶层块（`key:` 到下一个顶层键之间的缩进行）。
String _block(String text, String key) {
  final List<String> out = <String>[];
  bool inside = false;
  for (final String line in text.split('\n')) {
    if (line == '$key:') {
      inside = true;
      continue;
    }
    if (!inside) {
      continue;
    }
    if (line.isEmpty) {
      continue;
    }
    if (!line.startsWith(' ')) {
      break;
    }
    out.add(line.trim());
  }
  return out.join('\n');
}

void main() {
  final String spec = File('DESIGN.md').readAsStringSync();

  final Map<String, OgLPalette> palettes = <String, OgLPalette>{
    'primer-dark': OgLThemePacks.primer.paletteDark!,
    'primer-light': OgLThemePacks.primer.paletteLight!,
    'ogl-dark': OgLThemePacks.ogl.paletteDark!,
    'ogl-light': OgLThemePacks.ogl.paletteLight!,
  };

  group('DESIGN.md · 颜色令牌', () {
    test('四套调色板 × 全部语义角色与代码一致', () {
      final String colors = _block(spec, 'colors');
      expect(colors, isNotEmpty, reason: 'DESIGN.md 缺少 colors 块');
      for (final MapEntry<String, OgLPalette> entry in palettes.entries) {
        final OgLPalette p = entry.value;
        final Map<String, Color> roles = <String, Color>{
          'background': p.background,
          'surface': p.surface,
          'surface-alt': p.surfaceAlt,
          'border': p.border,
          'border-strong': p.borderStrong,
          'border-active': p.borderActive,
          'text': p.text,
          'text-dim': p.textDim,
          'text-faint': p.textFaint,
          'accent': p.accent,
          'on-accent': p.onAccent,
          'danger': p.danger,
          'warning': p.warning,
          'success': p.success,
          'info': p.info,
          'selection': p.selection,
          'code-background': p.codeBackground,
          'shadow': p.shadow,
        };
        for (final MapEntry<String, Color> role in roles.entries) {
          final String token = '${entry.key}-${role.key}';
          expect(
            colors.contains('$token: "${_cssHex(role.value)}"'),
            isTrue,
            reason: 'DESIGN.md 颜色令牌缺失或漂移：$token'
                '（应写为 ${_cssHex(role.value)}）',
          );
        }
      }
    });
  });

  group('DESIGN.md · 几何令牌', () {
    test('间距令牌与 design_tokens 一致', () {
      final String block = _block(spec, 'spacing');
      final Map<String, double> spaces = <String, double>{
        'xxs': OgLSpacing.xxs,
        'xs': OgLSpacing.xs,
        'sm': OgLSpacing.sm,
        'md': OgLSpacing.md,
        'lg': OgLSpacing.lg,
        'xl': OgLSpacing.xl,
        'xxl': OgLSpacing.xxl,
      };
      for (final MapEntry<String, double> e in spaces.entries) {
        expect(
          block.contains('${e.key}: ${_dim(e.value)}'),
          isTrue,
          reason: 'DESIGN.md 间距令牌缺失：${e.key}',
        );
      }
    });

    test('圆角令牌与 design_tokens 一致', () {
      final String block = _block(spec, 'rounded');
      final Map<String, double> radii = <String, double>{
        'none': OgLRadius.none,
        'xs': OgLRadius.xs,
        'sm': OgLRadius.sm,
        'medium': OgLRadius.medium,
        'lg': OgLRadius.lg,
        'large': OgLRadius.large,
        'xl': OgLRadius.xl,
        'pill': OgLRadius.pill,
      };
      for (final MapEntry<String, double> e in radii.entries) {
        expect(
          block.contains('${e.key}: ${_dim(e.value)}'),
          isTrue,
          reason: 'DESIGN.md 圆角令牌缺失：${e.key}',
        );
      }
    });
  });

  group('DESIGN.md · 结构', () {
    test('章节存在且顺序符合 design-md 规范', () {
      const List<String> sections = <String>[
        '## Overview',
        '## Colors',
        '## Typography',
        '## Layout',
        '## Elevation & Depth',
        '## Shapes',
        '## Components',
        "## Do's and Don'ts",
      ];
      int from = 0;
      for (final String section in sections) {
        final int at = spec.indexOf(section, from);
        expect(at >= 0, isTrue, reason: 'DESIGN.md 缺少章节或顺序错误：$section');
        from = at + 1;
      }
    });
  });

  group('UI_SYSTEM_V3.md · 控件清单', () {
    test('覆盖 lib/surface/kit 全部组件文件', () {
      final String doc = File('docs/UI_SYSTEM_V3.md').readAsStringSync();
      final List<String> files = Directory('lib/surface/kit')
          .listSync()
          .whereType<File>()
          .map((File f) => f.uri.pathSegments.last)
          .where((String n) => n.startsWith('kit_') && n.endsWith('.dart'))
          .toList()
        ..sort();
      expect(files, isNotEmpty, reason: 'kit 目录不应为空');
      for (final String name in files) {
        expect(
          doc.contains('lib/surface/kit/$name'),
          isTrue,
          reason: 'UI_SYSTEM_V3.md 缺少组件实现引用：$name（实现必须进规范）',
        );
      }
    });
  });
}
