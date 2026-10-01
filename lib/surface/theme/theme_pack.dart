/// L3 展示级 · 主题体系：主题包（Theme Pack）。
///
/// ## 一套主题包 = 一份可序列化的"外观契约"
/// 内置三套（用户还可以加自己的）：
/// | 包 | 风格 | 圆角 | 层次 | 字体倾向 |
/// | --- | --- | --- | --- | --- |
/// | [OgLThemePacks.vscode] | 极客 · 冷峻 · 信息密集 | 2（锐利） | 纯描边 | 等宽优先 |
/// | [OgLThemePacks.winui3] | 原生 · 云母 · 柔和 | 8 | 柔和阴影 | 无衬线 |
/// | [OgLThemePacks.material3] | 圆润 · 通透 · 分色 | 12 | 色调抬升 | 无衬线 |
///
/// ## 与设计令牌的分工
/// - **令牌**回答"多高、多快、多重"（与主题无关的物理量）；
/// - **主题包**回答"什么颜色、多圆、有没有阴影"（纯审美）。
/// 两者正交，因此"换成极客风 + 大字体 + 平板三栏"是可以自由组合的。
library;

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
    return OgLThemePacks.vscode.paletteFor(brightness);
  }

  /// 该包是否支持指定明暗（决定设置页是否显示"跟随系统"之外的选项）。
  bool supports(OgLBrightness brightness) =>
      brightness == OgLBrightness.dark
          ? (paletteDark != null || seed != null)
          : (paletteLight != null || seed != null);
}

/// 内置主题包与解析。
abstract final class OgLThemePacks {
  /// 全部内置包（顺序即设置页展示顺序）。
  static List<OgLThemePack> get all => <OgLThemePack>[
        vscode,
        winui3,
        material3,
      ];

  /// 默认包：极客风（与产品定位一致）。
  static OgLThemePack get fallback => vscode;

  /// 按 ID 解析；未知 ID 回落默认（设置里的脏值不该让界面崩）。
  static OgLThemePack byId(String? id) {
    for (final pack in all) {
      if (pack.id == id) {
        return pack;
      }
    }
    return fallback;
  }

  /// VS Code 极客风：冷灰底 + 1px 描边 + 锐角 + 等宽优先。
  static const OgLThemePack vscode = OgLThemePack(
    id: 'vscode.geek',
    name: '极客（VS Code）',
    description: '冷灰底、1px 描边、锐角、等宽字体优先——为长时间读代码而设计',
    iconSetId: 'minimal.line',
    defaultRadius: OgLRadius.xs,
    elevation: OgLElevationModel.outlined,
    monospaceFirst: true,
    paletteDark: OgLPalette(
      background: Color(0xFF0D1117),
      surface: Color(0xFF161B22),
      surfaceAlt: Color(0xFF21262D),
      border: Color(0xFF30363D),
      borderStrong: Color(0xFF484F58),
      text: Color(0xFFE6EDF3),
      textDim: Color(0xFF8B949E),
      textFaint: Color(0xFF6E7681),
      accent: Color(0xFF58A6FF),
      onAccent: Color(0xFF0D1117),
      danger: Color(0xFFF85149),
      warning: Color(0xFFD29922),
      success: Color(0xFF3FB950),
      info: Color(0xFF58A6FF),
      selection: Color(0x3358A6FF),
      codeBackground: Color(0xFF161B22),
      shadow: Color(0xFF000000),
    ),
    paletteLight: OgLPalette(
      background: Color(0xFFFFFFFF),
      surface: Color(0xFFF6F8FA),
      surfaceAlt: Color(0xFFEAEEF2),
      border: Color(0xFFD0D7DE),
      borderStrong: Color(0xFFAFB8C1),
      text: Color(0xFF1F2328),
      textDim: Color(0xFF656D76),
      textFaint: Color(0xFF8C959F),
      accent: Color(0xFF0969DA),
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

  /// WinUI 3：云母底、8px 圆角、柔和阴影。
  static const OgLThemePack winui3 = OgLThemePack(
    id: 'winui3',
    name: 'WinUI 3',
    description: '原生 Windows 观感：云母质感、8px 圆角、柔和层次',
    iconSetId: 'material.outlined',
    defaultRadius: OgLRadius.md,
    elevation: OgLElevationModel.soft,
    paletteDark: OgLPalette(
      background: Color(0xFF202020),
      surface: Color(0xFF2B2B2B),
      surfaceAlt: Color(0xFF323232),
      border: Color(0xFF3D3D3D),
      borderStrong: Color(0xFF5A5A5A),
      text: Color(0xFFFFFFFF),
      textDim: Color(0xFFC5C5C5),
      textFaint: Color(0xFF9A9A9A),
      accent: Color(0xFF60CDFF),
      onAccent: Color(0xFF003A5C),
      danger: Color(0xFFFF99A4),
      warning: Color(0xFFFCE100),
      success: Color(0xFF6CCB5F),
      info: Color(0xFF60CDFF),
      selection: Color(0x3360CDFF),
      codeBackground: Color(0xFF272727),
      shadow: Color(0xFF000000),
    ),
    paletteLight: OgLPalette(
      background: Color(0xFFF3F3F3),
      surface: Color(0xFFFFFFFF),
      surfaceAlt: Color(0xFFEAEAEA),
      border: Color(0xFFE1E1E1),
      borderStrong: Color(0xFFC8C8C8),
      text: Color(0xFF1A1A1A),
      textDim: Color(0xFF5D5D5D),
      textFaint: Color(0xFF8A8A8A),
      accent: Color(0xFF005FB8),
      onAccent: Color(0xFFFFFFFF),
      danger: Color(0xFFC42B1C),
      warning: Color(0xFF9D5D00),
      success: Color(0xFF0F7B0F),
      info: Color(0xFF005FB8),
      selection: Color(0x33005FB8),
      codeBackground: Color(0xFFF6F6F6),
      shadow: Color(0xFF000000),
    ),
  );

  /// Material 3：由种子色生成整套色调（对比度由 M3 算法保证）。
  static final OgLThemePack material3 = OgLThemePack(
    id: 'material3',
    name: 'Material 3',
    description: '通过种子色生成完整色调体系，圆润通透，跨平台观感统一',
    iconSetId: 'material.outlined',
    defaultRadius: OgLRadius.lg,
    elevation: OgLElevationModel.tonal,
    seed: const Color(0xFF6750A4),
  );
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

TextTheme _textTheme(OgLPalette palette, OgLTokens tokens, bool monoFirst) {
  TextStyle style(OgLTypeToken token, {Color? color}) => TextStyle(
        fontSize: tokens.fontSize(token),
        height: token.height,
        fontWeight: FontWeight.values[(token.weight ~/ 100 - 1).clamp(0, 8)],
        letterSpacing: token.letterSpacing,
        color: color ?? palette.text,
        fontFamily: monoFirst == token.mono ? 'monospace' : null,
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