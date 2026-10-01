/// OGL 页面 · 议题详情（正文 + 评论 + 关闭）。
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

/// 议题详情页。
class OgLIssuePage extends StatefulWidget {
  /// 创建页面。
  const OgLIssuePage({
    required this.surface,
    required this.fullName,
    required this.issue,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 议题原始数据（来自列表，含正文）。
  final Map<String, dynamic> issue;

  @override
  State<OgLIssuePage> createState() => _OgLIssuePageState();
}

class _OgLIssuePageState extends State<OgLIssuePage> {
  OgLAsyncController<List<Map<String, dynamic>>>? _comments;
  bool _busy = false;
  String? _error;
  String? _notice;
  String? _stateOverride;

  @override
  void initState() {
    super.initState();
    _commentsC().loadIfNeeded();
  }

  @override
  void dispose() {
    _comments?.removeListener(_onChanged);
    _comments?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  int get _number => GhJson.integer(widget.issue, 'number');

  OgLAsyncController<List<Map<String, dynamic>>> _commentsC() {
    final existing = _comments;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<Map<String, dynamic>>>(
      label: '评论',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api
          .issueComments(widget.fullName, _number),
    );
    controller.addListener(_onChanged);
    _comments = controller;
    return controller;
  }

  Future<void> _close() async {
    final confirmed = await ogLConfirmDialog(
      context,
      title: '关闭议题',
      message: '将把 #$_number 标记为已关闭（可在 GitHub 网页端重新打开）。',
      confirmLabel: '关闭',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api
          .updateIssue(widget.fullName, _number, state: 'closed');
      OgLAppLog.instance.add('议题', '已关闭 #$_number');
      if (mounted) {
        setState(() {
          _stateOverride = 'closed';
          _notice = '已关闭 #$_number';
        });
      }
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '议题',
        '关闭失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '关闭失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final issue = widget.issue;
    final state = _stateOverride ?? GhJson.str(issue, 'state');
    final body = GhJson.strOrNull(issue, 'body');
    final user = issue['user'];
    final login = user is Map<Object?, Object?>
        ? GhJson.str(Map<String, dynamic>.from(user), 'login')
        : '';
    final commentState = _commentsC().state;
    final comments = commentState.data ?? const <Map<String, dynamic>>[];

    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        OgLPageHeader(
          title: '#$_number ${GhJson.str(issue, 'title')}',
          description: 'by $login · ${state == 'open' ? '打开中' : '已关闭'}',
          actions: <Widget>[
            if (state == 'open')
              OgLButton(
                label: '关闭议题',
                variant: OgLButtonVariant.danger,
                leadingIcon: OgLIconName.issue,
                onPressed: _busy ? null : _close,
              ),
          ],
        ),
        if (_notice != null) ...<Widget>[
          OgLBanner(variant: OgLBannerVariant.success, text: _notice!),
          SizedBox(height: tokens.space(OgLSpacing.md)),
        ],
        if (_error != null) ...<Widget>[
          OgLBanner(variant: OgLBannerVariant.danger, text: _error!),
          SizedBox(height: tokens.space(OgLSpacing.md)),
        ],
        OgLStateLabel(
          kind: state == 'open' ? OgLStateKind.open : OgLStateKind.closed,
          text: state == 'open' ? 'Open' : 'Closed',
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        if (body != null && body.isNotEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(tokens.space(OgLSpacing.md)),
            decoration: BoxDecoration(
              color: ogL.palette.codeBackground,
              borderRadius:
                  BorderRadius.circular(tokens.radius(OgLRadius.medium)),
              border: Border.all(
                color: ogL.palette.border,
                width: tokens.hairline,
              ),
            ),
            child: SelectableText(
              body,
              style: TextStyle(
                fontFamily: kOgLMonoFamily,
                fontSize: tokens.fontSize(scale.data),
                color: ogL.palette.text,
              ),
            ),
          ),
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        Text(
          '评论（${comments.length}）',
          style: TextStyle(
            fontSize: tokens.fontSize(scale.title),
            fontWeight: FontWeight.w600,
            color: ogL.palette.text,
          ),
        ),
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        if (commentState.data == null && commentState.message != null)
          OgLBanner(
            variant: OgLBannerVariant.danger,
            title: '评论读取失败',
            text: commentState.message!,
            actions: <Widget>[
              OgLButton(
                label: '重试',
                size: OgLButtonSize.small,
                onPressed: () async {
                  await _commentsC().load();
                },
              ),
            ],
          )
        else if (commentState.data == null)
          const OgLSkeletonText(lines: 3)
        else if (comments.isEmpty)
          const OgLBanner(
            variant: OgLBannerVariant.info,
            text: '还没有评论。',
          )
        else
          for (final comment in comments)
            Padding(
              padding: EdgeInsets.only(bottom: tokens.space(OgLSpacing.sm)),
              child: _CommentCard(comment: comment),
            ),
      ],
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.comment});

  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final user = comment['user'];
    final login = user is Map<Object?, Object?>
        ? GhJson.str(Map<String, dynamic>.from(user), 'login')
        : '';
    final created = GhJson.str(comment, 'created_at');
    final body = GhJson.str(comment, 'body');
    return Container(
      padding: EdgeInsets.all(tokens.space(OgLSpacing.md)),
      decoration: BoxDecoration(
        color: ogL.palette.surfaceAlt,
        borderRadius: BorderRadius.circular(tokens.radius(OgLRadius.medium)),
        border: Border.all(color: ogL.palette.border, width: tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$login · ${created.split('T').first}',
            style: TextStyle(
              fontSize: tokens.fontSize(scale.label),
              color: ogL.palette.textFaint,
            ),
          ),
          SizedBox(height: tokens.space(OgLSpacing.xs)),
          SelectableText(
            body,
            style: TextStyle(
              fontSize: tokens.fontSize(scale.body),
              color: ogL.palette.text,
            ),
          ),
        ],
      ),
    );
  }
}