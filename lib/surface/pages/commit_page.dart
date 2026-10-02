/// OGL 页面 · 提交详情（提交信息 + 变更文件清单 + **分色**补丁预览）。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.7）
/// ```
/// OgLPageScaffold(返回键 + 首行提交信息 + 'sha · 作者')
/// ├ OgLSection('提交信息') → OgLBox → 完整信息（多行时才有）
/// └ OgLSection('变更文件 N') → OgLBox(padded:false) → 每文件一行
///    └ 展开 = 补丁预览（逐行分色：+ 绿 / - 红 / @@ 灰 / 其它常规）
/// ```
///
/// ## 纪律
/// - 补丁是**代码**：等宽 + 逐行分色（旧实现是一整块无差别文本，看不出增删）；
/// - 超长补丁按行截断并**明确告知**（不静默丢内容，也不让一屏塞十万行）；
/// - 四态只走 `ogLAsyncView`；初始提交（无父）→ 空态说明原因。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
import '../app/async_view.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 补丁最多渲染的行数（超出的行会被折叠并提示）。
const int _kMaxPatchLines = 400;

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

  String _statusText(String status) {
    switch (status) {
      case 'added':
        return '新增';
      case 'removed':
        return '删除';
      case 'modified':
        return '修改';
      case 'renamed':
        return '重命名';
      default:
        return status.isEmpty ? '变更' : status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final GhCommit commit = widget.commit;
    final String shortSha = commit.sha.length >= 7
        ? commit.sha.substring(0, 7)
        : commit.sha;
    final OgLAsyncController<List<Map<String, dynamic>>> controller = _filesC();
    final List<String> messageLines = commit.message.split('\n');

    return OgLPageScaffold(
      title: messageLines.isEmpty || messageLines.first.isEmpty
          ? '（无提交信息）'
          : messageLines.first,
      description: '$shortSha · @${commit.authorLogin ?? commit.authorName ?? '未知'}',
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
          label: '刷新 diff',
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
                  if (messageLines.length > 1)
                    const OgLLabel(
                      text: '多行提交信息',
                      variant: OgLLabelVariant.neutral,
                    ),
                  if (messageLines.length > 1)
                    SizedBox(width: tokens.space(OgLSpacing.xs)),
                  OgLLabel(
                    text: '${files.length} 个文件',
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
              if (messageLines.length > 1)
                OgLSection(
                  title: '提交信息',
                  child: OgLBox(
                    child: SelectableText(
                      commit.message,
                      style: TextStyle(
                        fontFamily: kOgLMonoFamily,
                        fontSize: tokens.fontSize(scale.data),
                        color: ogL.palette.text,
                      ),
                    ),
                  ),
                ),
              OgLSection(
                title: '变更文件',
                description: '点一行展开补丁（+ 绿 / − 红；超长自动截断）',
                child: ogLAsyncView<List<Map<String, dynamic>>>(
                  state: state,
                  onRetry: () async {
                    await controller.load();
                  },
                  errorTitle: 'diff 读取失败',
                  emptyIcon: OgLIconName.commit,
                  emptyTitle: '没有可比对的变更',
                  emptyBody: '初始提交（没有父提交）无法生成 diff；'
                      '或该提交只动了二进制文件。',
                  skeletonLines: 4,
                  child: OgLBox(
                    padded: false,
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < files.length; i++)
                          _FileDiffBlock(
                            file: files[i],
                            statusText: _statusText(
                              GhJson.str(files[i], 'status'),
                            ),
                            expanded: _expandedIndex == i,
                            showDivider: i != files.length - 1,
                            onToggle: () => setState(() {
                              _expandedIndex = _expandedIndex == i ? -1 : i;
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 一个文件：一行摘要 +（可展开的）分色补丁。
class _FileDiffBlock extends StatelessWidget {
  const _FileDiffBlock({
    required this.file,
    required this.statusText,
    required this.expanded,
    required this.showDivider,
    required this.onToggle,
  });

  final Map<String, dynamic> file;
  final String statusText;
  final bool expanded;
  final bool showDivider;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final String name = GhJson.str(file, 'filename');
    final int adds = GhJson.integer(file, 'additions');
    final int dels = GhJson.integer(file, 'deletions');
    final Object? patch = file['patch'];
    final String? patchText = patch is String ? patch : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OgLActionRow(
          leading: OgLIcon(
            name: OgLIconName.file,
            size: tokens.iconSize(base: 18),
            color: ogL.palette.textDim,
          ),
          title: name,
          subtitle: patchText == null
              ? '$statusText · （二进制或无补丁）'
              : '$statusText · 点开看补丁',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OgLLabel(
                text: '+$adds',
                variant: OgLLabelVariant.success,
              ),
              SizedBox(width: tokens.space(OgLSpacing.xxs)),
              OgLLabel(
                text: '-$dels',
                variant: OgLLabelVariant.danger,
              ),
            ],
          ),
          showChevron: patchText != null,
          showDivider: showDivider && !expanded,
          dense: true,
          onTap: patchText == null ? null : onToggle,
        ),
        if (expanded && patchText != null)
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.space(OgLSpacing.md),
              0,
              tokens.space(OgLSpacing.md),
              tokens.space(OgLSpacing.md),
            ),
            child: _PatchView(patch: patchText),
          ),
      ],
    );
  }
}

/// 补丁预览：逐行分色（+ 绿 / − 红 / @@ 灰），超长按行截断并提示。
class _PatchView extends StatelessWidget {
  const _PatchView({required this.patch});

  final String patch;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final List<String> lines = patch.split('\n');
    final bool truncated = lines.length > _kMaxPatchLines;
    final List<String> shown =
        truncated ? lines.sublist(0, _kMaxPatchLines) : lines;
    final TextStyle base = TextStyle(
      fontFamily: kOgLMonoFamily,
      fontSize: tokens.fontSize(scale.data),
      height: 1.35,
      color: ogL.palette.text,
    );

    return Container(
      padding: EdgeInsets.all(tokens.space(OgLSpacing.sm)),
      decoration: BoxDecoration(
        color: ogL.palette.codeBackground,
        borderRadius: BorderRadius.circular(tokens.radius(OgLRadius.small)),
        border: Border.all(color: ogL.palette.border, width: tokens.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SelectableText.rich(
            TextSpan(
              children: <TextSpan>[
                for (final String line in shown)
                  TextSpan(
                    text: '$line\n',
                    style: base.copyWith(
                      color: line.startsWith('+')
                          ? ogL.palette.success
                          : line.startsWith('-')
                              ? ogL.palette.danger
                              : line.startsWith('@@')
                                  ? ogL.palette.textFaint
                                  : ogL.palette.text,
                    ),
                  ),
              ],
            ),
          ),
          if (truncated) ...<Widget>[
            SizedBox(height: tokens.space(OgLSpacing.xs)),
            Text(
              '补丁过长，只显示前 $_kMaxPatchLines 行（共 ${lines.length} 行）。',
              style: TextStyle(
                fontSize: tokens.fontSize(scale.label),
                color: ogL.palette.textDim,
              ),
            ),
          ],
        ],
      ),
    );
  }
}