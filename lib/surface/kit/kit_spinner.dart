/// OGL Kit · 加载指示器 —— 对齐 Primer Loading 规范：
/// 小于 1 秒不显示；1–3 秒用不确定态（Spinner）；3 秒以上用确定态（进度条 + 文本）。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// 指示器尺寸。
enum OgLSpinnerSize {
  /// 小（行内 / 按钮内）。
  small,

  /// 中（内容区占位）。
  medium,

  /// 大（整页加载）。
  large,
}

/// 不确定态加载指示器。
class OgLSpinner extends StatelessWidget {
  /// 创建指示器。
  const OgLSpinner({this.size = OgLSpinnerSize.medium, this.label, super.key});

  /// 尺寸。
  final OgLSpinnerSize size;

  /// 伴随文本（可空）。
  final String? label;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final double px = switch (size) {
      OgLSpinnerSize.small => 16,
      OgLSpinnerSize.medium => 24,
      OgLSpinnerSize.large => 32,
    };
    final spinner = SizedBox(
      width: px,
      height: px,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: ogL.palette.accent,
      ),
    );
    final text = label;
    if (text == null) {
      return spinner;
    }
    final scale = const OgLTypeScale.standard();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        spinner,
        SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
        Text(
          text,
          style: TextStyle(
            fontSize: ogL.tokens.fontSize(scale.body),
            color: ogL.palette.textDim,
          ),
        ),
      ],
    );
  }
}

/// 确定态进度条（0–1）。
class OgLProgressBar extends StatelessWidget {
  /// 创建进度条。
  const OgLProgressBar({required this.value, this.showLabel = false, super.key});

  /// 进度（将被夹紧到 `[0, 1]`）。
  final double value;

  /// 是否在右侧显示百分比文本。
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final v = value.clamp(0.0, 1.0);
    final scale = const OgLTypeScale.standard();
    return Row(
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(
              ogL.tokens.radius(OgLRadius.small),
            ),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 6,
              color: ogL.palette.accent,
              backgroundColor: ogL.palette.surfaceAlt,
            ),
          ),
        ),
        if (showLabel) ...<Widget>[
          SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
          Text(
            '${(v * 100).round()}%',
            style: TextStyle(
              fontSize: ogL.tokens.fontSize(scale.label),
              color: ogL.palette.textDim,
            ),
          ),
        ],
      ],
    );
  }
}
