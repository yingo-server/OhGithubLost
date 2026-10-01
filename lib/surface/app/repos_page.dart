/// L3 展示级 · 仓库页：**第一条真实数据链路**。
///
/// ## 它接通的链路
/// ```
/// OgLReposPage → SurfaceBridge.domain.api（GhApi）
///              → base_bridge → net（限流/并发/重试）
///              → GitHub REST /user/repos
/// ```
/// 令牌经 `GhAuthService` 存入 L1 的安全保险库（`gh.token.*` 密文），
/// 页面上**永远不显示明文**，只显示脱敏与登录名。
///
/// ## 三条自我约束（与 og_l_app 相同）
/// 1. 没有 `MediaQuery` 宽度判断（布局交给上层与令牌）；
/// 2. 没有 `Colors.xxx` / 尺寸字面量，一律走 `OgLTheme` 令牌；
/// 3. 没有 `Icons.xxx`，一律走 `OgLIconName`。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../../domain/gh/gh_models.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'async_state.dart';
import 'error_surface.dart';

/// 仓库页（含令牌接入向导）。
class OgLReposPage extends StatefulWidget {
  /// 创建页面。
  const OgLReposPage({required this.surface, super.key});

  /// 表面桥（业务数据一律经 `surface.domain` 取）。
  final SurfaceBridge surface;

  @override
  State<OgLReposPage> createState() => _OgLReposPageState();
}

class _OgLReposPageState extends State<OgLReposPage> {
  OgLAsyncController<List<GhRepo>>? _repos;
  GhAccount? _account;
  bool _bootChecked = false;
  GhRepo? _selected;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _repos?.removeListener(_onChanged);
    _repos?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _prepare() async {
    final GhAccount? account = await widget.surface.domain.auth.activeAccount();
    if (!mounted) {
      return;
    }
    setState(() {
      _account = account;
      _bootChecked = true;
    });
    if (account != null) {
      await _ensureController().loadIfNeeded();
    }
  }

  OgLAsyncController<List<GhRepo>> _ensureController() {
    final existing = _repos;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhRepo>>(
      label: '仓库',
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      loader: () async {
        OgLAppLog.instance.add('仓库', '拉取仓库列表…');
        try {
          final list = await widget.surface.domain.api.myRepos(perPage: 100);
          OgLAppLog.instance.add('仓库', '拉取成功：${list.length} 个仓库');
          return list;
        } catch (error, stackTrace) {
          OgLAppLog.instance.add(
            '仓库',
            '拉取失败（原始异常）：$error\n$stackTrace',
            severity: OgLNoticeSeverity.critical,
          );
          rethrow;
        }
      },
    );
    controller.addListener(_onChanged);
    _repos = controller;
    return controller;
  }

  void _dropController() {
    _repos?.removeListener(_onChanged);
    _repos?.dispose();
    _repos = null;
    _selected = null;
  }

  Future<void> _afterLogin() async {
    _dropController();
    final GhAccount? account = await widget.surface.domain.auth.activeAccount();
    if (!mounted) {
      return;
    }
    setState(() => _account = account);
    if (account != null) {
      await _ensureController().load();
    }
  }

  Future<void> _logout() async {
    final account = _account;
    if (account == null) {
      return;
    }
    await widget.surface.domain.auth.removeAccount(account.id);
    _dropController();
    if (!mounted) {
      return;
    }
    setState(() => _account = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_bootChecked) {
      return const Center(child: CircularProgressIndicator());
    }
    final account = _account;
    if (account == null) {
      return _TokenOnboarding(surface: widget.surface, onDone: _afterLogin);
    }
    final controller = _ensureController();
    final state = controller.state;
    final selected = _selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _AccountBar(
          account: account,
          busy: controller.isBusy,
          onRefresh: controller.load,
          onLogout: _logout,
        ),
        if (state.refreshError != null)
          _NoticeBar(
            message: state.refreshError!,
            onDismiss: controller.dismissRefreshError,
          ),
        Expanded(
          child: selected != null
              ? _RepoDetail(
                  repo: selected,
                  onBack: () => setState(() => _selected = null),
                )
              : _RepoListBody(
                  controller: controller,
                  state: state,
                  onSelect: (GhRepo repo) => setState(() => _selected = repo),
                ),
        ),
      ],
    );
  }
}

/// 账号栏：登录名 + 刷新 + 退出。
class _AccountBar extends StatelessWidget {
  const _AccountBar({
    required this.account,
    required this.busy,
    required this.onRefresh,
    required this.onLogout,
  });

  final GhAccount account;
  final bool busy;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: ogL.tokens.space(OgLSpacing.sm)),
      child: Row(
        children: <Widget>[
          Icon(ogL.icon(OgLIconName.key), size: text.bodyMedium?.fontSize),
          SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
          Expanded(
            child: Text(
              '已登录：${account.login}',
              style: text.bodyMedium?.copyWith(color: palette.textDim),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : () => onRefresh(),
            icon: busy
                ? SizedBox(
                    width: text.bodyMedium?.fontSize ?? 16,
                    height: text.bodyMedium?.fontSize ?? 16,
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(ogL.icon(OgLIconName.sync)),
          ),
          TextButton(onPressed: () => onLogout(), child: const Text('退出登录')),
        ],
      ),
    );
  }
}

/// 刷新失败但在展示旧数据时的提示条。
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    return Container(
      margin: EdgeInsets.only(bottom: ogL.tokens.space(OgLSpacing.sm)),
      padding: EdgeInsets.all(ogL.tokens.space(OgLSpacing.sm)),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        border: Border.all(color: palette.textFaint, width: ogL.tokens.hairline),
      ),
      child: Row(
        children: <Widget>[
          Icon(ogL.icon(OgLIconName.warning)),
          SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
          Expanded(child: Text(message)),
          TextButton(onPressed: onDismiss, child: const Text('知道了')),
        ],
      ),
    );
  }
}

/// 列表主体：四态（加载 / 失败 / 空 / 就绪）。
class _RepoListBody extends StatelessWidget {
  const _RepoListBody({
    required this.controller,
    required this.state,
    required this.onSelect,
  });

  final OgLAsyncController<List<GhRepo>> controller;
  final OgLAsync<List<GhRepo>> state;
  final ValueChanged<GhRepo> onSelect;

  @override
  Widget build(BuildContext context) {
    if (state.hasData) {
      final repos = state.data ?? const <GhRepo>[];
      return RefreshIndicator(
        onRefresh: controller.load,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          itemCount: repos.length,
          separatorBuilder: (_, __) => const SizedBox.shrink(),
          itemBuilder: (BuildContext context, int index) =>
              _RepoRow(repo: repos[index], onTap: () => onSelect(repos[index])),
        ),
      );
    }
    if (state.phase == OgLAsyncPhase.failed) {
      return _StateMessage(
        icon: OgLIconName.error,
        title: state.message ?? '加载失败',
        actionLabel: '重试',
        onAction: controller.load,
      );
    }
    if (state.phase == OgLAsyncPhase.empty) {
      return _StateMessage(
        icon: OgLIconName.folder,
        title: '这个账号下还没有可见的仓库',
        actionLabel: '刷新',
        onAction: controller.load,
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

/// 失败的统一展示（带重试动作）。
class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final OgLIconName icon;
  final String title;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(ogL.icon(icon), color: palette.textDim),
          SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ogL.tokens.space(OgLSpacing.lg),
            ),
            child: Text(title, textAlign: TextAlign.center),
          ),
          SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
          FilledButton(onPressed: () => onAction(), child: Text(actionLabel)),
        ],
      ),
    );
  }
}

/// 单行仓库。
class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo, required this.onTap});

  final GhRepo repo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    final text = Theme.of(context).textTheme;
    final meta = <String>[
      repo.language ?? '未知语言',
      '★ ${repo.stars}',
      _formatDate(repo.updatedAt),
    ].join(' · ');
    return ListTile(
      onTap: onTap,
      leading: Icon(ogL.icon(OgLIconName.repository)),
      title: Row(
        children: <Widget>[
          Flexible(
            child: Text(
              repo.name,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall,
            ),
          ),
          if (repo.isPrivate)
            Padding(
              padding: EdgeInsets.only(left: ogL.tokens.space(OgLSpacing.sm)),
              child: Icon(
                ogL.icon(OgLIconName.key),
                size: text.labelSmall?.fontSize,
                color: palette.textFaint,
              ),
            ),
          if (repo.isArchived)
            Padding(
              padding: EdgeInsets.only(left: ogL.tokens.space(OgLSpacing.sm)),
              child: Text('已归档', style: text.labelSmall),
            ),
        ],
      ),
      subtitle: Text(
        repo.description?.isNotEmpty == true ? repo.description! : '（无描述）',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Icon(
            ogL.icon(OgLIconName.chevronRight),
            size: text.labelSmall?.fontSize,
            color: palette.textFaint,
          ),
          Text(meta, style: text.labelSmall?.copyWith(color: palette.textFaint)),
        ],
      ),
    );
  }
}

/// 仓库详情（只读事实面板）。
class _RepoDetail extends StatelessWidget {
  const _RepoDetail({required this.repo, required this.onBack});

  final GhRepo repo;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    final text = Theme.of(context).textTheme;
    final flags = <String>[
      if (repo.isPrivate) '私有',
      if (repo.isFork) 'Fork',
      if (repo.isArchived) '已归档',
      if (repo.hasPages) 'Pages',
    ];
    return ListView(
      children: <Widget>[
        Row(
          children: <Widget>[
            IconButton(
              tooltip: '返回列表',
              onPressed: onBack,
              icon: Icon(ogL.icon(OgLIconName.close)),
            ),
            Expanded(
              child: Text(repo.fullName, style: text.titleMedium),
            ),
          ],
        ),
        SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
        Text(
          repo.description?.isNotEmpty == true ? repo.description! : '（无描述）',
          style: text.bodyMedium?.copyWith(color: palette.textDim),
        ),
        SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
        if (flags.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: ogL.tokens.space(OgLSpacing.sm)),
            child: Wrap(
              spacing: ogL.tokens.space(OgLSpacing.sm),
              runSpacing: ogL.tokens.space(OgLSpacing.sm),
              children: <Widget>[
                for (final flag in flags)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ogL.tokens.space(OgLSpacing.sm),
                      vertical: ogL.tokens.space(OgLSpacing.sm),
                    ),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      border: Border.all(
                        color: palette.textFaint,
                        width: ogL.tokens.hairline,
                      ),
                    ),
                    child: Text(flag, style: text.labelSmall),
                  ),
              ],
            ),
          ),
        _Fact(label: '所有者', value: repo.ownerLogin),
        _Fact(label: '默认分支', value: repo.defaultBranch),
        _Fact(label: '语言', value: repo.language ?? '未知'),
        _Fact(label: '星标', value: '${repo.stars}'),
        _Fact(label: 'Fork', value: '${repo.forks}'),
        _Fact(label: '观察', value: '${repo.watchers}'),
        _Fact(label: '开放议题', value: '${repo.openIssues}'),
        _Fact(label: '体积', value: '${repo.sizeKb} KB'),
        _Fact(label: '最近更新', value: _formatDate(repo.updatedAt)),
        _Fact(label: '主页', value: repo.htmlUrl ?? '—'),
      ],
    );
  }
}

/// 详情里的一行事实。
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ogL.tokens.space(OgLSpacing.sm)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: ogL.tokens.space(OgLSpacing.lg) * 3,
            child: Text(
              label,
              style: text.bodySmall?.copyWith(color: palette.textFaint),
            ),
          ),
          Expanded(child: SelectableText(value, style: text.bodySmall)),
        ],
      ),
    );
  }
}

/// 令牌接入向导（**唯一**的令牌输入入口）。
class _TokenOnboarding extends StatefulWidget {
  const _TokenOnboarding({required this.surface, required this.onDone});

  final SurfaceBridge surface;
  final Future<void> Function() onDone;

  @override
  State<_TokenOnboarding> createState() => _TokenOnboardingState();
}

class _TokenOnboardingState extends State<_TokenOnboarding> {
  final TextEditingController _input = TextEditingController();
  bool _busy = false;
  String? _error;
  /// 原始异常全文（详细文本，供取证 / 复制）。
  String? _errorRaw;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) {
      return;
    }
    final auth = widget.surface.domain.auth;
    final api = widget.surface.domain.api;
    final GhToken token = GhToken(_input.text.trim());
    if (!token.looksValid) {
      setState(() => _error = '令牌形态不对：应以 ghp_ / gho_ / github_pat_ 开头。');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _errorRaw = null;
    });
    final pendingId = 'pending-${DateTime.now().millisecondsSinceEpoch}';
    OgLAppLog.instance.add('认证', '开始验证令牌（${token.masked}）');
    try {
      // 1) 先以临时账号落盘 + 切换，让客户端用这把令牌发请求；
      await auth.saveAccount(
        GhAccount(id: pendingId, login: '（待验证）'),
        token,
      );
      await auth.switchTo(pendingId);
    // 1.5) 回读自检：确认保险库往返后的令牌长度与掩码（防低级错误）。
    final rb = await auth.activeToken();
    OgLAppLog.instance.add(
      '认证',
      '回读自检：len=${rb?.value.length ?? -1} · ${rb?.masked ?? 'null'}',
    );
    // 2) 真实请求验证令牌（这一步会经过限流/并发/重试全套底座）。
    final me = await api.currentUser();
      OgLAppLog.instance.add('认证', '令牌有效：@${me.login}');
      // 3) 验证通过：换成正式账号（临时账号移除）。
      await auth.removeAccount(pendingId);
      await auth.saveAccount(
        GhAccount(id: 'user-${me.id}', login: me.login, name: me.name),
        token,
      );
      await auth.switchTo('user-${me.id}');
      if (!mounted) {
        return;
      }
      _input.clear();
      await widget.onDone();
} catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '认证',
        '验证失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      // ★ 先落日志、再翻译：异常全文进 logcat（tag=OGL_LOGIN_FAILURE），
      //   供设备侧取证；界面同时给出"人话"与原始文本。
      debugPrint('OGL_LOGIN_FAILURE: $error');
      await widget.surface.domain.auth.removeAccount(pendingId);
      if (!mounted) {
        return;
      }
      setState(() {
        _errorRaw = error.toString();
        _error = _describeLoginFailure(error);
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final palette = ogL.palette;
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        child: Container(
          constraints: BoxConstraints(
            maxWidth: ogL.tokens.space(OgLSpacing.lg) * 24,
          ),
          padding: EdgeInsets.all(ogL.tokens.space(OgLSpacing.lg)),
          decoration: BoxDecoration(
            color: palette.surfaceAlt,
            border: Border.all(
              color: palette.textFaint,
              width: ogL.tokens.hairline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(ogL.icon(OgLIconName.shield)),
                  SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
                  Text('接入 GitHub', style: text.titleMedium),
                ],
              ),
              SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
              Text(
                '粘贴一个访问令牌（PAT）。令牌会存进系统安全保险库，'
                '界面上永远只显示脱敏信息；不会请求任何非 GitHub 域名。',
                style: text.bodySmall?.copyWith(color: palette.textDim),
              ),
              SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
              TextField(
                controller: _input,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: '访问令牌',
                  hintText: 'ghp_… / github_pat_…',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...<Widget>[
                SizedBox(height: ogL.tokens.space(OgLSpacing.sm)),
                Text(
                  _error!,
                  style: text.bodySmall?.copyWith(color: palette.accent),
                ),
              ],
              if (_errorRaw != null && _errorRaw != _error)
                Padding(
                  padding: EdgeInsets.only(top: ogL.tokens.space(OgLSpacing.sm)),
                  child: SelectableText(
                    _errorRaw!,
                    maxLines: 4,
                    style: text.labelSmall?.copyWith(color: palette.textFaint),
                  ),
                ),
              SizedBox(height: ogL.tokens.space(OgLSpacing.md)),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存并验证'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 把登录失败翻译成"人话"。
///
/// 覆盖三类最常见失败：网络不可达、令牌无效、被限流。
/// （release 构建若缺平台网络权限，表现正是"网络不可达"。）
String _describeLoginFailure(Object error) {
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('Connection') ||
      text.contains('connection')) {
    return '网络不可达：请检查网络连接后重试。';
  }
  if (text.contains('401') || text.contains('Unauthorized')) {
    return '令牌无效或已过期：请到 GitHub 重新生成 PAT 后重试。';
  }
  if (text.contains('403') || text.contains('rate limit')) {
    return '被 GitHub 限流：请稍后再试。';
  }
  return '验证失败：$text';
}

/// 相对时间（今天 / N 天前 / 日期）。
String _formatDate(DateTime? time) {
  if (time == null) {
    return '未知';
  }
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} 小时前';
  }
  if (diff.inDays < 30) {
    return '${diff.inDays} 天前';
  }
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}