/// OGL Kit · 标签 —— Label / CounterLabel / StateLabel（对齐 Primer 语义色）。
///
/// 标签不是装饰：它承担"状态 → 颜色"的唯一映射，
/// 页面不允许自己选红绿（状态色收敛到调色板）。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// 标签语义。
enum OgLLabelVariant {
  /// 中性（默认灰）。
  neutral,

  /// 强调蓝。
  accent,

  /// 成功绿。
  success,

  /// 注意黄。
  attention,

  /// 危险红。
  danger,

  /// 完成紫（映射到强调色）。
  done,
}

/// 小标签（描边胶囊）。
class OgLLabel extends StatelessWidget {
  /// 创建标签。
  const OgLLabel({
    required this.text,
    this.variant = OgLLabelVariant.neutral,
    super.key,
  });

  /// 文本。
  final String text;

  /// 语义。
  final OgLLabelVariant variant;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final Color color = _colorFor(ogL, variant);
    final scale = const OgLTypeScale.standard();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ogL.tokens.space(OgLSpacing.sm),
        vertical: ogL.tokens.space(OgLSpacing.xxs),
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius:
            BorderRadius.circular(ogL.tokens.radius(OgLRadius.small)),
        border: Border.all(color: color.withAlpha(77), width: ogL.tokens.hairline),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: ogL.tokens.fontSize(scale.label),
          fontWeight: FontWeight.w500,
          color: color,
          height: 1.3,
        ),
      ),
    );
  }
}

/// 计数标签（GitHub 通知 / Issue 列表的"数字泡"）。
class OgLCounterLabel extends StatelessWidget {
  /// 创建计数标签。
  const OgLCounterLabel({
    required this.count,
    this.variant = OgLLabelVariant.neutral,
    super.key,
  });

  /// 数量。
  final int count;

  /// 语义。
  final OgLLabelVariant variant;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final Color color = _colorFor(ogL, variant);
    final scale = const OgLTypeScale.standard();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ogL.tokens.space(OgLSpacing.sm),
        vertical: ogL.tokens.space(OgLSpacing.xxs),
      ),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(ogL.tokens.radius(OgLRadius.pill)),
        border: Border.all(color: color.withAlpha(77), width: ogL.tokens.hairline),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: ogL.tokens.fontSize(scale.label),
          fontWeight: FontWeight.w600,
          color: color,
          height: 1.3,
        ),
      ),
    );
  }
}

/// 状态标签（Issue / PR：open / closed / done）。
enum OgLStateKind {
  /// 打开中。
  open,

  /// 已关闭。
  closed,

  /// 已完成 / 已合并。
  done,
}

/// 状态标签。
class OgLStateLabel extends StatelessWidget {
  /// 创建状态标签。
  const OgLStateLabel({required this.kind, required this.text, super.key});

  /// 状态。
  final OgLStateKind kind;

  /// 文本（如 "Open" / "Merged"）。
  final String text;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final Color color = switch (kind) {
      OgLStateKind.open => ogL.palette.success,
      OgLStateKind.closed => ogL.palette.danger,
      OgLStateKind.done => ogL.palette.accent,
    };
    final scale = const OgLTypeScale.standard();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ogL.tokens.space(OgLSpacing.sm),
        vertical: ogL.tokens.space(OgLSpacing.xxs),
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(ogL.tokens.radius(OgLRadius.pill)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: ogL.tokens.fontSize(scale.label),
          fontWeight: FontWeight.w600,
          color: ogL.palette.onAccent,
          height: 1.3,
        ),
      ),
    );
  }
}

Color _colorFor(OgLTheme ogL, OgLLabelVariant variant) => switch (variant) {
      OgLLabelVariant.neutral => ogL.palette.textDim,
      OgLLabelVariant.accent => ogL.palette.accent,
      OgLLabelVariant.success => ogL.palette.success,
      OgLLabelVariant.attention => ogL.palette.warning,
      OgLLabelVariant.danger => ogL.palette.danger,
      OgLLabelVariant.done => ogL.palette.accent,
    };
