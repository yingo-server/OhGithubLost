/// OGL 页面 · 登录（令牌向导）—— 全客户端的入口门。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.9）
/// ```
/// OgLPageScaffold('接入 GitHub' + 说明 + 游客模式入口)
/// ├ OgLBanner(info) 令牌安全：只进本机保险库
/// ├ OgLSection('粘贴令牌') → OgLBox → 密文输入框（回车即验证）+ 显示/隐藏 + 主操作
/// ├ OgLSection('向导进度') → OgLBox(padded:false) → 四步（暂存 / 验证 / 转正 / 回读）
/// └ OgLSection('怎么拿令牌') → OgLBox(padded:false) → 三步文字指引（可照抄）
/// ```
///
/// ## 四步为什么必须可见
/// 登录会依次做：① 暂存待验证账户 → ② `GET /user` 验证令牌 →
/// ③ 转正并切换 → ④ **保险库回读自检**（防"存进去读不出来"的往返损坏）。
/// 其中任何一步失败都会让"看起来登上了、实际没有令牌"，
/// 因此每一步都摊开显示状态，失败时错误原样给用户看（并写日志）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 登录页。
class OgLLoginPage extends StatefulWidget {
  /// 创建登录页。
  const OgLLoginPage({
    required this.surface,
    required this.onLoggedIn,
    this.onSkip,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 登录成功回调（由宿主决定去留）。
  final Future<void> Function() onLoggedIn;

  /// 可选：游客模式（跳过登录）。
  final Future<void> Function()? onSkip;

  @override
  State<OgLLoginPage> createState() => _OgLLoginPageState();
}

class _OgLLoginPageState extends State<OgLLoginPage> {
  final TextEditingController _input = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String _phase = '';

  /// 向导进度：0 = 还没开始；1..4 = 当前正在做的第几步；5 = 全部完成。
  int _step = 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) {
      return; // 回车连按 / 与按钮互斥：防双重提交
    }
    final String raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请先粘贴个人访问令牌');
      return;
    }
    final GhToken token = GhToken(raw);
    if (!token.looksValid) {
      setState(
        () => _error = '形态不像 GitHub 令牌（应以 ghp_ / gho_ / ghu_ / github_pat_ 等开头）',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _phase = '正在验证…';
      _step = 1;
    });

    final auth = widget.surface.domain.auth;
    final api = widget.surface.domain.api;
    final String pendingId = 'pending-${DateTime.now().millisecondsSinceEpoch}';
    try {
      OgLAppLog.instance.add('登录', '1/4 暂存待验证账户（$pendingId）');
      await auth.saveAccount(GhAccount(id: pendingId, login: '（待验证）'), token);
      await auth.switchTo(pendingId);

      if (mounted) {
        setState(() {
          _step = 2;
          _phase = '正在验证令牌（GET /user）…';
        });
      }
      OgLAppLog.instance.add('登录', '2/4 验证令牌（GET /user）…');
      final me = await api.currentUser();
      OgLAppLog.instance.add('登录', '3/4 验证成功：@${me.login}');

      if (mounted) {
        setState(() {
          _step = 3;
          _phase = '正在转正并切换账户…';
        });
      }
      await auth.removeAccount(pendingId);
      await auth.saveAccount(
        GhAccount(id: 'user-${me.id}', login: me.login, name: me.name),
        token,
      );
      await auth.switchTo('user-${me.id}');

      if (mounted) {
        setState(() {
          _step = 4;
          _phase = '正在回读保险库（自检）…';
        });
      }
      final readBack = await auth.activeToken();
      OgLAppLog.instance.add(
        '登录',
        '4/4 保险库回读：${readBack?.masked ?? "读取失败（令牌可能未落库）"}',
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _step = 5;
        _phase = '登录完成，正在进入…';
      });
      OgLAppLog.instance.add('登录', '完成：@${me.login}');
      await widget.onLoggedIn();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '登录',
        '失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      // ★ 清理"待验证"半成品：若失败时激活的仍是占位账户，
      // 连同它的令牌一起删除——否则下次启动会把「（待验证）」当成
      // "已登录"（跳过登录门、每个请求 401，用户看到的是"登录状态坏了"）。
      try {
        if (await auth.activeAccountId() == pendingId) {
          await auth.removeAccount(pendingId);
        }
      } catch (cleanupError) {
        OgLAppLog.instance.add(
          '登录',
          '清理待验证账户失败：$cleanupError',
          severity: OgLNoticeSeverity.warning,
        );
      }
      if (mounted) {
        setState(() {
          _error = '验证失败：$error';
          _phase = '';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      } else {
        _busy = false;
      }
    }
  }

  /// 四步中的一行：已完成 / 进行中 / 待做。
  Widget _stepRow({
    required OgLTheme ogL,
    required OgLTokens tokens,
    required int index,
    required String title,
    required String detail,
    required bool last,
  }) {
    final bool done = _step > index;
    final bool current = _step == index;
    return OgLActionRow(
      leading: OgLIcon(
        name: done
            ? OgLIconName.success
            : current
                ? OgLIconName.clock
                : OgLIconName.info,
        size: tokens.iconSize(base: 18),
        color: done
            ? ogL.palette.success
            : current
                ? ogL.palette.accent
                : ogL.palette.textFaint,
      ),
      title: '$index/4 $title',
      subtitle: detail,
      trailing: OgLLabel(
        text: done ? '完成' : (current ? '进行中' : '待做'),
        variant: done
            ? OgLLabelVariant.success
            : (current ? OgLLabelVariant.accent : OgLLabelVariant.neutral),
      ),
      dense: true,
      showDivider: !last,
    );
  }

  @override
  Widget build(BuildContext context) {
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;
    final OgLTypeScale scale = const OgLTypeScale.standard();
    final Future<void> Function()? skip = widget.onSkip;

    return OgLPageScaffold(
      title: '接入 GitHub',
      description: 'GitHub 第三方客户端 · 用个人访问令牌登录',
      actions: <Widget>[
        if (skip != null)
          OgLButton(
            label: '先逛逛（游客模式）',
            variant: OgLButtonVariant.invisible,
            leadingIcon: OgLIconName.search,
            onPressed: _busy
                ? null
                : () async {
                    await skip();
                  },
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const OgLBanner(
            variant: OgLBannerVariant.info,
            title: '令牌安全',
            text: '令牌只保存在本机安全保险库（Android Keystore / iOS Keychain / '
                '桌面秘密服务），请求只会发往 api.github.com，不经过任何第三方服务器。',
          ),
          OgLSection(
            title: '粘贴令牌',
            description: '回车即验证；界面永远只显示脱敏形态',
            child: OgLBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  OgLTextField(
                    controller: _input,
                    label: '个人访问令牌（Personal Access Token）',
                    hint: 'ghp_… / github_pat_…',
                    obscure: _obscure,
                    leadingIcon: OgLIconName.key,
                    enabled: !_busy,
                    onSubmitted: (String _) async {
                      await _login();
                    },
                    onChanged: (String _) {
                      if (_error != null) {
                        setState(() => _error = null);
                      }
                    },
                  ),
                  SizedBox(height: tokens.space(OgLSpacing.sm)),
                  Row(
                    children: <Widget>[
                      OgLButton(
                        label: _obscure ? '显示令牌' : '隐藏令牌',
                        variant: OgLButtonVariant.invisible,
                        size: OgLButtonSize.small,
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      const Spacer(),
                      OgLButton(
                        label: _busy ? '验证中…' : '验证并登录',
                        variant: OgLButtonVariant.primary,
                        leadingIcon: OgLIconName.shield,
                        loading: _busy,
                        onPressed: _busy ? null : _login,
                      ),
                    ],
                  ),
                  if (_error != null) ...<Widget>[
                    SizedBox(height: tokens.space(OgLSpacing.sm)),
                    OgLBanner(
                      variant: OgLBannerVariant.danger,
                      title: '登录失败',
                      text: '$_error\n（详细原因已写入应用日志，可在「设置 → 关于」复制）',
                    ),
                  ],
                  if (_phase.isNotEmpty) ...<Widget>[
                    SizedBox(height: tokens.space(OgLSpacing.sm)),
                    Text(
                      _phase,
                      style: TextStyle(
                        fontSize: tokens.fontSize(scale.label),
                        color: ogL.palette.textDim,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          OgLSection(
            title: '向导进度',
            description: '每一步都可见 —— 不会出现"看起来登上了、实际没令牌"',
            child: OgLBox(
              padded: false,
              child: Column(
                children: <Widget>[
                  _stepRow(
                    ogL: ogL,
                    tokens: tokens,
                    index: 1,
                    title: '暂存待验证账户',
                    detail: '先写入一个占位账户，验证通过再转正',
                    last: false,
                  ),
                  _stepRow(
                    ogL: ogL,
                    tokens: tokens,
                    index: 2,
                    title: '验证令牌（GET /user）',
                    detail: '确认令牌有效，并读出你的登录名',
                    last: false,
                  ),
                  _stepRow(
                    ogL: ogL,
                    tokens: tokens,
                    index: 3,
                    title: '转正并切换账户',
                    detail: '用真实账号 ID 覆盖占位账户，并切到它',
                    last: false,
                  ),
                  _stepRow(
                    ogL: ogL,
                    tokens: tokens,
                    index: 4,
                    title: '保险库回读自检',
                    detail: '把令牌读回来核对（防"存进去读不出来"）',
                    last: true,
                  ),
                ],
              ),
            ),
          ),
          OgLSection(
            title: '怎么拿令牌',
            child: OgLBox(
              padded: false,
              child: Column(
                children: <Widget>[
                  OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.info,
                      size: 18,
                      color: ogL.palette.textDim,
                    ),
                    title: '网页端 → Settings',
                    subtitle: '右上角头像 → Settings',
                    dense: true,
                  ),
                  OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.info,
                      size: 18,
                      color: ogL.palette.textDim,
                    ),
                    title: 'Developer settings',
                    subtitle: 'Settings 最下方 → Developer settings',
                    dense: true,
                  ),
                  OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.info,
                      size: 18,
                      color: ogL.palette.textDim,
                    ),
                    title: 'Personal access tokens',
                    subtitle: '新建令牌；权限建议先只勾 repo（只读起步）',
                    dense: true,
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}