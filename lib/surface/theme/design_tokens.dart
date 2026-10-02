/// L3 展示级 · 主题体系：设计令牌（Design Tokens）。
///
/// ## 为什么令牌必须是**纯 Dart**
/// 本文件**不 import 任何 Flutter**。原因有二：
/// 1. 令牌是"物理常数"，与渲染引擎无关，将来换渲染层不必改令牌；
/// 2. 它可以被**纯单元测试**覆盖——不需要 widget binding，跑得飞快。
///
/// ## 三条硬规则（后面所有界面都必须遵守）
/// 1. **不许硬编码尺寸**：间距 / 圆角 / 时长一律从 [OgLTokens] 取，
///    否则"紧凑密度"和"大字体"这两个设置会在某个角落静默失效。
/// 2. **触摸设备的最小点击目标不得小于 44**：密度档位只允许在
///    **鼠标**场景下把目标压小。这条是可访问性底线，不给"紧凑"让路。
/// 3. **文字缩放必须夹紧在 [0.85, 2.0]**：系统 3 倍字体会把布局撑爆，
///    与其静默错位，不如夹紧并让 UI 自己在 [OgLTokens.maxLinesHint] 上做取舍。
library;

/// 密度档位。
enum OgLDensity {
  /// 紧凑（桌面 / 高效率场景）。
  compact(0.875),

  /// 标准。
  standard(1),

  /// 宽松（触摸 / 大屏远距）。
  comfortable(1.2);

  /// 创建密度档位。
  const OgLDensity(this.scale);

  /// 尺寸缩放系数。
  final double scale;
}

/// 指针类型：决定最小点击目标。
enum OgLPointerKind {
  /// 触摸屏。
  touch,

  /// 鼠标 / 触控板。
  mouse,

  /// 手写笔。
  stylus,
}

/// 间距梯度（**基线值**，实际使用请经 [OgLTokens.space] 缩放）。
abstract final class OgLSpacing {
  /// 2。
  static const double xxs = 2;

  /// 4。
  static const double xs = 4;

  /// 8。
  static const double sm = 8;

  /// 12。
  static const double md = 12;

  /// 16。
  static const double lg = 16;

  /// 24。
  static const double xl = 24;

  /// 32。
  static const double xxl = 32;
}

/// 圆角梯度。
abstract final class OgLRadius {
  /// 0（直角，极客风）。
  static const double none = 0;

  /// 2（锐利）。
  static const double xs = 2;

  /// 4。
  static const double sm = 4;

  /// 8（WinUI 3 标准）。
  static const double md = 8;

  /// 12。
  static const double lg = 12;

  /// 16。
  static const double xl = 16;

  /// 3（Primer small：小徽标 / 小控件）。
  static const double small = 3;

  /// 6（Primer medium：按钮 / 输入框 / 卡片默认）。
  static const double medium = 6;

  /// 12（Primer large：面板 / 对话框）。
  static const double large = 12;

  /// 999（胶囊）。
  static const double pill = 999;
}

/// 描边宽度。
abstract final class OgLStroke {
  /// 2。
  static const double thick = 2;

  /// 1。
  static const double thin = 1;

  /// 0.5。
  static const double hairline = 0.5;
}

/// 动效时长。
///
/// 刻意**只保留四档且都偏短**：动画的职责是"让界面不显得死板"，
/// 不是"表演"。超过 400ms 的过场只会让高频操作变慢。
abstract final class OgLDuration {
  /// 0（关闭动效）。
  static const Duration instant = Duration.zero;

  /// 90ms：状态反馈（hover / press）。
  static const Duration fast = Duration(milliseconds: 90);

  /// 160ms：切换（tab / 选中）。
  static const Duration base = Duration(milliseconds: 160);

  /// 240ms：面板展开 / 收起。
  static const Duration slow = Duration(milliseconds: 240);

  /// 360ms：页面级过场（仅用于"换地方"，不用于高频操作）。
  static const Duration slower = Duration(milliseconds: 360);
}

/// 动效策略（对应"减少动态效果"无障碍开关）。
enum OgLMotionPolicy {
  /// 完整。
  full,

  /// 克制：去掉位移，只留淡入淡出。
  subtle,

  /// 无动效。
  none;

  /// 按策略缩放一个时长。
  Duration scale(Duration base) => switch (this) {
        OgLMotionPolicy.full => base,
        OgLMotionPolicy.subtle => Duration(
            milliseconds: (base.inMilliseconds * 0.6).round(),
          ),
        OgLMotionPolicy.none => OgLDuration.instant,
      };
}

/// 字阶中的一档。
class OgLTypeToken {
  /// 创建字阶。
  const OgLTypeToken({
    required this.size,
    required this.height,
    required this.weight,
    this.letterSpacing = 0,
    this.mono = false,
  });

  /// 字号（逻辑像素）。
  final double size;

  /// 行高倍数。
  final double height;

  /// 字重（100–900，避免依赖 Flutter 的 FontWeight）。
  final int weight;

  /// 字距。
  final double letterSpacing;

  /// 是否等宽字体（极客风的代码 / 数据展示）。
  final bool mono;
}

/// 字阶（**基线值**，实际字号 = size × textScale）。
class OgLTypeScale {
  /// 创建字阶。
  const OgLTypeScale({
    required this.display,
    required this.headline,
    required this.title,
    required this.body,
    required this.label,
    required this.data,
  });

  /// 默认字阶（桌面密度友好，最小正文 13）。
  const OgLTypeScale.standard()
      : display = const OgLTypeToken(size: 30, height: 1.2, weight: 600),
        headline = const OgLTypeToken(size: 22, height: 1.25, weight: 600),
        title = const OgLTypeToken(size: 16, height: 1.3, weight: 600),
        body = const OgLTypeToken(size: 14, height: 1.5, weight: 400),
        label = const OgLTypeToken(size: 12, height: 1.35, weight: 500),
        data = const OgLTypeToken(
          size: 13,
          height: 1.45,
          weight: 400,
          mono: true,
        );

  /// 展示级。
  final OgLTypeToken display;

  /// 标题级。
  final OgLTypeToken headline;

  /// 区块标题。
  final OgLTypeToken title;

  /// 正文。
  final OgLTypeToken body;

  /// 标签 / 辅助文字。
  final OgLTypeToken label;

  /// 数据 / 代码（等宽）。
  final OgLTypeToken data;
}

/// 等宽字体族名（**唯一定义处**）。
///
/// 用系统通用名 `monospace`：**零外部资源**（不打包 ttf），
/// Android / Windows / Linux / macOS 都能落到各自的默认等宽字体上。
const String kOgLMonoFamily = 'monospace';

/// 解析后的令牌集：**界面唯一允许读取尺寸的来源**。
class OgLTokens {
  /// 创建令牌集。
  const OgLTokens({
    required this.density,
    required this.textScale,
    required this.pointer,
    required this.hairline,
    this.reducedMotion = false,
    this.motionPolicy = OgLMotionPolicy.full,
  });

  /// 从"环境"解析出令牌。
  ///
  /// [textScale] 会被夹紧到 `[0.85, 2.0]`：系统给 3.0 时布局必然崩，
  /// 与其悄悄错位，不如夹紧并让界面自己截断（[maxLinesHint]）。
  /// [reducedMotion] 为真时动效全部置零（系统级无障碍开关）。
  /// [motionPolicy] 为用户级动效策略（设置页"动效：完整 / 克制 / 关闭"）——
  /// 必须经这里进入令牌，否则设置只是"存了不用"（点了没反应）。
  factory OgLTokens.resolve({
    OgLDensity density = OgLDensity.standard,
    double textScale = 1,
    OgLPointerKind pointer = OgLPointerKind.touch,
    double hairline = OgLStroke.hairline,
    bool reducedMotion = false,
    OgLMotionPolicy motionPolicy = OgLMotionPolicy.full,
  }) =>
      OgLTokens(
        density: density,
        textScale: textScale.clamp(_minTextScale, _maxTextScale),
        pointer: pointer,
        hairline: hairline,
        reducedMotion: reducedMotion,
        motionPolicy: motionPolicy,
      );

  static const double _minTextScale = 0.85;
  static const double _maxTextScale = 2;

  /// 密度。
  final OgLDensity density;

  /// 已夹紧的文字缩放。
  final double textScale;

  /// 指针类型。
  final OgLPointerKind pointer;

  /// 发丝线宽度（由设备像素比推导，见 `adaptive.dart` 的 `hairlineFor`）。
  final double hairline;

  /// 是否减少动效。
  final bool reducedMotion;

  /// 用户级动效策略（"完整 / 克制 / 关闭"）。
  final OgLMotionPolicy motionPolicy;

  /// 间距缩放。
  double space(double base) => base * density.scale;

  /// 圆角缩放（圆角不随文字缩放，只随密度）。
  double radius(double base) => base * density.scale;

  /// 描边宽度（发丝线随 DPR 走，其余随密度）。
  double stroke(double base) =>
      base <= OgLStroke.hairline ? hairline : base * density.scale;

  /// 字号（**唯一**允许计算字号的地方）。
  double fontSize(OgLTypeToken token) => token.size * textScale;

  /// 行高（逻辑像素）。
  double lineHeight(OgLTypeToken token) =>
      fontSize(token) * token.height;

  /// 最小点击目标。
  ///
  /// 触摸设备**永不低于 44**；只有鼠标场景才允许压到 28。
  double minTarget(OgLPointerKind kind) => switch (kind) {
        OgLPointerKind.touch =>
          density == OgLDensity.compact ? 44 : 48,
        OgLPointerKind.mouse => 28,
        OgLPointerKind.stylus => 32,
      };

  /// 目标高度（当前指针类型下的实际值）。
  double get targetSize => minTarget(pointer);

  /// 图标尺寸（随密度缩放，但不随文字缩放——图标缩放交给布局）。
  double iconSize({double base = 20}) => base * density.scale;

  /// 建议的最大行数：文字被放大到一定程度后，界面**必须**主动截断，
  /// 而不是让排版溢出。
  int get maxLinesHint => textScale >= 1.6 ? 2 : 3;

  /// 动效时长（受"减少动效"、用户策略与密度共同影响）。
  ///
  /// 优先级：系统级"减少动效" > 用户策略（关闭 → 归零；克制 → 时长缩至 60%）
  /// > 密度（紧凑档再快一档）。
  Duration motion(Duration base) {
    if (reducedMotion || motionPolicy == OgLMotionPolicy.none) {
      return OgLDuration.instant;
    }
    final Duration scaled = motionPolicy == OgLMotionPolicy.subtle
        ? motionPolicy.scale(base)
        : base;
    // 紧凑密度暗示"高频操作"，动效再快一档。
    if (density == OgLDensity.compact && scaled > OgLDuration.fast) {
      return Duration(milliseconds: (scaled.inMilliseconds * 0.8).round());
    }
    return scaled;
  }

  /// 复制并覆盖部分字段。
  OgLTokens copyWith({
    OgLDensity? density,
    double? textScale,
    OgLPointerKind? pointer,
    double? hairline,
    bool? reducedMotion,
    OgLMotionPolicy? motionPolicy,
  }) =>
      OgLTokens(
        density: density ?? this.density,
        textScale: textScale ?? this.textScale,
        pointer: pointer ?? this.pointer,
        hairline: hairline ?? this.hairline,
        reducedMotion: reducedMotion ?? this.reducedMotion,
        motionPolicy: motionPolicy ?? this.motionPolicy,
      );

  @override
  String toString() => 'OgLTokens(${density.name}, ×$textScale, '
      '${pointer.name}, hairline=$hairline, motion=${reducedMotion ? 'off' : 'on'})';
}
