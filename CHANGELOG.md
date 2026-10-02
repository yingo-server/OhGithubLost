# 变更记录（CHANGELOG）

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增（第二阶段 · UI 精修与功能复查 W0–W4）

- **UI 设计规范落库（W0）**：仓库根 `DESIGN.md`（design-md 格式：72 个颜色令牌 × 4 套调色板、
  字阶 / 间距 / 圆角 / 18 个组件令牌 + 8 章散文）；`docs/UI_SYSTEM_V3.md` 升级为**逐控件清单**
  （Primer 对照路径 / 状态 / 尺寸 / 实现 / 测试 / 勾选）。
- **新组件（W2）**：`OgLBlankslate`（空态）· `OgLBox`（分区容器）· `OgLStateView`（载/空/错三态收敛）·
  `OgLToggleSwitch`（自绘开关，整行可点）。
- **自绘矢量图标体系（W3）**：`lib/surface/icons/og_l_vector_icon.dart`（45 个语义的手写路径，
  24×24 网格、**纯直线**、端点 butt / 拐角 miter）+ `lib/surface/kit/kit_icon.dart`（`OgLIcon`）；
  图标包改为只描述风格（标准线性 1.75 / 极简细线 1.35 / 锐利实心 1.7），历史 ID 保持兼容。
- **组件快照矩阵（W4）**：`test/surface/ui_component_matrix_test.dart` 产出
  `build/ui_shots/matrix_<主题>__<明暗>.png`（两主题 × 明暗 × 全部 Kit 组件 + 45 图标总览，CI 工件可下载）。

### 修复（第二阶段）

- **解码错误**：`GhContent.decodeContent` 用 `String.fromCharCodes` → 改 `utf8.decode(allowMalformed: true)`
  （中文 / emoji 不再乱码）。
- **登录不缓存**：`PlatformStorage.open()` 从未接线 → 新增 `lib/base/base_bootstrap.dart`
  （真机用 `IoDiskKv` / `SecureDiskVault`，失败回内存并**大声上报**）。
- **仓库页标签竖排**：`Wrap + OgLButton` → `OgLUnderlineNav`（水平下划线导航）；
  搜索页模式切换 → `OgLSegmented`。
- **"大面积灰色块"（W1/W2，三条根因）**：① 输入框 `filled: true + surfaceAlt` 灰底大板 → 改 Primer 描边不填充；
  ② `OgLBanner` 用 `color.withAlpha(26)` 铺满整条 → 改面板色 + 语义描边；③ 空态被 Banner 冒充 / Pages 失败
  永远停在骨架 → 改 `OgLBlankslate` + 明确错误与重试。
- **文件打开失败＝静默失败**：错误只在文件视图渲染而失败时仍在目录视图 → 目录视图显示"文件打开失败 + 重试"。
- **仓库改名后失联**：后续请求仍用旧全名 → 引入 `_full` 全名状态，改名后继续可用。
- **图标未更换**：全仓库 53 处 `Icon(ogL.icon(X))` → `OgLIcon(name: X)`，清掉最后一处 Material 字形。

### 验证（第二阶段）

- CI 全绿：`8b51367c`（W1+W2）· `7c6cfdeb`（W3）· `b634b863`（W4）。
- 新增测试：`design_spec_sync_test`（规范 ↔ 代码令牌 + 控件覆盖）、`kit_states_test`（三态 / 空态 / 交互反馈）、
  `icon_vector_test`（语义全覆盖 / 可解析 / **结构性拦住 `Icons.xxx`**）、`ui_component_matrix_test`（快照矩阵）。
- 本地等价自检：`_setup/w0_selfcheck.py`（模拟测试断言；**曾抓到真实的圆角令牌漂移**）。

### 新增（W8 · 页面级商业重写）

- **`OgLPageScaffold` / `OgLSection`**（`lib/surface/kit/kit_page_scaffold.dart`）：
  统一页头（标题/说明/操作）、边距节律（`OgLSpacing.lg`）、宽屏限行（maxWidth 840 居中）、
  可选下拉刷新；小节负责"页里的分组"。**页面不再自己写 `ListView(padding:)`**。
- **仓库页改用它**：页头 +「仓库元信息盒」（公开/语言/默认分支/Pages 标签 +
  ★/Fork/Issue/体积 统计行，图标全部自绘矢量）+ 下划线导航 + 标签内容。
- **设置页重构**：分区（外观 / 网络·DNS / 开发者 / 账户）+ 行式布局；单选改为
  **整行可点 → 底部选择表**（当前项打勾），开关改为自绘 `OgLToggleSwitch` 行，
  自定义 `_SectionTitle`/`_Banner`/`_KeyValue` 退役；**退出登录补二次确认**（原实现点一下即删令牌）。
- **页面施工图**：`docs/UI_PAGES_PLAN.md`（先规划后写：结构 / 层级 / 行规格 / 状态 / 检查）。
- **首页重写**（W8-P2）：`OgLPageScaffold` + `OgLSegmented`（我的仓库 / 星标仓库，右侧计数说明）
  + `OgLBox` 包行；未登录给 `OgLBanner`（动作：接入令牌）+「接下来」引导；四态全部走 `ogLAsyncView`。
- **页面纪律护栏**（W8-P2）：`test/surface/page_discipline_test.dart` —— 页面不许野生（必须先在施工图立项）、
  不许 `Colors.`/`Color(0x`/`Icons.`/`ListTile(`/`SwitchListTile`/`ChoiceChip`、已重写页面必须走
  `OgLPageScaffold` 且不许自己写 `ListView(`、不许手写"`data == null` 即加载中"。
- **死代码收口**（W8-P2）：删除旧主壳 `OgLShell` 一族与 `app/repos_page.dart`（入口已是 `OgLClientShell`）；
  兜底色值 `Color(0xFFF85149)` 收敛为主题常量 `kOgLDangerDark`。
- **主壳规范化**（W8-P3）：新增 Kit 导航组件 `kit/kit_nav_shell.dart`（`OgLBottomNav` / `OgLNavRail` /
  `OgLNavDrawer` / `OgLShellHeader` / `OgLBrandMark`）；主壳删掉 Material `AppBar`/`NavigationBar`/
  `NavigationRail`/`ListTile`，五个页面的标题与图标收成单一数据源 `_nav`；手机形态不再叠 `AppBar`。
- **护栏升级**：`page_discipline_test.dart` 对主壳额外禁止 Material 导航控件。
- **README 渲染**（W8-P4）：`lib/surface/readme/readme_view.dart` —— 净化 Markdown
  （HTML 清理 / 徽章行删除 / 图片占位 / 空行压缩 / 超长截断且告知）+ `flutter_markdown` 渲染
  （样式表全走令牌）；仓库页「代码」标签下新增 README 区块（四态走 `ogLAsyncView`，
  没有 README = 空态而非错误）；链接用 `url_launcher` 打开，失败摊开 URL。层内检查 8 条断言。
- **搜索页重写 + 输入框补能力**（W8-P5）：`OgLPageScaffold` + 回车即搜 + 分段（仓库/代码）+
  结果计数；未搜索给"常用限定符"可点引导；**代码结果可点进所属仓库**（旧实现点了没反应）；
  `OgLTextField` 新增 `onSubmitted` / `textInputAction` / `autofocus`。
- **我的 + 议题详情**（W8-P6）：账户页四小节（账户/当前会话/内容/危险区）+ 空态引导；
  议题页正文与评论改用 Markdown 渲染（复用 README 渲染器）、关闭/**重新打开**同入口 + 二次确认；
  Kit 新增 `OgLIconButton`；**图标包 +2（`arrowLeft` / `chat`，共 47 个语义）**；
  外链收敛到唯一入口 `ogLOpenExternal()`（失败由页面摊开 URL）。
- **PR 详情**（W8-P7）：`OgLPageScaffold` + 返回键 + 语义状态标签（打开中/草稿/已合并/已关闭）
  + 全量增删统计 + Markdown 描述 + 变更文件行（中文状态 + 每文件 `+N/-N`）；**空变更 = 空态**。
- **剩余页面累积收口**（W8-P8，一次性）：
  **提交详情**（分色补丁 + 超长截断告知）、**Gists**（整行可点用浏览器打开）、
  **登录向导**（四步进度可见 + 回车验证）、**三个表单页**（行内校验 + 自绘开关行，
  彻底清掉 `SwitchListTile`）、**关于页**（七小节 + 信任链空态 + 日志一键复制，退役 `ExpansionTile`）。
  护栏升级：**12 个页面全部 `converted: true`**；`og_l_app.dart` 额外禁 Material 折叠/图标按钮/裸列表。
  推送策略按用户要求改为**累积推送**（一批 3～10 页，批内脚本预跑后再推一次）。
- **代码搜索直达文件 + E1/E2/E3 首批**（W8-P9）：
  `OgLRepoPage` 支持 `initialPath` —— 代码搜索结果**点开直达命中的文件**（含 `text_matches` 上下文）；
  主壳 `IndexedStack` 改**懒挂载**（冷启动不再同时构建五个页面）；新增 `lib/surface/util/gh_view_format.dart`
  统一"翻人话"（登录名 / 日期 / 文件状态 / 短 sha / 作者），四个页面的重复实现全部删除；
  新增护栏测试覆盖**减少动效必须归零**、密度提速、字号夹紧与格式函数。
- **议题 / PR 列表筛选与分页**（W9-P1）：仓库页这两个标签新增状态筛选（打开中 / 已关闭 / 全部）
  与「加载更多」（追加下一页，到底提示"没有更多了"）；切换筛选会重置分页；议题行按状态显示
  中文，并只在打开中时给「关闭」按钮。
- **日志落盘 + 全链路结果记录**（W9-P2）：日志不再只在内存里、也不再只记错误——
  新增内核级落盘器（`sdcard/logging` → 外部/文档/支持目录逐级回退，写后 flush，按天切分与滚动），
  启动链路、页面加载（开始/结果/耗时）、每个网络请求（状态码/体积/耗时/限流余量）、
  全部异常堆栈一律入库；关于页可见"当前日志文件路径 / 未落盘原因"并可一键复制；
  Android 清单注入 `MANAGE_EXTERNAL_STORAGE` 等权限（CI 产包护栏同步加验）。

### 修复（W7 · "空结果 = 加载中"根治 + 领域层硬化）

- **真因**：`OgLAsync.settle()` 在结果为空时进入 `empty` 阶段而 `data` 仍为 null，
  页面却用 `data == null` 当"加载中" ⇒ **零议题 / 零发布 / 零分支 / 零提交 / 零评论 /
  零文件 / 零 Gist / 空搜索一律永远停在骨架屏**（用户报的"仓库里很多标签失效"）。
- **修法**：四态语义下沉为 `OgLAsync.isFirstLoading / isEmptyResult / failureMessage /
  softError`；新增唯一映射点 `ogLAsyncView()`（骨架 / Blankslate / Banner+重试 / 内容）；
  仓库页七标签 + 目录浏览器与 7 个页面（共 12 处判定）全部改走 phase 语义。
- **刷新失败保留内容**：`OgLStateView` 新增 `softError` —— 有数据时只加顶部警告，
  不再把用户已有的内容换成整页错误。
- **领域层硬化**：读端点遇 404 / 409（不存在 / **仓库为空** / 功能未启用）一律当"没有"
  （`listDirectory` / `content` / `commits`）；写路径不受影响（写冲突仍是冲突）。
- **未知默认分支不再瞎猜**：`GhRepo.defaultBranch` 缺字段时为空串，`ref` / `sha`
  仅在非空时携带（交给 GitHub 用真实默认分支）；仓库页用 `GET /repos/{full}` 兜底补齐，
  失败不阻塞浏览。此前猜 `main` 会让默认分支是 `master` 的仓库**整页 404**。
- 新增测试：`test/surface/async_state_test.dart`、`test/domain/gh_absent_test.dart`。

### 修复（签名接线 · 实证驱动）

- **"证书不一致"的真正根因（本轮实测发现）**：此前只把固定 keystore 铺到
  `$HOME/.android/debug.keystore`，但 **AGP 实际并未用它签 release 包** ——
  对两份 CI 产物做**字节级取证**（在 APK Signing Block 窗口里取证书 DER 并比对）：
  两份构建的证书分别是 `DD:53:A9:…` 与 `AC:F7:9E:…`，**互不相同**，且都**不含**
  仓库固定证书（`7F:55:58:68:…`）的 DER 字节。这解释了用户"每次更新都报签名不一致"。
- **修法**：`build.yml` 增加 `重签 APK（固定证书）` 步骤 —— 构建后
  `zipalign -p -f 4` → `apksigner sign --ks <固定 keystore>`（同时开 v1/v2 签名），
  随后逐包跑 **`tool/verify_apk_cert.py`** 校验证书指纹，**不一致即让流水线失败**。
- 新工具：`tool/verify_apk_cert.py`（在签名块窗口内提取证书 DER 并比对，
  避免把应用内嵌的 CA 误当签名证书）。

### 新增（UI v3 重写与发布工程 · 随首个 Release `v0.1.0` 发布）
- **设计系统 v3**：两主题——`primer`（GitHub Primer 官方令牌）/ `ogl.spatial`（自研）；旧三主题退役。
- **OGL Kit**（`lib/surface/kit/`）：按钮 / 输入框 / 对话框 / 提示横幅 / 标签 / 列表行 / 加载 / 骨架 / 页头，
  全令牌驱动、零硬编码。
- **客户端主壳与页面群**：登录门（令牌向导 + 游客）、首页（我的/星标/新建仓库）、搜索（仓库/代码）、
  我的（账户管理）、仓库七标签（代码 / 议题 / PR / 发布 / 分支 / 提交 / 设置）、议题详情、提交对比、
  PR 文件变更、Gist 列表、设置（账户 / 网络·DNS / Pages·CNAME / 危险区）、关于页（启动报告 / 日志）。
- **CI 一键发布**：`workflow_dispatch` 可选通道（stable / beta / alpha）+ 版本号 / 版本名 / 说明，
  构建成功后自动创建 GitHub Release（资产含全平台产物 + 源码 zip/tar.gz）。
- **固定 Android 签名证书**（`.github/signing/`）：所有构建同一签名，支持覆盖安装。
- **发布包关闭开发旁路**：引导清单（Boot Manifest）由 CI 生成 + Ed25519 签名，
  `--dart-define-from-file` 编译期注入（零外部资源）；发布构建缺清单 = 拒绝启动，
  正式包不再出现 OGL-BOOT-107；新增两条防回归测试（信任链 / 注入防空）。

### 修复
- `GhJson` 同名导入漏缺（46 处编译错误：`issue_page` / `pull_page` / `commit_page` / `gists_page` 等）。
- 构建产物下载链路：断点续跑 + 大小校验（工具侧 `get_artifact_px.py` / `get_release.py`）。
- CI 护栏修正：`网络权限护栏` 条件把 `matrix.build` 误写为 `'android'`（实际为 `'apk'`）
  → 从未执行；已修正为 apk 腿逐包开验（护栏从此真正生效）。

### 验证
- CI `efa7ed66`：13/13 平台构建成功；`c2dbd711`：一键发布 + 固定证书落地；
  首个 Release `v0.1.0`（run `36872184715`）。
- 发布信任链：`test/kernel/boot_release_chain_test.dart`（私钥 ↔ 公钥 ↔ 签名）
  + 构建腿注入防空回归（`boot_define_injection_test.dart`）。

## [0.2.0] — L2 中枢级

### 新增
- **API 逻辑（`domain/gh`）**：领域模型（容错解析 / `raw` 保留 / `truncated` / `>1 MB` 识别）、
  多账号认证（令牌只进保险箱、脱敏 `toString`、删除顺序）、请求客户端
  （**限流避让** / 并发闸门 / 分页安全上限 / 错误映射）、端点全量封装、
  **`CacheRemote` 适配（D1–D10 落到真实 GitHub）**。
- **交互逻辑（`domain/ix`）**：会话（上下文 + 偏好 + 持久化）、批量任务
  （**类型级强制确认 + 通道选择 + 可取消 + 逐条结果**）、冲突编排（三方预览 + 处置排序）、
  通知中心（去重合并 / 安全告警不可关）。
- **本地深层信息（`domain/sys`）**：设备 / 应用 / 运行环境 / 内存 / 网络策略，
  以及 **Mod 能力守门**（清单 / 授权 / 撤销 / 审计 / 按授权裁剪）。
- **中枢桥**（`domain_bridge`）与四个模块装配。
- 文档：[FEATURES.md](docs/FEATURES.md)（功能树）、[CODE_MAP.md](docs/CODE_MAP.md)（代码地图）。

### 变更
- 内核 `KernelContext` 增加**可空**的 `probes`，使各层可在注册阶段挂自检项（向后兼容）。
- 镜像选择器新增 `setAllEnabled` / `restrictTo`（供批量任务切换通道）。

### 验证
- CI run `36811401922`：静态分析 0 错 0 警，单元测试 **248/248**。

## [0.1.0] — L0 内核级

### 新增
- **总线段（Kernel）**：契约、类型化 DI、桥注册表、模块总线（拓扑排序 / 环检测）、
  生命周期编排（失败回滚）、诊断中枢。
- **启动层（BootLoader）**：五阶段引导（自检 → 签名 → 模块指纹 → 扩展策略 → 就绪上报）、
  Ed25519 清单签名校验、目录指纹、信任策略与告警收集。
- **CI**：静态分析（警告即失败）+ 单元测试。
- 设计文档五件套：`ARCHITECTURE` / `CONSISTENCY` / `BOOT` / `NAMING` / `STANDARDS`。

### 验证
- CI run `36752266286`：静态分析 ✅、单元测试 **23/23** ✅。

## 0.3.0 — L3 展示层地基

- 新增设计令牌体系（密度 / 间距 / 圆角 / 描边 / 动效 / 字阶），文字缩放夹紧、触摸目标下限、减少动效归零
- 新增自适应布局引擎：断点 600/840/1200、设备形态、导航形态、分栏、网格列数（对宽度单调）、DPI 发丝线
- 新增图标语义层：45 个语义图标 × 3 套图标包，编译器强制每套齐全
- 新增主题引擎与三套内置主题包（VS Code 极客 / WinUI 3 / Material 3），`ThemeData` 收口到单一编译入口
- 新增跨平台权限策略矩阵与状态快照（核心流程零权限依赖；未知状态一律按不可用处理）
- 新增设置模型与开发者选项（含总闸护栏：未开开发者模式时危险开关被强制关闭并留痕）
- 新增表面桥与 `surfaceLayerModules()` 装配入口
- 修复：用户自定义强调色从未生效（存了不用）；设备对角线重复计入 DPR；网格列数非单调；权限缺设置路径
- 移除：`font_awesome_flutter`（`extends IconData` 与 Flutter 3.47 的 `final class IconData` 不兼容）
