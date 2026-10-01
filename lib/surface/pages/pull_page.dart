/// OGL 页面 · PR 详情（信息 + 文件变更清单）。
library;

import 'package:flutter/material.dart';

import '../app/async_state.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// PR 详情页。
class OgLPullPage extends StatefulWidget {
  /// 创建页面。
  const OgLPullPage({
    required this.surface,
    required this.fullName,
    required this.pull,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// PR 原始数据（来自列表）。
  final Map<String, dynamic> pull;

  @override
  State<OgLPullPage> createState() => _OgLPullPageState();
}

class _OgLPullPageState extends State<OgLPullPage> {
  OgLAsyncController<List<Map<String, dynamic>>>? _files;

  @override
  void initState() {
    super.initState();
    _filesC().loadIfNeeded();
  }

  @override
  void dispose() {
    _files?.removeListener(_onChanged);
    _files?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  int get _number => GhJson.integer(widget.pull, 'number');

  OgLAsyncController<List<Map<String, dynamic>>> _filesC() {
    final existing = _files;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<Map<String, dynamic>>>(
      label: '变更',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () =>
          widget.surface.domain.api.pullFiles(widget.fullName, _number),
    );
    controller.addListener(_onChanged);
    _files = controller;
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final pull = widget.pull;
    final body = GhJson.strOrNull(pull, 'body');
    final user = pull['user'];
    final login = user is Map<Object?, Object?>
        ? GhJson.str(Map<String, dynamic>.from(user), 'login')
        : '';
    final state = _filesC().state;
    final files = state.data ?? const <Map<String, dynamic>>[];

    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        OgLPageHeader(
          title: '#$_number ${GhJson.str(pull, 'title')}',
          description: 'by $login · ${GhJson.str(pull, 'state')}',
          actions: <Widget>[
            OgLButton(
              label: '刷新',
              variant: OgLButtonVariant.invisible,
              leadingIcon: OgLIconName.sync,
              onPressed: () async {
                await _filesC().load();
              },
            ),
          ],
        ),
        if (body != null && body.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: tokens.space(OgLSpacing.md)),
            child: SelectableText(
              body,
              style: TextStyle(
                fontSize: tokens.fontSize(scale.body),
                color: ogL.palette.textDim,
              ),
            ),
          ),
        Text(
          '变更文件（${files.length}）',
          style: TextStyle(
            fontSize: tokens.fontSize(scale.title),
            fontWeight: FontWeight.w600,
            color: ogL.palette.text,
          ),
        ),
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        if (state.data == null && state.message != null)
          OgLBanner(
            variant: OgLBannerVariant.danger,
            title: '文件读取失败',
            text: state.message!,
            actions: <Widget>[
              OgLButton(
                label: '重试',
                size: OgLButtonSize.small,
                onPressed: () async {
                  await _filesC().load();
                },
              ),
            ],
          )
        else if (state.data == null)
          const OgLSkeletonText(lines: 4)
        else if (files.isEmpty)
          const OgLBanner(
            variant: OgLBannerVariant.info,
            text: '没有文件变更。',
          )
        else
          for (final file in files)
            OgLActionRow(
              dense: true,
              leading: Icon(
                ogL.icon(OgLIconName.file),
                size: tokens.iconSize(base: 18),
                color: ogL.palette.textDim,
              ),
              title: GhJson.str(file, 'filename'),
              subtitle: '${GhJson.str(file, 'status')} · '
                  '+${GhJson.integer(file, 'additions')} · '
                  '-${GhJson.integer(file, 'deletions')}',
            ),
      ],
    );
  }
}