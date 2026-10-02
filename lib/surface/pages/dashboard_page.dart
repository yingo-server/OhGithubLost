/// L3 展示级 · 首页（我的仓库 / 星标仓库）。
///
/// - 分段切换：`SegmentedButton`（我的 / 星标）；
/// - 列表：`ListTile` + 刷新（下拉刷新 + 页头刷新按钮）；
/// - 四态收敛在 [AsyncView]（载 / 空 / 错 / 有数据，错误不许无声消失）；
/// - 主操作只有一个：新建仓库（页头）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import 'new_repo_page.dart';
import 'repo_page.dart';

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
  /// 0 = 我的仓库；1 = 星标仓库。
  int _segment = 0;

  AsyncController<List<GhRepo>>? _mine;
  AsyncController<List<GhRepo>>? _starred;

  @override
  void initState() {
    super.initState();
    _mineC().loadIfNeeded();
  }

  @override
  void dispose() {
    _mine?.dispose();
    _starred?.dispose();
    super.dispose();
  }

  AsyncController<List<GhRepo>> _mineC() {
    final existing = _mine;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhRepo>>(
      label: '我的仓库',
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.myRepos(perPage: 100),
    );
    _mine = controller;
    return controller;
  }

  AsyncController<List<GhRepo>> _starredC() {
    final existing = _starred;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhRepo>>(
      label: '星标仓库',
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.starredRepos(perPage: 100),
    );
    _starred = controller;
    return controller;
  }

  AsyncController<List<GhRepo>> get _active =>
      _segment == 0 ? _mineC() : _starredC();

  void _segmentChanged(int value) {
    setState(() => _segment = value);
    _active.loadIfNeeded();
  }

  Future<void> _refresh() => _active.load();

  void _openRepo(GhRepo repo) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            RepoPage(surface: widget.surface, repo: repo),
      ),
    );
  }

  Future<void> _createRepo() async {
    final GhRepo? created = await Navigator.of(context).push<GhRepo>(
      MaterialPageRoute<GhRepo>(
        builder: (BuildContext context) => NewRepoPage(surface: widget.surface),
      ),
    );
    if (created == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    OgLAppLog.instance.result('首页', '已创建仓库', created.fullName);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已创建 ${created.fullName}')),
    );
    await _mineC().load();
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
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refresh,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建仓库',
            onPressed: _createRepo,
          ),
        ],
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
            child: AsyncView<List<GhRepo>>(
              controller: _active,
              emptyIcon: Icons.folder_outlined,
              emptyText: _segment == 0 ? '还没有仓库' : '还没有星标仓库',
              emptyAction: _segment == 0
                  ? FilledButton(
                      onPressed: _createRepo,
                      child: const Text('新建仓库'),
                    )
                  : null,
              builder: (BuildContext context, List<GhRepo> repos) =>
                  RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: repos.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final GhRepo repo = repos[index];
                    return ListTile(
                      leading: Icon(
                        repo.isPrivate
                            ? Icons.lock_outline
                            : Icons.folder_outlined,
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
                    );
                  },
                ),
              ),
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