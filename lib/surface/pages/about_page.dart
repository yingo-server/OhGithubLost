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
      SnackBar(content: Text('已复制$label')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final KernelReport? snapshot = report;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
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
                  subtitle: Text('版本 ${snapshot?.appVersion ?? '未知'}'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('主要开发者'),
                  subtitle: Text(OgLProjectInfo.mainDeveloper),
                ),
                ListTile(
                  leading: const Icon(Icons.link),
                  title: const Text('代码仓库'),
                  subtitle: Text(OgLProjectInfo.repositoryUrl),
                  trailing: IconButton(
                    icon: const Icon(Icons.content_copy, size: 18),
                    tooltip: '复制仓库地址',
                    onPressed: () => _copy(
                      context,
                      OgLProjectInfo.repositoryUrl,
                      '仓库地址',
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.gavel_outlined),
                  title: const Text('开源许可'),
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
                  title: const Text('未来扩展'),
                  subtitle: const Text('以下位置预留，后续补充不必调整布局'),
                ),
                const Divider(height: 1),
                const ListTile(
                  dense: true,
                  leading: Icon(Icons.people_outline),
                  title: Text('贡献者名单'),
                  subtitle: Text('预留给参与代码、翻译与测试的贡献者'),
                ),
                const ListTile(
                  dense: true,
                  leading: Icon(Icons.favorite_outline),
                  title: Text('致谢'),
                  subtitle: Text('预留给上游项目与社区支持'),
                ),
              ],
            ),
          ),
          if (snapshot != null) ...<Widget>[
            const SizedBox(height: 16),
            Text('启动诊断', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _diagnosticTile(
              title: '启动报告',
              subtitle: snapshot.bootSummary,
              children: <Widget>[
                for (final MapEntry<String, String> entry
                    in snapshot.moduleStates.entries)
                  _KeyValueRow(label: entry.key, value: entry.value),
                _KeyValueRow(
                  label: '层级桥',
                  value: snapshot.bridges.join('、'),
                ),
                _KeyValueRow(
                  label: '服务',
                  value: '${snapshot.services.length} 项',
                ),
              ],
            ),
            _diagnosticTile(
              title: '信任告警',
              subtitle: snapshot.trustWarnings.isEmpty
                  ? '没有告警：引导清单签名与模块依赖都通过'
                  : '共 ${snapshot.trustWarnings.length} 条（需要处理）',
              children: <Widget>[
                if (snapshot.trustWarnings.isEmpty)
                  const ListTile(
                    leading: Icon(Icons.verified_outlined),
                    title: Text('信任链正常'),
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
              title: '依赖图',
              subtitle: '模块之间谁依赖谁（排查"为什么没启动"用）',
              children: <Widget>[
                SelectableText(
                  snapshot.moduleGraph,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
            _diagnosticTile(
              title: '启动阶段',
              subtitle: '共 ${snapshot.stages.length} 个阶段',
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
            '日志与开源许可位于设置页。',
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