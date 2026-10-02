/// OGL 页面 · Gist 列表（只读 + 一键在浏览器打开）。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.8）
/// ```
/// OgLPageScaffold('Gist' + '共 N 条（本机只读）' + 刷新；下拉刷新)
/// └ OgLSection('全部片段') → OgLBox(padded:false) → 每行：
///    文件名/描述 + 'N 个文件 · 公开/私密 · 更新日期' + 公开/私密标签 + 外链箭头
/// ```
///
/// ## 纪律
/// - **每一行都可点**：点开用系统浏览器看（旧实现只读展示、点了没反应）；
/// - 空态 = Blankslate（说明"怎么建 Gist"），不是 Banner 冒充；
/// - 四态只走 `ogLAsyncView`。
library;

import 'package:flutter/material.dart';

import '../app/async_state.dart';
import '../app/async_view.dart';
import '../kit/kit.dart';
import '../readme/link_opener.dart';
import '../surface_bridge.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// Gist 列表页。
class OgLGistsPage extends StatefulWidget {
  /// 创建页面。
  const OgLGistsPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<OgLGistsPage> createState() => _OgLGistsPageState();
}

class _OgLGistsPageState extends State<OgLGistsPage> {
  OgLAsyncController<List<Map<String, dynamic>>>? _gists;

  @override
  void initState() {
    super.initState();
    _gistsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _gists?.removeListener(_onChanged);
    _gists?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  OgLAsyncController<List<Map<String, dynamic>>> _gistsC() {
    final existing = _gists;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<Map<String, dynamic>>>(
      label: 'Gist',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.gists(),
    );
    controller.addListener(_onChanged);
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

  String _dateOf(Map<String, dynamic> gist) {
    final Object? updated = gist['updated_at'];
    if (updated is! String || updated.isEmpty) {
      return '';
    }
    return updated.split('T').first;
  }

  Future<void> _open(Map<String, dynamic> gist) async {
    final Object? url = gist['html_url'];
    if (url is! String || url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('这条 Gist 没有可打开的链接')),
        );
      }
      return;
    }
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    final bool ok = await ogLOpenExternal(uri, tag: 'Gist');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开浏览器，链接：$url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgLAsyncController<List<Map<String, dynamic>>> controller = _gistsC();

    return OgLPageScaffold(
      title: 'Gist',
      description: '代码片段（只读列表；编辑与新建请在 GitHub 网页端）',
      leading: OgLIconButton(
        icon: OgLIconName.arrowLeft,
        label: '返回',
        onTap: () => Navigator.of(context).maybePop(),
      ),
      onRefresh: () async {
        await controller.load();
      },
      actions: <Widget>[
        OgLButton(
          label: '刷新',
          variant: OgLButtonVariant.invisible,
          leadingIcon: OgLIconName.sync,
          onPressed: () async {
            await controller.load();
          },
        ),
      ],
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? child) {
          final OgLAsync<List<Map<String, dynamic>>> state = controller.state;
          final List<Map<String, dynamic>> list =
              state.data ?? const <Map<String, dynamic>>[];
          return OgLSection(
            title: '全部片段',
            description: list.isEmpty ? null : '共 ${list.length} 条 · 点一行用浏览器打开',
            topSpacing: 0,
            child: ogLAsyncView<List<Map<String, dynamic>>>(
              state: state,
              onRetry: () async {
                await controller.load();
              },
              errorTitle: 'Gist 读取失败',
              emptyIcon: OgLIconName.code,
              emptyTitle: '还没有 Gist',
              emptyBody: 'Gist 是 GitHub 的代码片段服务；'
                  '在网页端新建后，这里会自动出现。',
              skeletonLines: 5,
              child: OgLBox(
                padded: false,
                child: Column(
                  children: <Widget>[
                    for (int i = 0; i < list.length; i++)
                      _GistRow(
                        gist: list[i],
                        title: _titleOf(list[i]),
                        fileCount: _fileCountOf(list[i]),
                        date: _dateOf(list[i]),
                        showDivider: i != list.length - 1,
                        onOpen: _open,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 一行 Gist：描述 + 文件数/可见性/日期 + 外链箭头，整行可点。
class _GistRow extends StatelessWidget {
  const _GistRow({
    required this.gist,
    required this.title,
    required this.fileCount,
    required this.date,
    required this.showDivider,
    required this.onOpen,
  });

  final Map<String, dynamic> gist;
  final String title;
  final int fileCount;
  final String date;
  final bool showDivider;
  final Future<void> Function(Map<String, dynamic> gist) onOpen;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final bool isPublic = gist['public'] == true;
    final List<String> meta = <String>[
      '$fileCount 个文件',
      isPublic ? '公开' : '私密',
      if (date.isNotEmpty) date,
    ];
    return OgLActionRow(
      leading: OgLIcon(
        name: OgLIconName.code,
        size: ogL.tokens.iconSize(base: 20),
        color: ogL.palette.textDim,
      ),
      title: title,
      subtitle: meta.join(' · '),
      trailing: OgLLabel(
        text: isPublic ? '公开' : '私密',
        variant: isPublic ? OgLLabelVariant.success : OgLLabelVariant.neutral,
      ),
      showChevron: true,
      showDivider: showDivider,
      onTap: () async {
        await onOpen(gist);
      },
    );
  }
}