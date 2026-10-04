/// L3 展示级 · 全局动效策略（四档位 → 真实行为）。
///
/// ## 四个档位
/// - `0` 最小：关闭动效（`disableAnimations` 置真），页面切换即时；
/// - `1` 当前：沿用既有行为（尊重系统"减少动效"与 `reduceMotion`），
///   页面过渡使用 Flutter 默认；
/// - `2` 标准：页面过渡使用 Material 标准（各平台统一 Zoom）；
/// - `3` 增强：在标准之上叠一层淡入 + 轻微位移 + 缩放的过渡。
///
/// ## 分层
/// 本文件属 `surface`（L3），只读领域模型 [OgLSettings]，
/// 不依赖 `base` / `domain`，也不反向被低层引用。
library;

import 'package:flutter/material.dart';

import '../settings.dart';

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

  /// 页面过渡主题（按档位选择构建器）。
  ///
  /// ## 5.0：为什么换掉默认过渡（“页面过渡卡顿、其它动画不卡”的根因）
  /// Flutter 在 Android 上的默认过渡是**整页缩放 + 位移 + 淡入**（`ZoomPageTransitionsBuilder`）
  /// ——缩放会让**整页**在过渡期间反复重新光栅化，页面越重越卡；
  /// 而小控件动画只影响自己的小区域，所以"只有页面过渡卡"。
  ///
  /// 现在统一用**单层**过渡：淡入 + 轻微上移（无缩放），并强制包
  /// `RepaintBoundary`——过渡期间每帧只需重新合成图层，不必重绘页面内容。
  /// 档位只调整**位移距离**（0 关；1 最小；2 中等；3 最明显），不再叠加缩放。
  static PageTransitionsTheme pageTransitions(int level) {
    final PageTransitionsBuilder slide = switch (level) {
      0 => const _OgLInstantTransitionsBuilder(),
      2 => const _OgLSlideFadeTransitionsBuilder(offset: 0.035),
      3 => const _OgLSlideFadeTransitionsBuilder(offset: 0.06),
      _ => const _OgLSlideFadeTransitionsBuilder(),
    };
    return PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        for (final TargetPlatform platform in TargetPlatform.values)
          platform: slide,
      },
    );
  }
}

/// 即时过渡：不做任何动画。
class _OgLInstantTransitionsBuilder extends PageTransitionsBuilder {
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

/// 5.0 统一页面过渡：淡入 + 轻微上移（**无缩放**），并强制 `RepaintBoundary`。
///
/// 为什么不用缩放：缩放要求整页在过渡期间重新光栅化（高 DPI 下代价尤大），
/// 这正是"页面过渡卡、其它动画不卡"的成因。包上 `RepaintBoundary` 之后，
/// 过渡期间每帧只需要**重新合成**已缓存图层，不必重绘页面内容。
class _OgLSlideFadeTransitionsBuilder extends PageTransitionsBuilder {
  /// 创建过渡构建器。
  ///
  /// [offset] 为起始垂直位移（占页高比例，正=从下方进入）。
  const _OgLSlideFadeTransitionsBuilder({this.offset = 0.02});

  /// 起始垂直位移（档位越高越明显）。
  final double offset;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final Animation<double> curved = animation.drive(
      CurveTween(curve: Curves.easeOutCubic),
    );
    return RepaintBoundary(
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, offset),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

/// 动效档位作用域：把当前档位暴露给控件层。
///
/// 挂点：`OgLApp` 的 `builder`（位于 `MaterialApp` 之内，随设置变化重建）。
/// 控件据此让**动画时长**随档位变化；档位 `0` 时配合
/// `MediaQuery.disableAnimations` 完全关闭动画。
class OgLMotionScope extends InheritedWidget {
  /// 创建作用域。
  const OgLMotionScope({required this.level, required super.child, super.key});

  /// 当前动效档位（0–3）。
  final int level;

  /// 读取当前档位（未挂载时按 `1` 处理）。
  static int levelOf(BuildContext context) {
    final OgLMotionScope? scope =
        context.dependOnInheritedWidgetOfExactType<OgLMotionScope>();
    return scope?.level ?? 1;
  }

  @override
  bool updateShouldNotify(OgLMotionScope oldWidget) => oldWidget.level != level;
}
