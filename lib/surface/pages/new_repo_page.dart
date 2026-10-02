/// OGL 页面 · 新建仓库 —— 名称 / 描述 / 私有 / 自动初始化。
///
/// ## 布局（`docs/UI_PAGES_PLAN.md` §2.10）
/// ```
/// OgLPageScaffold('新建仓库' + 说明 + 返回键 + 取消)
/// ├ OgLBanner(info)：创建位置与影响
/// ├ OgLSection('填写内容') → OgLBox：
/// │    仓库名（必填，行内错误）/ 描述 / 私有（开关行）/ 自动初始化（开关行）
/// └ 底部主操作：创建仓库（primary，带 loading）
/// ```
///
/// ## 纪律
/// - 表单校验**行内提示**（不是弹窗），错误不静默；
/// - 开关用 `OgLActionRow + OgLToggleSwitch`（不再用 Material `SwitchListTile`）；
/// - 成功后把 `GhRepo` 交还宿主（首页会刷新并进入该仓库）。
library;

import 'package:flutter/material.dart';

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
    final OgLTheme ogL = OgLTheme.of(context);
    final OgLTokens tokens = ogL.tokens;

    return OgLPageScaffold(
      title: '新建仓库',
      description: '将在你的账户下创建一个新的 GitHub 仓库',
      leading: OgLIconButton(
        icon: OgLIconName.arrowLeft,
        label: '取消',
        onTap: _busy ? () {} : () => Navigator.of(context).maybePop(),
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
            variant: _private
                ? OgLBannerVariant.warning
                : OgLBannerVariant.info,
            title: _private ? '将创建为私有仓库' : '将创建为公开仓库',
            text: _private
                ? '只有你和受邀协作者能看到，公开前请确认其中没有敏感信息。'
                : '任何人可见；敏感内容请改用私有仓库。',
          ),
          OgLSection(
            title: '填写内容',
            child: OgLBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  OgLTextField(
                    controller: _name,
                    label: '仓库名（必填）',
                    hint: 'my-awesome-project',
                    leadingIcon: OgLIconName.repository,
                    enabled: !_busy,
                    error: _nameError,
                    onSubmitted: (String _) async {
                      await _create();
                    },
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
                ],
              ),
            ),
          ),
          OgLSection(
            title: '可见性与初始化',
            child: OgLBox(
              padded: false,
              child: Column(
                children: <Widget>[
                  OgLActionRow(
                    leading: OgLIcon(
                      name: _private ? OgLIconName.shield : OgLIconName.info,
                      size: tokens.iconSize(base: 18),
                      color: _private
                          ? ogL.palette.danger
                          : ogL.palette.textDim,
                    ),
                    title: '私有仓库',
                    subtitle: _private ? '仅你与协作者可见' : '当前为公开',
                    trailing: OgLToggleSwitch(
                      value: _private,
                      onChanged: _busy
                          ? null
                          : (bool value) => setState(() => _private = value),
                    ),
                    onTap: _busy
                        ? null
                        : () => setState(() => _private = !_private),
                  ),
                  OgLActionRow(
                    leading: OgLIcon(
                      name: OgLIconName.book,
                      size: tokens.iconSize(base: 18),
                      color: ogL.palette.textDim,
                    ),
                    title: '自动初始化',
                    subtitle: _autoInit
                        ? '附带 README（这样仓库一建好就能看到内容）'
                        : '建出来的会是一个空仓库',
                    trailing: OgLToggleSwitch(
                      value: _autoInit,
                      onChanged: _busy
                          ? null
                          : (bool value) => setState(() => _autoInit = value),
                    ),
                    onTap: _busy
                        ? null
                        : () => setState(() => _autoInit = !_autoInit),
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...<Widget>[
            SizedBox(height: tokens.space(OgLSpacing.md)),
            OgLBanner(
              variant: OgLBannerVariant.danger,
              title: '创建失败',
              text: '$_error\n（常见原因：同名仓库已存在、令牌缺少 repo 权限）',
            ),
          ],
          SizedBox(height: tokens.space(OgLSpacing.lg)),
          OgLButton(
            label: _busy ? '创建中…' : '创建仓库',
            variant: OgLButtonVariant.primary,
            leadingIcon: OgLIconName.add,
            loading: _busy,
            onPressed: _busy ? null : _create,
          ),
          SizedBox(height: tokens.space(OgLSpacing.xs)),
          Text(
            '创建成功后会自动进入新仓库；README 内容会显示在仓库页。',
            style: TextStyle(
              fontSize:
                  tokens.fontSize(const OgLTypeScale.standard().label),
              color: ogL.palette.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}