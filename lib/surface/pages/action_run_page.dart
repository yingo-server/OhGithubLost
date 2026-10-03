/// L3 展示级 · Actions 运行详情（作业 + 步骤 + 重跑 / 取消）。
///
/// 补齐"Actions 只列运行、点不动"的缺口：现在能看到每个 job 的每一步，
/// 并支持对已结束的运行**重新运行**、对进行中的运行**取消**。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import 'action_log_page.dart';

/// 一次运行 + 它的作业列表。
class _RunDetail {
  const _RunDetail(this.run, this.jobs);

  final Map<String, dynamic> run;
  final List<Map<String, dynamic>> jobs;
}

/// 运行详情页。
class ActionRunPage extends StatefulWidget {
  /// 创建页面。
  const ActionRunPage({
    required this.surface,
    required this.fullName,
    required this.run,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 运行对象（列表接口返回）。
  final Map<String, dynamic> run;

  /// 运行 ID。
  int get runId => ghInt(run, 'id');

  @override
  State<ActionRunPage> createState() => _ActionRunPageState();
}

class _ActionRunPageState extends State<ActionRunPage> {
  AsyncController<_RunDetail>? _detail;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _detailC().loadIfNeeded();
  }

  @override
  void dispose() {
    _detail?.dispose();
    super.dispose();
  }

  AsyncController<_RunDetail> _detailC() {
    final existing = _detail;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<_RunDetail>(
      label: '运行详情',
      isEmpty: (_RunDetail value) => false,
      loader: () async {
        final Map<String, dynamic>? run =
            await widget.surface.domain.api.workflowRun(
              widget.fullName,
              widget.runId,
            );
        final List<Map<String, dynamic>> jobs =
            await widget.surface.domain.api.workflowRunJobs(
          widget.fullName,
          widget.runId,
        );
        return _RunDetail(run ?? widget.run, jobs);
      },
    );
    _detail = controller;
    return controller;
  }

  Future<void> _rerun() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api
          .rerunWorkflowRun(widget.fullName, widget.runId);
      OgLAppLog.instance.result('Actions', '已触发重新运行', '#${widget.runId}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已触发重新运行')),
        );
      }
      await _detailC().load();
    } catch (error) {
      OgLAppLog.instance.add(
        'Actions',
        '重新运行失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新运行失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _cancel() async {
    if (_busy) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('取消运行'),
        content: const Text('将请求 GitHub 取消这次运行；已完成的步骤不会回滚。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('返回'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('取消运行'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api
          .cancelWorkflowRun(widget.fullName, widget.runId);
      OgLAppLog.instance.result('Actions', '已请求取消', '#${widget.runId}');
      await _detailC().load();
    } catch (error) {
      OgLAppLog.instance.add(
        'Actions',
        '取消失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  IconData _statusIcon(String status, String conclusion) {
    if (status != 'completed') {
      return Icons.sync;
    }
    switch (conclusion) {
      case 'success':
        return Icons.check_circle;
      case 'failure':
      case 'timed_out':
        return Icons.error;
      case 'cancelled':
      case 'skipped':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  Color _statusColor(ThemeData theme, String status, String conclusion) {
    if (status != 'completed') {
      return theme.colorScheme.primary;
    }
    switch (conclusion) {
      case 'success':
        return const Color(0xFF1A7F37);
      case 'failure':
      case 'timed_out':
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.outline;
    }
  }

  /// 把步骤/作业的 `started_at` → `completed_at` 折成"耗时"（缺失返回空串）。
  static String _durationText(Map<String, dynamic> node) {
    final DateTime? start = DateTime.tryParse(ghStr(node, 'started_at'));
    final DateTime? end = DateTime.tryParse(ghStr(node, 'completed_at'));
    if (start == null || end == null) {
      return '';
    }
    final Duration d = end.difference(start);
    if (d.isNegative) {
      return '';
    }
    if (d.inSeconds < 60) {
      return '耗时 ${d.inSeconds}s';
    }
    return '耗时 ${d.inMinutes}m${d.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '运行 #${ghInt(widget.run, 'run_number')}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: '查看日志',
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (BuildContext context) => ActionLogPage(
                    surface: widget.surface,
                    fullName: widget.fullName,
                    runId: widget.runId,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: AsyncView<_RunDetail>(
        controller: _detailC(),
        emptyText: '没有运行详情',
        builder: (BuildContext context, _RunDetail detail) {
          final Map<String, dynamic> run = detail.run;
          final String status = ghStr(run, 'status');
          final String conclusion = ghStr(run, 'conclusion');
          final String htmlUrl = ghStr(run, 'html_url');
          final bool running = status != 'completed';
          return RefreshIndicator(
            onRefresh: () => _detailC().load(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      _statusIcon(status, conclusion),
                      color: _statusColor(theme, status, conclusion),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ghStr(run, 'display_title').isEmpty
                            ? ghStr(run, 'name')
                            : ghStr(run, 'display_title'),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${ghStr(run, 'name')} · ${ghStr(run, 'event')} · '
                  '${ghStr(run, 'head_branch')} · ${ghShortSha(ghStr(run, 'head_sha'))}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '状态：$status'
                  '${conclusion.isEmpty ? '' : ' / $conclusion'} · '
                  '${ghDate(run, 'created_at')}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    if (!running)
                      FilledButton.tonalIcon(
                        onPressed: _busy ? null : _rerun,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重新运行'),
                      ),
                    if (running)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _cancel,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('取消运行'),
                      ),
                    if (htmlUrl.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          unawaited(openLinkOrCopy(context, htmlUrl, tag: 'Actions'));
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('浏览器打开'),
                      ),
                  ],
                ),
                const Divider(height: 32),
                Text('作业', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                if (detail.jobs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('没有作业记录'),
                  )
                else
                  for (final Map<String, dynamic> job in detail.jobs)
                    Card(
                      child: ExpansionTile(
                        leading: Icon(
                          _statusIcon(
                            ghStr(job, 'status'),
                            ghStr(job, 'conclusion'),
                          ),
                          color: _statusColor(
                            theme,
                            ghStr(job, 'status'),
                            ghStr(job, 'conclusion'),
                          ),
                        ),
                        title: Text(
                          ghStr(job, 'name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${ghStr(job, 'status')} · '
                          '${ghStr(job, 'conclusion').isEmpty ? '—' : ghStr(job, 'conclusion')}',
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        children: <Widget>[
                          for (final Object? rawStep in (job['steps'] is List
                              ? job['steps'] as List<Object?>
                              : const <Object?>[]))
                            if (rawStep is Map<Object?, Object?>)
                              Builder(builder: (BuildContext context) {
                                final Map<String, dynamic> step =
                                    Map<String, dynamic>.from(rawStep);
                                return ListTile(
                                  dense: true,
                                  leading: Icon(
                                    _statusIcon(
                                      ghStr(step, 'status'),
                                      ghStr(step, 'conclusion'),
                                    ),
                                    size: 18,
                                    color: _statusColor(
                                      theme,
                                      ghStr(step, 'status'),
                                      ghStr(step, 'conclusion'),
                                    ),
                                  ),
                                  title: Text(
                                    '${ghInt(step, 'number')}. ${ghStr(step, 'name')}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    <String>[
                                      ghStr(step, 'status'),
                                      if (ghStr(step, 'conclusion').isNotEmpty)
                                        ghStr(step, 'conclusion'),
                                      if (_durationText(step).isNotEmpty)
                                        _durationText(step),
                                    ].join(' · '),
                                  ),
                                );
                              }),
                        ],
                      ),
                    ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}