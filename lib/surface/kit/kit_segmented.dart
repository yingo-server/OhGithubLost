/// OGL Kit · SegmentedControl —— 对齐 Primer SegmentedControl：
/// 一组互斥选项（圆角分组 + 发丝描边），选中项以次级面板底高亮。
///
/// 与 UnderlineNav 的分工：**切换“视图范围/模式”用 Segmented（无链接语义），
/// 在“同级页面间导航”用 UnderlineNav。**
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';

/// Segmented 条目。
class OgLSegmentedItem<T> {
  /// 创建条目。
  const OgLSegmentedItem({required this.value, required this.label});

  /// 值。
  final T value;

  /// 标签。
  final String label;
}

/// Primer 风格分段控件。
class OgLSegmented<T> extends StatelessWidget {
  /// 创建分段控件。
  const OgLSegmented({
    required this.items,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// 条目。
  final List<OgLSegmentedItem<T>> items;

  /// 当前值。
  final T value;

  /// 切换回调。
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final palette = ogL.palette;
    final scale = const OgLTypeScale.standard();
    final double height = tokens.pointer == OgLPointerKind.touch
        ? tokens.targetSize
        : tokens.targetSize - 12;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.border, width: tokens.hairline),
        borderRadius: BorderRadius.circular(tokens.radius(OgLRadius.medium)),
      ),
      padding: EdgeInsets.all(tokens.space(OgLSpacing.xxs)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final item in items)
            Semantics(
              selected: item.value == value,
              button: true,
              label: item.label,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(item.value),
                  child: Container(
                    height: height,
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(
                      horizontal: tokens.space(OgLSpacing.md),
                    ),
                    decoration: BoxDecoration(
                      color: item.value == value
                          ? palette.surfaceAlt
                          : const Color(0x00000000),
                      borderRadius: BorderRadius.circular(
                        tokens.radius(OgLRadius.small),
                      ),
                    ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: tokens.fontSize(scale.label),
                        fontWeight: item.value == value
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: item.value == value
                            ? palette.text
                            : palette.textDim,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}