/// L3 展示级 · 全局动效策略（四档位 → 真实行为）。
///
/// ## 四个档位
/// - `0` 最小：关闭动效（`disableAnimations` 置真），页面切换即时；
/// - `1` 当前：沿用既有行为（尊重系统"减少动效"与 `reduceMotion`），
///   页面过渡使用 Flutter 默认；
/// - `2` 标准：页面过渡使用 Material 标准（Android/桌面 Zoom、iOS/Cupertino）；
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
  static PageTransitionsTheme pageTransitions(int level) {
    switch (level) {
      case 0:
        return const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: _OgLInstantTransitionsBuilder(),
            TargetPlatform.iOS: _OgLInstantTransitionsBuilder(),
            TargetPlatform.macOS: _OgLInstantTransitionsBuilder(),
            TargetPlatform.windows: _OgLInstantTransitionsBuilder(),
            TargetPlatform.linux: _OgLInstantTransitionsBuilder(),
            TargetPlatform.fuchsia: _OgLInstantTransitionsBuilder(),
          },
        );
      case 2:
        return const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: ZoomPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.windows: ZoomPageTransitionsBuilder(),
            TargetPlatform.linux: ZoomPageTransitionsBuilder(),
            TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
          },
        );
      case 3:
        return const PageTransitionsTheme(
          builders: <TargetPlatform, PageTransitionsBuilder>{
            TargetPlatform.android: _OgLEnhancedTransitionsBuilder(),
            TargetPlatform.iOS: _OgLEnhancedTransitionsBuilder(),
            TargetPlatform.macOS: _OgLEnhancedTransitionsBuilder(),
            TargetPlatform.windows: _OgLEnhancedTransitionsBuilder(),
            TargetPlatform.linux: _OgLEnhancedTransitionsBuilder(),
            TargetPlatform.fuchsia: _OgLEnhancedTransitionsBuilder(),
          },
        );
      case 1:
      default:
        // 显式使用 Flutter 默认过渡，等价于"不做覆盖"。
        return const PageTransitionsTheme();
    }
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

/// 增强过渡：淡入 + 轻微上移 + 轻微放大。
class _OgLEnhancedTransitionsBuilder extends PageTransitionsBuilder {
  const _OgLEnhancedTransitionsBuilder();

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
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      ),
    );
  }
}
