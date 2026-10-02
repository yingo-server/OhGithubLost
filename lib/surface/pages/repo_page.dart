/// OGL 页面 · 仓库详情（v1：代码浏览 → 文件查看 → 编辑提交 → 删除）。
///
/// 写入路径遵守底座纪律：**带基线 sha 的乐观锁**（`baseSha`），
/// 冲突（409/422）走"远端已变化，请重开文件"的人话提示，绝不静默覆盖。
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
import '../app/async_view.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../readme/readme_view.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'commit_page.dart';
import 'issue_page.dart';
import 'new_issue_page.dart';
import 'new_release_page.dart';
import 'pull_page.dart';

/// 仓库页内的标签。
enum _RepoTab {
  /// 代码（文件浏览）。
  code,

  /// 议题。
  issues,

  /// 拉取请求。
  pulls,

  /// 发布。
  releases,

  /// 分支。
  branches,

  /// 提交历史。
  commits,

  /// 工作流运行。
  actions,

  /// 设置与危险区。
  settings,
}

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
  OgLAsyncController<String?>? _readme;

  // 标签页
  _RepoTab _tab = _RepoTab.code;
  bool _releaseBusy = false;

  // 设置标签状态
  late final TextEditingController _nameCtl;
  late final TextEditingController _descCtl;
  final TextEditingController _cnameCtl = TextEditingController();
  bool _privateVal = false;
  bool _settingsBusy = false;
  OgLAsyncController<Map<String, dynamic>>? _pages;
  String? _cnameSha;
  OgLAsyncController<List<Map<String, dynamic>>>? _issues;
  OgLAsyncController<List<Map<String, dynamic>>>? _pulls;
  OgLAsyncController<List<GhRelease>>? _releases;
  OgLAsyncController<List<GhBranch>>? _branches;
  OgLAsyncController<List<GhCommit>>? _commits;
  OgLAsyncController<List<Map<String, dynamic>>>? _acts;

  // 文件状态
  GhContent? _file;
  String? _fileText;
  bool _fileLoading = false;
  String? _fileError;
  bool _editing = false;
  final TextEditingController _editController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  /// 当前仓库全名（仓库改名后继续沿用，避免"改名即失联"）。
  String? _fullName;

  /// 仓库信息（列表数据可能不全：缺 `default_branch` 等）。
  late GhRepo _repo;

  /// 最近一次尝试打开的文件（失败后一键重试用）。
  GhContent? _pendingFile;

  /// 当前仓库全名（改名后仍指向同一个仓库）。
  String get _full => _fullName ?? _repo.fullName;

  @override
  void initState() {
    super.initState();
    _repo = widget.repo;
    final raw = _repo.raw['viewer_has_starred'];
    _starred = raw is bool ? raw : null;
    _messageController.text = 'chore: update $_full';
    _nameCtl = TextEditingController(text: _repo.name);
    _descCtl = TextEditingController(text: _repo.description ?? '');
    _privateVal = _repo.isPrivate;
    _entriesC().loadIfNeeded();
    _readmeC().loadIfNeeded();
    // 列表里的仓库对象可能缺 `default_branch`（猜 main 会让 master 仓库全 404），
    // 因此用一次详情请求把事实补齐；失败不影响浏览（只写日志）。
    _refreshRepo();
  }

  @override
  void dispose() {
    _entries?.removeListener(_onChanged);
    _entries?.dispose();
    _readme?.removeListener(_onChanged);
    _readme?.dispose();
    _issues?.removeListener(_onChanged);
    _issues?.dispose();
    _pulls?.removeListener(_onChanged);
    _pulls?.dispose();
    _releases?.removeListener(_onChanged);
    _releases?.dispose();
    _branches?.removeListener(_onChanged);
    _branches?.dispose();
    _commits?.removeListener(_onChanged);
    _commits?.dispose();
    _acts?.removeListener(_onChanged);
    _acts?.dispose();
    _pages?.removeListener(_onChanged);
    _pages?.dispose();
    _nameCtl.dispose();
    _descCtl.dispose();
    _cnameCtl.dispose();
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
          _full,
          _path,
          branch: _repo.defaultBranch,
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

  /// README 控制器（`null` = 仓库没有 README，属于**空态**不是错误）。
  OgLAsyncController<String?> _readmeC() {
    final existing = _readme;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<String?>(
      label: 'README',
      isEmpty: (String? value) => value == null || value.trim().isEmpty,
      loader: () async {
        OgLAppLog.instance.add('仓库', '拉取 README（$_full）…');
        final text = await widget.surface.domain.api.readme(_full);
        OgLAppLog.instance
            .add('仓库', 'README：${text == null ? '无' : '${text.length} 字符'}');
        return text;
      },
    );
    controller.addListener(_onChanged);
    _readme = controller;
    return controller;
  }

  OgLAsyncController<List<Map<String, dynamic>>> _issuesC() {
    final existing = _issues;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<Map<String, dynamic>>>(
      label: '议题',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.issues(_full),
    );
    controller.addListener(_onChanged);
    _issues = controller;
    return controller;
  }

  OgLAsyncController<List<Map<String, dynamic>>> _pullsC() {
    final existing = _pulls;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<Map<String, dynamic>>>(
      label: 'PR',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.pulls(_full),
    );
    controller.addListener(_onChanged);
    _pulls = controller;
    return controller;
  }

  OgLAsyncController<List<GhRelease>> _releasesC() {
    final existing = _releases;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhRelease>>(
      label: '发布',
      isEmpty: (List<GhRelease> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.releases(_full),
    );
    controller.addListener(_onChanged);
    _releases = controller;
    return controller;
  }

  OgLAsyncController<List<GhBranch>> _branchesC() {
    final existing = _branches;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhBranch>>(
      label: '分支',
      isEmpty: (List<GhBranch> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.branches(_full),
    );
    controller.addListener(_onChanged);
    _branches = controller;
    return controller;
  }

  OgLAsyncController<List<GhCommit>> _commitsC() {
    final existing = _commits;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhCommit>>(
      label: '提交',
      isEmpty: (List<GhCommit> value) => value.isEmpty,
      loader: () => widget.surface.domain.api.commits(
            _full,
            branch: _repo.defaultBranch,
          ),
    );
    controller.addListener(_onChanged);
    _commits = controller;
    return controller;
  }

  /// 用 `GET /repos/{full}` 兜底刷新仓库信息（**失败不阻塞页面**）。
  Future<void> _refreshRepo() async {
    try {
      final fresh = await widget.surface.domain.api.repo(_full);
      if (!mounted) {
        return;
      }
      setState(() => _repo = fresh);
      await _entriesC().load();
    } catch (error) {
      OgLAppLog.instance.add('仓库', '详情刷新失败（不影响浏览）：$error');
    }
  }

  Future<void> _switchTab(_RepoTab tab) async {
    if (tab == _tab) {
      return;
    }
    setState(() => _tab = tab);
    if (tab == _RepoTab.code) {
      await _entriesC().loadIfNeeded();
    } else if (tab == _RepoTab.issues) {
      await _issuesC().loadIfNeeded();
    } else if (tab == _RepoTab.pulls) {
      await _pullsC().loadIfNeeded();
    } else if (tab == _RepoTab.releases) {
      await _releasesC().loadIfNeeded();
    } else if (tab == _RepoTab.branches) {
      await _branchesC().loadIfNeeded();
    } else if (tab == _RepoTab.commits) {
      await _commitsC().loadIfNeeded();
    } else if (tab == _RepoTab.actions) {
      await _actsC().loadIfNeeded();
    } else {
      await _pagesC().loadIfNeeded();
      await _loadCname();
    }
  }

  Future<void> _toggleStar() async {
    final target = !(_starred ?? false);
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.surface.domain.api.setStarred(_full, target);
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
      message: '将在你的账户下创建「$_full」的副本。',
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
      final forked = await widget.surface.domain.api.fork(_full);
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
      _fileError = null;
      _pendingFile = null;
      _editing = false;
    });
    _entriesC().load();
  }

  /// 重试最近一次失败的文件打开。
  ///
  /// 历史缺陷：打开文件失败时只改了 `_fileError`，而错误只在"文件视图"
  /// 里渲染 —— 文件没打开就还在目录视图，于是用户看到的是"点了没反应"
  /// （错误无声消失，违反红线）。这里给出可见的失败 + 一键重试。
  Future<void> _retryPendingOpen() async {
    final pending = _pendingFile;
    if (pending == null) {
      return;
    }
    await _openFile(pending);
  }

  Future<void> _openFile(GhContent entry) async {
    setState(() {
      _pendingFile = entry;
      _fileLoading = true;
      _fileError = null;
      _file = null;
      _fileText = null;
      _editing = false;
    });
    try {
      final file = await widget.surface.domain.api.content(
        _full,
        entry.path,
        branch: _repo.defaultBranch,
      );
      if (file == null) {
        throw Exception('读不到内容（可能是二进制文件或权限不足）');
      }
      var text = file.text;
      if (text == null && file.isTooLarge) {
        text = await widget.surface.domain.api
            .blobText(_full, file.sha);
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
        _full,
        file.path,
        content: _editController.text,
        message: message,
        baseSha: file.sha,
        branch: _repo.defaultBranch,
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
        _full,
        file.path,
        message: 'chore: delete ${file.path}',
        baseSha: file.sha,
        branch: _repo.defaultBranch,
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
    final repo = _repo;
    return OgLPageScaffold(
      title: repo.fullName,
      description: repo.description ?? '（无描述）',
      onRefresh: () async {
        await _refreshRepo();
      },
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildRepoMeta(ogL, tokens),
          if (_notice != null) ...<Widget>[
            SizedBox(height: tokens.space(OgLSpacing.md)),
            OgLBanner(variant: OgLBannerVariant.success, text: _notice!),
          ],
          if (_error != null) ...<Widget>[
            SizedBox(height: tokens.space(OgLSpacing.md)),
            OgLBanner(variant: OgLBannerVariant.danger, text: _error!),
          ],
          SizedBox(height: tokens.space(OgLSpacing.lg)),
          OgLUnderlineNav<_RepoTab>(
            items: <OgLUnderlineNavItem<_RepoTab>>[
              for (final tab in _RepoTab.values)
                OgLUnderlineNavItem<_RepoTab>(
                  value: tab,
                  label: _tabLabel(tab),
                ),
            ],
            value: _tab,
            onChanged: (tab) async {
              await _switchTab(tab);
            },
          ),
          SizedBox(height: tokens.space(OgLSpacing.md)),
          if (_tab == _RepoTab.code) ...<Widget>[
            if (_fileLoading && _file == null)
              const Center(child: OgLSpinner(label: '读取中…'))
            else if (_file != null)
              _buildFileView(ogL, tokens)
            else
              _buildBrowser(ogL, tokens),
            // README：GitHub 的仓库页把它放在文件列表下面，这里保持一致。
            _buildReadme(ogL, tokens),
          ] else if (_tab == _RepoTab.issues)
            _buildIssues(ogL, tokens)
          else if (_tab == _RepoTab.pulls)
            _buildPulls(ogL, tokens)
          else if (_tab == _RepoTab.releases)
            _buildReleases(ogL, tokens)
          else if (_tab == _RepoTab.branches)
            _buildBranches(ogL, tokens)
          else if (_tab == _RepoTab.commits)
            _buildCommits(ogL, tokens)
          else if (_tab == _RepoTab.actions)
            _buildActions(ogL, tokens)
          else
            _buildSettings(ogL, tokens),
        ],
      ),
    );
  }

  /// README 区块：**离线安全**渲染（净化 Markdown → 令牌化排版）。
  ///
  /// 四态纪律：`null` / 空文本 = **空态**（没有 README 是正常现象），
  /// 只有真异常才显示错误 + 重试 —— 不许把"没有"渲染成"坏了"。
  Widget _buildReadme(OgLTheme ogL, OgLTokens tokens) {
    final controller = _readmeC();
    return OgLSection(
      title: 'README',
      description: '显示在仓库首页的说明文档（图片不联网加载，链接可点开）',
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? child) {
          final OgLAsync<String?> state = controller.state;
          final String text = state.data ?? '';
          return ogLAsyncView<String?>(
            state: state,
            errorTitle: 'README 读取失败',
            onRetry: () async {
              await controller.load();
            },
            emptyIcon: OgLIconName.book,
            emptyTitle: '这个仓库还没有 README',
            emptyBody: '在默认分支放一个 `README.md`，它的内容会显示在这里。',
            skeletonLines: 6,
            child: OgLBox(
              child: OgLReadmeView(
                markdown: text,
                onOpenLink: _openLink,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 打开 README 里的链接：优先交给系统；失败则把 URL 摊开让用户自己复制
  /// （**不许"点了没反应"**）。
  Future<void> _openLink(Uri url) async {
    OgLAppLog.instance.add('仓库', '打开链接：$url');
    try {
      final bool ok = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!ok) {
        _showLink(url);
      }
    } catch (error) {
      OgLAppLog.instance
          .add('仓库', '打开链接失败：$error', severity: OgLNoticeSeverity.warning);
      _showLink(url);
    }
  }

  void _showLink(Uri url) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('无法打开浏览器，链接：$url')),
    );
  }

  /// 仓库元信息：标识标签 + 统计行（图标走自绘矢量，数字用等宽更整齐）。
  Widget _buildRepoMeta(OgLTheme ogL, OgLTokens tokens) {
    final repo = _repo;
    return OgLBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
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
              if (repo.defaultBranch.isNotEmpty)
                OgLLabel(
                  text: repo.defaultBranch,
                  variant: OgLLabelVariant.done,
                ),
              if (repo.hasPages)
                const OgLLabel(text: 'Pages', variant: OgLLabelVariant.accent),
            ],
          ),
          SizedBox(height: tokens.space(OgLSpacing.md)),
          Row(
            children: <Widget>[
              _metaItem(ogL, tokens, OgLIconName.star, '${repo.stars}'),
              _metaItem(ogL, tokens, OgLIconName.fork, '${repo.forks}'),
              _metaItem(ogL, tokens, OgLIconName.issue, '${repo.openIssues}'),
              _metaItem(
                ogL,
                tokens,
                OgLIconName.file,
                repo.sizeKb >= 1024
                    ? '${(repo.sizeKb / 1024).toStringAsFixed(1)} MB'
                    : '${repo.sizeKb} KB',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 统计项：语义图标 + 数字。
  Widget _metaItem(
    OgLTheme ogL,
    OgLTokens tokens,
    OgLIconName icon,
    String text,
  ) {
    final scale = const OgLTypeScale.standard();
    return Padding(
      padding: EdgeInsets.only(right: tokens.space(OgLSpacing.lg)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          OgLIcon(
            name: icon,
            size: tokens.iconSize(base: 14),
            color: ogL.palette.textDim,
          ),
          SizedBox(width: tokens.space(OgLSpacing.xs)),
          Text(
            text,
            style: TextStyle(
              fontFamily: kOgLMonoFamily,
              fontSize: tokens.fontSize(scale.label),
              color: ogL.palette.textDim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowser(OgLTheme ogL, OgLTokens tokens) {
    final state = _entriesC().state;
    final list = state.data ?? const <GhContent>[];
    final String? fileError = _fileError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                '/${_path.isEmpty ? _repo.name : _path}',
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
        if (fileError != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.sm)),
          OgLBanner(
            variant: OgLBannerVariant.danger,
            title: '文件打开失败',
            text: fileError,
            actions: <Widget>[
              OgLButton(
                label: '重试',
                size: OgLButtonSize.small,
                onPressed: () async {
                  await _retryPendingOpen();
                },
              ),
            ],
          ),
        ],
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        ogLAsyncView(
          state: state,
          errorTitle: '目录读取失败',
          onRetry: () => _entriesC().load(),
          emptyIcon: OgLIconName.folder,
          emptyTitle: '这个目录是空的',
          emptyBody: '换个目录看看；GitHub 不支持提交空目录。',
          skeletonLines: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final entry in list)
                OgLActionRow(
                  showDivider: true,
                  title: entry.path.split('/').last,
                  subtitle: entry.isDirectory ? '目录' : _sizeText(entry.size),
                  leading: OgLIcon(
                  name: entry.isDirectory
                      ? OgLIconName.folder
                      : OgLIconName.file,
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
  String _tabLabel(_RepoTab tab) {
    if (tab == _RepoTab.code) {
      return '代码';
    }
    if (tab == _RepoTab.issues) {
      return '议题';
    }
    if (tab == _RepoTab.pulls) {
      return 'PR';
    }
    if (tab == _RepoTab.releases) {
      return '发布';
    }
    if (tab == _RepoTab.branches) {
      return '分支';
    }
    if (tab == _RepoTab.actions) {
      return '操作';
    }
    if (tab == _RepoTab.settings) {
      return '设置';
    }
    return '提交';
  }

  String _loginOf(Map<String, dynamic> item) {
    final user = item['user'];
    if (user is Map<Object?, Object?>) {
      return GhJson.str(Map<String, dynamic>.from(user), 'login');
    }
    return '';
  }

  String _dateText(DateTime? date) {
    if (date == null) {
      return '—';
    }
    final text = date.toIso8601String();
    final index = text.indexOf('T');
    return index > 0 ? text.substring(0, index) : text;
  }

  String _shortSha(String sha) => sha.length >= 7 ? sha.substring(0, 7) : sha;

  Future<void> _createRelease() async {
    final created = await Navigator.of(context).push<GhRelease>(
      MaterialPageRoute<GhRelease>(
        builder: (BuildContext context) => OgLNewReleasePage(
          surface: widget.surface,
          fullName: _full,
          defaultBranch: _repo.defaultBranch,
        ),
      ),
    );
    if (created != null && mounted) {
      setState(() => _notice = '已发布 ${created.tagName}');
      await _releasesC().load();
    }
  }

  Future<void> _deleteRelease(GhRelease release) async {
    final confirmed = await ogLConfirmDialog(
      context,
      title: '删除发布',
      message: '将删除「${release.tagName}」的 Release（tag 本身保留）。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _releaseBusy = true);
    try {
      await widget.surface.domain.api
          .deleteRelease(_full, release.id);
      OgLAppLog.instance.add('发布', '已删除 ${release.tagName}');
      if (mounted) {
        setState(() => _notice = '已删除发布 ${release.tagName}');
      }
      await _releasesC().load();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '发布',
        '删除失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '删除失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _releaseBusy = false);
      } else {
        _releaseBusy = false;
      }
    }
  }

  Future<void> _closeIssue(Map<String, dynamic> item) async {
    final number = GhJson.integer(item, 'number');
    final confirmed = await ogLConfirmDialog(
      context,
      title: '关闭议题',
      message: '将把 #$number 标记为已关闭（可在 GitHub 网页端重新打开）。',
      confirmLabel: '关闭',
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api
          .updateIssue(_full, number, state: 'closed');
      OgLAppLog.instance.add('议题', '已关闭 #$number');
      if (mounted) {
        setState(() => _notice = '已关闭 #$number');
      }
      await _issuesC().load();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '议题',
        '关闭失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '关闭失败：$error');
      }
    }
  }

  OgLAsyncController<Map<String, dynamic>> _pagesC() {
    final existing = _pages;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<Map<String, dynamic>>(
      label: 'Pages',
      isEmpty: (Map<String, dynamic> value) => false,
      loader: () async {
        final info =
            await widget.surface.domain.api.pagesInfo(_full);
        return info ?? const <String, dynamic>{};
      },
    );
    controller.addListener(_onChanged);
    _pages = controller;
    return controller;
  }

  Future<void> _loadCname() async {
    try {
      final file = await widget.surface.domain.api
          .content(_full, 'CNAME');
      if (!mounted) {
        return;
      }
      setState(() {
        _cnameSha = file?.sha;
        _cnameCtl.text = file?.text?.trim() ?? '';
      });
    } catch (error) {
      OgLAppLog.instance.add('设置', '读取 CNAME 失败：$error');
    }
  }

  Future<void> _saveBasic() async {
    setState(() {
      _settingsBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      final updated = await widget.surface.domain.api.updateRepo(
        _full,
        name: _nameCtl.text.trim().isEmpty ? null : _nameCtl.text.trim(),
        description: _descCtl.text.trim(),
        private: _privateVal,
      );
      OgLAppLog.instance.add('设置', '已保存基本信息：${updated.fullName}');
      if (mounted) {
        setState(() {
          // 改名后继续用新全名操作 —— 否则后续请求会打到"已不存在的旧名"。
          if (updated.fullName.isNotEmpty && updated.fullName != _full) {
            _fullName = updated.fullName;
            _notice = '已保存基本信息（仓库已改名：${updated.fullName}）';
          } else {
            _notice = '已保存基本信息';
          }
        });
      }
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '设置',
        '保存失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _settingsBusy = false);
      } else {
        _settingsBusy = false;
      }
    }
  }

  Future<void> _saveCname() async {
    setState(() {
      _settingsBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.surface.domain.api.putContent(
        _full,
        'CNAME',
        content: '${_cnameCtl.text.trim()}\n',
        message: 'chore: configure custom domain',
        baseSha: _cnameSha,
        branch: _repo.defaultBranch,
      );
      OgLAppLog.instance.add('设置', '已保存 CNAME');
      if (mounted) {
        setState(() => _notice = '已保存 CNAME');
      }
      await _loadCname();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '设置',
        'CNAME 保存失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = 'CNAME 保存失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _settingsBusy = false);
      } else {
        _settingsBusy = false;
      }
    }
  }

  Future<void> _enablePages() async {
    setState(() {
      _settingsBusy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.surface.domain.api.enablePages(
        _full,
        branch: _repo.defaultBranch,
      );
      OgLAppLog.instance.add('设置', 'Pages 已启用');
      if (mounted) {
        setState(() => _notice = 'Pages 已启用');
      }
      await _pagesC().load();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '设置',
        'Pages 启用失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = 'Pages 启用失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _settingsBusy = false);
      } else {
        _settingsBusy = false;
      }
    }
  }

  Future<void> _disablePages() async {
    final confirmed = await ogLConfirmDialog(
      context,
      title: '停用 Pages',
      message: '将停止「$_full」的 Pages 站点。',
      confirmLabel: '停用',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() => _settingsBusy = true);
    try {
      await widget.surface.domain.api.disablePages(_full);
      OgLAppLog.instance.add('设置', 'Pages 已停用');
      if (mounted) {
        setState(() => _notice = 'Pages 已停用');
      }
      await _pagesC().load();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '设置',
        'Pages 停用失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = 'Pages 停用失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _settingsBusy = false);
      } else {
        _settingsBusy = false;
      }
    }
  }

  Future<void> _deleteRepo() async {
    final confirmed = await ogLConfirmDialog(
      context,
      title: '删除仓库',
      message: '将永久删除「$_full」及其全部内容。'
          '该操作不可撤销，也不会进入回收站。',
      confirmLabel: '永久删除',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    setState(() {
      _settingsBusy = true;
      _error = null;
    });
    try {
      await widget.surface.domain.api.deleteRepo(_full);
      OgLAppLog.instance.add('设置', '已删除仓库 $_full');
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '设置',
        '删除失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '删除失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _settingsBusy = false);
      } else {
        _settingsBusy = false;
      }
    }
  }

  Widget _buildSettings(OgLTheme ogL, OgLTokens tokens) {
    final scale = const OgLTypeScale.standard();
    final pagesState = _pagesC().state;
    final pages = pagesState.data ?? const <String, dynamic>{};
    final bool pagesEnabled = pages.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        OgLBox(
          title: '基本设置',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OgLTextField(
                controller: _nameCtl,
                label: '仓库名',
                enabled: !_settingsBusy,
              ),
              SizedBox(height: tokens.space(OgLSpacing.sm)),
              OgLTextField(
                controller: _descCtl,
                label: '描述',
                enabled: !_settingsBusy,
              ),
              SizedBox(height: tokens.space(OgLSpacing.sm)),
              OgLToggleSwitch(
                label: '私有仓库',
                description: '私有仓库只有你与协作者可见。',
                value: _privateVal,
                onChanged: _settingsBusy
                    ? null
                    : (bool v) => setState(() => _privateVal = v),
              ),
              SizedBox(height: tokens.space(OgLSpacing.md)),
              OgLButton(
                label: _settingsBusy ? '保存中…' : '保存基本信息',
                leadingIcon: OgLIconName.upload,
                loading: _settingsBusy,
                onPressed: _saveBasic,
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        OgLBox(
          title: 'Pages / 自定义域名',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (pagesState.failureMessage != null)
                // 历史缺陷：Pages 读取失败时旧实现永远停在骨架上
                // （"大面积灰色块"来源之三，而且永远不告诉用户失败了）。
                OgLBanner(
                  variant: OgLBannerVariant.danger,
                  title: 'Pages 状态读取失败',
                  text: pagesState.failureMessage!,
                  actions: <Widget>[
                    OgLButton(
                      label: '重试',
                      size: OgLButtonSize.small,
                      onPressed: () async {
                        await _pagesC().load();
                      },
                    ),
                  ],
                )
              else if (pagesState.isFirstLoading)
                const OgLSkeletonText(lines: 2)
              else if (!pagesEnabled) ...<Widget>[
                Text(
                  'Pages 未启用。',
                  style: TextStyle(
                    fontSize: tokens.fontSize(scale.body),
                    color: ogL.palette.textDim,
                  ),
                ),
                SizedBox(height: tokens.space(OgLSpacing.sm)),
                OgLButton(
                  label: '启用 Pages（分支：${_repo.defaultBranch}）',
                  leadingIcon: OgLIconName.workflow,
                  onPressed: _settingsBusy ? null : _enablePages,
                ),
              ] else ...<Widget>[
                Text(
                  '已启用：${pages['html_url'] is String ? pages['html_url'] : '（URL 未知）'}',
                  style: TextStyle(
                    fontFamily: kOgLMonoFamily,
                    fontSize: tokens.fontSize(scale.data),
                    color: ogL.palette.text,
                  ),
                ),
                SizedBox(height: tokens.space(OgLSpacing.sm)),
                OgLButton(
                  label: '停用 Pages',
                  variant: OgLButtonVariant.danger,
                  onPressed: _settingsBusy ? null : _disablePages,
                ),
              ],
              SizedBox(height: tokens.space(OgLSpacing.md)),
              OgLTextField(
                controller: _cnameCtl,
                label: 'CNAME（自定义域名）',
                hint: 'example.com',
                enabled: !_settingsBusy,
              ),
              SizedBox(height: tokens.space(OgLSpacing.sm)),
              OgLButton(
                label: '保存 CNAME',
                leadingIcon: OgLIconName.dns,
                onPressed: _settingsBusy ? null : _saveCname,
              ),
            ],
          ),
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        OgLBox(
          title: '危险区',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '删除仓库不可撤销，也不会进入回收站。',
                style: TextStyle(
                  fontSize: tokens.fontSize(scale.body),
                  color: ogL.palette.textDim,
                ),
              ),
              SizedBox(height: tokens.space(OgLSpacing.sm)),
              OgLButton(
                label: '删除仓库',
                variant: OgLButtonVariant.danger,
                leadingIcon: OgLIconName.delete,
                onPressed: _settingsBusy ? null : _deleteRepo,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _openIssue(Map<String, dynamic> item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OgLIssuePage(
          surface: widget.surface,
          fullName: _full,
          issue: item,
        ),
      ),
    );
    if (mounted) {
      await _issuesC().load();
    }
  }

  Future<void> _openCommit(GhCommit commit) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OgLCommitPage(
          surface: widget.surface,
          fullName: _full,
          commit: commit,
        ),
      ),
    );
  }

  OgLAsyncController<List<Map<String, dynamic>>> _actsC() {
    final existing = _acts;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<Map<String, dynamic>>>(
      label: '动作',
      isEmpty: (List<Map<String, dynamic>> value) => value.isEmpty,
      loader: () =>
          widget.surface.domain.api.workflowRuns(_full),
    );
    controller.addListener(_onChanged);
    _acts = controller;
    return controller;
  }

  Future<void> _openPull(Map<String, dynamic> item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OgLPullPage(
          surface: widget.surface,
          fullName: _full,
          pull: item,
        ),
      ),
    );
  }

  Future<void> _createBranch() async {
    final name = await ogLPromptDialog(
      context,
      title: '新建分支',
      label: '分支名',
      hint: 'feature/xxx',
      confirmLabel: '创建',
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api.createBranch(
        _full,
        name: trimmed,
        fromBranch: _repo.defaultBranch,
      );
      OgLAppLog.instance.add('分支', '已创建 $trimmed');
      if (mounted) {
        setState(() => _notice = '已创建分支 $trimmed');
      }
      await _branchesC().load();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '分支',
        '创建失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '创建分支失败：$error');
      }
    }
  }

  Future<void> _renameBranch(GhBranch branch) async {
    final name = await ogLPromptDialog(
      context,
      title: '重命名分支',
      label: '新名称',
      initial: branch.name,
      confirmLabel: '重命名',
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == branch.name || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api
          .renameBranch(_full, branch.name, trimmed);
      OgLAppLog.instance.add('分支', '已重命名 ${branch.name} → $trimmed');
      if (mounted) {
        setState(() => _notice = '已重命名：$trimmed');
      }
      await _branchesC().load();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '分支',
        '重命名失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '重命名失败：$error');
      }
    }
  }

  Future<void> _deleteBranch(GhBranch branch) async {
    final confirmed = await ogLConfirmDialog(
      context,
      title: '删除分支',
      message: '将删除分支「${branch.name}」。该操作不可直接撤销。',
      confirmLabel: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.api
          .deleteBranch(_full, branch.name);
      OgLAppLog.instance.add('分支', '已删除 ${branch.name}');
      if (mounted) {
        setState(() => _notice = '已删除分支 ${branch.name}');
      }
      await _branchesC().load();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '分支',
        '删除失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '删除分支失败：$error');
      }
    }
  }

  Widget _buildActions(OgLTheme ogL, OgLTokens tokens) {
    final state = _actsC().state;
    final list = state.data ?? const <Map<String, dynamic>>[];
    return ogLAsyncView(
      state: state,
      errorTitle: '操作记录读取失败',
      onRetry: () => _actsC().load(),
      emptyIcon: OgLIconName.workflow,
      emptyTitle: '没有工作流运行记录',
      emptyBody: '该仓库还没有跑过 Actions，或当前令牌缺少 actions 读取权限。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final item in list)
            OgLActionRow(
              showDivider: true,
              leading: OgLIcon(
                name: OgLIconName.workflow,
                size: tokens.iconSize(base: 20),
                color: ogL.palette.textDim,
              ),
              title: GhJson.str(item, 'name'),
              subtitle: '${GhJson.str(item, 'status')} · '
                  '${GhJson.str(item, 'conclusion').isEmpty ? '—' : GhJson.str(item, 'conclusion')} · '
                  '${_dateText(GhJson.date(item, 'created_at'))}',
            ),
        ],
      ),
    );
  }

  Future<void> _createIssue() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => OgLNewIssuePage(
          surface: widget.surface,
          fullName: _full,
        ),
      ),
    );
    if (created == true && mounted) {
      setState(() => _notice = '已创建议题');
      await _issuesC().load();
    }
  }

  Widget _buildIssues(OgLTheme ogL, OgLTokens tokens) {
    final state = _issuesC().state;
    final list = state.data ?? const <Map<String, dynamic>>[];
    return ogLAsyncView(
      state: state,
      errorTitle: '议题读取失败',
      onRetry: () => _issuesC().load(),
      emptyIcon: OgLIconName.issue,
      emptyTitle: '没有打开的议题',
      emptyBody: '议题用来跟踪缺陷与任务；可以从这里直接新建一个。',
      emptyAction: OgLButton(
        label: '新建议题',
        variant: OgLButtonVariant.primary,
        leadingIcon: OgLIconName.add,
        onPressed: _createIssue,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '共 ${list.length} 个议题',
                  style: TextStyle(
                    fontSize:
                        tokens.fontSize(const OgLTypeScale.standard().label),
                    color: ogL.palette.textDim,
                  ),
                ),
              ),
              OgLButton(
                label: '新建议题',
                variant: OgLButtonVariant.primary,
                size: OgLButtonSize.small,
                leadingIcon: OgLIconName.add,
                onPressed: _createIssue,
              ),
            ],
          ),
          for (final item in list)
            OgLActionRow(
              showDivider: true,
              leading: OgLIcon(
                name: OgLIconName.issue,
                size: tokens.iconSize(base: 20),
                color: ogL.palette.textDim,
              ),
              title:
                  '#${GhJson.integer(item, 'number')} ${GhJson.str(item, 'title')}',
              subtitle: 'by ${_loginOf(item)} · '
                  '${GhJson.integer(item, 'comments')} 条评论',
              trailing: OgLButton(
                label: '关闭',
                variant: OgLButtonVariant.invisible,
                size: OgLButtonSize.small,
                onPressed: () async {
                  await _closeIssue(item);
                },
              ),
              onTap: () async {
                await _openIssue(item);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPulls(OgLTheme ogL, OgLTokens tokens) {
    final state = _pullsC().state;
    final list = state.data ?? const <Map<String, dynamic>>[];
    return ogLAsyncView(
      state: state,
      errorTitle: 'PR 读取失败',
      onRetry: () => _pullsC().load(),
      emptyIcon: OgLIconName.pullRequest,
      emptyTitle: '没有打开的拉取请求',
      emptyBody: '当有人提出变更请求时，会出现在这里。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final item in list)
            OgLActionRow(
              showDivider: true,
              leading: OgLIcon(
                name: OgLIconName.pullRequest,
                size: tokens.iconSize(base: 20),
                color: ogL.palette.textDim,
              ),
              title:
                  '#${GhJson.integer(item, 'number')} ${GhJson.str(item, 'title')}',
              subtitle: 'by ${_loginOf(item)} · ${GhJson.str(item, 'state')}',
              showChevron: true,
              onTap: () async {
                await _openPull(item);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildReleases(OgLTheme ogL, OgLTokens tokens) {
    final state = _releasesC().state;
    final list = state.data ?? const <GhRelease>[];
    return ogLAsyncView(
      state: state,
      errorTitle: '发布读取失败',
      onRetry: () => _releasesC().load(),
      emptyIcon: OgLIconName.release,
      emptyTitle: '还没有发布',
      emptyBody: '发布用于给用户一个可下载的稳定版本。',
      emptyAction: OgLButton(
        label: '新建发布',
        variant: OgLButtonVariant.primary,
        leadingIcon: OgLIconName.add,
        onPressed: _releaseBusy ? null : _createRelease,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '共 ${list.length} 个发布',
                  style: TextStyle(
                    fontSize:
                        tokens.fontSize(const OgLTypeScale.standard().label),
                    color: ogL.palette.textDim,
                  ),
                ),
              ),
              OgLButton(
                label: '新建发布',
                variant: OgLButtonVariant.primary,
                size: OgLButtonSize.small,
                leadingIcon: OgLIconName.add,
                onPressed: _releaseBusy ? null : _createRelease,
              ),
            ],
          ),
          for (final release in list)
            OgLActionRow(
              showDivider: true,
              leading: OgLIcon(
                name: OgLIconName.release,
                size: tokens.iconSize(base: 20),
                color: ogL.palette.textDim,
              ),
              title: release.name ?? release.tagName,
              subtitle: '${release.tagName} · '
                  '${_dateText(release.publishedAt ?? release.createdAt)}'
                  '${release.isPrerelease ? ' · Pre' : ''}',
              trailing: OgLButton(
                label: '删除',
                variant: OgLButtonVariant.invisible,
                size: OgLButtonSize.small,
                onPressed: _releaseBusy
                    ? null
                    : () async {
                        await _deleteRelease(release);
                      },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBranches(OgLTheme ogL, OgLTokens tokens) {
    final state = _branchesC().state;
    final list = state.data ?? const <GhBranch>[];
    return ogLAsyncView(
      state: state,
      errorTitle: '分支读取失败',
      onRetry: () => _branchesC().load(),
      emptyIcon: OgLIconName.branch,
      emptyTitle: '没有分支',
      emptyBody: '分支用来隔离开发中的改动；可以从默认分支创建一个。',
      emptyAction: OgLButton(
        label: '新建分支',
        variant: OgLButtonVariant.primary,
        leadingIcon: OgLIconName.add,
        onPressed: _createBranch,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '共 ${list.length} 个分支',
                  style: TextStyle(
                    fontSize:
                        tokens.fontSize(const OgLTypeScale.standard().label),
                    color: ogL.palette.textDim,
                  ),
                ),
              ),
              OgLButton(
                label: '新建分支',
                variant: OgLButtonVariant.primary,
                size: OgLButtonSize.small,
                leadingIcon: OgLIconName.add,
                onPressed: _createBranch,
              ),
            ],
          ),
          for (final branch in list)
            OgLActionRow(
              showDivider: true,
              leading: OgLIcon(
                name: OgLIconName.branch,
                size: tokens.iconSize(base: 20),
                color: ogL.palette.textDim,
              ),
              title: branch.name,
              subtitle:
                  'sha ${_shortSha(branch.sha)}${branch.isProtected ? ' · 受保护' : ''}',
              trailing: Wrap(
                spacing: tokens.space(OgLSpacing.xs),
                children: <Widget>[
                  OgLButton(
                    label: '重命名',
                    variant: OgLButtonVariant.invisible,
                    size: OgLButtonSize.small,
                    onPressed: () async {
                      await _renameBranch(branch);
                    },
                  ),
                  OgLButton(
                    label: '删除',
                    variant: OgLButtonVariant.invisible,
                    size: OgLButtonSize.small,
                    onPressed: () async {
                      await _deleteBranch(branch);
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommits(OgLTheme ogL, OgLTokens tokens) {
    final state = _commitsC().state;
    final list = state.data ?? const <GhCommit>[];
    return ogLAsyncView(
      state: state,
      errorTitle: '提交读取失败',
      onRetry: () => _commitsC().load(),
      emptyIcon: OgLIconName.commit,
      emptyTitle: '没有提交记录',
      emptyBody: '这个分支上还没有任何提交。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final commit in list)
            OgLActionRow(
              showDivider: true,
              leading: OgLIcon(
                name: OgLIconName.commit,
                size: tokens.iconSize(base: 20),
                color: ogL.palette.textDim,
              ),
              title: commit.message.isEmpty
                  ? '（无提交信息）'
                  : commit.message.split('\n').first,
              subtitle: '${_shortSha(commit.sha)} · '
                  '${commit.authorLogin ?? commit.authorName ?? '未知'} · '
                  '${_dateText(commit.date)}',
              showChevron: true,
              onTap: () async {
                await _openCommit(commit);
              },
            ),
        ],
      ),
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