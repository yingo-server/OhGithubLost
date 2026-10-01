/// OGL 页面 · 我的（账户管理）—— 账户列表 / 切换 / 移除 / 新增 / 退出。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../app/async_state.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';
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
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  Future<void> _remove(GhAccount account) async {
    final confirmed = await ogLConfirmDialog(
      context,
      title: '移除账户',
      message: '将从本机移除「@${account.login}」及其令牌（密文先删、元数据后删）。'
          '不会对 GitHub 上的数据产生任何影响。',
      confirmLabel: '移除',
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
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) => Scaffold(
          body: SafeArea(
            child: OgLLoginPage(
              surface: widget.surface,
              onLoggedIn: () async {
                Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final state = _accountsC().state;
    final list = state.data ?? const <GhAccount>[];

    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        OgLPageHeader(
          title: '我的',
          description: '本机已接入 ${list.length} 个账户',
          actions: <Widget>[
            OgLButton(
              label: '刷新',
              variant: OgLButtonVariant.invisible,
              leadingIcon: OgLIconName.sync,
              onPressed: _refresh,
            ),
          ],
        ),
        if (state.data == null && state.message != null)
          OgLBanner(
            variant: OgLBannerVariant.danger,
            title: '账户读取失败',
            text: state.message!,
            actions: <Widget>[
              OgLButton(
                label: '重试',
                size: OgLButtonSize.small,
                onPressed: () async {
                  await _refresh();
                },
              ),
            ],
          )
        else if (state.data == null)
          const OgLSkeletonText(lines: 3)
        else if (list.isEmpty)
          const OgLBanner(
            variant: OgLBannerVariant.warning,
            title: '还没有账户',
            text: '点击下方「新增账户」接入第一个 GitHub 令牌。',
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (final account in list)
                OgLActionRow(
                  leading: Icon(
                    ogL.icon(OgLIconName.key),
                    size: tokens.iconSize(base: 20),
                    color: account.id == _activeId
                        ? ogL.palette.accent
                        : ogL.palette.textDim,
                  ),
                  title: '@${account.login}',
                  subtitle: account.name == null
                      ? account.id
                      : '${account.name} · ${account.id}',
                  selected: account.id == _activeId,
                  trailing: OgLButton(
                    label: '移除',
                    variant: OgLButtonVariant.invisible,
                    size: OgLButtonSize.small,
                    onPressed: _busy ? null : () async {
                      await _remove(account);
                    },
                  ),
                  onTap: account.id == _activeId || _busy
                      ? null
                      : () async {
                          await _switchTo(account);
                        },
                ),
            ],
          ),
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        OgLButton(
          label: '新增账户',
          variant: OgLButtonVariant.primary,
          leadingIcon: OgLIconName.add,
          onPressed: _busy ? null : _addAccount,
        ),
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        Text(
          '当前会话：${_activeId ?? "（无）"}',
          style: TextStyle(
            fontSize: tokens.fontSize(scale.label),
            color: ogL.palette.textFaint,
          ),
        ),
      ],
    );
  }
}