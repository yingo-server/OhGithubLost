/// OGL 页面 · 搜索 —— 仓库搜索 + 代码搜索（服务端 `/search/*`）。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.3）
/// ```
/// OgLPageScaffold(标题 + 说明)
/// ├ 搜索行：OgLTextField（回车即搜，键盘动作=search）+ 主操作按钮
/// ├ OgLSegmented(仓库 | 代码) + 右侧"结果计数"
/// └ 结果区：OgLBox(padded:false) 包行
///    - 未搜：OgLBlankslate（给用法与限定符，而不是一句"输入关键词"）
///    - 空结果：OgLBlankslate（把关键词回显，说明怎么放宽）
///    - 失败：OgLBanner(danger) + 重试（错误必须可见）
///    - 有结果：仓库行（可点进仓库）/ 代码行（可点进所属仓库）
/// ```
///
/// ## 纪律
/// 四态只走 `ogLAsyncView`；**代码结果也必须可点**（旧实现点了没反应，就是"失效"）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
import '../app/async_view.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'repo_page.dart';

/// 搜索模式。
enum _SearchMode {
  /// 搜仓库。
  repos,

  /// 搜代码。
  code,
}

/// 常用搜索限定符（GitHub 的语法，直接可抄）。
const List<List<String>> _qualifiers = <List<String>>[
  <String>['repo:owner/name', '只搜某个仓库里的代码'],
  <String>['language:dart', '限定语言'],
  <String>['org:github', '限定组织'],
  <String>['path:lib/', '限定目录（代码搜索）'],
  <String>['stars:>100', '按星标数筛选（仓库搜索）'],
];

/// 搜索页。
class OgLSearchPage extends StatefulWidget {
  /// 创建页面。
  const OgLSearchPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<OgLSearchPage> createState() => _OgLSearchPageState();
}

class _OgLSearchPageState extends State<OgLSearchPage> {
  final TextEditingController _input = TextEditingController();
  _SearchMode _mode = _SearchMode.repos;
  OgLAsyncController<List<GhRepo>>? _repoResults;
  OgLAsyncController<List<Map<String, dynamic>>>? _codeResults;
  String _query = '';
  bool _searched = false;

  @override
  void dispose() {
    _input.dispose();
    _repoResults?.removeListener(_onChanged);
    _repoResults?.dispose();
    _codeResults?.removeListener(_onChanged);
    _codeResults?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  OgLAsyncController<List<GhRepo>> _reposC() {
    final existing = _repoResults;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhRepo>>(
      label: '搜索仓库',
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      loader: () async {
        final list =
            await widget.surface.domain.api.searchRepos(_query, perPage: 30);
        OgLAppLog.instance.add('搜索', '「$_query」仓库结果：${list.length} 个');
        return list;
      },
    );
    controller.addListener(_onChanged);
    _repoResults = controller;
    return controller;
  }

  OgLAsyncController<List<Map<String, dynamic>>> _codeC() {
    final existing = _codeResults;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<Map<String, dynamic>>>(
      label: '搜索代码',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () async {
        final list =
            await widget.surface.domain.api.searchCode(_query, perPage: 30);
        OgLAppLog.instance.add('搜索', '「$_query」代码结果：${list.length} 条');
        return list;
      },
    );
    controller.addListener(_onChanged);
    _codeResults = controller;
    return controller;
  }

  Future<void> _search() async {
    final String q = _input.text.trim();
    if (q.isEmpty) {
      setState(() => _searched = false);
      return;
    }
    setState(() {
      _query = q;
      _searched = true;
    });
    if (_mode == _SearchMode.repos) {
      await _reposC().load();
    } else {
      await _codeC().load();
    }
  }

  Future<void> _switchMode(_SearchMode mode) async {
    if (mode == _mode) {
      return;
    }
    setState(() => _mode = mode);
    if (_searched && _query.isNotEmpty) {
      if (mode == _SearchMode.repos) {
        await _reposC().load();
      } else {
        await _codeC().load();
      }
    }
  }

  void _openRepo(GhRepo repo) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            OgLRepoPage(surface: widget.surface, repo: repo),
      ),
    );
  }

  /// 代码结果没有完整的仓库对象，只能按 `full_name` 现造一个最小的
  /// （仓库页会自己补齐缺失字段 —— 不再有"猜默认分支"的问题）。
  void _openCodeHit(Map<String, dynamic> item) {
    final String full = _repoOf(item);
    if (full.isEmpty || !full.contains('/')) {
      OgLAppLog.instance.add('搜索', '代码结果缺少仓库信息，无法跳转：$item');
      return;
    }
    final GhRepo repo = GhRepo.fromJson(<String, dynamic>{'full_name': full});
    _openRepo(repo);
  }

  String _repoOf(Map<String, dynamic> item) {
    final Object? repo = item['repository'];
    if (repo is Map<Object?, Object?>) {
      return GhJson.str(Map<String, dynamic>.from(repo), 'full_name');
    }
    return '';
  }

  /// 结果计数说明（把"有多少"讲清楚）。
  String _countLabel() {
    if (!_searched) {
      return '';
    }
    if (_mode == _SearchMode.repos) {
      final OgLAsync<List<GhRepo>> state = _reposC().state;
      if (state.isFirstLoading) {
        return '搜索中…';
      }
      final List<GhRepo>? data = state.data;
      if (data == null) {
        return state.failureMessage != null ? '搜索失败' : '没有结果';
      }
      return '${data.length} 个仓库';
    }
    final OgLAsync<List<Map<String, dynamic>>> state = _codeC().state;
    if (state.isFirstLoading) {
      return '搜索中…';
    }
    final List<Map<String, dynamic>>? data = state.data;
    if (data == null) {
      return state.failureMessage != null ? '搜索失败' : '没有结果';
    }
    return '${data.length} 条代码';
  }

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();

    return OgLPageScaffold(
      title: '搜索',
      description: '仓库与代码（经由 GitHub 服务端搜索）',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: OgLTextField(
                  controller: _input,
                  hint: '关键词 / 限定符，如 flutter repo:flutter/flutter',
                  leadingIcon: OgLIconName.search,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (String value) async {
                    await _search();
                  },
                ),
              ),
              SizedBox(width: tokens.space(OgLSpacing.sm)),
              OgLButton(
                label: '搜索',
                variant: OgLButtonVariant.primary,
                leadingIcon: OgLIconName.search,
                onPressed: _search,
              ),
            ],
          ),
          SizedBox(height: tokens.space(OgLSpacing.md)),
          Row(
            children: <Widget>[
              OgLSegmented<_SearchMode>(
                items: const <OgLSegmentedItem<_SearchMode>>[
                  OgLSegmentedItem<_SearchMode>(
                    value: _SearchMode.repos,
                    label: '仓库',
                  ),
                  OgLSegmentedItem<_SearchMode>(
                    value: _SearchMode.code,
                    label: '代码',
                  ),
                ],
                value: _mode,
                onChanged: (_SearchMode mode) async {
                  await _switchMode(mode);
                },
              ),
              SizedBox(width: tokens.space(OgLSpacing.sm)),
              Expanded(
                child: Text(
                  _countLabel(),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tokens.fontSize(scale.label),
                    color: ogL.palette.textDim,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.space(OgLSpacing.md)),
          if (!_searched)
            _buildHowTo(context)
          else if (_mode == _SearchMode.repos)
            _buildRepoResults()
          else
            _buildCodeResults(),
        ],
      ),
    );
  }

  /// 未搜索时的空态：**给用法**（而不是一句"请输入关键词"）。
  Widget _buildHowTo(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OgLBlankslate(
          icon: OgLIconName.search,
          title: '输入关键词开始搜索',
          body: '回车即搜。仓库搜索找项目，代码搜索找具体实现（需要登录）。',
        ),
        OgLSection(
          title: '常用限定符',
          description: '和 GitHub 网页端一致的语法，可直接抄',
          child: OgLBox(
            padded: false,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < _qualifiers.length; i++)
                  OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.terminal,
                      size: ogL.tokens.iconSize(base: 18),
                      color: ogL.palette.textDim,
                    ),
                    title: _qualifiers[i][0],
                    subtitle: _qualifiers[i][1],
                    showDivider: i != _qualifiers.length - 1,
                    onTap: () => setState(() {
                      _input.text = '${_input.text} ${_qualifiers[i][0]}'.trim();
                    }),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRepoResults() {
    final OgLAsyncController<List<GhRepo>> controller = _reposC();
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final OgLAsync<List<GhRepo>> state = controller.state;
        final List<GhRepo> list = state.data ?? const <GhRepo>[];
        return ogLAsyncView<List<GhRepo>>(
          state: state,
          onRetry: () async {
            await controller.load();
          },
          errorTitle: '仓库搜索失败',
          emptyIcon: OgLIconName.search,
          emptyTitle: '没有匹配「$_query」的仓库',
          emptyBody: '试试更短的关键词，或加上 language: / stars:>10 之类的限定符。',
          skeletonLines: 5,
          child: OgLBox(
            padded: false,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < list.length; i++)
                  _RepoHitRow(
                    repo: list[i],
                    showDivider: i != list.length - 1,
                    onOpen: _openRepo,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCodeResults() {
    final OgLAsyncController<List<Map<String, dynamic>>> controller = _codeC();
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final OgLAsync<List<Map<String, dynamic>>> state = controller.state;
        final List<Map<String, dynamic>> list =
            state.data ?? const <Map<String, dynamic>>[];
        return ogLAsyncView<List<Map<String, dynamic>>>(
          state: state,
          onRetry: () async {
            await controller.load();
          },
          errorTitle: '代码搜索失败',
          emptyIcon: OgLIconName.code,
          emptyTitle: '没有匹配「$_query」的代码',
          emptyBody: '代码搜索只覆盖你有权访问的仓库；试试 repo:owner/name 缩小范围。',
          skeletonLines: 5,
          child: OgLBox(
            padded: false,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < list.length; i++)
                  _CodeHitRow(
                    item: list[i],
                    repoOf: _repoOf(list[i]),
                    showDivider: i != list.length - 1,
                    onOpen: _openCodeHit,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 仓库命中行。
class _RepoHitRow extends StatelessWidget {
  const _RepoHitRow({
    required this.repo,
    required this.showDivider,
    required this.onOpen,
  });

  final GhRepo repo;
  final bool showDivider;
  final void Function(GhRepo repo) onOpen;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final List<String> meta = <String>[
      if (repo.language != null && repo.language!.isNotEmpty) repo.language!,
      '★ ${repo.stars}',
      if (repo.isPrivate) '私有',
    ];
    final String? desc = repo.description;
    return OgLActionRow(
      leading: OgLIcon(
        name: OgLIconName.repository,
        size: ogL.tokens.iconSize(base: 20),
        color: ogL.palette.textDim,
      ),
      title: repo.fullName,
      subtitle: desc == null || desc.isEmpty
          ? meta.join(' · ')
          : '${meta.join(' · ')} — $desc',
      showChevron: true,
      showDivider: showDivider,
      onTap: () => onOpen(repo),
    );
  }
}

/// 代码命中行：**可点**（进所属仓库）——旧实现点了没反应。
class _CodeHitRow extends StatelessWidget {
  const _CodeHitRow({
    required this.item,
    required this.repoOf,
    required this.showDivider,
    required this.onOpen,
  });

  final Map<String, dynamic> item;
  final String repoOf;
  final bool showDivider;
  final void Function(Map<String, dynamic> item) onOpen;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final String path = GhJson.str(item, 'path');
    final String name = GhJson.str(item, 'name');
    final String title = path.isEmpty ? name : path;
    final String subtitle =
        repoOf.isEmpty ? '（未知仓库）' : '$repoOf · 点开进入该仓库';
    return OgLActionRow(
      leading: OgLIcon(
        name: OgLIconName.file,
        size: ogL.tokens.iconSize(base: 20),
        color: ogL.palette.textDim,
      ),
      title: title.isEmpty ? '（无路径）' : title,
      subtitle: subtitle,
      showChevron: repoOf.isNotEmpty,
      showDivider: showDivider,
      onTap: () => onOpen(item),
    );
  }
}