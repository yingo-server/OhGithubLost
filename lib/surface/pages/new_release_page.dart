/// OGL 页面 · 新建发布（tag / 标题 / 说明 / 预发布）。
///
/// 创建成功后把 `GhRelease` 通过 `Navigator.pop` 交还宿主（仓库页会刷新列表）。
library;

import 'package:flutter/material.dart';

import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 新建发布页。
class OgLNewReleasePage extends StatefulWidget {
  /// 创建页面。
  const OgLNewReleasePage({
    required this.surface,
    required this.fullName,
    required this.defaultBranch,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  /// 目标分支（作为 target_commitish）。
  final String defaultBranch;

  @override
  State<OgLNewReleasePage> createState() => _OgLNewReleasePageState();
}

class _OgLNewReleasePageState extends State<OgLNewReleasePage> {
  final TextEditingController _tag = TextEditingController();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _prerelease = false;
  bool _busy = false;
  String? _error;
  String? _tagError;

  @override
  void dispose() {
    _tag.dispose();
    _name.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final tag = _tag.text.trim();
    if (tag.isEmpty) {
      setState(() => _tagError = 'tag 不能为空（如 v1.0.0）');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _tagError = null;
    });
    try {
      OgLAppLog.instance.add('发布', '创建 $tag…');
      final release = await widget.surface.domain.api.createRelease(
        widget.fullName,
        tagName: tag,
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        prerelease: _prerelease,
        targetCommitish: widget.defaultBranch,
      );
      OgLAppLog.instance.add('发布', '已创建 ${release.tagName}');
      if (mounted) {
        Navigator.of(context).pop(release);
      }
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '发布',
        '创建失败（原始异常）：$error\n$stackTrace',
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
        OgLPageHeader(
          title: '新建发布',
          description: '仓库：${widget.fullName} · 目标：${widget.defaultBranch}',
        ),
        OgLTextField(
          controller: _tag,
          label: 'tag（必填）',
          hint: 'v1.0.0',
          leadingIcon: OgLIconName.tag,
          enabled: !_busy,
          error: _tagError,
          onChanged: (String _) {
            if (_tagError != null) {
              setState(() => _tagError = null);
            }
          },
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        OgLTextField(
          controller: _name,
          label: '标题（可选）',
          hint: '第一版正式发布',
          enabled: !_busy,
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        OgLTextField(
          controller: _body,
          label: '说明（可选，支持 Markdown）',
          maxLines: 8,
          enabled: !_busy,
        ),
        SizedBox(height: tokens.space(OgLSpacing.sm)),
        SwitchListTile(
          dense: true,
          value: _prerelease,
          onChanged: _busy ? null : (bool v) => setState(() => _prerelease = v),
          title: const Text('标记为预发布（pre-release）'),
        ),
        if (_error != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.sm)),
          OgLBanner(variant: OgLBannerVariant.danger, text: _error!),
        ],
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        OgLButton(
          label: _busy ? '发布中…' : '创建发布',
          variant: OgLButtonVariant.primary,
          leadingIcon: OgLIconName.upload,
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