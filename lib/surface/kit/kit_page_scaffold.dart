/// OGL Kit · 页面骨架（Primer 页面结构：页头 + 内容槽 + 边距节律）。
///
/// ## 为什么需要它
/// 商业级界面的第一条要求是"**每一页看起来像同一个产品**"。
/// 页面若各自写 `ListView(padding: EdgeInsets.all(16))`，就会出现：
/// 有的页边距 12、有的 16、有的 24；窄屏贴边、宽屏文字拉成一行；
/// 页头有时在、有时无。把"页面框架"收敛成一个组件后，这些差异
/// 在结构上就不可能出现。
///
/// 规格（严格按令牌，不许写字面量）：
/// - 外边距：`OgLSpacing.lg`（随密度缩放）
/// - 内容最大宽度：840（宽屏居中，避免长行）
/// - 页头：标题（`headline`）+ 说明（`textDim`）+ 操作（自动换行）
/// - 页头与内容之间：`OgLSpacing.lg`
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// 页面骨架。
class OgLPageScaffold extends StatelessWidget {
  /// 创建页面骨架。
  const OgLPageScaffold({
    required this.title,
    required this.child,
    this.description,
    this.actions = const <Widget>[],
    this.leading,
    this.gutter = OgLSpacing.lg,
    this.maxWidth = 840,
    this.onRefresh,
    super.key,
  });

  /// 页面标题。
  final String title;

  /// 页面说明（可为空）。
  final String? description;

  /// 页头操作（按钮 / 图标按钮）。
  final List<Widget> actions;

  /// 标题前导（返回键 / 图标）。
  final Widget? leading;

  /// 内容。
  final Widget child;

  /// 外边距（令牌基线值）。
  final double gutter;

  /// 内容最大宽度（宽屏居中，避免超长行）。
  final double maxWidth;

  /// 下拉刷新（可选）。
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final String? desc = description;
    final double pad = tokens.space(gutter);
    final Widget? lead = leading;

    final Widget header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (lead != null) ...<Widget>[
              Padding(
                padding: EdgeInsets.only(top: tokens.space(OgLSpacing.xxs)),
                child: lead,
              ),
              SizedBox(width: tokens.space(OgLSpacing.xs)),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: tokens.fontSize(scale.headline),
                      fontWeight: FontWeight.w600,
                      color: ogL.palette.text,
                    ),
                  ),
                  if (desc != null && desc.isNotEmpty) ...<Widget>[
                    SizedBox(height: tokens.space(OgLSpacing.xxs)),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: tokens.fontSize(scale.body),
                        color: ogL.palette.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (actions.isNotEmpty) ...<Widget>[
              SizedBox(width: tokens.space(OgLSpacing.sm)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 用索引判断"是否最后一项"：`action != actions.last`
                  // 对两个相同的 const 实例会误判（相等 → 丢间距）。
                  for (int i = 0; i < actions.length; i++) ...<Widget>[
                    actions[i],
                    if (i != actions.length - 1)
                      SizedBox(width: tokens.space(OgLSpacing.xs)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ],
    );

    final Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        header,
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        child,
      ],
    );

    final Widget scroll = ListView(
      // AlwaysScrollable：内容不满一屏时也能下拉（否则 RefreshIndicator
      // 在短页面上"拉不动"——那是用户眼里的"刷新坏了"）。
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: pad,
        vertical: tokens.space(OgLSpacing.lg),
      ),
      children: <Widget>[
        // 宽屏居中 + 限制行宽（商业级阅读体验的底线之一）。
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: body,
          ),
        ),
      ],
    );

    final Future<void> Function()? refresh = onRefresh;
    if (refresh == null) {
      return scroll;
    }
    return RefreshIndicator(
      color: ogL.palette.accent,
      backgroundColor: ogL.palette.surface,
      onRefresh: refresh,
      child: scroll,
    );
  }
}

/// 小节（Primer 页面里的"分组标题 + 内容"）。
///
/// 用法：`OgLSection(title: '基本设置', actions: [...], child: OgLBox(...))`。
/// 与页面骨架的分工：**骨架管"这一页"，小节管"页里的分组"**。
class OgLSection extends StatelessWidget {
  /// 创建小节。
  const OgLSection({
    required this.title,
    required this.child,
    this.description,
    this.actions = const <Widget>[],
    this.spacing = OgLSpacing.sm,
    this.topSpacing = OgLSpacing.lg,
    super.key,
  });

  /// 小节标题。
  final String title;

  /// 小节说明（可选）。
  final String? description;

  /// 标题右侧操作（可选）。
  final List<Widget> actions;

  /// 标题与内容之间的间距（令牌基线值）。
  final double spacing;

  /// 与上一个小节之间的间距（令牌基线值）。
  final double topSpacing;

  /// 内容。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final String? desc = description;
    final List<Widget> acts = actions;

    return Padding(
      padding: EdgeInsets.only(top: tokens.space(topSpacing)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: tokens.fontSize(scale.title),
                    fontWeight: FontWeight.w600,
                    color: ogL.palette.text,
                  ),
                ),
              ),
              for (int i = 0; i < acts.length; i++) ...<Widget>[
                acts[i],
                if (i != acts.length - 1)
                  SizedBox(width: tokens.space(OgLSpacing.xs)),
              ],
            ],
          ),
          if (desc != null && desc.isNotEmpty) ...<Widget>[
            SizedBox(height: tokens.space(OgLSpacing.xxs)),
            Text(
              desc,
              style: TextStyle(
                fontSize: tokens.fontSize(scale.label),
                color: ogL.palette.textDim,
              ),
            ),
          ],
          SizedBox(height: tokens.space(spacing)),
          child,
        ],
      ),
    );
  }
}