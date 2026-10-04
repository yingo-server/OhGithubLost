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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../kernel/kernel.dart';
import '../../kernel/log/og_l_log_file.dart';
import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/project_info.dart';
import '../i18n/og_l_i18n.dart';
import '../settings.dart';
import '../surface_bridge.dart';
import '../theme.dart';
import '../types.dart';
import '../util/accel.dart';
import '../widgets/code_editor_field.dart';
import 'about_page.dart';
import 'network_page.dart';
import 'onboarding_page.dart';
import 'repo_page.dart';

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
  ///
  /// 5.2：档位语义改为**质量**（静默 / 保守 / 标准 / 拉满），
  /// 不再复用界面密度的「最小 / 当前 / 标准 / 增强」字样。
  List<String> get _motionShort => <String>[
        _t('motionMin'),
        _t('motionConservative'),
        _t('motionStandard'),
        _t('motionFull'),
      ];

  /// 动效档位的说明（与 [OgLSettings.motionLevelIds] 一一对应）。
  List<String> get _motionHints => <String>[
    _t('motionMinDesc'),
    _t('motionCurrentDesc'),
    _t('motionStandardDesc'),
    _t('motionEnhancedDesc'),
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
         SnackBar(content: Text(_t('noDnsServers'))),
      );
      return;
    }
    final String current = _settings.settings.dnsServerId;
    final String? picked = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title:  Text(_t('selectDns')),
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
         SnackBar(content: Text(_t('dnsSaved'))),
      );
    }
  }

  Future<void> _logout(GhAccount account) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('logout')),
        content: Text(
          _t('logoutDesc', {'login': account.login}) +
          _t('logoutDesc2'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.auth.removeAccount(account.id);
      // 多用户安全：移除账号后清空**所有**缓存，避免其它账号看到旧缓存。
      await widget.surface.clearAllCaches();
      clearOgLRepoPageCaches();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_t('loggedOut'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('logoutFailed', {'error': error}))),
        );
      }
    }
  }

  Future<void> _reset() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('resetSettings')),
        content:  Text(_t('resetDesc')),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('reset')),
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
         SnackBar(content: Text(_t('resetDone'))),
      );
    }
  }

  /// 设置页文案取用（统一 `settings` 分片）。
  String _t(String key, [Map<String, Object?>? args]) =>
      OgLI18n.instance.t('settings', key,
          args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

  /// `common` 分片文案（加速协议 / 通用按钮等）。
  String _tc(String key, [Map<String, Object?>? args]) =>
      OgLI18n.instance.t('common', key,
          args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

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
         SnackBar(content: Text(_t('starLoginFirst'))),
      );
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('donateHeart')),
        content: Text(
          _t('donateDesc1', {'login': account.login}) +
          _t('donateDesc2', {'repo': OgLProjectInfo.repoFullName}) +
          _t('donateDesc3'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('thinkAgain')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('donateHeart')),
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
             SnackBar(content: Text(_t('alreadyStarred'))),
          );
        }
        return;
      }
      await widget.surface.domain.api
          .setStarred(OgLProjectInfo.repoFullName, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text(_t('starredThanks'))),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('actionFailed', {'error': error}))),
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
      SnackBar(content: Text(_t('copiedLogLines', {'count': lines.length}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_t('title'))),
      body: OgLReveal(delay: Duration.zero, child: ListenableBuilder(
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
              // 网络：**独立子页面**（不再是一个可折叠分组）。
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.wifi_outlined),
                  title: Text(_t('network')),
                  subtitle:  Text(_t('dnsMode')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openNetwork,
                ),
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
              _accountSection(theme),
              _maintenanceSection(theme),
              // 关于：独立于折叠菜单的全屏子页面。
              Card(
                clipBehavior: Clip.antiAlias,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(OgLI18n.instance.t('shell', 'about')),
                  subtitle:  Text(_t('projectInfo')),
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
                  title:  Text(_t('donateHeart')),
                  subtitle: Text(_t('donateTileDesc', {'repo': OgLProjectInfo.repoFullName})),
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
      )),
    );
  }

  // ───────────────────────── 各分组 ─────────────────────────

  /// 外观（明暗 / 主题色 / 密度 / 字号 / 动效）。
  Widget _appearanceSection(ThemeData theme, OgLSettings value) => _section(
        theme,
        title: _t('appearance'),
        subtitle: _t('appearanceDesc'),
        children: <Widget>[
          _subTitle(theme, _t('themeMode')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<OgLThemeMode>(
              segments:  <ButtonSegment<OgLThemeMode>>[
                ButtonSegment<OgLThemeMode>(
                  value: OgLThemeMode.system,
                  label: Text(_t('followSystem')),
                ),
                ButtonSegment<OgLThemeMode>(
                  value: OgLThemeMode.light,
                  label: Text(_t('light')),
                ),
                ButtonSegment<OgLThemeMode>(
                  value: OgLThemeMode.dark,
                  label: Text(_t('dark')),
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
                    // 明环境下若沿用 M3 默认的 secondaryContainer，
                    // 勾号（onSecondaryContainer）在浅色芯片上对比度偏低。
                    // 这里改为**确定的 primary / onPrimary 组合**，深浅两态都有足够对比；
                    // 并关掉勾号、保留色点（色点本身就是最强的选中线索）。
                    showCheckmark: false,
                    selectedColor: theme.colorScheme.primary,
                    labelStyle: TextStyle(
                      color: value.seedColorId == entry.key
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
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
              segments:  <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'comfortable',
                  label: Text(_t('comfortable')),
                ),
                ButtonSegment<String>(
                  value: 'compact',
                  label: Text(_t('compact')),
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
            title:  Text(_t('reduceMotionA11y')),
            subtitle:  Text(_t('reduceMotionDesc')),
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
                child: Text(_t('motionLevel'), style: theme.textTheme.labelLarge),
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
        subtitle: _t('displayLanguage'),
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
        subtitle: _t('codeDesc'),
        children: <Widget>[
          SwitchListTile(
            title: Text(_t('syntaxHighlight')),
            subtitle:  Text(_t('codeColorDesc')),
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
                    label: Text(ogLCodePresetLabel(entry.key)),
                    selected: value.codeThemePreset == entry.key,
                    // 同款修正：选中态用 primary 底 + onPrimary 字/勾，确保明环境下的对比度。
                    selectedColor: theme.colorScheme.primary,
                    checkmarkColor: theme.colorScheme.onPrimary,
                    labelStyle: TextStyle(
                      color: value.codeThemePreset == entry.key
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
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
                _t('tokenBackground'),
                'background',
                value.codeColorBackground,
              ),
              _codeColorTile(
                theme,
                _t('tokenForeground'),
                'foreground',
                value.codeColorForeground,
              ),
              _codeColorTile(theme, _t('tokenKeyword'), 'keyword', value.codeColorKeyword),
              _codeColorTile(
                theme,
                _t('tokenType'),
                'typeName',
                value.codeColorTypeName,
              ),
              _codeColorTile(theme, _t('tokenString'), 'string', value.codeColorString),
              _codeColorTile(theme, _t('tokenComment'), 'comment', value.codeColorComment),
              _codeColorTile(theme, _t('tokenNumber'), 'number', value.codeColorNumber),
            ],
          SwitchListTile(
            title: Text(_t('codeWrap')),
            subtitle:  Text(_t('codeWrapDesc')),
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
            subtitle:  Text(_t('foldersFirstDesc')),
            value: value.foldersFirst,
            onChanged: _settings.setFoldersFirst,
          ),
        ],
      );

  /// 网络 / DNS / 下载并发 / 加速通道。
  ///
  /// 这些内容渲染在**独立的网络设置页**里（见 `network_page.dart`），
  /// 不再是一个"可折叠分组"。
  List<Widget> _networkTiles(ThemeData theme, OgLSettings value) => <Widget>[
          SwitchListTile(
            title: Text(_t('customDns')),
            subtitle:  Text(_t('dnsModeDesc')),
            value: value.dnsMode == 'custom',
            onChanged: (bool on) {
              widget.surface.setDnsMode(on ? 'custom' : 'system');
            },
          ),
          if (value.dnsMode == 'custom') ...<Widget>[
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title:  Text(_t('dnsServer')),
              subtitle: Text(
                widget.surface.dnsServerChoices[value.dnsServerId] ??
                    value.dnsServerId,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDnsServer,
            ),
            SwitchListTile(
              title: Text(_t('doh')),
              subtitle:  Text(_t('dnsServerDesc')),
              value: value.dnsPreferDoh,
              onChanged: widget.surface.setDnsPreferDoh,
            ),
          ],
const Divider(height: 1),
          ..._downloadTiles(theme, value),
          ..._accelTiles(theme, value),
        ];

  /// 打开**网络设置页**（独立页面；不再是可折叠分组）。
  ///
  /// 分节内容仍由本页闭包生成——逻辑与文案只有一份。
  void _openNetwork() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => NetworkSettingsPage(
          surface: widget.surface,
          builder: (BuildContext context, OgLSettings value) => Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _networkTiles(Theme.of(context), value),
            ),
          ),
        ),
      ),
    );
  }

  /// 轻提示。
  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// ── 下载（并发连接数）──────────────────────────────────────────────
  ///
  /// 只给固定档位（1 / 2 / 4 / 8）：用户不需要理解 TCP，只需要「快一点 / 稳一点」。
  /// 服务端不支持 Range 时中枢层会自动回退单连接，所以调高并发不会把下载搞坏。
  List<Widget> _downloadTiles(ThemeData theme, OgLSettings value) => <Widget>[
        ListTile(
          leading: const Icon(Icons.download_outlined),
          title: Text(_t('downloadConnections')),
          subtitle: Text(_t('downloadConnectionsDesc')),
          trailing: Text(
            _t('connectionsCount', <String, Object?>{
              'count': value.downloadConnections,
            }),
          ),
          onTap: () => unawaited(_pickDownloadConnections(value)),
        ),
      ];

  Future<void> _pickDownloadConnections(OgLSettings value) async {
    final int? picked = await showDialog<int>(
      context: context,
      builder: (BuildContext dialogContext) => SimpleDialog(
        title: Text(_t('downloadConnections')),
        children: <Widget>[
          for (final int choice in OgLSettings.downloadConnectionChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(choice),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(_t('connectionsCount', <String, Object?>{
                      'count': choice,
                    })),
                  ),
                  if (choice == value.downloadConnections)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted || picked == value.downloadConnections) {
      return;
    }
    await widget.surface.setDownloadConnections(picked);
    if (mounted) {
      _toast(_t('connectionsCount', <String, Object?>{'count': picked}));
    }
  }

  /// ── Release 下载加速（总开关 + 多通道 + 协议同意）────────────────────
  ///
  /// 设计：**只有一个总开关**；下面是通道列表（内置 + 自定义），可多选一。
  /// 开启总开关前若尚未同意当前版本协议，会先弹出协议并要求勾选同意
  /// （同意版本与时间会落盘，作为凭据）。
  List<Widget> _accelTiles(ThemeData theme, OgLSettings value) {
    final List<Widget> tiles = <Widget>[
      SwitchListTile(
        title:  Text(_t('accelTitle')),
        subtitle:  Text(_t('accelDesc')),
        value: value.releaseProxyEnabled,
        onChanged: (bool on) => unawaited(_toggleAccel(on)),
      ),
    ];
    if (!value.releaseProxyEnabled) {
      return tiles;
    }
    tiles.add(_subTitle(theme, _t('accelChannels')));
    for (final OgLAccelChannel channel in value.allAccelChannels) {
      final bool selected = channel.id == value.activeAccelChannel.id;
      tiles.add(
        ListTile(
          leading: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          ),
          title: Text(channel.builtin ? _tc('accelBuiltinName') : channel.name),
          subtitle: Text(
            channel.builtin ? _t('accelBuiltinDesc') : channel.baseUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: channel.builtin
              ? null
              : IconButton(
                  tooltip: _t('removeChannel'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      unawaited(widget.surface.removeAccelChannel(channel.id)),
                ),
          onTap: () =>
              unawaited(widget.surface.setReleaseProxySelected(channel.id)),
        ),
      );
    }
    tiles.add(
      ListTile(
        leading: const Icon(Icons.add),
        title:  Text(_t('addCustomChannel')),
        subtitle: const Text('第三方服务，需自行确认可信；地址需为 https://'),
        onTap: _addAccelChannel,
      ),
    );
    tiles.add(
      ListTile(
        leading: const Icon(Icons.gavel_outlined),
        title:  Text(_t('viewAccelAgreement')),
        subtitle: Text(
          value.accelConsentCurrent
              ? (value.releaseProxyConsentAt == null
                  ? _t('consented', {
                      'version': '${value.releaseProxyConsentVersion}',
                    })
                  : _t('consentedAt', {
                      'version': '${value.releaseProxyConsentVersion}',
                      'at': '${value.releaseProxyConsentAt}',
                    }))
              : _t('notConsented'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(
          _showAccelAgreement(value.activeAccelChannel, requireConsent: true),
        ),
      ),
    );
    return tiles;
  }

  /// 打开总开关：必须先同意当前版本协议。
  Future<void> _toggleAccel(bool on) async {
    if (!on) {
      await widget.surface.setReleaseProxyEnabled(false);
      return;
    }
    final OgLSettings value = widget.surface.settings.settings;
    if (!value.accelConsentCurrent) {
      final bool accepted = await _showAccelAgreement(
        value.activeAccelChannel,
        requireConsent: true,
      );
      if (!accepted) {
        return;
      }
    }
    await widget.surface.setReleaseProxyEnabled(true);
  }

  /// 展示协议；[requireConsent] 为真时返回"是否勾选并同意"。
  Future<bool> _showAccelAgreement(
    OgLAccelChannel channel, {
    required bool requireConsent,
  }) async {
    bool agreed = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setLocal) => AlertDialog(
          title: Text(channel.builtin ? _t('accelBuiltinTitle') : _t('accelThirdPartyTitle')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Text(ogLAccelAgreementFor(channel)),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child:  Text(_t('disagree')),
            ),
            FilledButton(
              onPressed: agreed
                  ? () => Navigator.of(dialogContext).pop(true)
                  : null,
              child:  Text(_t('agreeContinue')),
            ),
            if (requireConsent)
              CheckboxListTile(
                value: agreed,
                onChanged: (bool? v) => setLocal(() => agreed = v ?? false),
                title:  Text(_t('agreeRead')),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
              ),
          ],
        ),
      ),
    );
    if (ok == true && agreed) {
      await widget.surface.acceptAccelConsent();
      if (mounted) {
        OgLAppLog.instance.result(_t('title'), _t('agreedAccel'), channel.id);
      }
      return true;
    }
    return false;
  }

  /// 添加自定义通道（名称 + https 地址）。
  Future<void> _addAccelChannel() async {
    final TextEditingController name = TextEditingController();
    final TextEditingController url = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('addCustomChannel')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: name,
              decoration:  InputDecoration(
                labelText: _t('channelName'),
                hintText: _t('channelNameHint'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: url,
              decoration:  InputDecoration(
                labelText: _t('channelUrl'),
                hintText: 'https://example.com/',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child:  Text(_t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child:  Text(_t('add')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      name.dispose();
      url.dispose();
      return;
    }
    final String? error = ogLValidateAccelBaseUrl(url.text);
    if (error != null) {
      name.dispose();
      url.dispose();
      _toast(error);
      return;
    }
    final String label = name.text.trim().isEmpty ? _t('customChannel') : name.text.trim();
    final String id = 'custom-${DateTime.now().millisecondsSinceEpoch}';
    await widget.surface
        .upsertAccelChannel(OgLAccelChannel(id: id, name: label, baseUrl: url.text));
    name.dispose();
    url.dispose();
    if (mounted) {
      _toast(_t('channelAdded', {'label': label}));
    }
  }

  /// 账户。
  Widget _accountSection(ThemeData theme) => _section(
        theme,
        title: _t('account'),
        subtitle: _t('currentAccount'),
        children: <Widget>[
          FutureBuilder<GhAccount?>(
            future: widget.surface.domain.auth.activeAccount(),
            builder: (
              BuildContext context,
              AsyncSnapshot<GhAccount?> snapshot,
            ) {
              if (snapshot.connectionState != ConnectionState.done) {
                return  ListTile(
                  leading: Icon(Icons.key),
                  title: Text(_t('readingAccount')),
                );
              }
              final GhAccount? account = snapshot.data;
              if (account == null) {
                return  ListTile(
                  leading: Icon(Icons.key),
                  title: Text(_t('notLoggedIn')),
                  subtitle: Text(_t('notLoggedInHint')),
                );
              }
              return ListTile(
                leading: const Icon(Icons.key),
                title: Text('@${account.login}'),
                subtitle: Text(_t('accountId', {'id': account.id})),
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
        subtitle: _t('guideAndReset'),
        children: <Widget>[
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(_t('permissionsGuide')),
            subtitle:  Text(_t('recheckPermissions')),
            onTap: _openOnboarding,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(_t('resetSettings')),
            subtitle:  Text(_t('restoreDefaults')),
            onTap: _reset,
          ),
        ],
      );

  /// 开源许可：**合并为一条**，打开时弹窗（本项目 + 第三方依赖）。
  Widget _licenseSection(ThemeData theme) => Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: const Icon(Icons.gavel_outlined),
          title: Text(_t('licenses')),
          subtitle:  Text(_t('licensesDesc')),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showLicenses,
        ),
      );

  /// 许可弹窗：本项目许可 + 第三方依赖清单（**合并为一个入口**）。
  Future<void> _showLicenses() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title:  Text(_t('licenses')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.gavel_outlined),
                  title: Text(_t('licenseSelf', {'name': OgLProjectInfo.name})),
                  subtitle: Text(
                    '${OgLProjectInfo.licenseId} · ${OgLProjectInfo.licenseName}',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.inventory_2_outlined),
                  title:  Text(_t('thirdPartyDeps')),
                  subtitle: Text(
                    _t('depsCount', {'count': kOgLDependencyLicenses.length}),
                  ),
                ),
                for (final OgLDependencyLicense dep in kOgLDependencyLicenses)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(dep.name),
                    subtitle: Text('${dep.license} · ${dep.purpose}'),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child:  Text(_tc('close')),
          ),
        ],
      ),
    );
  }

  /// 日志（应用运行日志），默认收起。
  Widget _logsSection(ThemeData theme) => _section(
        theme,
        title: _t('logs'),
        subtitle: _t('logsDesc'),
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
                    title:  Text(_t('currentLogFile')),
                    subtitle: Text(OgLLogFile.filePath ?? _t('logDisabled')),
                  ),
                  if (!OgLLogFile.isEnabled)
                    ListTile(
                      leading: Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                      ),
                      title:  Text(_t('logDisabledReason')),
                      subtitle: Text(OgLLogFile.lastError ?? _t('unknown')),
                    ),
                  if (tail.isEmpty)
                     ListTile(title: Text(_t('noLogs')))
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
                        label:  Text(_t('copyAllLogs')),
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
        onTap: () => _pickCodeColor(field, argb, _t('chooseColor', {'label': label})),
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