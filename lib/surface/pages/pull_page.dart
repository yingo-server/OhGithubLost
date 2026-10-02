/// OGL 页面 · PR 详情（描述 + 变更文件清单 + 增删统计）。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.6）
/// ```
/// OgLPageScaffold(返回键 + '#N 标题' + 'by @login · 打开/已合并/已关闭' + 刷新)
/// ├ 状态行：OgLStateLabel(Merged/Open/Closed) + 变更统计（+N / -N）
/// ├ OgLSection('描述')  → OgLBox → Markdown 渲染（复用 README 渲染器）
/// └ OgLSection('变更文件 N') → OgLBox(padded:false) → 每文件一行（状态 + 增删）
/// ```
///
/// ## 纪律
/// 四态只走 `ogLAsyncView`（**没有文件变更也是空态**，不是加载中）；
/// 描述是 Markdown，不再用裸 SelectableText；PR 状态用语义标签而不是字符串。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
import '../app/async_view.dart';
import '../kit/kit.dart';
import '../readme/link_opener.dart';
import '../readme/readme_view.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import '../util/gh_view_format.dart';

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

  Future<void> _openLink(Uri url) async {
    final bool ok = await ogLOpenExternal(url, tag: 'PR');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开浏览器，链接：$url')),
      );
    }
  }

  /// 来源分支名（`head` 在 GitHub 的响应里是对象，不是字符串）。
  String _headRef(Map<String, dynamic> pull) {
    final Object? head = pull['head'];
    if (head is Map<Object?, Object?>) {
      return GhJson.str(Map<String, dynamic>.from(head), 'ref');
    }
    return GhJson.str(pull, 'head');
  }

  /// PR 状态 → 语义标签（打开 / 已合并 / 草稿 / 已关闭）。
  OgLLabel _stateLabel(Map<String, dynamic> pull) {
    final String state = GhJson.str(pull, 'state');
    final bool merged = GhJson.boolean(pull, 'merged');
    final bool draft = GhJson.boolean(pull, 'draft');
    if (merged) {
      return const OgLLabel(text: '已合并', variant: OgLLabelVariant.success);
    }
    if (draft) {
      return const OgLLabel(text: '草稿', variant: OgLLabelVariant.neutral);
    }
    if (state == 'closed') {
      return const OgLLabel(text: '已关闭', variant: OgLLabelVariant.danger);
    }
    return const OgLLabel(text: '打开中', variant: OgLLabelVariant.accent);
  }

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final Map<String, dynamic> pull = widget.pull;
    final String? body = GhJson.strOrNull(pull, 'body');
    final OgLAsyncController<List<Map<String, dynamic>>> controller = _filesC();

    return OgLPageScaffold(
      title: '#$_number ${GhJson.str(pull, 'title')}',
      description: <String>[
        'by @${ogLNodeLogin(pull)}',
        if (_headRef(pull).isNotEmpty) '分支 ${_headRef(pull)}',
      ].join(' · '),
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
          final List<Map<String, dynamic>> files =
              state.data ?? const <Map<String, dynamic>>[];
          int additions = 0;
          int deletions = 0;
          for (final Map<String, dynamic> file in files) {
            additions += GhJson.integer(file, 'additions');
            deletions += GhJson.integer(file, 'deletions');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  _stateLabel(pull),
                  SizedBox(width: tokens.space(OgLSpacing.xs)),
                  OgLLabel(
                    text: '变更 ${files.isEmpty ? '—' : files.length} 个文件',
                    variant: OgLLabelVariant.neutral,
                  ),
                  SizedBox(width: tokens.space(OgLSpacing.xs)),
                  OgLLabel(
                    text: '+$additions',
                    variant: OgLLabelVariant.success,
                  ),
                  SizedBox(width: tokens.space(OgLSpacing.xs)),
                  OgLLabel(
                    text: '-$deletions',
                    variant: OgLLabelVariant.danger,
                  ),
                ],
              ),
              OgLSection(
                title: '描述',
                description: body == null || body.trim().isEmpty
                    ? '这个 PR 没有写描述'
                    : null,
                child: OgLBox(
                  child: body == null || body.trim().isEmpty
                      ? const OgLBlankslate(
                          icon: OgLIconName.pullRequest,
                          title: '没有描述',
                          body: '作者只写了标题；文件改动见下方清单。',
                          compact: true,
                        )
                      : OgLReadmeView(markdown: body, onOpenLink: _openLink),
                ),
              ),
              OgLSection(
                title: '变更文件',
                description: '点行查看该文件的差异（在仓库页的文件视图里）',
                child: ogLAsyncView<List<Map<String, dynamic>>>(
                  state: state,
                  onRetry: () async {
                    await controller.load();
                  },
                  errorTitle: '变更文件读取失败',
                  emptyIcon: OgLIconName.compare,
                  emptyTitle: '没有文件变更',
                  emptyBody: '这个 PR 目前不含任何文件改动（可能只是讨论）。',
                  skeletonLines: 4,
                  child: OgLBox(
                    padded: false,
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < files.length; i++)
                          OgLActionRow(
                            leading: OgLIcon(
                              name: OgLIconName.file,
                              size: tokens.iconSize(base: 18),
                              color: ogL.palette.textDim,
                            ),
                            title: GhJson.str(files[i], 'filename'),
                            subtitle: ogLFileStatusText(
                              GhJson.str(files[i], 'status'),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                OgLLabel(
                                  text: '+${GhJson.integer(files[i], 'additions')}',
                                  variant: OgLLabelVariant.success,
                                ),
                                SizedBox(width: tokens.space(OgLSpacing.xxs)),
                                OgLLabel(
                                  text: '-${GhJson.integer(files[i], 'deletions')}',
                                  variant: OgLLabelVariant.danger,
                                ),
                              ],
                            ),
                            dense: true,
                            showDivider: i != files.length - 1,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: tokens.space(OgLSpacing.md)),
              Text(
                '提示：合并 / 关闭 PR 请在 GitHub 网页端完成；本页负责查看。',
                style: TextStyle(
                  fontSize: tokens.fontSize(scale.label),
                  color: ogL.palette.textFaint,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}