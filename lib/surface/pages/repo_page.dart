/// OGL 页面 · 仓库详情（v1：代码浏览 → 文件查看 → 编辑提交 → 删除）。
///
/// 写入路径遵守底座纪律：**带基线 sha 的乐观锁**（`baseSha`），
/// 冲突（409/422）走"远端已变化，请重开文件"的人话提示，绝不静默覆盖。
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

/// 仓库详情页。
class OgLRepoPage extends StatefulWidget {
  /// 创建页面。
  const OgLRepoPage({required this.surface, required this.repo, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库（来自列表的既有数据）。
  final GhRepo repo;

  @override
  State<OgLRepoPage> createState() => _OgLRepoPageState();
}

class _OgLRepoPageState extends State<OgLRepoPage> {
  // 头部状态
  bool? _starred;
  bool _busy = false;
  String? _error;
  String? _notice;

  // 浏览状态
  String _path = '';
  OgLAsyncController<List<GhContent>>? _entries;

  // 文件状态
  GhContent? _file;
  String? _fileText;
  bool _fileLoading = false;
  String? _fileError;
  bool _editing = false;
  final TextEditingController _editController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final raw = widget.repo.raw['viewer_has_starred'];
    _starred = raw is bool ? raw : null;
    _messageController.text = 'chore: update ${widget.repo.fullName}';
    _entriesC().loadIfNeeded();
  }

  @override
  void dispose() {
    _entries?.removeListener(_onChanged);
    _entries?.dispose();
    _editController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  OgLAsyncController<List<GhContent>> _entriesC() {
    final existing = _entries;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhContent>>(
      label: '目录',
      isEmpty: (List<GhContent> value) => value.isEmpty,
      loader: () async {
        final list = await widget.surface.domain.api.listDirectory(
          widget.repo.fullName,
          _path,
          branch: widget.repo.defaultBranch,
        );
        final dirs = list.where((GhContent c) => c.isDirectory).toList()
          ..sort((GhContent a, GhContent b) => a.path.compareTo(b.path));
        final files = list.where((GhContent c) => !c.isDirectory).toList()
          ..sort((GhContent a, GhContent b) => a.path.compareTo(b.path));
        return <GhContent>[...dirs, ...files];
      },
    );
    controller.addListener(_onChanged);
    _entries = controller;
    return controller;
  }

  Future<void> _toggleStar() async {
    final target = !(_starred ?? false);
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.surface.domain.api.setStarred(widget.repo.fullName, target);
      OgLAppLog.instance.add('仓库', target ? '已加星标' : '已取消星标');
      if (!mounted) {
        return;
      }
      setState(() {
        _starred = target;
        _notice = target ? '已加入星标' : '已取消星标';
      });
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '仓库',
        '星标失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '星标失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _fork() async {
    final confirmed = await ogLConfirmDialog(
      context,
      title: '复刻仓库',
      message: '将在你的账户下创建「${widget.repo.fullName}」的副本。',
      confirmLabel: '复刻',
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final forked = await widget.surface.domain.api.fork(widget.repo.fullName);
      OgLAppLog.instance.add('仓库', '已复刻为 ${forked.fullName}');
      if (mounted) {
        setState(() => _notice = '已复刻为 ${forked.fullName}');
      }
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '仓库',
        '复刻失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '复刻失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  void _goTo(String path) {
    setState(() {
      _path = path;
      _file = null;
      _fileText = null;
      _editing = false;
    });
    _entriesC().load();
  }

  Future<void> _openFile(GhContent entry) async {
    setState(() {
      _fileLoading = true;
      _fileError = null;
      _file = null;
      _fileText = null;
      _editing = false;
    });
    try {
      final file = await widget.surface.domain.api.content(
        widget.repo.fullName,
        entry.path,
        branch: widget.repo.defaultBranch,
      );
      if (file == null) {
        throw Exception('读不到内容（可能是二进制文件或权限不足）');
      }
      var text = file.text;
      if (text == null && file.isTooLarge) {
        text = await widget.surface.domain.api
            .blobText(widget.repo.fullName, file.sha);
      }
      if (!mounted) {
        return;
      }
      _editController.text = text ?? '';
      setState(() {
        _file = file;
        _fileText = text;
      });
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '文件',
        '打开失败：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _fileError = '打开失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _fileLoading = false);
      } else {
        _fileLoading = false;
      }
    }
  }

  Future<void> _saveFile() async {
    final file = _file;
    if (file == null) {
      return;
    }
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      setState(() => _fileError = '提交信息不能为空');
      return;
    }
    setState(() {
      _fileLoading = true;
      _fileError = null;
      _notice = null;
    });
    try {
      await widget.surface.domain.api.putContent(
        widget.repo.fullName,
        file.path,
        content: _editController.text,
        message: message,
        baseSha: file.sha,
        branch: widget.repo.defaultBranch,
      );
      OgLAppLog.instance.add('文件', '已提交：${file.path}');
      if (mounted) {
        setState(() {
          _editing = false;
          _notice = '已提交：${file.path}';
        });
      }
      await _openFile(file);
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '文件',
        '提交失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() {
          _fileError = '提交失败：$error（若为冲突：远端已更新，请重开文件再编辑）';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _fileLoading = false);
      } else {
        _fileLoading = false;
      }
    }
  }

  Future<void> _deleteFile() async {
    final file = _file;
    if (file == null) {
      return;
    }
    final confirmed = await ogLConfirmDialog(
      context,
      title: '删除文件',
      message: '将删除「${file.path}」并立即提交。该操作会进入仓库历史，但不可直接撤销。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _fileLoading = true;
      _fileError = null;
    });
    try {
      await widget.surface.domain.api.deleteContent(
        widget.repo.fullName,
        file.path,
        message: 'chore: delete ${file.path}',
        baseSha: file.sha,
        branch: widget.repo.defaultBranch,
      );
      OgLAppLog.instance.add('文件', '已删除：${file.path}');
      if (mounted) {
        setState(() {
          _file = null;
          _fileText = null;
          _editing = false;
          _notice = '已删除：${file.path}';
        });
      }
      _entriesC().load();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '文件',
        '删除失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _fileError = '删除失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _fileLoading = false);
      } else {
        _fileLoading = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final repo = widget.repo;
    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        OgLPageHeader(
          title: repo.fullName,
          description: repo.description ?? '（无描述）',
          actions: <Widget>[
            OgLButton(
              label: _starred == true ? '已星标' : '星标',
              variant: _starred == true
                  ? OgLButtonVariant.standard
                  : OgLButtonVariant.primary,
              leadingIcon: OgLIconName.star,
              onPressed: _busy ? null : _toggleStar,
            ),
            OgLButton(
              label: '复刻',
              leadingIcon: OgLIconName.fork,
              onPressed: _busy ? null : _fork,
            ),
          ],
        ),
        Wrap(
          spacing: tokens.space(OgLSpacing.sm),
          runSpacing: tokens.space(OgLSpacing.sm),
          children: <Widget>[
            OgLLabel(
              text: repo.isPrivate ? '私有' : '公开',
              variant: repo.isPrivate
                  ? OgLLabelVariant.attention
                  : OgLLabelVariant.success,
            ),
            if (repo.language != null)
              OgLLabel(text: repo.language!, variant: OgLLabelVariant.accent),
            OgLLabel(text: '★ ${repo.stars}', variant: OgLLabelVariant.neutral),
            OgLLabel(
              text: 'Fork ${repo.forks}',
              variant: OgLLabelVariant.neutral,
            ),
            OgLLabel(
              text: 'Issue ${repo.openIssues}',
              variant: OgLLabelVariant.neutral,
            ),
            OgLLabel(text: repo.defaultBranch, variant: OgLLabelVariant.done),
          ],
        ),
        if (_notice != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.md)),
          OgLBanner(variant: OgLBannerVariant.success, text: _notice!),
        ],
        if (_error != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.md)),
          OgLBanner(variant: OgLBannerVariant.danger, text: _error!),
        ],
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        Divider(color: ogL.palette.border, height: tokens.hairline),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        if (_fileLoading && _file == null)
          const Center(child: OgLSpinner(label: '读取中…'))
        else if (_file != null)
          _buildFileView(ogL, tokens)
        else
          _buildBrowser(ogL, tokens),
      ],
    );
  }

  Widget _buildBrowser(OgLTheme ogL, OgLTokens tokens) {
    final state = _entriesC().state;
    final list = state.data ?? const <GhContent>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '/${_path.isEmpty ? widget.repo.name : _path}',
                style: TextStyle(
                  fontFamily: kOgLMonoFamily,
                  fontSize:
                      tokens.fontSize(const OgLTypeScale.standard().data),
                  color: ogL.palette.textDim,
                ),
              ),
            ),
            if (_path.isNotEmpty)
              OgLButton(
                label: '返回上级',
                variant: OgLButtonVariant.invisible,
                size: OgLButtonSize.small,
                onPressed: () {
                  final parts = _path.split('/')..removeLast();
                  _goTo(parts.join('/'));
                },
              ),
            OgLButton(
              label: '刷新',
              variant: OgLButtonVariant.invisible,
              size: OgLButtonSize.small,
              leadingIcon: OgLIconName.sync,
              onPressed: () {
                _entriesC().load();
              },
            ),
          ],
        ),
        if (state.data == null && state.message != null)
          OgLBanner(
            variant: OgLBannerVariant.danger,
            title: '目录读取失败',
            text: state.message!,
            actions: <Widget>[
              OgLButton(
                label: '重试',
                size: OgLButtonSize.small,
                onPressed: () async {
                  await _entriesC().load();
                },
              ),
            ],
          )
        else if (state.data == null)
          const OgLSkeletonText(lines: 6)
        else if (list.isEmpty)
          const OgLBanner(
            variant: OgLBannerVariant.info,
            text: '这个目录是空的。',
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final entry in list)
                OgLActionRow(
                  title: entry.path.split('/').last,
                  subtitle: entry.isDirectory ? '目录' : _sizeText(entry.size),
                  leading: Icon(
                    ogL.icon(
                      entry.isDirectory
                          ? OgLIconName.folder
                          : OgLIconName.file,
                    ),
                    size: tokens.iconSize(base: 20),
                    color: entry.isDirectory
                        ? ogL.palette.accent
                        : ogL.palette.textDim,
                  ),
                  showChevron: entry.isDirectory,
                  onTap: () {
                    if (entry.isDirectory) {
                      _goTo(entry.path);
                    } else {
                      _openFile(entry);
                    }
                  },
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildFileView(OgLTheme ogL, OgLTokens tokens) {
    final file = _file;
    if (file == null) {
      return const SizedBox.shrink();
    }
    final scale = const OgLTypeScale.standard();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                file.path,
                style: TextStyle(
                  fontFamily: kOgLMonoFamily,
                  fontSize: tokens.fontSize(scale.data),
                  color: ogL.palette.text,
                ),
              ),
            ),
            OgLButton(
              label: '返回',
              variant: OgLButtonVariant.invisible,
              size: OgLButtonSize.small,
              onPressed: () {
                setState(() {
                  _file = null;
                  _fileText = null;
                  _editing = false;
                  _fileError = null;
                });
              },
            ),
          ],
        ),
        SizedBox(height: tokens.space(OgLSpacing.xs)),
        Text(
          '大小 ${_sizeText(file.size)} · sha ${file.sha.length >= 7 ? file.sha.substring(0, 7) : file.sha}',
          style: TextStyle(
            fontSize: tokens.fontSize(scale.label),
            color: ogL.palette.textFaint,
          ),
        ),
        if (_fileError != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.sm)),
          OgLBanner(variant: OgLBannerVariant.danger, text: _fileError!),
        ],
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        Wrap(
          spacing: tokens.space(OgLSpacing.sm),
          runSpacing: tokens.space(OgLSpacing.sm),
          children: <Widget>[
            OgLButton(
              label: _editing ? '取消编辑' : '编辑',
              variant: _editing
                  ? OgLButtonVariant.standard
                  : OgLButtonVariant.primary,
              leadingIcon: OgLIconName.edit,
              onPressed: () {
                setState(() {
                  _editing = !_editing;
                  _fileError = null;
                });
              },
            ),
            OgLButton(
              label: '删除',
              variant: OgLButtonVariant.danger,
              leadingIcon: OgLIconName.delete,
              onPressed: _fileLoading ? null : _deleteFile,
            ),
          ],
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        if (_editing) ...<Widget>[
          OgLTextField(
            controller: _editController,
            label: '内容（${file.path}）',
            maxLines: 16,
          ),
          SizedBox(height: tokens.space(OgLSpacing.md)),
          OgLTextField(
            controller: _messageController,
            label: '提交信息',
            leadingIcon: OgLIconName.commit,
          ),
          SizedBox(height: tokens.space(OgLSpacing.md)),
          OgLButton(
            label: _fileLoading ? '提交中…' : '提交（带基线 sha）',
            variant: OgLButtonVariant.primary,
            leadingIcon: OgLIconName.upload,
            loading: _fileLoading,
            onPressed: _saveFile,
          ),
        ] else
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
              _fileText ?? '（该文件无法以文本显示：二进制或体积受限）',
              style: TextStyle(
                fontFamily: kOgLMonoFamily,
                fontSize: tokens.fontSize(scale.data),
                color: ogL.palette.text,
              ),
            ),
          ),
      ],
    );
  }
}

String _sizeText(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}