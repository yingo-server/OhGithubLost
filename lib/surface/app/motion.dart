/// L3 展示级 · 全局动效策略（档位 → **质量**，而不是"有/无"）。
///
/// ## 设计原则（5.2 调整）
/// 用户反馈：整体动画仍偏卡。因此把思路从"低档直接砍掉效果"改成
/// **逐级降低质量**：
///
/// - 档位 `0`：**静默**（时长归零、无位移、无缩放）——无障碍 / 省电场景；
/// - 档位 `1`：**最保守**（只淡入、最短时长、错峰只覆盖前几项、无缩放）；
/// - 档位 `2`：**标准**（淡入 + 小位移、中等时长、错峰适度、仍不缩放）；
/// - 档位 `3`：**拉满**（淡入 + 较大位移 + 轻微缩放、最长时长、错峰最广）。
///
/// 关键约定：**1 < 2 < 3 逐级更"重"**，即每一档的时长 / 位移 / 参与动画的项数
/// 都**不减少**、缩放只可能出现在更高档。这样"降档"=降质量，而不是丢功能。
///
/// 任何动画都**不应硬编码时长/位移/缩放**：一律经 [OgLAnim]（见 `animations.dart`）
/// 读取本表；`tool/motion_audit.py` 会在 CI 里卡住硬编码。
library;

import 'package:flutter/material.dart';

import '../settings.dart';

/// 动效质量档（某档位下的**全部**动画参数）。
///
/// 纯数据 + 纯函数：可单测（逐级单调性），不依赖任何运行时环境。
@immutable
class OgLOAnimQuality {
  /// 创建。所有时长/系数都由档位表给出，业务代码不要自己造。
  const OgLOAnimQuality({
    required this.level,
    required this.fast,
    required this.medium,
    required this.slow,
    required this.staggerStep,
    required this.staggerMaxIndex,
    required this.revealOffset,
    required this.revealScaleFrom,
    required this.transitionOffset,
    required this.transitionScaleFrom,
    required this.blurSigma,
    required this.curve,
  });

  /// 档位（0–3）。
  final int level;

  /// 短反馈时长。
  final Duration fast;

  /// 中等时长（入场 / 状态变化）。
  final Duration medium;

  /// 较大范围变化的时长。
  final Duration slow;

  /// 列表错峰步长。
  final Duration staggerStep;

  /// 参与入场动画的最大序号（**更保守的档位只让前几项动**）。
  final int staggerMaxIndex;

  /// 入场位移（占自身高度比例；0 = 只淡入，不动位置）。
  final double revealOffset;

  /// 入场缩放起点（1 = 不缩放）。
  final double revealScaleFrom;

  /// 页面过渡位移（占页高比例）。
  final double transitionOffset;

  /// 页面过渡缩放起点（1 = 不缩放）。
  final double transitionScaleFrom;

  /// 允许的最大模糊半径（0 = 不允许任何模糊，模糊是最贵的效果之一）。
  final double blurSigma;

  /// 统一缓动（更保守的档位用更"直接"的曲线）。
  final Curve curve;

  /// 是否允许动画。
  bool get animates => level > 0;

  /// 是否允许缩放类效果（整页 / 整项缩放会触发重新光栅化）。
  bool get hasScale => revealScaleFrom < 1 || transitionScaleFrom < 1;

  /// 是否允许模糊。
  bool get hasBlur => blurSigma > 0;

  /// 逐档单调：本档是否**不比** [other] 更重（时长更短 / 位移更小 / 项数更少）。
  ///
  /// 用它把"降档 = 降质量"钉成测试。
  bool isNotHeavierThan(OgLOAnimQuality other) =>
      fast <= other.fast &&
      medium <= other.medium &&
      slow <= other.slow &&
      staggerStep <= other.staggerStep &&
      staggerMaxIndex <= other.staggerMaxIndex &&
      revealOffset <= other.revealOffset &&
      revealScaleFrom >= other.revealScaleFrom &&
      transitionOffset <= other.transitionOffset &&
      transitionScaleFrom >= other.transitionScaleFrom &&
      blurSigma <= other.blurSigma;

  /// 档位 → 质量表（**唯一事实来源**）。
  static OgLOAnimQuality of(int level) {
    switch (level) {
      case 1:
        return const OgLOAnimQuality(
          level: 1,
          fast: Duration(milliseconds: 110),
          medium: Duration(milliseconds: 150),
          slow: Duration(milliseconds: 190),
          staggerStep: Duration(milliseconds: 14),
          staggerMaxIndex: 3,
          revealOffset: 0,
          revealScaleFrom: 1,
          transitionOffset: 0.012,
          transitionScaleFrom: 1,
          blurSigma: 0,
          curve: Curves.linear,
        );
      case 2:
        return const OgLOAnimQuality(
          level: 2,
          fast: Duration(milliseconds: 170),
          medium: Duration(milliseconds: 220),
          slow: Duration(milliseconds: 280),
          staggerStep: Duration(milliseconds: 30),
          staggerMaxIndex: 8,
          revealOffset: 0.02,
          revealScaleFrom: 1,
          transitionOffset: 0.035,
          transitionScaleFrom: 1,
          blurSigma: 0,
          curve: Curves.easeOut,
        );
      case 3:
        return const OgLOAnimQuality(
          level: 3,
          fast: Duration(milliseconds: 220),
          medium: Duration(milliseconds: 300),
          slow: Duration(milliseconds: 380),
          staggerStep: Duration(milliseconds: 46),
          staggerMaxIndex: 16,
          revealOffset: 0.05,
          revealScaleFrom: 0.985,
          transitionOffset: 0.06,
          transitionScaleFrom: 0.99,
          blurSigma: 6,
          curve: Curves.easeOutCubic,
        );
      case 0:
      default:
        return const OgLOAnimQuality(
          level: 0,
          fast: Duration.zero,
          medium: Duration.zero,
          slow: Duration.zero,
          staggerStep: Duration.zero,
          staggerMaxIndex: 0,
          revealOffset: 0,
          revealScaleFrom: 1,
          transitionOffset: 0,
          transitionScaleFrom: 1,
          blurSigma: 0,
          curve: Curves.linear,
        );
    }
  }
}

/// 动效策略：把设置里的档位翻译成控件层能直接用的值。
abstract final class OgLMotion {
  /// 是否关闭动效。
  ///
  /// 档位 `0` 强制关闭；其余档位尊重系统"减少动效"与旧键 [OgLSettings.reduceMotion]。
  static bool disableAnimations(MediaQueryData query, OgLSettings settings) {
    if (settings.motionLevel <= 0) {
      return true;
    }
    return query.disableAnimations || settings.reduceMotion;
  }

  /// 页面过渡主题（按档位质量生成）。
  ///
  /// ## 为什么不用整页缩放（5.0 的结论）
  /// Flutter 默认过渡是**整页缩放 + 位移 + 淡入**（`ZoomPageTransitionsBuilder`）：
  /// 缩放要求**整页**在过渡期间反复重新光栅化 —— 页面越重越卡，
  /// 而小控件动画不受影响，于是表现为"只有页面过渡卡"。
  ///
  /// ## 5.2：按档位给**质量**
  /// - 位移距离逐档增大（`0.012 → 0.035 → 0.06`）；
  /// - **只有拉满档**允许 0.99 的轻微缩放，且同样包在 `RepaintBoundary` 里；
  /// - 过渡始终包 `RepaintBoundary`：过渡期间只重合成、不重绘页面内容。
  static PageTransitionsTheme pageTransitions(int level) {
    final OgLOAnimQuality quality = OgLOAnimQuality.of(level);
    final PageTransitionsBuilder builder = level <= 0
        ? const _OgLInstantTransitionsBuilder()
        : _OgLSlideFadeTransitionsBuilder(
            offset: quality.transitionOffset,
            scaleFrom: quality.transitionScaleFrom,
            curve: quality.curve,
          );
    return PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        for (final TargetPlatform platform in TargetPlatform.values)
          platform: builder,
      },
    );
  }
}

/// 即时过渡：不做任何动画（档位 0）。
class _OgLInstantTransitionsBuilder extends PageTransitionsBuilder {
  /// 创建。
  const _OgLInstantTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

/// 统一页面过渡：淡入（+ 可选轻微缩放）+ 可选轻位移，**强制 `RepaintBoundary`**。
class _OgLSlideFadeTransitionsBuilder extends PageTransitionsBuilder {
  /// 创建。
  const _OgLSlideFadeTransitionsBuilder({
    required this.offset,
    required this.scaleFrom,
    required this.curve,
  });

  /// 起始垂直位移（占页高比例；0 = 不位移）。
  final double offset;

  /// 起始缩放（1 = 不缩放；仅拉满档 < 1）。
  final double scaleFrom;

  /// 缓动。
  final Curve curve;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> curved = animation.drive(CurveTween(curve: curve));
    Widget result = child;
    if (offset > 0) {
      result = SlideTransition(
        position: Tween<Offset>(begin: Offset(0, offset), end: Offset.zero)
            .animate(curved),
        child: result,
      );
    }
    if (scaleFrom < 1) {
      result = ScaleTransition(
        scale: Tween<double>(begin: scaleFrom, end: 1).animate(curved),
        child: result,
      );
    }
    return RepaintBoundary(
      child: FadeTransition(opacity: curved, child: result),
    );
  }
}

/// 动效档位作用域：把当前档位暴露给控件层。
///
/// 挂点：`OgLApp` 的 `builder`（位于 `MaterialApp` 之内，随设置变化重建）。
/// 控件据此读 [OgLOAnimQuality]（时长 / 位移 / 缩放 / 错峰项数都随档位变化）。
class OgLMotionScope extends InheritedWidget {
  /// 创建作用域。
  const OgLMotionScope({required this.level, required super.child, super.key});

  /// 当前动效档位（0–3）。
  final int level;

  /// 读取当前档位（未挂载作用域时按 1 处理）。
  static int levelOf(BuildContext context) {
    final OgLMotionScope? scope =
        context.dependOnInheritedWidgetOfExactType<OgLMotionScope>();
    return scope?.level ?? 1;
  }

  @override
  bool updateShouldNotify(OgLMotionScope oldWidget) => oldWidget.level != level;
}
