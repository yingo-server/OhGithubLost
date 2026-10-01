/// OGL 页面 · 首页（Dashboard）—— 全客户端的信息入口：
/// 账户摘要 + 我的仓库 + 星标仓库（数据全部来自 `domain.gh`）。
///
/// 约束与旧页面一致：无 `MediaQuery` 宽度判断、无 `Colors.xxx`、
/// 无 `Icons.xxx`；视觉全部走 OGL Kit + 主题令牌。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../../domain/gh/gh_models.dart';
import '../app/async_state.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

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
    final GhAccount? account = await widget.surface.domain.auth.activeAccount();
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

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    if (!_bootChecked) {
      return const Center(child: OgLSpinner(label: '准备中…'));
    }
    final account = _account;
    return ListView(
      padding: EdgeInsets.symmetric(
        vertical: ogL.tokens.space(OgLSpacing.lg),
      ),
      children: <Widget>[
        OgLPageHeader(
          title: '首页',
          description: account == null
              ? '未登录'
              : '${account.name ?? account.login} · @${account.login}',
          actions: <Widget>[
            OgLButton(
              label: '刷新',
              variant: OgLButtonVariant.invisible,
              leadingIcon: OgLIconName.sync,
              onPressed: account == null ? null : _refreshAll,
            ),
          ],
        ),
        if (account == null)
          const OgLBanner(
            variant: OgLBannerVariant.warning,
            title: '未登录',
            text: '接入个人访问令牌后，这里会显示你的仓库与星标。',
          ),
        if (account != null) ...<Widget>[
          _Section(
            title: '我的仓库',
            ogL: ogL,
            child: _RepoSection(
              controller: _reposC(),
              onRetry: _refreshAll,
              emptyText: '还没有仓库，先在 GitHub 创建一个吧。',
            ),
          ),
          SizedBox(height: ogL.tokens.space(OgLSpacing.xl)),
          _Section(
            title: '星标仓库',
            ogL: ogL,
            child: _RepoSection(
              controller: _starredC(),
              onRetry: _refreshAll,
              emptyText: '还没有星标的仓库。',
            ),
          ),
        ],
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.ogL, required this.child});

  final String title;
  final OgLTheme ogL;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.only(
              top: ogL.tokens.space(OgLSpacing.md),
              bottom: ogL.tokens.space(OgLSpacing.sm),
            ),
            child: Text(
              title,
              style: TextStyle(
                fontSize:
                    ogL.tokens.fontSize(const OgLTypeScale.standard().title),
                fontWeight: FontWeight.w600,
                color: ogL.palette.text,
              ),
            ),
          ),
          child,
        ],
      );
}

class _RepoSection extends StatelessWidget {
  const _RepoSection({
    required this.controller,
    required this.onRetry,
    required this.emptyText,
  });

  final OgLAsyncController<List<GhRepo>> controller;
  final Future<void> Function() onRetry;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? child) {
        final state = controller.state;
        final data = state.data;
        if (data == null &&
            (state.phase == OgLAsyncPhase.idle ||
                state.phase == OgLAsyncPhase.loading)) {
          return const OgLSkeletonText(lines: 4);
        }
        if (data == null && state.message != null) {
          return OgLBanner(
            variant: OgLBannerVariant.danger,
            title: '加载失败',
            text: state.message!,
            actions: <Widget>[
              OgLButton(
                label: '重试',
                size: OgLButtonSize.small,
                onPressed: () async {
                  await onRetry();
                },
              ),
            ],
          );
        }
        if (state.phase == OgLAsyncPhase.empty ||
            (data != null && data.isEmpty)) {
          return Text(
            emptyText,
            style: TextStyle(
              fontSize:
                  ogL.tokens.fontSize(const OgLTypeScale.standard().body),
              color: ogL.palette.textDim,
            ),
          );
        }
        final list = data ?? const <GhRepo>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (state.refreshError != null)
              Padding(
                padding: EdgeInsets.only(
                  bottom: ogL.tokens.space(OgLSpacing.sm),
                ),
                child: OgLBanner(
                  variant: OgLBannerVariant.warning,
                  text: '刷新失败：${state.refreshError}',
                ),
              ),
            for (final repo in list) _RepoRow(repo: repo),
          ],
        );
      },
    );
  }
}

class _RepoRow extends StatelessWidget {
  const _RepoRow({required this.repo});

  final GhRepo repo;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final meta = <String>[
      repo.isPrivate ? '私有' : '公开',
      if (repo.language != null) repo.language!,
      '★ ${repo.stars}',
    ].join(' · ');
    final description = repo.description;
    return OgLActionRow(
      leading: Icon(
        ogL.icon(repo.isFork ? OgLIconName.fork : OgLIconName.repository),
        size: ogL.tokens.iconSize(base: 20),
        color: ogL.palette.textDim,
      ),
      title: repo.fullName,
      subtitle: description == null || description.isEmpty
          ? meta
          : '$meta — $description',
      trailing: repo.isArchived
          ? const OgLLabel(text: '归档', variant: OgLLabelVariant.attention)
          : null,
    );
  }
}