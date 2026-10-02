/// L3 展示级 · Gist 列表（只读）。
///
/// - 一行一条：描述（缺省用首个文件名）/ 文件数 / 可见性 / 更新时间；
/// - 点击用系统浏览器打开（本客户端不做 Gist 编辑）。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../app/async.dart';
import '../surface_bridge.dart';
import '../util/gh_format.dart';
import '../util/link_opener.dart';

/// Gist 列表页。
class GistsPage extends StatefulWidget {
  /// 创建页面。
  const GistsPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<GistsPage> createState() => _GistsPageState();
}

class _GistsPageState extends State<GistsPage> {
  AsyncController<List<Map<String, dynamic>>>? _gists;

  @override
  void initState() {
    super.initState();
    _gistsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _gists?.dispose();
    super.dispose();
  }

  AsyncController<List<Map<String, dynamic>>> _gistsC() {
    final existing = _gists;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<Map<String, dynamic>>>(
      label: 'Gist',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.gists(),
    );
    _gists = controller;
    return controller;
  }

  /// 描述缺省时用文件名（GitHub 网页端也是这个行为）。
  String _titleOf(Map<String, dynamic> gist) {
    final Object? description = gist['description'];
    if (description is String && description.trim().isNotEmpty) {
      return description.trim();
    }
    final Object? files = gist['files'];
    if (files is Map<Object?, Object?> && files.isNotEmpty) {
      return '${files.keys.first}';
    }
    return '（无描述）';
  }

  int _fileCountOf(Map<String, dynamic> gist) {
    final Object? files = gist['files'];
    return files is Map<Object?, Object?> ? files.length : 0;
  }

  Future<void> _open(Map<String, dynamic> gist) async {
    final String url = ghStr(gist, 'html_url');
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这条 Gist 没有可打开的链接')),
        );
      }
      return;
    }
    await openLinkOrCopy(context, url, tag: 'Gist');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gist 片段')),
      body: AsyncView<List<Map<String, dynamic>>>(
        controller: _gistsC(),
        emptyIcon: Icons.article_outlined,
        emptyText: '还没有 Gist 片段',
        builder: (
          BuildContext context,
          List<Map<String, dynamic>> gists,
        ) =>
            RefreshIndicator(
          onRefresh: () => _gistsC().load(),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: gists.length,
            separatorBuilder: (BuildContext context, int index) =>
                const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final Map<String, dynamic> gist = gists[index];
              final bool isPublic = gist['public'] == true;
              return ListTile(
                leading: const Icon(Icons.article_outlined),
                title: Text(
                  _titleOf(gist),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_fileCountOf(gist)} 个文件 · '
                  '${isPublic ? '公开' : '私密'} · '
                  '${ghDate(gist, 'updated_at')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.open_in_new),
                onTap: () => unawaited(_open(gist)),
              );
            },
          ),
        ),
      ),
    );
  }
}