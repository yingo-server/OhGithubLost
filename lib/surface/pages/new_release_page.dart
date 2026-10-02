/// L3 展示级 · 新建发布（表单）。
///
/// - 标签必填（如 `v1.0.0`）；名称 / 说明可选；可勾选"预发布"；
/// - 目标提交点使用仓库默认分支；
/// - 成功后把新发布对象带回上一页（pop 值）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';

/// 新建发布页。
class NewReleasePage extends StatefulWidget {
  /// 创建页面。
  const NewReleasePage({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  /// 仓库默认分支（作为目标提交点）。
  final String defaultBranch;

  @override
  State<NewReleasePage> createState() => _NewReleasePageState();
}

class _NewReleasePageState extends State<NewReleasePage> {
  final TextEditingController _tag = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _prerelease = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _tag.dispose();
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final String tag = _tag.text.trim();
    if (tag.isEmpty) {
      setState(() => _error = '请先填写标签（如 v1.0.0）');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final GhRelease release = await widget.surface.domain.api.createRelease(
        widget.fullName,
        tagName: tag,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        prerelease: _prerelease,
        targetCommitish:
            widget.defaultBranch.isEmpty ? null : widget.defaultBranch,
      );
      OgLAppLog.instance.result('发布', '已创建', release.tagName);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(release);
    } catch (error) {
      OgLAppLog.instance.add(
        '发布',
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
      appBar: AppBar(title: const Text('新建发布')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _tag,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '标签（tag）',
              hintText: 'v1.0.0',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '标题（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: '说明（可选，支持 Markdown）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('预发布'),
            subtitle: const Text('标记为 pre-release'),
            value: _prerelease,
            onChanged: _busy
                ? null
                : (bool value) => setState(() => _prerelease = value),
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
            child: Text(_busy ? '发布中…' : '创建发布'),
          ),
        ],
      ),
    );
  }
}