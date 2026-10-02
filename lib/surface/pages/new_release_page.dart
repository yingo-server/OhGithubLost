/// OGL 页面 · 新建发布（tag / 标题 / 说明 / 预发布）。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.10）
/// ```
/// OgLPageScaffold('新建发布' + '仓库 · 目标分支' + 返回键 + 取消)
/// ├ OgLBanner(info)：target 与 tag 的语义（避免误建）
/// ├ OgLSection('填写内容') → OgLBox：tag（必填，行内错误）/ 标题 / 说明（Markdown）
/// ├ OgLSection('发布选项') → OgLBox：预发布（开关行）
/// └ 底部主操作：创建发布（primary，带 loading）
/// ```
///
/// ## 纪律
/// - tag 校验**行内提示**；预发布开关用 `OgLToggleSwitch`（不再用 Material 开关）；
/// - 成功后把 `GhRelease` 交还宿主（仓库页刷新列表）。
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
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;

    return OgLPageScaffold(
      title: '新建发布',
      description: '仓库：${widget.fullName}',
      leading: OgLIconButton(
        icon: OgLIconName.arrowLeft,
        label: '取消',
        onTap: () => Navigator.of(context).maybePop(),
      ),
      actions: <Widget>[
        OgLButton(
          label: '取消',
          variant: OgLButtonVariant.invisible,
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OgLBanner(
            variant: OgLBannerVariant.info,
            title: '发布基于 tag',
            text: 'GitHub 会基于目标分支（当前：${widget.defaultBranch}）'
                '创建这个 tag，并把说明作为发布公告。',
          ),
          OgLSection(
            title: '填写内容',
            child: OgLBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
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
                    hint: '本次更新了什么',
                    maxLines: 8,
                    enabled: !_busy,
                  ),
                ],
              ),
            ),
          ),
          OgLSection(
            title: '发布选项',
            child: OgLBox(
              padded: false,
              child: OgLActionRow(
                leading: OgLIcon(
                  name: _prerelease ? OgLIconName.warning : OgLIconName.release,
                  size: tokens.iconSize(base: 18),
                  color: _prerelease
                      ? ogL.palette.warning
                      : ogL.palette.textDim,
                ),
                title: '标记为预发布（pre-release）',
                subtitle: _prerelease
                    ? '会明确标成预发布：不适合生产环境使用'
                    : '当前为正式发布',
                trailing: OgLToggleSwitch(
                  value: _prerelease,
                  onChanged: _busy
                      ? null
                      : (bool value) => setState(() => _prerelease = value),
                ),
                onTap: _busy
                    ? null
                    : () => setState(() => _prerelease = !_prerelease),
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            SizedBox(height: tokens.space(OgLSpacing.md)),
            OgLBanner(
              variant: OgLBannerVariant.danger,
              title: '创建失败',
              text: '$_error\n（常见原因：tag 已存在、令牌缺少 contents 写权限）',
            ),
          ],
          SizedBox(height: tokens.space(OgLSpacing.lg)),
          OgLButton(
            label: _busy ? '发布中…' : '创建发布',
            variant: OgLButtonVariant.primary,
            leadingIcon: OgLIconName.upload,
            loading: _busy,
            onPressed: _busy ? null : _create,
          ),
          SizedBox(height: tokens.space(OgLSpacing.xs)),
          Text(
            '创建成功后返回仓库页的「发布」标签刷新即可看到。',
            style: TextStyle(
              fontSize: tokens.fontSize(const OgLTypeScale.standard().label),
              color: ogL.palette.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}