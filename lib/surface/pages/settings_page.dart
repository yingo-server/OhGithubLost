/// L3 展示级 · 设置（外观 / 网络 / 账户 / 维护）。
///
/// ## 只留"真选项"
/// - 外观：明暗（跟随系统 / 亮 / 暗）——立即重建主题；
/// - 网络：DNS 解析模式 / 服务器 / DoH——**即时生效**（策略对象可变）；
/// - 账户：当前账号 + 退出登录（删除本机令牌）；
/// - 维护：一键重置设置。
///
/// 旧版的"密度 / 图标包 / 主题包 / 开发者开关"等假选项已全部移除
/// （它们没有接到任何真实行为上，留着只会误导）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../settings.dart';
import '../surface_bridge.dart';

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
        content: const Text('将把外观与网络设置恢复为默认值（账户与数据不受影响）。'),
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
              Text('外观', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<OgLThemeMode>(
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
              const Divider(height: 32),
              Text('网络 / DNS', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
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
                        onChanged: (bool on) {
                          widget.surface.setDnsPreferDoh(on);
                        },
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
              const Divider(height: 32),
              Text('账户', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
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
              const Divider(height: 32),
              Text('维护', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: const Text('重置设置'),
                  subtitle: const Text('恢复外观与网络的默认值'),
                  onTap: _reset,
                ),
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }
}