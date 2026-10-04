/// L3 展示级 · 动效工具箱（**只从档位质量表取值**）。
///
/// ## 两条纪律（5.2）
/// 1. **不硬编码**：时长 / 位移 / 缩放 / 缓动一律经 [OgLAnim] 读
///    [OgLOAnimQuality]（`motion.dart` 的档位表）。CI 的 `tool/motion_audit.py`
///    会拦下 `lib/surface/**` 里私造的 `Duration(milliseconds: …)`。
/// 2. **降档 = 降质量，不是砍功能**：
///    - 档位 `0` 静默（时长 0、无位移缩放）；
///    - 档位 `1` 最保守（只淡入、最短时长、错峰只覆盖前几项）；
///    - 档位 `2` 标准（淡入 + 小位移）；
///    - 档位 `3` 拉满（淡入 + 较大位移 + 轻微缩放 + 最广错峰）。
///
/// 另外：**入场动画按档位限项**。长列表里给每一项都挂动画，代价随行数线性增长，
/// 这正是"列表滑动发涩"的常见来源；[OgLAnim.staggerOf] 对超出档位上限的序号返回
/// `null`，[OgLReveal] 见到 `null` 就**直接渲染**（不进入动画）。
library;

import 'package:flutter/material.dart';

import 'motion.dart';

/// 动效时长 / 位移 / 开关（全部来自档位质量表）。
abstract final class OgLAnim {
  /// 当前档位（未挂载作用域时按 1）。
  static int level(BuildContext context) => OgLMotionScope.levelOf(context);

  /// 当前是否允许动画（档位 0 或系统「减少动效」时为否）。
  ///
  /// **窄选择器**：只订阅 `disableAnimations`，不再因为键盘 insets / 旋转等
  /// 与自己无关的 MediaQuery 变化而重建（列表项里调用尤其重要）。
  static bool enabled(BuildContext context) =>
      level(context) > 0 && !MediaQuery.disableAnimationsOf(context);

  /// 当前档位的质量表。
  static OgLOAnimQuality quality(BuildContext context) {
    final int lv = enabled(context) ? level(context) : 0;
    return OgLOAnimQuality.of(lv);
  }

  /// 快（短反馈）。
  static Duration fast(BuildContext context) => quality(context).fast;

  /// 中（入场 / 状态变化）。
  static Duration medium(BuildContext context) => quality(context).medium;

  /// 慢（较大范围的变化，如整主题切换）。
  static Duration slow(BuildContext context) => quality(context).slow;

  /// 统一缓动。
  static Curve curve(BuildContext context) => quality(context).curve;

  /// 入场位移（占自身高度比例；0 = 只淡入）。
  static double revealOffset(BuildContext context) =>
      quality(context).revealOffset;

  /// 入场缩放起点（1 = 不缩放）。
  static double revealScale(BuildContext context) =>
      quality(context).revealScaleFrom;

  /// 大体积动画（整页 / 半页）统一曲线：起步快、收尾柔。
  static Curve largeCurve(BuildContext context) => quality(context).largeCurve;

  /// 大体积内容切换（loading → data）时长。
  static Duration stateSwapDuration(BuildContext context) =>
      quality(context).stateSwapDuration;

  /// 大体积内容切换的起始缩放（1 = 不缩放）。
  static double stateSwapScale(BuildContext context) {
    // 复用全页过渡的缩放量级：低档不缩放，中/高档各给一点点。
    final double from = quality(context).transitionScaleFrom;
    return from >= 1 ? 1 : from;
  }

  /// 切 tab 的滑动时长。
  static Duration shellDuration(BuildContext context) =>
      quality(context).shellDuration;

  /// 切 tab 的位移比例。
  static double shellOffset(BuildContext context) =>
      quality(context).shellOffset;

  /// 整页翻页（引导页）时长。
  static Duration pageViewDuration(BuildContext context) =>
      quality(context).pageViewDuration;

  /// 半页弹层（底部面板）时长。
  static Duration sheetDuration(BuildContext context) =>
      quality(context).sheetDuration;

  /// 列表错峰延迟；**超出本档上限返回 `null` = 该项不参与动画**。
  ///
  /// 返回 `null` 而不是"给一个很大的延迟"，是为了让调用方**立刻静态渲染**，
  /// 避免长列表尾部一堆项同时起动画。
  static Duration? staggerOf(BuildContext context, int index) {
    final OgLOAnimQuality q = quality(context);
    if (!q.animates || index < 0 || index > q.staggerMaxIndex) {
      return null;
    }
    return q.staggerStep * index;
  }
}

/// 入场动画：淡入（+ 档位允许时叠加位移 / 缩放）。
///
/// - [delay] 传 `null`（或 [OgLAnim.staggerOf] 超出上限时的返回值）→ **不做动画**；
/// - 档位 `0` / 系统减少动效 → 直接显示；
/// - 动画期间子控件包在 `RepaintBoundary` 里：每帧只重合成，不重绘列表项内容。
class OgLReveal extends StatefulWidget {
  /// 创建入场包装。
  const OgLReveal({required this.child, this.delay, super.key});

  /// 子控件。
  final Widget child;

  /// 延迟（用于列表错峰）；`null` = 不播放动画。
  final Duration? delay;

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

  @override
  void didUpdateWidget(covariant OgLReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 档位从低切到高（或反之）时重新判定一次：档位变化不该让已显示的项回弹。
    if (oldWidget.delay != widget.delay && widget.delay == null) {
      _shown = true;
    }
  }

  void _start() {
    if (!mounted) {
      return;
    }
    final Duration? delay = widget.delay;
    if (!OgLAnim.enabled(context) || delay == null) {
      setState(() => _shown = true);
      return;
    }
    if (delay == Duration.zero) {
      setState(() => _shown = true);
      return;
    }
    Future<void>.delayed(delay, () {
      if (mounted) {
        setState(() => _shown = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!OgLAnim.enabled(context) || widget.delay == null) {
      return widget.child;
    }
    final Duration duration = OgLAnim.medium(context);
    final Curve curve = OgLAnim.curve(context);
    final double offset = OgLAnim.revealOffset(context);
    final double scaleFrom = OgLAnim.revealScale(context);

    // 由内到外叠：淡入 → （可选）位移 → （可选）缩放。
    Widget result = widget.child;
    if (scaleFrom < 1) {
      result = AnimatedScale(
        scale: _shown ? 1 : scaleFrom,
        duration: duration,
        curve: curve,
        child: result,
      );
    }
    if (offset > 0) {
      result = AnimatedSlide(
        offset: _shown ? Offset.zero : Offset(0, offset),
        duration: duration,
        curve: curve,
        child: result,
      );
    }
    result = AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: duration,
      curve: curve,
      child: result,
    );
    // 每项独立绘制边界：动画期间不牵连整列表重绘。
    return RepaintBoundary(child: result);
  }
}

/// **大体积内容切换**：整页 / 半页内容（loading → data、页面级状态）换用
/// 「快速淡入 + 极轻缩放」。
///
/// 为什么单独做成一个组件：
/// - 大体积内容用纯淡入会"发闷"，用位移又容易和页面过渡打架——
///   **淡入 + 极轻缩放**是最稳的"灵动"组合，且几乎不增加绘制成本
///   （缩放幅度 ≤ 1%、外层仍有 `RepaintBoundary`）；
/// - 缩放属于"会被低档位关掉的效果"，因此它的取值、曲线、时长都从
///   `OgLOAnimQuality` 来；门禁（`tool/motion_audit.py`）只允许在**本文件**
///   与 `motion.dart` 里出现 `ScaleTransition`，避免各处私自造效果。
class OgLSurfaceSwitch extends StatelessWidget {
  /// 创建。
  const OgLSurfaceSwitch({required this.child, super.key});

  /// 当前内容（用 `Key` 区分不同状态即可触发切换）。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Duration duration = OgLAnim.stateSwapDuration(context);
    final Curve curve = OgLAnim.largeCurve(context);
    final double from = OgLAnim.stateSwapScale(context);
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (Widget current, Animation<double> animation) {
        if (from >= 1) {
          // 低档：只淡入（不缩放）——最保守但仍"有反应"。
          return FadeTransition(opacity: animation, child: current);
        }
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: from, end: 1).animate(animation),
            child: current,
          ),
        );
      },
      child: child,
    );
  }
}
