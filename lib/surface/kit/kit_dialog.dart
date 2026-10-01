/// OGL Kit · 对话框 —— 规格对齐 Primer Dialog：
/// 标题 + 正文（人话解释后果）+ 取消 / 确认；danger 变体用于不可逆操作。
///
/// 安全约定：关掉对话框（点外部 / 返回键）**绝不等于确认**。
library;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../theme/theme_pack.dart';
import 'kit_button.dart';

/// OGL 确认对话框。
class OgLConfirmDialog extends StatelessWidget {
  /// 创建对话框。
  const OgLConfirmDialog({
    required this.title,
    required this.message,
    this.confirmLabel = '确认',
    this.cancelLabel = '取消',
    this.danger = false,
    super.key,
  });

  /// 标题。
  final String title;

  /// 正文（说明后果）。
  final String message;

  /// 确认按钮文案。
  final String confirmLabel;

  /// 取消按钮文案。
  final String cancelLabel;

  /// 危险操作（红色确认按钮）。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ogL = OgLTheme.of(context);
    final scale = const OgLTypeScale.standard();
    return AlertDialog(
      backgroundColor: ogL.palette.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ogL.tokens.radius(OgLRadius.large)),
        side: BorderSide(color: ogL.palette.border, width: ogL.tokens.hairline),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: ogL.tokens.fontSize(scale.title),
          fontWeight: FontWeight.w600,
          color: ogL.palette.text,
        ),
      ),
      content: Text(
        message,
        style: TextStyle(
          fontSize: ogL.tokens.fontSize(scale.body),
          color: ogL.palette.textDim,
        ),
      ),
      actions: <Widget>[
        OgLButton(
          label: cancelLabel,
          variant: OgLButtonVariant.invisible,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        OgLButton(
          label: confirmLabel,
          variant: danger ? OgLButtonVariant.danger : OgLButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// 弹出确认对话框；返回是否确认（关掉 = false，**绝不默认确认**）。
Future<bool> ogLConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool danger = false,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => OgLConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
    ),
  );
  return result ?? false;
}