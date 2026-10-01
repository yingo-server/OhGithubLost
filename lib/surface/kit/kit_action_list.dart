/// OGL Kit · 列表行 —— 规格对齐 Primer ActionList：
/// 前导（图标 / 头像）+ 主 / 副文本 + 尾部；整行可点；选中态走强调底。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 列表行。
class OgLActionRow extends StatelessWidget {
  /// 创建列表行。
  const OgLActionRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.selected = false,
    this.dense = false,
    this.showChevron = false,
    super.key,
  });

  /// 主文本。
  final String title;

  /// 副文本。
  final String? subtitle;

  /// 前导组件（图标 / 头像）。
  final Widget? leading;

  /// 尾部组件（标签 / 计数 / 自定义）。
  final Widget? trailing;

  /// 点击回调。
  final VoidCallback? onTap;

  /// 选中态。
  final bool selected;

  /// 紧凑行（44 高）。
  final bool dense;

  /// 尾部箭头（桌面"可进入"提示）。
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final double minHeight = dense ? 44 : 56;
    final sub = subtitle;
    final Widget? tail = trailing;
    final lead = leading;
    final bool enabled = onTap != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: minHeight),
          padding: EdgeInsets.symmetric(
            horizontal: tokens.space(OgLSpacing.md),
            vertical: tokens.space(OgLSpacing.xs),
          ),
          color: selected ? ogL.palette.selection : const Color(0x00000000),
          child: Row(
            children: <Widget>[
              if (lead != null) ...<Widget>[
                lead,
                SizedBox(width: tokens.space(OgLSpacing.md)),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: tokens.maxLinesHint,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: tokens.fontSize(scale.body),
                        fontWeight: FontWeight.w500,
                        color: ogL.palette.text,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        maxLines: tokens.maxLinesHint,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: tokens.fontSize(scale.label),
                          color: ogL.palette.textDim,
                        ),
                      ),
                  ],
                ),
              ),
              if (tail != null) ...<Widget>[
                SizedBox(width: tokens.space(OgLSpacing.sm)),
                tail,
              ],
              if (showChevron && enabled) ...<Widget>[
                SizedBox(width: tokens.space(OgLSpacing.sm)),
                Icon(
                  ogL.icon(OgLIconName.chevronRight),
                  size: tokens.iconSize(base: 16),
                  color: ogL.palette.textFaint,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}