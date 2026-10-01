/// OGL Kit · 空态（Blankslate）—— 对齐 Primer Blankslate：
/// 语义图标 + 标题 + 一句话说明 + 可选下一步动作。
///
/// 纪律：**空态不许用 Banner 冒充** —— 那会渲染成一大块半透明色块，
/// 既是"大面积灰色块"的来源，也让用户误以为出了问题。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 空白板（空态）。
class OgLBlankslate extends StatelessWidget {
  /// 创建空态。
  const OgLBlankslate({
    required this.title,
    this.body,
    this.icon = OgLIconName.info,
    this.action,
    this.compact = false,
    super.key,
  });

  /// 标题（一句话说清"这里为什么是空的"）。
  final String title;

  /// 补充说明（可选）。
  final String? body;

  /// 语义图标。
  final OgLIconName icon;

  /// 下一步动作（可选）。
  final Widget? action;

  /// 紧凑形态（嵌在列表里时用）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final String? bodyText = body;
    final Widget? actionWidget = action;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space(OgLSpacing.lg),
        vertical: tokens.space(compact ? OgLSpacing.md : OgLSpacing.xl),
      ),
      // Primer Blankslate：**不做填充**，只用一层发丝描边把区域圈出来。
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(tokens.radius(OgLRadius.medium)),
        border: Border.all(color: ogL.palette.border, width: tokens.hairline),
      ),
      child: Column(
        children: <Widget>[
          Icon(
            ogL.icon(icon),
            size: tokens.iconSize(base: compact ? 20 : 24),
            color: ogL.palette.textFaint,
          ),
          SizedBox(height: tokens.space(OgLSpacing.sm)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: tokens.fontSize(scale.title),
              fontWeight: FontWeight.w600,
              color: ogL.palette.text,
            ),
          ),
          if (bodyText != null) ...<Widget>[
            SizedBox(height: tokens.space(OgLSpacing.xs)),
            Text(
              bodyText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: tokens.fontSize(scale.body),
                color: ogL.palette.textDim,
              ),
            ),
          ],
          if (actionWidget != null) ...<Widget>[
            SizedBox(height: tokens.space(OgLSpacing.md)),
            actionWidget,
          ],
        ],
      ),
    );
  }
}