/// L3 展示级 · 议题详情（正文 + 评论 + 关闭 / 重开）。
///
/// - 正文与评论都按 Markdown 渲染（README 同一条渲染管线）；
/// - 关闭 / 重开是**状态切换**：二次确认，失败可见（横幅 + 日志）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/readme_view.dart';

/// 评论文本上限（字符数）。
///
/// GitHub 对正文有长度限制，这里取一个留有余量的本地阈值：
/// 超限时本地即可给出清晰提示，而不是把请求打出去再被服务端拒绝。
const int _kMaxCommentChars = 60000;

/// 议题详情页。
class IssuePage extends StatefulWidget {
  /// 创建页面。
  const IssuePage({
    required this.surface,
    required this.fullName,
    required this.issue,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  /// 议题原始对象（列表接口返回的 Map）。
  final Map<String, dynamic> issue;

  @override
  State<IssuePage> createState() => _IssuePageState();
}

class _IssuePageState extends State<IssuePage> {
  AsyncController<List<Map<String, dynamic>>>? _comments;
  late String _state = ghStr(widget.issue, 'state');
  bool _busy = false;

  /// 评论输入。
  final TextEditingController _comment = TextEditingController();
  bool _posting = false;

  int get _number => ghInt(widget.issue, 'number');

  @override
  void initState() {
    super.initState();
    _commentsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _comments?.dispose();
    _comment.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _commentsC() {
    final existing = _comments;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: '评论',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () =>
          widget.surface.domain.api.issueComments(widget.fullName, _number),
    );
    _comments = controller;
    return controller;
  }

  Future<void> _toggleState() async {
    if (_busy) {
      return;
    }
    final bool closing = _state == 'open';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(closing ? '关闭议题 #$_number' : '重新打开议题 #$_number'),
        content: Text(closing ? '关闭后仍可在「已关闭」筛选里看到它。' : '重新打开后议题会回到打开列表。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(closing ? '关闭' : '重新打开'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.updateIssue(
        widget.fullName,
        _number,
        state: closing ? 'closed' : 'open',
      );
      OgLAppLog.instance.result(
        '议题',
        closing ? '已关闭' : '已重新打开',
        '#$_number',
      );
      if (!mounted) {
        return;
      }
      setState(() => _state = closing ? 'closed' : 'open');
    } catch (error) {
      OgLAppLog.instance.add(
        '议题',
        '状态切换失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _postComment() async {
    final String body = _comment.text.trim();
    if (body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('评论不能为空')),
      );
      return;
    }
    // 护栏：GitHub 对评论正文有长度上限；本地先拦，避免把超大负载发出去
    // 后被服务端拒绝（浪费一次往返，且错误信息不如本地清晰）。
    if (body.length > _kMaxCommentChars) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('评论过长（${body.length}/$_kMaxCommentChars 字符），请精简后重试'),
        ),
      );
      return;
    }
    if (_posting) {
      return;
    }
    setState(() => _posting = true);
    try {
      await widget.surface.domain.api.createIssueComment(
        widget.fullName,
        _number,
        body: body,
      );
      OgLAppLog.instance.result('议题', '评论已发布', '#$_number');
      if (!mounted) {
        return;
      }
      _comment.clear();
      await _commentsC().load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('评论已发布')),
        );
      }
    } catch (error) {
      OgLAppLog.instance.add(
        '议题',
        '评论发布失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('评论失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _posting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String title = ghStr(widget.issue, 'title');
    final String body = ghStrOrNull(widget.issue, 'body') ?? '';
    final bool open = _state == 'open';
    return Scaffold(
      appBar: AppBar(
        title: Text('#$_number', maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'by ${ghLogin(widget.issue)} · '
            '${ghDate(widget.issue, 'created_at')} · '
            '${open ? '打开中' : '已关闭'}',
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
                    unawaited(openExternalLink(uri, tag: '议题'));
                  },
                ),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _toggleState,
              icon: Icon(open ? Icons.task_alt : Icons.undo),
              label: Text(open ? '关闭议题' : '重新打开'),
            ),
          ),
          const Divider(height: 32),
          Text('评论', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AsyncView<List<Map<String, dynamic>>>(
            controller: _commentsC(),
            fill: false,
            emptyIcon: Icons.chat_bubble_outline,
            emptyText: '还没有评论',
            builder: (
              BuildContext context,
              List<Map<String, dynamic>> comments,
            ) =>
                Column(
              children: <Widget>[
                for (final Map<String, dynamic> comment in comments)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '${ghLogin(comment)} · '
                            '${ghDate(comment, 'created_at')}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          ReadmeView(
                            markdown: ghStr(comment, 'body'),
                            onOpenLink: (Uri uri) {
                              unawaited(openExternalLink(uri, tag: '评论'));
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          Text('发表评论', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _comment,
            minLines: 3,
            maxLines: 8,
            enabled: !_posting,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '支持 Markdown；请保持友善与具体',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _posting ? null : _postComment,
              icon: const Icon(Icons.send),
              label: Text(_posting ? '发布中…' : '发表评论'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}