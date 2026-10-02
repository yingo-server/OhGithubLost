/// OGL Kit · 导航外壳组件（底栏 / 导航轨 / 抽屉 / 壳页头）。
///
/// ## 为什么导航也要进 Kit
/// 主壳曾经直接用 Material 的 `AppBar` + `NavigationBar` + `Drawer` + `ListTile`：
/// 结果**页面上下的观感与页面内部完全不是一套** —— 页内是发丝描边 + 令牌间距，
/// 外壳却是 Material 阴影、涟漪、浮起卡片与系统字体权重。
/// 导航是"每屏都看见"的东西，必须和页面同源。
///
/// ## 三条纪律（与 Kit 总则一致）
/// 1. 尺寸 / 颜色 / 动效只从令牌与调色板读取；
/// 2. 触摸目标 ≥ `tokens.targetSize`（≥44）；
/// 3. 选中态用"色彩 + 字重 + 位置指示"三重表达，不依赖单色。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'kit_action_list.dart';
import 'kit_icon.dart';

/// 导航目标（值 + 标题 + 图标）。
class OgLNavDestination<T> {
  /// 创建导航目标。
  const OgLNavDestination({
    required this.value,
    required this.label,
    required this.icon,
  });

  /// 值。
  final T value;

  /// 标题。
  final String label;

  /// 图标（自绘矢量）。
  final OgLIconName icon;
}

/// 应用品牌标记（壳里出现三处，统一成一处实现）。
class OgLBrandMark extends StatelessWidget {
  /// 创建品牌标记。
  const OgLBrandMark({this.compact = false, super.key});

  /// 紧凑模式（只显示图标）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        OgLIcon(
          name: OgLIconName.code,
          size: tokens.iconSize(base: compact ? 22 : 20),
          color: ogL.palette.accent,
        ),
        if (!compact) ...<Widget>[
          SizedBox(width: tokens.space(OgLSpacing.sm)),
          Text(
            'OhGithubLost',
            style: TextStyle(
              fontSize: tokens.fontSize(scale.title),
              fontWeight: FontWeight.w600,
              color: ogL.palette.text,
            ),
          ),
        ],
      ],
    );
  }
}

/// 手机底栏（Primer 风格的"图标 + 标签 + 顶部指示条"）。
class OgLBottomNav<T> extends StatelessWidget {
  /// 创建底栏。
  const OgLBottomNav({
    required this.destinations,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// 目标列表（≤5）。
  final List<OgLNavDestination<T>> destinations;

  /// 当前值。
  final T value;

  /// 切换回调。
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    return Material(
      color: ogL.palette.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: ogL.palette.border, width: tokens.hairline),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: <Widget>[
              for (final OgLNavDestination<T> item in destinations)
                Expanded(
                  child: _BottomNavCell<T>(
                    item: item,
                    selected: item.value == value,
                    tokens: tokens,
                    ogL: ogL,
                    scale: scale,
                    onTap: () => onChanged(item.value),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavCell<T> extends StatelessWidget {
  const _BottomNavCell({
    required this.item,
    required this.selected,
    required this.tokens,
    required this.ogL,
    required this.scale,
    required this.onTap,
  });

  final OgLNavDestination<T> item;
  final bool selected;
  final OgLTokens tokens;
  final OgLTheme ogL;
  final OgLTypeScale scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? ogL.palette.accent : ogL.palette.textDim;
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
            constraints: BoxConstraints(minHeight: tokens.targetSize),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: selected ? ogL.palette.accent : const Color(0x00000000),
                  width: tokens.stroke(OgLStroke.thick),
                ),
              ),
            ),
            padding: EdgeInsets.symmetric(
              vertical: tokens.space(OgLSpacing.xs),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OgLIcon(name: item.icon, size: tokens.iconSize(base: 20), color: fg),
                SizedBox(height: tokens.space(OgLSpacing.xxs)),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tokens.fontSize(scale.label),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 导航轨（平板 / 桌面）：品牌 + 条目，选中项带左侧强调条。
class OgLNavRail<T> extends StatelessWidget {
  /// 创建导航轨。
  const OgLNavRail({
    required this.destinations,
    required this.value,
    required this.onChanged,
    this.extended = false,
    super.key,
  });

  /// 目标列表。
  final List<OgLNavDestination<T>> destinations;

  /// 当前值。
  final T value;

  /// 切换回调。
  final ValueChanged<T> onChanged;

  /// 是否展开标签。
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    return Container(
      width: extended ? tokens.space(OgLSpacing.xxl * 8) : tokens.targetSize + 24,
      decoration: BoxDecoration(
        color: ogL.palette.surface,
        border: Border(
          right: BorderSide(color: ogL.palette.border, width: tokens.hairline),
        ),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(tokens.space(OgLSpacing.md)),
              child: OgLBrandMark(compact: !extended),
            ),
            for (final OgLNavDestination<T> item in destinations)
              _RailCell<T>(
                item: item,
                selected: item.value == value,
                extended: extended,
                tokens: tokens,
                ogL: ogL,
                scale: scale,
                onTap: () => onChanged(item.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailCell<T> extends StatelessWidget {
  const _RailCell({
    required this.item,
    required this.selected,
    required this.extended,
    required this.tokens,
    required this.ogL,
    required this.scale,
    required this.onTap,
  });

  final OgLNavDestination<T> item;
  final bool selected;
  final bool extended;
  final OgLTokens tokens;
  final OgLTheme ogL;
  final OgLTypeScale scale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? ogL.palette.text : ogL.palette.textDim;
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
            constraints: BoxConstraints(minHeight: tokens.targetSize),
            decoration: BoxDecoration(
              color: selected ? ogL.palette.surfaceAlt : null,
              border: Border(
                left: BorderSide(
                  color: selected ? ogL.palette.accent : const Color(0x00000000),
                  width: tokens.stroke(OgLStroke.thick),
                ),
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: tokens.space(OgLSpacing.md),
              vertical: tokens.space(OgLSpacing.xs),
            ),
            child: Row(
              children: <Widget>[
                OgLIcon(name: item.icon, size: tokens.iconSize(base: 20), color: fg),
                if (extended) ...<Widget>[
                  SizedBox(width: tokens.space(OgLSpacing.sm)),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: tokens.fontSize(scale.body),
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: fg,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 窄窗抽屉内容（配合 `Scaffold.drawer`，但**视觉全部由令牌决定**）。
class OgLNavDrawer<T> extends StatelessWidget {
  /// 创建抽屉内容。
  const OgLNavDrawer({
    required this.destinations,
    required this.value,
    required this.onChanged,
    super.key,
  });

  /// 目标列表。
  final List<OgLNavDestination<T>> destinations;

  /// 当前值。
  final T value;

  /// 切换回调。
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    return ColoredBox(
      color: ogL.palette.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.all(tokens.space(OgLSpacing.md)),
              child: const OgLBrandMark(),
            ),
            Divider(
              height: tokens.hairline,
              thickness: tokens.hairline,
              color: ogL.palette.border,
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  vertical: tokens.space(OgLSpacing.xs),
                ),
                child: Column(
                  children: <Widget>[
                    for (final OgLNavDestination<T> item in destinations)
                      OgLActionRow(
                        leading: OgLIcon(
                          name: item.icon,
                          size: tokens.iconSize(base: 20),
                          color: item.value == value
                              ? ogL.palette.accent
                              : ogL.palette.textDim,
                        ),
                        title: item.label,
                        selected: item.value == value,
                        dense: true,
                        onTap: () => onChanged(item.value),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 壳页头（窄窗用）：菜单按钮 + 当前页标题（替代 Material `AppBar`）。
class OgLShellHeader extends StatelessWidget {
  /// 创建壳页头。
  const OgLShellHeader({
    required this.title,
    this.onMenu,
    this.actions = const <Widget>[],
    super.key,
  });

  /// 当前页标题。
  final String title;

  /// 菜单按钮回调（null = 不显示按钮）。
  final VoidCallback? onMenu;

  /// 右侧操作。
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    return Container(
      decoration: BoxDecoration(
        color: ogL.palette.surface,
        border: Border(
          bottom: BorderSide(color: ogL.palette.border, width: tokens.hairline),
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: tokens.space(OgLSpacing.sm),
        vertical: tokens.space(OgLSpacing.xs),
      ),
      child: Row(
        children: <Widget>[
          if (onMenu != null)
            OgLIconButton(
              icon: OgLIconName.list,
              label: '打开导航',
              onTap: onMenu!,
            ),
          SizedBox(width: tokens.space(OgLSpacing.xs)),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: tokens.fontSize(scale.title),
                fontWeight: FontWeight.w600,
                color: ogL.palette.text,
              ),
            ),
          ),
          for (final Widget action in actions) action,
        ],
      ),
    );
  }
}

/// 图标按钮（自绘，触摸目标 ≥44）—— 返回键 / 菜单键 / 页内工具用。
class OgLIconButton extends StatelessWidget {
  const OgLIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final OgLIconName icon;
  final String label;
  final VoidCallback onTap;

  /// 危险语义（删除 / 关闭等）。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Material(
            // 与 OgLButton 同款：借 InkWell 拿 hover / press / focus 反馈。
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              hoverColor: ogL.palette.selection,
              focusColor: ogL.palette.selection,
              highlightColor: ogL.palette.selection,
              child: Container(
                width: tokens.targetSize,
                height: tokens.targetSize,
                alignment: Alignment.center,
                child: OgLIcon(
                  name: icon,
                  size: tokens.iconSize(base: 20),
                  color: danger ? ogL.palette.danger : ogL.palette.textDim,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}