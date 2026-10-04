/// L3 展示级 · 首次引导（分步）。
///
/// ## 分步设计
/// 用 `PageView` 把引导拆成 4 步：欢迎 → 权限 → 隐私 → 完成。
/// 每步只讲一件事，底部有进度指示与「上一步 / 下一步」，
/// 用户始终知道「还有几步、当前在哪一步」。
///
/// ## 权限是「真请求」
/// 权限获取走 [OgLPermissionGateway]（不同平台不同网关）：
/// - 存储：用真实写入探针**主动获取**；失败则**弹窗**说明并**跳转**系统设置；
/// - 通知：弹窗说明后跳转系统设置（纯 Dart 无法直接申请）。
/// 拿不到就如实告诉用户，绝不自称已授权。
library;

import 'package:flutter/material.dart';

import '../app/animations.dart';
import '../app/error_surface.dart';
import '../app/permissions.dart';
import '../i18n/og_l_i18n.dart';
import '../surface_bridge.dart';

/// 取 `onboarding` 分片文案。
String _t(String key, [Map<String, Object?>? args]) =>
    OgLI18n.instance.t('onboarding', key,
        args: args?.map((String k, Object? v) => MapEntry<String, String>(k, '$v')));

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

  /// 完成回调（首次引导点「开始使用」/ 回顾模式点「完成」）。
  final VoidCallback onFinished;

  /// 是否「回顾模式」（从设置页进入；完成时不改动引导标志）。
  final bool review;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  static const int _stepCount = 4;

  late final OgLPermissionGateway _gateway = ogLPermissionGateway(
    storageProbe: widget.surface.ensureStorage,
    storageLocation: widget.surface.appStoragePath,
  );
  final PageController _page = PageController();

  int _step = 0;
  List<OgLPermissionInfo>? _infos;
  OgLPermission? _busyPermission;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
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
        _t('title'),
        _t('permissionListFailed', {'error': error}),
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
      _t('title'),
      _t('requestingPermission', {'title': info.title, 'platform': _gateway.platformLabel}),
    );
    OgLPermissionStatus status;
    try {
      status = await _gateway.request(info.permission);
    } catch (error) {
      OgLAppLog.instance.add(
        _t('title'),
        _t('permissionRequestFailed', {'error': error}),
        severity: OgLNoticeSeverity.warning,
      );
      status = OgLPermissionStatus.needsUserAction;
    }
    if (!mounted) {
      return;
    }
    setState(() => _busyPermission = null);
    await _load();
    if (!mounted) {
      return;
    }
    await _explain(info, status);
  }

  /// 请求后的弹窗说明：能自动获取就报喜；否则说明为什么要手动、如何跳转。
  Future<void> _explain(
    OgLPermissionInfo info,
    OgLPermissionStatus status,
  ) async {
    switch (status) {
      case OgLPermissionStatus.granted:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('ready', {'title': info.title}))),
        );
        return;
      case OgLPermissionStatus.notRequired:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('noAuthNeeded', {'title': info.title}))),
        );
        return;
      case OgLPermissionStatus.needsUserAction:
      case OgLPermissionStatus.unsupported:
        await showDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) => AlertDialog(
            title: Text(info.title),
            content: Text(
              status == OgLPermissionStatus.unsupported
                  ? _t('cannotInApp', {'rationale': info.rationale})
                  : _t('enableInSettings', {'rationale': info.rationale}),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child:  Text(_t('gotIt')),
              ),
              if (_gateway.canOpenSettings)
                FilledButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await _gateway.request(info.permission);
                    await _load();
                  },
                  child:  Text(_t('openSettings')),
                ),
            ],
          ),
        );
        return;
    }
  }

  Future<void> _next() async {
    if (_step >= _stepCount - 1) {
      await _finish();
      return;
    }
    await _page.nextPage(
      duration: OgLAnim.pageViewDuration(context),
      curve: OgLAnim.largeCurve(context),
    );
  }

  Future<void> _back() async {
    if (_step <= 0) {
      return;
    }
    await _page.previousPage(
      duration: OgLAnim.pageViewDuration(context),
      curve: OgLAnim.largeCurve(context),
    );
  }

  Future<void> _finish() async {
    if (!widget.review) {
      await widget.surface.settings.setOnboardingDone(true);
    }
    if (mounted) {
      widget.onFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: widget.review ? AppBar(title:  Text(_t('permissionGuide'))) : null,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            _progress(theme),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (int value) => setState(() => _step = value),
                children: <Widget>[
                  _welcomeStep(theme),
                  _permissionStep(theme),
                  _privacyStep(theme),
                  _doneStep(theme),
                ],
              ),
            ),
            _navBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _progress(ThemeData theme) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < _stepCount; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i <= _step
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _navBar(ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: <Widget>[
            if (_step > 0)
              TextButton(onPressed: _back, child:  Text(_t('previous'))),
            const Spacer(),
            Text('${_step + 1} / $_stepCount', style: theme.textTheme.bodySmall),
            const Spacer(),
            FilledButton(
              onPressed: _infos == null ? null : _next,
              child: Text(
                _step >= _stepCount - 1
                    ? (widget.review ? _t('finish') : _t('getStarted'))
                    : _t('next'),
              ),
            ),
          ],
        ),
      );

  Widget _stepBody(ThemeData theme, {required List<Widget> children}) =>
      ListView(padding: const EdgeInsets.all(20), children: children);

  Widget _welcomeStep(ThemeData theme) => _stepBody(
        theme,
        children: <Widget>[
          const SizedBox(height: 24),
          Icon(Icons.hub_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            _t('welcomeTitle'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _t('welcomeDesc') +
            _t('welcomeDesc2'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone_android),
              title: Text(_t('currentPlatform', {'platform': _gateway.platformLabel})),
              subtitle:  Text(_t('platformNote')),
            ),
          ),
        ],
      );

  Widget _permissionStep(ThemeData theme) => _stepBody(
        theme,
        children: <Widget>[
          Text(_t('permissionIntro'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_infos == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            for (final OgLPermissionInfo info in _infos!)
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
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonal(
                          onPressed: _busyPermission == null && !info.ready
                              ? () => _request(info)
                              : null,
                          child: Text(
                            _busyPermission == info.permission
                                ? _t('fetching')
                                : info.ready
                                    ? _t('readyState')
                                    : _t('fetchOrSettings'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      );

  Widget _privacyStep(ThemeData theme) => _stepBody(
        theme,
        children: <Widget>[
          Text(_t('dataPrivacy'), style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
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
                      _t('tokenVault') +
                      _t('tokenVault2'),
                      style: TextStyle(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
           Card(
            child: ListTile(
              leading: Icon(Icons.folder_outlined),
              title: Text(_t('fileLocation')),
              subtitle: Text(_t('fileLocationDesc')),
            ),
          ),
           Card(
            child: ListTile(
              leading: Icon(Icons.description_outlined),
              title: Text(_t('traceable')),
              subtitle: Text(_t('traceableDesc')),
            ),
          ),
        ],
      );

  Widget _doneStep(ThemeData theme) => _stepBody(
        theme,
        children: <Widget>[
          const SizedBox(height: 24),
          Icon(
            Icons.check_circle_outline,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            widget.review ? _t('readyTitle') : _t('readyTitle2'),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            _t('readyDesc'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );

  String _statusText(OgLPermissionStatus status) {
    switch (status) {
      case OgLPermissionStatus.granted:
        return _t('stateGranted');
      case OgLPermissionStatus.needsUserAction:
        return _t('stateManual');
      case OgLPermissionStatus.notRequired:
        return _t('stateNotNeeded');
      case OgLPermissionStatus.unsupported:
        return _t('stateUnsupported');
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
}