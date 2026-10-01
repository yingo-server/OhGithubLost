/// OGL 页面 · 登录（令牌向导）—— 全客户端的入口门。
///
/// 流程对齐旧向导并升级为 Kit 外观：
/// 1) 暂存"待验证"账户 → 2) 以该令牌验证 GET /user → 3) 转正并切换 →
/// 4) 保险库回读自检（防"存进去读不出来"的往返损坏）。
///
/// 安全：令牌只进 L1 安全保险库；界面永远只显示脱敏形态。
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

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final raw = _input.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = '请先粘贴个人访问令牌');
      return;
    }
    final token = GhToken(raw);
    if (!token.looksValid) {
      setState(
        () => _error = '形态不像 GitHub 令牌（应以 ghp_ / gho_ / github_pat_ 开头）',
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _phase = '正在验证…';
    });

    final auth = widget.surface.domain.auth;
    final api = widget.surface.domain.api;
    final pendingId = 'pending-${DateTime.now().millisecondsSinceEpoch}';
    try {
      OgLAppLog.instance.add('登录', '1/4 暂存待验证账户（$pendingId）');
      await auth.saveAccount(GhAccount(id: pendingId, login: '（待验证）'), token);
      await auth.switchTo(pendingId);

      if (mounted) {
        setState(() => _phase = '正在验证令牌（GET /user）…');
      }
      OgLAppLog.instance.add('登录', '2/4 验证令牌（GET /user）…');
      final me = await api.currentUser();
      OgLAppLog.instance.add('登录', '3/4 验证成功：@${me.login}');

      await auth.removeAccount(pendingId);
      await auth.saveAccount(
        GhAccount(id: 'user-${me.id}', login: me.login, name: me.name),
        token,
      );
      await auth.switchTo('user-${me.id}');
      final readBack = await auth.activeToken();
      OgLAppLog.instance.add(
        '登录',
        '4/4 保险库回读：${readBack?.masked ?? "读取失败（令牌可能未落库）"}',
      );

      if (!mounted) {
        return;
      }
      setState(() => _phase = '登录完成，正在进入…');
      OgLAppLog.instance.add('登录', '完成：@${me.login}');
      await widget.onLoggedIn();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '登录',
        '失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
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

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final tokens = ogL.tokens;
    final scale = const OgLTypeScale.standard();
    final skip = widget.onSkip;

    return ListView(
      padding: EdgeInsets.symmetric(
        vertical: tokens.space(OgLSpacing.xl),
      ),
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              ogL.icon(OgLIconName.code),
              color: ogL.palette.accent,
              size: tokens.iconSize(base: 24),
            ),
            SizedBox(width: tokens.space(OgLSpacing.sm)),
            Text(
              'OhGithubLost',
              style: TextStyle(
                fontSize: tokens.fontSize(scale.title),
                fontWeight: FontWeight.w600,
                color: ogL.palette.text,
              ),
            ),
          ],
        ),
        SizedBox(height: tokens.space(OgLSpacing.xxs)),
        Text(
          'GitHub 第三方客户端 · 接入你的访问令牌开始使用',
          style: TextStyle(
            fontSize: tokens.fontSize(scale.label),
            color: ogL.palette.textDim,
          ),
        ),
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        const OgLBanner(
          variant: OgLBannerVariant.info,
          title: '令牌安全',
          text: '令牌只保存在本机安全保险库（KeyStore 等平台机制），'
              '请求只会发往 api.github.com，不会经过任何第三方服务器。',
        ),
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        OgLTextField(
          controller: _input,
          label: '个人访问令牌（Personal Access Token）',
          hint: 'ghp_…',
          obscure: _obscure,
          leadingIcon: OgLIconName.key,
          enabled: !_busy,
          onChanged: (String _) {
            if (_error != null) {
              setState(() => _error = null);
            }
          },
        ),
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        OgLButton(
          label: _obscure ? '显示令牌' : '隐藏令牌',
          variant: OgLButtonVariant.invisible,
          size: OgLButtonSize.small,
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
        if (_error != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.sm)),
          OgLBanner(variant: OgLBannerVariant.danger, text: _error!),
        ],
        SizedBox(height: tokens.space(OgLSpacing.md)),
        OgLButton(
          label: _busy ? '验证中…' : '验证并登录',
          variant: OgLButtonVariant.primary,
          leadingIcon: OgLIconName.shield,
          loading: _busy,
          onPressed: _login,
        ),
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
        if (skip != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.lg)),
          OgLButton(
            label: '先逛逛（游客模式）',
            variant: OgLButtonVariant.invisible,
            size: OgLButtonSize.small,
            onPressed: () async {
              await skip();
            },
          ),
        ],
        SizedBox(height: tokens.space(OgLSpacing.xl)),
        Text(
          '获取令牌：GitHub → Settings → Developer settings → '
          'Personal access tokens（建议勾选 repo 只读起步）。',
          style: TextStyle(
            fontSize: tokens.fontSize(scale.label),
            color: ogL.palette.textFaint,
          ),
        ),
      ],
    );
  }
}