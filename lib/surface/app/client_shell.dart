/// L3 展示级 · 客户端主壳（登录门 + 四页导航）。
///
/// ## 形态（Material 3 原生）
/// - 手机（< 600）：`NavigationBar` 底栏；
/// - 平板 / 桌面（≥ 600）：`NavigationRail` 导航轨（≥ 1200 展开标签）。
///
/// ## 两个产品级细节
/// 1. **懒挂载**：只构建访问过的标签页，避免冷启动时多个页面同时发请求；
/// 2. **登录门**：未登录时展示登录页；游客模式可跳过（只读浏览公开内容）。
///
/// "关于"不再是独立标签，而是设置页内的全屏子页面（见 [SettingsPage]）。
library;

import 'package:flutter/material.dart';

import '../../kernel/kernel.dart';
import '../i18n/og_l_i18n.dart';
import '../pages/dashboard_page.dart';
import '../pages/login_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/profile_page.dart';
import '../pages/search_page.dart';
import '../pages/settings_page.dart';
import '../surface_bridge.dart';
import '../types.dart';
import 'animations.dart';
import 'error_surface.dart';

/// 壳内的四个页面（导航值）。
enum OgLShellTab {
  /// 首页（我的仓库 / 星标）。
  home,

  /// 搜索（仓库 / 代码）。
  search,

  /// 我的（账户 / Gist / 危险区）。
  profile,

  /// 设置（外观 / 网络 / 账户 / 关于）。
  settings,
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
    // ★ 认证是全局可观察状态：登录 / 失效 / 切号 / 登出都自动联动。
    widget.surface.domain.auth.addListener(_onAuthChanged);
    _check();
  }

  @override
  void dispose() {
    widget.surface.domain.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) {
      _check();
    }
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
        return SearchPage(
          key: ValueKey<String>('search-${_accountId ?? 'guest'}'),
          surface: widget.surface,
        );
      case OgLShellTab.profile:
        return ProfilePage(surface: widget.surface, onAccountsChanged: _check);
      case OgLShellTab.settings:
        return SettingsPage(surface: widget.surface, report: widget.report);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        // 统一接管返回键：二级页 / 弹窗 / 抽屉 / tab / 退出（见 [_handleBack]）。
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (didPop) {
            return;
          }
          unawaited(_handleBack());
        },
        child: _buildShell(context),
      );

  /// 原 shell 构建（被 [build] 包在 `PopScope` 里）。
  Widget _buildShell(BuildContext context) {
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
    if ((_accountId == null ||
        widget.surface.domain.auth.state == GhAuthState.expired) &&
        !_guest) {
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
    // R7：页面切换加**左右滑动**入场动画（保留 IndexedStack 的状态与懒挂载）。
    // 关闭动画（档位 0 / 系统减少动效）时瞬时切换。
    final Widget body = _OgLShellSlide(
      index: index,
      child: IndexedStack(index: index, children: pages),
    );

    final double width = MediaQuery.sizeOf(context).width;

    // ── 手机：底栏 ──
    if (width < 600) {
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (int value) =>
              _select(OgLShellTab.values[value]),
          destinations: <NavigationDestination>[
            NavigationDestination(
              icon: const Icon(Icons.folder_outlined),
              selectedIcon: const Icon(Icons.folder),
              label: OgLI18n.instance.t('shell', 'home'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.search),
              label: OgLI18n.instance.t('shell', 'search'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: OgLI18n.instance.t('shell', 'profile'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings),
              label: OgLI18n.instance.t('shell', 'settings'),
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
            destinations: <NavigationRailDestination>[
              NavigationRailDestination(
                icon: const Icon(Icons.folder_outlined),
                selectedIcon: const Icon(Icons.folder),
                label: Text(OgLI18n.instance.t('shell', 'home')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.search),
                label: Text(OgLI18n.instance.t('shell', 'search')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.person_outline),
                selectedIcon: const Icon(Icons.person),
                label: Text(OgLI18n.instance.t('shell', 'profile')),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: Text(OgLI18n.instance.t('shell', 'settings')),
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

/// R7：底部/侧边导航切换时的**左右滑动**入场。
///
/// 保留 [IndexedStack] 作为 child（状态与懒挂载不变），只在切换那一刻
/// 对新页面做一次轻微水平位移 + 淡出过渡。关闭动画时（档位 0 / 系统减少动效）
/// 不做任何位移——直接瞬时切换。
class _OgLShellSlide extends StatefulWidget {
  const _OgLShellSlide({required this.index, required this.child});

  /// 当前索引（变化即触发一次入场）。
  final int index;

  /// 页面内容。
  final Widget child;

  @override
  State<_OgLShellSlide> createState() => _OgLShellSlideState();
}

class _OgLShellSlideState extends State<_OgLShellSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: 1,
  );

  /// 起始水平位移（正=从右进入，负=从左进入）。
  double _from = 0;

  @override
  void didUpdateWidget(covariant _OgLShellSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) {
      return;
    }
    final bool animate = OgLAnim.enabled(context);
    if (!animate) {
      _from = 0;
      _controller.value = 1;
      return;
    }
    _from = widget.index > oldWidget.index ? 0.06 : -0.06;
    _controller.duration = OgLAnim.medium(context);
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        // RepaintBoundary：切 tab 时只做图层位移、不重绘整页
        //（此前"整棵页面树每帧重绘"正是切换卡顿的主因）。
        builder: (BuildContext context, Widget? child) => RepaintBoundary(
          child: FractionalTranslation(
            translation: Offset(_from * (1 - _controller.value), 0),
            child: child,
          ),
        ),
        child: widget.child,
      );
}