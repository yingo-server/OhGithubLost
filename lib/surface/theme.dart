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

/// 按明暗编译主题（浅色 / 深色两态；其余交给 Material 3 默认值）。
ThemeData buildOgLTheme(Brightness brightness) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: kOgLSeedColor,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
  );
}
