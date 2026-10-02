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
import '../kit/kit.dart';
import '../settings/settings_model.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'client_shell.dart';
import 'error_surface.dart';

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
          seedColor: kOgLDangerDark,
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

/// 关于页：启动报告 / 模块 / 信任链 / 依赖图 / 阶段 / 日志。
///
/// 这是导航的最后一页（产品决策：导航收敛为 仓库 / 设置 / 关于；
/// 原「概览」与「诊断」两页整体并入本页，不再各占一个入口）。
///
/// ## 纪律
/// - 页面骨架走 `OgLPageScaffold`（旧实现是裸 `ListView` + Material `ExpansionTile`）；
/// - 折叠不再交给 Material：**关键信息默认展开**（版本 / 信任链 / 存储接线），
///   只有"可能很长"的两块（依赖图 / 日志）做截断显示 + 明确的截断说明；
/// - 日志必须能一键复制（用户反馈问题时最需要的东西）。
class _AboutPage extends StatelessWidget {
  const _AboutPage({required this.report});

  /// 启动报告（内核在启动时定格的快照）。
  final KernelReport report;

  /// 日志尾部最多显示多少条（超出的仍会被"复制全部"带走）。
  static const int _logTailShown = 80;

  Future<void> _copyAll(BuildContext context, List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${lines.length} 行日志到剪贴板')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: OgLAppLog.instance,
        builder: (BuildContext context, Widget? _) {
          final ogL = OgLTheme.of(context);
          final OgLTokens tokens = ogL.tokens;
          final OgLTypeScale scale = const OgLTypeScale.standard();
          final appLog = OgLAppLog.instance.entries;
          final List<String> kernelLines = report.logTail
              .map((KernelLogEntry entry) => entry.toString())
              .toList();
          final List<String> appLines =
              appLog.map((OgLNotice notice) => notice.toDisplay()).toList();
          final List<String> allLines = <String>[...kernelLines, ...appLines];
          final int shown =
              allLines.length > _logTailShown ? _logTailShown : allLines.length;
          final List<String> tail = allLines.sublist(allLines.length - shown);

          return OgLPageScaffold(
            title: '关于',
            description: '启动报告 / 信任链 / 依赖图 / 日志',
            actions: <Widget>[
              OgLButton(
                label: '复制全部日志',
                variant: OgLButtonVariant.invisible,
                leadingIcon: OgLIconName.list,
                onPressed: () async {
                  await _copyAll(context, allLines);
                },
              ),
            ],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                OgLSection(
                  title: '启动报告',
                  topSpacing: 0,
                  description: report.safeMode
                      ? '安全模式：是（部分能力被关闭）'
                      : '安全模式：否（全部能力可用）',
                  child: OgLBox(
                    padded: false,
                    child: Column(
                      children: <Widget>[
                        OgLActionRow(
                          leading: OgLIcon(
                            name: OgLIconName.info,
                            size: tokens.iconSize(base: 18),
                            color: ogL.palette.textDim,
                          ),
                          title: '版本',
                          subtitle: report.appVersion,
                          dense: true,
                        ),
                        OgLActionRow(
                          leading: OgLIcon(
                            name: OgLIconName.clock,
                            size: tokens.iconSize(base: 18),
                            color: ogL.palette.textDim,
                          ),
                          title: '生成时间',
                          subtitle: '${report.generatedAt}',
                          dense: true,
                        ),
                        OgLActionRow(
                          leading: OgLIcon(
                            name: OgLIconName.shield,
                            size: tokens.iconSize(base: 18),
                            color: report.safeMode
                                ? ogL.palette.warning
                                : ogL.palette.success,
                          ),
                          title: '安全模式',
                          subtitle: report.safeMode ? '是' : '否',
                          dense: true,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                ),
                OgLSection(
                  title: '引导与模块',
                  description: report.bootSummary,
                  child: OgLBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _KeyValue(ogL: ogL, rows: report.moduleStates),
                        SizedBox(height: tokens.space(OgLSpacing.sm)),
                        _KeyValue(
                          ogL: ogL,
                          rows: <String, String>{
                            '层级桥': report.bridges.join('、'),
                            '服务': '${report.services.length} 项',
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                OgLSection(
                  title: '信任告警',
                  description: report.trustWarnings.isEmpty
                      ? '没有告警：引导清单签名与模块依赖都通过'
                      : '共 ${report.trustWarnings.length} 条（必须处理）',
                  child: report.trustWarnings.isEmpty
                      ? const OgLBlankslate(
                          icon: OgLIconName.shield,
                          title: '信任链正常',
                          body: '内核完成了引导清单签名校验与依赖解析，没有降级项。',
                          compact: true,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (final Object warning in report.trustWarnings)
                              _Banner(
                                ogL: ogL,
                                color: ogL.palette.warning,
                                icon: OgLIconName.warning,
                                text: warning.toString(),
                              ),
                          ],
                        ),
                ),
                OgLSection(
                  title: '依赖图',
                  description: '模块之间谁依赖谁（排查"为什么没启动"用）',
                  child: OgLBox(
                    child: SelectableText(
                      report.moduleGraph,
                      style: TextStyle(
                        fontFamily: kOgLMonoFamily,
                        fontSize: tokens.fontSize(scale.data),
                        color: ogL.palette.text,
                      ),
                    ),
                  ),
                ),
                OgLSection(
                  title: '启动阶段',
                  description: '共 ${report.stages.length} 个阶段',
                  child: OgLBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final Object stage in report.stages)
                          SelectableText(
                            stage.toString(),
                            style: TextStyle(
                              fontFamily: kOgLMonoFamily,
                              fontSize: tokens.fontSize(scale.label),
                              color: ogL.palette.textDim,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                OgLSection(
                  title: '日志',
                  description: allLines.isEmpty
                      ? '还没有日志'
                      : '共 ${allLines.length} 行；下面显示最后 $shown 行'
                          '（「复制全部日志」会带走全部）',
                  actions: <Widget>[
                    OgLButton(
                      label: '复制',
                      size: OgLButtonSize.small,
                      variant: OgLButtonVariant.invisible,
                      leadingIcon: OgLIconName.list,
                      onPressed: () async {
                        await _copyAll(context, allLines);
                      },
                    ),
                  ],
                  child: OgLBox(
                    child: tail.isEmpty
                        ? const OgLBlankslate(
                            icon: OgLIconName.terminal,
                            title: '没有日志',
                            body: '发生网络 / 写入 / 启动事件后，这里会出现记录。',
                            compact: true,
                          )
                        : SelectableText(
                            tail.join('\n'),
                            style: TextStyle(
                              fontFamily: kOgLMonoFamily,
                              fontSize: tokens.fontSize(scale.label),
                              height: 1.4,
                              color: ogL.palette.textDim,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      );
}

/// 设置页：外观 / 网络 / 开发者 / 账户（**分区 + 行式**，严格走令牌与 Kit）。
class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.surface});

  final SurfaceBridge surface;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final settings = surface.settings;
    final value = settings.settings;

    return OgLPageScaffold(
      title: '设置',
      description: '外观 / 网络 / 开发者 / 账户',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ── 外观 ──────────────────────────────────────────────
          OgLSection(
            title: '外观',
            topSpacing: 0,
            child: OgLBox(
              padded: false,
              child: Column(
                children: <Widget>[
                  _ChoiceRow<OgLThemeMode>(
                    icon: OgLIconName.theme,
                    title: '明暗',
                    selected: value.mode,
                    options: const <OgLThemeMode, String>{
                      OgLThemeMode.system: '跟随系统',
                      OgLThemeMode.light: '亮色',
                      OgLThemeMode.dark: '暗色',
                    },
                    onPick: settings.setMode,
                  ),
                  _ChoiceRow<String>(
                    icon: OgLIconName.layout,
                    title: '主题',
                    selected: value.themeId.isEmpty
                        ? OgLThemePacks.fallback.id
                        : value.themeId,
                    options: <String, String>{
                      for (final pack in OgLThemePacks.all) pack.id: pack.name,
                    },
                    onPick: settings.setTheme,
                  ),
                  _ChoiceRow<String>(
                    icon: OgLIconName.book,
                    title: '图标包',
                    selected: value.iconSetId.isEmpty
                        ? surface.effectiveIconSetId()
                        : value.iconSetId,
                    options: <String, String>{
                      for (final set in OgLIconSets.all)
                        set.id: set.displayName,
                    },
                    onPick: settings.setIconSet,
                  ),
                  _ChoiceRow<OgLDensityChoice>(
                    icon: OgLIconName.list,
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
                  _ChoiceRow<OgLMotionSetting>(
                    icon: OgLIconName.sync,
                    title: '动效',
                    selected: value.motion,
                    options: const <OgLMotionSetting, String>{
                      OgLMotionSetting.auto: '跟随系统',
                      OgLMotionSetting.full: '完整',
                      OgLMotionSetting.subtle: '克制',
                      OgLMotionSetting.none: '关闭',
                    },
                    onPick: settings.applyMotion,
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
          // ── 网络 / DNS ────────────────────────────────────────
          OgLSection(
            title: '网络 / DNS',
            description: '自定义解析为进阶选项；异常时请切回系统（重启后完全生效）',
            child: OgLBox(
              padded: false,
              child: Column(
                children: <Widget>[
                  _ChoiceRow<String>(
                    icon: OgLIconName.dns,
                    title: '解析模式',
                    selected: value.dnsMode,
                    options: const <String, String>{
                      'system': '系统（默认）',
                      'custom': '自定义',
                    },
                    onPick: settings.setDnsMode,
                    showDivider: value.dnsMode == 'custom',
                  ),
                  if (value.dnsMode == 'custom') ...<Widget>[
                    _ChoiceRow<String>(
                      icon: OgLIconName.mirror,
                      title: 'DNS 服务器',
                      selected: value.dnsServerId,
                      options: _dnsChoiceLabels,
                      onPick: settings.setDnsServer,
                    ),
                    _ToggleRow(
                      icon: OgLIconName.shield,
                      title: 'DoH 优先（加密解析）',
                      description: '关闭则走明文 UDP，容易被中间设备干扰',
                      value: value.dnsPreferDoh,
                      onChanged: settings.setDnsPreferDoh,
                      showDivider: false,
                    ),
                  ],
                ],
              ),
            ),
          ),
          // ── 开发者（危险，总闸控制） ───────────────────────────
          OgLSection(
            title: '开发者 / 测试选项',
            description: '总闸关闭时下列开关立即全部复位',
            child: OgLBox(
              padded: false,
              child: Column(
                children: <Widget>[
                  _ToggleRow(
                    icon: OgLIconName.bug,
                    title: '开发者模式',
                    description: value.developerMode
                        ? '已开启：下列开关可用'
                        : '关闭状态：下列开关一律失效',
                    value: value.developerMode,
                    onChanged: settings.setDeveloperMode,
                    danger: true,
                  ),
                  for (final OgLDevFlag flag in OgLDevFlag.values)
                    _ToggleRow(
                      icon: flag.risk == OgLRisk.dangerous
                          ? OgLIconName.warning
                          : OgLIconName.terminal,
                      title: flag.description,
                      description: flag.risk == OgLRisk.dangerous
                          ? '危险：可能导致覆盖他人提交'
                          : null,
                      value: value.dev.isOn(flag),
                      onChanged: value.developerMode
                          ? (bool on) => settings.setDevFlag(flag, on)
                          : null,
                      danger: flag.risk == OgLRisk.dangerous,
                      showDivider: flag != OgLDevFlag.values.last,
                    ),
                ],
              ),
            ),
          ),
          if (value.dev.activeDangerous.isNotEmpty) ...<Widget>[
            SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
            OgLBanner(
              variant: OgLBannerVariant.danger,
              title: '危险开关已开启',
              text: '当前有 ${value.dev.activeDangerous.length} 个危险开关处于开启状态，'
                  '请确认这是你想要的。',
            ),
          ],
          if (settings.lastError != null) ...<Widget>[
            SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
            OgLBanner(
              variant: OgLBannerVariant.warning,
              title: '设置保存异常',
              text: '${settings.lastError!}（本次改动已生效，但重启可能丢失）',
            ),
          ],
          // ── 账户 ─────────────────────────────────────────────
          OgLSection(
            title: '账户',
            child: OgLBox(
              padded: false,
              child: FutureBuilder<GhAccount?>(
                future: surface.domain.auth.activeAccount(),
                builder:
                    (BuildContext context, AsyncSnapshot<GhAccount?> snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const OgLActionRow(
                      leading: OgLIcon(
                        name: OgLIconName.key,
                        size: 18,
                      ),
                      title: '读取账户…',
                    );
                  }
                  final GhAccount? account = snap.data;
                  if (account == null) {
                    return const OgLActionRow(
                      leading: OgLIcon(
                        name: OgLIconName.key,
                        size: 18,
                      ),
                      title: '未登录',
                      subtitle: '到「仓库」页接入令牌后即可浏览私有仓库',
                    );
                  }
                  return OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.key,
                      size: 18,
                      color: ogL.palette.textDim,
                    ),
                    title: '@${account.login}',
                    subtitle: '账号 ID：${account.id}',
                    trailing: OgLButton(
                      label: '退出登录',
                      variant: OgLButtonVariant.danger,
                      onPressed: () async {
                        final bool ok = await ogLConfirmDialog(
                          context,
                          title: '退出登录',
                          message: '将删除「@${account.login}」在本机保存的令牌。'
                              '该账号的远端数据不受影响；重新登录需要再次输入令牌。',
                          confirmLabel: '退出登录',
                          danger: true,
                        );
                        if (!ok || !context.mounted) {
                          return;
                        }
                        await surface.domain.auth.removeAccount(account.id);
                        OgLAppLog.instance
                            .add('账户', '已退出登录（@${account.login}）');
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// （诊断页已并入 _AboutPage 的折叠栏，见文件上方。）


/// 键值两列（左列窄、右列等宽可选中）—— 启动报告 / 诊断信息用。
class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.rows, required this.ogL});

  final Map<String, String> rows;
  final OgLTheme ogL;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final MapEntry<String, String> entry in rows.entries)
            Padding(
              padding: EdgeInsets.symmetric(
                vertical: ogL.tokens.space(OgLSpacing.xxs),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: ogL.tokens.space(OgLSpacing.xxl * 3),
                    child: Text(
                      entry.key,
                      style: TextStyle(color: ogL.palette.textDim),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      entry.value,
                      style: const TextStyle(fontFamily: kOgLMonoFamily),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
}

/// 轻提示条：语义图标 + `OgLBanner`（危险 / 警告两档）。
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
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: ogL.tokens.space(OgLSpacing.md)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            OgLIcon(
              name: icon,
              size: ogL.tokens.iconSize(base: 18),
              color: color,
            ),
            SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
            Expanded(
              child: OgLBanner(
                variant: color == ogL.palette.danger
                    ? OgLBannerVariant.danger
                    : OgLBannerVariant.warning,
                text: text,
              ),
            ),
          ],
        ),
      );
}

/// 一行式单选：**整行可点 → 底部选择表**（Primer ActionList 形态）。
///
/// 旧实现是一串 `ChoiceChip`（Material 视觉 + 行内堆叠），与"发丝描边 + 直角偏锐"
/// 的语言冲突，而且选项一多就挤成一团。
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.icon,
    required this.title,
    required this.selected,
    required this.options,
    required this.onPick,
    this.showDivider = true,
  });

  final OgLIconName icon;
  final String title;
  final T selected;
  final Map<T, String> options;
  final ValueChanged<T> onPick;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final String current = options[selected] ?? '$selected';
    return OgLActionRow(
      leading: OgLIcon(name: icon, size: 18, color: ogL.palette.textDim),
      title: title,
      subtitle: '当前：$current',
      showDivider: showDivider,
      onTap: () async {
        final T? picked = await _pickOption<T>(
          context,
          title: title,
          options: options,
          selected: selected,
        );
        if (picked != null) {
          onPick(picked);
        }
      },
    );
  }
}

/// 底部选择表：统一"选一个"的交互（整行可点、当前项打勾、点空白即取消）。
Future<T?> _pickOption<T>(
  BuildContext context, {
  required String title,
  required Map<T, String> options,
  required T selected,
}) {
  final OgLTheme ogL = OgLTheme.of(context);
  final OgLTokens tokens = ogL.tokens;
  final OgLTypeScale scale = const OgLTypeScale.standard();
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: ogL.palette.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radius(OgLRadius.large)),
    ),
    builder: (BuildContext sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.all(tokens.space(OgLSpacing.md)),
            child: Text(
              title,
              style: TextStyle(
                fontSize: tokens.fontSize(scale.title),
                fontWeight: FontWeight.w600,
                color: ogL.palette.text,
              ),
            ),
          ),
          for (final MapEntry<T, String> entry in options.entries)
            OgLActionRow(
              title: entry.value,
              showDivider: true,
              trailing: entry.key == selected
                  ? OgLIcon(
                      name: OgLIconName.success,
                      size: tokens.iconSize(base: 16),
                      color: ogL.palette.success,
                    )
                  : null,
              onTap: () => Navigator.of(sheet).pop(entry.key),
            ),
          SizedBox(height: tokens.space(OgLSpacing.sm)),
        ],
      ),
    ),
  );
}

/// 一行式开关（OgLActionRow + 自绘 OgLToggleSwitch，整行可点）。
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    this.danger = false,
    this.showDivider = true,
  });

  final OgLIconName icon;
  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool danger;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final bool enabled = onChanged != null;
    return OgLActionRow(
      leading: OgLIcon(
        name: icon,
        size: 18,
        color: danger ? ogL.palette.danger : ogL.palette.textDim,
      ),
      title: title,
      subtitle: description,
      showDivider: showDivider,
      trailing: OgLToggleSwitch(value: value, onChanged: onChanged),
      onTap: enabled ? () => onChanged!(!value) : null,
    );
  }
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