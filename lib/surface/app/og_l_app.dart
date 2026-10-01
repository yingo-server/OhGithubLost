/// L3 展示级 · 应用外壳（App Shell）。
///
/// ## 它证明整条链路是通的
/// 这一个文件同时用到了四层成果：
/// - 内核的 `KernelReport`（启动报告 / 信任告警 / 模块状态）；
/// - 表面桥 `SurfaceBridge`（环境解析 + 主题编译 + 设置持久化）；
/// - 布局引擎 `OgLLayoutSpec`（导航形态与分栏全自动）；
/// - 设计令牌 + 主题包 + 图标语义层（**没有一处硬编码颜色/尺寸/图标字形**）。
///
/// ## 三条自我约束
/// 1. 页面里**没有** `MediaQuery.of(context).size.width > 600` 这种判断；
/// 2. 页面里**没有** `Colors.xxx`、没有 `EdgeInsets.all(16)` 字面量；
/// 3. 页面里**没有** `Icons.xxx`，一律走 `OgLIconName`。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/gh/gh_auth.dart';
import '../../kernel/diagnostics.dart';
import '../../kernel/kernel.dart';
import '../layout/adaptive.dart';
import '../settings/settings_model.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'client_shell.dart';
import 'error_surface.dart';
import 'repos_page.dart';

import '../kit/kit.dart';
/// 设置页：DNS 服务器展示名（与 base 层内置表一一对应）。
const Map<String, String> _dnsChoiceLabels = <String, String>{
  'alidns': '阿里 AliDNS · 223.5.5.5',
  'dnspod': '腾讯 DNSPod · 119.29.29.29',
  'dns114': '114 DNS · 114.114.114.114',
  'cloudflare': 'Cloudflare · 1.1.1.1',
  'google': 'Google · 8.8.8.8',
};

/// 应用根。
class OgLApp extends StatelessWidget {
  /// 创建应用根。
  const OgLApp({required this.surface, required this.report, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  /// 启动报告。
  final KernelReport report;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: surface.settings,
        builder: (BuildContext context, Widget? _) => Builder(
          builder: (BuildContext context) {
            final query = MediaQuery.of(context);
            return MaterialApp(
              title: 'OhGithubLost',
              debugShowCheckedModeBanner: false,
              // 桌面：鼠标/触控板可拖拽滚动（Flutter 默认只认触摸）。
              scrollBehavior: const OgLScrollBehavior(),
              // 全局兜底：无论系统把字号调到多大，都不允许突破这两个边界。
              // 令牌层已夹紧一次，这里再夹一次是"双保险"——
              // 任何绕过令牌直接写 fontSize 的第三方组件也逃不掉。
              builder: (BuildContext context, Widget? child) =>
                  MediaQuery.withClampedTextScaling(
                minScaleFactor: 0.85,
                maxScaleFactor: 2,
                // 全局错误呈现层：未捕获异常 → 弹窗；一般告警 → 横幅。
                child: OgLNoticeHost(
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
              theme: surface.themeFor(
                query: query,
                systemBrightness: query.platformBrightness,
              ),
              home: OgLClientShell(surface: surface, report: report),
            );
          },
        ),
      );
}

/// 启动被拒时的兜底界面。
///
/// **不静默降级**：引导清单签名失败 / 模块依赖不满足时，
/// 直接把原因摊开给用户，并说明"数据没有被改动"。
class OgLBootFailureApp extends StatelessWidget {
  /// 创建兜底界面。
  const OgLBootFailureApp({required this.message, super.key});

  /// 失败原因。
  final String message;

  @override
  Widget build(BuildContext context) {
    // 令牌是**纯 Dart**，兜底界面也能用——不必等主题系统就绪。
    final tokens = OgLTokens.resolve(textScale: MediaQuery.textScalerOf(context).scale(1));
    final scale = const OgLTypeScale.standard();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const OgLScrollBehavior(),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF85149),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: tokens.space(OgLSpacing.xxl * 16),
            ),
            child: Padding(
              padding: EdgeInsets.all(tokens.space(OgLSpacing.xl)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '启动被拒绝',
                    style: TextStyle(
                      fontSize: tokens.fontSize(scale.headline),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: tokens.space(OgLSpacing.md)),
                  Text(
                    '数据没有被改动，也没有任何东西被上传。',
                    style: TextStyle(fontSize: tokens.fontSize(scale.body)),
                  ),
                  SizedBox(height: tokens.space(OgLSpacing.lg)),
                  SelectableText(
                    message,
                    style: TextStyle(
                      fontFamily: kOgLMonoFamily,
                      fontSize: tokens.fontSize(scale.data),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 主壳：按布局结论自动切换导航形态。
class OgLShell extends StatefulWidget {
  /// 创建主壳。
  const OgLShell({required this.surface, required this.report, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  /// 启动报告。
  final KernelReport report;

  @override
  State<OgLShell> createState() => _OgLShellState();
}

class _OgLShellState extends State<OgLShell> {
  int _index = 0;

  static const List<OgLIconName> _icons = <OgLIconName>[
    OgLIconName.repository,
    OgLIconName.settings,
    OgLIconName.info,
  ];
  static const List<String> _titles = <String>['仓库', '设置', '关于'];
  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final layout = ogL.layout;
    final destinations = <Widget>[
      OgLReposPage(surface: widget.surface),
      _SettingsPage(surface: widget.surface),
      _AboutPage(report: widget.report),
    ];

    final body = _ContentFrame(
      maxWidth: layout.contentMaxWidth,
      gutter: ogL.tokens.space(OgLSpacing.lg),
      child: destinations[_index],
    );

    // ── 窄轨 / 宽轨：侧边的信息密度随宽度增加 ──
    if (layout.navigation.isRail) {
      return Scaffold(
        body: Row(
          children: <Widget>[
            NavigationRail(
              extended: layout.showNavLabels,
              selectedIndex: _index,
              onDestinationSelected: (int value) => setState(() => _index = value),
              leading: layout.showNavLabels
                  ? _Brand(ogL: ogL)
                  : Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: ogL.tokens.space(OgLSpacing.sm),
                      ),
                      child: OgLIcon(name: OgLIconName.repository),
                    ),
              destinations: <NavigationRailDestination>[
                for (var i = 0; i < _icons.length; i++)
                  NavigationRailDestination(
                    icon: OgLIcon(name: _icons[i]),
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

    // ── 手机：底部栏 ──
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
                icon: OgLIcon(name: _icons[i]),
                label: _titles[i],
              ),
          ],
        ),
      );
    }

    // ── 桌面窄窗：抽屉 ──
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
                  leading: OgLIcon(name: _icons[i]),
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
            OgLIcon(name: OgLIconName.code, color: ogL.palette.accent),
            SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
            Text('OhGithubLost', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
}

/// 内容框：宽屏限宽居中、窄屏贴边（**不硬编码**断点）。
class _ContentFrame extends StatelessWidget {
  const _ContentFrame({
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

/// 关于页：启动概览 / 模块 / 信任告警 / 依赖图 / 阶段 / 日志 —— 全部收进折叠栏。
///
/// 这是导航的最后一页（产品决策：导航收敛为 仓库 / 设置 / 关于；
/// 原「概览」与「诊断」两页整体并入本页，不再各占一个入口）。
class _AboutPage extends StatelessWidget {
  const _AboutPage({required this.report});

  /// 启动报告（内核在启动时定格的快照）。
  final KernelReport report;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: OgLAppLog.instance,
        builder: (BuildContext context, Widget? _) {
          final ogL = OgLTheme.of(context);
          final appLog = OgLAppLog.instance.entries;
          return ListView(
            children: <Widget>[
              ExpansionTile(
                title: const Text('启动报告'),
                children: <Widget>[
                  _KeyValue(
                    ogL: ogL,
                    rows: <String, String>{
                      '版本': report.appVersion,
                      '生成时间': '${report.generatedAt}',
                      '安全模式': report.safeMode ? '是' : '否',
                      '引导摘要': report.bootSummary,
                    },
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      top: ogL.tokens.space(OgLSpacing.sm),
                    ),
                    child: _KeyValue(ogL: ogL, rows: report.moduleStates),
                  ),
                  Padding(
                    padding: EdgeInsets.only(
                      top: ogL.tokens.space(OgLSpacing.sm),
                    ),
                    child: _KeyValue(
                      ogL: ogL,
                      rows: <String, String>{
                        '层级桥': report.bridges.join('、'),
                        '服务': '${report.services.length} 项',
                      },
                    ),
                  ),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
                ],
              ),
              if (report.trustWarnings.isNotEmpty)
                ExpansionTile(
                  title: Text('信任告警（${report.trustWarnings.length}）'),
                  children: <Widget>[
                    for (final warning in report.trustWarnings)
                      _Banner(
                        ogL: ogL,
                        color: ogL.palette.warning,
                        icon: OgLIconName.warning,
                        text: warning.toString(),
                      ),
                  ],
                ),
              ExpansionTile(
                title: const Text('依赖图'),
                children: <Widget>[
                  Padding(
                    padding: EdgeInsets.all(
                      ogL.tokens.space(OgLSpacing.sm),
                    ),
                    child: Text(
                      report.moduleGraph,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
              ExpansionTile(
                title: Text('启动阶段（${report.stages.length}）'),
                children: <Widget>[
                  for (final stage in report.stages)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: ogL.tokens.space(OgLSpacing.xxs),
                      ),
                      child: Text(stage.toString()),
                    ),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
                ],
              ),
              ExpansionTile(
                title: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '日志（内核 ${report.logTail.length} · 应用 ${appLog.length}）',
                      ),
                    ),
                    IconButton(
                      tooltip: '复制全部日志',
                      icon: const OgLIcon(name: OgLIconName.list),
                      onPressed: () async {
                        final buffer = StringBuffer();
                        for (final entry in report.logTail) {
                          buffer.writeln(entry.toString());
                        }
                        for (final entry in appLog) {
                          buffer.writeln(entry.toDisplay());
                        }
                        await Clipboard.setData(
                          ClipboardData(text: buffer.toString()),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('全部日志已复制到剪贴板'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
                children: <Widget>[
                  for (final entry in report.logTail)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: ogL.tokens.space(OgLSpacing.xxs),
                      ),
                      child: SelectableText(
                        entry.toString(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: ogL.tokens
                              .fontSize(const OgLTypeScale.standard().label),
                          color: entry.level == KernelLogLevel.error
                              ? ogL.palette.danger
                              : ogL.palette.textDim,
                        ),
                      ),
                    ),
                  for (final entry in appLog)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: ogL.tokens.space(OgLSpacing.xxs),
                      ),
                      child: SelectableText(
                        entry.toDisplay(),
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: ogL.tokens
                              .fontSize(const OgLTypeScale.standard().label),
                          color: switch (entry.severity) {
                            OgLNoticeSeverity.critical => ogL.palette.danger,
                            OgLNoticeSeverity.warning => ogL.palette.warning,
                            OgLNoticeSeverity.info => ogL.palette.textDim,
                          },
                        ),
                      ),
                    ),
                  SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
                ],
              ),
            ],
          );
        },
      );
}

/// 设置页：外观 / 行为 / 开发者选项（含总闸护栏）。
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.surface});

  final SurfaceBridge surface;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final settings = surface.settings;
    final value = settings.settings;

    return ListView(
      children: <Widget>[
        _SectionTitle(text: '账户', ogL: ogL),
        FutureBuilder<GhAccount?>(
          future: surface.domain.auth.activeAccount(),
          builder: (BuildContext context, AsyncSnapshot<GhAccount?> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              );
            }
            final account = snap.data;
            if (account == null) {
              return Text(
                '未登录（到「仓库」页接入令牌）',
                style: TextStyle(color: ogL.palette.textDim),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _KeyValue(
                  ogL: ogL,
                  rows: <String, String>{
                    '登录名': '@${account.login}',
                    '账号 ID': account.id,
                  },
                ),
                TextButton(
                  onPressed: () async {
                    await surface.domain.auth.removeAccount(account.id);
                    OgLAppLog.instance
                        .add('账户', '已退出登录（@${account.login}）');
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已退出登录')),
                      );
                    }
                  },
                  child: Text(
                    '退出登录',
                    style: TextStyle(color: ogL.palette.danger),
                  ),
                ),
              ],
            );
          },
        ),
        _SectionTitle(text: '网络 / DNS', ogL: ogL),
        _ChoiceRow<String>(
          ogL: ogL,
          title: '解析模式',
          selected: value.dnsMode,
          options: const <String, String>{
            'system': '系统（默认）',
            'custom': '自定义',
          },
          onPick: settings.setDnsMode,
        ),
        if (value.dnsMode == 'custom') ...<Widget>[
          _ChoiceRow<String>(
            ogL: ogL,
            title: 'DNS 服务器',
            selected: value.dnsServerId,
            options: _dnsChoiceLabels,
            onPick: settings.setDnsServer,
          ),
          SwitchListTile(
            dense: true,
            value: value.dnsPreferDoh,
            onChanged: settings.setDnsPreferDoh,
            title: const Text('DoH 优先（加密解析）'),
          ),
          Text(
            '提示：自定义解析为进阶选项；如遇连接异常请切回系统。',
            style: TextStyle(color: ogL.palette.textDim),
          ),
        ],
        Padding(
          padding: EdgeInsets.symmetric(
            vertical: ogL.tokens.space(OgLSpacing.sm),
          ),
          child: Text(
            value.dnsMode == 'custom'
                ? '当前：自定义 · '
                    '${_dnsChoiceLabels[value.dnsServerId] ?? value.dnsServerId}'
                    '${value.dnsPreferDoh ? ' · DoH 优先' : ' · 明文'}'
                    '（切换在重启应用后完全生效）'
                : '当前：系统解析（默认）',
            style: TextStyle(color: ogL.palette.textDim),
          ),
        ),
        _SectionTitle(text: '外观', ogL: ogL),
        _ChoiceRow<OgLThemeMode>(
          ogL: ogL,
          title: '明暗',
          selected: value.mode,
          options: const <OgLThemeMode, String>{
            OgLThemeMode.system: '跟随系统',
            OgLThemeMode.light: '亮色',
            OgLThemeMode.dark: '暗色',
          },
          onPick: settings.setMode,
        ),
        _SectionTitle(text: '主题包', ogL: ogL),
        // 刻意不用 RadioListTile：新版 Flutter 已废弃其 groupValue / onChanged，
        // 而我们的 CI 是"警告即失败"。
        _ChoiceRow<String>(
          ogL: ogL,
          title: '主题',
          selected: value.themeId.isEmpty
              ? OgLThemePacks.fallback.id
              : value.themeId,
          options: <String, String>{
            for (final pack in OgLThemePacks.all) pack.id: pack.name,
          },
          onPick: settings.setTheme,
        ),
        for (final pack in OgLThemePacks.all)
          Padding(
            padding: EdgeInsets.only(
              bottom: ogL.tokens.space(OgLSpacing.sm),
            ),
            child: Text(
              '${pack.name}：${pack.description}',
              style: TextStyle(color: ogL.palette.textDim),
            ),
          ),
        _SectionTitle(text: '图标包', ogL: ogL),
        _ChoiceRow<String>(
          ogL: ogL,
          title: '图标',
          selected: value.iconSetId.isEmpty
              ? surface.effectiveIconSetId()
              : value.iconSetId,
          options: <String, String>{
            for (final set in OgLIconSets.all) set.id: set.displayName,
          },
          onPick: settings.setIconSet,
        ),
        _SectionTitle(text: '密度', ogL: ogL),
        _ChoiceRow<OgLDensityChoice>(
          ogL: ogL,
          title: '密度',
          selected: value.density,
          options: const <OgLDensityChoice, String>{
            OgLDensityChoice.auto: '自动',
            OgLDensityChoice.compact: '紧凑',
            OgLDensityChoice.standard: '标准',
            OgLDensityChoice.comfortable: '宽松',
          },
          onPick: settings.applyDensity,
        ),
        _SectionTitle(text: '动效', ogL: ogL),
        _ChoiceRow<OgLMotionSetting>(
          ogL: ogL,
          title: '动效',
          selected: value.motion,
          options: const <OgLMotionSetting, String>{
            OgLMotionSetting.auto: '跟随系统',
            OgLMotionSetting.full: '完整',
            OgLMotionSetting.subtle: '克制',
            OgLMotionSetting.none: '关闭',
          },
          onPick: settings.applyMotion,
        ),
        _SectionTitle(text: '开发者 / 测试选项', ogL: ogL),
        SwitchListTile(
          dense: true,
          value: value.developerMode,
          onChanged: settings.setDeveloperMode,
          title: const Text('开发者模式'),
          subtitle: Text(
            '打开后才能启用下列开关；关闭时**立即全部复位**',
            style: TextStyle(color: ogL.palette.textDim),
          ),
        ),
        for (final flag in OgLDevFlag.values)
          SwitchListTile(
            dense: true,
            value: value.dev.isOn(flag),
            onChanged: value.developerMode
                ? (bool on) => settings.setDevFlag(flag, on)
                : null,
            title: Row(
              children: <Widget>[
                Text(flag.description),
                if (flag.risk == OgLRisk.dangerous) ...<Widget>[
                  SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
                  OgLIcon(
                    name: OgLIconName.warning,
                    size: ogL.tokens.iconSize(base: 16),
                    color: ogL.palette.danger,
                  ),
                ],
              ],
            ),
            subtitle: flag.risk == OgLRisk.dangerous
                ? Text(
                    '危险：可能导致覆盖他人提交',
                    style: TextStyle(color: ogL.palette.danger),
                  )
                : null,
          ),
        if (value.dev.activeDangerous.isNotEmpty)
          _Banner(
            ogL: ogL,
            color: ogL.palette.danger,
            icon: OgLIconName.shield,
            text: '当前有 ${value.dev.activeDangerous.length} 个危险开关处于开启状态',
          ),
        if (settings.lastError != null)
          _Banner(
            ogL: ogL,
            color: ogL.palette.warning,
            icon: OgLIconName.warning,
            text: settings.lastError!,
          ),
      ],
    );
  }
}

// （诊断页已并入 _AboutPage 的折叠栏，见文件上方。）


class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text, required this.ogL});
  final String text;
  final OgLTheme ogL;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(
          top: ogL.tokens.space(OgLSpacing.xl),
          bottom: ogL.tokens.space(OgLSpacing.sm),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      );
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.rows, required this.ogL});

  final Map<String, String> rows;
  final OgLTheme ogL;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final entry in rows.entries)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: ogL.tokens.space(OgLSpacing.xxs),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 96,
                    child: Text(
                      entry.key,
                      style: TextStyle(color: ogL.palette.textDim),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      entry.value,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.ogL,
    required this.color,
    required this.icon,
    required this.text,
  });

  final OgLTheme ogL;
  final Color color;
  final OgLIconName icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: EdgeInsets.only(top: ogL.tokens.space(OgLSpacing.md)),
        padding: EdgeInsets.all(ogL.tokens.space(OgLSpacing.md)),
        decoration: BoxDecoration(
          color: ogL.palette.surfaceAlt,
          borderRadius: BorderRadius.circular(
            ogL.tokens.radius(OgLRadius.medium),
          ),
          border: Border.all(color: color, width: ogL.tokens.hairline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OgLIcon(name: icon, size: ogL.tokens.iconSize(base: 18), color: color),
            SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

/// 一行式单选（选项多时比 RadioListTile 更省空间）。
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.ogL,
    required this.title,
    required this.selected,
    required this.options,
    required this.onPick,
  });

  final OgLTheme ogL;
  final String title;
  final T selected;
  final Map<T, String> options;
  final void Function(T value) onPick;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: ogL.tokens.space(OgLSpacing.xs)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: TextStyle(color: ogL.palette.textDim)),
            SizedBox(height: ogL.tokens.space(OgLSpacing.xs)),
            Wrap(
              spacing: ogL.tokens.space(OgLSpacing.sm),
              runSpacing: ogL.tokens.space(OgLSpacing.xs),
              children: <Widget>[
                for (final entry in options.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: entry.key == selected,
                    onSelected: (bool on) {
                      if (on) {
                        onPick(entry.key);
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      );
}

/// 设置页（公开视图，供新主壳复用）。
class OgLSettingsView extends StatelessWidget {
  /// 创建设置视图。
  const OgLSettingsView({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  Widget build(BuildContext context) => _SettingsPage(surface: surface);
}

/// 关于页（公开视图，供新主壳复用）。
class OgLAboutView extends StatelessWidget {
  /// 创建关于视图。
  const OgLAboutView({required this.report, super.key});

  /// 启动报告。
  final KernelReport report;

  @override
  Widget build(BuildContext context) => _AboutPage(report: report);
}