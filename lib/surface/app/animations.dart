/// L3 展示级 · 动效工具箱（与动效档位联动）。
///
/// ## 与档位的关系
/// 档位 `0`（最小）会把 `MediaQuery.disableAnimations` 置真（见 `app/motion.dart`），
/// 因此本文件的所有动画在档位 `0` 下**自动失效**，控件无需各自判断。
///
/// ## 提供的工具
/// - [OgLAnim]：按可用性给出快 / 中 / 慢时长与错峰延迟；
/// - [OgLReveal]：入场淡入 + 轻微上移，用于列表项与卡片。
library;

import 'package:flutter/material.dart';

/// 动效时长与开关。
abstract final class OgLAnim {
  /// 当前是否允许动画（档位 `0` 时为否）。
  static bool enabled(BuildContext context) =>
      !MediaQuery.of(context).disableAnimations;

  /// 快（短反馈）。
  static Duration fast(BuildContext context) =>
      enabled(context) ? const Duration(milliseconds: 150) : Duration.zero;

  /// 中（入场 / 状态变化）。
  static Duration medium(BuildContext context) =>
      enabled(context) ? const Duration(milliseconds: 220) : Duration.zero;

  /// 慢（较大范围的变化）。
  static Duration slow(BuildContext context) =>
      enabled(context) ? const Duration(milliseconds: 300) : Duration.zero;

  /// 列表错峰延迟（按序号递增，封顶 240ms，避免长列表越等越久）。
  static Duration stagger(BuildContext context, int index) {
    if (!enabled(context)) {
      return Duration.zero;
    }
    final int capped = index > 6 ? 6 : index;
    return Duration(milliseconds: 40 * capped);
  }
}

/// 入场动画：淡入 + 轻微上移。
///
/// - 档位 `0`：直接显示，不做任何动画；
/// - 其余档位：按 [delay] 延迟后播放一次。
class OgLReveal extends StatefulWidget {
  /// 创建入场包装。
  const OgLReveal({required this.child, this.delay = Duration.zero, super.key});

  /// 子控件。
  final Widget child;

  /// 延迟（用于列表错峰）。
  final Duration delay;

  @override
  State<OgLReveal> createState() => _OgLRevealState();
}

class _OgLRevealState extends State<OgLReveal> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!mounted) {
      return;
    }
    if (!OgLAnim.enabled(context) || widget.delay == Duration.zero) {
      setState(() => _shown = true);
      return;
    }
    Future<void>.delayed(widget.delay, () {
      if (mounted) {
        setState(() => _shown = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!OgLAnim.enabled(context)) {
      return widget.child;
    }
    final Duration duration = OgLAnim.medium(context);
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: duration,
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.04),
        duration: duration,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}