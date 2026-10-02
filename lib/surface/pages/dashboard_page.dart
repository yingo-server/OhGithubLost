/// OGL 页面 · 首页（Dashboard）—— 全客户端的信息入口。
///
/// ## 布局（严格按 `docs/UI_PAGES_PLAN.md` §2.2）
/// ```
/// OgLPageScaffold(标题 + 账户摘要 + 动作：新建仓库 / 刷新；支持下拉刷新)
/// ├ [未登录] OgLBanner(warning, action: 接入令牌) + 「接下来」行式引导
/// └ [已登录] OgLSegmented(我的仓库 | 星标仓库)
///            └ OgLSection(计数说明) → OgLBox(padded:false) → 行 ×N
/// ```
///
/// ## 纪律
/// - 四态**只走** `ogLAsyncView`（唯一映射点）：空 ≠ 载 ≠ 错（W7 教训）；
/// - 视觉全部令牌化 + 自绘矢量图标；不写 `Colors.*` / `Icons.*` / 字面量间距；
/// - 行只用 `OgLActionRow`，列表由 `OgLBox(padded:false)` 包裹（行自带发丝分割线）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
import '../app/async_view.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'login_page.dart';
import 'new_repo_page.dart';
import 'repo_page.dart';

/// 首页列表范围。
enum _DashTab {
  /// 我的仓库（含私有、协作）。
  mine,

  /// 我星标（收藏）的仓库。
  starred,
}

/// 首页。
class OgLDashboardPage extends StatefulWidget {
  /// 创建首页。
  const OgLDashboardPage({required this.surface, super.key});

  /// 表面桥（业务数据一律经 `surface.domain` 取）。
  final SurfaceBridge surface;

  @override
  State<OgLDashboardPage> createState() => _OgLDashboardPageState();
}

class _OgLDashboardPageState extends State<OgLDashboardPage> {
  OgLAsyncController<List<GhRepo>>? _repos;
  OgLAsyncController<List<GhRepo>>? _starred;
  GhAccount? _account;
  bool _bootChecked = false;
  _DashTab _tab = _DashTab.mine;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _repos?.removeListener(_onChanged);
    _repos?.dispose();
    _starred?.removeListener(_onChanged);
    _starred?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _prepare() async {
    GhAccount? account;
    try {
      account = await widget.surface.domain.auth.activeAccount();
    } catch (error) {
      // 存储读取失败不能把首页卡在"启动中"骨架：按未登录处理并留痕。
      OgLAppLog.instance.add(
        '首页',
        '账户读取失败（按未登录处理）：$error',
        severity: OgLNoticeSeverity.warning,
      );
      account = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _account = account;
      _bootChecked = true;
    });
    if (account != null) {
      await _reposC().loadIfNeeded();
      await _starredC().loadIfNeeded();
    }
  }

  OgLAsyncController<List<GhRepo>> _reposC() {
    final existing = _repos;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhRepo>>(
      label: '我的仓库',
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      loader: () async {
        OgLAppLog.instance.add('首页', '拉取我的仓库…');
        try {
          final list = await widget.surface.domain.api.myRepos(perPage: 100);
          OgLAppLog.instance.add('首页', '我的仓库：${list.length} 个');
          return list;
        } catch (error, stackTrace) {
          OgLAppLog.instance.add(
            '首页',
            '我的仓库拉取失败（原始异常）：$error\n$stackTrace',
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

  OgLAsyncController<List<GhRepo>> _starredC() {
    final existing = _starred;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhRepo>>(
      label: '星标仓库',
      isEmpty: (List<GhRepo> value) => value.isEmpty,
      loader: () async {
        OgLAppLog.instance.add('首页', '拉取星标仓库…');
        try {
          final list = await widget.surface.domain.api.starredRepos(perPage: 100);
          OgLAppLog.instance.add('首页', '星标仓库：${list.length} 个');
          return list;
        } catch (error, stackTrace) {
          OgLAppLog.instance.add(
            '首页',
            '星标仓库拉取失败（原始异常）：$error\n$stackTrace',
            severity: OgLNoticeSeverity.critical,
          );
          rethrow;
        }
      },
    );
    controller.addListener(_onChanged);
    _starred = controller;
    return controller;
  }

  Future<void> _refreshAll() async {
    await _reposC().load();
    await _starredC().load();
  }

  void _openRepo(GhRepo repo) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            OgLRepoPage(surface: widget.surface, repo: repo),
      ),
    );
  }

  Future<void> _createRepo() async {
    final created = await Navigator.of(context).push<GhRepo>(
      MaterialPageRoute<GhRepo>(
        builder: (BuildContext context) =>
            OgLNewRepoPage(surface: widget.surface),
      ),
    );
    if (created != null && mounted) {
      await _refreshAll();
      _openRepo(created);
    }
  }

  Future<void> _openLogin() async {
    // 先把 Navigator 抓在手里：回调里 await 之后不再碰 `context`（lint: use_build_context_synchronously）。
    final NavigatorState nav = Navigator.of(context);
    await nav.push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OgLLoginPage(
          surface: widget.surface,
          onLoggedIn: () async {
            // 登录页把"登录成功后去哪"交给宿主：这里刷新首页并退回首页。
            await _prepare();
            nav.pop();
          },
        ),
      ),
    );
    if (mounted) {
      await _prepare();
    }
  }

  /// 小节说明：把"有多少"讲清楚（而不是让用户自己数）。
  String _describe(OgLAsync<List<GhRepo>> state) {
    final List<GhRepo>? data = state.data;
    if (state.isFirstLoading) {
      return '读取中…';
    }
    if (state.failureMessage != null) {
      return '读取失败（下方可重试）';
    }
    if (state.isEmptyResult || data == null) {
      return '一个都还没有';
    }
    final int priv = data.where((GhRepo repo) => repo.isPrivate).length;
    return '共 ${data.length} 个${priv > 0 ? ' · 其中私有 $priv 个' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    if (!_bootChecked) {
      return const OgLPageScaffold(
        title: '首页',
        child: OgLSkeletonText(lines: 6),
      );
    }
    final GhAccount? account = _account;
    // 显示名与登录名相同（常见）时不重复展示——避免"某某 · @某某"的蠢观感。
    final String accountLine = account == null
        ? '未登录 · 只读公开内容'
        : (account.name == null ||
                account.name!.isEmpty ||
                account.name == account.login)
            ? '@${account.login}'
            : '${account.name} · @${account.login}';
    final bool mine = _tab == _DashTab.mine;
    final OgLAsyncController<List<GhRepo>> controller =
        mine ? _reposC() : _starredC();

    return OgLPageScaffold(
      title: '首页',
      description: accountLine,
      onRefresh: account == null ? null : _refreshAll,
      actions: <Widget>[
        OgLButton(
          label: '新建仓库',
          // 主操作用 primary（GitHub 的 New 按钮语义）：与"刷新"拉开主次。
          variant: OgLButtonVariant.primary,
          leadingIcon: OgLIconName.add,
          onPressed: account == null ? null : _createRepo,
        ),
        OgLButton(
          label: '刷新',
          variant: OgLButtonVariant.invisible,
          leadingIcon: OgLIconName.sync,
          // 刷新时给可见反馈（并防重复点击）：点的瞬间就能看到"在转"。
          loading:
              account != null && (_reposC().isBusy || _starredC().isBusy),
          onPressed: account == null ? null : _refreshAll,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (account == null) ...<Widget>[
            OgLBanner(
              variant: OgLBannerVariant.warning,
              title: '未登录',
              text: '接入个人访问令牌后，这里会显示你的仓库与星标；'
                  '令牌只保存在本机（可在设置 → 账户里随时移除）。',
              actions: <Widget>[
                OgLButton(
                  label: '接入令牌',
                  leadingIcon: OgLIconName.key,
                  onPressed: _openLogin,
                ),
              ],
            ),
            OgLSection(
              title: '接下来',
              description: '不需要账号也能用的部分',
              child: OgLBox(
                padded: false,
                child: Column(
                  children: <Widget>[
                    OgLActionRow(
                      leading: OgLIcon(
                        name: OgLIconName.search,
                        size: 20,
                        color: ogL.palette.textDim,
                      ),
                      title: '搜索公开仓库与代码',
                      subtitle: '到「搜索」页输入关键字即可，无需登录',
                    ),
                    OgLActionRow(
                      leading: OgLIcon(
                        name: OgLIconName.shield,
                        size: 20,
                        color: ogL.palette.textDim,
                      ),
                      title: '只读浏览',
                      subtitle: '未登录时不会发起任何写入操作',
                      showDivider: false,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...<Widget>[
            Row(
              children: <Widget>[
                OgLSegmented<_DashTab>(
                  items: const <OgLSegmentedItem<_DashTab>>[
                    OgLSegmentedItem<_DashTab>(
                      value: _DashTab.mine,
                      label: '我的仓库',
                    ),
                    OgLSegmentedItem<_DashTab>(
                      value: _DashTab.starred,
                      label: '星标仓库',
                    ),
                  ],
                  value: _tab,
                  onChanged: (_DashTab value) => setState(() => _tab = value),
                ),
                SizedBox(width: ogL.tokens.space(OgLSpacing.sm)),
                Expanded(
                  child: Text(
                    _describe(controller.state),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: ogL.tokens.fontSize(
                        const OgLTypeScale.standard().label,
                      ),
                      color: ogL.palette.textDim,
                    ),
                  ),
                ),
              ],
            ),
            OgLSection(
              title: mine ? '我的仓库' : '星标仓库',
              description: mine
                  ? '含私有与协作仓库；点一行进入仓库页'
                  : '你在 GitHub 上点过 ★ 的公开项目',
              topSpacing: OgLSpacing.md,
              child: _RepoList(
                controller: controller,
                mine: mine,
                onRetry: _refreshAll,
                onOpen: _openRepo,
                onCreate: _createRepo,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一排仓库（四态由 `ogLAsyncView` 统一决定）。
class _RepoList extends StatelessWidget {
  const _RepoList({
    required this.controller,
    required this.mine,
    required this.onRetry,
    required this.onOpen,
    required this.onCreate,
  });

  final OgLAsyncController<List<GhRepo>> controller;
  final bool mine;
  final Future<void> Function() onRetry;
  final void Function(GhRepo repo) onOpen;
  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? child) {
          final OgLAsync<List<GhRepo>> state = controller.state;
          final List<GhRepo> list = state.data ?? const <GhRepo>[];
          return ogLAsyncView<List<GhRepo>>(
            state: state,
            onRetry: onRetry,
            errorTitle: mine ? '我的仓库读取失败' : '星标仓库读取失败',
            emptyIcon: mine ? OgLIconName.repository : OgLIconName.star,
            emptyTitle: mine ? '还没有仓库' : '还没有星标',
            emptyBody: mine
                ? '可以在这里直接新建一个：公开、私有都行。'
                : '在仓库页点 ★ 收藏的项目会出现在这里。',
            emptyAction: mine
                ? OgLButton(
                    label: '新建仓库',
                    leadingIcon: OgLIconName.add,
                    onPressed: () async {
                      await onCreate();
                    },
                  )
                : null,
            skeletonLines: 5,
            child: OgLBox(
              padded: false,
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < list.length; i++)
                    _RepoRow(
                      repo: list[i],
                      showDivider: i != list.length - 1,
                      onOpen: onOpen,
                    ),
                ],
              ),
            ),
          );
        },
      );
}

/// 仓库行。
class _RepoRow extends StatelessWidget {
  const _RepoRow({
    required this.repo,
    required this.onOpen,
    required this.showDivider,
  });

  final GhRepo repo;
  final void Function(GhRepo repo) onOpen;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final List<String> meta = <String>[
      if (repo.language != null && repo.language!.isNotEmpty) repo.language!,
      '★ ${repo.stars}',
      if (repo.forks > 0) 'Fork ${repo.forks}',
    ];
    final String? description = repo.description;
    return OgLActionRow(
      leading: OgLIcon(
        name: repo.isFork ? OgLIconName.fork : OgLIconName.repository,
        size: ogL.tokens.iconSize(base: 20),
        color: ogL.palette.textDim,
      ),
      title: repo.fullName,
      subtitle: description == null || description.isEmpty
          ? meta.join(' · ')
          : '${meta.join(' · ')} — $description',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (repo.isPrivate)
            const OgLLabel(text: '私有', variant: OgLLabelVariant.neutral),
          if (repo.isArchived) ...<Widget>[
            SizedBox(width: ogL.tokens.space(OgLSpacing.xs)),
            const OgLLabel(text: '归档', variant: OgLLabelVariant.attention),
          ],
        ],
      ),
      showChevron: true,
      showDivider: showDivider,
      onTap: () => onOpen(repo),
    );
  }
}