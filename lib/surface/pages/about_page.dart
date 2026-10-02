/// L3 展示级 · 关于（启动报告 / 信任链 / 依赖图 / 日志）。
///
/// - 启动报告与信任告警来自内核（`KernelReport`）；
/// - 应用日志（含网络 / 认证 / 写入的原始错误）来自 [OgLAppLog]；
/// - 一键复制全部日志——用户反馈问题时最需要的东西。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../kernel/kernel.dart';
import '../../kernel/log/og_l_log_file.dart';
import '../app/error_surface.dart';

/// 关于页。
class AboutPage extends StatelessWidget {
  /// 创建页面。
  const AboutPage({required this.report, super.key});

  /// 启动报告（内核在启动时定格的快照）。
  final KernelReport report;

  /// 日志尾部最多显示多少条（超出的仍会被"复制全部"带走）。
  static const int _logTailShown = 80;

  Future<void> _copyAll(BuildContext context, List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: lines.join('\n')));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已复制 ${lines.length} 行日志到剪贴板')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListenableBuilder(
      listenable: OgLAppLog.instance,
      builder: (BuildContext context, Widget? _) {
        final List<String> kernelLines =
            report.logTail.map((entry) => entry.toString()).toList();
        final List<String> appLines = OgLAppLog.instance.entries
            .map((OgLAppLogEntry entry) => entry.toDisplay())
            .toList();
        final List<String> allLines = <String>[...kernelLines, ...appLines];
        final int shown =
            allLines.length > _logTailShown ? _logTailShown : allLines.length;
        final List<String> tail = allLines.sublist(allLines.length - shown);

        return Scaffold(
          appBar: AppBar(
            title: const Text('关于'),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.content_copy),
                tooltip: '复制全部日志',
                onPressed: () => _copyAll(context, allLines),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('版本', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('版本'),
                      subtitle: Text(report.appVersion),
                    ),
                    ListTile(
                      leading: const Icon(Icons.schedule),
                      title: const Text('生成时间'),
                      subtitle: Text('${report.generatedAt}'),
                    ),
                    ListTile(
                      leading: Icon(
                        report.safeMode ? Icons.warning_amber_rounded : Icons.shield_outlined,
                      ),
                      title: const Text('安全模式'),
                      subtitle: Text(report.safeMode ? '是（部分能力被关闭）' : '否（全部能力可用）'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              Text('日志文件', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('当前日志文件'),
                      subtitle: Text(OgLLogFile.filePath ?? '未启用落盘（原因见下）'),
                      trailing: TextButton(
                        onPressed: () async {
                          final String path = OgLLogFile.filePath ?? '(未启用)';
                          await Clipboard.setData(ClipboardData(text: path));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('已复制：$path')),
                            );
                          }
                        },
                        child: const Text('复制路径'),
                      ),
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
                    if (!OgLLogFile.isEnabled)
                      ListTile(
                        title: const Text('尝试过的目录'),
                        subtitle: Text(OgLLogFile.triedDirectories.join('\n')),
                      ),
                    const ListTile(
                      leading: Icon(Icons.lightbulb_outline),
                      title: Text('日志内容'),
                      subtitle: Text(
                        '启动链路 / 页面加载（开始·结果·耗时）/ 每个网络请求（状态码·耗时）/ 全部异常堆栈',
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 32),
              ExpansionTile(
                title: const Text('启动报告'),
                subtitle: Text(report.bootSummary),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: <Widget>[
                  for (final MapEntry<String, String> entry
                      in report.moduleStates.entries)
                    _KeyValueRow(label: entry.key, value: entry.value),
                  _KeyValueRow(
                    label: '层级桥',
                    value: report.bridges.join('、'),
                  ),
                  _KeyValueRow(
                    label: '服务',
                    value: '${report.services.length} 项',
                  ),
                ],
              ),
              ExpansionTile(
                title: const Text('信任告警'),
                subtitle: Text(
                  report.trustWarnings.isEmpty
                      ? '没有告警：引导清单签名与模块依赖都通过'
                      : '共 ${report.trustWarnings.length} 条（必须处理）',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: <Widget>[
                  if (report.trustWarnings.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.verified_outlined),
                      title: Text('信任链正常'),
                    )
                  else
                    for (final Object warning in report.trustWarnings)
                      ListTile(
                        leading: Icon(
                          Icons.warning_amber_rounded,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(warning.toString()),
                      ),
                ],
              ),
              ExpansionTile(
                title: const Text('依赖图'),
                subtitle: const Text('模块之间谁依赖谁（排查"为什么没启动"用）'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: <Widget>[
                  SelectableText(
                    report.moduleGraph,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
              ExpansionTile(
                title: const Text('启动阶段'),
                subtitle: Text('共 ${report.stages.length} 个阶段'),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: <Widget>[
                  for (final Object stage in report.stages)
                    SelectableText(
                      stage.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              ExpansionTile(
                title: const Text('日志'),
                subtitle: Text(
                  allLines.isEmpty
                      ? '还没有日志'
                      : '共 ${allLines.length} 行；下面显示最后 $shown 行',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: <Widget>[
                  if (tail.isEmpty)
                    const ListTile(title: Text('没有日志'))
                  else
                    SelectableText(
                      tail.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _copyAll(context, allLines),
                      icon: const Icon(Icons.content_copy, size: 16),
                      label: const Text('复制全部日志'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
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