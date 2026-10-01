/// OGL Kit · 容器盒（Box）—— 对齐 Primer Box：
/// 一个带发丝描边、可带标题头的分区容器。
///
/// 页面用它对设置项 / 列表分组，避免"一堵墙式的裸控件"——
/// 这也是"大面积灰色块"的另一半解药：分组靠**描边**，不靠**灰底**。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// 分区容器。
class OgLBox extends StatelessWidget {
  /// 创建容器。
  const OgLBox({
    required this.child,
    this.title,
    this.actions = const <Widget>[],
    this.padded = true,
    super.key,
  });

  /// 内容。
  final Widget child;

  /// 标题（可选；显示在带底色的头部）。
  final String? title;

  /// 头部右侧操作（可选）。
  final List<Widget> actions;

  /// 内容是否加内边距。
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final String? titleText = title;
    final double radius = tokens.radius(OgLRadius.medium);

    Widget content = child;
    if (padded) {
      content = Padding(
        padding: EdgeInsets.all(tokens.space(OgLSpacing.md)),
        child: child,
      );
    }

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ogL.palette.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ogL.palette.border, width: tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (titleText != null)
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space(OgLSpacing.md),
                vertical: tokens.space(OgLSpacing.sm),
              ),
              decoration: BoxDecoration(
                color: ogL.palette.surfaceAlt,
                border: Border(
                  bottom: BorderSide(
                    color: ogL.palette.border,
                    width: tokens.hairline,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      titleText,
                      style: TextStyle(
                        fontSize: tokens.fontSize(scale.title),
                        fontWeight: FontWeight.w600,
                        color: ogL.palette.text,
                      ),
                    ),
                  ),
                  ...actions,
                ],
              ),
            ),
          content,
        ],
      ),
    );
  }
}