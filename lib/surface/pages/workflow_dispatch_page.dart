/// L3 展示级 · 手动触发工作流（`workflow_dispatch`）。
///
/// R10：选中工作流后，**读取它的 YAML 声明**（`on.workflow_dispatch.inputs`），
/// 把必选参数 / 默认值 / 可选项**渲染成表单**，而不是让用户手写 `key=value`。
/// 仍保留“高级：直接输入”的入口，兼容无法解析（或私有语法）的情况。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:yaml/yaml.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';

/// 一个 `workflow_dispatch` 参数声明。
class _WfInput {
  _WfInput({
    required this.name,
    this.description,
    this.required = false,
    this.defaultValue,
    this.type = 'string',
    this.options = const <String>[],
  });

  final String name;
  final String? description;
  final bool required;
  final String? defaultValue;
  final String type;
  final List<String> options;
}

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
  String? _selectedPath;
  bool _busy = false;

  /// 解析出的参数表单状态。
  List<_WfInput> _form = const <_WfInput>[];
  final Map<String, TextEditingController> _formText =
      <String, TextEditingController>{};
  final Map<String, String> _formChoice = <String, String>{};
  final Map<String, bool> _formBool = <String, bool>{};
  bool _loadingForm = false;
  String? _formError;

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
    for (final TextEditingController c in _formText.values) {
      c.dispose();
    }
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

  /// 解析 `on.workflow_dispatch.inputs`（YAML 1.2：`on` 作为普通键）。
  ///
  /// 兼容 `on:` 被解析成布尔键 `true` 的情况（部分 YAML 实现）。
  static List<_WfInput> _parseWorkflowInputs(String text) {
    final Object? doc = loadYaml(text);
    if (doc is! Map) {
      return const <_WfInput>[];
    }
    Object? on = doc['on'];
    on ??= doc[true];
    if (on is! Map) {
      // `on: workflow_dispatch`（无参数）或无法识别。
      return const <_WfInput>[];
    }
    Object? wd = on['workflow_dispatch'];
    wd ??= on[true];
    if (wd is! Map) {
      return const <_WfInput>[];
    }
    final Object? inputs = wd['inputs'];
    if (inputs is! Map) {
      return const <_WfInput>[];
    }
    final List<_WfInput> result = <_WfInput>[];
    for (final MapEntry<Object?, Object?> entry in inputs.entries) {
      final String name = '${entry.key}';
      final Object? cfg = entry.value;
      if (cfg is Map) {
        final Object? options = cfg['options'];
        result.add(_WfInput(
          name: name,
          description: cfg['description']?.toString(),
          required: cfg['required'] == true,
          defaultValue: cfg['default']?.toString(),
          type: cfg['type']?.toString() ?? 'string',
          options: options is List
              ? options.map((Object? o) => '$o').toList()
              : const <String>[],
        ));
      } else {
        result.add(_WfInput(name: name));
      }
    }
    return result;
  }

  Future<void> _loadForm(String path) async {
    setState(() {
      _loadingForm = true;
      _formError = null;
      _form = const <_WfInput>[];
      for (final TextEditingController c in _formText.values) {
        c.dispose();
      }
      _formText.clear();
      _formChoice.clear();
      _formBool.clear();
    });
    try {
      final String? text = await widget.surface.domain.api.rawFileText(
        widget.fullName,
        path,
        branch: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
      );
      if (!mounted) {
        return;
      }
      if (text == null) {
        setState(() {
          _loadingForm = false;
          _formError = '读不到工作流文件（$path）：可能路径变更或令牌权限不足';
        });
        return;
      }
      final List<_WfInput> parsed = _parseWorkflowInputs(text);
      setState(() {
        _loadingForm = false;
        _form = parsed;
        for (final _WfInput input in parsed) {
          if (input.type == 'choice') {
            _formChoice[input.name] =
                input.defaultValue ?? (input.options.isEmpty ? '' : input.options.first);
          } else if (input.type == 'boolean') {
            _formBool[input.name] = input.defaultValue == 'true';
          } else {
            _formText[input.name] =
                TextEditingController(text: input.defaultValue ?? '');
          }
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingForm = false;
        _formError = '解析工作流参数失败：$error';
      });
    }
  }

  /// 从下拉变更工作流时调用。
  void _selectWorkflow(Map<String, dynamic> wf) {
    setState(() {
      _selected = ghInt(wf, 'id').toString();
      _selectedPath = ghStr(wf, 'path');
    });
    final String? path = _selectedPath;
    if (path != null && path.isNotEmpty) {
      _loadForm(path);
    }
  }

  /// 表单 → inputs；缺必选即报错。
  Map<String, String> _collectFormInputs() {
    final Map<String, String> result = <String, String>{};
    final List<String> missing = <String>[];
    for (final _WfInput input in _form) {
      String value;
      if (input.type == 'choice') {
        value = _formChoice[input.name] ?? '';
      } else if (input.type == 'boolean') {
        value = (_formBool[input.name] ?? false) ? 'true' : 'false';
      } else {
        value = _formText[input.name]?.text.trim() ?? '';
      }
      if (value.isEmpty && input.required) {
        missing.add(input.name);
        continue;
      }
      if (value.isNotEmpty) {
        result[input.name] = value;
      }
    }
    if (missing.isNotEmpty) {
      throw FormatException('缺少必选参数：${missing.join('、')}');
    }
    return result;
  }

  /// 解析“高级：直接输入”文本框（JSON 或每行 key=value）。
  Map<String, String> _parseManualInputs() {
    final String raw = _inputs.text.trim();
    if (raw.isEmpty) {
      return const <String, String>{};
    }
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
      inputs = <String, String>{
        ..._collectFormInputs(),
        ..._parseManualInputs(),
      };
    } on FormatException catch (error) {
      _toast(error.message);
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
          if (_selected == null && workflows.isNotEmpty) {
            // 默认选中第一个工作流——不能在 build 中直接 setState，
            // 放到下一帧执行。
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selected == null) {
                _selectWorkflow(workflows.first);
              }
            });
          }
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
                        onTap: _busy ? null : () => _selectWorkflow(wf),
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
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('参数', style: theme.textTheme.titleSmall),
                  ),
                  if (_loadingForm)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ..._formSection(theme),
              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('高级：直接输入', style: theme.textTheme.titleSmall),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                children: <Widget>[
                  TextField(
                    controller: _inputs,
                    minLines: 3,
                    maxLines: 8,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: '每行 key=value，例如\nversion_name=2.0.0\nchannel=stable',
                    ),
                  ),
                ],
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

  /// 参数表单区：按类型渲染控件；无参数则给出说明。
  List<Widget> _formSection(ThemeData theme) {
    if (_formError != null) {
      return <Widget>[
        Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(_formError!, style: theme.textTheme.bodySmall),
          ),
        ),
      ];
    }
    if (_form.isEmpty) {
      return <Widget>[
        Text(
          '该工作流没有声明参数（可直接触发）。',
          style: theme.textTheme.bodySmall,
        ),
      ];
    }
    return <Widget>[
      for (final _WfInput input in _form)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _fieldFor(theme, input),
        ),
    ];
  }

  Widget _fieldFor(ThemeData theme, _WfInput input) {
    final String label = input.name + (input.required ? '（必选）' : '（可选）');
    final String? helper = input.description;
    if (input.type == 'choice') {
      final String value = _formChoice[input.name] ?? '';
      return DropdownButtonFormField<String>(
        initialValue: input.options.contains(value) ? value : null,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
        items: <DropdownMenuItem<String>>[
          for (final String option in input.options)
            DropdownMenuItem<String>(value: option, child: Text(option)),
        ],
        onChanged: (String? v) =>
            setState(() => _formChoice[input.name] = v ?? ''),
      );
    }
    if (input.type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: helper == null ? null : Text(helper),
        value: _formBool[input.name] ?? false,
        onChanged: (bool v) => setState(() => _formBool[input.name] = v),
      );
    }
    return TextField(
      controller: _formText[input.name],
      keyboardType: input.type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: input.type == 'number'
          ? <TextInputFormatter>[FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))]
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        border: const OutlineInputBorder(),
      ),
    );
  }
}