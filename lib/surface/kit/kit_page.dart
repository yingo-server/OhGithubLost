/// OGL Kit · 页面骨架 —— 页头（标题 / 说明 / 操作）。
/// 页面统一从这里开始，避免各页各写一套标题排版。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// 页头。
class OgLPageHeader extends StatelessWidget {
  /// 创建页头。
  const OgLPageHeader({
    required this.title,
    this.description,
    this.actions = const <Widget>[],
    super.key,
  });

  /// 标题。
  final String title;

  /// 说明（次级文本）。
  final String? description;

  /// 右侧操作（按钮等）。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final desc = description;
    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space(OgLSpacing.lg)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: tokens.fontSize(scale.title),
                    fontWeight: FontWeight.w600,
                    color: ogL.palette.text,
                  ),
                ),
                if (desc != null) ...<Widget>[
                  SizedBox(height: tokens.space(OgLSpacing.xs)),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: tokens.fontSize(scale.label),
                      color: ogL.palette.textDim,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actions.isNotEmpty)
            Wrap(
              spacing: tokens.space(OgLSpacing.sm),
              runSpacing: tokens.space(OgLSpacing.sm),
              children: actions,
            ),
        ],
      ),
    );
  }
}