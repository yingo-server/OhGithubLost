/// L3 展示级 · 手动触发工作流（`workflow_dispatch`）。
///
/// 为什么单独成页：触发需要"选工作流 + 选 ref + 填 inputs"三步，
/// 塞进对话框会让小屏难以输入与校验；独立页面更清晰，也便于展示错误。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';

/// 手动触发页。
class WorkflowDispatchPage extends StatefulWidget {
  /// 创建页面。
  const WorkflowDispatchPage({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 默认分支（作为默认 ref）。
  final String defaultBranch;

  @override
  State<WorkflowDispatchPage> createState() => _WorkflowDispatchPageState();
}

class _WorkflowDispatchPageState extends State<WorkflowDispatchPage> {
  AsyncController<List<Map<String, dynamic>>>? _workflows;
  final TextEditingController _ref = TextEditingController();
  final TextEditingController _inputs = TextEditingController();
  String? _selected;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ref.text = widget.defaultBranch;
    _workflowsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _workflows?.dispose();
    _ref.dispose();
    _inputs.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _workflowsC() {
    final existing = _workflows;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: '工作流',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.workflows(widget.fullName),
    );
    _workflows = controller;
    return controller;
  }

  /// 解析 `inputs` 文本框：支持 JSON 对象，或每行 `key=value`。
  ///
  /// 两种都支持是为了降低使用门槛（JSON 在手机上打引号很烦）。
  Map<String, String> _parseInputs() {
    final String raw = _inputs.text.trim();
    if (raw.isEmpty) {
      return const <String, String>{};
    }
    // ① JSON 对象（键值统一转成字符串，符合 GitHub inputs 的类型要求）。
    if (raw.startsWith('{')) {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('inputs 需为 JSON 对象');
      }
      return <String, String>{
        for (final MapEntry<Object?, Object?> e in decoded.entries)
          '${e.key}': '${e.value}',
      };
    }
    // ② 每行 key=value（手机输入更省事）。
    final Map<String, String> result = <String, String>{};
    for (final String line in raw.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final int eq = trimmed.indexOf('=');
      if (eq <= 0) {
        throw const FormatException('每行需形如 key=value');
      }
      result[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
    }
    return result;
  }

  Future<void> _submit() async {
    final String workflowIdOrFile = _selected ?? '';
    if (workflowIdOrFile.isEmpty) {
      _toast('请选择要触发的工作流');
      return;
    }
    final String ref = _ref.text.trim();
    if (ref.isEmpty) {
      _toast('请填写 ref（如 main）');
      return;
    }
    Map<String, String> inputs;
    try {
      inputs = _parseInputs();
    } on FormatException catch (error) {
      _toast('inputs 格式错误：${error.message}');
      return;
    }
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.dispatchWorkflow(
        widget.fullName,
        workflowIdOrFile: workflowIdOrFile,
        ref: ref,
        inputs: inputs,
      );
      OgLAppLog.instance.result('Actions', '已触发工作流', workflowIdOrFile);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Actions',
        '触发失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        _toast('触发失败：$error（该工作流可能未声明 workflow_dispatch）');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('手动触发工作流'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '触发中…' : '触发'),
          ),
        ],
      ),
      body: AsyncView<List<Map<String, dynamic>>>(
        controller: _workflowsC(),
        emptyIcon: Icons.play_circle_outline,
        emptyText: '该仓库没有工作流（或令牌缺少 Actions 权限）',
        builder: (BuildContext context, List<Map<String, dynamic>> workflows) {
          // 默认选中第一个工作流。
          _selected ??= ghInt(workflows.first, 'id').toString();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text('工作流', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: <Widget>[
                    for (final Map<String, dynamic> wf in workflows)
                      ListTile(
                        leading: Icon(
                          _selected == ghInt(wf, 'id').toString()
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                        ),
                        title: Text(
                          ghStr(wf, 'name'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${ghStr(wf, 'path')} · ${ghStr(wf, 'state')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: _busy
                            ? null
                            : () => setState(
                                  () => _selected =
                                      ghInt(wf, 'id').toString(),
                                ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text('ref（分支 / 标签）', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _ref,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'main',
                ),
              ),
              const SizedBox(height: 16),
              Text('inputs（可选）', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              TextField(
                controller: _inputs,
                minLines: 3,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '每行 key=value，例如\nversion_name=2.0.0\nchannel=stable',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '提示：仅声明了 workflow_dispatch 的工作流可被触发；'
                '否则 GitHub 会返回 422（本页会如实提示）。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}