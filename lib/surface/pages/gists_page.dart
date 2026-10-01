/// OGL 页面 · Gist 列表（只读）。
library;

import 'package:flutter/material.dart';

import '../app/async_state.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
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

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final state = _gistsC().state;
    final list = state.data ?? const <Map<String, dynamic>>[];

    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        OgLPageHeader(
          title: 'Gist',
          description: '共 ${list.length} 条（只读列表，编辑请前往 GitHub 网页端）',
          actions: <Widget>[
            OgLButton(
              label: '刷新',
              variant: OgLButtonVariant.invisible,
              leadingIcon: OgLIconName.sync,
              onPressed: () async {
                await _gistsC().load();
              },
            ),
          ],
        ),
        if (state.data == null && state.message != null)
          OgLBanner(
            variant: OgLBannerVariant.danger,
            title: 'Gist 读取失败',
            text: state.message!,
            actions: <Widget>[
              OgLButton(
                label: '重试',
                size: OgLButtonSize.small,
                onPressed: () async {
                  await _gistsC().load();
                },
              ),
            ],
          )
        else if (state.data == null)
          const OgLSkeletonText(lines: 5)
        else if (list.isEmpty)
          const OgLBanner(
            variant: OgLBannerVariant.info,
            text: '还没有 Gist。',
          )
        else
          for (final gist in list)
            OgLActionRow(
              leading: Icon(
                ogL.icon(OgLIconName.code),
                size: tokens.iconSize(base: 20),
                color: ogL.palette.textDim,
              ),
              title: _descriptionOf(gist),
              subtitle: '${_filesOf(gist)} 个文件 · '
                  '${_publicOf(gist) ? '公开' : '私密'}',
            ),
      ],
    );
  }

  String _descriptionOf(Map<String, dynamic> gist) {
    final description = gist['description'];
    if (description is String && description.isNotEmpty) {
      return description;
    }
    final files = gist['files'];
    if (files is Map<Object?, Object?> && files.isNotEmpty) {
      final first = files.keys.first;
      return '$first';
    }
    return '（无描述）';
  }

  int _filesOf(Map<String, dynamic> gist) {
    final files = gist['files'];
    return files is Map<Object?, Object?> ? files.length : 0;
  }

  bool _publicOf(Map<String, dynamic> gist) => gist['public'] == true;
}