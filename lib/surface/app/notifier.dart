/// L3 展示级 · 统一用户反馈（SnackBar）。
///
/// ## 为什么要有它
/// 此前每个页面各写一份私有的 `_toast(String message)`（共 7 份实现，
/// 行为一致、各写各的：`mounted` 判断 + 直接 `showSnackBar`）。
/// 统一入口后，「提示长什么样、什么语气」只有一处定义。
///
/// ## 三种语气
/// - [OgLNotifier.info] / [OgLNotifier.success]：普通提示（默认配色）；
/// - [OgLNotifier.warning]：需要用户留意的失败 / 风险（error 配色）。
///
/// 注：本文件目前**只建立入口**；各页面 `_toast` 的批量替换放在
/// Phase 5 的后半批（涉及文件多，避免与其它改动混在一起）。
library;

import 'package:flutter/material.dart';

/// 统一用户反馈（SnackBar）。
///
/// 替代散落在各页面的 7 份 `_toast` 私有实现。
class OgLNotifier {
  /// 用脚手架信使构造：`OgLNotifier(ScaffoldMessenger.of(context))`。
  OgLNotifier(this._messenger);

  final ScaffoldMessengerState _messenger;

  /// 普通提示。
  void info(String message) => _show(message);

  /// 成功提示。
  void success(String message) => _show(message);

  /// 失败 / 风险提示（error 配色）。
  void warning(String message) => _show(message, isError: true);

  void _show(String message, {bool isError = false}) {
    if (!_messenger.mounted) {
      // 页面已退出 / 组件已卸载：丢弃提示，不再向已销毁的树写状态。
      return;
    }
    final ColorScheme scheme = Theme.of(_messenger.context).colorScheme;
    _messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: isError ? TextStyle(color: scheme.onError) : null,
        ),
        // 悬浮样式：不压住底部导航栏（也符合 Material 3 的默认推荐）。
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? scheme.error : null,
      ),
    );
  }
}
