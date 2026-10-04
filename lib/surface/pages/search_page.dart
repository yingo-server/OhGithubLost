/// L3 展示级 · 搜索页（仓库 / 代码，服务端搜索）。
///
/// - 模式切换：`SegmentedButton`（仓库 / 代码）；
/// - 回车即搜；空关键字不打扰服务端；
/// - 结果行：仓库 → 仓库页；代码 → 直达所属仓库的该文件。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/animations.dart';

import '../app/async.dart';
import '../app/error_surface.dart';

import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';

import '../types.dart';
import '../util/gh_format.dart';

import 'repo_page.dart';

/// 取 `search_page` 分片文案。
String _t(String key, [Map<String, String>? args]) =>
    OgLI18n.instance.t('search_page', key, args: args);

/// 一条搜索命中（把两种结果形态收敛成同一种展示）。
class _SearchHit {
  const _SearchHit({
    required this.title,
    required this.subtitle,
    required this.repo,
    this.initialPath,
  });

  final String title;
  final String subtitle;
  final GhRepo? repo;
  final String? initialPath;
}

/// 搜索页。
class SearchPage extends StatefulWidget {
  /// 创建页面。
  const SearchPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _input = TextEditingController();

  /// 0 = 仓库；1 = 代码。
  int _mode = 0;

  AsyncController<List<_SearchHit>>? _results;
  String _query = '';

  @override
  void dispose() {
    _input.dispose();
    _results?.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final String q = _input.text.trim();
    if (q.isEmpty) {
      return;
    }
    _query = q;
    final AsyncController<List<_SearchHit>> controller;
    if (_mode == 0) {
      controller = AsyncController<List<_SearchHit>>(
        label: _t('repoSearch'),
        isEmpty: (List<_SearchHit> value) => value.isEmpty,
        loader: () async {
          final List<GhRepo> repos =
              await widget.surface.domain.api.searchRepos(q, perPage: 30);
          OgLAppLog.instance.add(_t('search'), _t('repoResults', <String, String>{'q': q, 'count': repos.length}));
          return repos
              .map(
                (GhRepo repo) => _SearchHit(
                  title: repo.fullName,
                  subtitle: _repoSubtitle(repo),
                  repo: repo,
                ),
              )
              .toList();
        },
      );
    } else {
      controller = AsyncController<List<_SearchHit>>(
        label: _t('codeSearch'),
        isEmpty: (List<_SearchHit> value) => value.isEmpty,
        loader: () async {
          final List<Map<String, dynamic>> items =
              await widget.surface.domain.api.searchCode(q, perPage: 30);
          OgLAppLog.instance.add(_t('search'), _t('codeResults', <String, String>{'q': q, 'count': items.length}));
          return items.map(_hitFromCode).toList();
        },
      );
    }
    final old = _results;
    setState(() => _results = controller);
    old?.dispose();
    unawaited(controller.load());
  }

  /// 代码命中 → 展示行（含“直达文件”所需的仓库 + 路径）。
  _SearchHit _hitFromCode(Map<String, dynamic> item) {
    final String path = ghStr(item, 'path');
    final String name = ghStr(item, 'name');
    final String fragment = _fragmentOf(item);
    final Map<String, dynamic>? repoMap = _repoOf(item);
    final GhRepo repo = repoMap == null
        ? GhRepo.fromJson(const <String, dynamic>{})
        : GhRepo.fromJson(repoMap);
    return _SearchHit(
      title: path.isEmpty ? name : path,
      subtitle: fragment.isEmpty ? _t('openFileHint') : fragment,
      repo: repo.fullName.isEmpty ? null : repo,
      initialPath: path.isEmpty ? null : path,
    );
  }

  String _fragmentOf(Map<String, dynamic> item) {
    final Object? matches = item['text_matches'];
    if (matches is! List<Object?>) {
      return '';
    }
    for (final Object? match in matches) {
      if (match is Map<Object?, Object?>) {
        final String fragment =
            ghStr(Map<String, dynamic>.from(match), 'fragment').trim();
        if (fragment.isNotEmpty) {
          return fragment.replaceAll(RegExp(r'\s+'), ' ').trim();
        }
      }
    }
    return '';
  }

  Map<String, dynamic>? _repoOf(Map<String, dynamic> item) {
    final Object? repo = item['repository'];
    if (repo is Map<Object?, Object?>) {
      return Map<String, dynamic>.from(repo);
    }
    return null;
  }

  void _open(_SearchHit hit) {
    final GhRepo? repo = hit.repo;
    if (repo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(_t('noRepoForResult'))),
      );
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => RepoPage(
          surface: widget.surface,
          repo: repo,
          initialPath: hit.initialPath,
        ),
      ),
    );
  }

  String _repoSubtitle(GhRepo repo) {
    final List<String> meta = <String>[
      if (repo.language != null && repo.language!.isNotEmpty) repo.language!,
      '★ ${repo.stars}',
      if (repo.isPrivate) _t('private'),
    ];
    final String? desc = repo.description;
    if (desc == null || desc.isEmpty) {
      return meta.join(' · ');
    }
    return '${meta.join(' · ')} — $desc';
  }

  @override
  Widget build(BuildContext context) {
    final AsyncController<List<_SearchHit>>? controller = _results;
    return Scaffold(
      appBar: AppBar(title:  Text(_t('search'))),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: <Widget>[
                SegmentedButton<int>(
                  segments:  <ButtonSegment<int>>[
                    ButtonSegment<int>(value: 0, label: Text(_t('tabRepos'))),
                    ButtonSegment<int>(value: 1, label: Text(_t('tabCode'))),
                  ],
                  selected: <int>{_mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (Set<int> selection) {
                    if (selection.isNotEmpty && selection.first != _mode) {
                      // 切换模式必须清空旧结果：否则会出现"代码结果留在仓库标签下"。
                      final AsyncController<List<_SearchHit>>? old = _results;
                      setState(() {
                        _mode = selection.first;
                        _results = null;
                        _query = '';
                        _input.clear();
                      });
                      old?.dispose();
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _input,
                  textInputAction: TextInputAction.search,
                  decoration:  InputDecoration(
                    hintText: _t('queryHint'),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (String _) async {
                    await _run();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: controller == null
                ?  Center(child: Text(_t('startHint')))
                : AsyncView<List<_SearchHit>>(
                    controller: controller,
                    emptyIcon: Icons.search_off,
                    emptyText: _t('noResults', <String, String>{'query': _query}),
                    builder: (
                      BuildContext context,
                      List<_SearchHit> hits,
                    ) =>
                        ListView.separated(
                      itemCount: hits.length,
                      separatorBuilder: (BuildContext context, int index) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext context, int index) {
                        final _SearchHit hit = hits[index];
                        return OgLReveal(
                          delay: OgLAnim.stagger(context, index),
                          child: ListTile(
                            leading: Icon(
                              hit.initialPath == null
                                  ? Icons.folder_outlined
                                  : Icons.description_outlined,
                            ),
                            title: Text(
                              hit.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              hit.subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _open(hit),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}