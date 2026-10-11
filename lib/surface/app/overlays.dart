/// L3 展示级 · **半页以上的动态弹层**（底部面板）的统一定速入口。
///
/// ## 为什么需要它
/// `showModalBottomSheet` 的入场时长由**它自己的动画控制器**决定
/// （Flutter 默认约 250ms），散落在各页调用时无法统一定速；
/// 而底部面板常常占掉半屏以上，属于"大体积动画"，用户对它的**手感**最敏感。
///
/// 这里经 `sheetAnimationStyle` 注入**按动效档位给的时长**（控制器仍归框架
/// 所有 —— 先前自建控制器再在 `pop` 同帧 `dispose`，会把闭场动画掐断：
/// 出场第一帧控制器就被释放，面板直接跳没）：
/// - 档位 `0`（静默）→ 时长 0，面板直接出现（不闪、也不拖）；
/// - 档位 `1 → 3` → 130 / 160 / 200ms（比 Flutter 默认更快）。
///
/// ## 用法
/// ```dart
/// final String? picked = await ogLShowSheet<String>(
///   context: context,
///   isScrollControlled: true,
///   builder: (BuildContext sheetContext) => const _MySheet(),
/// );
/// ```
library;

import 'package:flutter/material.dart';

import 'animations.dart';

/// 按档位加速的底部弹层（半页以上的动态面板）。
Future<T?> ogLShowSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool showDragHandle = true,
  bool isScrollControlled = false,
  bool useSafeArea = false,
}) {
  final Duration duration = OgLAnim.sheetDuration(context);
  // 时长交给框架自带的控制器（`sheetAnimationStyle`）：不再自建
  // `AnimationController`，也就不存在「pop 同帧 dispose 掐断闭场动画」。
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: showDragHandle,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    sheetAnimationStyle: AnimationStyle(
      duration: duration,
      reverseDuration: duration,
    ),
    builder: builder,
  );
}