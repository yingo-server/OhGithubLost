/// L3 展示级 · 主题体系：主题包（Theme Pack）。
///
/// ## 一套主题包 = 一份可序列化的"外观契约"
/// 内置两套（产品决策：只保留两个主题）：
/// | 包 | 风格 | 圆角 | 层次 | 字体倾向 |
/// | --- | --- | --- | --- | --- |
/// | [OgLThemePacks.primer] | GitHub Primer 官方规范 | 6 | 纯描边 | 无衬线 |
/// | [OgLThemePacks.ogl] | OGL 自研 · 深空极简 | 12 | 纯描边 | 无衬线 |
///
/// ## 与设计令牌的分工
/// - **令牌**回答"多高、多快、多重"（与主题无关的物理量）；
/// - **主题包**回答"什么颜色、多圆、有没有阴影"（纯审美）。
/// 两者正交，因此"换成极客风 + 大字体 + 平板三栏"是可以自由组合的。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../layout/adaptive.dart';
import 'design_tokens.dart';
import 'icon_pack.dart';

/// 明暗模式。
enum OgLBrightness {
  /// 亮色。
  light,

  /// 暗色。
  dark;

  /// 转 Flutter。
  Brightness get flutter =>
      this == OgLBrightness.dark ? Brightness.dark : Brightness.light;
}

/// 层次模型（决定"抬升"是用阴影还是描边）。
enum OgLElevationModel {
  /// 纯描边（极客风：没有阴影，靠 1px 线区分层级）。
  outlined,

  /// 柔和阴影（WinUI 3 风格）。
  soft,

  /// 色调抬升（Material 3：用 surface 色调差而非阴影）。
  tonal;

  /// 该模型是否使用阴影。
  bool get usesShadow => this == OgLElevationModel.soft;
}

/// 调色板（界面唯一允许取色的地方）。
class OgLPalette {
  /// 创建调色板。
  const OgLPalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.danger,
    required this.warning,
    required this.success,
    required this.info,
    required this.selection,
    required this.codeBackground,
    required this.shadow,
  });

  /// 由 Material 色彩方案派生（用于"靠种子生成调色板"的主题包）。
  ///
  /// 这条路径保证：即使主题包只提供一个种子色，
  /// 也能得到一套**对比度合规**的完整调色板（M3 的色调算法负责这件事）。
  factory OgLPalette.fromScheme(ColorScheme scheme) => OgLPalette(
        background: scheme.surface,
        surface: scheme.surfaceContainerLow,
        surfaceAlt: scheme.surfaceContainerHigh,
        border: scheme.outlineVariant,
        borderStrong: scheme.outline,
        text: scheme.onSurface,
        textDim: scheme.onSurfaceVariant,
        textFaint: scheme.outline,
        accent: scheme.primary,
        onAccent: scheme.onPrimary,
        danger: scheme.error,
        warning: scheme.tertiary,
        success: scheme.secondary,
        info: scheme.primary,
        selection: scheme.primary.withAlpha(46), // ≈ alpha 0.18
        codeBackground: scheme.surfaceContainerHighest,
        shadow: scheme.shadow,
      );

  /// 主背景。
  final Color background;

  /// 卡片 / 面板底色。
  final Color surface;

  /// 次级面板（列表条目、hover）。
  final Color surfaceAlt;

  /// 分割线（发丝）。
  final Color border;

  /// 强描边（输入框、聚焦）。
  final Color borderStrong;

  /// 主文字。
  final Color text;

  /// 次级文字。
  final Color textDim;

  /// 三级文字（占位 / 时间戳）。
  final Color textFaint;

  /// 强调色（选中、主按钮）。
  final Color accent;

  /// 强调色上的文字。
  final Color onAccent;

  /// 危险。
  final Color danger;

  /// 警告。
  final Color warning;

  /// 成功。
  final Color success;

  /// 信息。
  final Color info;

  /// 选中底色。
  final Color selection;

  /// 代码块底色。
  final Color codeBackground;

  /// 阴影色。
  final Color shadow;

  /// 复制并覆盖。
  OgLPalette copyWith({Color? accent}) => OgLPalette(
        background: background,
        surface: surface,
        surfaceAlt: surfaceAlt,
        border: border,
        borderStrong: borderStrong,
        text: text,
        textDim: textDim,
        textFaint: textFaint,
        accent: accent ?? this.accent,
        onAccent: onAccent,
        danger: danger,
        warning: warning,
        success: success,
        info: info,
        selection: selection,
        codeBackground: codeBackground,
        shadow: shadow,
      );
}

/// 主题包。
class OgLThemePack {
  /// 创建主题包。
  const OgLThemePack({
    required this.id,
    required this.name,
    required this.description,
    required this.iconSetId,
    required this.defaultRadius,
    required this.elevation,
    this.monospaceFirst = false,
    this.paletteLight,
    this.paletteDark,
    this.seed,
  });

  /// ID（进设置持久化）。
  final String id;

  /// 显示名。
  final String name;

  /// 一句话描述（设置页展示）。
  final String description;

  /// 默认图标包 ID。
  final String iconSetId;

  /// 默认圆角。
  final double defaultRadius;

  /// 层次模型。
  final OgLElevationModel elevation;

  /// 是否等宽字体优先（极客风）。
  final bool monospaceFirst;

  /// 亮色调色板（与 [seed] 二选一）。
  final OgLPalette? paletteLight;

  /// 暗色调色板（与 [seed] 二选一）。
  final OgLPalette? paletteDark;

  /// 种子色（用于按 M3 算法生成调色板）。
  final Color? seed;

  /// 取指定明暗的调色板。
  ///
  /// **绝不抛异常**：缺调色板时按种子生成；连种子都没有时回落默认包。
  OgLPalette paletteFor(OgLBrightness brightness) {
    final explicit =
        brightness == OgLBrightness.dark ? paletteDark : paletteLight;
    if (explicit != null) {
      return explicit;
    }
    final seedColor = seed;
    if (seedColor != null) {
      return OgLPalette.fromScheme(
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: brightness.flutter,
        ),
      );
    }
    return OgLThemePacks.primer.paletteFor(brightness);
  }

  /// 该包是否支持指定明暗（决定设置页是否显示"跟随系统"之外的选项）。
  bool supports(OgLBrightness brightness) =>
      brightness == OgLBrightness.dark
          ? (paletteDark != null || seed != null)
          : (paletteLight != null || seed != null);
}

/// 内置主题包与解析。
abstract final class OgLThemePacks {
  /// 全部内置包（顺序即设置页展示顺序；Primer 官方置于首位）。
  static List<OgLThemePack> get all => <OgLThemePack>[
        primer,
        ogl,
      ];

  /// 默认包：**Primer（官方）**（按 GitHub Primer 规范落地）。
  static OgLThemePack get fallback => primer;

  /// 按 ID 解析；未知 ID 回落默认（设置里的脏值不该让界面崩）。
  static OgLThemePack byId(String? id) {
    for (final pack in all) {
      if (pack.id == id) {
        return pack;
      }
    }
    return fallback;
  }

  /// Primer（官方）：GitHub 产品界面的设计语言 —— 功能色角色 + 发丝描边 + 6px 圆角。
  ///
  /// 取值按 Primer 功能令牌（bgColor-default / bgColor-muted /
  /// borderColor-default / fgColor-default / fgColor-muted /
  /// fgColor-accent / bgColor-accent-emphasis / fgColor-onEmphasis +
  /// success / attention / danger 语义色），明暗双模均齐。
  static const OgLThemePack primer = OgLThemePack(
    id: 'primer',
    name: 'Primer（官方）',
    description: 'GitHub 官方设计系统：功能色角色、发丝描边、6px 圆角、信息密度适中',
    iconSetId: 'material.outlined',
    defaultRadius: OgLRadius.medium,
    elevation: OgLElevationModel.outlined,
    paletteDark: OgLPalette(
      background: Color(0xFF0D1117), // bgColor-default（dark）
      surface: Color(0xFF161B22), // bgColor-muted（dark）
      surfaceAlt: Color(0xFF21262D), // hover / 次级面板
      border: Color(0xFF30363D), // borderColor-default（dark）
      borderStrong: Color(0xFF484F58), // 强描边（控件边界）
      text: Color(0xFFE6EDF3), // fgColor-default（dark）
      textDim: Color(0xFF8B949E), // fgColor-muted（dark）
      textFaint: Color(0xFF6E7681), // fgColor-subtle（dark）
      accent: Color(0xFF2F81F7), // fgColor-accent（dark）
      onAccent: Color(0xFFFFFFFF), // fgColor-onEmphasis
      danger: Color(0xFFF85149), // fgColor-danger（dark）
      warning: Color(0xFFD29922), // fgColor-attention（dark）
      success: Color(0xFF3FB950), // fgColor-success（dark）
      info: Color(0xFF2F81F7),
      selection: Color(0x332F81F7), // accent-muted ≈ 20% 选中底
      codeBackground: Color(0xFF161B22),
      shadow: Color(0xFF010409),
    ),
    paletteLight: OgLPalette(
      background: Color(0xFFFFFFFF), // bgColor-default（light）
      surface: Color(0xFFF6F8FA), // bgColor-muted（light）
      surfaceAlt: Color(0xFFEAEEF2), // hover / 次级面板
      border: Color(0xFFD0D7DE), // borderColor-default（light）
      borderStrong: Color(0xFFAFB8C1),
      text: Color(0xFF1F2328), // fgColor-default（light）
      textDim: Color(0xFF656D76), // fgColor-muted（light）
      textFaint: Color(0xFF6E7781), // fgColor-subtle（light）
      accent: Color(0xFF0969DA), // fgColor-accent（light）
      onAccent: Color(0xFFFFFFFF),
      danger: Color(0xFFCF222E),
      warning: Color(0xFF9A6700),
      success: Color(0xFF1A7F37),
      info: Color(0xFF0969DA),
      selection: Color(0x330969DA),
      codeBackground: Color(0xFFF6F8FA),
      shadow: Color(0xFF1F2328),
    ),
  );

  /// 「OGL」自研：深空底 + 发丝描边 + 单一强调色（通用性第一、性能第二）。
  static const OgLThemePack ogl = OgLThemePack(
    id: 'ogl.spatial',
    name: 'OGL（自研）',
    description: '自研风格：大留白、发丝描边、单一强调色；通用性优先',
    iconSetId: 'material.outlined',
    defaultRadius: OgLRadius.lg,
    elevation: OgLElevationModel.outlined,
    paletteDark: OgLPalette(
      background: Color(0xFF0B0E13),
      surface: Color(0xFF12161D),
      surfaceAlt: Color(0xFF181E27),
      border: Color(0xFF2A3442),
      borderStrong: Color(0xFF3D4A5C),
      text: Color(0xFFE8ECF2),
      textDim: Color(0xFF9AA6B5),
      textFaint: Color(0xFF5C6B7E),
      accent: Color(0xFF4C8DFF),
      onAccent: Color(0xFFFFFFFF),
      danger: Color(0xFFF2555A),
      warning: Color(0xFFE5A50A),
      success: Color(0xFF4CC38A),
      info: Color(0xFF4C8DFF),
      selection: Color(0x334C8DFF),
      codeBackground: Color(0xFF10151C),
      shadow: Color(0xFF000000),
    ),
    paletteLight: OgLPalette(
      background: Color(0xFFF7F8FA),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFF0F2F5),
      border: Color(0xFFD8DDE5),
      borderStrong: Color(0xFFC3CAD4),
      text: Color(0xFF1A1F26),
      textDim: Color(0xFF5A6572),
      textFaint: Color(0xFF8A94A3),
      accent: Color(0xFF2F6FEB),
      onAccent: Color(0xFFFFFFFF),
      danger: Color(0xFFD03036),
      warning: Color(0xFFB07A00),
      success: Color(0xFF1F9D61),
      info: Color(0xFF2F6FEB),
      selection: Color(0x332F6FEB),
      codeBackground: Color(0xFFF3F5F8),
      shadow: Color(0xFF000000),
    ),
  );

  // （历史上还有 vscode / winui3 / material3 / spatial 多套实验主题；
  //   产品决策：只保留「Primer（官方）」与「OGL（自研）」两套。）
}

/// 主题上下文：把"令牌 / 调色板 / 图标包 / 动效"打包进 Widget 树。
///
/// 之所以用 [ThemeExtension] 而不是自定义 InheritedWidget：
/// 它能被 Flutter 的 `ThemeData.lerp` 自动插值，主题切换时过渡不会闪。
@immutable
class OgLTheme extends ThemeExtension<OgLTheme> {
  /// 创建主题上下文。
  const OgLTheme({
    required this.tokens,
    required this.palette,
    required this.themeId,
    required this.iconSet,
    required this.layout,
    this.motion = OgLMotionPolicy.full,
  });

  /// 从 Widget 树里取（拿不到时用默认，**绝不抛**）。
  static OgLTheme of(BuildContext context) =>
      Theme.of(context).extension<OgLTheme>() ?? fallback;

  /// 兜底实例（widget 测试 / 极早期渲染用）。
  static final OgLTheme fallback = OgLTheme(
    tokens: OgLTokens.resolve(),
    palette: OgLThemePacks.fallback.paletteFor(OgLBrightness.dark),
    themeId: OgLThemePacks.fallback.id,
    iconSet: OgLIconSets.fallback,
    layout: OgLLayoutSpec.resolve(
      const OgLViewport(
        size: Size(400, 800),
        devicePixelRatio: 2,
        textScale: 1,
        padding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
        platform: OgLPlatformKind.android,
        pointer: OgLPointerKind.touch,
      ),
    ),
  );

  /// 设计令牌。
  final OgLTokens tokens;

  /// 调色板。
  final OgLPalette palette;

  /// 主题包 ID（诊断用）。
  final String themeId;

  /// 图标包。
  final OgLIconSet iconSet;

  /// 布局结论。
  final OgLLayoutSpec layout;

  /// 动效策略。
  final OgLMotionPolicy motion;

  /// 取图标。
  IconData icon(OgLIconName name) => iconSet.resolve(name);

  /// 按语义取色（把"状态色"收敛到一处，避免页面各写各的红绿）。
  Color colorFor(OgLSemanticColor semantic) => switch (semantic) {
        OgLSemanticColor.neutral => palette.text,
        OgLSemanticColor.dim => palette.textDim,
        OgLSemanticColor.faint => palette.textFaint,
        OgLSemanticColor.accent => palette.accent,
        OgLSemanticColor.danger => palette.danger,
        OgLSemanticColor.warning => palette.warning,
        OgLSemanticColor.success => palette.success,
        OgLSemanticColor.info => palette.info,
      };

  @override
  OgLTheme copyWith({
    OgLTokens? tokens,
    OgLPalette? palette,
    String? themeId,
    OgLIconSet? iconSet,
    OgLLayoutSpec? layout,
    OgLMotionPolicy? motion,
  }) =>
      OgLTheme(
        tokens: tokens ?? this.tokens,
        palette: palette ?? this.palette,
        themeId: themeId ?? this.themeId,
        iconSet: iconSet ?? this.iconSet,
        layout: layout ?? this.layout,
        motion: motion ?? this.motion,
      );

  @override
  OgLTheme lerp(covariant OgLTheme? other, double t) {
    if (other == null) {
      return this;
    }
    // 令牌与布局不做数值插值（密度 / 断点跳变时插值反而会闪），
    // 只插值颜色——这正是"主题切换要平滑、布局切换要干脆"的取舍。
    return OgLTheme(
      tokens: t < 0.5 ? tokens : other.tokens,
      palette: _lerpPalette(palette, other.palette, t),
      themeId: t < 0.5 ? themeId : other.themeId,
      iconSet: t < 0.5 ? iconSet : other.iconSet,
      layout: t < 0.5 ? layout : other.layout,
      motion: t < 0.5 ? motion : other.motion,
    );
  }

  static OgLPalette _lerpPalette(OgLPalette a, OgLPalette b, double t) =>
      OgLPalette(
        background: Color.lerp(a.background, b.background, t)!,
        surface: Color.lerp(a.surface, b.surface, t)!,
        surfaceAlt: Color.lerp(a.surfaceAlt, b.surfaceAlt, t)!,
        border: Color.lerp(a.border, b.border, t)!,
        borderStrong: Color.lerp(a.borderStrong, b.borderStrong, t)!,
        text: Color.lerp(a.text, b.text, t)!,
        textDim: Color.lerp(a.textDim, b.textDim, t)!,
        textFaint: Color.lerp(a.textFaint, b.textFaint, t)!,
        accent: Color.lerp(a.accent, b.accent, t)!,
        onAccent: Color.lerp(a.onAccent, b.onAccent, t)!,
        danger: Color.lerp(a.danger, b.danger, t)!,
        warning: Color.lerp(a.warning, b.warning, t)!,
        success: Color.lerp(a.success, b.success, t)!,
        info: Color.lerp(a.info, b.info, t)!,
        selection: Color.lerp(a.selection, b.selection, t)!,
        codeBackground: Color.lerp(a.codeBackground, b.codeBackground, t)!,
        shadow: Color.lerp(a.shadow, b.shadow, t)!,
      );
}

/// 语义色（页面只表达"这是什么状态"，不直接挑颜色）。
enum OgLSemanticColor {
  /// 常规文字。
  neutral,

  /// 次级文字。
  dim,

  /// 三级文字。
  faint,

  /// 强调。
  accent,

  /// 危险。
  danger,

  /// 警告。
  warning,

  /// 成功。
  success,

  /// 信息。
  info,
}

/// 把主题包编译成 Flutter 的 [ThemeData]。
///
/// 这是整个展示层**唯一**允许构造 `ThemeData` 的地方。
ThemeData buildOgLTheme({
  required OgLThemePack pack,
  required OgLBrightness brightness,
  required OgLTokens tokens,
  required OgLLayoutSpec layout,
  OgLMotionPolicy motion = OgLMotionPolicy.full,
  int? accentOverride,
}) {
  final base = pack.paletteFor(brightness);
  // 用户自定义强调色：**必须真的用上**。
  // 之前的版本把它存进了设置却从未消费——那就是典型的"点了没反应"。
  final palette =
      accentOverride == null ? base : base.copyWith(accent: Color(accentOverride));
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    brightness: brightness.flutter,
  ).copyWith(
    surface: palette.background,
    onSurface: palette.text,
    primary: palette.accent,
    onPrimary: palette.onAccent,
    error: palette.danger,
    outline: palette.borderStrong,
    outlineVariant: palette.border,
    shadow: palette.shadow,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness.flutter,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    dividerColor: palette.border,
    splashFactory: pack.elevation == OgLElevationModel.outlined
        // 极客风不要水波纹：那种"扩散的圆"与 1px 描边语言冲突。
        ? NoSplash.splashFactory
        : InkRipple.splashFactory,
    dividerTheme: DividerThemeData(
      // 发丝线 = 1 物理像素，而不是"1 逻辑像素"。
      thickness: tokens.hairline,
      space: tokens.hairline,
      color: palette.border,
    ),
    visualDensity: switch (tokens.density) {
      OgLDensity.compact => VisualDensity.compact,
      OgLDensity.standard => VisualDensity.standard,
      OgLDensity.comfortable => VisualDensity.comfortable,
    },
    // ── 交互反馈（键盘与鼠标用户的可感知性）─────────────────────────
    // 没有这两项的桌面应用，键盘用户按 Tab 走一圈会"看不见焦点在哪"，
    // 鼠标用户划过列表也毫无反馈 —— 这是社区里最常见的低级体验缺陷。
    focusColor: palette.selection,
    hoverColor: palette.surfaceAlt,
    textTheme: _textTheme(palette, tokens, pack.monospaceFirst),
    extensions: <ThemeExtension<dynamic>>[
      OgLTheme(
        tokens: tokens,
        palette: palette,
        themeId: pack.id,
        iconSet: OgLIconSets.byId(pack.iconSetId),
        layout: layout,
        motion: motion,
      ),
    ],
  );
}

/// 滚动行为：桌面端允许"鼠标 / 触控板拖拽滚动"。
///
/// Flutter 默认只让**触摸**拖拽滚动，桌面用户拿鼠标拖列表是拖不动的——
/// 这是社区里最常见的"一眼看出是移动端套壳"的细节。
/// 开源社区主流桌面 Flutter 应用都会覆盖这一个 getter。
class OgLScrollBehavior extends MaterialScrollBehavior {
  /// 创建滚动行为。
  const OgLScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}

TextTheme _textTheme(OgLPalette palette, OgLTokens tokens, bool monoFirst) {
  TextStyle style(OgLTypeToken token, {Color? color}) => TextStyle(
        fontSize: tokens.fontSize(token),
        height: token.height,
        fontWeight: FontWeight.values[(token.weight ~/ 100 - 1).clamp(0, 8)],
        letterSpacing: token.letterSpacing,
        color: color ?? palette.text,
        fontFamily: monoFirst == token.mono ? kOgLMonoFamily : null,
      );

  final scale = const OgLTypeScale.standard();
  return TextTheme(
    displaySmall: style(scale.display),
    headlineSmall: style(scale.headline),
    titleMedium: style(scale.title),
    bodyLarge: style(scale.body),
    bodyMedium: style(scale.body),
    bodySmall: style(scale.label, color: palette.textDim),
    labelLarge: style(scale.title),
    labelMedium: style(scale.label, color: palette.textDim),
    labelSmall: style(scale.label, color: palette.textFaint),
  );
}