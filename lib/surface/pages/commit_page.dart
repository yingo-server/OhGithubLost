/// OGL 页面 · 提交详情（提交信息 + 变更文件清单 + 补丁预览）。
///
/// 数据来源：`compare(parent...sha)`（服务端 diff）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 提交详情页。
class OgLCommitPage extends StatefulWidget {
  /// 创建页面。
  const OgLCommitPage({
    required this.surface,
    required this.fullName,
    required this.commit,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 提交。
  final GhCommit commit;

  @override
  State<OgLCommitPage> createState() => _OgLCommitPageState();
}

class _OgLCommitPageState extends State<OgLCommitPage> {
  OgLAsyncController<List<Map<String, dynamic>>>? _files;
  int _expandedIndex = -1;

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

  OgLAsyncController<List<Map<String, dynamic>>> _filesC() {
    final existing = _files;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<Map<String, dynamic>>>(
      label: '变更',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () async {
        final parents = widget.commit.parentShas;
        if (parents.isEmpty) {
          return const <Map<String, dynamic>>[];
        }
        return widget.surface.domain.api.compare(
          widget.fullName,
          parents.first,
          widget.commit.sha,
        );
      },
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
    final commit = widget.commit;
    final state = _filesC().state;
    final files = state.data ?? const <Map<String, dynamic>>[];

    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        OgLPageHeader(
          title: commit.message.isEmpty
              ? '（无提交信息）'
              : commit.message.split('\n').first,
          description: '${commit.sha.length >= 7 ? commit.sha.substring(0, 7) : commit.sha} · '
              '${commit.authorLogin ?? commit.authorName ?? '未知'}',
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
        if (commit.message.contains('\n'))
          Padding(
            padding: EdgeInsets.only(bottom: tokens.space(OgLSpacing.md)),
            child: SelectableText(
              commit.message,
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
        if (state.failureMessage != null)
          OgLBanner(
            variant: OgLBannerVariant.danger,
            title: 'diff 读取失败',
            text: state.failureMessage!,
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
        else if (state.isFirstLoading)
          const OgLSkeletonText(lines: 4)
        else if (files.isEmpty)
          const OgLBanner(
            variant: OgLBannerVariant.info,
            text: '没有文件变更（或为初始提交）。',
          )
        else
          for (var i = 0; i < files.length; i++)
            _FileDiffCard(
              file: files[i],
              expanded: _expandedIndex == i,
              onToggle: () => setState(() {
                _expandedIndex = _expandedIndex == i ? -1 : i;
              }),
            ),
      ],
    );
  }
}

class _FileDiffCard extends StatelessWidget {
  const _FileDiffCard({
    required this.file,
    required this.expanded,
    required this.onToggle,
  });

  final Map<String, dynamic> file;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final name = GhJson.str(file, 'filename');
    final adds = GhJson.integer(file, 'additions');
    final dels = GhJson.integer(file, 'deletions');
    final patch = file['patch'];
    final patchText = patch is String ? patch : null;

    return Padding(
      padding: EdgeInsets.only(bottom: tokens.space(OgLSpacing.sm)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OgLActionRow(
            dense: true,
            title: name,
            subtitle: '+$adds · -$dels${patchText == null ? ' · （二进制或无补丁）' : ''}',
            leading: OgLIcon(
              name: OgLIconName.file,
              size: tokens.iconSize(base: 18),
              color: ogL.palette.textDim,
            ),
            showChevron: patchText != null,
            onTap: patchText == null ? null : onToggle,
          ),
          if (expanded && patchText != null)
            Container(
              margin: EdgeInsets.only(top: tokens.space(OgLSpacing.xs)),
              padding: EdgeInsets.all(tokens.space(OgLSpacing.sm)),
              decoration: BoxDecoration(
                color: ogL.palette.codeBackground,
                borderRadius:
                    BorderRadius.circular(tokens.radius(OgLRadius.small)),
                border: Border.all(
                  color: ogL.palette.border,
                  width: tokens.hairline,
                ),
              ),
              child: SelectableText(
                patchText.length > 6000
                    ? '${patchText.substring(0, 6000)}\n…（截断显示）'
                    : patchText,
                style: TextStyle(
                  fontFamily: kOgLMonoFamily,
                  fontSize: tokens.fontSize(scale.data),
                  color: ogL.palette.text,
                ),
              ),
            ),
        ],
      ),
    );
  }
}