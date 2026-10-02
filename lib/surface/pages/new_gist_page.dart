/// L3 展示级 · 新建 Gist（单文件）。
///
/// 说明：GitHub 支持多文件 Gist，但移动端输入体验有限；
/// 这里先做**单文件**新建，详情页可继续追加/编辑。
library;

import 'package:flutter/material.dart';

import '../app/error_surface.dart';
import '../surface_bridge.dart';

/// 新建 Gist 页。
class NewGistPage extends StatefulWidget {
  /// 创建页面。
  const NewGistPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<NewGistPage> createState() => _NewGistPageState();
}

class _NewGistPageState extends State<NewGistPage> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _filename =
      TextEditingController(text: 'snippet.txt');
  final TextEditingController _content = TextEditingController();
  bool _public = false;
  bool _busy = false;

  @override
  void dispose() {
    _description.dispose();
    _filename.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String filename = _filename.text.trim();
    if (filename.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写文件名')),
      );
      return;
    }
    if (_content.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('内容不能为空')),
      );
      return;
    }
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.createGist(
        files: <String, String>{filename: _content.text},
        description: _description.text,
        public: _public,
      );
      OgLAppLog.instance.result('Gist', '已创建', filename);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Gist',
        '创建失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('新建 Gist'),
        actions: <Widget>[
          TextButton(
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? '创建中…' : '创建'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _description,
            decoration: const InputDecoration(
              labelText: '描述（可选）',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _filename,
            decoration: const InputDecoration(
              labelText: '文件名（含扩展名，决定高亮语言）',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.insert_drive_file_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Text('内容', style: theme.textTheme.labelLarge),
          const SizedBox(height: 6),
          TextField(
            controller: _content,
            minLines: 8,
            maxLines: 20,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '粘贴或输入代码 / 文本',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('公开 Gist'),
            subtitle: const Text('公开后任何人可通过链接访问'),
            value: _public,
            onChanged: (bool on) => setState(() => _public = on),
          ),
          const SizedBox(height: 8),
          Text(
            '提示：文件名扩展名会影响高亮语言（如 main.dart / app.py）。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}