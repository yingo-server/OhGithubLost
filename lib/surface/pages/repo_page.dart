/// L3 展示级 · 仓库详情页（八标签 + 分支切换）。
///
/// ## 4.1 仓库浏览增强
/// - **分支切换**：AppBar 下方常驻分支栏，切换后代码 / 提交 / 发布 / Actions 同步；
/// - **新建文件**：代码标签提供 FAB 入口；
/// - **目录内筛选**：当前目录按名称过滤；
/// - **图片预览**：图片文件直接在应用内预览（不再显示二进制乱码）；
/// - **分页**：仓库列表与仓库页各列表统一「加载更多」。
///
/// ## 控件规范
/// 全部使用 Material 3；「新建」类主操作统一为 [FloatingActionButton]，
/// 次要操作收进 [PopupMenuButton]，空/错/载三态统一收敛。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/gh/gh_client.dart';
import '../../domain/gh/gh_models.dart';
import '../../domain/ix/ix_download.dart';
import '../app/animations.dart';
import '../app/error_surface.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';
import '../util/file_icons.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';
import '../widgets/code_editor_field.dart';
import '../widgets/readme_view.dart';
import 'action_run_page.dart';
import 'code_editor_page.dart';
import 'commit_page.dart';
import 'issue_page.dart';
import 'new_issue_page.dart';
import 'new_release_page.dart';
import 'pull_page.dart';
import 'release_detail_page.dart';
import 'workflow_dispatch_page.dart';

/// 每页条数（统一）。
const int _kPageSize = 30;

/// 重负载端点（发布 / Actions）每页条数。
///
/// 这两类响应**单条就很大**（发布含全部附件、Actions 含全部作业），
/// 按 30 条一次拉取会产出数百 KB 到数 MB 的响应体——既慢，又容易在弱网下中断。
const int _kHeavyPageSize = 10;

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

  /// 仓库。
  final GhRepo repo;

  /// 初始路径（从代码搜索直达；可空）。
  final String? initialPath;

  @override
  State<RepoPage> createState() => _RepoPageState();
}

class _RepoPageState extends State<RepoPage> {
  late GhRepo _repo = widget.repo;
  late String _branch = widget.repo.defaultBranch;
  bool _starred = false;
  bool _starBusy = false;
  bool _forkBusy = false;

  String get _full => _repo.fullName;

  @override
  void initState() {
    super.initState();
    unawaited(_loadStarred());
  }

  Future<void> _loadStarred() async {
    try {
      final bool starred = await widget.surface.domain.api.isRepoStarred(_full);
      if (mounted) {
        setState(() => _starred = starred);
      }
    } catch (_) {
      // 未登录 / 无权限：保持未星标状态即可，不打扰用户。
    }
  }

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
      if (mounted) {
        setState(() => _starred = target);
        _toast(target ? '已加星标' : '已取消星标');
      }
    } catch (error) {
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
      _toast('复刻失败：$error');
    } finally {
      if (mounted) {
        setState(() => _forkBusy = false);
      }
    }
  }

  void _openInBrowser() {
    final String url = _repo.htmlUrl ?? 'https://github.com/${_repo.fullName}';
    unawaited(openLinkOrCopy(context, url, tag: '仓库'));
  }

  Future<void> _copyCloneUrl() async {
    await Clipboard.setData(ClipboardData(text: 'https://github.com/$_full.git'));
    _toast('已复制克隆地址');
  }

  /// 选择分支（Material 底部弹层 + 搜索）。
  Future<void> _pickBranch() async {
    List<GhBranch> branches;
    try {
      branches = await widget.surface.domain.api
          .branches(_full, perPage: 100);
    } catch (error) {
      _toast('分支读取失败：$error');
      return;
    }
    if (!mounted) {
      return;
    }
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => _BranchSheet(
        branches: branches,
        current: _branch,
        defaultBranch: _repo.defaultBranch,
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    final String next = picked == _kDefaultBranchMark ? _repo.defaultBranch : picked;
    if (next == _branch) {
      return;
    }
    setState(() => _branch = next);
    OgLAppLog.instance.result('仓库', '已切换分支', next);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String branchKey = _branch.isEmpty ? 'default' : _branch;
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
            PopupMenuButton<String>(
              tooltip: '更多',
              onSelected: (String value) {
                switch (value) {
                  case 'fork':
                    unawaited(_fork());
                  case 'browser':
                    _openInBrowser();
                  case 'clone':
                    unawaited(_copyCloneUrl());
                }
              },
              itemBuilder: (BuildContext context) =>
                  const <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'fork',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.call_split),
                    title: Text('复刻仓库'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'clone',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.link),
                    title: Text('复制克隆地址'),
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'browser',
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.open_in_new),
                    title: Text('用浏览器打开'),
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(96),
            child: Column(
              children: <Widget>[
                _branchBar(theme),
                TabBar(
                  isScrollable: true,
                  tabs: <Tab>[
                    Tab(text: OgLI18n.instance.t('repo', 'code')),
                    Tab(text: OgLI18n.instance.t('repo', 'issues')),
                    Tab(text: OgLI18n.instance.t('repo', 'pulls')),
                    Tab(text: OgLI18n.instance.t('repo', 'releases')),
                    Tab(text: OgLI18n.instance.t('repo', 'branches')),
                    Tab(text: OgLI18n.instance.t('repo', 'commits')),
                    Tab(text: OgLI18n.instance.t('repo', 'actions')),
                    Tab(text: OgLI18n.instance.t('repo', 'repoSettings')),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _CodeTab(
              key: ValueKey<String>('code-$branchKey'),
              surface: widget.surface,
              fullName: _full,
              branch: _branch,
              initialPath: widget.initialPath,
            ),
            _IssuesTab(surface: widget.surface, fullName: _full),
            _PullsTab(surface: widget.surface, fullName: _full),
            _ReleasesTab(
              key: ValueKey<String>('rel-$branchKey'),
              surface: widget.surface,
              fullName: _full,
              branch: _branch,
            ),
            _BranchesTab(
              surface: widget.surface,
              fullName: _full,
              defaultBranch: _repo.defaultBranch,
              onBranchChanged: () => setState(() {}),
            ),
            _CommitsTab(
              key: ValueKey<String>('cmt-$branchKey'),
              surface: widget.surface,
              fullName: _full,
              branch: _branch,
            ),
            _ActionsTab(
              key: ValueKey<String>('act-$branchKey'),
              surface: widget.surface,
              fullName: _full,
              branch: _branch,
            ),
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

  Widget _branchBar(ThemeData theme) => Material(
        color: theme.colorScheme.surfaceContainerHighest,
        child: InkWell(
          onTap: _pickBranch,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: <Widget>[
                const Icon(Icons.account_tree_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _branch.isEmpty ? '默认分支' : _branch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
                if (_branch == _repo.defaultBranch)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('默认', style: theme.textTheme.bodySmall),
                  ),
                const Icon(Icons.expand_more),
              ],
            ),
          ),
        ),
      );
}

/// 分支弹层的「默认分支」标记值。
const String _kDefaultBranchMark = '\u0000default';

/// 分支选择弹层（搜索 + 列表）。
class _BranchSheet extends StatefulWidget {
  const _BranchSheet({
    required this.branches,
    required this.current,
    required this.defaultBranch,
  });

  final List<GhBranch> branches;
  final String current;
  final String defaultBranch;

  @override
  State<_BranchSheet> createState() => _BranchSheetState();
}

class _BranchSheetState extends State<_BranchSheet> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<GhBranch> shown = widget.branches
        .where((GhBranch b) =>
            _filter.isEmpty ||
            b.name.toLowerCase().contains(_filter.toLowerCase()))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
                hintText: '搜索分支',
              ),
              onChanged: (String value) => setState(() => _filter = value),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? const Center(child: Text('没有匹配的分支'))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (BuildContext context, int index) {
                      final GhBranch branch = shown[index];
                      final bool isCurrent = branch.name == widget.current;
                      final bool isDefault =
                          branch.name == widget.defaultBranch;
                      return ListTile(
                        leading: Icon(
                          branch.isProtected
                              ? Icons.lock_outline
                              : Icons.account_tree_outlined,
                        ),
                        title: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${ghShortSha(branch.sha)}'
                          '${isDefault ? ' · 默认分支' : ''}'
                          '${branch.isProtected ? ' · 受保护' : ''}',
                        ),
                        trailing: isCurrent
                            ? Icon(Icons.check, color: theme.colorScheme.primary)
                            : null,
                        onTap: () => Navigator.of(context).pop(branch.name),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 分页控制器与统一列表渲染
// ─────────────────────────────────────────────────────────────────────────────

/// 清空所有"按目标缓存"的分页快照。
///
/// **切换账号时必须调用**：快照里可能含上一个账号可见的私有数据
/// （用户要求：切号清除所有缓存）。
void clearOgLRepoPageCaches() => _recentPage.clear();

/// 一次成功的分页快照（供同目标的标签页重建后"秒开"，避免重复请求）。
class _CachedPage {
  const _CachedPage(this.at, this.items, this.done, this.page);

  final DateTime at;
  final List<Object?> items;
  final bool done;
  final int page;
}

/// 分页快照缓存（按 `cacheKey` 隔离）。
final Map<String, _CachedPage> _recentPage = <String, _CachedPage>{};

/// 快照有效期：过期即回源。
const Duration _kPageCacheTtl = Duration(seconds: 6);

/// 通用分页数据源（首屏 + 加载更多 + 下拉刷新）。
class _Paged<T> extends ChangeNotifier {
  _Paged({required this.loader, this.pageSize = _kPageSize, this.cacheKey});

  final Future<List<T>> Function(int page) loader;
  final int pageSize;

  /// 快照键：同一目标（仓库 / 分支 / 目录 / 滤器）共用一个键。
  ///
  /// 为什么需要：`TabBarView` 会销毁不可见页，切回来时 State 重建 →
  /// 每个标签都会重新拉取，短时间内把同一端点连打数次（配额与带宽白烧）。
  /// 有了快照，重建即秒开、不再重复请求。目录 / 滤器会变化的目标，
  /// 由调用方在加载前更新本键。
  String? cacheKey;

  final List<T> items = <T>[];
  int _page = 1;
  bool loading = false;
  bool done = false;
  bool _everLoaded = false;
  bool _everFailed = false;
  String? error;

  /// 未显式要求时：首次加载按"自动"处理（可用快照），
  /// 之后一律按"显式"处理（用户下拉刷新 / 写后重载，必须真的回源）。
  bool get _shouldForce => _everLoaded || _everFailed;

  Future<void> loadMore() => _load(force: false);

  Future<void> refresh() => _load(force: _shouldForce, reset: true);

  Future<void> _load({required bool force, bool reset = false}) async {
    if (loading) {
      return;
    }
    final String? key = cacheKey;
    if (!force && reset && key != null) {
      final _CachedPage? cached = _recentPage[key];
      if (cached != null &&
          DateTime.now().difference(cached.at) < _kPageCacheTtl) {
        // 命中快照：直接展示，不发请求（重建的标签页因此"秒开"）。
        items
          ..clear()
          ..addAll(cached.items.whereType<T>());
        done = cached.done;
        _page = cached.page;
        error = null;
        _everLoaded = true;
        notifyListeners();
        return;
      }
    }
    if (reset) {
      items.clear();
      _page = 1;
      done = false;
      error = null;
    } else if (done) {
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final List<T> list = await loader(_page);
      items.addAll(list);
      if (list.length < pageSize) {
        done = true;
      }
      _page++;
      _everLoaded = true;
      if (key != null) {
        _recentPage[key] = _CachedPage(
          DateTime.now(),
          List<Object?>.of(items),
          done,
          _page,
        );
      }
    } catch (e) {
      error = '$e';
      _everFailed = true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

/// 统一渲染分页列表（空 / 错 / 载三态 + 加载更多 + 下拉刷新）。
///
/// [items] 为空时渲染 `paged.items` 全量；给了则只渲染该子集
/// （用于**客户端筛选**：筛选只影响展示，不影响分页状态）。
Widget _pagedBody<T>(
  BuildContext context,
  _Paged<T> paged,
  Widget Function(BuildContext context, T item, int index) itemBuilder, {
  required String emptyText,
  IconData emptyIcon = Icons.inbox_outlined,
  Widget? emptyAction,
  List<T>? items,
}) {
  final List<T> list = items ?? paged.items;
  if (paged.items.isEmpty && paged.loading) {
    return const Center(child: CircularProgressIndicator());
  }
  if (paged.items.isEmpty && paged.error != null) {
    return _MessagePane(
      icon: Icons.error_outline,
      message: paged.error!,
      action: FilledButton.tonal(
        onPressed: paged.refresh,
        child: const Text('重试'),
      ),
    );
  }
  if (paged.items.isEmpty) {
    return _MessagePane(icon: emptyIcon, message: emptyText, action: emptyAction);
  }
  return RefreshIndicator(
    onRefresh: paged.refresh,
    child: ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: list.length + (paged.done ? 0 : 1),
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (index == list.length) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: paged.loading
                  ? const CircularProgressIndicator()
                  : OutlinedButton(
                      onPressed: paged.loadMore,
                      child: Text('加载更多（已 ${paged.items.length} 条）'),
                    ),
            ),
          );
        }
        return OgLReveal(
          delay: OgLAnim.stagger(context, index),
          child: itemBuilder(context, list[index], index),
        );
      },
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// 代码标签
// ─────────────────────────────────────────────────────────────────────────────

class _CodeTab extends StatefulWidget {
  const _CodeTab({
    required this.surface,
    required this.fullName,
    required this.branch,
    this.initialPath,
    super.key,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String branch;
  final String? initialPath;

  @override
  State<_CodeTab> createState() => _CodeTabState();
}

class _CodeTabState extends State<_CodeTab> {
  String _path = '';
  late final _Paged<GhContent> _entries = _Paged<GhContent>(
    loader: _loadPage,
    cacheKey: _keyFor(''),
  );
  final TextEditingController _filter = TextEditingController();
  final TextEditingController _newPath = TextEditingController();

  GhContent? _file;
  bool _busy = false;
  String? _readme;
  bool _readmeTried = false;

  /// 目录列表"是否强制回源"（下拉刷新 / 写操作后置真；平时走缓存）。
  bool _forceList = false;

  String _keyFor(String path) =>
      'code:${widget.fullName}:${widget.branch}:$path';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_bootstrap()));
  }

  @override
  void dispose() {
    _entries.dispose();
    _filter.dispose();
    _newPath.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final String? initial = widget.initialPath;
    if (initial != null && initial.isNotEmpty) {
      await _openPath(initial);
    } else {
      await _entries.refresh();
      unawaited(_loadReadme());
    }
  }

  /// 目录内容一次性返回（Contents API 不分页），因此第 2 页起即结束。
  ///
  /// 缓存交给底座：默认走缓存（目录 TTL 1 分钟），仅下拉刷新 / 写操作后
  /// （[_forceList]）才强制回源——此前这里恒为 `true`，导致缓存永不命中、
  /// 每次切目录 / 切标签都重新下载。
  Future<List<GhContent>> _loadPage(int page) async {
    if (page > 1) {
      return const <GhContent>[];
    }
    final bool force = _forceList;
    _forceList = false;
    return widget.surface.domain.api.listDirectory(
      widget.fullName,
      _path,
      branch: widget.branch,
      refresh: force,
    );
  }

  /// 重新拉取当前目录（[force] 为真时绕过 HTTP 缓存）。
  Future<void> _reload({bool force = true}) async {
    _forceList = force;
    await _entries.refresh();
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
      final String? text =
          await widget.surface.domain.api.readme(widget.fullName);
      if (mounted) {
        setState(() => _readme = text);
      }
    } catch (_) {
      // README 缺失不是错误。
    }
  }

  Future<void> _goTo(String path) async {
    setState(() {
      _path = path;
      _file = null;
    });
    // 快照键跟随目录：否则标签页重建后会拿到"上一个目录"的快照。
    _entries.cacheKey = _keyFor(path);
    await _entries.refresh();
    if (path.isEmpty) {
      _readmeTried = false;
      await _loadReadme();
    }
  }

  Future<void> _openPath(String path) async {
    setState(() => _busy = true);
    try {
      // 走缓存（30 秒 TTL）：同一文件短时间内重复打开不再回源。
      final GhContent? content = await widget.surface.domain.api.content(
        widget.fullName,
        path,
        branch: widget.branch,
      );
      if (!mounted) {
        return;
      }
      if (content == null) {
        _toast('路径不存在：$path');
        return;
      }
      if (content.isDirectory) {
        await _goTo(content.path);
      } else {
        setState(() => _file = content);
      }
    } catch (error) {
      _toast('读取失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openFile(GhContent entry) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      // 走缓存（30 秒 TTL）。
      final GhContent? content = await widget.surface.domain.api.content(
        widget.fullName,
        entry.path,
        branch: widget.branch,
      );
      if (!mounted) {
        return;
      }
      if (content == null) {
        _toast('读取失败：文件可能已不存在');
        return;
      }
      setState(() => _file = content);
    } catch (error) {
      _toast('读取失败：$error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _openEditor(GhContent file) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => CodeEditorPage(
          surface: widget.surface,
          fullName: widget.fullName,
          path: file.path,
          initialText: file.text ?? '',
          baseSha: file.sha,
          branch: widget.branch,
        ),
      ),
    );
    if (saved == true && mounted) {
      await _refreshFile(file.path);
      await _reload();
    }
  }

  Future<void> _refreshFile(String path) async {
    try {
      // 刚从编辑器写回：必须回源（写路径已失效本地缓存，这里是双保险）。
      final GhContent? fresh = await widget.surface.domain.api.content(
        widget.fullName,
        path,
        branch: widget.branch,
        refresh: true,
      );
      if (mounted && fresh != null) {
        setState(() => _file = fresh);
      }
    } catch (_) {
      // 刷新失败不阻塞（旧内容仍在）。
    }
  }

  /// 新建文件（Material 对话框：路径 + 内容）。
  Future<void> _createFile() async {
    _newPath.text = _path.isEmpty ? '' : '$_path/';
    final TextEditingController content = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('新建文件'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _newPath,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '文件路径',
                  hintText: 'src/hello.dart',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: content,
                minLines: 4,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: const InputDecoration(
                  labelText: '内容（可留空后编辑）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) {
      return;
    }
    final String path = _newPath.text.trim();
    if (path.isEmpty) {
      _toast('请填写文件路径');
      return;
    }
    try {
      await widget.surface.domain.api.putContent(
        widget.fullName,
        path,
        content: content.text,
        message: 'chore: add $path',
        branch: widget.branch,
      );
      OgLAppLog.instance.result('仓库', '已新建文件', path);
      content.dispose();
      _toast('已创建：$path');
      await _reload();
    } catch (error) {
      content.dispose();
      _toast('创建失败：$error');
    }
  }

  Future<void> _deleteEntry(GhContent entry) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('将删除 ${entry.path} 并提交到仓库。该操作不易撤销。'),
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
      final GhWriteResult result =
          await widget.surface.domain.api.deleteContentLocked(
        widget.fullName,
        entry.path,
        message: 'chore: delete ${entry.path}',
        baseSha: entry.sha,
        branch: widget.branch,
        confirmed: true,
      );
      if (!result.ok) {
        _toast('删除失败：${result.detail ?? result.conflict.name}');
        return;
      }
      OgLAppLog.instance.result('仓库', '已删除', entry.path);
      if (_file?.path == entry.path) {
        setState(() => _file = null);
      }
      _toast('已删除：${entry.path}');
      await _reload();
    } catch (error) {
      _toast('删除失败：$error');
    }
  }

  /// 原始下载直链（路径分段做 URL 编码）。
  String? _downloadUrlOf(GhContent entry) {
    final String? direct = entry.downloadUrl;
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    if (entry.isDirectory) {
      return null;
    }
    final String encodedPath =
        entry.path.split('/').map(Uri.encodeComponent).join('/');
    return 'https://raw.githubusercontent.com/${widget.fullName}/'
        '${Uri.encodeComponent(widget.branch)}/$encodedPath';
  }

  Future<void> _downloadEntry(GhContent entry) async {
    final String? url = _downloadUrlOf(entry);
    if (url == null || url.isEmpty) {
      _toast('该条目没有可用的下载链接');
      return;
    }
    try {
      await widget.surface.domain.downloads.enqueue(
        url: url,
        fileName: ghPathName(entry.path),
        category: IxDownloadCategory.repo,
      );
      _toast('已加入下载：${ghPathName(entry.path)}');
    } catch (error) {
      _toast('加入下载失败：$error');
    }
  }

  void _showEntryDetails(GhContent entry) {
    final ThemeData theme = Theme.of(context);
    final String url = _downloadUrlOf(entry) ?? '';
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(ghPathName(entry.path)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _detailRow(theme, '路径', entry.path),
              _detailRow(theme, '类型', entry.isDirectory ? '目录' : '文件'),
              if (!entry.isDirectory)
                _detailRow(theme, '大小', ghSizeText(entry.size)),
              _detailRow(theme, 'SHA', entry.sha.isEmpty ? '—' : entry.sha),
              if (url.isNotEmpty) _detailRow(theme, '下载直链', url),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: entry.path));
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                _toast('已复制路径');
              }
            },
            child: const Text('复制路径'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(ThemeData theme, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: theme.textTheme.labelSmall),
            SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      );

  Future<void> _showEntryMenu(GhContent entry) async {
    final ThemeData theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: Icon(
                ogLFileVisualFor(entry.path, isDirectory: entry.isDirectory).icon,
                color:
                    ogLFileVisualFor(entry.path, isDirectory: entry.isDirectory).color,
              ),
              title: Text(ghPathName(entry.path)),
              subtitle: Text(entry.isDirectory ? '目录' : '文件'),
            ),
            const Divider(height: 1),
            if (!entry.isDirectory)
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('下载'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_downloadEntry(entry));
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('详情信息'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showEntryDetails(entry);
              },
            ),
            if (!entry.isDirectory)
              ListTile(
                leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                title: Text('删除', style: TextStyle(color: theme.colorScheme.error)),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  unawaited(_deleteEntry(entry));
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _breadcrumb(BuildContext context) {
    final List<String> parts =
        _path.split('/').where((String p) => p.isNotEmpty).toList();
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: <Widget>[
          TextButton(onPressed: () => _goTo(''), child: const Text('根目录')),
          for (int i = 0; i < parts.length; i++) ...<Widget>[
            Icon(Icons.chevron_right, size: 16, color: scheme.outline),
            TextButton(
              onPressed:
                  i == parts.length - 1 ? null : () => _goTo(parts.sublist(0, i + 1).join('/')),
              child: Text(parts[i]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _readmeTile() {
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
            onPressed: () => setState(() => _file = null),
          ),
          Expanded(
            child: Text(
              file.path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
          if (!file.isTooLarge)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '编辑',
              onPressed: () => _openEditor(file),
            ),
          PopupMenuButton<String>(
            onSelected: (String value) {
              switch (value) {
                case 'delete':
                  unawaited(_deleteFromFile(file));
                case 'browser':
                  _openFileInBrowser(file);
                case 'copy':
                  unawaited(_copyPath(file.path));
              }
            },
            itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'copy', child: Text('复制路径')),
              PopupMenuItem<String>(value: 'browser', child: Text('用浏览器打开')),
              PopupMenuItem<String>(value: 'delete', child: Text('删除文件')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFromFile(GhContent file) => _deleteEntry(file);

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    _toast('已复制路径');
  }

  void _openFileInBrowser(GhContent file) {
    final String? url = file.htmlUrl;
    if (url == null || url.isEmpty) {
      _toast('该文件没有可打开的链接');
      return;
    }
    unawaited(openLinkOrCopy(context, url, tag: '文件'));
  }

  static bool _isImage(String path) {
    final String lower = path.toLowerCase();
    for (final String ext in <String>[
      '.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.ico',
    ]) {
      if (lower.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  Widget _buildViewer(GhContent file, TextStyle codeStyle, OgLCodeTheme theme) {
    if (_isImage(file.path)) {
      final String? url = _downloadUrlOf(file);
      if (url == null) {
        return _MessagePane(
          icon: Icons.image_not_supported_outlined,
          message: '无法获取图片地址',
        );
      }
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: Image.network(
            url,
            fit: BoxFit.contain,
            loadingBuilder: (BuildContext context, Widget child,
                    ImageChunkEvent? progress) =>
                progress == null
                    ? child
                    : const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
            errorBuilder: (BuildContext context, Object error,
                    StackTrace? stack) =>
                _MessagePane(
              icon: Icons.broken_image_outlined,
              message: '图片加载失败（可点右上角用浏览器打开）',
            ),
          ),
        ),
      );
    }
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
      // 交给库渲染（自带双向滚动 / 行号 / 高亮），不再自建滚动包裹层。
      return OgLCodeViewer(
        code: text,
        path: file.path,
        fontSize: codeStyle.fontSize ?? 13,
        highlight: true,
        codeTheme: theme,
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final GhContent? file = _file;
    if (_busy) {
      return const Center(child: CircularProgressIndicator());
    }
    if (file != null) {
      return Column(
        children: <Widget>[
          _buildFileHeader(file),
          Expanded(
            child: _buildViewer(
              file,
              const TextStyle(fontFamily: 'monospace', fontSize: 13),
              OgLCodeTheme.fromScheme(theme.colorScheme),
            ),
          ),
        ],
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createFile,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('新建文件'),
      ),
      body: Column(
        children: <Widget>[
          if (_path.isNotEmpty) _breadcrumb(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _filter,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.filter_alt_outlined),
                hintText: '筛选当前目录',
              ),
              onChanged: (String value) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _entries,
              builder: (BuildContext context, Widget? _) {
                final String q = _filter.text.trim().toLowerCase();
                final List<GhContent> sorted = List<GhContent>.of(_entries.items)
                  ..sort((GhContent a, GhContent b) {
                    if (a.isDirectory != b.isDirectory) {
                      return a.isDirectory ? -1 : 1;
                    }
                    return ghPathName(a.path)
                        .toLowerCase()
                        .compareTo(ghPathName(b.path).toLowerCase());
                  });
                final List<GhContent> shown = q.isEmpty
                    ? sorted
                    : sorted
                        .where((GhContent e) =>
                            ghPathName(e.path).toLowerCase().contains(q))
                        .toList();
                if (_entries.items.isEmpty && _entries.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (_entries.items.isEmpty && _entries.error != null) {
                  return _MessagePane(
                    icon: Icons.error_outline,
                    message: _entries.error!,
                    action: FilledButton.tonal(
                      onPressed: _entries.refresh,
                      child: const Text('重试'),
                    ),
                  );
                }
                if (sorted.isEmpty) {
                  return _MessagePane(
                    icon: Icons.folder_open,
                    message: '这个目录是空的',
                    action: FilledButton.tonal(
                      onPressed: _createFile,
                      child: const Text('新建文件'),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => _reload(),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: <Widget>[
                      if (_path.isNotEmpty)
                        ListTile(
                          leading: const Icon(Icons.arrow_upward),
                          title: const Text('上一级'),
                          onTap: () {
                            final int cut = _path.lastIndexOf('/');
                            unawaited(_goTo(cut <= 0 ? '' : _path.substring(0, cut)));
                          },
                        ),
                      if (_path.isEmpty) _readmeTile(),
                      if (shown.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('没有匹配的条目')),
                        ),
                      for (int i = 0; i < shown.length; i++)
                        OgLReveal(
                          delay: OgLAnim.stagger(context, i),
                          child: ListTile(
                            leading: Icon(
                              ogLFileVisualFor(shown[i].path,
                                      isDirectory: shown[i].isDirectory)
                                  .icon,
                              color: ogLFileVisualFor(shown[i].path,
                                      isDirectory: shown[i].isDirectory)
                                  .color,
                            ),
                            title: Text(
                              ghPathName(shown[i].path),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: shown[i].isDirectory
                                ? null
                                : Text(ghSizeText(shown[i].size)),
                            trailing: shown[i].isDirectory
                                ? const Icon(Icons.chevron_right)
                                : null,
                            onTap: () {
                              if (shown[i].isDirectory) {
                                unawaited(_goTo(shown[i].path));
                              } else {
                                unawaited(_openFile(shown[i]));
                              }
                            },
                            onLongPress: () => unawaited(_showEntryMenu(shown[i])),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 议题 / PR
// ─────────────────────────────────────────────────────────────────────────────

class _IssuesTab extends StatefulWidget {
  const _IssuesTab({required this.surface, required this.fullName});

  final SurfaceBridge surface;
  final String fullName;

  @override
  State<_IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<_IssuesTab> {
  String _state = 'open';
  late final _Paged<Map<String, dynamic>> _paged =
      _Paged<Map<String, dynamic>>(loader: _load);

  Future<List<Map<String, dynamic>>> _load(int page) =>
      widget.surface.domain.api.issues(
        widget.fullName,
        state: _state,
        perPage: _kPageSize,
        page: page,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
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
      await _paged.refresh();
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
      await _paged.refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('关闭失败：$error')),
        );
      }
    }
  }

  void _openIssue(Map<String, dynamic> item) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => IssuePage(
          surface: widget.surface,
          fullName: widget.fullName,
          issue: item,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('新建议题'),
      ),
      body: Column(
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
                  unawaited(_paged.refresh());
                }
              },
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _paged,
              builder: (BuildContext context, Widget? _) => _pagedBody<Map<String, dynamic>>(
                context,
                _paged,
                (BuildContext context, Map<String, dynamic> item, int index) {
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
                emptyIcon: Icons.task_alt,
                emptyText: _state == 'all' ? '还没有议题' : '没有该状态的议题',
                emptyAction: FilledButton.tonal(
                  onPressed: _create,
                  child: const Text('新建议题'),
                ),
              ),
            ),
          ),
        ],
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
  String _state = 'open';
  late final _Paged<Map<String, dynamic>> _paged =
      _Paged<Map<String, dynamic>>(loader: _load);

  Future<List<Map<String, dynamic>>> _load(int page) =>
      widget.surface.domain.api.pulls(
        widget.fullName,
        state: _state,
        perPage: _kPageSize,
        page: page,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
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
                unawaited(_paged.refresh());
              }
            },
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: _paged,
            builder: (BuildContext context, Widget? _) => _pagedBody<Map<String, dynamic>>(
              context,
              _paged,
              (BuildContext context, Map<String, dynamic> item, int index) => ListTile(
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
              ),
              emptyIcon: Icons.call_merge,
              emptyText: _state == 'all' ? '还没有 PR' : '没有该状态的 PR',
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 发布
// ─────────────────────────────────────────────────────────────────────────────

class _ReleasesTab extends StatefulWidget {
  const _ReleasesTab({
    required this.surface,
    required this.fullName,
    required this.branch,
    super.key,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String branch;

  @override
  State<_ReleasesTab> createState() => _ReleasesTabState();
}

class _ReleasesTabState extends State<_ReleasesTab> {
  late final _Paged<GhRelease> _paged = _Paged<GhRelease>(
    loader: (int page) => widget.surface.domain.api.releases(
      widget.fullName,
      perPage: _kHeavyPageSize,
      page: page,
    ),
    cacheKey: 'releases:${widget.fullName}',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final GhRelease? created = await Navigator.of(context).push<GhRelease>(
      MaterialPageRoute<GhRelease>(
        builder: (BuildContext context) => NewReleasePage(
          surface: widget.surface,
          fullName: widget.fullName,
          defaultBranch: widget.branch,
        ),
      ),
    );
    if (created != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已创建发布 ${created.tagName}')),
      );
      await _paged.refresh();
    }
  }

  Future<void> _openDetail(GhRelease release) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ReleaseDetailPage(
          surface: widget.surface,
          fullName: widget.fullName,
          release: release,
        ),
      ),
    );
    if (changed == true && mounted) {
      await _paged.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.new_releases_outlined),
        label: const Text('新建发布'),
      ),
      body: ListenableBuilder(
        listenable: _paged,
        builder: (BuildContext context, Widget? _) => _pagedBody<GhRelease>(
          context,
          _paged,
          (BuildContext context, GhRelease release, int index) {
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () => unawaited(_openDetail(release)),
            );
          },
          emptyIcon: Icons.new_releases_outlined,
          emptyText: '还没有发布',
          emptyAction: FilledButton.tonal(
            onPressed: _create,
            child: const Text('新建发布'),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 分支
// ─────────────────────────────────────────────────────────────────────────────

class _BranchesTab extends StatefulWidget {
  const _BranchesTab({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
    required this.onBranchChanged,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String defaultBranch;
  final VoidCallback onBranchChanged;

  @override
  State<_BranchesTab> createState() => _BranchesTabState();
}

class _BranchesTabState extends State<_BranchesTab> {
  late final _Paged<GhBranch> _paged = _Paged<GhBranch>(
    loader: (int page) => widget.surface.domain.api.branches(
      widget.fullName,
      perPage: _kPageSize,
      page: page,
    ),
    cacheKey: 'branches:${widget.fullName}',
  );
  final TextEditingController _createName = TextEditingController();
  final TextEditingController _renameName = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    _createName.dispose();
    _renameName.dispose();
    super.dispose();
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
      await _paged.refresh();
      widget.onBranchChanged();
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
      await _paged.refresh();
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
      await widget.surface.domain.api.deleteBranch(widget.fullName, branch.name);
      OgLAppLog.instance.result('分支', '已删除', branch.name);
      await _paged.refresh();
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.alt_route),
        label: const Text('新建分支'),
      ),
      body: ListenableBuilder(
        listenable: _paged,
        builder: (BuildContext context, Widget? _) => _pagedBody<GhBranch>(
          context,
          _paged,
          (BuildContext context, GhBranch branch, int index) {
            final bool isDefault = branch.name == widget.defaultBranch;
            return ListTile(
              leading: Icon(
                branch.isProtected
                    ? Icons.lock_outline
                    : Icons.account_tree_outlined,
              ),
              title: Text(branch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                '${ghShortSha(branch.sha)}'
                '${isDefault ? ' · 默认分支' : ''}'
                '${branch.isProtected ? ' · 受保护' : ''}',
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (String value) {
                  if (value == 'rename') {
                    unawaited(_rename(branch));
                  } else if (value == 'delete') {
                    unawaited(_delete(branch));
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'rename',
                    enabled: !isDefault,
                    child: const Text('重命名'),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    enabled: !isDefault,
                    child: const Text('删除'),
                  ),
                ],
              ),
            );
          },
          emptyIcon: Icons.account_tree_outlined,
          emptyText: '还没有分支',
          emptyAction: FilledButton.tonal(
            onPressed: _create,
            child: const Text('新建分支'),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 提交
// ─────────────────────────────────────────────────────────────────────────────

class _CommitsTab extends StatefulWidget {
  const _CommitsTab({
    required this.surface,
    required this.fullName,
    required this.branch,
    super.key,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String branch;

  @override
  State<_CommitsTab> createState() => _CommitsTabState();
}

class _CommitsTabState extends State<_CommitsTab> {
  late final _Paged<GhCommit> _paged = _Paged<GhCommit>(
    loader: (int page) => widget.surface.domain.api.commits(
      widget.fullName,
      branch: widget.branch,
      perPage: _kPageSize,
      page: page,
    ),
    cacheKey: 'commits:${widget.fullName}:${widget.branch}',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _paged,
      builder: (BuildContext context, Widget? _) => _pagedBody<GhCommit>(
        context,
        _paged,
        (BuildContext context, GhCommit commit, int index) => ListTile(
          leading: const Icon(Icons.history),
          title: Text(commit.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${ghCommitAuthor(commit)} · '
            '${commit.date?.toIso8601String().split('T').first ?? ''} · '
            '${ghShortSha(commit.sha)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => CommitPage(
                surface: widget.surface,
                fullName: widget.fullName,
                commit: commit,
              ),
            ),
          ),
        ),
        emptyIcon: Icons.history,
        emptyText: '还没有提交',
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsTab extends StatefulWidget {
  const _ActionsTab({
    required this.surface,
    required this.fullName,
    required this.branch,
    super.key,
  });

  final SurfaceBridge surface;
  final String fullName;
  final String branch;

  @override
  State<_ActionsTab> createState() => _ActionsTabState();
}

class _ActionsTabState extends State<_ActionsTab> {
  String _filter = 'all';
  late final _Paged<Map<String, dynamic>> _paged =
      _Paged<Map<String, dynamic>>(
    loader: _load,
    cacheKey: 'actions:${widget.fullName}:${widget.branch}',
  );

  Future<List<Map<String, dynamic>>> _load(int page) =>
      widget.surface.domain.api.workflowRuns(
        widget.fullName,
        branch: widget.branch,
        perPage: _kHeavyPageSize,
        page: page,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_paged.refresh()));
  }

  @override
  void dispose() {
    _paged.dispose();
    super.dispose();
  }

  Future<void> _dispatch() async {
    final bool? triggered = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => WorkflowDispatchPage(
          surface: widget.surface,
          fullName: widget.fullName,
          defaultBranch: widget.branch,
        ),
      ),
    );
    if (triggered == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已触发工作流')),
      );
      await _paged.refresh();
    }
  }

  bool _matches(Map<String, dynamic> run) {
    if (_filter == 'all') {
      return true;
    }
    final String status = ghStr(run, 'status');
    final String conclusion = ghStr(run, 'conclusion');
    switch (_filter) {
      case 'running':
        return status != 'completed';
      case 'success':
        return conclusion == 'success';
      case 'failure':
        return conclusion == 'failure' || conclusion == 'timed_out';
      default:
        return true;
    }
  }

  IconData _iconFor(String status, String conclusion) {
    if (status != 'completed') {
      return Icons.sync;
    }
    switch (conclusion) {
      case 'success':
        return Icons.check_circle;
      case 'failure':
      case 'timed_out':
        return Icons.error;
      case 'cancelled':
      case 'skipped':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _paged,
      builder: (BuildContext context, Widget? _) {
        final List<Map<String, dynamic>> shown =
            _paged.items.where(_matches).toList();
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: _dispatch,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('手动触发'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: <Widget>[
                          for (final MapEntry<String, String> entry
                              in const <String, String>{
                            'all': '全部',
                            'running': '进行中',
                            'success': '成功',
                            'failure': '失败',
                          }.entries)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(entry.value),
                                selected: _filter == entry.key,
                                onSelected: (bool on) {
                                  if (on) {
                                    setState(() => _filter = entry.key);
                                  }
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: shown.isEmpty && _paged.items.isNotEmpty
                  ? const _MessagePane(
                      icon: Icons.filter_alt_off_outlined,
                      message: '没有符合筛选条件的运行',
                    )
                  : _pagedBody<Map<String, dynamic>>(
                      context,
                      _paged,
                      (BuildContext context, Map<String, dynamic> run, int index) {
                        final String status = ghStr(run, 'status');
                        final String conclusion = ghStr(run, 'conclusion');
                        return ListTile(
                          leading: Icon(
                            _iconFor(status, conclusion),
                            color: conclusion == 'success'
                                ? const Color(0xFF1A7F37)
                                : conclusion == 'failure' ||
                                        conclusion == 'timed_out'
                                    ? Theme.of(context).colorScheme.error
                                    : Theme.of(context).colorScheme.outline,
                          ),
                          title: Text(
                            ghStr(run, 'display_title').isEmpty
                                ? ghStr(run, 'name')
                                : ghStr(run, 'display_title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${ghStr(run, 'name')} · ${ghStr(run, 'event')} · '
                            '${status.isEmpty ? '—' : status}'
                            '${conclusion.isEmpty ? '' : ' / $conclusion'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (BuildContext context) => ActionRunPage(
                                surface: widget.surface,
                                fullName: widget.fullName,
                                run: run,
                              ),
                            ),
                          ),
                        );
                      },
                      emptyIcon: Icons.play_circle_outline,
                      emptyText: '没有工作流运行记录',
                      items: shown,
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 仓库设置
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
      if (mounted && cname != null) {
        setState(() => _cname.text = cname);
      }
    } catch (_) {
      // 大多数仓库没有自定义域名。
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
      if (mounted) {
        widget.onRepoChanged(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存')),
        );
      }
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
      final GhContent? existing = await widget.surface.domain.api
          .content(_full, 'CNAME', branch: widget.repo.defaultBranch);
      if (existing == null) {
        await widget.surface.domain.api.putContent(
          _full,
          'CNAME',
          content: '$domain\n',
          message: 'chore: configure custom domain',
          branch: widget.repo.defaultBranch,
        );
      } else {
        final GhWriteResult result = await widget.surface.domain.api
            .putContentLocked(
          _full,
          'CNAME',
          content: '$domain\n',
          message: 'chore: configure custom domain',
          baseSha: existing.sha,
          branch: widget.repo.defaultBranch,
        );
        if (!result.ok) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('CNAME 保存失败：${result.detail ?? result.conflict.name}'),
              ),
            );
          }
          return;
        }
      }
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
      await widget.surface.domain.api
          .enablePages(_full, branch: widget.repo.defaultBranch);
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
        content: Text('将删除 $_full（含代码与记录）。该操作不可撤销。'),
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
      OgLAppLog.instance.add('仓库', '已删除仓库 $_full',
          severity: OgLNoticeSeverity.warning);
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
          builder: (BuildContext context, AsyncSnapshot<Map<String, dynamic>?> snapshot) {
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
        Wrap(
          spacing: 8,
          children: <Widget>[
            FilledButton.tonal(
              onPressed: _busy ? null : _enablePages,
              child: const Text('启用（默认分支）'),
            ),
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
          style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.error),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('删除仓库会连同代码与记录一起消失，且不可撤销。'),
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

// ─────────────────────────────────────────────────────────────────────────────
// 通用
// ─────────────────────────────────────────────────────────────────────────────

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