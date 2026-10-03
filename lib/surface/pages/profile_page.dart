/// L3 展示级 · 我的（账户管理）。
///
/// - 账户列表：切换 / 移除（破坏性操作二次确认）；
/// - 新增账户：复用登录页（令牌向导）；
/// - Gist 片段入口（列表、详情、新建、编辑、删除）；
/// - 危险区：退出登录（删除本机令牌，远端数据不受影响）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_auth.dart';
import '../app/async.dart';
import '../app/error_surface.dart';
import '../surface_bridge.dart';
import 'drafts_page.dart';
import 'gists_page.dart';
import 'login_page.dart';
import 'repo_page.dart';

/// 我的页。
class ProfilePage extends StatefulWidget {
  /// 创建页面。
  const ProfilePage({
    required this.surface,
    required this.onAccountsChanged,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 账户变更回调（主壳用它重新过登录门）。
  final Future<void> Function() onAccountsChanged;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  AsyncController<List<GhAccount>>? _accounts;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _accountsC().loadIfNeeded();
    // 草稿变更可观察：编辑保存 / 提交清稿后角标实时刷新。
    widget.surface.domain.api.draftsChanged.addListener(_onDraftsChanged);
  }

  @override
  void dispose() {
    widget.surface.domain.api.draftsChanged.removeListener(_onDraftsChanged);
    _accounts?.dispose();
    super.dispose();
  }

  void _onDraftsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  AsyncController<List<GhAccount>> _accountsC() {
    final existing = _accounts;
    if (existing != null) {
      return existing;
    }
    final controller = AsyncController<List<GhAccount>>(
      label: '账户',
      isEmpty: (List<GhAccount> value) => value.isEmpty,
      loader: () async {
        final List<GhAccount> list = await widget.surface.domain.auth.accounts();
        _activeId = await widget.surface.domain.auth.activeAccountId();
        return list;
      },
    );
    _accounts = controller;
    return controller;
  }

  Future<void> _refresh() async {
    await _accountsC().load();
    // 会话里的账号信息必须跟着切换走，否则中枢层仍认为自己还是旧账号。
    await widget.surface.domain.session.refreshAccount();
    await widget.onAccountsChanged();
  }

  Future<void> _switchTo(GhAccount account) async {
    try {
      final bool ok = await widget.surface.domain.auth.switchTo(account.id);
      if (!mounted) {
        return;
      }
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('@${account.login} 没有可用令牌，已拒绝切换'),
          ),
        );
        return;
      }
      OgLAppLog.instance.result('账户', '已切换', '@${account.login}');
      // 多用户安全：缓存不含账号维度（分页快照 / 仓库缓存都不含），
      // 切换后必须**清空所有缓存**，避免"用 B 账号看到 A 账号的私有数据"。
      await widget.surface.clearAllCaches();
      clearOgLRepoPageCaches();
      await _refresh();
    } catch (error) {
      OgLAppLog.instance.add(
        '账户',
        '切换失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换失败：$error')),
        );
      }
    }
  }

  Future<void> _remove(GhAccount account) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('移除账户'),
        content: Text(
          '将删除「@${account.login}」在本机保存的令牌。'
          '该账号的远端数据不受影响；重新使用需要再次输入令牌。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await widget.surface.domain.auth.removeAccount(account.id);
      OgLAppLog.instance.result('账户', '已移除', '@${account.login}');
      try {
        await widget.surface.clearRepositoryCache();
      } catch (error) {
        OgLAppLog.instance.add(
          '账户',
          '清空仓库缓存失败（不影响操作）：$error',
          severity: OgLNoticeSeverity.warning,
        );
      }
      await _refresh();
    } catch (error) {
      OgLAppLog.instance.add(
        '账户',
        '移除失败：$error',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('移除失败：$error')),
        );
      }
    }
  }

  Future<void> _addAccount() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext routeContext) => LoginPage(
          surface: widget.surface,
          onLoggedIn: () async {
            await _accountsC().load();
            await widget.onAccountsChanged();
            if (routeContext.mounted) {
              Navigator.of(routeContext).pop();
            }
          },
        ),
      ),
    );
  }

  void _openGists() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => GistsPage(surface: widget.surface),
      ),
    );
  }

  void _openDrafts() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (BuildContext context) => DraftsPage(surface: widget.surface),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncController<List<GhAccount>> controller = _accountsC();
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            tooltip: '新增账户',
            onPressed: _addAccount,
          ),
        ],
      ),
      body: AsyncView<List<GhAccount>>(
        controller: controller,
        emptyIcon: Icons.key_outlined,
        emptyText: '未登录（去「登录」页接入令牌后即可浏览私有仓库）',
        builder: (BuildContext context, List<GhAccount> accounts) => ListView(
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('账户'),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: <Widget>[
                  for (final GhAccount account in accounts)
                    ListTile(
                      leading: const Icon(Icons.key),
                      title: Text('@${account.login}'),
                      subtitle: Text(
                        account.id == _activeId ? '当前账号' : '可切换',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          if (account.id != _activeId)
                            TextButton(
                              onPressed: () => _switchTo(account),
                              child: const Text('切换'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '移除',
                            onPressed: () => _remove(account),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('内容'),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                leading: const Icon(Icons.edit_note),
                title: const Text('草稿箱'),
                subtitle: ListenableBuilder(
                  listenable: widget.surface.domain.api.draftsChanged,
                  builder: (BuildContext context, Widget? _) => FutureBuilder<int>(
                    future: widget.surface.domain.api.draftCount(),
                    builder:
                        (BuildContext context, AsyncSnapshot<int> snapshot) {
                      final int count = snapshot.data ?? 0;
                      return Text(count == 0 ? '没有未提交的草稿' : '$count 条未提交草稿');
                    },
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openDrafts,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                leading: const Icon(Icons.article_outlined),
                title: const Text('Gist 片段'),
                subtitle: const Text('代码片段：列表、详情、新建、编辑、删除'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openGists,
              ),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('危险区'),
            ),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('退出登录会删除本机保存的令牌；远端数据不受影响。'),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: accounts.isEmpty
                          ? null
                          : () async {
                              final GhAccount? current = _currentOf(accounts);
                              if (current != null) {
                                await _remove(current);
                              }
                            },
                      child: const Text('退出当前账号'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  GhAccount? _currentOf(List<GhAccount> accounts) {
    for (final GhAccount account in accounts) {
      if (account.id == _activeId) {
        return account;
      }
    }
    return accounts.isEmpty ? null : accounts.first;
  }
}