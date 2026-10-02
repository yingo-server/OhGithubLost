/// L3 展示级 · 登录页（令牌向导）—— 全客户端的入口门。
///
/// ## 四步为什么必须可见
/// 登录会依次做：① 暂存待验证账户 → ② `GET /user` 验证令牌 →
/// ③ 转正并切换 → ④ **保险库回读自检**（防"存进去读不出来"的往返损坏）。
/// 任何一步失败都会让"看起来登上了、实际没有令牌"，
/// 因此每一步都摊开显示状态，失败时错误原样给用户看（并写日志）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';

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
      trailing: Text(done ? '完成' : (current ? '进行中' : '待做')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Future<void> Function()? skip = widget.onSkip;
    return Scaffold(
      appBar: AppBar(
        title: const Text('接入 GitHub'),
        automaticallyImplyLeading: false,
        actions: <Widget>[
          if (skip != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await skip();
                    },
              child: const Text('先逛逛（游客模式）'),
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
                  const Expanded(
                    child: Text(
                      '令牌只保存在本机安全保险库（Android Keystore / iOS Keychain / '
                      '桌面秘密服务），请求只会发往 api.github.com，不经过任何第三方服务器。',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('粘贴令牌', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _input,
            obscureText: _obscure,
            enabled: !_busy,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: '个人访问令牌（Personal Access Token）',
              hintText: 'ghp_… / github_pat_…',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                tooltip: _obscure ? '显示令牌' : '隐藏令牌',
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
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('验证中…'),
                    ],
                  )
                : const Text('验证并登录'),
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
                  '$_error\n（详细原因已写入应用日志，可在「关于」页复制）',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text('向导进度', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                _stepTile(
                  index: 1,
                  title: '暂存待验证账户',
                  detail: '先写入一个占位账户，验证通过再转正',
                ),
                _stepTile(
                  index: 2,
                  title: '验证令牌（GET /user）',
                  detail: '确认令牌有效，并读出你的登录名',
                ),
                _stepTile(
                  index: 3,
                  title: '转正并切换账户',
                  detail: '用真实账号 ID 覆盖占位账户，并切到它',
                ),
                _stepTile(
                  index: 4,
                  title: '保险库回读自检',
                  detail: '把令牌读回来核对（防"存进去读不出来"）',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('怎么拿令牌', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('网页端 → Settings'),
                  subtitle: Text('右上角头像 → Settings'),
                ),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Developer settings'),
                  subtitle: Text('Settings 最下方 → Developer settings'),
                ),
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Personal access tokens'),
                  subtitle: Text('新建令牌；权限建议先只勾 repo（只读起步）'),
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