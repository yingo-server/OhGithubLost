/// OGL 应用 · 客户端主壳（全功能 GitHub 客户端）—— 登录门 + 五页导航。
///
/// ## 形态自动切换（由布局引擎给出结论，页面自己不知道）
/// - 手机：`OgLBottomNav`（自绘底栏：图标 + 标签 + 顶部指示条）
/// - 平板 / 桌面：`OgLNavRail`（自绘导航轨，可展开标签）
/// - 桌面窄窗：`OgLNavDrawer`（自绘抽屉行）+ `OgLShellHeader`（自绘页头）
///
/// ## 为什么不用 Material 的 AppBar / NavigationBar / Drawer+ListTile
/// 导航是"每屏都看见"的东西：外壳若是 Material 阴影 + 涟漪 + 系统字体权重，
/// 就会和页面内部（发丝描边 + 令牌间距 + 自绘图标）明显不是一套。
/// 现在外壳与页面**同源**：同样的令牌、同样的图标、同样的选中语义。
library;

import 'package:flutter/material.dart';

import '../../kernel/kernel.dart';
import '../kit/kit.dart';
import '../layout/adaptive.dart';
import '../pages/dashboard_page.dart';
import '../pages/login_page.dart';
import '../pages/profile_page.dart';
import '../pages/search_page.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'og_l_app.dart';

/// 壳内的五个页面（导航值）。
enum OgLShellTab {
  /// 首页（仓库 / 星标）。
  home,

  /// 搜索（仓库 / 代码）。
  search,

  /// 我的（账户）。
  profile,

  /// 设置。
  settings,

  /// 关于（启动报告 / 日志）。
  about,
}

/// 客户端主壳（含登录门）。
class OgLClientShell extends StatefulWidget {
  /// 创建主壳。
  const OgLClientShell({
    required this.surface,
    required this.report,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 启动报告（关于页需要）。
  final KernelReport report;

  @override
  State<OgLClientShell> createState() => _OgLClientShellState();
}

class _OgLClientShellState extends State<OgLClientShell> {
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();

  OgLShellTab _tab = OgLShellTab.home;
  bool _checked = false;
  bool _guest = false;
  String? _accountId;

  /// 已经访问过的页面（**懒挂载**）。
  ///
  /// 旧实现把五个页面全部塞进 `IndexedStack`：启动瞬间就会同时构建
  /// 首页 / 搜索 / 我的 / 设置 / 关于（各自可能立刻发请求、建控制器），
  /// 冷启动因此明显变慢。现在只挂载"用过的"页面，其它放占位。
  final Set<OgLShellTab> _visited = <OgLShellTab>{OgLShellTab.home};

  static const List<OgLNavDestination<OgLShellTab>> _nav =
      <OgLNavDestination<OgLShellTab>>[
    OgLNavDestination<OgLShellTab>(
      value: OgLShellTab.home,
      label: '首页',
      icon: OgLIconName.repository,
    ),
    OgLNavDestination<OgLShellTab>(
      value: OgLShellTab.search,
      label: '搜索',
      icon: OgLIconName.search,
    ),
    OgLNavDestination<OgLShellTab>(
      value: OgLShellTab.profile,
      label: '我的',
      icon: OgLIconName.key,
    ),
    OgLNavDestination<OgLShellTab>(
      value: OgLShellTab.settings,
      label: '设置',
      icon: OgLIconName.settings,
    ),
    OgLNavDestination<OgLShellTab>(
      value: OgLShellTab.about,
      label: '关于',
      icon: OgLIconName.info,
    ),
  ];

  static String _labelOf(OgLShellTab tab) => _nav
      .firstWhere((OgLNavDestination<OgLShellTab> item) => item.value == tab)
      .label;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final account = await widget.surface.domain.auth.activeAccount();
    if (!mounted) {
      return;
    }
    setState(() {
      _accountId = account?.id;
      _checked = true;
      if (account != null) {
        _guest = false;
      }
    });
  }

  void _select(OgLShellTab tab) {
    if (tab == _tab) {
      return;
    }
    setState(() {
      _tab = tab;
      _visited.add(tab);
    });
  }

  /// 某一页的实例（懒挂载：只有访问过的 tab 才会被构建）。
  Widget _pageFor(OgLShellTab tab) {
    switch (tab) {
      case OgLShellTab.home:
        return OgLDashboardPage(
          key: ValueKey<String>('dash-${_accountId ?? "guest"}'),
          surface: widget.surface,
        );
      case OgLShellTab.search:
        return OgLSearchPage(surface: widget.surface);
      case OgLShellTab.profile:
        return OgLProfilePage(surface: widget.surface, onAccountsChanged: _check);
      case OgLShellTab.settings:
        return OgLSettingsView(surface: widget.surface);
      case OgLShellTab.about:
        return OgLAboutView(report: widget.report);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final layout = ogL.layout;
    if (!_checked) {
      return const Scaffold(
        body: Center(child: OgLSpinner(label: '启动中…')),
      );
    }
    if (_accountId == null && !_guest) {
      return Scaffold(
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
              child: Padding(
                padding: EdgeInsets.all(ogL.tokens.space(OgLSpacing.lg)),
                child: OgLLoginPage(
                  surface: widget.surface,
                  onLoggedIn: _check,
                  onSkip: () async {
                    setState(() => _guest = true);
                  },
                ),
              ),
            ),
          ),
        ),
      );
    }

    final List<Widget> pages = <Widget>[
      for (final OgLShellTab tab in OgLShellTab.values)
        _visited.contains(tab) ? _pageFor(tab) : const SizedBox.shrink(),
    ];
    final int index = OgLShellTab.values.indexOf(_tab);
    final Widget body = IndexedStack(index: index, children: pages);

    // ── 平板 / 桌面：导航轨 ──
    if (layout.navigation.isRail) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            OgLNavRail<OgLShellTab>(
              destinations: _nav,
              value: _tab,
              extended: layout.showNavLabels,
              onChanged: _select,
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    // ── 手机：底栏（页面自带页头，故壳不再叠一条 AppBar）──
    if (layout.navigation == OgLNavKind.bottomBar) {
      return Scaffold(
        body: body,
        bottomNavigationBar: OgLBottomNav<OgLShellTab>(
          destinations: _nav,
          value: _tab,
          onChanged: _select,
        ),
      );
    }

    // ── 桌面窄窗：自绘页头 + 自绘抽屉 ──
    return Scaffold(
      key: _scaffold,
      drawer: Drawer(
        width: ogL.tokens.space(OgLSpacing.xxl * 9),
        backgroundColor: ogL.palette.surface,
        shape: const RoundedRectangleBorder(),
        child: OgLNavDrawer<OgLShellTab>(
          destinations: _nav,
          value: _tab,
          onChanged: (OgLShellTab tab) {
            _select(tab);
            _scaffold.currentState?.closeDrawer();
          },
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OgLShellHeader(
            title: _labelOf(_tab),
            onMenu: () => _scaffold.currentState?.openDrawer(),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}