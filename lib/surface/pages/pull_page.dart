/// L3 展示级 · PR 详情（描述 + 变更文件）。
///
/// - 描述按 Markdown 渲染；
/// - 文件列表带 `+N / -M` 统计；有补丁文本时可展开查看（等宽）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/readme_view.dart';

/// PR 详情页。
class PullPage extends StatefulWidget {
  /// 创建页面。
  const PullPage({
    required this.surface,
    required this.fullName,
    required this.pull,
    required this.number,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  /// PR 原始对象（列表接口返回的 Map）。
  final Map<String, dynamic> pull;

  /// PR 编号。
  final int number;

  @override
  State<PullPage> createState() => _PullPageState();
}

class _PullPageState extends State<PullPage> {
  AsyncController<List<Map<String, dynamic>>>? _files;

  @override
  void initState() {
    super.initState();
    _filesC().loadIfNeeded();
  }

  @override
  void dispose() {
    _files?.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _filesC() {
    final existing = _files;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: '变更文件',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () =>
          widget.surface.domain.api.pullFiles(widget.fullName, widget.number),
    );
    _files = controller;
    return controller;
  }

  /// PR 状态 → 中文（打开 / 已合并 / 草稿 / 已关闭）。
  String _stateText() {
    final String state = ghStr(widget.pull, 'state');
    final bool merged = widget.pull['merged'] == true;
    final bool draft = widget.pull['draft'] == true;
    if (merged) {
      return '已合并';
    }
    if (state == 'closed') {
      return '已关闭';
    }
    if (draft) {
      return '草稿';
    }
    return state == 'open' ? '打开中' : state;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String title = ghStr(widget.pull, 'title');
    final String body = ghStrOrNull(widget.pull, 'body') ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '#${widget.number}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'by ${ghLogin(widget.pull)} · '
            '${ghDate(widget.pull, 'created_at')} · '
            '${_stateText()}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (body.trim().isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ReadmeView(
                  markdown: body,
                  onOpenLink: (Uri uri) {
                    unawaited(openExternalLink(uri, tag: 'PR'));
                  },
                ),
              ),
            ),
          const Divider(height: 32),
          Text('变更文件', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AsyncView<List<Map<String, dynamic>>>(
            controller: _filesC(),
            fill: false,
            emptyIcon: Icons.description_outlined,
            emptyText: '没有变更文件',
            builder: (
              BuildContext context,
              List<Map<String, dynamic>> files,
            ) =>
                Column(
              children: <Widget>[
                for (final Map<String, dynamic> file in files) _fileTile(file),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _fileTile(Map<String, dynamic> file) {
    final String name = ghStr(file, 'filename');
    final int additions = ghInt(file, 'additions');
    final int deletions = ghInt(file, 'deletions');
    final String? patch = ghStrOrNull(file, 'patch');
    final String subtitle =
        '${ghFileStatusText(ghStr(file, 'status'))} · +$additions / -$deletions';
    if (patch == null || patch.trim().isEmpty) {
      return ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
      );
    }
    return ExpansionTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SelectableText(
            patch,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ],
    );
  }
}