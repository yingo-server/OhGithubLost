/// L3 展示级 · 提交详情（元信息 + 分色补丁）。
///
/// - 与父提交比较（`parents.first → sha`），列出变更文件；
/// - 补丁按行分色：`+` 绿 / `-` 红 / `@@` 强调色（其余正常）；
/// - 初始提交（无父提交）给出明确说明，而不是空白。
library;

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../surface_bridge.dart';
import '../types.dart';
import '../util/gh_format.dart';

/// 提交详情页。
class CommitPage extends StatefulWidget {
  /// 创建页面。
  const CommitPage({
    required this.surface,
    required this.fullName,
    required this.commit,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名（`owner/repo`）。
  final String fullName;

  /// 提交对象。
  final GhCommit commit;

  @override
  State<CommitPage> createState() => _CommitPageState();
}

class _CommitPageState extends State<CommitPage> {
  AsyncController<List<Map<String, dynamic>>>? _diff;

  @override
  void initState() {
    super.initState();
    _diffC().loadIfNeeded();
  }

  @override
  void dispose() {
    _diff?.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _diffC() {
    final existing = _diff;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: '变更',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () {
        final List<String> parents = widget.commit.parentShas;
        if (parents.isEmpty) {
          return Future<List<Map<String, dynamic>>>.value(
            const <Map<String, dynamic>>[],
          );
        }
        return widget.surface.domain.api
            .compare(widget.fullName, parents.first, widget.commit.sha);
      },
    );
    _diff = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GhCommit commit = widget.commit;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          ghShortSha(commit.sha),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SelectableText(
                    commit.sha,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${ghCommitAuthor(commit)} · '
                    '${commit.date?.toIso8601String().split('T').first ?? ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(commit.message),
                ],
              ),
            ),
          ),
          const Divider(height: 32),
          Text('变更文件', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          AsyncView<List<Map<String, dynamic>>>(
            controller: _diffC(),
            fill: false,
            emptyIcon: Icons.history,
            emptyText: widget.commit.parentShas.isEmpty
                ? '这是初始提交，没有可比对的父提交。'
                : '没有可显示的变更',
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
          child: _PatchView(patch: patch),
        ),
      ],
    );
  }
}

/// 分色补丁：`+` 绿 / `-` 红 / `@@` 强调色 / 其余跟随主题。
class _PatchView extends StatelessWidget {
  const _PatchView({required this.patch});

  final String patch;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    const TextStyle base = TextStyle(fontFamily: 'monospace', fontSize: 12);
    final List<TextSpan> spans = <TextSpan>[];
    for (final String line in patch.split('\n')) {
      Color color = scheme.onSurface;
      if (line.startsWith('+')) {
        color = const Color(0xFF2DA44E);
      } else if (line.startsWith('-')) {
        color = const Color(0xFFCF222E);
      } else if (line.startsWith('@@')) {
        color = scheme.primary;
      }
      spans.add(
        TextSpan(
          text: '$line\n',
          style: base.copyWith(color: color),
        ),
      );
    }
    return SelectableText.rich(TextSpan(children: spans));
  }
}