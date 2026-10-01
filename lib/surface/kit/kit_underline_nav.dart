/// OGL Kit · UnderlineNav —— 对齐 Primer UnderlineNav（水平标签导航）。
///
/// 规格取义（Primer）：
/// - **水平排列、可横向滚动**，不换行、不竖排；
/// - 条目 = 标签（+ 可选前置图标 + 可选计数）；
/// - 选中项：底部 2px 高亮（`borderActive`）+ 字重 600；未选中常规色；
/// - 触摸高度 ≥44；`dense` 用于桌面/密集场景。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// UnderlineNav 条目。
class OgLUnderlineNavItem<T> {
  /// 创建条目。
  const OgLUnderlineNavItem({
    required this.value,
    required this.label,
    this.icon,
    this.count,
  });

  /// 值。
  final T value;

  /// 标签。
  final String label;

  /// 可选前置图标。
  final OgLIconName? icon;

  /// 可选计数（null = 不显示）。
  final int? count;
}

/// Primer 风格的水平下划线导航。
class OgLUnderlineNav<T> extends StatelessWidget {
  /// 创建导航。
  const OgLUnderlineNav({
    required this.items,
    required this.value,
    required this.onChanged,
    this.dense = false,
    super.key,
  });

  /// 条目。
  final List<OgLUnderlineNavItem<T>> items;

  /// 当前值。
  final T value;

  /// 切换回调。
  final ValueChanged<T> onChanged;

  /// 紧凑模式（桌面 / 工具栏）。
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final palette = ogL.palette;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: palette.border, width: tokens.hairline),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (final item in items)
              _OgLUnderlineNavEntry<T>(
                item: item,
                selected: item.value == value,
                dense: dense,
                onTap: () => onChanged(item.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _OgLUnderlineNavEntry<T> extends StatelessWidget {
  const _OgLUnderlineNavEntry({
    required this.item,
    required this.selected,
    required this.dense,
    required this.onTap,
  });

  final OgLUnderlineNavItem<T> item;
  final bool selected;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final palette = ogL.palette;
    final scale = const OgLTypeScale.standard();
    final iconName = item.icon;
    final count = item.count;
    final double vPadTop =
        tokens.space(dense ? OgLSpacing.sm : OgLSpacing.md);
    final double vPadBottom =
        tokens.space(dense ? OgLSpacing.xs : OgLSpacing.sm);
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            alignment: Alignment.center,
            constraints: BoxConstraints(
              minHeight: dense ? tokens.targetSize - 4 : tokens.targetSize,
            ),
            padding: EdgeInsets.only(top: vPadTop, bottom: vPadBottom),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  // Primer：选中下划线用 borderColor-active（发丝字重 2px）。
                  color: selected
                      ? palette.borderActive
                      : const Color(0x00000000),
                  width: 2,
                ),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tokens.space(OgLSpacing.sm + OgLSpacing.xxs),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (iconName != null) ...<Widget>[
                    Icon(
                      ogL.icon(iconName),
                      size: tokens.iconSize(base: 16),
                      color: selected ? palette.text : palette.textDim,
                    ),
                    SizedBox(width: tokens.space(OgLSpacing.xs)),
                  ],
                  Text(
                    item.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: tokens.fontSize(scale.label),
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? palette.text : palette.textDim,
                    ),
                  ),
                  if (count != null) ...<Widget>[
                    SizedBox(width: tokens.space(OgLSpacing.xs)),
                    _OgLNavCountPill(count: count, selected: selected),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OgLNavCountPill extends StatelessWidget {
  const _OgLNavCountPill({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final palette = ogL.palette;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space(OgLSpacing.xs),
      ),
      decoration: BoxDecoration(
        color: selected ? palette.selection : palette.surfaceAlt,
        borderRadius: BorderRadius.circular(tokens.radius(OgLRadius.small)),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: tokens.fontSize(const OgLTypeScale.standard().label) - 2,
          height: 1.5,
          color: palette.textDim,
        ),
      ),
    );
  }
}