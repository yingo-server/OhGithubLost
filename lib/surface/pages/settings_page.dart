/// L3 展示级 · 设置（**全部为可折叠分组**）。
///
/// ## 为什么改成折叠
/// 设置项持续增多（外观 / 代码与文件 / 网络 / 账户 / 维护），
/// 平铺会让用户在一屏里被几十个控件淹没、找不到目标。
/// 折叠分组让"每一屏只展开一件关心的事"，同时保留全部能力。
///
/// ## 只留"真选项"
/// 每个条目都必须**接到真实行为**上（外观→主题/缩放/动效；代码→高亮/字号/
/// 换行/排序；网络→DNS 即时生效；账户→退出；维护→重置/权限引导）。
/// 没有"被存起来但不做事"的假开关。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../settings.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../widgets/code_view.dart';
import 'onboarding_page.dart';

/// 设置页。
class SettingsPage extends StatefulWidget {
  /// 创建页面。
  const SettingsPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  OgLSettingsController get _settings => widget.surface.settings;

  /// 拖动中的草稿值（松手才落盘，避免拖动过程高频写盘）。
  double? _fontScaleDraft;
  double? _codeFontDraft;

  /// 自定义代码配色的可选色板（ARGB）。
  static const List<int> _kCodePalette = <int>[
    0xFF000000,
    0xFF101418,
    0xFF1E1E1E,
    0xFF2D333B,
    0xFFF6F8FA,
    0xFFFFFFFF,
    0xFFE6EDF3,
    0xFF24292F,
    0xFF79C0FF,
    0xFF0550AE,
    0xFF569CD6,
    0xFF4EC9B0,
    0xFF6A9955,
    0xFFCE9178,
    0xFF953800,
    0xFFFFA657,
    0xFFB5CEA8,
    0xFFCF222E,
    0xFFFF7B72,
    0xFF8250DF,
    0xFFBC8CFF,
    0xFF9BA7B4,
  ];

  Future<void> _pickCodeColor(String field, int current, String title) async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text(title),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: 280,
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final int argb in _kCodePalette)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => Navigator.of(dialogContext).pop(argb),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(argb),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: argb == current
                                ? Theme.of(dialogContext).colorScheme.primary
                                : const Color(0x33000000),
                            width: argb == current ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    await _settings.setCodeColor(field, picked);
  }

  Future<void> _pickDnsServer() async {
    final Map<String, String> choices = widget.surface.dnsServerChoices;
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前环境没有可选的 DNS 服务器')),
      );
      return;
    }
    final String current = _settings.settings.dnsServerId;
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: const Text('选择 DNS 服务器'),
        children: <Widget>[
          for (final MapEntry<String, String> entry in choices.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(entry.key),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(entry.value)),
                  if (entry.key == current)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    await widget.surface.setDnsServer(picked);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('DNS 选择已保存并生效')),
      );
    }
  }

  Future<void> _logout(GhAccount account) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('退出登录'),
        content: Text(
          '将删除「@${account.login}」在本机保存的令牌。'
          '该账号的远端数据不受影响；重新登录需要再次输入令牌。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.auth.removeAccount(account.id);
      // 多用户安全：移除账号后清空一致性缓存，避免其它账号看到旧缓存。
      await widget.surface.clearRepositoryCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已退出登录（令牌已从本机删除）')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('退出失败：$error')),
        );
      }
    }
  }

  Future<void> _reset() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('重置设置'),
        content: const Text('将把外观 / 代码 / 网络设置恢复为默认值（账户与数据不受影响）。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await _settings.reset();
    widget.surface.applyDns();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已恢复默认设置')),
      );
    }
  }

  void _openOnboarding() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OnboardingPage(
          surface: widget.surface,
          review: true,
          onFinished: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (BuildContext context, Widget? _) {
          final OgLSettings value = _settings.settings;
          final String? saveError = _settings.lastError;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _section(
                theme,
                title: '外观',
                subtitle: '明暗 / 主题色 / 密度 / 文字 / 动效',
                expanded: true,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('明暗模式', style: theme.textTheme.labelLarge),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SegmentedButton<OgLThemeMode>(
                      segments: const <ButtonSegment<OgLThemeMode>>[
                        ButtonSegment<OgLThemeMode>(
                          value: OgLThemeMode.system,
                          label: Text('跟随系统'),
                        ),
                        ButtonSegment<OgLThemeMode>(
                          value: OgLThemeMode.light,
                          label: Text('亮色'),
                        ),
                        ButtonSegment<OgLThemeMode>(
                          value: OgLThemeMode.dark,
                          label: Text('暗色'),
                        ),
                      ],
                      selected: <OgLThemeMode>{value.mode},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<OgLThemeMode> selection) {
                        if (selection.isNotEmpty) {
                          _settings.setMode(selection.first);
                        }
                      },
                    ),
                  ),
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('主题色', style: theme.textTheme.labelLarge),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final MapEntry<String, Color> entry
                            in kOgLSeedColors.entries)
                          ChoiceChip(
                            avatar: CircleAvatar(
                              backgroundColor: entry.value,
                              radius: 10,
                            ),
                            label: Text(ogLSeedColorLabel(entry.key)),
                            selected: value.seedColorId == entry.key,
                            onSelected: (bool on) {
                              if (on) {
                                _settings.setSeedColor(entry.key);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('界面密度', style: theme.textTheme.labelLarge),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                          value: 'comfortable',
                          label: Text('舒适'),
                        ),
                        ButtonSegment<String>(
                          value: 'compact',
                          label: Text('紧凑'),
                        ),
                      ],
                      selected: <String>{value.density},
                      showSelectedIcon: false,
                      onSelectionChanged: (Set<String> selection) {
                        if (selection.isNotEmpty) {
                          _settings.setDensity(selection.first);
                        }
                      },
                    ),
                  ),
                  const Divider(height: 24),
                  _sliderTile(
                    theme,
                    title: '文字缩放',
                    value: _fontScaleDraft ?? value.fontScale,
                    min: OgLSettings.minFontScale,
                    max: OgLSettings.maxFontScale,
                    display:
                        '${(100 * (_fontScaleDraft ?? value.fontScale)).round()}%',
                    divisions: 16,
                    onChanged: (double v) =>
                        setState(() => _fontScaleDraft = v),
                    onChangeEnd: (double v) {
                      setState(() => _fontScaleDraft = null);
                      _settings.setFontScale(v);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('减少动效'),
                    subtitle: const Text('关闭页面过渡等动画（无障碍）'),
                    value: value.reduceMotion,
                    onChanged: _settings.setReduceMotion,
                  ),
                ],
              ),
              _section(
                theme,
                title: '代码与文件',
                subtitle: '语法高亮 / 配色 / 字号 / 换行 / 目录优先',
                children: <Widget>[
                  SwitchListTile(
                    title: const Text('语法高亮'),
                    subtitle: const Text('按文件类型着色（关键词 / 字符串 / 注释）'),
                    value: value.codeHighlight,
                    onChanged: _settings.setCodeHighlight,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('高亮主题', style: theme.textTheme.labelLarge),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final MapEntry<String, String> entry
                            in kOgLCodePresetLabels.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: value.codeThemePreset == entry.key,
                            onSelected: (bool on) {
                              if (on) {
                                _settings.setCodeThemePreset(entry.key);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                  if (value.codeThemePreset == kOgLCodePresetCustom)
                    ...<Widget>[
                      const Divider(height: 1),
                      _codeColorTile(
                        theme,
                        '背景',
                        'background',
                        value.codeColorBackground,
                      ),
                      _codeColorTile(
                        theme,
                        '正文',
                        'foreground',
                        value.codeColorForeground,
                      ),
                      _codeColorTile(
                        theme,
                        '关键词',
                        'keyword',
                        value.codeColorKeyword,
                      ),
                      _codeColorTile(
                        theme,
                        '类型',
                        'typeName',
                        value.codeColorTypeName,
                      ),
                      _codeColorTile(
                        theme,
                        '字符串',
                        'string',
                        value.codeColorString,
                      ),
                      _codeColorTile(
                        theme,
                        '注释',
                        'comment',
                        value.codeColorComment,
                      ),
                      _codeColorTile(
                        theme,
                        '数字',
                        'number',
                        value.codeColorNumber,
                      ),
                    ],
                  SwitchListTile(
                    title: const Text('自动换行'),
                    subtitle: const Text('关闭则横向滚动查看长行'),
                    value: value.codeWrap,
                    onChanged: _settings.setCodeWrap,
                  ),
                  _sliderTile(
                    theme,
                    title: '代码字号',
                    value: _codeFontDraft ?? value.codeFontSize,
                    min: OgLSettings.minCodeFontSize,
                    max: OgLSettings.maxCodeFontSize,
                    display: '${(_codeFontDraft ?? value.codeFontSize).round()}',
                    divisions: 12,
                    onChanged: (double v) => setState(() => _codeFontDraft = v),
                    onChangeEnd: (double v) {
                      setState(() => _codeFontDraft = null);
                      _settings.setCodeFontSize(v);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('目录优先排序'),
                    subtitle: const Text('仓库浏览时把文件夹排在文件前面'),
                    value: value.foldersFirst,
                    onChanged: _settings.setFoldersFirst,
                  ),
                ],
              ),
              _section(
                theme,
                title: '网络 / DNS',
                subtitle: '当前：${widget.surface.dnsSummary}',
                children: <Widget>[
                  SwitchListTile(
                    title: const Text('自定义 DNS 解析'),
                    subtitle: const Text('关闭则使用系统解析（推荐默认）'),
                    value: value.dnsMode == 'custom',
                    onChanged: (bool on) {
                      widget.surface.setDnsMode(on ? 'custom' : 'system');
                    },
                  ),
                  if (value.dnsMode == 'custom') ...<Widget>[
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('DNS 服务器'),
                      subtitle: Text(
                        widget.surface.dnsServerChoices[value.dnsServerId] ??
                            value.dnsServerId,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickDnsServer,
                    ),
                    SwitchListTile(
                      title: const Text('DoH 优先（加密解析）'),
                      subtitle: const Text('关闭则走明文 UDP，容易被中间设备干扰'),
                      value: value.dnsPreferDoh,
                      onChanged: widget.surface.setDnsPreferDoh,
                    ),
                  ],
                ],
              ),
              if (saveError != null) ...<Widget>[
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      saveError,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _section(
                theme,
                title: '账户',
                subtitle: '当前账号 / 退出登录',
                children: <Widget>[
                  FutureBuilder<GhAccount?>(
                    future: widget.surface.domain.auth.activeAccount(),
                    builder: (
                      BuildContext context,
                      AsyncSnapshot<GhAccount?> snapshot,
                    ) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const ListTile(
                          leading: Icon(Icons.key),
                          title: Text('读取账户…'),
                        );
                      }
                      final GhAccount? account = snapshot.data;
                      if (account == null) {
                        return const ListTile(
                          leading: Icon(Icons.key),
                          title: Text('未登录'),
                          subtitle: Text('到「我的」页接入令牌后即可浏览私有仓库'),
                        );
                      }
                      return ListTile(
                        leading: const Icon(Icons.key),
                        title: Text('@${account.login}'),
                        subtitle: Text('账号 ID：${account.id}'),
                        trailing: OutlinedButton(
                          onPressed: () => _logout(account),
                          child: const Text('退出登录'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              _section(
                theme,
                title: '维护',
                subtitle: '权限引导 / 重置设置',
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.privacy_tip_outlined),
                    title: const Text('权限与引导'),
                    subtitle: const Text('重新查看当前平台的权限说明'),
                    onTap: _openOnboarding,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.settings_backup_restore),
                    title: const Text('重置设置'),
                    subtitle: const Text('恢复外观 / 代码 / 网络的默认值'),
                    onTap: _reset,
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  /// 可折叠分组：标题 + 摘要（收起时也能看到关键信息）。
  Widget _section(
    ThemeData theme, {
    required String title,
    required String subtitle,
    required List<Widget> children,
    bool expanded = false,
  }) =>
      Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: Theme(
          // 去掉 ExpansionTile 展开时的上下分隔线，外观更干净。
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: expanded,
            title: Text(title, style: theme.textTheme.titleMedium),
            subtitle: subtitle.isEmpty
                ? null
                : Text(subtitle, style: theme.textTheme.bodySmall),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: children,
          ),
        ),
      );

  /// 自定义配色的一行：名称 + 当前颜色 + 选择入口。
  Widget _codeColorTile(
    ThemeData theme,
    String label,
    String field,
    int argb,
  ) =>
      ListTile(
        dense: true,
        title: Text(label),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: Color(argb),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _pickCodeColor(field, argb, '选择「$label」颜色'),
      );

  Widget _sliderTile(
    ThemeData theme, {
    required String title,
    required double value,
    required double min,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    int? divisions,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(title, style: theme.textTheme.labelLarge),
                ),
                Text(display, style: theme.textTheme.bodySmall),
              ],
            ),
            Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ],
        ),
      );
}