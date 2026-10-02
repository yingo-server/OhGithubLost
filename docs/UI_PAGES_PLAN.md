# OGL · 主页面布局规划（UI_PAGES_PLAN）

> **纪律：先规划、后写码。** 本文件是"逐个页面重写 UI"的施工图：
> 每一页在动代码之前，必须先在本文里有**结构、层级、行规格、状态、检查**五件事。
> 规格真源：[`../DESIGN.md`](../DESIGN.md)（令牌）· [`UI_SYSTEM_V3.md`](UI_SYSTEM_V3.md)（控件）。
> 读取顺序：本文 → 令牌 → 控件 → 页面。

---

## 0. 总纲（所有页面共同遵守）

### 0.1 页面骨架（唯一入口）
```
OgLPageScaffold(
  title / description,      // 页头：headline 字阶 + textDim 说明
  actions: [...],           // 页头操作（≤3 个，主操作在前）
  onRefresh: ...,           // 下拉刷新
  child: Column(...)        // 内容：OgLSection / OgLBox / 列表
)
```
- 外边距 `OgLSpacing.lg`、内容 **maxWidth 840 居中**、页头与内容间距 `OgLSpacing.lg`。
- **页面禁止自己写 `ListView(padding:)` / `SingleChildScrollView`**（否则边距与宽屏行为必然发散）。

### 0.2 信息层级（每页最多三层）
1. **页头**：这是什么 + 主操作；
2. **元信息/工具条**：`OgLBox` 内的标签行 + 统计行（图标 + 等宽数字）；
3. **内容区**：`OgLSection` 分组 + `OgLBox(padded: false)` 包列表（行自带内边距与发丝分割线）。

### 0.3 行的解剖（列表行只允许这一种形状）
```
OgLActionRow(
  leading:  OgLIcon(name: ..., size: 20)          // 自绘矢量，禁止 Material 字形
  title:    主文本（body 字阶）
  subtitle: 副文本（label 字阶 / textDim）
  trailing: OgLLabel | OgLCounterLabel | OgLStateLabel | 值文本 | OgLButton(invisible)
  showChevron / showDivider / onTap
)
```

### 0.4 四态（一律走唯一映射点 `ogLAsyncView`）
| 阶段 | 呈现 |
| --- | --- |
| idle / loading（无数据） | 骨架（`skeletonLines` 按内容高度给 2–6） |
| empty | `OgLBlankslate`（图标 + 一句话 + **下一步动作**） |
| failed | `OgLBanner(danger)` + **重试**（错误必须可见） |
| ready（带 `refreshError`） | 内容 + 顶部**软提示**（保留旧数据） |

### 0.5 令牌纪律（"不要只改颜色"）
- 间距 / 圆角 / 描边 / 时长 / 字号：**只能**经 `tokens.space()/radius()/stroke()/motion()/fontSize()`。
- 颜色：只能经 `ogL.palette.*` / `colorFor()`；**禁止** `Colors.*`、`Color(0x…)`（Kit 内部除外）。
- 触摸目标 ≥44；键盘焦点可见；"减少动效"⇒ 动效归零。
- 图标：只能 `OgLIcon(name: ...)`。

### 0.6 层内检查（每页落地即插）
1. `test/surface/pages_<name>_test.dart`：**四态渲染**（载/空/错/有数据）+ 关键交互（主操作/切换/confirm）；
2. 组件矩阵快照追加该页（`build/ui_shots/matrix_*.png`）——"长什么样"变成可看的事实；
3. CI 绿（analyze --fatal-infos --fatal-warnings + 全测试）。

---

## 1. 推进顺序与推送策略

| 序 | 页面 | 文件 | 状态 |
| --- | --- | --- | --- |
| 1 | 设置（含外观/网络/开发者/账户） | `surface/app/og_l_app.dart` | ✅ 本批完成（分区行式 + 底部选择表 + 自绘开关 + 退出登录二次确认） |
| 2 | 首页（我的 / 星标 / 新建） | `pages/dashboard_page.dart` | ✅ 本批完成（骨架 + 分段切换 + 计数说明 + 四态走唯一映射点） |
| 3 | 搜索（仓库 / 代码） | `pages/search_page.dart` | ✅ 本批完成（骨架 + 回车即搜 + 限定符引导 + 结果可点 + 计数说明） |
| 4 | 我的（账户管理） | `pages/profile_page.dart` | ✅ 本批完成（分区：账户/会话/内容/危险区 + 空态引导 + 破坏性操作二次确认） |
| 5 | 议题详情 | `pages/issue_page.dart` | ✅ 本批完成（骨架 + 返回键 + Markdown 正文/评论 + 关闭/重开二次确认） |
| 6 | PR 详情 | `pages/pull_page.dart` | ✅ 本批完成（骨架 + 返回键 + Markdown 描述 + 语义状态标签 + 增删统计） |
| 7 | 提交详情（diff） | `pages/commit_page.dart` | ✅ 本批完成（骨架 + 返回键 + **分色补丁**（+绿/−红/@@灰）+ 超长按行截断告知） |
| 8 | Gists | `pages/gists_page.dart` | ✅ 本批完成（骨架 + **整行可点用浏览器打开** + 公开/私密标签 + 空态） |
| 9 | 登录 / 新增账户向导 | `pages/login_page.dart` | ✅ 本批完成（骨架 + **四步向导可见**（暂存/验证/转正/回读）+ 回车验证 + 令牌指引） |
| 10 | 表单页（新建仓库 / 议题 / 发布） | `pages/new_repo_page.dart` · `pages/new_issue_page.dart` · `pages/new_release_page.dart` | ✅ 本批完成（骨架 + 行内校验 + 自绘开关行 + 底部主操作） |
| — | 仓库页 | `pages/repo_page.dart` | ✅ 已落地（骨架 + 元信息盒 + 七标签 + **README 渲染** + **议题/PR 筛选与分页**） |
| — | **主壳（导航外壳）** | `app/client_shell.dart` + `kit/kit_nav_shell.dart` | ✅ W8-P3 完成（底栏 / 导航轨 / 抽屉 / 壳页头全部自绘，与页面同源） |
| — | **关于页** | `app/og_l_app.dart`（`_AboutPage`） | ✅ 本批完成（骨架 + 小节 + 信任链空态 + 日志截断显示与一键复制） |

**推送策略（已按用户要求调整）：累积推送** —— 不再一页一推：
一批通常包含 3～10 页（代码 + 测试 + 文档一起），**批内自查（等价脚本预跑）后再推一次**，
CI 绿才能开下一批；只有遇到编译/测试红灯才额外补一次修复推送。每批前后各备份一份到 `_backup/`。

---

## 2. 逐页规划

### 2.1 设置（重构重点）

**目标**：把"能点的都能看懂、危险的有闸门"。分区行式布局，**一眼看出哪些是外观、哪些会影响数据**。

```
OgLPageScaffold(title: '设置', description: '外观 / 网络 / 仓库 / 开发者 / 关于', actions: [重置])
├ OgLSection('外观')
│  └ OgLBox(padded:false)
│     ├ 行：主题（值文本 = 当前主题名 · chevron）→ 选择弹窗
│     ├ 行：明暗（值文本 = 跟随系统/亮/暗 · chevron）
│     ├ 行：密度（值文本 = 自动/紧凑/标准/宽松 · chevron）
│     ├ 行：动效（OgLToggleSwitch 或值文本）
│     └ 行：强调色（色块 + 值文本 + chevron）
├ OgLSection('网络')
│  └ OgLBox(padded:false)
│     ├ 行：DNS 策略（系统 / 自定义 · chevron）+ 副标题：当前服务器名
│     ├ 行：DoH 优先（OgLToggleSwitch）
│     └ 行：连接行为说明（文本行，非交互）
├ OgLSection('仓库与写入')
│  └ OgLBox(padded:false)
│     ├ 行：缓存条目上限（值 = 数字 · chevron → 输入弹窗，夹紧 [64,8192]）
│     ├ 行：缓存 TTL（值 = 天数 · chevron，夹紧 [0,3650]）
│     ├ 行：批量操作每次询问（OgLToggleSwitch）
│     └ 行：写入通道（值 = 每次问/直写/镜像 · chevron）
├ OgLSection('开发者（危险）', description:'总闸关闭时以下开关一律失效并清空')
│  └ OgLBox(padded:false)
│     ├ 行：开发者模式（OgLToggleSwitch，danger 语义）
│     └ 每个危险开关一行（仅在总闸开时可用；每开一个都要 confirm 弹窗说明后果）
└ OgLSection('关于')
   └ OgLBox(padded:false)
      ├ 行：版本 / 构建号（值文本）
      ├ 行：启动报告（chevron → 展开：信任链状态 / 引导清单签名 / 存储接线）
      ├ 行：应用日志（chevron → 展开日志尾部）+ 页头操作"复制全部日志"（OgLIconName.list）
      ├ 行：修复过的配置（lastRepairs，非空才显示）
      └ 行：许可证（chevron → MIT）
```
**纪律**：每行 `leading` 用自绘矢量图标（`theme`/`dns`/`database`→用 `file`/`shield`/`key`/`bug`/`info` 现有语义）；危险项 `danger` 语义 + **二次确认**；保存失败必须提示"重启会丢"。

### 2.2 首页（dashboard）

```
OgLPageScaffold(title:'首页', description:'我的仓库 / 星标仓库', actions:[刷新, 新建仓库], onRefresh)
├ OgLSegmented(我的 | 星标)
├ OgLBox(padded:false, title:'共 N 个仓库')
│  └ 行 ×N：OgLIcon(repository) + fullName + 描述/语言/★ 副文本 + OgLLabel(私有) + chevron → 仓库页
└ 四态：无仓库 → Blankslate('还没有仓库', action: 新建仓库)；403/限流 → Banner+重试
```

### 2.3 搜索

```
OgLPageScaffold(title:'搜索', description:'仓库搜索 / 代码搜索（服务端）')
├ OgLTextField(hint:'repo:… 或关键字', leadingIcon: search, onSubmitted)
├ OgLSegmented(仓库 | 代码)
├ 结果列表：仓库行（repository 图标 + fullName + ★/语言）/ 代码行（file 图标 + path:行号 + 片段）
└ 四态：未输入 → Blankslate('输入关键字开始搜索')；无结果 → Blankslate('没有匹配结果')
```

### 2.4 我的（账户）

```
OgLPageScaffold(title:'我的', description:'账户与令牌', actions:[新增账户])
└ OgLBox(padded:false, title:'账户')
   └ 行 ×N：OgLIcon(key) + login + OgLStateLabel(当前/可切换) + trailing: 切换(OgLButton invisible)
      + 移除(danger, confirm) ；行尾 chevron 进详情
└ OgLSection('危险区')：退出登录（danger + confirm，说明"令牌会从保险箱删除"）
```

### 2.5 议题详情 / 2.6 PR / 2.7 提交 / 2.8 Gists / 2.9 登录 / 2.10 表单页

- 共同形状：`OgLPageScaffold` + **元信息 Box**（`OgLLabel` 状态标签 + by/时间 + 计数）+ **内容 Box**（正文/文件/diff，等宽 `data` 字阶）+ **操作区**（关闭 / 重开 / 合并只在有权限时显示）。
- 列表型（PR 文件 / 提交 diff / Gists）：`OgLBox(padded:false)` + 行（`OgLIcon(file|commit|code)` + 路径 + `+N/-N` 标签）+ 空态 Blankslate。
- 登录：四阶段向导（暂存 → 验证 → 转正 → 保险箱回读）用 `OgLBox` 包步骤日志（等宽），令牌输入 `obscure`，失败给 `OgLBanner(danger)` + 重试；保留游客模式入口。
- 表单页（新建仓库/议题/发布）：`OgLPageScaffold` + 表单 `OgLBox`（`OgLTextField`，`error:` 行内提示）+ 底部主操作 `OgLButton(primary, loading:)`；提交失败保留输入并给可重试错误。

---

## 3. 验收（每页完成定义）

1. 页面**不含** `ListView(` / `SingleChildScrollView(` / `Colors.` / `Color(0x` / 数字字面量间距（Kit 与 Kit 级组件除外）；
2. 四态齐全且经 `ogLAsyncView`；
3. 主操作 ≤1 且位置固定（页头或表单底部）；
4. 页面级 widget 测试 + 快照矩阵追加通过；
5. CI 绿；文档（UI_SYSTEM_V3 页面版图）同步勾选。