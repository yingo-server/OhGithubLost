/// L3 展示级 · 主题编译（Material 3 直出，保守设计）。
///
/// ## 为什么这么小
/// 旧展示层维护了一整套自研设计系统（令牌 / 主题包 / 图标包 / 自适应引擎）。
/// 重写后一律直接使用 **Flutter 框架自带的 Material 3**：
/// - 颜色：`ColorScheme.fromSeed`（单一种子色，浅 / 深两态）；
/// - 组件：全部使用框架组件（Button / ListTile / NavigationBar…）；
/// - 图标：全部使用 `Icons.*` 字形。
///
/// 这里只保留**唯一一次**主题编译，页面不写任何色值。
library;

import 'package:flutter/material.dart';

/// 品牌种子色（GitHub 蓝）。
const Color kOgLSeedColor = Color(0xFF0969DA);

/// 可选主题色（id → 颜色 + 展示名）。
///
/// 集中在此，设置页只按 id 取用；`settings.dart` 只存 id，
/// 不依赖 Flutter —— 保持数据层与展示层解耦。
const Map<String, Color> kOgLSeedColors = <String, Color>{
  'github': kOgLSeedColor,
  'ocean': Color(0xFF0B6E99),
  'forest': Color(0xFF2E7D32),
  'grape': Color(0xFF7B3FE4),
  'sunset': Color(0xFFE06C00),
  'rose': Color(0xFFC2185B),
  'slate': Color(0xFF546E7A),
};

/// 主题色展示名。
const Map<String, String> kOgLSeedColorLabels = <String, String>{
  'github': 'GitHub 蓝',
  'ocean': '深海',
  'forest': '森林',
  'grape': '葡萄紫',
  'sunset': '日落橙',
  'rose': '玫瑰红',
  'slate': '石板灰',
};

/// 按 id 取主题色（未知 id 回落品牌色）。
Color ogLSeedColorOf(String id) => kOgLSeedColors[id] ?? kOgLSeedColor;

/// 按 id 取主题色名（未知 id 回落首个）。
String ogLSeedColorLabel(String id) =>
    kOgLSeedColorLabels[id] ?? kOgLSeedColorLabels.values.first;

/// 界面密度（`compact` → 更紧凑）。
VisualDensity ogLDensityOf(String id) => id == 'compact'
    ? VisualDensity.compact
    : VisualDensity.standard;

/// 按明暗 + 主题色 + 密度编译主题（浅色 / 深色两态；其余交给 Material 3 默认值）。
ThemeData buildOgLTheme(
  Brightness brightness, {
  Color seedColor = kOgLSeedColor,
  VisualDensity density = VisualDensity.standard,
}) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    visualDensity: density,
  );
}
