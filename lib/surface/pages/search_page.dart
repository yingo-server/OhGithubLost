/// OGL 页面 · 搜索 —— 仓库搜索 + 代码搜索（服务端，`/search/*`）。
///
/// 结果页的"仓库"条目可直达仓库详情；代码结果 v1 只读展示
/// （直达文件视图待路由参数化后开放）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
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
      label: '搜索',
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
      label: '代码搜索',
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
    final q = _input.text.trim();
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

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        const OgLPageHeader(
          title: '搜索',
          description: '仓库与代码（经由 GitHub 服务端搜索）',
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: OgLTextField(
                controller: _input,
                hint: '输入关键词，如 flutter state',
                leadingIcon: OgLIconName.search,
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
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        Align(
          alignment: Alignment.centerLeft,
          child: OgLSegmented<_SearchMode>(
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
            onChanged: (mode) async {
              await _switchMode(mode);
            },
          ),
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        if (!_searched)
          Text(
            '输入关键词后点「搜索」。',
            style: TextStyle(
              fontSize: tokens.fontSize(scale.body),
              color: ogL.palette.textDim,
            ),
          )
        else if (_mode == _SearchMode.repos)
          _buildRepoResults(ogL, tokens)
        else
          _buildCodeResults(ogL, tokens),
      ],
    );
  }

  Widget _buildRepoResults(OgLTheme ogL, OgLTokens tokens) {
    final state = _reposC().state;
    final list = state.data ?? const <GhRepo>[];
    if (state.failureMessage != null) {
      return OgLBanner(
        variant: OgLBannerVariant.danger,
        title: '搜索失败',
        text: state.failureMessage!,
        actions: <Widget>[
          OgLButton(
            label: '重试',
            size: OgLButtonSize.small,
            onPressed: () async {
              await _reposC().load();
            },
          ),
        ],
      );
    }
    if (state.isFirstLoading) {
      return const OgLSkeletonText(lines: 5);
    }
    if (list.isEmpty) {
      return const OgLBanner(
        variant: OgLBannerVariant.info,
        text: '没有匹配的仓库。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final repo in list)
          OgLActionRow(
            leading: OgLIcon(
              name: OgLIconName.repository,
              size: tokens.iconSize(base: 20),
              color: ogL.palette.textDim,
            ),
            title: repo.fullName,
            subtitle: repo.description == null || repo.description!.isEmpty
                ? '★ ${repo.stars}'
                : '★ ${repo.stars} · ${repo.description}',
            showChevron: true,
            onTap: () => _openRepo(repo),
          ),
      ],
    );
  }

  Widget _buildCodeResults(OgLTheme ogL, OgLTokens tokens) {
    final state = _codeC().state;
    final list = state.data ?? const <Map<String, dynamic>>[];
    if (state.failureMessage != null) {
      return OgLBanner(
        variant: OgLBannerVariant.danger,
        title: '搜索失败',
        text: state.failureMessage!,
        actions: <Widget>[
          OgLButton(
            label: '重试',
            size: OgLButtonSize.small,
            onPressed: () async {
              await _codeC().load();
            },
          ),
        ],
      );
    }
    if (state.isFirstLoading) {
      return const OgLSkeletonText(lines: 5);
    }
    if (list.isEmpty) {
      return const OgLBanner(
        variant: OgLBannerVariant.info,
        text: '没有匹配的代码。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final item in list)
          OgLActionRow(
            leading: OgLIcon(
              name: OgLIconName.code,
              size: tokens.iconSize(base: 20),
              color: ogL.palette.textDim,
            ),
            title: GhJson.str(item, 'name'),
            subtitle: '${_repoOf(item)} · ${GhJson.str(item, 'path')}',
          ),
      ],
    );
  }

  String _repoOf(Map<String, dynamic> item) {
    final repo = item['repository'];
    if (repo is Map<Object?, Object?>) {
      return GhJson.str(Map<String, dynamic>.from(repo), 'full_name');
    }
    return '';
  }
}