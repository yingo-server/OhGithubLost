/// L3 展示级 · Actions 运行日志（按 job 展示，可搜索）。
///
/// 数据来自中枢层 `IxActionLogs`（带令牌下载日志 zip 并解压），
/// 页面只负责呈现与检索。
library;

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../surface_bridge.dart';

/// Actions 日志页。
class ActionLogPage extends StatefulWidget {
  /// 创建页面。
  const ActionLogPage({
    required this.surface,
    required this.fullName,
    required this.runId,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 运行 ID。
  final int runId;

  @override
  State<ActionLogPage> createState() => _ActionLogPageState();
}

class _ActionLogPageState extends State<ActionLogPage> {
  AsyncController<Map<String, String>>? _logs;
  final TextEditingController _query = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _logsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _logs?.dispose();
    _query.dispose();
    super.dispose();
  }

  AsyncController<Map<String, String>> _logsC() {
    final existing = _logs;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<Map<String, String>>(
      label: '运行日志',
      isEmpty: (Map<String, String> value) => value.isEmpty,
      loader: () => widget.surface.domain.actionLogs
          .fetch(widget.fullName, widget.runId),
    );
    _logs = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新拉取',
            onPressed: () => _logsC().load(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _query,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                hintText: '搜索 job 名',
              ),
              onChanged: (String value) => setState(() => _filter = value),
            ),
          ),
          Expanded(
            child: AsyncView<Map<String, String>>(
              controller: _logsC(),
              emptyIcon: Icons.receipt_long,
              emptyText: '没有日志（可能尚未完成，或令牌缺少 Actions 权限）',
              builder: (BuildContext context, Map<String, String> logs) {
                final List<String> keys = logs.keys
                    .where((String k) =>
                        _filter.isEmpty ||
                        k.toLowerCase().contains(_filter.toLowerCase()))
                    .toList()
                  ..sort();
                if (keys.isEmpty) {
                  return const Center(child: Text('没有匹配的 job'));
                }
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: <Widget>[
                    for (final String key in keys)
                      Card(
                        clipBehavior: Clip.antiAlias,
                        child: ExpansionTile(
                          leading: const Icon(Icons.terminal),
                          title: Text(
                            key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          childrenPadding:
                              const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          children: <Widget>[
                            Container(
                              width: double.infinity,
                              constraints: const BoxConstraints(maxHeight: 420),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  logs[key] ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}