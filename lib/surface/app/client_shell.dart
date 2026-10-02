/// L3 展示级 · 客户端主壳（登录门 + 五页导航）。
///
/// ## 形态（Material 3 原生）
/// - 手机（< 600）：`NavigationBar` 底栏；
/// - 平板 / 桌面（≥ 600）：`NavigationRail` 导航轨（≥ 1200 展开标签）。
///
/// ## 两个产品级细节
/// 1. **懒挂载**：只构建访问过的标签页，避免冷启动时五个页面同时发请求；
/// 2. **登录门**：未登录时展示登录页；游客模式可跳过（只读浏览公开内容）。
library;

import 'package:flutter/material.dart';

import '../../kernel/kernel.dart';
import '../pages/about_page.dart';
import '../pages/dashboard_page.dart';
import '../pages/login_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/profile_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../surface_bridge.dart';
import 'error_surface.dart';

/// 壳内的五个页面（导航值）。
enum OgLShellTab {
  /// 首页（我的仓库 / 星标）。
  home,

  /// 搜索（仓库 / 代码）。
  search,

  /// 我的（账户 / Gist / 危险区）。
  profile,

  /// 设置（外观 / 网络 / 账户）。
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
  OgLShellTab _tab = OgLShellTab.home;
  bool _checked = false;
  bool _guest = false;
  String? _accountId;

  /// 是否已完成首次引导（设置在 `runApp` 之前已加载，直接读取即可）。
  bool _onboardingDone = false;

  /// 已经访问过的页面（**懒挂载**）。
  final Set<OgLShellTab> _visited = <OgLShellTab>{OgLShellTab.home};

  @override
  void initState() {
    super.initState();
    _onboardingDone = widget.surface.settings.settings.onboardingDone;
    _check();
  }

  Future<void> _check() async {
    String? accountId;
    try {
      final account = await widget.surface.domain.auth.activeAccount();
      accountId = account?.id;
    } catch (error) {
      // 读取失败不能把应用卡在"启动中"（没有恢复路径）：
      // 按未登录处理并留痕，用户至少能到达登录门 / 游客模式。
      OgLAppLog.instance.add(
        '账户',
        '启动时账户读取失败（按未登录处理）：$error',
        severity: OgLNoticeSeverity.warning,
      );
      accountId = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _accountId = accountId;
      _checked = true;
      if (accountId != null) {
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
        return DashboardPage(
          key: ValueKey<String>('dash-${_accountId ?? 'guest'}'),
          surface: widget.surface,
        );
      case OgLShellTab.search:
        return SearchPage(surface: widget.surface);
      case OgLShellTab.profile:
        return ProfilePage(surface: widget.surface, onAccountsChanged: _check);
      case OgLShellTab.settings:
        return SettingsPage(surface: widget.surface);
      case OgLShellTab.about:
        return AboutPage(report: widget.report);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 首次引导优先于登录门：先让用户知道"这个应用会碰什么、不碰什么"。
    if (!_onboardingDone) {
      return OnboardingPage(
        surface: widget.surface,
        onFinished: () => setState(() => _onboardingDone = true),
      );
    }
    if (!_checked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_accountId == null && !_guest) {
      return LoginPage(
        surface: widget.surface,
        onLoggedIn: _check,
        onSkip: () async {
          setState(() => _guest = true);
        },
      );
    }

    final List<Widget> pages = <Widget>[
      for (final OgLShellTab tab in OgLShellTab.values)
        _visited.contains(tab) ? _pageFor(tab) : const SizedBox.shrink(),
    ];
    final int index = OgLShellTab.values.indexOf(_tab);
    final Widget body = IndexedStack(index: index, children: pages);

    final double width = MediaQuery.sizeOf(context).width;

    // ── 手机：底栏 ──
    if (width < 600) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (int value) =>
              _select(OgLShellTab.values[value]),
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(Icons.folder_outlined),
              selectedIcon: Icon(Icons.folder),
              label: '首页',
            ),
            NavigationDestination(
              icon: Icon(Icons.search),
              label: '搜索',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: '我的',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: '设置',
            ),
            NavigationDestination(
              icon: Icon(Icons.info_outline),
              selectedIcon: Icon(Icons.info),
              label: '关于',
            ),
          ],
        ),
      );
    }

    // ── 平板 / 桌面：导航轨 ──
    final bool extended = width >= 1200;
    return Scaffold(
      body: Row(
        children: <Widget>[
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (int value) =>
                _select(OgLShellTab.values[value]),
            extended: extended,
            labelType:
                extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
            destinations: const <NavigationRailDestination>[
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: Text('首页'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.search),
                label: Text('搜索'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: Text('我的'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('设置'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.info_outline),
                selectedIcon: Icon(Icons.info),
                label: Text('关于'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ],
      ),
    );
  }
}