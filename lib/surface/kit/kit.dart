/// OGL Kit —— 表面层组件套件（控件语义对齐 GitHub Primer 规范）。
///
/// ## 三条约定
/// 1. 一切尺寸 / 颜色 / 圆角 / 动效只从 `OgLTheme` 令牌读取，
///    组件内无硬编码视觉常量（密度、大字体、明暗切换因此全自动成立）；
/// 2. 组件只表达"语义"（primary / danger / info…），
///    主题（Primer 官方 / OGL 自研）决定最终观感；
/// 3. 触摸目标 ≥44 与"减少动效"由令牌层保证，组件不各写各的。
library;

export 'kit_action_list.dart';
export 'kit_banner.dart';
export 'kit_blankslate.dart';
export 'kit_box.dart';
export 'kit_button.dart';
export 'kit_dialog.dart';
export 'kit_label.dart';
export 'kit_page.dart';
export 'kit_segmented.dart';
export 'kit_skeleton.dart';
export 'kit_spinner.dart';
export 'kit_state_view.dart';
export 'kit_text_field.dart';
export 'kit_toggle.dart';
export 'kit_underline_nav.dart';
