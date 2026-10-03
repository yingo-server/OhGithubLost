/// L3 展示级 · 首页（我的仓库 / 星标仓库，分页）。
///
/// - 分段切换：`SegmentedButton`（我的 / 星标）；
/// - 列表：Material `ListTile` + 下拉刷新 + 「加载更多」；
/// - 四态（载 / 空 / 错 / 有数据）统一收敛；错误可见且可重试。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/animations.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import 'download_manager_page.dart';
import 'new_repo_page.dart';
import 'notifications_page.dart';
import 'repo_page.dart';

/// 每页条数。
const int _kPageSize = 30;

/// 首页。
class DashboardPage extends StatefulWidget {
  /// 创建页面。
  const DashboardPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _segment = 0;
  late final _RepoPaged _mine = _RepoPaged(
    loader: (int page) => widget.surface.domain.api
        .myRepos(perPage: _kPageSize, page: page, sort: 'updated'),
  );
  late final _RepoPaged _starred = _RepoPaged(
    loader: (int page) =>
        widget.surface.domain.api.starredRepos(perPage: _kPageSize, page: page),
  );

  _RepoPaged get _active => _segment == 0 ? _mine : _starred;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_mine.refresh()));
  }

  @override
  void dispose() {
    _mine.dispose();
    _starred.dispose();
    super.dispose();
  }

  void _segmentChanged(int value) {
    setState(() => _segment = value);
    unawaited(_active.refresh());
  }

  void _openRepo(GhRepo repo) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RepoPage(surface: widget.surface, repo: repo),
      ),
    );
  }

  void _openDownloads() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DownloadManagerPage(surface: widget.surface),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (BuildContext context) => const NotificationsPage()),
    );
  }

  Future<void> _createRepo() async {
    final GhRepo? created = await Navigator.of(context).push<GhRepo>(
      MaterialPageRoute<GhRepo>(
        builder: (BuildContext context) => NewRepoPage(surface: widget.surface),
      ),
    );
    if (created == null || !mounted) {
      return;
    }
    OgLAppLog.instance.result('首页', '已创建仓库', created.fullName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已创建 ${created.fullName}')),
    );
    await _mine.refresh();
    if (mounted) {
      setState(() => _segment = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: <Widget>[
          ListenableBuilder(
            listenable: OgLAppLog.instance,
            builder: (BuildContext context, Widget? _) {
              final int alerts = OgLAppLog.instance.entries
                  .where((OgLAppLogEntry e) => e.severity != OgLNoticeSeverity.info)
                  .length;
              return IconButton(
                icon: alerts > 0
                    ? Badge(
                        label: Text('$alerts'),
                        child: const Icon(Icons.notifications_outlined),
                      )
                    : const Icon(Icons.notifications_outlined),
                tooltip: '通知中心',
                onPressed: _openNotifications,
              );
            },
          ),
          ListenableBuilder(
            listenable: widget.surface.domain.downloads,
            builder: (BuildContext context, Widget? _) {
              final int running = widget.surface.domain.downloads.runningCount;
              return IconButton(
                icon: running > 0
                    ? Badge(
                        label: Text('$running'),
                        child: const Icon(Icons.download_outlined),
                      )
                    : const Icon(Icons.download_outlined),
                tooltip: '下载管理',
                onPressed: _openDownloads,
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRepo,
        icon: const Icon(Icons.add),
        label: const Text('新建仓库'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<int>(
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text('我的')),
                ButtonSegment<int>(value: 1, label: Text('星标')),
              ],
              selected: <int>{_segment},
              showSelectedIcon: false,
              onSelectionChanged: (Set<int> selection) {
                if (selection.isNotEmpty) {
                  _segmentChanged(selection.first);
                }
              },
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _active,
              builder: (BuildContext context, Widget? _) {
                final _RepoPaged p = _active;
                if (p.items.isEmpty && p.loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (p.items.isEmpty && p.error != null) {
                  return _RepoMessage(
                    icon: Icons.error_outline,
                    message: p.error!,
                    action: FilledButton.tonal(
                      onPressed: p.refresh,
                      child: const Text('重试'),
                    ),
                  );
                }
                if (p.items.isEmpty) {
                  return _RepoMessage(
                    icon: Icons.folder_outlined,
                    message: _segment == 0 ? '还没有仓库' : '还没有星标仓库',
                    action: _segment == 0
                        ? FilledButton(
                            onPressed: _createRepo,
                            child: const Text('新建仓库'),
                          )
                        : null,
                  );
                }
                return RefreshIndicator(
                  onRefresh: p.refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: p.items.length + (p.done ? 0 : 1),
                    separatorBuilder: (BuildContext context, int index) =>
                        const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index == p.items.length) {
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Center(
                            child: p.loading
                                ? const CircularProgressIndicator()
                                : OutlinedButton(
                                    onPressed: p.loadMore,
                                    child: Text('加载更多（已 ${p.items.length} 条）'),
                                  ),
                          ),
                        );
                      }
                      final GhRepo repo = p.items[index];
                      return OgLReveal(
                        delay: OgLAnim.stagger(context, index),
                        child: ListTile(
                          leading: Icon(
                            repo.isPrivate ? Icons.lock_outline : Icons.folder_outlined,
                          ),
                          title: Text(
                            repo.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _repoSubtitle(repo),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _openRepo(repo),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _repoSubtitle(GhRepo repo) {
    final List<String> meta = <String>[
      if (repo.language != null && repo.language!.isNotEmpty) repo.language!,
      '★ ${repo.stars}',
      if (repo.isPrivate) '私有',
    ];
    final String? desc = repo.description;
    if (desc == null || desc.isEmpty) {
      return meta.join(' · ');
    }
    return '${meta.join(' · ')} — $desc';
  }
}

/// 分页仓库源。
class _RepoPaged extends ChangeNotifier {
  _RepoPaged({required this.loader});

  final Future<List<GhRepo>> Function(int page) loader;

  final List<GhRepo> items = <GhRepo>[];
  int _page = 1;
  bool loading = false;
  bool done = false;
  String? error;

  Future<void> loadMore() async {
    if (loading || done) {
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final List<GhRepo> list = await loader(_page);
      items.addAll(list);
      if (list.length < _kPageSize) {
        done = true;
      }
      _page++;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    items.clear();
    _page = 1;
    done = false;
    error = null;
    await loadMore();
  }
}

/// 空/错态面板。
class _RepoMessage extends StatelessWidget {
  const _RepoMessage({required this.icon, required this.message, this.action});

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