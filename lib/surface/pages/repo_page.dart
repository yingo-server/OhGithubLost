/// L3 展示级 · 仓库详情页（八标签）。
///
/// 标签：代码 / 议题 / PR / 发布 / 分支 / 提交 / Actions / 设置。
///
/// ## 保守实现
/// - 全部使用 Material 3：`DefaultTabController` + `TabBar` + `TabBarView`；
/// - 每个标签自己懒加载（进入才发请求）；
/// - 危险操作（删文件 / 删分支 / 删发布 / 删仓库）一律二次确认；
/// - 写操作带基线 sha（乐观锁）：基线过期时服务端会拒绝，绝不静默覆盖。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/readme_view.dart';
import 'commit_page.dart';
import 'issue_page.dart';
import 'new_issue_page.dart';
import 'new_release_page.dart';
import 'pull_page.dart';

/// 仓库详情页。
class RepoPage extends StatefulWidget {
  /// 创建页面。
  const RepoPage({
    required this.surface,
    required this.repo,
    this.initialPath,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库（可由刷新结果覆盖）。
  final GhRepo repo;

  /// 初始路径（从代码搜索直达某文件 / 目录；可空）。
  final String? initialPath;

  @override
  State<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends State<RepoPage> {
  late GhRepo _repo = widget.repo;
  bool _starred = false;
  bool _starBusy = false;
  bool _forkBusy = false;

  String get _full => _repo.fullName;

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleStar() async {
    if (_starBusy) {
      return;
    }
    setState(() => _starBusy = true);
    final bool target = !_starred;
    try {
      await widget.surface.domain.api.setStarred(_full, target);
      OgLAppLog.instance.result('仓库', target ? '已加星标' : '已取消星标', _full);
      if (!mounted) {
        return;
      }
      setState(() => _starred = target);
      _toast(target ? '已加星标' : '已取消星标');
    } catch (error) {
      OgLAppLog.instance.add(
        '仓库',
        '星标操作失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      _toast('操作失败：$error');
    } finally {
      if (mounted) {
        setState(() => _starBusy = false);
      }
    }
  }

  Future<void> _fork() async {
    if (_forkBusy) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('复刻仓库'),
        content: Text('将把 $_full 复刻到你的账号下，继续？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('复刻'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _forkBusy = true);
    try {
      final GhRepo forked = await widget.surface.domain.api.fork(_full);
      OgLAppLog.instance.result('仓库', '已复刻', forked.fullName);
      _toast('已复刻为 ${forked.fullName}');
    } catch (error) {
      OgLAppLog.instance.add(
        '仓库',
        '复刻失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      _toast('复刻失败：$error');
    } finally {
      if (mounted) {
        setState(() => _forkBusy = false);
      }
    }
  }

  void _openInBrowser() {
    final String url =
        _repo.htmlUrl ?? 'https://github.com/${_repo.fullName}';
    unawaited(openLinkOrCopy(context, url, tag: '仓库'));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 8,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_repo.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: <Widget>[
            IconButton(
              icon: Icon(_starred ? Icons.star : Icons.star_border),
              tooltip: _starred ? '取消星标' : '加星',
              onPressed: _starBusy ? null : _toggleStar,
            ),
            IconButton(
              icon: const Icon(Icons.call_split),
              tooltip: '复刻',
              onPressed: _forkBusy ? null : _fork,
            ),
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: '用浏览器打开',
              onPressed: _openInBrowser,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Tab>[
              Tab(text: '代码'),
              Tab(text: '议题'),
              Tab(text: 'PR'),
              Tab(text: '发布'),
              Tab(text: '分支'),
              Tab(text: '提交'),
              Tab(text: 'Actions'),
              Tab(text: '设置'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _CodeTab(
              surface: widget.surface,
              fullName: _full,
              defaultBranch: _repo.defaultBranch,
              initialPath: widget.initialPath,
            ),
            _IssuesTab(surface: widget.surface, fullName: _full),
            _PullsTab(surface: widget.surface, fullName: _full),
            _ReleasesTab(
              surface: widget.surface,
              fullName: _full,
              defaultBranch: _repo.defaultBranch,
            ),
            _BranchesTab(
              surface: widget.surface,
              fullName: _full,
              defaultBranch: _repo.defaultBranch,
            ),
            _CommitsTab(
              surface: widget.surface,
              fullName: _full,
              defaultBranch: _repo.defaultBranch,
            ),
            _ActionsTab(surface: widget.surface, fullName: _full),
            _RepoSettingsTab(
              surface: widget.surface,
              repo: _repo,
              onRepoChanged: (GhRepo fresh) => setState(() => _repo = fresh),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 代码标签
// ─────────────────────────────────────────────────────────────────────────────

class _CodeTab extends StatefulWidget {
  const _CodeTab({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
    this.initialPath,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String defaultBranch;
  final String? initialPath;

  @override
  State<_CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends State<_CodeTab> {
  String _path = '';
  AsyncController<List<GhContent>>? _entries;
  GhContent? _file;
  bool _fileBusy = false;
  bool _editing = false;
  bool _saving = false;
  final TextEditingController _editor = TextEditingController();

  String? _readme;
  String? _readmeError;
  bool _readmeTried = false;

  @override
  void initState() {
    super.initState();
    _entriesC().loadIfNeeded();
    final String? initial = widget.initialPath;
    if (initial != null && initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_openPath(initial));
      });
    } else {
      unawaited(_loadReadme());
    }
  }

  @override
  void dispose() {
    _entries?.dispose();
    _editor.dispose();
    super.dispose();
  }

  AsyncController<List<GhContent>> _entriesC() {
    final existing = _entries;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhContent>>(
      label: '目录',
      isEmpty: (List<GhContent> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.listDirectory(
        widget.fullName,
        _path,
        branch: widget.defaultBranch,
      ),
    );
    _entries = controller;
    return controller;
  }

  void _toast(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadReadme() async {
    if (_readmeTried) {
      return;
    }
    _readmeTried = true;
    try {
      final String? text = await widget.surface.domain.api.readme(widget.fullName);
      if (!mounted) {
        return;
      }
      setState(() {
        _readme = text;
        _readmeError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _readmeError = 'README 读取失败：$error');
    }
  }

  /// 从搜索直达（文件或目录）。
  Future<void> _openPath(String path) async {
    setState(() => _fileBusy = true);
    try {
      final GhContent? content = await widget.surface.domain.api.content(
        widget.fullName,
        path,
        branch: widget.defaultBranch,
      );
      if (!mounted) {
        return;
      }
      if (content == null) {
        _toast('路径不存在：$path');
        return;
      }
      if (content.isDirectory) {
        setState(() => _path = content.path);
        await _entriesC().load();
      } else {
        setState(() {
          _file = content;
          _editing = false;
          _editor.text = content.text ?? '';
        });
      }
    } catch (error) {
      _toast('读取失败：$error');
    } finally {
      if (mounted) {
        setState(() => _fileBusy = false);
      }
    }
  }

  void _openDir(GhContent entry) {
    setState(() => _path = entry.path);
    unawaited(_entriesC().load());
  }

  void _up() {
    final int cut = _path.lastIndexOf('/');
    setState(() => _path = cut <= 0 ? '' : _path.substring(0, cut));
    unawaited(_entriesC().load());
    if (_path.isEmpty) {
      unawaited(_loadReadme());
    }
  }

  Future<void> _openFile(GhContent entry) async {
    if (_fileBusy) {
      return;
    }
    setState(() => _fileBusy = true);
    try {
      final GhContent? content = await widget.surface.domain.api.content(
        widget.fullName,
        entry.path,
        branch: widget.defaultBranch,
      );
      if (!mounted) {
        return;
      }
      if (content == null) {
        _toast('读取失败：文件可能已不存在');
        return;
      }
      setState(() {
        _file = content;
        _editing = false;
        _editor.text = content.text ?? '';
      });
    } catch (error) {
      _toast('读取失败：$error');
    } finally {
      if (mounted) {
        setState(() => _fileBusy = false);
      }
    }
  }

  Future<void> _refreshFile(String path) async {
    try {
      final GhContent? fresh = await widget.surface.domain.api.content(
        widget.fullName,
        path,
        branch: widget.defaultBranch,
      );
      if (!mounted || fresh == null) {
        return;
      }
      setState(() {
        _file = fresh;
        _editor.text = fresh.text ?? '';
      });
    } catch (_) {
      // 刷新失败不阻塞（旧内容还在屏幕上，下一次操作会再试）。
    }
  }

  Future<void> _save() async {
    final GhContent? file = _file;
    if (file == null || _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.surface.domain.api.putContent(
        widget.fullName,
        file.path,
        content: _editor.text,
        message: 'docs: update ${file.path}',
        baseSha: file.sha,
        branch: widget.defaultBranch,
      );
      OgLAppLog.instance.result('编辑', '已提交', file.path);
      if (!mounted) {
        return;
      }
      setState(() => _editing = false);
      _toast('已提交修改：${file.path}');
      await _refreshFile(file.path);
      await _entriesC().load();
    } catch (error) {
      OgLAppLog.instance.add(
        '编辑',
        '提交失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() {});
        _toast('提交失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    final GhContent? file = _file;
    if (file == null) {
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('将删除 ${file.path} 并提交到仓库。该操作不易撤销。'),
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
    try {
      await widget.surface.domain.api.deleteContent(
        widget.fullName,
        file.path,
        message: 'chore: delete ${file.path}',
        baseSha: file.sha,
        branch: widget.defaultBranch,
      );
      OgLAppLog.instance.result('编辑', '已删除', file.path);
      if (!mounted) {
        return;
      }
      setState(() {
        _file = null;
        _editing = false;
      });
      _toast('已删除：${file.path}');
      await _entriesC().load();
    } catch (error) {
      OgLAppLog.instance.add(
        '编辑',
        '删除失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      _toast('删除失败：$error');
    }
  }

  void _openFileInBrowser(GhContent file) {
    final String? url = file.htmlUrl;
    if (url == null || url.isEmpty) {
      _toast('该文件没有可打开的链接');
      return;
    }
    unawaited(openLinkOrCopy(context, url, tag: '文件'));
  }

  Widget _readmeTile() {
    final String? err = _readmeError;
    if (err != null) {
      return ListTile(
        leading: const Icon(Icons.warning_amber_rounded),
        title: const Text('README 读取失败'),
        subtitle: Text(err),
      );
    }
    final String? md = _readme;
    if (md == null || md.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return ExpansionTile(
      title: const Text('README'),
      subtitle: const Text('点击展开 / 收起'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: <Widget>[
        ReadmeView(
          markdown: md,
          onOpenLink: (Uri uri) {
            unawaited(openExternalLink(uri, tag: 'README'));
          },
        ),
      ],
    );
  }

  Widget _buildFileHeader(GhContent file) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回目录',
            onPressed: () {
              setState(() {
                _file = null;
                _editing = false;
              });
            },
          ),
          Expanded(
            child: Text(
              file.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          if (!_editing && !file.isTooLarge)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: () {
                setState(() {
                  _editing = true;
                  _editor.text = file.text ?? '';
                });
              },
            ),
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除',
              onPressed: _delete,
            ),
          if (!_editing)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: '用浏览器打开',
              onPressed: () => _openFileInBrowser(file),
            ),
        ],
      ),
    );
  }

  Widget _buildViewer(GhContent file) {
    if (file.isTooLarge) {
      return _MessagePane(
        icon: Icons.warning_amber_rounded,
        message: '文件过大（超过 1 MB），接口未返回内容。\n可用浏览器打开查看。',
        action: FilledButton.tonal(
          onPressed: () => _openFileInBrowser(file),
          child: const Text('用浏览器打开'),
        ),
      );
    }
    final String? text = file.text;
    if (text == null) {
      return _MessagePane(
        icon: Icons.help_outline,
        message: '没有可显示的文本内容（可能是二进制文件）。',
        action: FilledButton.tonal(
          onPressed: () => _openFileInBrowser(file),
          child: const Text('用浏览器打开'),
        ),
      );
    }
    if (file.path.toLowerCase().endsWith('.md')) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ReadmeView(
          markdown: text,
          onOpenLink: (Uri uri) {
            unawaited(openExternalLink(uri, tag: '文件'));
          },
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _editor,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: '文件内容',
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            children: <Widget>[
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() => _editing = false),
                child: const Text('取消'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '提交中…' : '提交修改'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fileBusy) {
      return const Center(child: CircularProgressIndicator());
    }
    final GhContent? file = _file;
    if (file != null) {
      return Column(
        children: <Widget>[
          _buildFileHeader(file),
          Expanded(
            child: _editing ? _buildEditor() : _buildViewer(file),
          ),
        ],
      );
    }
    return AsyncView<List<GhContent>>(
      controller: _entriesC(),
      emptyIcon: Icons.folder_open,
      emptyText: '这个目录是空的',
      builder: (BuildContext context, List<GhContent> entries) =>
          RefreshIndicator(
        onRefresh: () => _entriesC().load(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: <Widget>[
            if (_path.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('上一级'),
                onTap: _up,
              ),
            if (_path.isEmpty) _readmeTile(),
            for (final GhContent entry in entries)
              ListTile(
                leading: Icon(
                  entry.isDirectory ? Icons.folder : Icons.description_outlined,
                ),
                title: Text(
                  ghPathName(entry.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: entry.isDirectory ? null : Text(ghSizeText(entry.size)),
                trailing: entry.isDirectory
                    ? const Icon(Icons.chevron_right)
                    : null,
                onTap: () {
                  if (entry.isDirectory) {
                    _openDir(entry);
                  } else {
                    unawaited(_openFile(entry));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 简单消息面板（图标 + 文案 + 可选动作）。
class _MessagePane extends StatelessWidget {
  const _MessagePane({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...<Widget>[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 议题 / PR 标签（筛选 + 分页）
// ─────────────────────────────────────────────────────────────────────────────

class _IssuesTab extends StatefulWidget {
  const _IssuesTab({required this.surface, required this.fullName});

  final SurfaceBridge surface;
  final String fullName;

  @override
  State<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<_IssuesTab> {
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  String _state = 'open';
  int _page = 1;
  bool _loading = false;
  bool _moreDone = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 1;
      _moreDone = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Map<String, dynamic>> list =
          await widget.surface.domain.api.issues(
        widget.fullName,
        state: _state,
        perPage: 30,
        page: _page,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _items.addAll(list);
        _moreDone = list.length < 30;
        _page += 1;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = '议题读取失败：$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _create() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => NewIssuePage(
          surface: widget.surface,
          fullName: widget.fullName,
        ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已创建议题')),
      );
      await _reload();
    }
  }

  Future<void> _close(int number) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('关闭议题 #$number'),
        content: const Text('关闭后仍可在「已关闭」筛选里看到它。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api
          .updateIssue(widget.fullName, number, state: 'closed');
      OgLAppLog.instance.result('议题', '已关闭', '#$number');
      await _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('关闭失败：$error')),
        );
      }
    }
  }

  void _openIssue(Map<String, dynamic> item) {
    final int number = ghInt(item, 'number');
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => IssuePage(
          surface: widget.surface,
          fullName: widget.fullName,
          issue: item,
        ),
      ),
    );
    OgLAppLog.instance.add('议题', '打开 #$number');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SegmentedButton<String>(
                segments: const <ButtonSegment<String>>[
                  ButtonSegment<String>(value: 'open', label: Text('打开中')),
                  ButtonSegment<String>(value: 'closed', label: Text('已关闭')),
                  ButtonSegment<String>(value: 'all', label: Text('全部')),
                ],
                selected: <String>{_state},
                showSelectedIcon: false,
                onSelectionChanged: (Set<String> selection) {
                  if (selection.isNotEmpty && selection.first != _state) {
                    setState(() => _state = selection.first);
                    unawaited(_reload());
                  }
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: _create,
                  child: const Text('新建议题'),
                ),
              ),
            ],
          ),
        ),
        if (_error != null)
          ListTile(
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(_error!),
            trailing: TextButton(
              onPressed: () => unawaited(_loadMore()),
              child: const Text('重试'),
            ),
          ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      if (_error != null) {
        return Center(
          child: TextButton(
            onPressed: () => unawaited(_reload()),
            child: const Text('重试'),
          ),
        );
      }
      return _MessagePane(
        icon: Icons.task_alt,
        message: _state == 'all' ? '还没有议题' : '没有该状态的议题',
        action: FilledButton.tonal(
          onPressed: _create,
          child: const Text('新建议题'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (_moreDone ? 0 : 1),
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: () => unawaited(_loadMore()),
                        child: const Text('加载更多'),
                      ),
              ),
            );
          }
          final Map<String, dynamic> item = _items[index];
          final int number = ghInt(item, 'number');
          return ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: Text(
              '#$number ${ghStr(item, 'title')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'by ${ghLogin(item)} · ${ghInt(item, 'comments')} 条评论 · '
              '${ghDate(item, 'created_at')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: ghStr(item, 'state') == 'open'
                ? IconButton(
                    icon: const Icon(Icons.task_alt),
                    tooltip: '关闭',
                    onPressed: () => _close(number),
                  )
                : const Icon(Icons.chevron_right),
            onTap: () => _openIssue(item),
          );
        },
      ),
    );
  }
}

class _PullsTab extends StatefulWidget {
  const _PullsTab({required this.surface, required this.fullName});

  final SurfaceBridge surface;
  final String fullName;

  @override
  State<_PullsTab> createState() => _PullsTabState();
}

class _PullsTabState extends State<_PullsTab> {
  final List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  String _state = 'open';
  int _page = 1;
  bool _loading = false;
  bool _moreDone = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_reload());
    });
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 1;
      _moreDone = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<Map<String, dynamic>> list =
          await widget.surface.domain.api.pulls(
        widget.fullName,
        state: _state,
        perPage: 30,
        page: _page,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _items.addAll(list);
        _moreDone = list.length < 30;
        _page += 1;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'PR 读取失败：$error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _openPull(Map<String, dynamic> item) {
    final int number = ghInt(item, 'number');
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => PullPage(
          surface: widget.surface,
          fullName: widget.fullName,
          pull: item,
          number: number,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            segments: const <ButtonSegment<String>>[
              ButtonSegment<String>(value: 'open', label: Text('打开中')),
              ButtonSegment<String>(value: 'closed', label: Text('已关闭')),
              ButtonSegment<String>(value: 'all', label: Text('全部')),
            ],
            selected: <String>{_state},
            showSelectedIcon: false,
            onSelectionChanged: (Set<String> selection) {
              if (selection.isNotEmpty && selection.first != _state) {
                setState(() => _state = selection.first);
                unawaited(_reload());
              }
            },
          ),
        ),
        if (_error != null)
          ListTile(
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(_error!),
            trailing: TextButton(
              onPressed: () => unawaited(_loadMore()),
              child: const Text('重试'),
            ),
          ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return _MessagePane(
        icon: Icons.call_merge,
        message: _state == 'all' ? '还没有 PR' : '没有该状态的 PR',
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _items.length + (_moreDone ? 0 : 1),
        separatorBuilder: (BuildContext context, int index) =>
            const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          if (index == _items.length) {
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: _loading
                    ? const CircularProgressIndicator()
                    : OutlinedButton(
                        onPressed: () => unawaited(_loadMore()),
                        child: const Text('加载更多'),
                      ),
              ),
            );
          }
          final Map<String, dynamic> item = _items[index];
          return ListTile(
            leading: const Icon(Icons.call_merge),
            title: Text(
              '#${ghInt(item, 'number')} ${ghStr(item, 'title')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              'by ${ghLogin(item)} · ${ghDate(item, 'created_at')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openPull(item),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 发布标签
// ─────────────────────────────────────────────────────────────────────────────

class _ReleasesTab extends StatefulWidget {
  const _ReleasesTab({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String defaultBranch;

  @override
  State<_ReleasesTab> createState() => _ReleasesTabState();
}

class _ReleasesTabState extends State<_ReleasesTab> {
  AsyncController<List<GhRelease>>? _releases;

  @override
  void initState() {
    super.initState();
    _releasesC().loadIfNeeded();
  }

  @override
  void dispose() {
    _releases?.dispose();
    super.dispose();
  }

  AsyncController<List<GhRelease>> _releasesC() {
    final existing = _releases;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhRelease>>(
      label: '发布',
      isEmpty: (List<GhRelease> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.releases(widget.fullName),
    );
    _releases = controller;
    return controller;
  }

  Future<void> _create() async {
    final GhRelease? created = await Navigator.of(context).push<GhRelease>(
      MaterialPageRoute<GhRelease>(
        builder: (BuildContext context) => NewReleasePage(
          surface: widget.surface,
          fullName: widget.fullName,
          defaultBranch: widget.defaultBranch,
        ),
      ),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建发布 ${created.tagName}')),
      );
      await _releasesC().load();
    }
  }

  Future<void> _delete(GhRelease release) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除发布'),
        content: Text('将删除发布 ${release.tagName}。该操作不易撤销。'),
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
    try {
      await widget.surface.domain.api
          .deleteRelease(widget.fullName, release.id);
      OgLAppLog.instance.result('发布', '已删除', release.tagName);
      await _releasesC().load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
    }
  }

  void _showNotes(GhRelease release) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(
          release.tagName +
              (release.name == null || release.name!.isEmpty
                  ? ''
                  : ' · ${release.name}'),
        ),
        content: SingleChildScrollView(
          child: ReadmeView(
            markdown: release.body ?? '（无说明）',
            onOpenLink: (Uri uri) {
              unawaited(openExternalLink(uri, tag: '发布'));
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _create,
              child: const Text('新建发布'),
            ),
          ),
        ),
        Expanded(
          child: AsyncView<List<GhRelease>>(
            controller: _releasesC(),
            emptyIcon: Icons.new_releases_outlined,
            emptyText: '还没有发布',
            builder: (BuildContext context, List<GhRelease> releases) =>
                RefreshIndicator(
              onRefresh: () => _releasesC().load(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: releases.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final GhRelease release = releases[index];
                  final List<String> marks = <String>[
                    if (release.isDraft) '草稿',
                    if (release.isPrerelease) '预发布',
                  ];
                  return ListTile(
                    leading: const Icon(Icons.new_releases_outlined),
                    title: Text(
                      release.tagName +
                          (release.name == null || release.name!.isEmpty
                              ? ''
                              : ' · ${release.name}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      <String>[
                        if (release.publishedAt != null)
                          '发布 ${release.publishedAt!.toIso8601String().split('T').first}',
                        if (marks.isNotEmpty) marks.join(' / '),
                        '${release.assets.length} 个附件',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '删除',
                      onPressed: () => _delete(release),
                    ),
                    onTap: () => _showNotes(release),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 分支标签
// ─────────────────────────────────────────────────────────────────────────────

class _BranchesTab extends StatefulWidget {
  const _BranchesTab({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String defaultBranch;

  @override
  State<_BranchesTab> createState() => _BranchesTabState();
}

class _BranchesTabState extends State<_BranchesTab> {
  AsyncController<List<GhBranch>>? _branches;
  final TextEditingController _createName = TextEditingController();
  final TextEditingController _renameName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _branchesC().loadIfNeeded();
  }

  @override
  void dispose() {
    _branches?.dispose();
    _createName.dispose();
    _renameName.dispose();
    super.dispose();
  }

  AsyncController<List<GhBranch>> _branchesC() {
    final existing = _branches;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhBranch>>(
      label: '分支',
      isEmpty: (List<GhBranch> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.branches(widget.fullName),
    );
    _branches = controller;
    return controller;
  }

  Future<void> _create() async {
    _createName.clear();
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('新建分支'),
        content: TextField(
          controller: _createName,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分支名',
            hintText: 'feature/xxx',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_createName.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    final String trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api.createBranch(
        widget.fullName,
        name: trimmed,
        fromBranch: widget.defaultBranch,
      );
      OgLAppLog.instance.result('分支', '已创建', trimmed);
      await _branchesC().load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败：$error')),
        );
      }
    }
  }

  Future<void> _rename(GhBranch branch) async {
    _renameName.text = branch.name;
    final String? input = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('重命名分支'),
        content: TextField(
          controller: _renameName,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新名称'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(_renameName.text),
            child: const Text('重命名'),
          ),
        ],
      ),
    );
    final String trimmed = input?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == branch.name || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api
          .renameBranch(widget.fullName, branch.name, trimmed);
      OgLAppLog.instance.result('分支', '已重命名', '${branch.name} → $trimmed');
      await _branchesC().load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重命名失败：$error')),
        );
      }
    }
  }

  Future<void> _delete(GhBranch branch) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除分支'),
        content: Text('将删除分支「${branch.name}」。该操作不可直接撤销。'),
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
    try {
      await widget.surface.domain.api
          .deleteBranch(widget.fullName, branch.name);
      OgLAppLog.instance.result('分支', '已删除', branch.name);
      await _branchesC().load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: _create,
              child: const Text('新建分支'),
            ),
          ),
        ),
        Expanded(
          child: AsyncView<List<GhBranch>>(
            controller: _branchesC(),
            emptyIcon: Icons.account_tree_outlined,
            emptyText: '还没有分支',
            builder: (BuildContext context, List<GhBranch> branches) =>
                RefreshIndicator(
              onRefresh: () => _branchesC().load(),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: branches.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
                itemBuilder: (BuildContext context, int index) {
                  final GhBranch branch = branches[index];
                  final bool isDefault = branch.name == widget.defaultBranch;
                  return ListTile(
                    leading: Icon(
                      branch.isProtected
                          ? Icons.lock_outline
                          : Icons.account_tree_outlined,
                    ),
                    title: Text(
                      branch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${ghShortSha(branch.sha)}'
                      '${isDefault ? ' · 默认分支' : ''}'
                      '${branch.isProtected ? ' · 受保护' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: '重命名',
                          onPressed: isDefault ? null : () => _rename(branch),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '删除',
                          onPressed: isDefault ? null : () => _delete(branch),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 提交标签
// ─────────────────────────────────────────────────────────────────────────────

class _CommitsTab extends StatefulWidget {
  const _CommitsTab({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String defaultBranch;

  @override
  State<_CommitsTab> createState() => _CommitsTabState();
}

class _CommitsTabState extends State<_CommitsTab> {
  AsyncController<List<GhCommit>>? _commits;

  @override
  void initState() {
    super.initState();
    _commitsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _commits?.dispose();
    super.dispose();
  }

  AsyncController<List<GhCommit>> _commitsC() {
    final existing = _commits;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhCommit>>(
      label: '提交',
      isEmpty: (List<GhCommit> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.commits(
        widget.fullName,
        branch: widget.defaultBranch,
      ),
    );
    _commits = controller;
    return controller;
  }

  void _openCommit(GhCommit commit) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => CommitPage(
          surface: widget.surface,
          fullName: widget.fullName,
          commit: commit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<GhCommit>>(
      controller: _commitsC(),
      emptyIcon: Icons.history,
      emptyText: '还没有提交',
      builder: (BuildContext context, List<GhCommit> commits) =>
          RefreshIndicator(
        onRefresh: () => _commitsC().load(),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: commits.length,
          separatorBuilder: (BuildContext context, int index) =>
              const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final GhCommit commit = commits[index];
            return ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                commit.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${ghCommitAuthor(commit)} · '
                '${commit.date?.toIso8601String().split('T').first ?? ''} · '
                '${ghShortSha(commit.sha)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openCommit(commit),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions 标签
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsTab extends StatefulWidget {
  const _ActionsTab({required this.surface, required this.fullName});

  final SurfaceBridge surface;
  final String fullName;

  @override
  State<_ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends State<_ActionsTab> {
  AsyncController<List<Map<String, dynamic>>>? _runs;

  @override
  void initState() {
    super.initState();
    _runsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _runs?.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _runsC() {
    final existing = _runs;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: 'Actions',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.workflowRuns(widget.fullName),
    );
    _runs = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return AsyncView<List<Map<String, dynamic>>>(
      controller: _runsC(),
      emptyIcon: Icons.play_circle_outline,
      emptyText: '没有工作流运行记录（该仓库还没跑过 Actions，或令牌缺少权限）',
      builder: (
        BuildContext context,
        List<Map<String, dynamic>> runs,
      ) =>
          RefreshIndicator(
        onRefresh: () => _runsC().load(),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: runs.length,
          separatorBuilder: (BuildContext context, int index) =>
              const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final Map<String, dynamic> run = runs[index];
            final String conclusion = ghStr(run, 'conclusion');
            return ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(
                ghStr(run, 'name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${ghStr(run, 'status')} · '
                '${conclusion.isEmpty ? '—' : conclusion} · '
                '${ghDate(run, 'created_at')}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 设置标签
// ─────────────────────────────────────────────────────────────────────────────

class _RepoSettingsTab extends StatefulWidget {
  const _RepoSettingsTab({
    required this.surface,
    required this.repo,
    required this.onRepoChanged,
  });

  final SurfaceBridge surface;
  final GhRepo repo;
  final ValueChanged<GhRepo> onRepoChanged;

  @override
  State<_RepoSettingsTab> createState() => _RepoSettingsTabState();
}

class _RepoSettingsTabState extends State<_RepoSettingsTab> {
  late final TextEditingController _name =
      TextEditingController(text: widget.repo.name);
  late final TextEditingController _description =
      TextEditingController(text: widget.repo.description ?? '');
  final TextEditingController _cname = TextEditingController();
  bool _busy = false;
  Future<Map<String, dynamic>?>? _pagesFuture;

  String get _full => widget.repo.fullName;

  @override
  void initState() {
    super.initState();
    _pagesFuture = _loadPages();
    unawaited(_loadCname());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _cname.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _loadPages() async {
    try {
      return await widget.surface.domain.api.pagesInfo(_full);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCname() async {
    try {
      final String? cname = await widget.surface.domain.api.readCname(_full);
      if (!mounted || cname == null) {
        return;
      }
      setState(() => _cname.text = cname);
    } catch (_) {
      // CNAME 读不到不是错误（大多数仓库没有自定义域名）。
    }
  }

  Future<void> _saveBasic() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      final GhRepo updated = await widget.surface.domain.api.updateRepo(
        _full,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        description: _description.text.trim(),
      );
      OgLAppLog.instance.result('仓库', '基本信息已更新', _full);
      if (!mounted) {
        return;
      }
      widget.onRepoChanged(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
    } catch (error) {
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

  Future<void> _saveCname() async {
    if (_busy) {
      return;
    }
    final String domain = _cname.text.trim();
    if (domain.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写域名')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final GhContent? existing = await widget.surface.domain.api.content(
        _full,
        'CNAME',
        branch: widget.repo.defaultBranch,
      );
      await widget.surface.domain.api.putContent(
        _full,
        'CNAME',
        content: '$domain\n',
        message: 'chore: configure custom domain',
        baseSha: existing?.sha,
        branch: widget.repo.defaultBranch,
      );
      OgLAppLog.instance.result('仓库', 'CNAME 已写入', domain);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存 CNAME')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CNAME 保存失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _enablePages() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.enablePages(
        _full,
        branch: widget.repo.defaultBranch,
      );
      OgLAppLog.instance.result('仓库', 'Pages 已启用', _full);
      if (mounted) {
        setState(() => _pagesFuture = _loadPages());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pages 已启用（首次发布可能需要几十秒）')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启用失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _disablePages() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api.disablePages(_full);
      OgLAppLog.instance.result('仓库', 'Pages 已停用', _full);
      if (mounted) {
        setState(() => _pagesFuture = _loadPages());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pages 已停用')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('停用失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _deleteRepo() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除仓库'),
        content: Text('将彻底删除 $_full（含全部代码与记录）。该操作不可撤销！'),
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
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api.deleteRepo(_full);
      OgLAppLog.instance.add('仓库', '已删除仓库 $_full', severity: OgLNoticeSeverity.warning);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败：$error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('基本信息', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _name,
          decoration: const InputDecoration(
            labelText: '仓库名',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _description,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '描述',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy ? null : _saveBasic,
            child: const Text('保存基本信息'),
          ),
        ),
        const Divider(height: 32),
        Text('Pages', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        FutureBuilder<Map<String, dynamic>?>(
          future: _pagesFuture,
          builder: (
            BuildContext context,
            AsyncSnapshot<Map<String, dynamic>?> snapshot,
          ) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Text('读取中…');
            }
            final Map<String, dynamic>? info = snapshot.data;
            if (info == null) {
              return const Text('当前未启用');
            }
            final String url = ghStr(info, 'html_url');
            final String status = ghStr(info, 'status');
            return Text(
              '状态：${status.isEmpty ? '已启用' : status}'
              '${url.isEmpty ? '' : '\n地址：$url'}',
            );
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            FilledButton.tonal(
              onPressed: _busy ? null : _enablePages,
              child: const Text('启用（默认分支）'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _disablePages,
              child: const Text('停用'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _cname,
          decoration: const InputDecoration(
            labelText: '自定义域名（CNAME）',
            hintText: 'example.com',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonal(
            onPressed: _busy ? null : _saveCname,
            child: const Text('保存 CNAME'),
          ),
        ),
        const Divider(height: 32),
        Text(
          '危险区',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('删除仓库会连同全部代码与记录一起消失，且不可撤销。'),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _deleteRepo,
                  child: const Text('删除仓库'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}