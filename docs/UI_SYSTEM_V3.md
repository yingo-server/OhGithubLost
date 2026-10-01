# OGL 设计系统 v3（Primer 官方 + OGL 自研）

> 状态：**UI v3 重写进行中（第二阶段 W0 · 规范已落库）**。
> 本文件是**控件级规范与落地清单**；机器可读的视觉身份（颜色 / 字阶 / 圆角 / 间距令牌）真源是仓库根
> [`DESIGN.md`](../DESIGN.md)。两者由 `test/surface/design_spec_sync_test.dart` 对账。
>
> 规范来源：
> - 控件语义 / 配色 / 尺寸：**GitHub Primer**（仓库内快照 [`docs/refs/prime`](refs/prime)）
> - 方法与文件格式：**design.md**（仓库内快照 [`docs/refs/design-md`](refs/design-md)）
> - 工程铁律：沿用 [`SURFACE.md`](SURFACE.md)（断点 / 发丝线 / 触摸 ≥44 / 减少动效）

---

## 1. 两个主题（产品决策：只保留两个）

| id | 名称 | 定位 |
| --- | --- | --- |
| `primer` | **Primer（官方，默认）** | 按 Primer 功能令牌落地：`bgColor-default / bgColor-muted / borderColor-default / fgColor-default / fgColor-muted / fgColor-accent / fgColor-onEmphasis` + success / attention / danger 语义色；圆角 6；发丝描边 |
| `ogl.spatial` | **OGL（自研）** | 深空底 + 单一强调色 + 大留白；通用性优先 |

已移除：`vscode.geek` / `winui3` / `material3`（历史实验包，全部退役）。

## 2. 令牌（与主题正交）

- **机器可读真源**：`DESIGN.md` —— 颜色 4 套调色板 × 18 角色 / 字阶 6 档 / 间距 7 档 / 圆角 8 档。
- **代码真源**：`lib/surface/theme/design_tokens.dart`（物理令牌）+ `lib/surface/theme/theme_pack.dart`（调色板）。
- 页面不得写死色值 / 尺寸：取色走 `OgLPalette` / `colorFor(OgLSemanticColor)`，取尺寸走 `OgLTokens`。
- 圆角对齐 Primer：`small = 3` · `medium = 6` · `large = 12`。
- 图标一律走 `OgLIconName` 语义层（W3 起为**自绘矢量包**，零外部资源）。

## 3. 控件规格清单（逐控件）

> 每条的字段：**Primer 对照** / 状态规格 / 尺寸与令牌 / 实现 / 测试 / 状态。
> 状态：☑ = 已落地；☐ = 本轮待做（波次见括号）。
> **纪律：任何控件都必须先在本清单有条目，才能开工实现。**

| # | 控件 | 实现文件 | Primer 对照 | 状态 |
| --- | --- | --- | --- | --- |
| 3.1 | OgLButton | `lib/surface/kit/kit_button.dart` | `content/components/button.mdx` | ☑ 待 W4 核对 |
| 3.2 | OgLTextField | `lib/surface/kit/kit_text_field.dart` | `content/components/text-input.mdx` | ☑ 待 W4 核对 |
| 3.3 | OgLConfirmDialog / OgLPromptDialog | `lib/surface/kit/kit_dialog.dart` | `content/components/dialog.mdx` | ☑ 待 W4 核对 |
| 3.4 | OgLBanner | `lib/surface/kit/kit_banner.dart` | `content/components/banner.mdx` | ☑ 待 W4 核对 |
| 3.5 | OgLLabel / OgLCounterLabel / OgLStateLabel | `lib/surface/kit/kit_label.dart` | `label.mdx` · `counter-label.mdx` · `state-label.mdx` | ☑ 待 W4 核对 |
| 3.6 | OgLActionRow | `lib/surface/kit/kit_action_list.dart` | `content/components/action-list.mdx` | ☑ 待 W4 核对 |
| 3.7 | OgLSpinner / OgLProgressBar | `lib/surface/kit/kit_spinner.dart` | `spinner.mdx` · `progress-bar.mdx` | ☑ 待 W4 核对 |
| 3.8 | OgLSkeletonBox / Text / Avatar | `lib/surface/kit/kit_skeleton.dart` | `skeleton-box.mdx` · `skeleton-text.mdx` · `skeleton-avatar.mdx` | ☑ 待 W4 核对 |
| 3.9 | OgLPageHeader | `lib/surface/kit/kit_page.dart` | `content/components/page-header.mdx` | ☑ 待 W4 核对 |
| 3.10 | OgLUnderlineNav | `lib/surface/kit/kit_underline_nav.dart` | `content/components/underline-nav.mdx` | ☑ 待 W4 核对 |
| 3.11 | OgLSegmented | `lib/surface/kit/kit_segmented.dart` | `content/components/segmented-control.mdx` | ☑ 待 W4 核对 |
| 3.14 | OgLBlankslate（空态） | `lib/surface/kit/kit_blankslate.dart` | `content/components/blankslate.mdx` | ☑ 新增（W2） |
| 3.15 | OgLBox（分区容器） | `lib/surface/kit/kit_box.dart` | `box.mdx` · `border-box.mdx` | ☑ 新增（W2） |
| 3.16 | OgLStateView（三态收敛） | `lib/surface/kit/kit_state_view.dart` | —（内部纪律组件） | ☑ 新增（W2） |
| 3.17 | OgLToggleSwitch（开关） | `lib/surface/kit/kit_toggle.dart` | `toggle-switch.mdx` | ☑ 新增（W2） |

### 3.1 OgLButton

- **Primer 对照**：`docs/refs/prime/content/components/button.mdx`（+ `button-group.mdx`、`icon-button.mdx`）
- **变体**：`primary`（强调底 + `on-accent` 文字）/ `standard`（`surface` 底 + `border` 描边）/ `danger`（危险底）/ `invisible`（无底无框，仅 hover 有 `surface-alt`）
- **尺寸**：`small`（高 28）/ `medium`（高 32）——Primer 基准；触摸目标由 `OgLTokens.targetSize` 抬到 **≥44**
- **状态**：rest / hover（`surface-alt`）/ active / focus-visible（`selection`）/ disabled（降透明度、禁止点击的明确"不可用"感）/ **loading**（内联 spinner + 禁止重复提交）
- **令牌**：圆角 `OgLRadius.medium`；水平内边距 `OgLSpacing.md`；字阶 `title`；图标尺寸 `tokens.iconSize()`
- **实现**：`lib/surface/kit/kit_button.dart` · **测试**：`test/surface/kit_test.dart`

### 3.2 OgLTextField

- **Primer 对照**：`docs/refs/prime/content/components/text-input.mdx`（+ `form-control.mdx`、`textarea.mdx`）
- **结构**：标签（`form-control` 语义）/ 占位 / 错误文本（`danger`）/ 聚焦强调描边（`accent`）
- **状态**：rest（`border`）/ hover（`borderStrong`）/ focus（`accent` 描边 + `selection` 底）/ invalid（`danger` 描边 + 错误文本）/ disabled
- **尺寸**：高 32（Primer 基准）；触摸 ≥44；密文模式用于令牌输入
- **配色纪律（W2 修正）**：**不填充**（`filled: false`）—— Primer TextInput 是
  `bgColor-default + borderColor-default`；旧实现的 `surfaceAlt` 填充会把每个输入框
  变成一大块灰底大板（"大面积灰色块"来源之一）
- **实现**：`lib/surface/kit/kit_text_field.dart` · **测试**：`test/surface/kit_test.dart` · `test/surface/kit_states_test.dart`

### 3.3 OgLConfirmDialog / OgLPromptDialog

- **Primer 对照**：`docs/refs/prime/content/components/dialog.mdx`
- **结构**：标题 + 正文（**人话说明后果**）+ 取消 / 确认；`danger` 变体用于破坏性操作
- **铁律**：**关闭 ≠ 确认**（点遮罩 / 返回 = 取消）；批量 / 危险操作必须先询问
- **尺寸**：圆角 `OgLRadius.large`（12）；内边距 `OgLSpacing.xl`（24）；宽度随断点（≥600 时定宽）
- **实现**：`lib/surface/kit/kit_dialog.dart` · **测试**：`test/surface/kit_test.dart`

### 3.4 OgLBanner

- **Primer 对照**：`docs/refs/prime/content/components/banner.mdx`（+ `inline-message.mdx`）
- **变体**：`info` / `success` / `warning` / `danger`
- **结构**：语义图标 + 标题 + 文本 + 可选操作；**底色 = `surface`**，语义色只出现在图标 / 边框
  （旧实现用 `color.withAlpha(26)` 铺满整条，暗色下就是一大块灰蓝色板）
- **铁律**：**错误不许无声消失** —— 关键失败必须有 Banner 或弹窗 + 应用日志双通道
- **实现**：`lib/surface/kit/kit_banner.dart` · **测试**：`test/surface/kit_test.dart` · `test/surface/kit_states_test.dart`

### 3.5 OgLLabel / OgLCounterLabel / OgLStateLabel

- **Primer 对照**：`docs/refs/prime/content/components/label.mdx` · `counter-label.mdx` · `state-label.mdx`
- **映射**：`neutral / accent / success / attention / danger / done` → 语义色（**唯一映射处**）
- **状态标签**：`open` / `closed` / `done` 三态（议题 / PR 列表）
- **尺寸**：圆角 `pill`；内边距 `OgLSpacing.sm` × `OgLSpacing.xxs`；字阶 `label`
- **实现**：`lib/surface/kit/kit_label.dart` · **测试**：`test/surface/kit_test.dart`

### 3.6 OgLActionRow（列表行）

- **Primer 对照**：`docs/refs/prime/content/components/action-list.mdx`（+ `nav-list.mdx`）
- **结构**：前导（图标 / 头像）/ 主文本（`title`）/ 副文本（`textDim`）/ 尾部（计数 / 箭头）/ 选中态（`selection`）
- **行为**：整行可点（命中区 = 整行），触摸 ≥44；**hover / focus / press 都有反馈**（`InkWell`）
- **实现**：`lib/surface/kit/kit_action_list.dart` · **测试**：`test/surface/kit_test.dart` · `test/surface/kit_states_test.dart`

### 3.7 OgLSpinner / OgLProgressBar

- **Primer 对照**：`docs/refs/prime/content/components/spinner.mdx` · `progress-bar.mdx`
- **加载三段律**：`<1s` 不显示 · `1–3s` spinner · `3s+` 进度条（确定态）
- **令牌**：尺寸 `small / medium`（随密度）；颜色 `textDim`
- **实现**：`lib/surface/kit/kit_spinner.dart` · **测试**：`test/surface/kit_test.dart`

### 3.8 OgLSkeletonBox / OgLSkeletonText / OgLSkeletonAvatar

- **Primer 对照**：`skeleton-box.mdx` · `skeleton-text.mdx` · `skeleton-avatar.mdx`
- **动效**：900ms 呼吸；**"减少动效"时静止**（不许闪）
- **颜色**：`surfaceAlt` 底 + 圆角 `medium`——**禁止使用与主背景同色的灰块**（历史"大面积灰块"缺陷根因之一，W2 复查）
- **实现**：`lib/surface/kit/kit_skeleton.dart` · **测试**：`test/surface/kit_test.dart`

### 3.9 OgLPageHeader

- **Primer 对照**：`docs/refs/prime/content/components/page-header.mdx`（+ `pagehead.mdx`）
- **结构**：标题（`headline`）+ 说明（`textDim`）+ 操作区（按钮组）；收纳为两侧自适应
- **实现**：`lib/surface/kit/kit_page.dart` · **测试**：`test/surface/kit_test.dart`

### 3.10 OgLUnderlineNav

- **Primer 对照**：`docs/refs/prime/content/components/underline-nav.mdx`（+ `underline-panels.mdx`、`tab-nav.mdx`）
- **铁律**：**水平**排布（可横向滚动）；选中项 2px `border-active` 下划线；计数徽标用 `OgLCounterLabel`
- **历史缺陷**：仓库页七标签曾用 `Wrap + OgLButton` 拼装 → 退化成"竖排链接堆"。回归测试锁死水平性与回调值
- **实现**：`lib/surface/kit/kit_underline_nav.dart` · **测试**：`test/surface/kit_nav_test.dart`

### 3.11 OgLSegmented

- **Primer 对照**：`docs/refs/prime/content/components/segmented-control.mdx`
- **语义**：**模式切换**（搜索页"仓库 / 代码"）；选中项 `surface` 底 + 描边
- **禁令**：模式切换**不得**用两个通栏大按钮代替（历史缺陷，已修）
- **实现**：`lib/surface/kit/kit_segmented.dart` · **测试**：`test/surface/kit_nav_test.dart`

### 3.12 图标体系（自绘矢量，W3 已交付）

- **Primer 对照**：`docs/refs/prime/content/components/icon.mdx` + Octicons（`octicons.mdx`）
- **实现**：几何数据 `lib/surface/icons/og_l_vector_icon.dart`（手写 `d` 路径，24 × 24 网格）；
  渲染组件 `lib/surface/kit/kit_icon.dart`（`OgLIcon`）
- **设计语言**：**参考 GitHub 但更概念、更尖锐** —— 全部直线构成（圆一律用八边形 / 菱形代替），
  端点 `butt`、拐角 `miter`，不出现任何圆头圆角
- **风格包**（沿用历史 ID，老设置不失效）：`material.outlined`（标准线性 1.75）·
  `minimal.line`（极简细线 1.35）· `material.filled`（锐利实心 1.7，闭合形状填充）
- **铁律**：界面**只能**用 `OgLIcon(name: ...)` —— 仓库里已经不存在任何
  `Icons.xxx` 或 `Icon(ogL.icon(...))`（由 `test/surface/icon_vector_test.dart` 结构性地拦住）
- **测试**：`test/surface/icon_vector_test.dart`（语义全覆盖 / 可解析 / 语义唯一 / 无 Material 字形）

### 3.13 页面三态模板（W2 统一）

- **Primer 对照**：`blankslate.mdx`（空态）
- **载**：`OgLSpinner` / `OgLSkeleton*`（按 `<1s / 1–3s / 3s+` 三段律）
- **空**：`blankslate` 形态——语义图标 + 一句话 + **下一步动作**（按钮）
- **错**：`OgLBanner(danger)` + **可重试**按钮 + 应用日志留痕
- **纪律**：三态一律走 Kit，不许页面自绘临时占位块

### 3.14 OgLBlankslate（空态）

- **Primer 对照**：`docs/refs/prime/content/components/blankslate.mdx`
- **结构**：语义图标（`textFaint`）+ 标题（`title`）+ 一句话说明（`textDim`）+ 可选动作
- **铁律**：**空态不许用 Banner 冒充** —— 旧实现把"这个目录是空的 / 没有打开的议题"
  渲染成半透明色块，既是"大面积灰色块"的主要来源，也误导用户以为出错了
- **实现**：`lib/surface/kit/kit_blankslate.dart` · **测试**：`test/surface/kit_states_test.dart`

### 3.15 OgLBox（分区容器）

- **Primer 对照**：`docs/refs/prime/content/components/box.mdx` · `border-box.mdx`
- **结构**：`surface` 底 + 发丝描边（`radius = medium`）；可选头部（`surfaceAlt` 底 + 底线）
- **用途**：设置页分区（基本设置 / Pages / 危险区）。**分组靠描边，不靠灰底**
- **实现**：`lib/surface/kit/kit_box.dart` · **测试**：`test/surface/kit_states_test.dart`

### 3.16 OgLStateView（三态收敛）

- **职责**：把"载 / 空 / 错"收敛到**一处**实现，页面不再各写一套
  - 载 = `OgLSkeletonText`（`<1s 不显示` 的细分由页面按需覆盖）
  - 空 = `OgLBlankslate`
  - 错 = `OgLBanner(danger)` + **重试**按钮（错误不许无声消失）
- **纪律**：仓库页七个标签 + 目录浏览器全部改走它（W1/W2 已落地）
- **实现**：`lib/surface/kit/kit_state_view.dart` · **测试**：`test/surface/kit_states_test.dart`

### 3.17 OgLToggleSwitch（开关）

- **Primer 对照**：`docs/refs/prime/content/components/toggle-switch.mdx`
- **规格**：轨道 36×20（`pill` 圆角 + 发丝描边），选中轨道 `accent`、滑块 `onAccent`
- **为什么不用 Material `Switch`**：水波纹 / 大尺寸 / 材质色与"发丝描边 + 直角偏锐"语言冲突
- **可访问性**：**整行可点**（点标签也能切换），禁用态降透明度
- **实现**：`lib/surface/kit/kit_toggle.dart` · **测试**：`test/surface/kit_states_test.dart`

## 4. 页面版图（`lib/surface/pages/`）

- **登录门** `login_page.dart`：令牌向导（暂存 → 验证 → 转正 → 保险库回读四阶段日志；游客模式入口）。
- **首页** `dashboard_page.dart`：我的仓库 / 星标仓库（骨架 → 空态 → 失败重试四态纪律）；「新建」仓库。
- **搜索** `search_page.dart`：仓库搜索 + 代码搜索（服务端），模式切换用 `OgLSegmented`。
- **我的** `profile_page.dart`：账户列表 / 切换 / 移除 / 新增 / 退出。
- **仓库页** `repo_page.dart`（7 标签，`OgLUnderlineNav`）：
  - 代码：目录浏览 → 文件查看 → 编辑提交（**带基线 sha 乐观锁**）→ 删除；
  - 议题：列表 + 关闭；PR：列表；发布：列表 + 新建 / 删除；
  - 分支：列表；提交：历史（sha / 作者 / 日期）；设置：基本信息 / Pages / CNAME / 危险区（删除仓库）。
  - **W1 待办**：逐标签**功能复查**（部分功能失效，需审计 → 修复 → 补测）。
- **设置 / 关于**：折叠栏 + 应用级日志 + 一键复制，外观按 Kit 统一。

## 5. 与旧文档的关系

- `DESIGN.md`（仓库根）：视觉身份真源（令牌 + 理念）。本文件与之互补：**本文件管"控件"，它管"令牌"**。
- `SURFACE.md`：布局 / DPI / 无障碍 / 权限铁律**继续有效**（本系统与之叠加）。
- `UI_SYSTEM_V2.md`：作废存档。
- `PHASE2_PLAN.md`：第二阶段执行契约（波次 / 层检 / 推送策略）。

## 6. 更新规则（强制）

1. 新增 / 修改控件：**先改本清单**（条目 + Primer 对照 + 实现路径），再改代码，再补测试；
2. 控件落地后在表格里打勾；W4 完成 Primer 逐项核对后改为"☑ 已核对"；
3. 令牌改动：先改 `DESIGN.md` → 再改 `theme_pack.dart` / `design_tokens.dart` → 跑
   `test/surface/design_spec_sync_test.dart`（任一方向漂移即红）。