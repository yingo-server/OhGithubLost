/// OGL Kit · 开关（ToggleSwitch）—— 对齐 Primer ToggleSwitch：
/// 胶囊轨道 + 圆形滑块，选中时轨道走强调色。
///
/// 为什么不用 Material 的 `Switch`：它是 Material 的视觉语言
/// （水波纹 + 大尺寸 + 材质色），与本仓库"发丝描边 + 直角偏锐"的
/// Primer 语言冲突；自绘一个 40 行的开关反而更一致、也更可控。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// OGL 开关。
class OgLToggleSwitch extends StatelessWidget {
  /// 创建开关。
  const OgLToggleSwitch({
    required this.value,
    this.onChanged,
    this.label,
    this.description,
    super.key,
  });

  /// 当前值。
  final bool value;

  /// 变更回调（为 null 即禁用）。
  final ValueChanged<bool>? onChanged;

  /// 标签（可选）。
  final String? label;

  /// 说明（可选，显示在标签下方）。
  final String? description;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final ValueChanged<bool>? handler = onChanged;
    final bool enabled = handler != null;

    const double trackWidth = 36;
    const double trackHeight = 20;
    const double knobSize = trackHeight - 4;

    final Color track = !enabled
        ? ogL.palette.surfaceAlt
        : (value ? ogL.palette.accent : ogL.palette.surfaceAlt);

    final Widget knob = AnimatedContainer(
      duration: tokens.motion(OgLDuration.base),
      width: knobSize,
      height: knobSize,
      decoration: BoxDecoration(
        color: enabled ? ogL.palette.onAccent : ogL.palette.textFaint,
        shape: BoxShape.circle,
      ),
    );

    final Widget trackWidget = AnimatedContainer(
      duration: tokens.motion(OgLDuration.base),
      width: trackWidth,
      height: trackHeight,
      padding: const EdgeInsets.all(2),
      alignment: value ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(OgLRadius.pill),
        border: Border.all(
          color: ogL.palette.border,
          width: tokens.hairline,
        ),
      ),
      child: knob,
    );

    final String? labelText = label;
    final String? descriptionText = description;

    final Widget row = Row(
      children: <Widget>[
        if (labelText != null)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  labelText,
                  style: TextStyle(
                    fontSize: tokens.fontSize(scale.body),
                    color: ogL.palette.text,
                  ),
                ),
                if (descriptionText != null)
                  Text(
                    descriptionText,
                    style: TextStyle(
                      fontSize: tokens.fontSize(scale.label),
                      color: ogL.palette.textDim,
                    ),
                  ),
              ],
            ),
          ),
        trackWidget,
      ],
    );

    // 整行可点（点标签也能切换）——只让滑块可点是最常见的可访问性缺陷。
    final Widget body = Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.xs)),
      child: row,
    );

    final Widget interactive = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? () => handler(!value) : null,
      child: Semantics(
        container: true,
        checked: value,
        enabled: enabled,
        label: labelText,
        child: body,
      ),
    );

    if (enabled) {
      return interactive;
    }
    return Opacity(opacity: 0.5, child: interactive);
  }
}