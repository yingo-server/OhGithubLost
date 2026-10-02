/// L3 展示级 · 异步四态 → OGL Kit 的**唯一映射点**。
///
/// ## 为什么必须只有一处
/// 历史缺陷（W7 修复）：每个标签各自判断 `state.data == null` 当"加载中"，
/// 而**空结果的 `data` 同样是 null** —— 于是"零议题 / 零发布 / 零分支"
/// 全被当成加载中，页面**永远停在骨架**，用户看到的就是"标签失效"。
///
/// 现在四态只在这里映射一次：
/// ```
/// idle / loading（且无数据） → 骨架
/// failed                     → Banner(danger) + 重试（错误必须可见）
/// empty                      → Blankslate（空要有空的样子）
/// ready                      → 页面内容；若带 refreshError，内容 + 顶部提示
/// ```
/// 页面不再自己判断状态，也就**不可能再判错**。
library;

import 'package:flutter/material.dart';

import '../kit/kit.dart';
import '../theme/icon_pack.dart';
import 'async_state.dart';

/// 把 [OgLAsync] 的四态渲染成 Kit 组件。
///
/// [child] 是"有数据时"的内容；空 / 错 / 载三态由本函数负责。
Widget ogLAsyncView<T>({
  required OgLAsync<T> state,
  required Widget child,
  String errorTitle = '读取失败',
  Future<void> Function()? onRetry,
  OgLIconName emptyIcon = OgLIconName.info,
  String emptyTitle = '暂无内容',
  String? emptyBody,
  Widget? emptyAction,
  int skeletonLines = 5,
}) =>
    OgLStateView(
      loading: state.isFirstLoading,
      error: state.failureMessage,
      errorTitle: errorTitle,
      onRetry: onRetry,
      softError: state.softError,
      isEmpty: state.isEmptyResult,
      emptyIcon: emptyIcon,
      emptyTitle: emptyTitle,
      emptyBody: emptyBody,
      emptyAction: emptyAction,
      skeletonLines: skeletonLines,
      child: child,
    );