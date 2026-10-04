/// L3 展示级 · 关于（项目信息 + 启动诊断）。
///
/// ## 它展示什么
/// - 项目名称、主要开发者、版本、仓库地址（事实来自 [OgLProjectInfo]）；
/// - 未来扩展位（贡献者名单、致谢等预留，后续追加不必改布局）；
/// - 启动诊断（启动报告 / 信任告警 / 依赖图 / 启动阶段），来自 [KernelReport]。
///
/// ## 它不展示什么
/// 日志与开源许可已归入设置页，便于集中查看；关于页保持"一个身份页"的定位。
library;

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import '../../kernel/kernel.dart';

import '../app/project_info.dart';
import '../i18n/og_l_i18n.dart';

/// 取 `about_page` 分片文案。
String _t(String key, [Map<String, String>? args]) =>
    OgLI18n.instance.t('about_page', key, args: args);

/// 关于页。
class AboutPage extends StatelessWidget {
  /// 创建页面。
  ///
  /// [report] 可为 `null`（例如未启动内核的预览场景）：此时不展示启动诊断段。
  const AboutPage({this.report, super.key});

  /// 启动报告（内核在启动时定格的快照）。
  final KernelReport? report;

  Future<void> _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('copied', <String, String>{'label': label}))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KernelReport? snapshot = report;
    return Scaffold(
      appBar: AppBar(title:  Text(_t('title'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.apps),
                  title: Text(
                    '${OgLProjectInfo.name}（${OgLProjectInfo.abbreviation}）',
                    style: theme.textTheme.titleMedium,
                  ),
                  subtitle: Text(_t('version', <String, String>{
                    'version': snapshot?.appVersion ??
                        OgLI18n.instance.t('common', 'unknown'),
                  })),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title:  Text(_t('developer')),
                  subtitle: Text(OgLProjectInfo.mainDeveloper),
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title:  Text(_t('repo')),
                  subtitle: Text(OgLProjectInfo.repositoryUrl),
                  trailing: IconButton(
                    icon: const Icon(Icons.content_copy, size: 18),
                    tooltip: _t('copyRepoUrl'),
                    onPressed: () => _copy(
                      context,
                      OgLProjectInfo.repositoryUrl,
                      _t('repoUrl'),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title:  Text(_t('license')),
                  subtitle: Text(
                    '${OgLProjectInfo.licenseId} · ${OgLProjectInfo.licenseName}',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title:  Text(_t('futureExt')),
                  subtitle:  Text(_t('futureExtDesc')),
                ),
                const Divider(height: 1),
                 ListTile(
                  dense: true,
                  leading: Icon(Icons.people_outline),
                  title: Text(_t('contributors')),
                  subtitle: Text(_t('contributorsDesc')),
                ),
                 ListTile(
                  dense: true,
                  leading: Icon(Icons.favorite_outline),
                  title: Text(_t('thanks')),
                  subtitle: Text(_t('thanksDesc')),
                ),
              ],
            ),
          ),
          if (snapshot != null) ...<Widget>[
            const SizedBox(height: 16),
            Text(_t('bootDiagnostics'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _diagnosticTile(
              title: _t('bootReport'),
              subtitle: snapshot.bootSummary,
              children: <Widget>[
                for (final MapEntry<String, String> entry
                    in snapshot.moduleStates.entries)
                  _KeyValueRow(label: entry.key, value: entry.value),
                _KeyValueRow(
                  label: _t('layerBridges'),
                  value: snapshot.bridges.join('、'),
                ),
                _KeyValueRow(
                  label: _t('services'),
                  value: _t('servicesCount', <String, String>{'count': snapshot.services.length}),
                ),
              ],
            ),
            _diagnosticTile(
              title: _t('trustWarnings'),
              subtitle: snapshot.trustWarnings.isEmpty
                  ? _t('trustOk')
                  : _t('trustCount', <String, String>{'count': snapshot.trustWarnings.length}),
              children: <Widget>[
                if (snapshot.trustWarnings.isEmpty)
                   ListTile(
                    leading: Icon(Icons.verified_outlined),
                    title: Text(_t('trustChainOk')),
                  )
                else
                  for (final Object warning in snapshot.trustWarnings)
                    ListTile(
                      leading: Icon(
                        Icons.warning_amber_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(warning.toString()),
                    ),
              ],
            ),
            _diagnosticTile(
              title: _t('dependencyGraph'),
              subtitle: _t('dependencyGraphDesc'),
              children: <Widget>[
                SelectableText(
                  snapshot.moduleGraph,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
            _diagnosticTile(
              title: _t('bootStages'),
              subtitle: _t('stagesCount', <String, String>{'count': snapshot.stages.length}),
              children: <Widget>[
                for (final Object stage in snapshot.stages)
                  SelectableText(
                    stage.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text(
            _t('logsAndLicenseHint'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 诊断折叠组（默认收起）。
  Widget _diagnosticTile({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) =>
      Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          title: Text(title),
          subtitle: Text(subtitle),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
      );
}

/// 键值一行（左列标签、右列等宽值）。
class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}