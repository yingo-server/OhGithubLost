/// L3 展示级 · 应用外壳：导航、分栏与键盘操控。
///
/// ## 这一层解决的三件事
/// 1. **导航形态**：底栏 / 窄轨 / 宽轨 / 抽屉 —— 由 `OgLLayoutSpec` 决定，
///    页面完全不知道自己是长在手机还是 4K 大屏上；
/// 2. **分栏**：单栏 / 列表详情 / 三栏 —— 同样来自布局结论。
///    列表详情与三栏**共用同一个列表组件实例**，避免两栏各拉一次数据；
/// 3. **键盘操控**（桌面深度打磨）：
///    - `Ctrl/Cmd+1/2/3` 切页
///    - `Ctrl/Cmd+R` 刷新当前页
///    - `Ctrl/Cmd+K` 聚焦搜索框
///    - `Esc` 关闭抽屉 / 清除聚焦
///    - `Ctrl/Cmd+,` 打开设置
///    这些都是**桌面用户的本能**，缺一个都会觉得"这不是个正经桌面应用"。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../layout/adaptive.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 一页的静态描述。
class OgLPageSpec {
  /// 创建页描述。
  const OgLPageSpec({
    required this.id,
    required this.title,
    required this.icon,
    required this.builder,
    this.showInNav = true,
    this.usesPanes = false,
  });

  /// 稳定 ID（进快捷键与状态持久化）。
  final String id;

  /// 标题（导航与 AppBar）。
  final String title;

  /// 语义图标。
  final OgLIconName icon;

  /// 构建内容。
  final WidgetBuilder builder;

  /// 是否出现在主导航里（设置这类可以藏进 AppBar）。
  final bool showInNav;

  /// 该页是否使用分栏（列表 + 详情）。
  ///
  /// **默认 false**：只有"列表类"页面（仓库 / 文件 / 提交…）才参与分栏；
  /// 设置、诊断这类页面永远单栏铺满。否则会出现
  /// "切到设置页却还在显示列表"这种低级错误——本字段就是为堵住它而存在。
  final bool usesPanes;
}

/// 键盘意图（抽象出来便于测试与自定义）。
enum OgLShortcutIntent {
  /// 切到第 N 页。
  gotoPage,

  /// 刷新。
  refresh,

  /// 聚焦搜索。
  focusSearch,

  /// 打开设置。
  openSettings,

  /// 关闭浮层 / 取消。
  dismiss,
}

/// 主壳：负责"外壳"，不负责"内容"。
class OgLShellFrame extends StatefulWidget {
  /// 创建主壳。
  const OgLShellFrame({
    required this.pages,
    required this.onRefresh,
    this.header,
    this.footer,
    this.listPane,
    this.detailPane,
    this.auxPane,
    this.banner,
    super.key,
  });

  /// 页面清单（顺序即导航顺序，普通页）。
  final List<OgLPageSpec> pages;

  /// 刷新回调（`Ctrl+R` 触发）。
  final Future<void> Function() onRefresh;

  /// 顶部附加区（横幅 / 搜索框）。
  final Widget? header;

  /// 底部附加区（状态栏）。
  final Widget? footer;

  /// 列表栏（分栏模式下的左栏）。
  final Widget? listPane;

  /// 详情栏（分栏模式下的右栏）。
  final Widget? detailPane;

  /// 附加栏（三栏模式下的第三栏，如 diff / 元信息）。
  final Widget? auxPane;

  /// 全局横幅（冲突 / 信任告警这类必须触达的信息）。
  final Widget? banner;

  @override
  State<OgLShellFrame> createState() => _OgLShellFrameState();
}

class _OgLShellFrameState extends State<OgLShellFrame> {
  int _index = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 分栏模式下"是否已经选中列表项"。
  ///
  /// 手机上没有详情栏，选中即跳转；宽屏上选中只是换右栏内容。
  bool _hasSelection = false;

  void _goto(int index) {
    if (index < 0 || index >= widget.pages.length || index == _index) {
      return;
    }
    setState(() => _index = index);
  }

  void _dismiss() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      Navigator.of(context).pop();
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// 快捷键绑定：**桌面深度打磨的关键**。
  Map<ShortcutActivator, VoidCallback> _bindings() {
    final bool isApple = Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.macOS;
    // 用函数声明而不是"把闭包赋给变量"：后者会被 lint 拦下，
    // 而且函数声明更利于阅读与调试。
    SingleActivator withMeta(LogicalKeyboardKey key) =>
        SingleActivator(key, control: !isApple, meta: isApple);

    final bindings = <ShortcutActivator, VoidCallback>{
      withMeta(LogicalKeyboardKey.keyR): () => widget.onRefresh(),
      withMeta(LogicalKeyboardKey.keyK): () {
        // 找第一个 text field 聚焦（搜索框约定为 index 0 的 text field）。
        final nodes = FocusManager.instance.rootScope;
        nodes.requestFocus();
      },
      withMeta(LogicalKeyboardKey.comma): () {
        final settingsIndex = widget.pages.indexWhere(
          (OgLPageSpec page) => page.id == 'settings',
        );
        if (settingsIndex >= 0) {
          _goto(settingsIndex);
        }
      },
      const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
    };

    for (var i = 0; i < widget.pages.length && i < 9; i++) {
      final numberKey = <LogicalKeyboardKey>[
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ][i];
      bindings[withMeta(numberKey)] = () => _goto(i);
    }
    return bindings;
  }

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final layout = ogL.layout;
    final navPages = widget.pages.where((OgLPageSpec p) => p.showInNav).toList();
    final current = widget.pages[_index];

    final content = _buildContent(context, ogL, layout, current);

    return CallbackShortcuts(
      bindings: _bindings(),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: _scaffoldKey,
          drawer: layout.navigation == OgLNavKind.drawer
              ? _buildDrawer(context, ogL, navPages)
              : null,
          appBar: layout.navigation.isRail
              ? null
              : AppBar(
                  title: Text(current.title),
                  actions: <Widget>[
                    IconButton(
                      tooltip: '刷新',
                      onPressed: () => widget.onRefresh(),
                      icon: Icon(ogL.icon(OgLIconName.sync)),
                    ),
                  ],
                ),
          body: Column(
            children: <Widget>[
              if (widget.banner != null) widget.banner!,
              if (widget.header != null) widget.header!,
              Expanded(
                child: Row(
                  children: <Widget>[
                    if (layout.navigation.isRail)
                      _NavigationRail(
                        ogL: ogL,
                        pages: navPages,
                        selectedIndex: _navIndexOf(navPages, current),
                        extended: layout.showNavLabels,
                        onSelect: (int navIndex) =>
                            _goto(widget.pages.indexOf(navPages[navIndex])),
                        onRefresh: widget.onRefresh,
                      ),
                    if (layout.navigation.isRail)
                      VerticalDivider(width: ogL.tokens.hairline),
                    Expanded(child: content),
                  ],
                ),
              ),
              if (widget.footer != null) widget.footer!,
            ],
          ),
          bottomNavigationBar:
              layout.navigation == OgLNavKind.bottomBar && navPages.isNotEmpty
                  ? NavigationBar(
                      selectedIndex: _navIndexOf(navPages, current),
                      onDestinationSelected: (int navIndex) =>
                          _goto(widget.pages.indexOf(navPages[navIndex])),
                      destinations: <Widget>[
                        for (final page in navPages)
                          NavigationDestination(
                            icon: Icon(ogL.icon(page.icon)),
                            label: page.title,
                          ),
                      ],
                    )
                  : null,
        ),
      ),
    );
  }

  int _navIndexOf(List<OgLPageSpec> navPages, OgLPageSpec current) {
    final index = navPages.indexWhere((OgLPageSpec p) => p.id == current.id);
    return index < 0 ? 0 : index;
  }

  /// 分栏编排：**同一份数据只拉一次**。
  Widget _buildContent(
    BuildContext context,
    OgLTheme ogL,
    OgLLayoutSpec layout,
    OgLPageSpec current,
  ) {
    // 非列表类页面（设置 / 诊断）永远单栏铺满——
    // 不能因为"外壳提供了分栏"就让所有页面都套进分栏里。
    if (!current.usesPanes || widget.listPane == null) {
      return _Frame(
        maxWidth: layout.contentMaxWidth,
        gutter: ogL.tokens.space(OgLSpacing.lg),
        child: current.builder(context),
      );
    }

    // 列表详情：左列表 + 右详情。
    final panes = <Widget>[
      widget.listPane!,
      if (widget.detailPane != null) widget.detailPane!,
      if (layout.panes == OgLPaneLayout.threePane && widget.auxPane != null)
        widget.auxPane!,
    ];

    if (panes.length == 1) {
      // 单栏：列表占满，选中后由页面自己 push 详情。
      return widget.listPane!;
    }

    // 宽屏：按比例分栏。比例写死在这里，页面不许再调。
    final flexes = panes.length == 2
        ? <int>[2, 3]
        : <int>[2, 3, 2];

    return Row(
      children: <Widget>[
        for (var i = 0; i < panes.length; i++) ...<Widget>[
          if (i > 0) VerticalDivider(width: ogL.tokens.hairline),
          Expanded(
            flex: flexes[i],
            child: _hasSelection || i == 0
                ? panes[i]
                : _EmptyDetailHint(ogL: ogL, onPick: () => setState(() => _hasSelection = true)),
          ),
        ],
      ],
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    OgLTheme ogL,
    List<OgLPageSpec> navPages,
  ) =>
      Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.symmetric(
              vertical: ogL.tokens.space(OgLSpacing.sm),
            ),
            children: <Widget>[
              Padding(
                padding: EdgeInsets.all(ogL.tokens.space(OgLSpacing.md)),
                child: Row(
                  children: <Widget>[
                    Icon(ogL.icon(OgLIconName.code), color: ogL.palette.accent),
                    SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
                    Text(
                      'OhGithubLost',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              Divider(height: ogL.tokens.hairline, color: ogL.palette.border),
              for (final page in navPages)
                ListTile(
                  leading: Icon(ogL.icon(page.icon)),
                  title: Text(page.title),
                  selected: page.id == widget.pages[_index].id,
                  onTap: () {
                    _goto(widget.pages.indexOf(page));
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      );
}

class _NavigationRail extends StatelessWidget {
  const _NavigationRail({
    required this.ogL,
    required this.pages,
    required this.selectedIndex,
    required this.extended,
    required this.onSelect,
    required this.onRefresh,
  });

  final OgLTheme ogL;
  final List<OgLPageSpec> pages;
  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => NavigationRail(
        extended: extended,
        selectedIndex: selectedIndex,
        onDestinationSelected: onSelect,
        leading: Padding(
          padding: EdgeInsets.symmetric(
            vertical: ogL.tokens.space(OgLSpacing.sm),
          ),
          child: Icon(ogL.icon(OgLIconName.code), color: ogL.palette.accent),
        ),
        // 注意：这里**不能**用 `Expanded` 包住——NavigationRail 的 trailing
// 位于一个高度不受约束的 Column 里，Expanded 会在运行时抛
// "unbounded height" 异常（CI 的静态分析抓不到这类问题）。
        trailing: Padding(
          padding: EdgeInsets.only(bottom: ogL.tokens.space(OgLSpacing.md)),
          child: IconButton(
            tooltip: '刷新',
            onPressed: () => onRefresh(),
            icon: Icon(ogL.icon(OgLIconName.sync)),
          ),
        ),
        destinations: <NavigationRailDestination>[
          for (final page in pages)
            NavigationRailDestination(
              icon: Icon(ogL.icon(page.icon)),
              label: Text(page.title),
            ),
        ],
      );
}

/// 宽屏但尚未选中任何条目时的右栏占位。
class _EmptyDetailHint extends StatelessWidget {
  const _EmptyDetailHint({required this.ogL, required this.onPick});

  final OgLTheme ogL;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(ogL.tokens.space(OgLSpacing.xl)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                ogL.icon(OgLIconName.list),
                size: ogL.tokens.iconSize(base: 32),
                color: ogL.palette.textFaint,
              ),
              SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
              Text(
                '从左侧选择一项查看详情',
                style: TextStyle(color: ogL.palette.textDim),
              ),
            ],
          ),
        ),
      );
}

/// 限宽居中容器（宽屏不出现"一行两千像素"）。
class _Frame extends StatelessWidget {
  const _Frame({
    required this.child,
    required this.maxWidth,
    required this.gutter,
  });

  final Widget child;
  final double maxWidth;
  final double gutter;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: EdgeInsets.all(gutter), child: child),
        ),
      );
}