/// OGL Kit · 三态视图 —— 把"载 / 空 / 错"收敛成**一处**实现。
///
/// 纪律（第二阶段 W2）：
/// - **载** = 骨架（或调用方自备的 spinner）；
/// - **空** = `OgLBlankslate`（**不许**用 Banner 冒充空态）；
/// - **错** = `OgLBanner(danger)` + 可重试按钮（**错误不许无声消失**）。
///
/// 页面只管"有没有数据、数据是什么"，三态的呈现交给这里 ——
/// 这样"某个页面忘了处理失败"这类缺陷在结构上就不可能发生。
library;

import 'package:flutter/material.dart';

import '../theme/icon_pack.dart';
import 'kit_banner.dart';
import 'kit_blankslate.dart';
import 'kit_button.dart';
import 'kit_skeleton.dart';

/// 三态视图。
class OgLStateView extends StatelessWidget {
  /// 创建三态视图。
  const OgLStateView({
    required this.child,
    required this.isEmpty,
    this.loading = false,
    this.error,
    this.errorTitle = '读取失败',
    this.onRetry,
    this.emptyTitle = '暂无内容',
    this.emptyBody,
    this.emptyIcon = OgLIconName.info,
    this.emptyAction,
    this.skeletonLines = 5,
    super.key,
  });

  /// 有数据时渲染的内容。
  final Widget child;

  /// 数据是否为空。
  final bool isEmpty;

  /// 是否加载中（数据尚未到达且没有错误）。
  final bool loading;

  /// 错误文本（非空即错误态）。
  final String? error;

  /// 错误标题。
  final String errorTitle;

  /// 重试回调（有则渲染"重试"按钮）。
  final Future<void> Function()? onRetry;

  /// 空态标题。
  final String emptyTitle;

  /// 空态说明。
  final String? emptyBody;

  /// 空态图标。
  final OgLIconName emptyIcon;

  /// 空态动作。
  final Widget? emptyAction;

  /// 骨架行数。
  final int skeletonLines;

  @override
  Widget build(BuildContext context) {
    final String? errorText = error;
    final Future<void> Function()? retry = onRetry;
    if (errorText != null) {
      return OgLBanner(
        variant: OgLBannerVariant.danger,
        title: errorTitle,
        text: errorText,
        actions: <Widget>[
          if (retry != null)
            OgLButton(
              label: '重试',
              size: OgLButtonSize.small,
              onPressed: () async {
                await retry();
              },
            ),
        ],
      );
    }
    if (loading) {
      return OgLSkeletonText(lines: skeletonLines);
    }
    if (isEmpty) {
      return OgLBlankslate(
        icon: emptyIcon,
        title: emptyTitle,
        body: emptyBody,
        action: emptyAction,
      );
    }
    return child;
  }
}