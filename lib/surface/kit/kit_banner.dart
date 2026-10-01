/// OGL Kit · 横幅 / Flash —— 对齐 Primer Banner：
/// info / success / warning / danger 四种语义；图标 + 标题 + 文本 + 可选操作。
/// 用于页面级状态与"必须触达"的提示（信任告警、冲突、网络策略变化…）。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 横幅语义。
enum OgLBannerVariant {
  /// 信息。
  info,

  /// 成功。
  success,

  /// 警告。
  warning,

  /// 危险。
  danger,
}

/// OGL 横幅。
class OgLBanner extends StatelessWidget {
  /// 创建横幅。
  const OgLBanner({
    required this.text,
    this.variant = OgLBannerVariant.info,
    this.title,
    this.actions = const <Widget>[],
    super.key,
  });

  /// 正文。
  final String text;

  /// 语义。
  final OgLBannerVariant variant;

  /// 可选标题（加粗一行）。
  final String? title;

  /// 可选操作（按钮等，横排在正文下方）。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    final Color color = switch (variant) {
      OgLBannerVariant.info => palette.info,
      OgLBannerVariant.success => palette.success,
      OgLBannerVariant.warning => palette.warning,
      OgLBannerVariant.danger => palette.danger,
    };
    final OgLIconName iconName = switch (variant) {
      OgLBannerVariant.info => OgLIconName.info,
      OgLBannerVariant.success => OgLIconName.success,
      OgLBannerVariant.warning => OgLIconName.warning,
      OgLBannerVariant.danger => OgLIconName.error,
    };
    final scale = const OgLTypeScale.standard();
    final heading = title;

    return Container(
      padding: EdgeInsets.all(ogL.tokens.space(OgLSpacing.md)),
      decoration: BoxDecoration(
        // Primer Banner：底色用**面板色**（surface），语义色只出现在
        // 图标 / 边框上。旧实现用 `color.withAlpha(26)` 铺满整条，
        // 在暗色主题下会变成一大块灰蓝色板（"大面积灰色块"来源之二）。
        color: ogL.palette.surface,
        borderRadius:
            BorderRadius.circular(ogL.tokens.radius(OgLRadius.medium)),
        border: Border.all(
          color: color.withAlpha(102),
          width: ogL.tokens.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            ogL.icon(iconName),
            size: ogL.tokens.iconSize(base: 16),
            color: color,
          ),
          SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (heading != null) ...<Widget>[
                  Text(
                    heading,
                    style: TextStyle(
                      fontSize: ogL.tokens.fontSize(scale.title),
                      fontWeight: FontWeight.w600,
                      color: ogL.palette.text,
                    ),
                  ),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.xxs)),
                ],
                Text(
                  text,
                  style: TextStyle(
                    fontSize: ogL.tokens.fontSize(scale.body),
                    color: ogL.palette.text,
                  ),
                ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(
                      top: ogL.tokens.space(OgLSpacing.sm),
                    ),
                    child: Wrap(
                      spacing: ogL.tokens.space(OgLSpacing.sm),
                      runSpacing: ogL.tokens.space(OgLSpacing.sm),
                      children: actions,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
