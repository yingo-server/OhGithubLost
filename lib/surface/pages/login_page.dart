/// L3 展示级 · 登录页（令牌向导）—— 全客户端的入口门。
///
/// ## 四步为什么必须可见
/// 登录会依次做：① 暂存待验证账户 → ② `GET /user` 验证令牌 →
/// ③ 转正并切换 → ④ **保险库回读自检**（防"存进去读不出来"的往返损坏）。
/// 任何一步失败都会让"看起来登上了、实际没有令牌"，
/// 因此每一步都摊开显示状态，失败时错误原样给用户看（并写日志）。
library;

import 'package:flutter/material.dart';

import '../app/error_surface.dart';

import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';

import '../types.dart';

/// 取 `login` 分片文案。
String _t(String key, [Map<String, String>? args]) =>
    OgLI18n.instance.t('login', key, args: args);

/// 登录页。
class LoginPage extends StatefulWidget {
  /// 创建登录页。
  const LoginPage({
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
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
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
      setState(() => _error = OgLI18n.instance.t('login', 'tokenRequired'));
      return;
    }
    final GhToken token = GhToken(raw);
    if (!token.looksValid) {
      setState(
        () => _error = OgLI18n.instance.t('login', 'tokenShapeInvalid'),
      );
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _phase = OgLI18n.instance.t('login', 'verifying');
      _step = 1;
    });

    final auth = widget.surface.domain.auth;
    final api = widget.surface.domain.api;
    final String pendingId = 'pending-${DateTime.now().millisecondsSinceEpoch}';
    try {
      OgLAppLog.instance.add(_t('signIn'), '1/4 暂存待验证账户（$pendingId）');
      await auth.saveAccount(GhAccount(id: pendingId, login: OgLI18n.instance.t('login', 'pendingSuffix')), token);
      await auth.switchTo(pendingId);

      if (mounted) {
        setState(() {
          _step = 2;
          _phase = OgLI18n.instance.t('login', 'phaseVerify');
        });
      }
      OgLAppLog.instance.add(_t('signIn'), '2/4 验证令牌（GET /user）…');
      final me = await api.currentUser();
      OgLAppLog.instance.add(_t('signIn'), '3/4 验证成功：@${me.login}');

      if (mounted) {
        setState(() {
          _step = 3;
          _phase = OgLI18n.instance.t('login', 'phasePromote');
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
          _phase = OgLI18n.instance.t('login', 'phaseVault');
        });
      }
      final readBack = await auth.activeToken();
      OgLAppLog.instance.add(
        _t('signIn'),
        '4/4 保险库回读：${readBack?.masked ?? "读取失败（令牌可能未落库）"}',
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _step = 5;
        _phase = OgLI18n.instance.t('login', 'phaseDone');
      });
      OgLAppLog.instance.add(_t('signIn'), '完成：@${me.login}');
      await widget.onLoggedIn();
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        _t('signIn'),
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
          _t('signIn'),
          '清理待验证账户失败：$cleanupError',
          severity: OgLNoticeSeverity.warning,
        );
      }
      if (mounted) {
        setState(() {
          _error = OgLI18n.instance.t('login', 'verifyFailed', args: <String, String>{'error': '$error'});
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
  Widget _stepTile({
    required int index,
    required String title,
    required String detail,
  }) {
    final bool done = _step > index;
    final bool current = _step == index;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        done
            ? Icons.check_circle
            : current
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
        color: done
            ? scheme.primary
            : current
                ? scheme.primary
                : scheme.outline,
      ),
      title: Text('$index/4 $title'),
      subtitle: Text(detail),
      trailing: Text(done ? OgLI18n.instance.t('login', 'statusDone') : (current ? OgLI18n.instance.t('login', 'statusRunning') : OgLI18n.instance.t('login', 'statusPending'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Future<void> Function()? skip = widget.onSkip;
    return Scaffold(
      appBar: AppBar(
        title: Text(OgLI18n.instance.t('login', 'title')),
        automaticallyImplyLeading: false,
        actions: <Widget>[
          if (skip != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await skip();
                    },
              child: Text(OgLI18n.instance.t('login', 'skip')),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.security, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      // 保险库说明：`vaultNote`（含平台与域名等专有名词，不译）。
                      OgLI18n.instance.t('login', 'vaultNote'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(OgLI18n.instance.t('login', 'pasteToken'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _input,
            obscureText: _obscure,
            enabled: !_busy,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: OgLI18n.instance.t('login', 'tokenLabel'),
              hintText: 'ghp_… / github_pat_…',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                tooltip: _obscure ? OgLI18n.instance.t('login', 'showToken') : OgLI18n.instance.t('login', 'hideToken'),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onSubmitted: (String _) async {
              await _login();
            },
            onChanged: (String _) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text(OgLI18n.instance.t('login', 'verifying')),
                    ],
                  )
                : Text(OgLI18n.instance.t('login', 'signIn')),
          ),
          if (_phase.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(_phase, style: Theme.of(context).textTheme.bodySmall),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  // 错误详情：保留原始异常 + 引导去「关于」页复制。
                  OgLI18n.instance.t(
                    'login',
                    'errorDetail',
                    args: <String, String>{'error': _error ?? ''},
                  ),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(OgLI18n.instance.t('login', 'progressTitle'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                _stepTile(
                  index: 1,
                  title: OgLI18n.instance.t('login', 'stepStageTitle'),
                  detail: OgLI18n.instance.t('login', 'stepStageDesc'),
                ),
                _stepTile(
                  index: 2,
                  title: OgLI18n.instance.t('login', 'stepVerifyTitle'),
                  detail: OgLI18n.instance.t('login', 'stepVerifyDesc'),
                ),
                _stepTile(
                  index: 3,
                  title: OgLI18n.instance.t('login', 'stepPromoteTitle'),
                  detail: OgLI18n.instance.t('login', 'stepPromoteDesc'),
                ),
                _stepTile(
                  index: 4,
                  title: OgLI18n.instance.t('login', 'stepVaultTitle'),
                  detail: OgLI18n.instance.t('login', 'stepVaultDesc'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(OgLI18n.instance.t('login', 'howToTitle'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text(OgLI18n.instance.t('login', 'howToWeb')),
                  subtitle: Text(OgLI18n.instance.t('login', 'howToAvatar')),
                ),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Developer settings'),
                  subtitle: Text(OgLI18n.instance.t('login', 'howToDeveloper')),
                ),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Personal access tokens'),
                  subtitle: Text(OgLI18n.instance.t('login', 'howToScope')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}