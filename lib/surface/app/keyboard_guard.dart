/// L3 展示级 · 键盘 inset 守卫 + 窗口指标日志。
///
/// ## 它解决两个真实问题
/// 1. **"幽灵键盘"把界面顶残**：Android 上报了巨大的 `viewInsets.bottom`
///    （半屏以上），但屏幕上并没有键盘。`Scaffold` 会照章办事：
///    body 被压扁、底栏被抬到屏幕中间 —— 用户看到的就是
///    "内容全空 + 底栏居中 + 下方一大片黑"。
///    规则很简单：**没有任何文本输入获得焦点时，bottom inset 一律当 0**；
///    真的在打字（`EditableText` 持有焦点）时，原样保留、正常避让键盘。
/// 2. **窗口指标的"黑匣子"**：把每次 metrics 变化（尺寸 / insets / padding）
///    写进日志文件 —— 下次真机复现时，"半屏从哪来"会有第一手数据。
library;

import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';

import '../../kernel/log/og_l_log_file.dart';

/// 键盘 inset 守卫（挂在 `MaterialApp.builder`，包住整棵应用树）。
class OgLKeyboardGuard extends StatefulWidget {
  /// 创建守卫。
  const OgLKeyboardGuard({required this.child, super.key});

  /// 被包裹的应用内容。
  final Widget child;

  @override
  State<OgLKeyboardGuard> createState() => _OgLKeyboardGuardState();
}

class _OgLKeyboardGuardState extends State<OgLKeyboardGuard>
    with WidgetsBindingObserver {
  bool _ignoring = false;
  String _lastMetrics = '';

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _logMetrics('初始'));
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _logMetrics('变化');

  void _onFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// 当前焦点是不是文本输入（`EditableText` 把自己的 FocusNode 挂在自身上）。
  bool get _textFocused {
    final BuildContext? context = FocusManager.instance.primaryFocus?.context;
    return context?.widget is EditableText;
  }

  void _logMetrics(String phase) {
    try {
      final FlutterView view =
          WidgetsBinding.instance.platformDispatcher.views.first;
      final double dpr = view.devicePixelRatio;
      final Size logical = view.physicalSize / dpr;
      final String line = '$phase：窗口 ${logical.width.toStringAsFixed(0)}×'
          '${logical.height.toStringAsFixed(0)} @${dpr.toStringAsFixed(2)}x '
          'viewInsets=${(view.viewInsets / dpr).toString()} '
          'padding=${(view.padding / dpr).toString()}';
      if (line == _lastMetrics) {
        return;
      }
      _lastMetrics = line;
      OgLLogFile.line('窗口', line);
    } catch (error) {
      OgLLogFile.line('窗口', '窗口指标读取失败：$error', level: 'WARN');
    }
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData query = MediaQuery.of(context);
    final double bottom = query.viewInsets.bottom;
    final bool ignore = bottom > 0 && !_textFocused;

    if (ignore && !_ignoring) {
      OgLLogFile.line(
        '窗口',
        '检测到无文本焦点的残留键盘 inset=${bottom.toStringAsFixed(0)} '
            '→ 已忽略（防止"底栏被顶到屏幕中间"）',
        level: 'WARN',
      );
    }
    if (!ignore && _ignoring) {
      OgLLogFile.line('窗口', '键盘 inset 恢复生效（bottom=${bottom.toStringAsFixed(0)}）');
    }
    _ignoring = ignore;

    if (!ignore) {
      return widget.child;
    }
    // 只针对"没有文本焦点"的场景把 bottom inset 归零；
    // 真键盘弹出（有 EditableText 焦点）时走上面的正常路径。
    return MediaQuery(
      data: query.removeViewInsets(removeBottom: true),
      child: widget.child,
    );
  }
}