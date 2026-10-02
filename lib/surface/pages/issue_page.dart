/// OGL 页面 · 议题详情（正文 + 评论 + 关闭 / 重新打开）。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.5）
/// ```
/// OgLPageScaffold(返回键 + '#N 标题' + 'by @login · 打开中/已关闭' + 关闭/重开)
/// ├ 状态行：OgLStateLabel(Open/Closed) + 计数
/// ├ OgLSection('描述')  → OgLBox → Markdown 渲染（复用 README 渲染器）
/// └ OgLSection('评论 N') → OgLBox(padded:false) → 每条评论一块
///    - 空评论 = 空态（不是"加载中"，也不是错误）
///    - 读取失败 = Banner + 重试
/// ```
///
/// ## 纪律
/// - 议题正文与评论都是 **Markdown**：复用 `OgLReadmeView`（离线安全 + 令牌化），
///   不再用等宽裸文本（那是"能看但不像产品"的典型）；
/// - 破坏性操作（关闭）**先确认**；结果给可见反馈（notice / error 都摊开）；
/// - 四态只走 `ogLAsyncView`。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
import '../app/async_view.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../readme/link_opener.dart';
import '../readme/readme_view.dart';
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

  /// 关闭 / 重新打开（同一个动作，两种目标状态）。
  Future<void> _setState(String target) async {
    final bool closing = target == 'closed';
    final bool confirmed = await ogLConfirmDialog(
      context,
      title: closing ? '关闭议题' : '重新打开议题',
      message: closing
          ? '将把 #$_number 标记为已关闭（可在 GitHub 网页端或这里重新打开）。'
          : '将把 #$_number 重新标记为打开。',
      confirmLabel: closing ? '关闭' : '重新打开',
      danger: closing,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.surface.domain.api
          .updateIssue(widget.fullName, _number, state: target);
      OgLAppLog.instance.add('议题', '已${closing ? '关闭' : '重新打开'} #$_number');
      if (mounted) {
        setState(() {
          _stateOverride = target;
          _notice = '已${closing ? '关闭' : '重新打开'} #$_number';
          _error = null;
        });
      }
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '议题',
        '${closing ? '关闭' : '重开'}失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '${closing ? '关闭' : '重新打开'}失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  /// 打开正文/评论里的链接：失败**不许静默**（把 URL 摊开）。
  Future<void> _openLink(Uri url) async {
    final bool ok = await ogLOpenExternal(url, tag: '议题');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开浏览器，链接：$url')),
      );
    }
  }

  String _loginOf(Map<String, dynamic> node) {
    final Object? user = node['user'];
    if (user is Map<Object?, Object?>) {
      return GhJson.str(Map<String, dynamic>.from(user), 'login');
    }
    return '';
  }

  String _dateOf(Map<String, dynamic> node) {
    final String raw = GhJson.str(node, 'created_at');
    if (raw.isEmpty) {
      return '';
    }
    return raw.split('T').first;
  }

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final Map<String, dynamic> issue = widget.issue;
    final String state = _stateOverride ?? GhJson.str(issue, 'state');
    final bool open = state == 'open';
    final String? body = GhJson.strOrNull(issue, 'body');
    final OgLAsyncController<List<Map<String, dynamic>>> controller =
        _commentsC();

    return OgLPageScaffold(
      title: '#$_number ${GhJson.str(issue, 'title')}',
      description: 'by @${_loginOf(issue)}'
          '${_dateOf(issue).isEmpty ? '' : ' · ${_dateOf(issue)}'}',
      leading: OgLIconButton(
        icon: OgLIconName.arrowLeft,
        label: '返回',
        onTap: () => Navigator.of(context).maybePop(),
      ),
      actions: <Widget>[
        if (_busy)
          const OgLSpinner(label: '处理中…')
        else
          OgLButton(
            label: open ? '关闭议题' : '重新打开',
            variant: open ? OgLButtonVariant.danger : OgLButtonVariant.invisible,
            leadingIcon: open ? OgLIconName.issue : OgLIconName.sync,
            onPressed: () async {
              await _setState(open ? 'closed' : 'open');
            },
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (_notice != null) ...<Widget>[
            OgLBanner(
              variant: OgLBannerVariant.success,
              title: _notice!,
              text: open
                  ? '状态已同步到 GitHub。'
                  : '议题已关闭；仍可查看讨论（重开按钮在页头）。',
            ),
            SizedBox(height: tokens.space(OgLSpacing.md)),
          ],
          if (_error != null) ...<Widget>[
            OgLBanner(
              variant: OgLBannerVariant.danger,
              title: '操作失败',
              text: _error!,
            ),
            SizedBox(height: tokens.space(OgLSpacing.md)),
          ],
          Row(
            children: <Widget>[
              OgLStateLabel(
                kind: open ? OgLStateKind.open : OgLStateKind.closed,
                text: open ? 'Open' : 'Closed',
              ),
              SizedBox(width: tokens.space(OgLSpacing.sm)),
              Expanded(
                child: Text(
                  '仓库：${widget.fullName}',
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: tokens.fontSize(
                      const OgLTypeScale.standard().label,
                    ),
                    color: ogL.palette.textDim,
                  ),
                ),
              ),
            ],
          ),
          OgLSection(
            title: '描述',
            description: body == null || body.trim().isEmpty
                ? '这条议题没有写描述'
                : null,
            child: OgLBox(
              child: body == null || body.trim().isEmpty
                  ? const OgLBlankslate(
                      icon: OgLIconName.issue,
                      title: '没有描述',
                      body: '作者只写了标题。讨论都在下面的评论里。',
                      compact: true,
                    )
                  : OgLReadmeView(markdown: body, onOpenLink: _openLink),
            ),
          ),
          OgLSection(
            title: '评论',
            description: '按时间顺序显示；Markdown 已渲染',
            child: ListenableBuilder(
              listenable: controller,
              builder: (BuildContext context, Widget? child) {
                final OgLAsync<List<Map<String, dynamic>>> state =
                    controller.state;
                final List<Map<String, dynamic>> list =
                    state.data ?? const <Map<String, dynamic>>[];
                return ogLAsyncView<List<Map<String, dynamic>>>(
                  state: state,
                  onRetry: () async {
                    await controller.load();
                  },
                  errorTitle: '评论读取失败',
                  emptyIcon: OgLIconName.chat,
                  emptyTitle: '还没有评论',
                  emptyBody: '这条议题暂时没有人参与讨论。',
                  skeletonLines: 4,
                  child: OgLBox(
                    padded: false,
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < list.length; i++)
                          _CommentBlock(
                            comment: list[i],
                            login: _loginOf(list[i]),
                            date: _dateOf(list[i]),
                            showDivider: i != list.length - 1,
                            onOpenLink: _openLink,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox(height: tokens.space(OgLSpacing.lg)),
          Text(
            '提示：在网页端才能新增评论；本页负责查看与状态变更。',
            style: TextStyle(
              fontSize: tokens.fontSize(const OgLTypeScale.standard().label),
              color: ogL.palette.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// 一条评论：头部行（作者 + 日期）+ Markdown 正文。
class _CommentBlock extends StatelessWidget {
  const _CommentBlock({
    required this.comment,
    required this.login,
    required this.date,
    required this.showDivider,
    required this.onOpenLink,
  });

  final Map<String, dynamic> comment;
  final String login;
  final String date;
  final bool showDivider;
  final void Function(Uri url) onOpenLink;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final String body = GhJson.str(comment, 'body');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OgLActionRow(
          leading: OgLIcon(
            name: OgLIconName.chat,
            size: tokens.iconSize(base: 18),
            color: ogL.palette.textDim,
          ),
          title: login.isEmpty ? '（未知用户）' : '@$login',
          subtitle: date.isEmpty ? null : date,
          dense: true,
          showDivider: false,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            tokens.space(OgLSpacing.md),
            0,
            tokens.space(OgLSpacing.md),
            tokens.space(OgLSpacing.md),
          ),
          child: body.trim().isEmpty
              ? Text(
                  '（空评论）',
                  style: TextStyle(
                    fontSize:
                        tokens.fontSize(const OgLTypeScale.standard().body),
                    color: ogL.palette.textDim,
                  ),
                )
              : OgLReadmeView(markdown: body, onOpenLink: onOpenLink),
        ),
        if (showDivider)
          Divider(
            height: tokens.hairline,
            thickness: tokens.hairline,
            color: ogL.palette.border,
          ),
      ],
    );
  }
}