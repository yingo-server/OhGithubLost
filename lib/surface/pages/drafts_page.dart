/// L3 展示级 · 草稿箱（本机未提交的编辑）。
///
/// - 列出本机草稿：仓库 / 路径 / 修订 / 更新时间；
/// - 查看内容（可复制）、删除草稿；
/// - 数据来自 `GhApi.drafts`（与编辑器写入同一套键）；
/// - **订阅草稿变更**：提交清稿 / 新草稿落盘后列表自动刷新。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/animations.dart';
import '../app/async.dart';
import '../surface_bridge.dart';
import '../types.dart';

/// 草稿箱页。
class DraftsPage extends StatefulWidget {
  /// 创建页面。
  const DraftsPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<DraftsPage> createState() => _DraftsPageState();
}

class _DraftsPageState extends State<DraftsPage> {
  AsyncController<List<GhDraft>>? _drafts;

  @override
  void initState() {
    super.initState();
    _controller().loadIfNeeded();
    // 草稿变更可观察：提交清稿 / 新草稿落盘后列表自动刷新。
    widget.surface.domain.api.draftsChanged.addListener(_onDraftsChanged);
  }

  @override
  void dispose() {
    widget.surface.domain.api.draftsChanged.removeListener(_onDraftsChanged);
    _drafts?.dispose();
    super.dispose();
  }

  void _onDraftsChanged() {
    if (mounted) {
      unawaited(_controller().load());
    }
  }

  AsyncController<List<GhDraft>> _controller() {
    final existing = _drafts;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhDraft>>(
      label: '草稿',
      isEmpty: (List<GhDraft> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.drafts(),
    );
    _drafts = controller;
    return controller;
  }

  static String _fmt(DateTime time) {
    final DateTime t = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _delete(GhDraft draft) async {
    await widget.surface.domain.api.discardDraft(
      draft.repo,
      draft.path,
      branch: draft.branch.isEmpty ? null : draft.branch,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('草稿已删除')),
      );
      await _controller().load();
    }
  }

  void _view(GhDraft draft) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(draft.fileName),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              draft.content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: draft.content)));
              Navigator.of(dialogContext).pop();
            },
            child: const Text('复制内容'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_delete(draft));
            },
            child: const Text('删除草稿'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('草稿箱')),
      body: AsyncView<List<GhDraft>>(
        controller: _controller(),
        emptyIcon: Icons.edit_note,
        emptyText: '还没有未提交的草稿',
        builder: (BuildContext context, List<GhDraft> drafts) =>
            RefreshIndicator(
          onRefresh: () => _controller().load(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: drafts.length,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final GhDraft draft = drafts[index];
              return OgLReveal(
                delay: OgLAnim.stagger(context, index),
                child: ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: Text(
                    draft.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${draft.repo}${draft.branch.isEmpty ? '' : '@${draft.branch}'} · '
                    'rev ${draft.revision} · ${_fmt(draft.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => unawaited(_delete(draft)),
                  ),
                  onTap: () => _view(draft),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}