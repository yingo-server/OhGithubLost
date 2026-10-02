/// L3 展示级 · Gist 详情（查看 / 编辑 / 删除文件）。
///
/// 单文件内容可能被服务端截断（`truncated: true`）；此时回退用
/// `raw_url` 拉全文，**绝不把"被截断的内容"当成完整内容展示**。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/code_view.dart';

/// 一个 Gist 文件（内容已解析）。
class _GistFile {
  const _GistFile({
    required this.name,
    required this.language,
    required this.content,
    required this.size,
  });

  final String name;
  final String language;
  final String content;
  final int size;
}

/// 一个 Gist（文件已解析）。
class _GistDetail {
  const _GistDetail({
    required this.description,
    required this.isPublic,
    required this.htmlUrl,
    required this.files,
  });

  final String description;
  final bool isPublic;
  final String htmlUrl;
  final List<_GistFile> files;
}

/// Gist 详情页。
class GistDetailPage extends StatefulWidget {
  /// 创建页面。
  const GistDetailPage({
    required this.surface,
    required this.gistId,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// Gist ID。
  final String gistId;

  @override
  State<GistDetailPage> createState() => _GistDetailPageState();
}

class _GistDetailPageState extends State<GistDetailPage> {
  AsyncController<_GistDetail>? _detail;
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

  AsyncController<_GistDetail> _detailC() {
    final existing = _detail;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<_GistDetail>(
      label: 'Gist 详情',
      isEmpty: (_GistDetail value) => value.files.isEmpty,
      loader: () async {
        final Map<String, dynamic>? gist =
            await widget.surface.domain.api.gist(widget.gistId);
        if (gist == null) {
          throw StateError('Gist 不存在或无权访问');
        }
        final Object? filesRaw = gist['files'];
        final List<_GistFile> files = <_GistFile>[];
        if (filesRaw is Map<Object?, Object?>) {
          for (final Object? value in filesRaw.values) {
            if (value is! Map<Object?, Object?>) {
              continue;
            }
            final Map<String, dynamic> f = Map<String, dynamic>.from(value);
            final String name = ghStr(f, 'filename');
            String content = ghStr(f, 'content');
            final bool truncated = f['truncated'] == true;
            if (truncated || content.isEmpty) {
              final String raw = ghStr(f, 'raw_url');
              if (raw.isNotEmpty) {
                try {
                  content = await widget.surface.domain.api.rawText(raw);
                } catch (_) {
                  // 拉全文失败：保留已拿到的内容（可能为空），由 UI 说明。
                }
              }
            }
            files.add(_GistFile(
              name: name,
              language: ghStr(f, 'language'),
              content: content,
              size: ghInt(f, 'size'),
            ));
          }
        }
        return _GistDetail(
          description: ghStr(gist, 'description'),
          isPublic: gist['public'] == true,
          htmlUrl: ghStr(gist, 'html_url'),
          files: files,
        );
      },
    );
    _detail = controller;
    return controller;
  }

  Future<void> _editFile(_GistFile file) async {
    final TextEditingController controller =
        TextEditingController(text: file.content);
    final String? updated = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('编辑 ${file.name}'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            minLines: 10,
            maxLines: 20,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (updated == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.updateGist(
        widget.gistId,
        files: <String, String?>{file.name: updated},
      );
      OgLAppLog.instance.result('Gist', '已更新', file.name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存')),
        );
      }
      await _detailC().load();
    } catch (error) {
      OgLAppLog.instance.add(
        'Gist',
        '更新失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteGist() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除 Gist'),
        content: const Text('将从 GitHub 永久删除该 Gist，操作不可撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.deleteGist(widget.gistId);
      OgLAppLog.instance.result('Gist', '已删除', widget.gistId);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      OgLAppLog.instance.add(
        'Gist',
        '删除失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _copy(_GistFile file) async {
    await Clipboard.setData(ClipboardData(text: file.content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${file.name}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gist 详情'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除 Gist',
            onPressed: _busy ? null : _deleteGist,
          ),
        ],
      ),
      body: AsyncView<_GistDetail>(
        controller: _detailC(),
        emptyIcon: Icons.article_outlined,
        emptyText: '这个 Gist 没有文件',
        builder: (BuildContext context, _GistDetail detail) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            Text(
              detail.description.isEmpty ? '（无描述）' : detail.description,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${detail.isPublic ? '公开' : '私密'} · ${detail.files.length} 个文件',
              style: theme.textTheme.bodySmall,
            ),
            if (detail.htmlUrl.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    unawaited(
                      openLinkOrCopy(context, detail.htmlUrl, tag: 'Gist'),
                    );
                  },
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('在浏览器打开'),
                ),
              ),
            ],
            const Divider(height: 32),
            for (final _GistFile file in detail.files)
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.description_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  file.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  ghSizeText(file.size),
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_all_outlined),
                            tooltip: '复制内容',
                            onPressed: () => unawaited(_copy(file)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: '编辑',
                            onPressed:
                                _busy ? null : () => unawaited(_editFile(file)),
                          ),
                        ],
                      ),
                    ),
                    if (file.content.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('（内容为空或无法读取，可在浏览器查看）'),
                      )
                    else
                      CodeView(
                        code: file.content,
                        language: file.language.isEmpty
                            ? ogLDetectLanguage(file.name)
                            : file.language,
                        showLineNumbers: false,
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}