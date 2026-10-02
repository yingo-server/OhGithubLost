/// L3 展示级 · 新建议题（表单）。
///
/// - 标题必填；正文可选（Markdown）；
/// - 成功后 `pop(true)`，由上一页决定如何刷新。
library;

import 'package:flutter/material.dart';

import '../app/error_surface.dart';
import '../surface_bridge.dart';

/// 新建议题页。
class NewIssuePage extends StatefulWidget {
  /// 创建页面。
  const NewIssuePage({
    required this.surface,
    required this.fullName,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  @override
  State<NewIssuePage> createState() => _NewIssuePageState();
}

class _NewIssuePageState extends State<NewIssuePage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final String title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请先填写标题');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.surface.domain.api.createIssue(
        widget.fullName,
        title: title,
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
      );
      OgLAppLog.instance.result('议题', '已创建', title);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      OgLAppLog.instance.add(
        '议题',
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
      appBar: AppBar(title: const Text('新建议题')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: '正文（可选，支持 Markdown）',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
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
            child: Text(_busy ? '提交中…' : '创建议题'),
          ),
        ],
      ),
    );
  }
}