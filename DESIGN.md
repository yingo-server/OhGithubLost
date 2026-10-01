---
version: "alpha"
name: OhGithubLost（OGL）
description: |
  GitHub 第三方客户端（Flutter 全平台）的视觉身份。
  两套主题：primer（GitHub Primer 官方，默认）与 ogl.spatial（自研）。
  机器可读令牌是规范值；散文部分解释"为什么"以及"怎么用"。
colors:
  # ── Primer（官方，默认主题）─────────────────────────────────────────
  primer-dark-background: "#0D1117"
  primer-dark-surface: "#161B22"
  primer-dark-surface-alt: "#21262D"
  primer-dark-border: "#30363D"
  primer-dark-border-strong: "#484F58"
  primer-dark-border-active: "#F78166"
  primer-dark-text: "#E6EDF3"
  primer-dark-text-dim: "#8B949E"
  primer-dark-text-faint: "#6E7681"
  primer-dark-accent: "#2F81F7"
  primer-dark-on-accent: "#FFFFFF"
  primer-dark-danger: "#F85149"
  primer-dark-warning: "#D29922"
  primer-dark-success: "#3FB950"
  primer-dark-info: "#2F81F7"
  primer-dark-selection: "#2F81F733"
  primer-dark-code-background: "#161B22"
  primer-dark-shadow: "#010409"
  primer-light-background: "#FFFFFF"
  primer-light-surface: "#F6F8FA"
  primer-light-surface-alt: "#EAEEF2"
  primer-light-border: "#D0D7DE"
  primer-light-border-strong: "#AFB8C1"
  primer-light-border-active: "#FD8C73"
  primer-light-text: "#1F2328"
  primer-light-text-dim: "#656D76"
  primer-light-text-faint: "#6E7781"
  primer-light-accent: "#0969DA"
  primer-light-on-accent: "#FFFFFF"
  primer-light-danger: "#CF222E"
  primer-light-warning: "#9A6700"
  primer-light-success: "#1A7F37"
  primer-light-info: "#0969DA"
  primer-light-selection: "#0969DA33"
  primer-light-code-background: "#F6F8FA"
  primer-light-shadow: "#1F2328"
  # ── OGL（自研主题）───────────────────────────────────────────────
  ogl-dark-background: "#0B0E13"
  ogl-dark-surface: "#12161D"
  ogl-dark-surface-alt: "#181E27"
  ogl-dark-border: "#2A3442"
  ogl-dark-border-strong: "#3D4A5C"
  ogl-dark-border-active: "#4C8DFF"
  ogl-dark-text: "#E8ECF2"
  ogl-dark-text-dim: "#9AA6B5"
  ogl-dark-text-faint: "#5C6B7E"
  ogl-dark-accent: "#4C8DFF"
  ogl-dark-on-accent: "#FFFFFF"
  ogl-dark-danger: "#F2555A"
  ogl-dark-warning: "#E5A50A"
  ogl-dark-success: "#4CC38A"
  ogl-dark-info: "#4C8DFF"
  ogl-dark-selection: "#4C8DFF33"
  ogl-dark-code-background: "#10151C"
  ogl-dark-shadow: "#000000"
  ogl-light-background: "#F7F8FA"
  ogl-light-surface: "#FFFFFF"
  ogl-light-surface-alt: "#F0F2F5"
  ogl-light-border: "#D8DDE5"
  ogl-light-border-strong: "#C3CAD4"
  ogl-light-border-active: "#2F6FEB"
  ogl-light-text: "#1A1F26"
  ogl-light-text-dim: "#5A6572"
  ogl-light-text-faint: "#8A94A3"
  ogl-light-accent: "#2F6FEB"
  ogl-light-on-accent: "#FFFFFF"
  ogl-light-danger: "#D03036"
  ogl-light-warning: "#B07A00"
  ogl-light-success: "#1F9D61"
  ogl-light-info: "#2F6FEB"
  ogl-light-selection: "#2F6FEB33"
  ogl-light-code-background: "#F3F5F8"
  ogl-light-shadow: "#000000"
typography:
  display:
    fontFamily: system-ui
    fontSize: 30px
    fontWeight: 600
    lineHeight: 1.2
  headline:
    fontFamily: system-ui
    fontSize: 22px
    fontWeight: 600
    lineHeight: 1.25
  title:
    fontFamily: system-ui
    fontSize: 16px
    fontWeight: 600
    lineHeight: 1.3
  body:
    fontFamily: system-ui
    fontSize: 14px
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: system-ui
    fontSize: 12px
    fontWeight: 500
    lineHeight: 1.35
  data:
    fontFamily: monospace
    fontSize: 13px
    fontWeight: 400
    lineHeight: 1.45
rounded:
  none: 0px
  xs: 2px
  sm: 4px
  md: 8px
  lg: 12px
  xl: 16px
  small: 3px
  medium: 6px
  large: 12px
  pill: 999px
spacing:
  xxs: 2px
  xs: 4px
  sm: 8px
  md: 12px
  lg: 16px
  xl: 24px
  xxl: 32px
components:
  button-primary:
    backgroundColor: "{colors.primer-dark-accent}"
    textColor: "{colors.primer-dark-on-accent}"
    rounded: "{rounded.medium}"
    padding: 12px
    height: 32px
  button-standard:
    backgroundColor: "{colors.primer-dark-surface}"
    textColor: "{colors.primer-dark-text}"
    rounded: "{rounded.medium}"
    height: 32px
  button-standard-hover:
    backgroundColor: "{colors.primer-dark-surface-alt}"
  button-danger:
    backgroundColor: "{colors.primer-dark-danger}"
    textColor: "{colors.primer-dark-on-accent}"
    rounded: "{rounded.medium}"
    height: 32px
  text-input:
    backgroundColor: "{colors.primer-dark-background}"
    textColor: "{colors.primer-dark-text}"
    rounded: "{rounded.medium}"
    height: 32px
  text-input-focus:
    backgroundColor: "{colors.primer-dark-accent}"
  text-input-invalid:
    backgroundColor: "{colors.primer-dark-danger}"
  nav-underline-active:
    backgroundColor: "{colors.primer-dark-border-active}"
    height: 2px
  segmented-selected:
    backgroundColor: "{colors.primer-dark-surface}"
    textColor: "{colors.primer-dark-text}"
    rounded: "{rounded.medium}"
  dialog:
    backgroundColor: "{colors.primer-dark-surface}"
    textColor: "{colors.primer-dark-text}"
    rounded: "{rounded.large}"
    padding: 24px
  banner-info:
    backgroundColor: "{colors.primer-dark-surface}"
    textColor: "{colors.primer-dark-info}"
  banner-danger:
    backgroundColor: "{colors.primer-dark-surface}"
    textColor: "{colors.primer-dark-danger}"
  label-neutral:
    backgroundColor: "{colors.primer-dark-surface-alt}"
    textColor: "{colors.primer-dark-text-dim}"
    rounded: "{rounded.pill}"
  label-accent:
    backgroundColor: "{colors.primer-dark-surface-alt}"
    textColor: "{colors.primer-dark-accent}"
    rounded: "{rounded.pill}"
  action-row:
    backgroundColor: "{colors.primer-dark-background}"
    textColor: "{colors.primer-dark-text}"
    height: 48px
  action-row-hover:
    backgroundColor: "{colors.primer-dark-surface-alt}"
  skeleton:
    backgroundColor: "{colors.primer-dark-surface-alt}"
    rounded: "{rounded.medium}"
  page-header:
    backgroundColor: "{colors.primer-dark-background}"
    textColor: "{colors.primer-dark-text}"
  empty-state:
    backgroundColor: "{colors.primer-dark-background}"
    textColor: "{colors.primer-dark-text-dim}"
  blankslate:
    backgroundColor: "{colors.primer-dark-background}"
    textColor: "{colors.primer-dark-text-dim}"
    rounded: "{rounded.medium}"
  box:
    backgroundColor: "{colors.primer-dark-surface}"
    textColor: "{colors.primer-dark-text}"
    rounded: "{rounded.medium}"
  box-header:
    backgroundColor: "{colors.primer-dark-surface-alt}"
    textColor: "{colors.primer-dark-text}"
  toggle-track-off:
    backgroundColor: "{colors.primer-dark-surface-alt}"
    rounded: "{rounded.pill}"
  toggle-track-on:
    backgroundColor: "{colors.primer-dark-accent}"
    rounded: "{rounded.pill}"
---

## Overview

**OhGithubLost（OGL）** 是一个 GitHub 第三方客户端（Flutter 全平台）。它的视觉身份只有两套皮肤：

| 包 | id | 定位 |
| --- | --- | --- |
| **Primer（官方，默认）** | `primer` | 按 GitHub Primer 功能令牌落地：功能色角色、发丝描边、6px 圆角、信息密度适中 |
| **OGL（自研）** | `ogl.spatial` | 深空底 + 单一强调色 + 大留白；通用性优先 |

两者都支持明暗双模，**只保留这两个**（历史上 vscode / winui3 / material3 / spatial 实验主题全部退役）。

三条铁律（由 CI 强制，见 `test/surface/*`）：

1. **颜色只经语义令牌**：页面不得写字面色（`Colors.red` 直接被拦），取色走 `OgLPalette` / `colorFor(OgLSemanticColor)`。
2. **尺寸只经令牌**：间距 / 圆角 / 描边 / 动效一律从 `OgLTokens` 取，禁止硬编码 `16.0`。
3. **图标只经语义名**：只允许 `OgLIconName`（后期为自绘矢量包），禁止写 `Icons.xxx`。

规范家族（读的顺序）：本文件（视觉身份，机器可读）→ [`docs/UI_SYSTEM_V3.md`](docs/UI_SYSTEM_V3.md)（控件级规格与落地勾选）→ [`docs/SURFACE.md`](docs/SURFACE.md)（工程铁律：断点 / 发丝线 / ≥44 / 减少动效）→ [`docs/refs/prime`](docs/refs/prime)（Primer 全量组件文档）。

**一致性由测试锁定**：`test/surface/design_spec_sync_test.dart` 逐项核对本文件的颜色 / 间距 / 圆角令牌与 `theme_pack.dart` / `design_tokens.dart`；任何一边漂移都会红。

## Colors

四套调色板（= 两主题 × 明暗）共用同一组**语义角色**。取色只许走角色，不许走色值：

| 角色 | 含义 | Primer 暗 | Primer 亮 | OGL 暗 | OGL 亮 |
| --- | --- | --- | --- | --- | --- |
| background | 主背景（页面底） | `#0D1117` | `#FFFFFF` | `#0B0E13` | `#F7F8FA` |
| surface | 卡片 / 面板 / 代码块底 | `#161B22` | `#F6F8FA` | `#12161D` | `#FFFFFF` |
| surface-alt | 次级面板 / 悬停底 | `#21262D` | `#EAEEF2` | `#181E27` | `#F0F2F5` |
| border | 分割线（发丝） | `#30363D` | `#D0D7DE` | `#2A3442` | `#D8DDE5` |
| border-strong | 强描边（输入框 / 聚焦） | `#484F58` | `#AFB8C1` | `#3D4A5C` | `#C3CAD4` |
| border-active | 活动下划线（选中标签） | `#F78166` | `#FD8C73` | `#4C8DFF` | `#2F6FEB` |
| text | 主文字 | `#E6EDF3` | `#1F2328` | `#E8ECF2` | `#1A1F26` |
| text-dim | 次级文字 | `#8B949E` | `#656D76` | `#9AA6B5` | `#5A6572` |
| text-faint | 三级文字（时间戳 / 占位） | `#6E7681` | `#6E7781` | `#5C6B7E` | `#8A94A3` |
| accent | 强调色（主按钮 / 链接） | `#2F81F7` | `#0969DA` | `#4C8DFF` | `#2F6FEB` |
| on-accent | 强调色上的文字 | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| danger | 危险 / 失败 | `#F85149` | `#CF222E` | `#F2555A` | `#D03036` |
| warning | 注意 / 警告 | `#D29922` | `#9A6700` | `#E5A50A` | `#B07A00` |
| success | 成功 | `#3FB950` | `#1A7F37` | `#4CC38A` | `#1F9D61` |
| info | 信息 | `#2F81F7` | `#0969DA` | `#4C8DFF` | `#2F6FEB` |
| selection | 选中底（20% 透明强调色） | `#2F81F733` | `#0969DA33` | `#4C8DFF33` | `#2F6FEB33` |
| code-background | 代码块底 | `#161B22` | `#F6F8FA` | `#10151C` | `#F3F5F8` |
| shadow | 阴影（仅预留） | `#010409` | `#1F2328` | `#000000` | `#000000` |

规则：

- **状态色收敛**：成功 / 失败 / 警告 / 信息一律从语义色取，页面不得各写各的红绿。
- **选中态**用 `selection`（半透明强调色），不用纯色块。
- **用户自定义强调色必须真的生效**（`buildOgLTheme(accentOverride:)`）——存了不用的设置等于"点了没反应"。
- 亮色下 accent / info / success / danger 一律使用深一档的色值（Primer 亮色令牌），保证正文对比度 ≥ 4.5:1。

## Typography

| 令牌 | 字号 | 字重 | 行高 | 用法 |
| --- | --- | --- | --- | --- |
| display | 30 | 600 | 1.2 | 空态大标题 / 登录页主标题 |
| headline | 22 | 600 | 1.25 | 页面标题 |
| title | 16 | 600 | 1.3 | 区块标题 / 列表主文本强调 / 按钮 |
| body | 14 | 400 | 1.5 | 正文 |
| label | 12 | 500 | 1.35 | 标签 / 辅助文字 / 计数 |
| data | 13 | 400 | 1.45 | 代码 / SHA / 数据（等宽） |

- **字族**：非等宽 = 平台默认无衬线（`fontFamily = null`）；等宽 = 系统 `monospace`。**零外部字体**（不打包 ttf）。
- **缩放**：系统文字缩放夹紧在 `[0.85, 2.0]`；`textScale ≥ 1.6` 时界面主动把行数上限降到 2（`OgLTokens.maxLinesHint`），宁可截断不可溢出。

## Layout

- **间距刻度**：`xxs 2 · xs 4 · sm 8 · md 12 · lg 16 · xl 24 · xxl 32`，实际使用一律经 `OgLTokens.space()`（随密度缩放）。
- **断点只有三个**：`600 / 840 / 1200`。
  - 导航形态：`<600` 底栏（移动）/ 抽屉（桌面）→ `<1240` 窄轨 → `≥1240` 宽轨；
  - 分栏：`<720` 单栏 → `<1100` 列表 + 详情 → 三栏；列数 / 栏数对宽度严格单调。
- **触摸目标 ≥ 44**（`compact` 密度也不破例）；鼠标场景才允许 28。
- **发丝线 = 1 物理像素**（`tokens.hairline`，随 DPR 推导），禁止写 `thickness: 1`。
- **动效四档**：`fast 90ms`（hover / press）· `base 160ms`（切换）· `slow 240ms`（面板）· `slower 360ms`（换页）。系统"减少动态效果" ⇒ 全部归零。

## Elevation & Depth

- 两套主题都是 **outlined 模型**：**没有阴影**，层级靠底色差（`background → surface → surface-alt`）+ 1px 描边表达。
- 焦点：`focusColor = selection`；悬停：`hoverColor = surface-alt`。键盘用户必须"看得见焦点在哪"。
- `shadow` 令牌仅为将来 soft 模型预留，当前两主题**不使用**。

## Shapes

- **圆角**：`none 0 · xs 2 · sm 4 · md 8 · lg 12 · xl 16 · small 3 · medium 6 · large 12 · pill 999`；与 Primer 对齐（small 3 / medium 6 / large 12）。
- **描边**：`hairline 0.5`（发丝，随 DPR）· `thin 1` · `thick 2`。
- 形状语言：**直角偏锐**——除 `pill`（标签）与 `large`（对话框）外，一律 ≤ 12px。

## Components

组件规格与实现状态的真源是 [`docs/UI_SYSTEM_V3.md`](docs/UI_SYSTEM_V3.md)（逐控件：Primer 对照 / 状态 / 尺寸 / 令牌 / 实现文件 / 测试 / 勾选）。本表只是索引：

| 组件 | Primer 对照 | 实现 |
| --- | --- | --- |
| Button（primary / standard / danger / invisible） | `content/components/button.mdx` | `lib/surface/kit/kit_button.dart` |
| TextField | `content/components/text-input.mdx` | `lib/surface/kit/kit_text_field.dart` |
| Dialog（确认 / 输入） | `content/components/dialog.mdx` | `lib/surface/kit/kit_dialog.dart` |
| Banner | `content/components/banner.mdx` | `lib/surface/kit/kit_banner.dart` |
| Label / CounterLabel / StateLabel | `content/components/label.mdx` · `state-label.mdx` | `lib/surface/kit/kit_label.dart` |
| ActionRow（列表行） | `content/components/action-list.mdx` | `lib/surface/kit/kit_action_list.dart` |
| Spinner / ProgressBar | `content/components/spinner.mdx` · `progress-bar.mdx` | `lib/surface/kit/kit_spinner.dart` |
| Skeleton（Box / Text / Avatar） | `content/components/skeleton-box.mdx` 等 | `lib/surface/kit/kit_skeleton.dart` |
| PageHeader | `content/components/page-header.mdx` | `lib/surface/kit/kit_page.dart` |
| UnderlineNav | `content/components/underline-nav.mdx` | `lib/surface/kit/kit_underline_nav.dart` |
| Segmented | `content/components/segmented-control.mdx` | `lib/surface/kit/kit_segmented.dart` |
| Icon（矢量） | `content/components/icon.mdx` · `octicons` | `lib/surface/icons/`（W3 落地） |
| 空态 / 错误态模板 | `content/components/blankslate.mdx` | 页面三态模板（W2 统一） |

> 组件令牌的 YAML 引用以**默认主题（Primer 暗色）**为基准；其余三套调色板的对应值见 Colors 一节。

## Do's and Don'ts

**Do**

- 用语义角色取色、用令牌取尺寸、用 `OgLIconName` 取图标。
- 空态给文案 + 下一步动作；错误态给"可重试"；加载态 `<1s` 不显示、`1–3s` spinner、`3s+` 进度。
- 触摸目标 ≥ 44；键盘焦点可见；"减少动效"时动效归零。
- 新增控件先写规范（本文件 + `UI_SYSTEM_V3.md` 条目），再写实现，再补测试。

**Don't**

- 不硬编码颜色 / 间距 / 圆角 / 时长；不在页面里构造 `ThemeData`。
- 不写 `Icons.xxx`（图标必须走语义名）；不引外部字体 / 图片资源。
- 不做静默失败（错误必须可见：弹窗 + 日志）；不做"点了没反应"的按钮。
- 不用超过 400ms 的过场；不用阴影（当前两主题）。
