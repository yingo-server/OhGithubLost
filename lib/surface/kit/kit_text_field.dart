/// OGL Kit · 输入框 —— 规格对齐 Primer TextInput / FormControl：
/// 标签、占位、错误文本、聚焦强调描边；触摸态不矮于 44。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

import 'kit_icon.dart';
/// OGL 单行 / 多行输入框。
class OgLTextField extends StatelessWidget {
  /// 创建输入框。
  const OgLTextField({
    this.controller,
    this.label,
    this.hint,
    this.error,
    this.obscure = false,
    this.enabled = true,
    this.maxLines = 1,
    this.leadingIcon,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
    super.key,
  });

  /// 文本控制器。
  final TextEditingController? controller;

  /// 标签（显示在上方）。
  final String? label;

  /// 占位文本。
  final String? hint;

  /// 错误文本（非空时描边与文案转危险色）。
  final String? error;

  /// 是否密文（令牌输入）。
  final bool obscure;

  /// 是否可编辑。
  final bool enabled;

  /// 行数（1 = 单行；密文强制单行）。
  final int maxLines;

  /// 前置语义图标。
  final OgLIconName? leadingIcon;

  /// 变更回调。
  final ValueChanged<String>? onChanged;

  /// 提交回调（回车 / 键盘完成键）—— 搜索这类"敲完就走"的场景必须支持，
  /// 否则用户只能去够按钮。
  final ValueChanged<String>? onSubmitted;

  /// 键盘动作（搜索场景用 `TextInputAction.search`）。
  final TextInputAction? textInputAction;

  /// 是否自动聚焦（进入页面即可输入）。
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final radius = ogL.tokens.radius(OgLRadius.medium);
    final Color stroke = error != null ? palette.danger : palette.border;
    // 聚焦描边同样要"感知错误"：`InputDecoration` 的 hasError 由 `errorText`
    // 决定，而本组件的错误文本是自定义渲染的（不传 errorText）——
    // 因此 `errorBorder` / `focusedErrorBorder` 永远不会被框架采用。
    // 与其留两条死配置，不如把颜色判断直接做进可生效的边框里。
    final Color focusStroke = error != null ? palette.danger : palette.accent;
    final iconName = leadingIcon;

    final Widget field = TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      autofocus: autofocus,
      cursorColor: palette.accent,
      style: TextStyle(
        fontSize: tokens.fontSize(scale.body),
        color: palette.text,
      ),
      decoration: InputDecoration(
        isDense: true,
        // Primer TextInput：**不填充**（bgColor-default + 描边）。
        // 曾经的 `filled: true` + `surfaceAlt` 会把每个输入框画成
        // 一块灰底大板 —— 那正是"大面积灰色块"的主要来源。
        filled: false,
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: tokens.fontSize(scale.body),
          color: palette.textFaint,
        ),
        prefixIcon: iconName == null
            ? null
            : OgLIcon(
                name: iconName,
                size: tokens.iconSize(base: 16),
                color: palette.textDim,
              ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: tokens.space(OgLSpacing.md),
          vertical: tokens.space(OgLSpacing.md),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: stroke, width: tokens.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(
            color: focusStroke,
            width: tokens.stroke(OgLStroke.thin),
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: palette.border, width: tokens.hairline),
        ),
      ),
    );

    final labelText = label;
    final errorText = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (labelText != null) ...<Widget>[
          Text(
            labelText,
            style: TextStyle(
              fontSize: tokens.fontSize(scale.label),
              fontWeight: FontWeight.w500,
              color: palette.textDim,
            ),
          ),
          SizedBox(height: tokens.space(OgLSpacing.xs)),
        ],
        field,
        if (errorText != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.xs)),
          Text(
            errorText,
            style: TextStyle(
              fontSize: tokens.fontSize(scale.label),
              color: palette.danger,
            ),
          ),
        ],
      ],
    );
  }
}