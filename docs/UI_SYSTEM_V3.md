# OGL 设计系统 v3（Primer 官方 + OGL 自研）

> 状态：**UI v3 重写进行中**。本文件是新表面层的**唯一设计真源**；
> 旧 `UI_SYSTEM_V2.md`（Spatial 主导向）随之作废，仅存档参考。
>
> 规范来源：
> - 控件语义 / 配色 / 尺寸：**GitHub Primer**（仓库内快照 `docs/refs/prime`）
> - 方法论：Google **design.md**（仓库内快照 `docs/refs/design-md`）
> - 工程铁律：沿用 `docs/SURFACE.md`（断点 / 发丝线 / 触摸 ≥44 / 减少动效）

---

## 1. 两个主题（产品决策：只保留两个）

| id | 名称 | 定位 | 备注 |
| --- | --- | --- | --- |
| `primer` | **Primer（官方，默认）** | 按 Primer 功能令牌落地：`bgColor-default / bgColor-muted / borderColor-default / fgColor-default / fgColor-muted / fgColor-accent / fgColor-onEmphasis` + success / attention / danger 语义色；圆角 6；发丝描边 | 唯一"官方"主题 |
| `ogl.spatial` | **OGL（自研）** | 深空底 + 单一强调色 + 大留白；通用性优先 | 第二主题 |

已移除：`vscode.geek` / `winui3` / `material3`（历史实验包，全部退役）。

## 2. 令牌（与主题正交）

- **物理令牌**（`design_tokens.dart`，纯 Dart）：密度 / 间距 / 圆角 / 描边 / 时长 / 字阶。
- 圆角对齐 Primer：`small = 3` · `medium = 6` · `large = 12`（另有兼容旧梯度的 none/xs/sm/lg/pill）。
- 颜色一律经主题包调色板（`OgLPalette`）读取；页面不得直接写字面色。
- 图标一律走 `OgLIconName` 语义层（45 语义 × 3 套包，编译期强制齐全）。

## 3. 组件套件（OGL Kit，`lib/surface/kit/`）

| 组件 | 职责 | 规格来源 |
| --- | --- | --- |
| `OgLButton` | primary / standard / danger / invisible；small / medium；加载态；前置图标 | Primer Button |
| `OgLTextField` | 标签 / 占位 / 错误文本 / 聚焦强调描边；密文模式（令牌输入） | Primer TextInput / FormControl |
| `OgLConfirmDialog` + `ogLConfirmDialog()` | 标题 + 正文（人话后果）+ 取消/确认；danger 变体；**关闭≠确认** | Primer Dialog |
| `OgLBanner` | info / success / warning / danger；图标 + 标题 + 文本 + 操作 | Primer Banner / Flash |
| `OgLLabel` / `OgLCounterLabel` / `OgLStateLabel` | 状态→颜色的唯一映射（neutral/accent/success/attention/danger/done；open/closed/done） | Primer Label / StateLabel |
| `OgLActionRow` | 列表行：前导/主副文本/尾部/选中态/整行可点/箭头 | Primer ActionList |
| `OgLSpinner` / `OgLProgressBar` | 不确定态 / 确定态加载；<1s 不显示、1–3s spinner、3s+ 进度 | Primer Loading |
| `OgLSkeletonBox/Text/Avatar` | 骨架屏（900ms 呼吸；减少动效时静止） | Primer Skeleton |
| `OgLPageHeader` | 页头：标题 / 说明 / 操作 | Primer 页面结构 |

约定：**一切视觉经令牌**；组件只表达语义；触摸目标 ≥44；"减少动效"全局生效。

## 4. 页面版图（`lib/surface/pages/`）

- **登录门** `login_page.dart`：令牌向导（暂存→验证→转正→保险库回读四阶段日志；游客模式入口）。
- **首页** `dashboard_page.dart`：我的仓库 / 星标仓库（骨架→空态→失败重试四态纪律）；「新建」仓库。
- **搜索** `search_page.dart`：仓库搜索 + 代码搜索（服务端），仓库结果直达详情。
- **我的** `profile_page.dart`：账户列表 / 切换 / 移除 / 新增 / 退出。
- **仓库页** `repo_page.dart`（7 标签）：
  - 代码：目录浏览 → 文件查看 → 编辑提交（**带基线 sha 乐观锁**）→ 删除；
  - 议题：列表 + 关闭；PR：列表；发布：列表 + 新建 / 删除；
  - 分支：列表；提交：历史（sha/作者/日期）；设置：基本信息 / Pages / CNAME / 危险区（删除仓库）。
- **设置 / 关于**：沿用既有实现（折叠栏 + 应用级日志 + 一键复制），后续按 Kit 外观统一换肤。

## 5. 与旧文档的关系

- `SURFACE.md`：布局 / DPI / 无障碍 / 权限铁律**继续有效**（本系统与之叠加）。
- `UI_SYSTEM_V2.md`：作废存档。
- 本文件随 UI v3 推进持续更新；控件逐项落地后在此打勾。
