/// OGL 页面 · 新建仓库 —— 名称 / 描述 / 私有 / 自动初始化。
///
/// 创建成功后把 `GhRepo` 通过 `Navigator.pop` 交还宿主（首页会刷新并进入该仓库）。
library;

import 'package:flutter/material.dart';

import '../../domain/gh/gh_models.dart';
import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 新建仓库页。
class OgLNewRepoPage extends StatefulWidget {
  /// 创建页面。
  const OgLNewRepoPage({required this.surface, super.key});

  /// 表面桥。
  final SurfaceBridge surface;

  @override
  State<OgLNewRepoPage> createState() => _OgLNewRepoPageState();
}

class _OgLNewRepoPageState extends State<OgLNewRepoPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _description = TextEditingController();
  bool _private = false;
  bool _autoInit = true;
  bool _busy = false;
  String? _error;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '仓库名不能为空');
      return;
    }
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(name)) {
      setState(() => _nameError = '只能包含字母、数字、点、下划线、连字符');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _nameError = null;
    });
    try {
      OgLAppLog.instance.add('新建仓库', '创建「$name」…');
      final repo = await widget.surface.domain.api.createRepo(
        name: name,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        private: _private,
        autoInit: _autoInit,
      );
      OgLAppLog.instance.add('新建仓库', '成功：${repo.fullName}');
      if (mounted) {
        Navigator.of(context).pop(repo);
      }
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '新建仓库',
        '失败（原始异常）：$error\n$stackTrace',
        severity: OgLNoticeSeverity.critical,
      );
      if (mounted) {
        setState(() => _error = '创建失败：$error');
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
    return ListView(
      padding: EdgeInsets.symmetric(vertical: tokens.space(OgLSpacing.lg)),
      children: <Widget>[
        const OgLPageHeader(
          title: '新建仓库',
          description: '将在你的账户下创建一个新的 GitHub 仓库',
        ),
        OgLTextField(
          controller: _name,
          label: '仓库名（必填）',
          hint: 'my-awesome-project',
          leadingIcon: OgLIconName.repository,
          enabled: !_busy,
          error: _nameError,
          onChanged: (String _) {
            if (_nameError != null) {
              setState(() => _nameError = null);
            }
          },
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        OgLTextField(
          controller: _description,
          label: '描述（可选）',
          hint: '一句话说明这个仓库做什么',
          enabled: !_busy,
        ),
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        SwitchListTile(
          dense: true,
          value: _private,
          onChanged: _busy ? null : (bool v) => setState(() => _private = v),
          title: const Text('私有仓库'),
        ),
        SwitchListTile(
          dense: true,
          value: _autoInit,
          onChanged: _busy ? null : (bool v) => setState(() => _autoInit = v),
          title: const Text('自动初始化（附带 README）'),
        ),
        if (_error != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.sm)),
          OgLBanner(variant: OgLBannerVariant.danger, text: _error!),
        ],
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        OgLButton(
          label: _busy ? '创建中…' : '创建仓库',
          variant: OgLButtonVariant.primary,
          leadingIcon: OgLIconName.add,
          loading: _busy,
          onPressed: _create,
        ),
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        OgLButton(
          label: '取消',
          variant: OgLButtonVariant.invisible,
          onPressed: _busy
              ? null
              : () {
                  Navigator.of(context).pop();
                },
        ),
      ],
    );
  }
}