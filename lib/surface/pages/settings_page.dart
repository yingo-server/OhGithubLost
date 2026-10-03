/// L3 展示级 · 设置（**分组可折叠，默认收起**）。
///
/// ## 为什么折叠
/// 设置项持续增多（外观 / 语言 / 代码与文件 / 网络 / 账户 / 维护 /
/// 许可 / 日志），平铺会让用户在一屏里被几十个控件淹没、找不到目标。
/// 折叠分组让"每一屏只展开一件关心的事"，同时保留全部能力；默认收起，
/// 进入设置页看到的是**分组标题清单**，而不是一长串控件。
///
/// ## 子条目
/// 分组内允许二级结构：先放"开关 / 选择"，再放"依赖它的子项"
/// （例如自定义 DNS 打开后才出现 DNS 服务器与 DoH）。
///
/// ## 关于与捐赠
/// - "关于"是设置页内的**全屏子页面**（不塞进折叠菜单）；
/// - "捐赠一颗心"用**当前登录令牌**给项目仓库加星，含二次确认与已 star 处理。
///
/// ## 只留"真选项"
/// 每个条目都必须**接到真实行为**上（外观→主题/缩放/动效；代码→高亮/字号/
/// 换行/排序；网络→DNS 即时生效；账户→退出；维护→重置/权限引导）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/gh/gh_auth.dart';
import '../../kernel/kernel.dart';
import '../../kernel/log/og_l_log_file.dart';
import '../app/error_surface.dart';
import '../app/project_info.dart';
import '../i18n/og_l_i18n.dart';
import '../settings.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../widgets/code_editor_field.dart';
import 'about_page.dart';
import 'onboarding_page.dart';

/// 设置页。
class SettingsPage extends StatefulWidget {
  /// 创建页面。
  ///
  /// [report] 可为 `null`（未启动内核的预览场景）：关于页仍可打开，
  /// 只是不展示启动诊断段。
  const SettingsPage({required this.surface, this.report, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  /// 启动报告（透传给关于页）。
  final KernelReport? report;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  OgLSettingsController get _settings => widget.surface.settings;

  /// 拖动中的草稿值（松手才落盘，避免拖动过程高频写盘）。
  double? _fontScaleDraft;
  double? _codeFontDraft;

  /// 日志栏目最多展示的行数（复制仍带走全部）。
  static const int _logTailShown = 80;

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

  /// 动效档位的短标签（与 [OgLSettings.motionLevelIds] 一一对应）。
  static const List<String> _motionShort = <String>['最小', '当前', '标准', '增强'];

  /// 动效档位的说明（与 [OgLSettings.motionLevelIds] 一一对应）。
  static const List<String> _motionHints = <String>[
    '关闭页面过渡等动画',
    '沿用当前的动效量',
    '页面过渡使用 Material 标准',
    '在标准之上增加淡入与缩放',
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

  /// 设置页文案取用（统一 `settings` 分片）。
  String _t(String key) => OgLI18n.instance.t('settings', key);

  Future<void> _pickLanguage() async {
    final String current = _settings.settings.languageCode;
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text(_t('language')),
        children: <Widget>[
          for (final OgLLocale item in OgLI18n.locales)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(item.code),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(item.label)),
                  if (item.code == current)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == current) {
      return;
    }
    await widget.surface.setLanguage(picked);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_t('language')}: ${OgLI18n.instance.localeLabel}'),
        ),
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

  /// 打开关于页（全屏子页面）。
  void _openAbout() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => AboutPage(report: widget.report),
      ),
    );
  }

  /// 捐赠一颗心：二次确认后，用当前登录令牌给项目仓库加星。
  ///
  /// 已 star 时不重复操作，直接给出提示（幂等，不制造"操作了但没变化"的疑惑）。
  Future<void> _donateStar() async {
    final GhAccount? account = await widget.surface.domain.auth.activeAccount();
    if (!mounted) {
      return;
    }
    if (account == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录，再用当前账号为项目点亮 star')),
      );
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('捐赠一颗心'),
        content: Text(
          '将用当前登录账号「@${account.login}」'
          '给 ${OgLProjectInfo.repoFullName} 点亮 star。'
          '如果已经 star 过，不会重复操作。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('捐赠一颗心'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      final bool already = await widget.surface.domain.api
          .isRepoStarred(OgLProjectInfo.repoFullName);
      if (already) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('这个账号已经 star 过，心意已收到')),
          );
        }
        return;
      }
      await widget.surface.domain.api
          .setStarred(OgLProjectInfo.repoFullName, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('感谢支持，已为项目点亮 star')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$error')),
        );
      }
    }
  }

  /// 复制全部日志到剪贴板。
  Future<void> _copyLogs(List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${lines.length} 行日志')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('title'))),
      body: ListenableBuilder(
        listenable: _settings,
        builder: (BuildContext context, Widget? _) {
          final OgLSettings value = _settings.settings;
          final String? saveError = _settings.lastError;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _appearanceSection(theme, value),
              _languageSection(theme),
              _codeSection(theme, value),
              _networkSection(theme, value),
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
              _accountSection(theme),
              _maintenanceSection(theme),
              // 关于：独立于折叠菜单的全屏子页面。
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(OgLI18n.instance.t('shell', 'about')),
                  subtitle: const Text('项目信息与启动诊断'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openAbout,
                ),
              ),
              // 捐赠一颗心：二次确认后加星。
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(Icons.favorite, color: theme.colorScheme.error),
                  title: const Text('捐赠一颗心'),
                  subtitle: Text('用当前登录账号给 ${OgLProjectInfo.repoFullName} 点亮 star'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _donateStar,
                ),
              ),
              _licenseSection(theme),
              _logsSection(theme),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────── 各分组 ─────────────────────────

  /// 外观（明暗 / 主题色 / 密度 / 字号 / 动效）。
  Widget _appearanceSection(ThemeData theme, OgLSettings value) => _section(
        theme,
        title: _t('appearance'),
        subtitle: '主题、缩放与动效',
        children: <Widget>[
          _subTitle(theme, _t('themeMode')),
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
          _subTitle(theme, _t('themeColor')),
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
          _subTitle(theme, _t('density')),
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
            title: _t('fontScale'),
            value: _fontScaleDraft ?? value.fontScale,
            min: OgLSettings.minFontScale,
            max: OgLSettings.maxFontScale,
            display: '${(100 * (_fontScaleDraft ?? value.fontScale)).round()}%',
            divisions: 16,
            onChanged: (double v) => setState(() => _fontScaleDraft = v),
            onChangeEnd: (double v) {
              setState(() => _fontScaleDraft = null);
              _settings.setFontScale(v);
            },
          ),
          const Divider(height: 24),
          _motionTile(theme, value.motionLevel),
          SwitchListTile(
            title: const Text('减少动效（无障碍）'),
            subtitle: const Text('跟随系统的"减少动效"设置；档位"最小"会直接关闭'),
            value: value.reduceMotion,
            onChanged: _settings.setReduceMotion,
          ),
        ],
      );

  /// 动效档位（四档，横向分段）。
  Widget _motionTile(ThemeData theme, int level) {
    final int index = level.clamp(0, _motionShort.length - 1).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('动效档位', style: theme.textTheme.labelLarge),
              ),
              Text(_motionShort[index], style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: <ButtonSegment<int>>[
              for (int i = 0; i < _motionShort.length; i++)
                ButtonSegment<int>(value: i, label: Text(_motionShort[i])),
            ],
            selected: <int>{index},
            showSelectedIcon: false,
            onSelectionChanged: (Set<int> selection) {
              if (selection.isNotEmpty) {
                _settings.setMotionLevel(selection.first);
              }
            },
          ),
          const SizedBox(height: 4),
          Text(_motionHints[index], style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// 语言。
  Widget _languageSection(ThemeData theme) => _section(
        theme,
        title: _t('language'),
        subtitle: '界面显示语言',
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.translate),
            title: Text(_t('language')),
            subtitle: Text(OgLI18n.instance.localeLabel),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickLanguage,
          ),
        ],
      );

  /// 代码与文件。
  Widget _codeSection(ThemeData theme, OgLSettings value) => _section(
        theme,
        title: _t('codeAndFiles'),
        subtitle: '高亮、字号与排序',
        children: <Widget>[
          SwitchListTile(
            title: Text(_t('syntaxHighlight')),
            subtitle: const Text('按文件类型着色（关键词 / 字符串 / 注释）'),
            value: value.codeHighlight,
            onChanged: _settings.setCodeHighlight,
          ),
          _subTitle(theme, _t('highlightTheme')),
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
              _codeColorTile(theme, '关键词', 'keyword', value.codeColorKeyword),
              _codeColorTile(
                theme,
                '类型',
                'typeName',
                value.codeColorTypeName,
              ),
              _codeColorTile(theme, '字符串', 'string', value.codeColorString),
              _codeColorTile(theme, '注释', 'comment', value.codeColorComment),
              _codeColorTile(theme, '数字', 'number', value.codeColorNumber),
            ],
          SwitchListTile(
            title: Text(_t('codeWrap')),
            subtitle: const Text('关闭则横向滚动查看长行'),
            value: value.codeWrap,
            onChanged: _settings.setCodeWrap,
          ),
          _sliderTile(
            theme,
            title: _t('codeFontSize'),
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
            title: Text(_t('foldersFirst')),
            subtitle: const Text('仓库浏览时把文件夹排在文件前面'),
            value: value.foldersFirst,
            onChanged: _settings.setFoldersFirst,
          ),
        ],
      );

  /// 网络 / DNS。
  Widget _networkSection(ThemeData theme, OgLSettings value) => _section(
        theme,
        title: _t('network'),
        subtitle: '解析方式',
        children: <Widget>[
          SwitchListTile(
            title: Text(_t('customDns')),
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
              title: Text(_t('doh')),
              subtitle: const Text('关闭则走明文 UDP，容易被中间设备干扰'),
              value: value.dnsPreferDoh,
              onChanged: widget.surface.setDnsPreferDoh,
            ),
          ],
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('Release 附件加速通道'),
            subtitle: const Text('经加速通道下载发布附件；关闭则直连（不影响其它下载）'),
            value: value.releaseProxyEnabled,
            onChanged: _settings.setReleaseProxyEnabled,
          ),
        ],
      );

  /// 账户。
  Widget _accountSection(ThemeData theme) => _section(
        theme,
        title: _t('account'),
        subtitle: '当前登录账号',
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
                  child: Text(_t('logout')),
                ),
              );
            },
          ),
        ],
      );

  /// 维护。
  Widget _maintenanceSection(ThemeData theme) => _section(
        theme,
        title: _t('maintenance'),
        subtitle: '引导与重置',
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(_t('permissionsGuide')),
            subtitle: const Text('重新查看当前平台的权限说明'),
            onTap: _openOnboarding,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(_t('resetSettings')),
            subtitle: const Text('恢复外观 / 代码 / 网络的默认值'),
            onTap: _reset,
          ),
        ],
      );

  /// 开源许可（本项目 + 第三方依赖），默认收起。
  Widget _licenseSection(ThemeData theme) => _section(
        theme,
        title: '开源许可',
        subtitle: '本项目与第三方依赖',
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text('${OgLProjectInfo.name}（本项目）'),
            subtitle: Text(
              '${OgLProjectInfo.licenseId} · ${OgLProjectInfo.licenseName}',
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('第三方依赖'),
            subtitle: Text('共 ${kOgLDependencyLicenses.length} 项'),
          ),
          for (final OgLDependencyLicense dep in kOgLDependencyLicenses)
            ListTile(
              dense: true,
              title: Text(dep.name),
              subtitle: Text('${dep.license} · ${dep.purpose}'),
            ),
        ],
      );

  /// 日志（应用运行日志），默认收起。
  Widget _logsSection(ThemeData theme) => _section(
        theme,
        title: '日志',
        subtitle: '网络 / 认证 / 写入的原始记录',
        children: <Widget>[
          ListenableBuilder(
            listenable: OgLAppLog.instance,
            builder: (BuildContext context, Widget? _) {
              final List<String> allLines = OgLAppLog.instance.entries
                  .map((OgLAppLogEntry entry) => entry.toDisplay())
                  .toList();
              final int shown = allLines.length > _logTailShown
                  ? _logTailShown
                  : allLines.length;
              final List<String> tail = allLines.sublist(allLines.length - shown);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('当前日志文件'),
                    subtitle: Text(OgLLogFile.filePath ?? '未启用落盘'),
                  ),
                  if (!OgLLogFile.isEnabled)
                    ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                      ),
                      title: const Text('未能落盘的原因'),
                      subtitle: Text(OgLLogFile.lastError ?? '未知'),
                    ),
                  if (tail.isEmpty)
                    const ListTile(title: Text('还没有日志'))
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: SelectableText(
                        tail.join('\n'),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: TextButton.icon(
                        onPressed: () => _copyLogs(allLines),
                        icon: const Icon(Icons.content_copy, size: 16),
                        label: const Text('复制全部日志'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      );

  // ───────────────────────── 通用零件 ─────────────────────────

  /// 可折叠分组：标题 + 摘要，**默认收起**。
  Widget _section(
    ThemeData theme, {
    required String title,
    required List<Widget> children,
    String subtitle = '',
  }) =>
      Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: Theme(
          // 去掉 ExpansionTile 展开时的上下分隔线，外观更干净。
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(title, style: theme.textTheme.titleMedium),
            subtitle: subtitle.isEmpty
                ? null
                : Text(subtitle, style: theme.textTheme.bodySmall),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: children,
          ),
        ),
      );

  /// 分组内的二级小标题。
  Widget _subTitle(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text, style: theme.textTheme.labelLarge),
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