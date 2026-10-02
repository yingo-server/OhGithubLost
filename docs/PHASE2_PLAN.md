# OGL 第二阶段 · 修复与重构总计划（PHASE2）

> 本文件是第二阶段**唯一执行契约**（v2：含"规范先行"与"仓库功能复查"两波）。
> 机器可读视觉身份真源：[`../DESIGN.md`](../DESIGN.md)；控件级清单：[`UI_SYSTEM_V3.md`](UI_SYSTEM_V3.md)。
>
> 规则：**先修根因，再插检查，再换装外观；每波收口一次 push；CI 不绿不进下一波；开发期不等构建。**

## 0. 问题清单（用户报告 + 排查确认）

| # | 现象 | 根因（已确认） | 层 | 状态 |
| --- | --- | --- | --- | --- |
| 1 | 文件打开"解码错误"（中文 / emoji 全乱） | `GhContent.decodeContent` 用 `String.fromCharCodes` 而非 UTF-8 解码 | L2 | ✅ 已修 + 测试 |
| 2 | 登录信息不缓存，重启即失忆 | `PlatformStorage.open()` 从未被调用 → DiskModule 全走内存实现 | L1 | ✅ 已修 + 测试 |
| 3 | 仓库页标签竖排成"链接堆" | 标签用 `Wrap + OgLButton` 拼装，未按 Primer UnderlineNav | L3 | ✅ 已换装 + 测试 |
| 4 | 搜索页模式切换是两个通栏大按钮 | 同上（未用 Segmented） | L3 | ✅ 已换装 |
| 5 | 仓库设置 / 议题页出现大面积灰色块 | **三条根因**：输入框灰底填充 / Banner 半透明铺色 / 空态被 Banner 冒充 + Pages 失败停在骨架 | L3 | ✅ W1+W2 已修 |
| 6 | 图标未更换（仍是 Material 字形） | 图标层未自绘矢量 | L3 | ✅ W3 已修（自绘矢量 + 53 处迁移） |
| 7 | 更新安装报"证书不一致" | **根因已实证**：只把固定 keystore 铺到 `~/.android/debug.keystore`，AGP 并未采用它（两次构建证书互不相同） | 工程 | ✅ 改为**构建后显式重签** + 证书护栏（`tool/verify_apk_cert.py`） |
| 8 | 之后的版本不得开启 debug 模式 | 引导清单签名注入已落地；列入每版验收 | L0/工程 | ✅ 已修 |
| 9 | **仓库内部分功能失效（待复查）** | **已审计**：7 标签 + 仓库级操作；修掉文件打开静默失败 / 改名失联 / Pages 失败停骨架 / 标签名 | L2/L3 | ✅ W1 已修 |
| 10 | **UI 设计规范缺位（未控件级落库）** | 规范未按 design-md 落库、未插一致性检查 | L3/工程 | ✅ **W0 已落库** |

## 1. 分层修复原则

```
L0 内核    不动（信任链已固化）
L1 底座    存储接线 / 失败上报 /（检查）装配测试          ✅ 已收口
L2 领域    解码修复 /（检查）解码测试                     ✅ 已收口
L3 表面    W0 规范 → W1 仓库复查 → W2 页面结构 → W3 图标 → W4 Primer 细节
工程        CI / 构建 / 发布 / 证书 / 备份 / 记忆
```

每题都遵守：**根因 → 修复 → 检查（测试或 CI 护栏）→ 推送**。

## 2. 波次与层内检查

### W0 · UI 设计规范落库（先行）✅
- [x] `DESIGN.md`（仓库根，design-md 格式：YAML 令牌 + 散文，章节序合规）
- [x] `docs/UI_SYSTEM_V3.md` 升级为**逐控件规范清单**（11 组件全量 + Primer 对照 + 实现路径）
- [x] 检查：`test/surface/design_spec_sync_test.dart`
      （令牌一致性：4 调色板 × 18 角色 + 间距 + 圆角 + 章节序；控件覆盖：kit 全文件）
- [x] 推送（本批）

### W1 + W2 · 仓库页功能复查 + 页面结构（灰块）✅ 本批
> 两波合批推送：它们改的是同一个文件、同一批状态处理，分开推只会把
> "改一半"的中间态留在远端。

**W1 功能复查（静态审计 + 修复）**
- [x] 逐标签审计：代码 / 议题 / PR / 发布 / 分支 / 提交 / 操作 / 设置（数据流 + 动作路径）
- [x] 修复 ①：**文件打开失败＝静默失败**（错误只在文件视图渲染，而失败时仍停在目录视图）
      → 目录视图现在显示"文件打开失败 + 重试"（`_pendingFile` + `_retryPendingOpen`）
- [x] 修复 ②：**仓库改名后失联**（后续请求仍用旧全名）→ `_full` 全名状态 + 改名后提示
- [x] 修复 ③：**Pages 读取失败永远停在骨架** → 明确错误 + 重试
- [x] 修复 ④：标签名"动作"→"操作"（对齐 Primer Actions）
- [x] 检查：`test/surface/kit_states_test.dart`（三态 / 空态 / 交互反馈）

**W2 页面结构（灰块根因）**
- [x] 根因①：`OgLTextField` 的 `filled: true + surfaceAlt` → **每个输入框都是一块灰底大板**
- [x] 根因②：`OgLBanner` 用 `color.withAlpha(26)` 铺满整条 → **整条灰蓝色块**（空态还被 Banner 冒充）
- [x] 根因③：`OgLSkeletonText` 在 Pages 失败时**永远停在骨架**（永不结束的灰条）
- [x] 新增：`OgLBlankslate`（空态）· `OgLBox`（分区）· `OgLStateView`（三态收敛）· `OgLToggleSwitch`（自绘开关）
- [x] 三态统一：仓库页七标签 + 目录浏览器全部走 `OgLStateView`
- [x] 设置页改 `OgLBox` 三分区；`SwitchListTile` 换成自绘开关（整行可点）
- [x] 检查：`test/surface/kit_states_test.dart`（含"输入框不填充 / 横幅非色块"两条回归）
- [x] 推送（本批）

### W3 · 自绘矢量图标体系 ✅ 本批
- [x] `lib/surface/icons/og_l_vector_icon.dart`：45 个语义的手写 `d` 路径（24×24 网格，纯直线）
- [x] `lib/surface/kit/kit_icon.dart`：`OgLIcon` 渲染组件（端点 butt / 拐角 miter，等比缩放）
- [x] `icon_pack.dart` 重写：图标包只描述**风格**（线宽 / 填充），ID 保持兼容
- [x] **全部 53 处调用点迁移**（20 个文件）：`Icon(ogL.icon(X))` → `OgLIcon(name: X)`
- [x] 清掉最后 1 处 Material 字形（`Icons.copy_all` → `OgLIconName.list`）
- [x] 检查：`test/surface/icon_vector_test.dart`
      （语义全覆盖 / 可解析且不越界 / 语义唯一 / **结构性拦住 `Icons.xxx` 与旧取图标方式**）
- [x] 推送（本批）

### W4 · Primer 细节对齐 + 快照矩阵 ✅ 本批
- [x] 逐控件核对（间距 / 圆角 / 字号 / 状态色 / 动效）—— 对照 `docs/refs/prime`
- [x] **修正**：按钮"视觉高度（28/32）"与"命中区（≥44）"拆分（此前触摸态按钮一律 44 高，偏 Material 而非 Primer）
- [x] 新增**组件快照矩阵**：`test/surface/ui_component_matrix_test.dart` →
      `build/ui_shots/matrix_<主题>__<明暗>.png`（两主题 × 明暗 × 全部 Kit 组件 + 45 个自绘图标总览）
- [x] `UI_SYSTEM_V3.md` 标注 W4 核对结论
- [x] 推送（本批）

### W5 · 收口 ✅
- [x] 文档勾选：CHANGELOG / ROADMAP / FEATURES / PHASE2 / UI_SYSTEM_V3
- [x] 备份归档（每波推送前 / 后各一份 `_backup/ogl-p2-w*-{pre,post}-*.tar.gz`）
- [x] 记忆终档（状态卡 / 工程决策库 / 架构与代码地图）
- [x] 构建 13/13 核验：build run `36894987321` = **success**（14/14 任务：引导清单 + 13 平台）

### W6 · 签名接线修复（实证驱动）✅ 本批
- [x] **取证**：对两份 CI 产物做签名块字节级比对 → 证书互不相同（`DD:53:A9:…` / `AC:F7:9E:…`），
      且都不含固定证书（`7F:55:58:68:…`）的 DER ⇒ 旧做法（只铺 `~/.android/debug.keystore`）**不生效**
- [x] **修法**：`build.yml` 新增 `重签 APK（固定证书）`：`zipalign -p -f 4` → `apksigner sign`（固定 keystore、v1+v2）
- [x] **护栏**：新增 `tool/verify_apk_cert.py`，逐包校验证书指纹，不一致即流水线失败
- [x] 推送并复跑构建，产物证书 = 固定证书（见 CHANGELOG「修复（签名接线 · 实证驱动）」）

### W7 · "空结果 = 加载中"缺陷根治 + 领域层硬化 ✅ 本批

**缺陷（用户报告"仓库内很多标签失效"的真因）**：页面一律用
`state.data == null` 当"加载中"，而 `OgLAsync.settle()` 在**结果为空**时
进入 `empty` 阶段且 **`data` 同样是 null** ⇒ 零议题 / 零发布 / 零分支 / 零提交 /
零评论 / 零文件 / 零 Gist / 空搜索**永远停在骨架屏**（看起来就是"标签打不开"）。

- [x] **语义下沉到一处**：`OgLAsync` 新增 `isFirstLoading` / `isEmptyResult` /
      `failureMessage` / `softError`（空 ≠ 载 ≠ 错，三者互斥）
- [x] **唯一映射点**：新增 `lib/surface/app/async_view.dart::ogLAsyncView`，
      四态 → 骨架 / Blankslate / Banner+重试 / 内容（+ 刷新失败软提示）
- [x] 仓库页七标签 + 目录浏览器全部改走它；议题详情 / PR / 提交 / Gists / 搜索 /
      账户页 / 首页的判定同步换成 phase 语义（共 12 处）
- [x] `OgLStateView` 新增 `softError`：**刷新失败保留内容**，只加顶部警告
- [x] **领域层硬化**：读类端点遇 404/409（不存在 / 仓库为空 / 功能未启用）一律当"没有"
      （`listDirectory` / `content` / `commits`）
- [x] **未知默认分支不再瞎猜**：`GhRepo.defaultBranch` 缺字段时为空串；
      `ref` / `sha` 仅在非空时携带（GitHub 自动用真实默认分支）；
      仓库页用 `GET /repos/{full}` 兜底补齐（失败不阻塞浏览）
- [x] 检查：`test/surface/async_state_test.dart`（四态语义 + 映射点）·
      `test/domain/gh_absent_test.dart`（空仓库/404/未启用/未知分支）
- [x] 推送（本批）

### W8 · 页面级商业重写（逐页推进）⏳

> 目标：**每一页都长得像同一个产品**。做法是先把"页面框架"收敛成 Kit 组件，
> 再逐页改用它 + 用 `OgLBox` / `OgLSection` 分组 + 图标全部走自绘矢量。

- [x] 新增 `OgLPageScaffold`（页头 + 边距节律 + 宽屏限行 840 + 下拉刷新）与 `OgLSection`（小节）
- [x] **仓库页**改用骨架：页头（标题/说明/星标/复刻）+「仓库元信息盒」（公开/语言/默认分支/Pages 标签
      + ★/Fork/Issue/体积 统计行，图标全部自绘矢量）+ UnderlineNav + 标签内容
- [ ] 首页 / 搜索 / 我的 / 设置 / 议题详情 / PR / 提交 / Gists / 登录 逐页同样处理
- [ ] **设置页重构**：分区（外观 / 网络 / 仓库 / 危险区）统一为"图标 + 标题 + 副标题 + 右侧控件"行式布局
- [ ] 检查：每页落地后补组件矩阵快照 + 页面级 widget 测试

### W8-P1 · 设置页重构 ✅ 本批

- [x] 页面骨架 `OgLPageScaffold` + `OgLSection` 分区（外观 / 网络·DNS / 开发者 / 账户）+ `OgLBox(padded:false)` 包行
- [x] **删除 Material 堆砌**：`ChoiceChip` 单选堆 → `_ChoiceRow`（整行可点 + **底部选择表**，当前项打勾）；
      `SwitchListTile` → `_ToggleRow`（`OgLActionRow` + 自绘 `OgLToggleSwitch`，整行可点）
- [x] 自定义 `_SectionTitle` / `_Banner` / `_KeyValue` 全部退役（改用 Kit 的 `OgLSection` / `OgLBanner` / `OgLActionRow`）
- [x] **退出登录补二次确认**（原来点一下就直接删令牌 —— 违反"危险操作先询问"红线）
- [x] 危险开关：总闸关时整行禁用 + 行内说明；已开启的危险开关有独立 `OgLBanner(danger)` 提示
- [ ] 关于页（启动报告 / 日志 / 复制）并入同一次重构的下半场
- [ ] 页面级 widget 测试（bridge 依赖 → 需先做测试用 SurfaceBridge 假体）

### W8-P2 · 首页重写 + 页面纪律护栏 ✅ 本批

- [x] **首页** `dashboard_page.dart` 重写：`OgLPageScaffold`（页头 + 新建/刷新 + 下拉刷新）+
      `OgLSegmented`（我的仓库 / 星标仓库，一次只看一个列表，右侧给**计数说明**）+ `OgLBox` 包行；
      未登录 = `OgLBanner`(action 接入令牌) + 「接下来」行式引导；**四态全部改走 `ogLAsyncView`**
- [x] **页面纪律护栏**（把规范写成会失败的测试）`test/surface/page_discipline_test.dart`：
      ① 页面必须在施工图立项（不许野生）② 页面/应用壳禁止 `Colors.` `Color(0x` `Icons.`
      `SwitchListTile` `ChoiceChip` `RadioListTile` `ListTile(` ③ 已重写页面必须走 `OgLPageScaffold`
      且不许自己写 `ListView(`/`SingleChildScrollView(` ④ 已重写页面不许手写"data==null 即加载中"
- [x] **死代码收口**：删除旧主壳 `OgLShell`/`_OgLShellState`/`_Brand`/`_ContentFrame` 与
      `app/repos_page.dart`（入口早已是 `OgLClientShell`，全仓含测试无引用）；`og_l_app.dart` 32.7 KB → 28.0 KB
- [x] **色值字面量收敛**：兜底界面的 `Color(0xFFF85149)` → 主题常量 `kOgLDangerDark`（唯一来源）
- [ ] W8-P3：主壳 `client_shell.dart` 规范化（现在的 `AppBar` + `Drawer` + `ListTile` 还是 Material 形态）

### W8-P3 · 主壳规范化 ✅ 本批

- [x] **新增 Kit 导航组件** `lib/surface/kit/kit_nav_shell.dart`：
      `OgLNavDestination`（值 + 标题 + 图标）/ `OgLBrandMark` /
      `OgLBottomNav`（手机底栏：图标 + 标签 + **顶部指示条**，触摸目标 ≥44）/
      `OgLNavRail`（平板桌面导航轨，可展开标签，选中项带左侧强调条 + `surfaceAlt`）/
      `OgLNavDrawer`（窄窗抽屉：`OgLActionRow` 行）/ `OgLShellHeader`（自绘壳页头，替代 `AppBar`）
- [x] **主壳重写** `client_shell.dart`：删除 Material `AppBar` / `NavigationBar` /
      `NavigationRail` / `NavigationDestination` / `ListTile`；改为 `OgLShellTab` + `_nav` 单一数据源
      （五个页面的标题与图标只写一遍，壳页头/抽屉标题都从它取，避免"三处各写一套"）
- [x] **护栏升级**：`page_discipline_test.dart` 对 `client_shell.dart` 额外禁止
      `AppBar(` / `NavigationBar(` / `NavigationRail(` / `NavigationDestination(` / `ListTile(`
- [x] 手机形态不再叠 Material `AppBar`：页面自带 `OgLPageScaffold` 页头，壳只提供底栏（少一层视觉噪音）

### W8-P4 · README 渲染 ✅ 本批

- [x] 新增 `lib/surface/readme/readme_view.dart`：
      **纯函数净化** `ogLSimplifyReadme()`（HTML 注释/标签清理、`[![…](…)](…)` 徽章行整行删除、
      图片 → `（图：alt）` 占位、连续空行压缩、超长按行边界截断且**明确告知**）+
      `OgLReadmeView`（`flutter_markdown` 后端，样式表全部来自令牌与调色板）
- [x] **代码块原样保留**：围栏内部不清理标签/图片/注释（示例代码不许被改）
- [x] 仓库页接线：`_readmeC()`（`null`/空文本 = **空态**，不是错误）+ 代码标签下 `OgLSection('README')`，
      四态走 `ogLAsyncView`；空态给"放一个 README.md 就会显示在这里"的可操作说明
- [x] 链接：`url_launcher` 打开；失败**不静默**（SnackBar 摊开 URL）
- [x] 层内检查 `test/surface/readme_test.dart`：8 条断言（离线安全 / 徽章行 / HTML / 代码块 / 压缩 / 截断 / 空态）
- [x] 离线红线：README 里的图片**一律不联网取**（避免徽章与截图拖死首屏）

### W8-P5 · 搜索页重写 ✅ 本批

- [x] `search_page.dart` 重写：`OgLPageScaffold` + 搜索行（`OgLTextField` **回车即搜**）+ `OgLSegmented`
      + 右侧**结果计数**说明 + `OgLBox` 包结果行
- [x] **Kit 补能力**：`OgLTextField` 新增 `onSubmitted` / `textInputAction` / `autofocus`
      （搜索这种"敲完就走"的场景，旧组件不支持回车 → 用户只能去够按钮）
- [x] **未搜索 ≠ 空结果**：未搜 = `OgLBlankslate` + **常用限定符行（可点即拼进输入框）**；
      空结果 = Blankslate 回显关键词并给放宽建议
- [x] **代码结果可点**（旧实现点了没反应 —— 属于"功能失效"）：按 `repository.full_name` 造最小
      `GhRepo` 跳进仓库页（仓库页会自行补齐缺字段）
- [x] 护栏：搜索页登记为 `converted: true`（骨架 / 无自写滚动 / 无手写状态判定）

### W8-P6 · 我的（账户）+ 议题详情 ✅ 本批

- [x] **我的** `profile_page.dart` 重写：`OgLPageScaffold` + 四个小节（账户 / 当前会话 / 内容 / 危险区）；
      账户行 = 自绘钥匙图标（当前用 accent）+「当前」标签 + 切换/移除按钮；空态 = Blankslate + 「接入令牌」动作；
      新增账户走 `ColoredBox + SafeArea`（不再套 Material `Scaffold`）；退出登录二次确认且文案说明"只删本机令牌"
- [x] **议题详情** `issue_page.dart` 重写：页头（返回键 + `#N 标题` + by/日期）+ 状态行（`OgLStateLabel`）
      + 「描述」「评论」两节；**正文与评论改用 `OgLReadmeView` 渲染 Markdown**（旧实现是等宽裸文本）；
      关闭/**重新打开**同一入口（据当前状态切换）+ 二次确认；空评论 = 空态
- [x] **Kit 补能力**：`OgLIconButton`（自绘图标按钮，≥44，支持 danger）公开给所有详情页做返回键/工具；
      **图标包 +2**：`arrowLeft`（返回）、`chat`（评论）—— 47 个语义，矢量表与枚举数量保持一致
- [x] **外链唯一入口** `lib/surface/readme/link_opener.dart`（`ogLOpenExternal`）：仓库页与议题页共用，
      失败返回 `false` 由页面把 URL 摊开（杜绝"点了没反应"）

### W8-P8 · 剩余页面一次性收口（累积推送）✅ 本批

> **推送策略变更（按用户要求）**：不再"一页一推"，改为**累积推送** ——
> 一批包含 3～10 页（代码 + 测试 + 文档同批），批内用等价脚本预跑护栏后再推一次；
> CI 绿才开下一批，红灯才补一次修复推送。

- [x] **提交详情** `commit_page.dart`：骨架 + 返回键 + 语义标签（N 文件 / +N / −N）+
      **分色补丁**（`+` 绿 / `−` 红 / `@@` 灰，等宽，超长按行截断并告知行数）
- [x] **Gists** `gists_page.dart`：骨架 + 整行可点（`ogLOpenExternal` 打开浏览器）+
      条数/可见性/日期 + 公开/私密标签 + 空态说明
- [x] **登录向导** `login_page.dart`：骨架 + **四步进度可见**（暂存 → 验证 → 转正 → 保险库回读）+
      回车即验证 + 失败提示带"日志在哪看" + 取令牌三步指引
- [x] **三个表单页**（新建仓库 / 议题 / 发布）：骨架 + 行内校验 + `OgLActionRow + OgLToggleSwitch`
      开关行（**彻底清掉 Material `SwitchListTile`**）+ 底部主操作 + 失败原因提示
- [x] **关于页** `og_l_app.dart`（`_AboutPage`）：骨架 + 七个小节（启动报告 / 引导与模块 /
      信任告警 / 依赖图 / 启动阶段 / 日志）+ 信任链正常空态 + 日志尾部截断显示与**一键复制全部**；
      `ExpansionTile` / `IconButton` / 裸 `ListView` 全部退役
- [x] **护栏升级到"全页面 converted"**：12 个页面全部登记为 `converted: true`（必须走骨架、
      禁自写滚动、禁手写状态判定）；`og_l_app.dart` 额外禁 `ListView(` / `ExpansionTile(` / `IconButton(`
- [x] 批内自查：等价脚本预跑（页面 + 应用壳）**0 违规**

### W8-P9 · 代码搜索直达文件 + E1/E2/E3 首批 ✅ 本批

- [x] **代码搜索增强**：`OgLRepoPage` 新增 `initialPath`（可选）—— 代码搜索结果点进去
      **直接打开命中的那个文件**（旧实现只把人丢到仓库首页）；命中上下文用
      `text_matches.fragment` 显示为行副标题（没有则退回"仓库 · 点开直达该文件"）
- [x] **E1 动效**：新增护栏测试 —— `reducedMotion ⇒ motion() == Duration.zero`、
      紧凑密度比 `fast` 长的动效再快一档、`textScale` 夹紧 ≤2.0
- [x] **E2 性能**：主壳 `IndexedStack` 改为**懒挂载**（只构建访问过的 tab，
      未访问用 `SizedBox.shrink()` 占位）—— 冷启动不再同时拉起五个页面及其控制器/请求
- [x] **E3 代码之美**：新增 `lib/surface/util/gh_view_format.dart`（唯一实现处）：
      `ogLNodeLogin` / `ogLDateOnly` / `ogLFileStatusText` / `ogLShortSha` / `ogLCommitAuthor`；
      议题 / PR / 提交 / Gists 四个页面里的重复私有实现**全部删除**，改为共用
- [x] 层内检查：`test/surface/gh_view_format_test.dart`（格式 5 组 + 动效/密度/字号 4 组断言）

### W9-P1 · 议题 / PR 列表：状态筛选 + 加载更多 ✅ 本批

- [x] `GhApi.issues/pulls` 本就支持 `state/per_page/page`，但界面**只拉第一页 30 条且不能筛**；
      现在仓库页这两个标签顶部有 `OgLSegmented`（**打开中 / 已关闭 / 全部**）+ 右侧计数
- [x] 尾部「加载更多（当前 N 条）」→ 拉下一页**追加**；到底后显示「没有更多了（已加载 N 条）」
      （诚实启发式：返回条数 < 每页条数 ⇒ 到底；GitHub 这两个接口不给总数）
- [x] 筛选变化 = 重新从第一页拉（丢弃旧分页结果），避免"换了筛选还混着旧数据"
- [x] 议题行：状态中文（打开中 / 已关闭）+ **只有打开中的才给「关闭」按钮**；空态文案随筛选变化
- [x] 失败可见：加载更多失败 → 日志（critical）+ 页面错误提示

### W9-P2 · 日志落盘 + 全链路结果记录 ✅ 本批

> 用户原话："你的日志估计什么都没有记录，而且极其不全面……始终保存到 sdcard/logging"。
> 这条彻底照做：**日志不再只在内存里**，而且**不只记错误**。

- [x] 新增 `lib/kernel/log/og_l_log_file.dart`：**即时落盘**（写后排队 flush）、
      按天切分、超限滚动（`.1.log`）、候选目录逐个探测（带真实写入探针）、
      失败时保留"试过哪些目录 + 原因"（关于页可见）
- [x] 新增 `lib/base/log/log_dirs.dart`：候选链 `sdcard/logging` → 应用外部目录 →
      应用文档目录 → 应用支持目录（非 Android 平台同理取"看得见"的文档目录）
- [x] `main.dart`：启动第一件事初始化落盘；**启动链路全记录**（底座装配 / 内核引导 / 模块数 /
      信任告警 / 存储接线 / runApp）；`FlutterError.onError` 与平台未捕获异常**连堆栈写盘**
- [x] `OgLAppLog`：内存上限 200 → **2000**；每条日志同时落盘；新增 `result()` / `step()`，
      **成功结果也入库**（例：`✔ 拉取议题：30 条`）
- [x] `OgLAsyncController.load()`：自动记录 **开始 → 结果（条数/字符数 + 耗时 ms）→ 失败**
- [x] `GhClient.send()`：每个请求记录 **→ 方法/路径/查询**、**← 状态码/体积/耗时/限流余量/镜像**、
      失败再记一行 `✗`（含映射后的异常）
- [x] Android 权限：新增 `tool/inject_android_manifest.py`（幂等）注入
      `INTERNET` + `MANAGE_EXTERNAL_STORAGE` + `READ/WRITE_EXTERNAL_STORAGE(maxSdk)` +
      `requestLegacyExternalStorage`；CI 产包护栏同步加验（缺一即红）
- [x] 关于页新增「日志文件」小节：当前文件路径（可一键复制）、未落盘原因、试过的目录、
      以及"如何让日志写进 sdcard/logging"的说明
- [x] 层内检查 `test/kernel/log_file_test.dart`：真实写盘 / 候选回退 / 全失败不抛 / 滚动 / 与 `OgLAppLog` 联通

## 3. 推送策略（硬性）

1. 每波收口**一次** push（代码 + 检查 + 文档 同批）；
2. push 后等 **CI 绿** 才进下一波；CI 红则修复后重推同一波；
3. **开发期不等构建**（build 随 push 自动跑，不阻塞推进；W5 收口时统一核 13/13）；
4. 推送**前 / 后各备份 1 份** tar.gz 到 `_backup/`（命名含波次与时间）；
5. 每波收口**更新记忆档案**（状态卡：波次 / commit / CI / 下一波）。

## 4. 验收指标（第二阶段完成定义）

- CI：`analyze --fatal-infos --fatal-warnings` + 全部测试绿（每波）；
- 构建：13/13 目标绿（收口核验）；
- 规范：`DESIGN.md` 全令牌条目 + 一致性测试绿 + `UI_SYSTEM_V3` 全勾；
- 真机核验清单：
  1. 登录后重启应用，**登录仍在**（缓存问题消失）；
  2. 打开中文 / emoji 文件，**无解码错误**；
  3. 仓库页标签为**水平下划线导航**，且**七个标签功能全部可用**（W1）；
  4. **无大面积灰色块**（W2）；
  5. 图标为**自绘矢量**（非 Material 字形）（W3）；
  6. 更新安装可直接覆盖（固定证书）；
  7. 关于页无 `OGL-BOOT-107`（开发旁路关闭）；
  8. 界面逐控件符合 Primer 规范（W4 核对表通过）。