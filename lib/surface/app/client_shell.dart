/// OGL 应用 · 客户端主壳（全功能 GitHub 客户端）—— 登录门 + 四页导航。
///
/// 形态自动切换（与全局布局引擎一致）：
/// - 手机：底部栏；桌面窄窗：抽屉；平板 / 桌面：导航轨（可展开标签）。
/// - 页面用 `IndexedStack` 保持状态；账户切换时首页按新 key 重建。
library;

import 'package:flutter/material.dart';

import '../../kernel/kernel.dart';
import '../kit/kit.dart';
import '../layout/adaptive.dart';
import '../pages/dashboard_page.dart';
import '../pages/login_page.dart';
import '../pages/profile_page.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'og_l_app.dart';

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
  int _index = 0;
  bool _checked = false;
  bool _guest = false;
  String? _accountId;

  static const List<String> _titles = <String>['首页', '我的', '设置', '关于'];
  static const List<OgLIconName> _icons = <OgLIconName>[
    OgLIconName.repository,
    OgLIconName.key,
    OgLIconName.settings,
    OgLIconName.info,
  ];

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

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final layout = ogL.layout;
    if (!_checked) {
      return const Scaffold(body: Center(child: OgLSpinner(label: '启动中…')));
    }
    if (_accountId == null && !_guest) {
      return Scaffold(
        body: SafeArea(
          child: _Frame(
            maxWidth: layout.contentMaxWidth,
            gutter: ogL.tokens.space(OgLSpacing.lg),
            child: OgLLoginPage(
              surface: widget.surface,
              onLoggedIn: _check,
              onSkip: () async {
                setState(() => _guest = true);
              },
            ),
          ),
        ),
      );
    }

    final destinations = <Widget>[
      OgLDashboardPage(
        key: ValueKey<String>('dash-${_accountId ?? "guest"}'),
        surface: widget.surface,
      ),
      OgLProfilePage(
        surface: widget.surface,
        onAccountsChanged: _check,
      ),
      OgLSettingsView(surface: widget.surface),
      OgLAboutView(report: widget.report),
    ];
    final body = IndexedStack(index: _index, children: destinations);

    if (layout.navigation.isRail) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              extended: layout.showNavLabels,
              selectedIndex: _index,
              onDestinationSelected: (int value) =>
                  setState(() => _index = value),
              leading: layout.showNavLabels
                  ? _Brand(ogL: ogL)
                  : Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: ogL.tokens.space(OgLSpacing.sm),
                      ),
                      child: Icon(ogL.icon(OgLIconName.code)),
                    ),
              destinations: <NavigationRailDestination>[
                for (var i = 0; i < _icons.length; i++)
                  NavigationRailDestination(
                    icon: Icon(ogL.icon(_icons[i])),
                    label: Text(_titles[i]),
                  ),
              ],
            ),
            VerticalDivider(width: ogL.tokens.hairline),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (layout.navigation == OgLNavKind.bottomBar) {
      return Scaffold(
        appBar: AppBar(title: Text(_titles[_index])),
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (int value) => setState(() => _index = value),
          destinations: <Widget>[
            for (var i = 0; i < _icons.length; i++)
              NavigationDestination(
                icon: Icon(ogL.icon(_icons[i])),
                label: _titles[i],
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_titles[_index])),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.symmetric(
              vertical: ogL.tokens.space(OgLSpacing.sm),
            ),
            children: <Widget>[
              _Brand(ogL: ogL),
              for (var i = 0; i < _icons.length; i++)
                ListTile(
                  leading: Icon(ogL.icon(_icons[i])),
                  title: Text(_titles[i]),
                  selected: i == _index,
                  onTap: () {
                    setState(() => _index = i);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        ),
      ),
      body: body,
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.ogL});

  final OgLTheme ogL;

  @override
  Widget build(BuildContext context) => Padding(
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
      );
}

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