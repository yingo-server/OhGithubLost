/// OGL 页面 · 我的（账户管理）—— 账户列表 / 切换 / 移除 / 新增 / 退出 / Gist。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.4）
/// ```
/// OgLPageScaffold(标题 + "本机已接入 N 个账户" + 动作：Gist / 新增账户；下拉刷新)
/// ├ OgLSection('账户')      → OgLBox(padded:false) → 行 ×N（当前项选中 + 「当前」标签）
/// ├ OgLSection('会话')      → 当前账户与账号 ID（一眼看清"我现在是谁"）
/// ├ OgLSection('内容')      → Gist 片段
/// └ OgLSection('危险区')    → 退出登录（二次确认，说明"只删本机令牌"）
/// ```
///
/// ## 纪律
/// 四态只走 `ogLAsyncView`（没有账户 = **空态**，要给出"接入令牌"的下一步）；
/// 所有破坏性操作**先确认**；错误不静默（Banner + 重试 / 日志）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../app/async_state.dart';
import '../app/async_view.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
import 'gists_page.dart';
import 'login_page.dart';

/// 我的（账户管理）页。
class OgLProfilePage extends StatefulWidget {
  /// 创建页面。
  const OgLProfilePage({
    required this.surface,
    required this.onAccountsChanged,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 账户发生变更（切换 / 移除 / 新增 / 退出）后的回调；
  /// 由宿主刷新会话状态（决定停留在主壳还是回登录门）。
  final Future<void> Function() onAccountsChanged;

  @override
  State<OgLProfilePage> createState() => _OgLProfilePageState();
}

class _OgLProfilePageState extends State<OgLProfilePage> {
  OgLAsyncController<List<GhAccount>>? _accounts;
  String? _activeId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _accounts?.removeListener(_onChanged);
    _accounts?.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _prepare() async {
    _activeId = await widget.surface.domain.auth.activeAccountId();
    await _accountsC().loadIfNeeded();
  }

  OgLAsyncController<List<GhAccount>> _accountsC() {
    final existing = _accounts;
    if (existing != null) {
      return existing;
    }
    final controller = OgLAsyncController<List<GhAccount>>(
      label: '账户',
      isEmpty: (List<GhAccount> value) => value.isEmpty,
      loader: () async {
        final list = await widget.surface.domain.auth.accounts();
        _activeId = await widget.surface.domain.auth.activeAccountId();
        return list;
      },
    );
    controller.addListener(_onChanged);
    _accounts = controller;
    return controller;
  }

  Future<void> _refresh() async {
    await _accountsC().load();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _switchTo(GhAccount account) async {
    setState(() => _busy = true);
    try {
      await widget.surface.domain.auth.switchTo(account.id);
      OgLAppLog.instance.add('账户', '已切换到 @${account.login}');
      await _refresh();
      await widget.onAccountsChanged();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '账户',
        '切换失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换失败：$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _remove(GhAccount account, {required bool quit}) async {
    final bool confirmed = await ogLConfirmDialog(
      context,
      title: quit ? '退出登录' : '移除账户',
      message: '将从本机移除「@${account.login}」及其令牌（密文先删、元数据后删）。'
          '不会对 GitHub 上的数据产生任何影响。',
      confirmLabel: quit ? '退出登录' : '移除',
      danger: true,
    );
    if (!confirmed || !mounted) {
      return;
    }
    await widget.surface.domain.auth.removeAccount(account.id);
    OgLAppLog.instance.add('账户', '已移除 @${account.login}');
    await _refresh();
    await widget.onAccountsChanged();
  }

  Future<void> _addAccount() async {
    final OgLTheme ogL = OgLTheme.of(context);
    final NavigatorState nav = Navigator.of(context);
    final bool? ok = await nav.push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => ColoredBox(
          // 登录页自带布局；这里只给"底色 + 安全区"，不再套 Material Scaffold。
          color: ogL.palette.surface,
          child: SafeArea(
            child: OgLLoginPage(
              surface: widget.surface,
              onLoggedIn: () async {
                nav.pop(true);
              },
              onSkip: () async {
                nav.pop(false);
              },
            ),
          ),
        ),
      ),
    );
    if (ok == true && mounted) {
      await _refresh();
      await widget.onAccountsChanged();
    }
  }

  void _openGists() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => OgLGistsPage(surface: widget.surface),
      ),
    );
  }

  GhAccount? _activeAccount(List<GhAccount> list) {
    final String? id = _activeId;
    if (id == null) {
      return null;
    }
    for (final GhAccount account in list) {
      if (account.id == id) {
        return account;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final OgLAsyncController<List<GhAccount>> controller = _accountsC();

    return OgLPageScaffold(
      title: '我的',
      description: '账户与令牌（只保存在本机）',
      onRefresh: _refresh,
      actions: <Widget>[
        OgLButton(
          label: '新增账户',
          leadingIcon: OgLIconName.add,
          onPressed: _busy ? null : _addAccount,
        ),
        OgLButton(
          label: '刷新',
          variant: OgLButtonVariant.invisible,
          leadingIcon: OgLIconName.sync,
          onPressed: _refresh,
        ),
      ],
      child: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? child) {
          final OgLAsync<List<GhAccount>> state = controller.state;
          final List<GhAccount> list = state.data ?? const <GhAccount>[];
          final GhAccount? active = _activeAccount(list);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OgLSection(
                title: '账户',
                description: list.isEmpty
                    ? null
                    : '共 ${list.length} 个 · 点一行即可切换（当前会话用蓝点标出）',
                topSpacing: 0,
                actions: <Widget>[
                  if (_busy)
                    const OgLSpinner(label: '处理中…')
                  else
                    OgLButton(
                      label: '新增',
                      variant: OgLButtonVariant.invisible,
                      size: OgLButtonSize.small,
                      leadingIcon: OgLIconName.add,
                      onPressed: _addAccount,
                    ),
                ],
                child: ogLAsyncView<List<GhAccount>>(
                  state: state,
                  onRetry: _refresh,
                  errorTitle: '账户读取失败',
                  emptyIcon: OgLIconName.key,
                  emptyTitle: '还没有账户',
                  emptyBody: '接入一个 GitHub 个人访问令牌，就能浏览私有仓库、'
                      '搜索代码并提交改动；令牌只保存在本机。',
                  emptyAction: OgLButton(
                    label: '接入令牌',
                    leadingIcon: OgLIconName.key,
                    onPressed: _addAccount,
                  ),
                  skeletonLines: 3,
                  child: OgLBox(
                    padded: false,
                    child: Column(
                      children: <Widget>[
                        for (int i = 0; i < list.length; i++)
                          _AccountRow(
                            account: list[i],
                            active: list[i].id == _activeId,
                            busy: _busy,
                            showDivider: i != list.length - 1,
                            onSwitch: _switchTo,
                            onRemove: (GhAccount account) async {
                              await _remove(account, quit: false);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              OgLSection(
                title: '当前会话',
                description: 'github.com 上"你是谁"由这里的账户决定',
                child: OgLBox(
                  padded: false,
                  child: Column(
                    children: <Widget>[
                      OgLActionRow(
                        leading: OgLIcon(
                          name: OgLIconName.key,
                          size: tokens.iconSize(base: 20),
                          color: ogL.palette.textDim,
                        ),
                        title: active == null
                            ? '未选择账户'
                            : '@${active.login}',
                        subtitle: active == null
                            ? '游客模式：只能浏览公开内容'
                            : '账号 ID：${active.id}',
                        trailing: active == null
                            ? null
                            : const OgLLabel(
                                text: '使用中',
                                variant: OgLLabelVariant.success,
                              ),
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
              ),
              OgLSection(
                title: '内容',
                child: OgLBox(
                  padded: false,
                  child: OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.code,
                      size: tokens.iconSize(base: 20),
                      color: ogL.palette.textDim,
                    ),
                    title: 'Gist 片段',
                    subtitle: '查看 / 新建代码片段（需要登录）',
                    showChevron: true,
                    onTap: _openGists,
                  ),
                ),
              ),
              OgLSection(
                title: '危险区',
                description: '这里的操作只影响本机保存的令牌',
                child: OgLBox(
                  padded: false,
                  child: OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.warning,
                      size: tokens.iconSize(base: 20),
                      color: ogL.palette.danger,
                    ),
                    title: '退出登录',
                    subtitle: active == null
                        ? '当前没有可退出的账户'
                        : '移除 @${active.login} 在本机保存的令牌（会先二次确认）',
                    trailing: OgLButton(
                      label: '退出登录',
                      variant: OgLButtonVariant.danger,
                      size: OgLButtonSize.small,
                      onPressed: active == null || _busy
                          ? null
                          : () async {
                              await _remove(active, quit: true);
                            },
                    ),
                  ),
                ),
              ),
              if (state.softError != null) ...<Widget>[
                SizedBox(height: tokens.space(OgLSpacing.md)),
                OgLBanner(
                  variant: OgLBannerVariant.warning,
                  text: state.softError!,
                ),
              ],
              SizedBox(height: tokens.space(OgLSpacing.md)),
              Text(
                '提示：令牌只保存在本机安全存储（Android Keystore / iOS Keychain）；'
                '换机或重装需要重新接入。',
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

/// 账户行：当前账户高亮 + 「当前」标签；其它账户可一键切换；都可移除（带确认）。
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.active,
    required this.busy,
    required this.showDivider,
    required this.onSwitch,
    required this.onRemove,
  });

  final GhAccount account;
  final bool active;
  final bool busy;
  final bool showDivider;
  final Future<void> Function(GhAccount account) onSwitch;
  final Future<void> Function(GhAccount account) onRemove;

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final String? name = account.name;
    return OgLActionRow(
      leading: OgLIcon(
        name: OgLIconName.key,
        size: ogL.tokens.iconSize(base: 20),
        color: active ? ogL.palette.accent : ogL.palette.textDim,
      ),
      title: '@${account.login}',
      subtitle: name == null || name.isEmpty
          ? '账号 ID：${account.id}'
          : '$name · 账号 ID：${account.id}',
      selected: active,
      showDivider: showDivider,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (active)
            const OgLLabel(text: '当前', variant: OgLLabelVariant.success)
          else
            OgLButton(
              label: '切换',
              variant: OgLButtonVariant.invisible,
              size: OgLButtonSize.small,
              onPressed: busy
                  ? null
                  : () async {
                      await onSwitch(account);
                    },
            ),
          OgLButton(
            label: '移除',
            variant: OgLButtonVariant.danger,
            size: OgLButtonSize.small,
            onPressed: busy
                ? null
                : () async {
                    await onRemove(account);
                  },
          ),
        ],
      ),
      onTap: active || busy
          ? null
          : () async {
              await onSwitch(account);
            },
    );
  }
}