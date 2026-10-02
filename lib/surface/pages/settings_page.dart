/// L3 展示级 · 设置（外观 / 代码与文件 / 网络 / 账户 / 维护）。
///
/// ## 只留"真选项"
/// 每一个条目都必须**接到真实行为**上：
/// - 外观 → `themeFor` / 文字缩放 / 动效；
/// - 代码与文件 → 语法高亮 / 字号 / 换行 / 目录优先；
/// - 网络 → DNS 策略（即时生效）；
/// - 账户 → 退出登录；
/// - 维护 → 重置设置 / 重新查看权限引导。
///
/// 没有"被存起来但不做事"的假开关——假选项比没有选项更糟。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../settings.dart';
import '../surface_bridge.dart';
import '../theme.dart';
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
              _sectionTitle(theme, '外观'),
              Card(
                child: Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
                              label: Text(
                                ogLSeedColorLabel(entry.key),
                              ),
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
              ),
              const SizedBox(height: 16),
              _sectionTitle(theme, '代码与文件'),
              Card(
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      title: const Text('语法高亮'),
                      subtitle: const Text('按文件类型着色（关键词 / 字符串 / 注释）'),
                      value: value.codeHighlight,
                      onChanged: _settings.setCodeHighlight,
                    ),
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
                      onChanged: (double v) =>
                          setState(() => _codeFontDraft = v),
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
              ),
              const SizedBox(height: 16),
              _sectionTitle(theme, '网络 / DNS'),
              Text(
                '当前：${widget.surface.dnsSummary}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
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
              ),
              if (saveError != null) ...<Widget>[
                const SizedBox(height: 12),
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
              ],
              const SizedBox(height: 16),
              _sectionTitle(theme, '账户'),
              FutureBuilder<GhAccount?>(
                future: widget.surface.domain.auth.activeAccount(),
                builder: (
                  BuildContext context,
                  AsyncSnapshot<GhAccount?> snapshot,
                ) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Card(
                      child: ListTile(
                        leading: Icon(Icons.key),
                        title: Text('读取账户…'),
                      ),
                    );
                  }
                  final GhAccount? account = snapshot.data;
                  if (account == null) {
                    return const Card(
                      child: ListTile(
                        leading: Icon(Icons.key),
                        title: Text('未登录'),
                        subtitle: Text('到「我的」页接入令牌后即可浏览私有仓库'),
                      ),
                    );
                  }
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.key),
                      title: Text('@${account.login}'),
                      subtitle: Text('账号 ID：${account.id}'),
                      trailing: OutlinedButton(
                        onPressed: () => _logout(account),
                        child: const Text('退出登录'),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _sectionTitle(theme, '维护'),
              Card(
                child: Column(
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
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: theme.textTheme.titleMedium),
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