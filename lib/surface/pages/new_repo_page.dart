/// L3 展示级 · 新建仓库（表单）。
///
/// - 只保留必要字段：名称 / 描述 / 是否私有；
/// - 提交失败**保留输入**并给出可读错误（不是"点了没反应"）；
/// - 成功后把新仓库对象带回上一页（pop 值）。
library;

import 'package:flutter/material.dart';

import '../types.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';

/// 新建仓库页。
class NewRepoPage extends StatefulWidget {
  /// 创建页面。
  const NewRepoPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<NewRepoPage> createState() => _NewRepoPageState();
}

class _NewRepoPageState extends State<NewRepoPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  bool _private = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final String name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请先填写仓库名');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GhRepo repo = await widget.surface.domain.api.createRepo(
        name: name,
        description:
            _description.text.trim().isEmpty ? null : _description.text.trim(),
        private: _private,
      );
      OgLAppLog.instance.result('新建仓库', '已创建', repo.fullName);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(repo);
    } catch (error) {
      OgLAppLog.instance.add(
        '新建仓库',
        '创建失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '创建失败：$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('新建仓库')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _name,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '仓库名',
              hintText: 'my-project',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '描述（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('私有仓库'),
            subtitle: const Text('仅自己可见'),
            value: _private,
            onChanged: _busy
                ? null
                : (bool value) => setState(() => _private = value),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '创建中…' : '创建仓库'),
          ),
        ],
      ),
    );
  }
}