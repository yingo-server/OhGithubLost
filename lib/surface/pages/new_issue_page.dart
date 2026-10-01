/// OGL 页面 · 新建议题（标题 + 正文）。
library;

import 'package:flutter/material.dart';

import '../app/error_surface.dart';
import '../kit/kit.dart';
import '../surface_bridge.dart';
import '../theme/design_tokens.dart';
import '../theme/icon_pack.dart';
import '../theme/theme_pack.dart';

/// 新建议题页。
class OgLNewIssuePage extends StatefulWidget {
  /// 创建页面。
  const OgLNewIssuePage({
    required this.surface,
    required this.fullName,
    super.key,
  });

  /// 表面桥。
  final SurfaceBridge surface;

  /// 仓库全名。
  final String fullName;

  @override
  State<OgLNewIssuePage> createState() => _OgLNewIssuePageState();
}

class _OgLNewIssuePageState extends State<OgLNewIssuePage> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _body = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _titleError;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = '标题不能为空');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _titleError = null;
    });
    try {
      OgLAppLog.instance.add('议题', '创建「$title」…');
      await widget.surface.domain.api.createIssue(
        widget.fullName,
        title: title,
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
      );
      OgLAppLog.instance.add('议题', '已创建：$title');
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error, stackTrace) {
      OgLAppLog.instance.add(
        '议题',
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
          title: '新建议题',
          description: '仓库：${widget.fullName}',
        ),
        OgLTextField(
          controller: _title,
          label: '标题（必填）',
          hint: '一句话描述问题',
          leadingIcon: OgLIconName.issue,
          enabled: !_busy,
          error: _titleError,
          onChanged: (String _) {
            if (_titleError != null) {
              setState(() => _titleError = null);
            }
          },
        ),
        SizedBox(height: tokens.space(OgLSpacing.md)),
        OgLTextField(
          controller: _body,
          label: '正文（可选，支持 Markdown）',
          maxLines: 10,
          enabled: !_busy,
        ),
        if (_error != null) ...<Widget>[
          SizedBox(height: tokens.space(OgLSpacing.sm)),
          OgLBanner(variant: OgLBannerVariant.danger, text: _error!),
        ],
        SizedBox(height: tokens.space(OgLSpacing.lg)),
        OgLButton(
          label: _busy ? '创建中…' : '创建议题',
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