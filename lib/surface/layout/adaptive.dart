/// L3 展示级 · 布局：自适应引擎（横竖屏 / 大小屏 / 平板 / 桌面窗口 / DPI）。
///
/// ## 它解决什么
/// 同一个界面要同时长在：5 寸手机竖屏、6.7 寸手机横屏、小平板、
/// 12 寸平板横屏、Windows 上被拖到 380px 宽的窗口、以及 4K 显示器。
/// 如果每个页面自己写 `if (width > 600)`，三个月后必然到处不一致。
///
/// 所以规则**只在这里定义一次**，页面只消费 [OgLLayoutSpec] 的结论：
/// ```
/// 屏幕 → OgLViewport（含 DPI / 文字缩放 / 指针 / 安全区）
///      → OgLLayoutSpec（导航形态 / 分栏 / 列数 / 内容宽度）
///      → 页面（只管渲染，不做尺寸决策）
/// ```
///
/// ## DPI 为什么必须参与
/// 逻辑像素相同、物理像素不同的两台设备，观感差别在**细节**上：
/// - 发丝分割线：DPR=1 时 1 逻辑像素 = 1 物理像素（干净）；
///   DPR=3 时同样的写法会得到 3 物理像素的粗线（显脏）。
///   正确做法是 [OgLAdaptive.hairlineFor]：按 DPR 反算，永远只占 1 物理像素。
/// - 目标尺寸：屏幕物理尺寸决定"手指够不够得着"，
///   所以 [OgLAdaptive.diagonalInches] 用物理对角线判断平板 / 桌面。
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/design_tokens.dart';

/// 运行平台（权限、导航惯例、指针默认值都依赖它）。
enum OgLPlatformKind {
  /// Android。
  android,

  /// iOS / iPadOS。
  iOS,

  /// Windows。
  windows,

  /// Linux。
  linux,

  /// macOS。
  macOS,

  /// Web。
  web,

  /// 未知 / 其他。
  other;

  /// 是否桌面级平台（窗口可自由缩放、惯用鼠标）。
  bool get isDesktop =>
      this == OgLPlatformKind.windows ||
      this == OgLPlatformKind.linux ||
      this == OgLPlatformKind.macOS;

  /// 是否移动级平台。
  bool get isMobile =>
      this == OgLPlatformKind.android || this == OgLPlatformKind.iOS;

  /// 是否苹果平台（权限模型同源）。
  bool get isApple => this == OgLPlatformKind.iOS || this == OgLPlatformKind.macOS;
}

/// 屏幕尺寸等级（Material 3 的 window size class）。
///
/// 断点固定为 600 / 840 / 1200：这是"折叠屏展开""小平板"
/// "桌面窗口舒适宽度"三条经验分界，**不允许页面自行改**。
enum OgLScreenSize {
  /// < 600：手机竖屏、窄窗口。
  compact,

  /// 600–839：手机横屏、小平板竖屏。
  medium,

  /// 840–1199：平板横屏、桌面小窗。
  expanded,

  /// ≥ 1200：桌面 / 大平板。
  large;

  /// 由宽度判定等级。
  static OgLScreenSize fromWidth(double width) {
    if (width < 600) {
      return OgLScreenSize.compact;
    }
    if (width < 840) {
      return OgLScreenSize.medium;
    }
    if (width < 1200) {
      return OgLScreenSize.expanded;
    }
    return OgLScreenSize.large;
  }
}

/// 设备形态（由**物理对角线**判定，而不是逻辑宽度）。
enum OgLFormFactor {
  /// 手机。
  phone,

  /// 平板。
  tablet,

  /// 桌面 / 笔记本。
  desktop,

  /// 大屏（电视 / 投影：远距离观看，需要更大目标）。
  tv,
}

/// 主导航形态。
enum OgLNavKind {
  /// 底部栏（手机）。
  bottomBar,

  /// 侧边窄轨（图标 + 极少文字）。
  navRail,

  /// 侧边宽轨（图标 + 文字）。
  extendedRail,

  /// 抽屉（窄窗口 / 桌面小窗）。
  drawer;

  /// 是否占用水平空间。
  bool get isRail =>
      this == OgLNavKind.navRail || this == OgLNavKind.extendedRail;

  /// 导航占用的逻辑宽度（0 表示不占宽）。
  double get width => switch (this) {
        OgLNavKind.navRail => 72,
        OgLNavKind.extendedRail => 220,
        OgLNavKind.bottomBar || OgLNavKind.drawer => 0,
      };
}

/// 分栏形态。
enum OgLPaneLayout {
  /// 单栏（列表和详情是两个页面）。
  single,

  /// 列表 + 详情（左侧列表常驻）。
  listDetail,

  /// 列表 + 详情 + 附加面板（如 diff / 提交信息）。
  threePane;

  /// 常驻栏数。
  int get paneCount => switch (this) {
        OgLPaneLayout.single => 1,
        OgLPaneLayout.listDetail => 2,
        OgLPaneLayout.threePane => 3,
      };
}

/// 视口：一次渲染中所有"环境事实"的唯一来源。
class OgLViewport {
  /// 创建视口。
  const OgLViewport({
    required this.size,
    required this.devicePixelRatio,
    required this.textScale,
    required this.padding,
    required this.viewInsets,
    required this.platform,
    required this.pointer,
    this.reducedMotion = false,
  });

  /// 由 `MediaQueryData` 构造。
  ///
  /// 同时兼容桌面端（窗口可任意缩放，`size` 就是窗口大小）
  /// 与移动端（`size` 是屏幕减去系统栏后的可用区域）。
  factory OgLViewport.fromMediaQuery(
    MediaQueryData query, {
    required OgLPlatformKind platform,
    OgLPointerKind? pointer,
    bool? reducedMotion,
  }) {
    final ratio = query.devicePixelRatio;
    return OgLViewport(
      size: query.size,
      devicePixelRatio: ratio.isFinite && ratio > 0 ? ratio : 1,
      // 用 `textScaler.scale(1)` 而不是已废弃的 `textScaleFactor`：
      // 后者在新版 Flutter 上会触发 lint，而我们的 CI 是"警告即失败"。
      textScale: query.textScaler.scale(1),
      padding: query.padding,
      viewInsets: query.viewInsets,
      platform: platform,
      pointer: pointer ?? _defaultPointerFor(platform),
      reducedMotion: reducedMotion ?? false,
    );
  }

  /// 可用尺寸（逻辑像素）。
  final Size size;

  /// 设备像素比。
  final double devicePixelRatio;

  /// 系统文字缩放。
  final double textScale;

  /// 安全区内边距（刘海 / 挖孔 / 手势条）。
  final EdgeInsets padding;

  /// 被键盘等系统面板遮挡的边距。
  final EdgeInsets viewInsets;

  /// 平台。
  final OgLPlatformKind platform;

  /// 指针类型。
  final OgLPointerKind pointer;

  /// 是否开启"减少动态效果"。
  final bool reducedMotion;

  static OgLPointerKind _defaultPointerFor(OgLPlatformKind platform) =>
      platform.isDesktop ? OgLPointerKind.mouse : OgLPointerKind.touch;

  /// 宽度。
  double get width => size.width;

  /// 高度。
  double get height => size.height;

  /// 短边。
  double get shortestSide => math.min(width, height);

  /// 长边。
  double get longestSide => math.max(width, height);

  /// 是否横屏（等高时按横屏处理，避免布局在正方形窗口里抖动）。
  bool get isLandscape => width >= height;

  /// 是否竖屏。
  bool get isPortrait => !isLandscape;

  /// 屏幕尺寸等级。
  OgLScreenSize get sizeClass => OgLScreenSize.fromWidth(width);

  /// 屏幕对角线（英寸）。
  ///
  /// 用 `dp = 1/160 英寸` 这一 Android 基线换算——它比"逻辑宽度"
  /// 更能反映"这台设备到底有多大"，从而正确区分手机与平板。
  /// 注意：dp 已经密度无关，**不再参与 DPR 运算**（详见 [OgLAdaptive.diagonalInches]）。
  double get diagonalInches => OgLAdaptive.diagonalInches(size);

  /// 设备形态。
  OgLFormFactor get formFactor {
    final diagonal = diagonalInches;
    if (platform.isDesktop) {
      // 桌面接大屏时按大屏处理（远距离观看）。
      return diagonal >= 32 ? OgLFormFactor.tv : OgLFormFactor.desktop;
    }
    if (diagonal >= 20) {
      return OgLFormFactor.tv;
    }
    if (diagonal >= 7) {
      return OgLFormFactor.tablet;
    }
    return OgLFormFactor.phone;
  }

  /// 键盘 / 软键盘是否弹起。
  bool get keyboardVisible => viewInsets.bottom > 0;

  /// 可用高度（扣除键盘）。
  double get availableHeight => math.max(0, height - viewInsets.bottom);

  /// 发丝线宽度。
  double get hairline => OgLAdaptive.hairlineFor(devicePixelRatio);

  /// 推荐的密度（用户仍可在设置里覆盖）。
  ///
  /// 逻辑：桌面 + 鼠标 → 紧凑（信息密度优先）；
  /// 大屏触摸 → 宽松（远距离触达）；手机 → 标准。
  OgLDensity get suggestedDensity {
    if (platform.isDesktop && pointer == OgLPointerKind.mouse) {
      return OgLDensity.compact;
    }
    if (formFactor == OgLFormFactor.tv) {
      return OgLDensity.comfortable;
    }
    return OgLDensity.standard;
  }

  /// 解析出布局结论。
  OgLLayoutSpec get spec => OgLLayoutSpec.resolve(this);

  @override
  String toString() => 'OgLViewport(${size.width.toInt()}×${size.height.toInt()}, '
      'dpr=$devicePixelRatio, ${platform.name}, ${pointer.name}, '
      '${sizeClass.name}/${formFactor.name})';
}

/// 布局结论：页面只读它，不再自己做尺寸判断。
class OgLLayoutSpec {
  /// 创建布局结论。
  const OgLLayoutSpec({
    required this.sizeClass,
    required this.formFactor,
    required this.navigation,
    required this.panes,
    required this.gridColumns,
    required this.contentMaxWidth,
    required this.navigationWidth,
    required this.showNavLabels,
    required this.isLandscape,
  });

  /// 解析。
  ///
  /// 所有分支都写成**单调**的：宽度只会让信息"变多"，不会来回跳，
  /// 这样窗口拖动时布局不会反复闪烁。
  factory OgLLayoutSpec.resolve(OgLViewport viewport) {
    final width = viewport.width;
    final sizeClass = viewport.sizeClass;

    // ── 主导航 ──────────────────────────────────────────────
    // 极窄的桌面窗口用抽屉：把底部栏塞进桌面窗口是移动端习惯的误用。
    final OgLNavKind navigation;
    if (width < 600) {
      navigation = viewport.platform.isDesktop
          ? OgLNavKind.drawer
          : OgLNavKind.bottomBar;
    } else if (width < 1240) {
      navigation = OgLNavKind.navRail;
    } else {
      navigation = OgLNavKind.extendedRail;
    }

    // ── 分栏 ────────────────────────────────────────────────
    final OgLPaneLayout panes;
    if (width < 720) {
      panes = OgLPaneLayout.single;
    } else if (width < 1100) {
      panes = OgLPaneLayout.listDetail;
    } else {
      panes = OgLPaneLayout.threePane;
    }

    return OgLLayoutSpec(
      sizeClass: sizeClass,
      formFactor: viewport.formFactor,
      navigation: navigation,
      panes: panes,
      gridColumns: OgLAdaptive.gridColumns(width: width),
      contentMaxWidth: OgLAdaptive.contentMaxWidth(viewport.formFactor),
      navigationWidth: navigation.width,
      showNavLabels: navigation == OgLNavKind.extendedRail,
      isLandscape: viewport.isLandscape,
    );
  }

  /// 屏幕尺寸等级。
  final OgLScreenSize sizeClass;

  /// 设备形态。
  final OgLFormFactor formFactor;

  /// 主导航形态。
  final OgLNavKind navigation;

  /// 分栏形态。
  final OgLPaneLayout panes;

  /// 网格列数。
  final int gridColumns;

  /// 内容区最大宽度（`double.infinity` 表示不限）。
  final double contentMaxWidth;

  /// 导航占用宽度。
  final double navigationWidth;

  /// 导航是否显示文字标签。
  final bool showNavLabels;

  /// 是否横屏。
  final bool isLandscape;

  /// 除导航外的可用宽度。
  double contentWidth(double viewportWidth) =>
      math.max(0, viewportWidth - navigationWidth);

  @override
  String toString() => 'OgLLayoutSpec(${sizeClass.name}, ${navigation.name}, '
      '${panes.name}, cols=$gridColumns)';
}

/// 自适应工具函数（纯函数，全部可单测）。
abstract final class OgLAdaptive {
  /// 网格瓦片的目标宽度。
  ///
  /// **按窗口宽度分级，而不是按设备形态**——这一点是踩过坑才定下来的：
  /// 若瓦片宽度跟着"手机/平板"跳变，那么窗口被拖宽、跨过形态阈值的那一刻，
  /// 瓦片会突然变大，**列数反而减少**（用户看到的就是"越拖越挤"的跳动）。
  /// 现在的分级只与宽度有关，于是列数对宽度**严格单调**。
  static double tileWidthFor(double width) => switch (width) {
        < 600 => 150, // 手机竖屏：一行 2–3 个
        < 1200 => 190, // 平板 / 桌面小窗
        < 1920 => 230, // 桌面
        _ => 260, // 大屏
      };

  /// 内容区最大宽度：避免在 4K 上出现"一行 2000px 的正文"。
  static double contentMaxWidth(OgLFormFactor formFactor) =>
      switch (formFactor) {
        OgLFormFactor.phone => double.infinity,
        OgLFormFactor.tablet => 840,
        OgLFormFactor.desktop => 1120,
        OgLFormFactor.tv => 1440,
      };

  /// 网格列数：由宽度与瓦片目标宽度推导，夹在 `[2, 6]`。
  ///
  /// 只依赖宽度 ⇒ 对宽度单调 ⇒ 拖窗口时列数只增不减，不会来回跳。
  static int gridColumns({
    required double width,
    double spacing = 12,
  }) {
    final tile = tileWidthFor(width);
    // 先按"含间距"的等效宽度算，否则瓦片实际会比目标窄一档。
    final raw = ((width + spacing) / (tile + spacing)).floor();
    return raw.clamp(2, 6);
  }

  /// 发丝线宽度：**永远只占 1 物理像素**。
  ///
  /// DPR=1 → 1.0；2 → 0.5；3 → 0.333；4 → 0.25（下限 0.25 防消失）。
  static double hairlineFor(double devicePixelRatio) {
    if (!devicePixelRatio.isFinite || devicePixelRatio <= 0) {
      return OgLStroke.hairline;
    }
    return (1 / devicePixelRatio).clamp(0.25, 1);
  }

  /// 对角线长度（英寸，**dp 模型**）。
  ///
  /// `1 dp = 1/160 英寸` 是 Android 的定义——dp 本身已经是"密度无关"单位，
  /// 所以这里**不能**再乘除 [devicePixelRatio]：那等于把密度重复计入，
  /// 会让"高 DPI 手机"被误判成更小的设备（一个曾经真实存在过的 bug）。
  /// 设备像素比只在一处用到：[hairlineFor]。
  static double diagonalInches(Size logicalSize) =>
      math.sqrt(
        logicalSize.width * logicalSize.width +
            logicalSize.height * logicalSize.height,
      ) /
      160;

  /// 从若干候选值里按屏幕等级挑一个（页面书写更紧凑）。
  static T pick<T>(
    OgLScreenSize sizeClass, {
    required T compact,
    T? medium,
    T? expanded,
    T? large,
  }) =>
      switch (sizeClass) {
        OgLScreenSize.compact => compact,
        OgLScreenSize.medium => medium ?? compact,
        OgLScreenSize.expanded => expanded ?? medium ?? compact,
        OgLScreenSize.large => large ?? expanded ?? medium ?? compact,
      };

  /// 左右留白：宽屏上把内容居中，窄屏上贴边。
  static EdgeInsets horizontalGutter(
    OgLViewport viewport, {
    required double base,
  }) {
    final gutter = viewport.isLandscape && viewport.width >= 840
        ? base * 2
        : base;
    return EdgeInsets.symmetric(horizontal: gutter);
  }
}