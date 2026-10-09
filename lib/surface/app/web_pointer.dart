/// L3 展示级 · **Web 专属**：指针形态判定（鼠标 / 触控板 vs 触摸）。
///
/// ## 它解决什么
/// Web 版把交互统一到**桌面鼠标**：右键 = 返回（接入与返回键同一条返回链）、
/// 长按左键 = 长按菜单、单击 = 点按。要不要向用户说明这套约定，取决于
/// 当前设备**有没有鼠标** —— 用 `matchMedia('(pointer: fine)')` 判定
/// （精确指针 = 鼠标 / 触控板）。
///
/// ## 单一构建目标（本分支 = 纯 Web）
/// 实现收敛到 `web_pointer_web.dart`，判定失败如实返回"没有鼠标"，
/// 不假装有（说明文字只对真的有鼠标的用户有意义）。
library;

import 'package:flutter/foundation.dart';

import 'web_pointer_web.dart' as impl;

/// 当前是否为"精确指针"设备（鼠标 / 触控板）。
///
/// 非浏览器环境恒为 `false`（本模块整体不生效）。
bool ogLWebFinePointer() {
  if (!kIsWeb) {
    return false;
  }
  return impl.ogLWebFinePointer();
}
