/// L3 展示级 · 首次引导（欢迎 + 权限说明 + 隐私声明）。
///
/// ## 设计原则
/// - **不是**"点一下就跳过"的假引导：每一项权限都说明"为什么需要"；
/// - 权限获取走 [OgLPermissionGateway]（不同平台不同网关），
///   拿不到就**如实**告诉用户去系统设置，绝不自称已授权；
/// - 引导完成标志写进设置（`onboardingDone`），
///   在设置页可随时"重新查看权限"。
library;

import 'package:flutter/material.dart';

import '../app/error_surface.dart';
import '../app/permissions.dart';
import '../surface_bridge.dart';

/// 首次引导页。
class OnboardingPage extends StatefulWidget {
  /// 创建引导页。
  const OnboardingPage({
    required this.surface,
    required this.onFinished,
    this.review = false,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 完成回调（首次引导点"开始使用" / 回顾模式点"完成"）。
  final VoidCallback onFinished;

  /// 是否"回顾模式"（从设置页进入；完成时不改动引导标志）。
  final bool review;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final OgLPermissionGateway _gateway = ogLPermissionGateway();

  List<OgLPermissionInfo>? _infos;
  OgLPermission? _busyPermission;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<OgLPermissionInfo> infos = await _gateway.describe();
      if (!mounted) {
        return;
      }
      setState(() => _infos = infos);
    } catch (error) {
      OgLAppLog.instance.add(
        '引导',
        '权限清单读取失败：$error',
        severity: OgLNoticeSeverity.warning,
      );
      if (mounted) {
        setState(() => _infos = const <OgLPermissionInfo>[]);
      }
    }
  }

  Future<void> _request(OgLPermissionInfo info) async {
    if (_busyPermission != null) {
      return;
    }
    setState(() => _busyPermission = info.permission);
    OgLAppLog.instance.add(
      '引导',
      '请求权限：${info.title}（平台=${_gateway.platformLabel}）',
    );
    try {
      await _gateway.request(info.permission);
    } catch (error) {
      OgLAppLog.instance.add(
        '引导',
        '权限请求失败：$error',
        severity: OgLNoticeSeverity.warning,
      );
    } finally {
      if (mounted) {
        setState(() => _busyPermission = null);
        await _load();
      }
    }
  }

  Future<void> _finish() async {
    if (!widget.review) {
      await widget.surface.settings.setOnboardingDone(true);
    }
    if (mounted) {
      widget.onFinished();
    }
  }

  String _statusText(OgLPermissionStatus status) {
    switch (status) {
      case OgLPermissionStatus.granted:
        return '已具备';
      case OgLPermissionStatus.needsUserAction:
        return '需手动开启';
      case OgLPermissionStatus.notRequired:
        return '本平台无需';
      case OgLPermissionStatus.unsupported:
        return '本平台不支持';
    }
  }

  IconData _statusIcon(OgLPermissionStatus status) {
    switch (status) {
      case OgLPermissionStatus.granted:
        return Icons.check_circle_outline;
      case OgLPermissionStatus.needsUserAction:
        return Icons.privacy_tip_outlined;
      case OgLPermissionStatus.notRequired:
        return Icons.remove_circle_outline;
      case OgLPermissionStatus.unsupported:
        return Icons.block_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<OgLPermissionInfo> infos = _infos ?? const <OgLPermissionInfo>[];
    return Scaffold(
      appBar: widget.review
          ? AppBar(title: const Text('权限与引导'))
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            const SizedBox(height: 12),
            Icon(Icons.hub_outlined, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              '欢迎使用 OhGithubLost',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              '全能 GitHub 仓库管理器。开始前，请花一分钟了解权限用途。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android),
                title: Text('当前平台：${_gateway.platformLabel}'),
                subtitle: const Text('不同平台的权限门槛不同，本页按当前平台给出说明。'),
              ),
            ),
            const SizedBox(height: 16),
            Text('权限说明', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_infos == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final OgLPermissionInfo info in infos)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(_statusIcon(info.status), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                info.title,
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                            Chip(
                              label: Text(_statusText(info.status)),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(info.rationale, style: theme.textTheme.bodySmall),
                        if (info.actionable) ...<Widget>[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonal(
                              onPressed: _busyPermission == null
                                  ? () => _request(info)
                                  : null,
                              child: Text(
                                _busyPermission == info.permission
                                    ? '打开中…'
                                    : _gateway.canOpenSettings
                                        ? '去系统设置'
                                        : '了解',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '你的令牌只保存在本机安全保险库（Keystore / DPAPI / libsecret），'
                        '不会上传到任何第三方服务器；仓库数据只与 GitHub 通信。',
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _infos == null ? null : _finish,
              child: Text(widget.review ? '完成' : '开始使用'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}