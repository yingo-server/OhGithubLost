/// OGL Kit · 按钮 —— 规格对齐 Primer Button：
/// 变体（primary / standard / danger / invisible）、尺寸（small / medium）、
/// 加载态、前置图标、禁用态。
///
/// 为什么单独造按钮而不直接用 Material 的：
/// 1. Primer 的主按钮语义是"成功色强调"，与 Material 的主色逻辑不同；
/// 2. 触摸 ≥44 / 桌面 28 的密度纪律应统一由令牌给出；
/// 3. 主题切换（Primer / OGL）时按钮观感应自动一致，不允许页面各自写样式。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

import 'kit_icon.dart';
/// 按钮变体（语义，而非颜色）。
enum OgLButtonVariant {
  /// 主操作（GitHub 语义：成功色强调）。
  primary,

  /// 常规操作（中性底 + 描边）。
  standard,

  /// 危险操作（删除 / 覆盖）。
  danger,

  /// 无框（工具栏 / 行内链接式操作）。
  invisible,
}

/// 按钮尺寸。
enum OgLButtonSize {
  /// 小（行内 / 工具条）。
  small,

  /// 中（默认）。
  medium,
}

/// OGL 按钮。
class OgLButton extends StatelessWidget {
  /// 创建按钮。
  const OgLButton({
    required this.label,
    this.onPressed,
    this.variant = OgLButtonVariant.standard,
    this.size = OgLButtonSize.medium,
    this.leadingIcon,
    this.loading = false,
    super.key,
  });

  /// 文本标签。
  final String label;

  /// 点击回调（`null` = 禁用）。
  final VoidCallback? onPressed;

  /// 变体。
  final OgLButtonVariant variant;

  /// 尺寸。
  final OgLButtonSize size;

  /// 前置图标（语义）。
  final OgLIconName? leadingIcon;

  /// 是否加载中（加载时自动禁用并显示指示器）。
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final palette = ogL.palette;
    final bool enabled = onPressed != null && !loading;
    const transparent = Color(0x00000000);

    final Color bg;
    final Color fg;
    final Color border;
    if (!enabled) {
      if (variant == OgLButtonVariant.invisible) {
        bg = transparent;
        border = transparent;
      } else {
        bg = palette.surfaceAlt;
        border = palette.border;
      }
      fg = palette.textFaint;
    } else if (variant == OgLButtonVariant.primary) {
      bg = palette.success;
      fg = palette.onAccent;
      border = palette.success;
    } else if (variant == OgLButtonVariant.danger) {
      bg = palette.danger;
      fg = palette.onAccent;
      border = palette.danger;
    } else if (variant == OgLButtonVariant.invisible) {
      bg = transparent;
      fg = palette.accent;
      border = transparent;
    } else {
      bg = palette.surfaceAlt;
      fg = palette.text;
      border = palette.border;
    }

    // Primer 对齐（W4）：**视觉高度**回到 Primer 的 28 / 32，
    // 而**命中区**由外层 SizedBox 抬到 ≥44（触摸）——
    // 两者分离，既不像 Material 那样臃肿，也不违反"触摸目标 ≥44"的底线。
    final double height = size == OgLButtonSize.small ? 28 : 32;
    final double hPad =
        size == OgLButtonSize.small ? OgLSpacing.sm : OgLSpacing.lg;
    final scale = const OgLTypeScale.standard();

    final Widget content = loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: Padding(
              padding: EdgeInsets.all(1),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : Text(
            label,
            style: TextStyle(
              fontSize: tokens.fontSize(
                size == OgLButtonSize.small ? scale.label : scale.body,
              ),
              fontWeight: FontWeight.w600,
              color: fg,
              height: 1.2,
            ),
          );

    final OgLIconName? iconName = leadingIcon;
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (iconName != null && !loading) ...<Widget>[
          OgLIcon(name: iconName, size: tokens.iconSize(base: 16), color: fg),
          SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
        ],
        content,
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            height: tokens.targetSize,
            child: Center(
              child: Container(
                height: height,
                padding:
                    EdgeInsets.symmetric(horizontal: ogL.tokens.space(hPad)),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(
                    ogL.tokens.radius(OgLRadius.medium),
                  ),
                  border:
                      Border.all(color: border, width: ogL.tokens.hairline),
                ),
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
