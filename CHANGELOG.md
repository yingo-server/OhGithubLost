# 更新日志

本项目各版本的变更记录，新版本在前。

### 文件操作细节（续）
- **重命名文件**：长按文件 → 重命名（内容不变，**一次原子提交**：新增新路径 + 删除旧路径）；
  新路径同样受"禁中文/特殊字符"校验；`.gitkeep` 不允许重命名。
- **删除目录**：长按目录 → 删除目录，会先枚举其下全部文件并在**一次提交**中删除；
  结果被截断或超过 200 个文件时**拒绝**并提示分批（不静默半删）。

### 系统级通知（接入插件）
- 新增 `flutter_local_notifications`，后台/`allChannels` 通知改为**真正发系统通知**
  （Android / Windows / Linux / macOS / iOS）；失败只留痕并回退到"落盘 + 回前台补发"。
- Android 需 core library desugaring：`tool/inject_android_gradle.py` 现在**幂等注入**
  `compileOptions.isCoreLibraryDesugaringEnabled` 与 `desugar_jdk_libs:2.1.4`，并在自检中校验。

### 动效（R7 续）
- 主题切换带动画（`themeAnimationDuration`）：换明暗 / 主题色不再"硬切"；
  系统关闭动画时自动为 0（与 R11 一致）。

## v5.0.0（计划 · 未发布）

用户明确的 5.0 范围（在 4.9 之后再动）：

1. **下载管理器多线程下载**：确保真正并发分片；并优化进度条与速度显示的动画。
2. **页面过渡动画卡顿**：自 4.8 起，**页面过渡**动画总是卡顿，而其它动画不卡
   （4.8 引入了 `_OgLShellSlide` + `themeAnimationDuration`，需定位冲突/重复动画）。
3. **Actions 运行日志（详细页）**：长日志加载缓慢，需要懒加载 / 虚拟化 / 分块渲染。
4. **通知中心**：emoji 风格"撕裂"（**不应使用 emoji**，改为统一图标）；详情展开无动画。
5. **安卓返回键绑定**：全局返回键行为不佳，需要统一处理（含二级页 / 弹窗 / 抽屉）。

## v4.9.0（2026-10-03）

本版本 = **结构与多语言工程**（不含新功能）。

### 四层结构收口（启动 / 硬件 / 逻辑 / 交互）
- 依赖方向固定为 `surface → domain → base → kernel`，只允许向下。
- 新增交互层**类型门面** `lib/surface/types.dart`：UI 只能看到 DTO / 枚举 / 异常，
  服务类（`GhClient` / `GhAuthService` / `IxDownloadManager` / `IxSession` /
  `IxNotificationCenter`）被 `hide`，只能经 `SurfaceBridge` 取用。
- 15 个页面 / 组件改为只 import 门面；导入段按 `directives_ordering` 重排。
- **下载能力上桥**：`SurfaceBridge` 提供 `downloadTasks / downloadsListenable /
  pauseDownload / resumeDownload / retryDownload / cancelDownload /
  removeDownload / clearFinishedDownloads`，下载页不再接触管理器实现。
- 新增 `tool/layer_audit.py`（四层审计）：**当前违规 0**；domain 直接依赖 base
  内部类型的 11 处已登记为"待收敛"清单，后续批次逐步消掉。

### 多语言（工程侧）
- i18n 内核 `t(page, key, {args})` 支持 `{name}` 占位符（缺参保留原样，不抛异常），
  动态文案（`已删除：{path}`）从此可本地化。
- 新增 `tool/i18n_scan.py`：扫描中文字面量、映射到页面分片、对齐各语言 key 集合，
  并提供 `--check` 供 CI 卡住回退。
- 现状盘点：**1324 处**中文字面量 / **27 个页面分片**；现有分片仅 **66 个 key**
  （common 22 / settings 22 / repo 9 / shell 7 / login 6），覆盖约 5%。
  → 文案抽取与翻译按页面分批推进（zh / zh_TW / en 人工按语境、其余机翻）。

## v4.8.0（2026-10-03）

### 下载加速通道（重做）
- **恢复为独立条目**：设置 → 网络 → 「Release 下载加速」。
- **只有一个总开关**；下面是**通道列表**：内置通道（开发者自建，HTTPS）+ 任意多个
  **自定义通道**，**单选生效**，自定义通道可随时移除（内置不可删）。
- **内置通道地址更新为 `https://server.344977.xyz:9999/`**（HTTPS；此前明文
  `http://…:5000/` 会被 Android 9+ 拦截，正是 4.4.0 那次下载故障的根因）。
- 自定义通道地址**必须是 HTTPS**，且需以 `/` 结尾；明文 http 会被直接拒绝并说明原因。
- 生效条件 = 总开关打开 **且** 已同意当前版本协议；否则一律直连。

### 协议（具法律效力的显式同意）
- 新增两份协议文本与**版本号**（`util/accel.dart`）：
  - **外来服务自负责任协议**（自定义/第三方通道）；
  - **内置通道安全声明**（开发者自建通道）。
- 开启总开关时若未同意当前版本，**必须先勾选"我已阅读并同意上述条款"** 才能继续；
  同意后记录**版本号 + 时间戳**落盘，作为凭据；协议升版需重新同意。

### 其他
- 新增单元测试 `test/surface/path_rules_test.dart`（路径规则 / 空文件 / `.gitkeep` /
  通道地址 / 地址拼接 / 协议区分）。

### 本版本未纳入（4.9 排期）
- **多语言（R6）**：继续后延。
- 目录重命名、跨目录批量操作（当前仅支持单文件重命名与目录删除）。

## v4.7.0（2026-10-03）

R3 / 文件细节 / 通知 / 外观修正（**多语言仍留待下一版本**）：

### 文件创建（仓库 · 代码页）
- **单一 "+" 入口**：原来的"新建文件"按钮改为只有加号的 FAB；
  **添加路径 = 建目录**——路径以 `/` 结尾时自动创建 `<目录>/.gitkeep` 占位
  （Git 不跟踪空目录）。
- **禁止空文件**：新建文件必须填写内容（`.gitkeep` 占位例外）。
- **路径规则**（`util/path_rules.dart`，新建/重命名共用）：只允许
  `A-Z a-z 0-9 . _ -` 与 `/`；**禁止中文与全角字符**、空格与特殊字符；
  禁止 `..`、`//`、以 `/` 开头、以点/空格结尾、Windows 保留名、单级 > 100 字符。
- 同名条目存在时**先拦下**并给出原因（不再等 422）。

### R3 越权入口（用 `permissions.push`，不做降级）
- `GhRepo` 新增 `canPush` / `canAdmin`（解析 `permissions`）与 `isWritable`。
- 仓库页在 `initState` **补拉单仓库详情**（只有该接口返回 `permissions`，
  列表/收藏/搜索都没有）；拿不到详情时留痕并按不可写处理。
- 无写权限时隐藏：**仓库设置标签页**、新建文件 FAB 与空态按钮、
  文件编辑/删除、条目删除、新建发布、新建分支。

### 通知（渠道参数 + 前后台分流）
- 新增 `OgLNoticeDelivery{auto, inAppOnly, allChannels}`，`report()` 可指定投递方式。
- `OgLNoticeHost` 接入 `WidgetsBindingObserver`：**后台不弹应用内提示**，
  `allChannels` / critical 走系统通道，其余排队并在**回到前台时补发**（不丢消息）。

### 外观
- 外观页 `ChoiceChip` 选中态改为 `primary/onPrimary`，**明环境下对比度提升**；
  主题色芯片不再用勾号顶掉色点。

## v4.6.0（2026-10-03）

第三阶段（工程与交互）：

- **R10 工作流参数表单**：手动触发工作流时，读取该工作流 YAML 的
  `on.workflow_dispatch.inputs`，把**必选参数 / 默认值 / 选项**渲染成表单
  （字符串 / 数字 / 布尔 / 下拉选择），必选缺失会在提交前拦下并提示；
  保留「高级：直接输入」入口（JSON 或每行 `key=value`）。新增纯 Dart 依赖 `yaml`。
- **R7 页面切换动画**：底部 / 侧边导航切换时加入**左右滑动**入场过渡
  （保留 `IndexedStack` 的状态与懒挂载）；关闭动画时瞬时切换。

> 待办：**R6 多语言**（其余页面仍有硬编码中文）体量较大，需要单独排期
> 逐页抽取文案 + 补齐各语言分片，本次未纳入，以免产出半成品的一致性问题。

## v4.5.0（2026-10-03）

第二阶段（体验）修复：

- **R1 通知中心**：条目可点击展开**完整详情**（时间 / 区域 / 正文，可选中复制）；
  新增「已读 / 未读」状态与「标记已读 / 全部已读」；保留「重置通知中心」
  （只清内存条目，磁盘日志不动）。
- **R4 只读缓存**：新增中枢级只读端点缓存（`GhReadCache`），为 Releases /
  分支 / 提交 / Issues / PR / Actions / 仓库详情等只读端点设定缓存时长
  （30–60 秒），账号维度隔离；**下拉刷新 / 写后重读会让缓存失效**并回源；
  切换账号时清空。搜索、用户、限流端点不缓存（必须新鲜）。写操作令整体失效。
- **R5 Release 附件**：点击改为**查看文件详情**（大小 / 类型 / 下载次数 / 直链），
  下载与复制链接移到详情弹窗与**长按**菜单——不再点一下就下载。
- **R11 动画警告**：检测到系统关闭动画（开发者选项 / 无障碍）时，启动即通过
  通知中心给出**明确警告**（此前应用不给任何提示，属缺陷）。

## v4.4.0（2026-10-03）

修复（设备实测反馈）

- **下载：不再走明文加速通道**。该通道仅支持 HTTP（无 TLS），在 Android 9+ 会被
  系统直接拦截（`Cleartext HTTP traffic to ... not permitted`）。设置项已从界面
  移除；通道地址仍只存在于实现内部常量，不对外暴露。
- **下载完成显示真实大小**：库对小文件可能一次进度事件都不发，此前界面一直显示
  `0 B`；现于完成时以磁盘文件大小回填（读不到则按事件码 `OGL-DL-101` 上报）。
- **Actions 筛选失效**：成功 / 失败 / 进行中筛选此前只用于判断空态，列表仍渲染
  全量；现按筛选后的子集渲染。
- **搜索页切换标签不清空结果**：切「仓库 / 代码」时清空旧结果与输入框。
- **切换 / 移除账号时清空全部缓存**：仓库缓存 + DNS 缓存 + 页面分页快照
  （避免"用 B 账号看到 A 账号的私有数据"）。
- **通知中心打通**：内核诊断的 **warn 与 error** 现在都会进入通知中心
  （error → 严重级弹窗；warn → 横幅），且要求携带事件码——不允许静默降级。

## v4.3.0（2026-10-03）

下载

- Release 附件加速**改为设置项**（设置 → 网络 →「Release 附件加速通道」），
  默认**关闭** —— 加速通道属于第三方信任边界，需用户显式开启；关闭后附件直连。
  该开关只作用于 Release 附件，不影响仓库文件 / Gist 的下载。
- **通道地址不再出现在任何界面文案或设置项中**（收敛为实现内部常量）。

## v4.2.0（2026-10-03）

本版：网络传输弃用 dio、代码编辑与高亮换用成熟库、并批量修复设备日志排查出的
问题（P2–P7）。

代码查看与编辑（**换用成熟库**）

- 新增 `re_editor`（编辑器内核）+ `re_highlight`（语法高亮，highlight.js 的 Dart
  移植）；删除自研词法器与自绘渲染 `lib/surface/widgets/code_view.dart`。
- 编辑器不再使用"高亮图层 + 透明输入层"叠加：语法高亮、行号、查找替换、
  撤销重做、折叠、快捷键全部由库提供，光标 / 换行 / 滚动不再错位。
- 查看器（仓库文件、Gist）与编辑器共用同一套库渲染（`OgLCodeViewer` /
  `OgLCodeField`）；超大文本改由库的 `CodeHighlightThemeMode.maxSize` 兜底。
- 保留项目语义：语言识别（按扩展名 / 文件名）、设置里的高亮预设与自定义配色
  （翻译为 highlight.js 主题表）、草稿防抖落盘、加锁保存与冲突提示。

下载（`background_downloader`，本就是库实现）

- 移除旧自研分块下载器遗留的 `threadsActive` 字段（从未赋值）；
- 进度速率改为按库的进度事件**差分估算**（此前该字段恒为 0，界面上的速率是假的）。

网络（**弃用 dio**）

- 传输层由 `dio` 改为**直接使用 `dart:io HttpClient`**（新增 `lib/base/net/io_net_transport.dart`，
  删除 `dio_net_transport.dart`），`pubspec.yaml` 移除 `dio` 依赖；Actions 日志下载（`IxActionLogs`）
  同步改为 `HttpClient`。理由：Dio 把"连接策略"藏进适配器层，排查与修都无法直接动手。
- **禁用 keep-alive 连接复用**（每个请求 `request.persistentConnection = false`，
  即请求头带 `connection: close`）：
  设备日志实证 `Connection closed before full header was received` 反复出现，
  而同一时刻原生自检全绿——差别只在"是否复用连接"。禁用复用后每个请求走新连接，
  从根上消除该类故障。
- 连接类失败（`SocketException` / `HttpException`）统一归为**可重试**的连接错误，
  并在重试前**清空 DNS 缓存**（避免钉在坏 IP 上）。
- 新增 PoC / 回归测试 `test/base/net_transport_reconnect_test.dart`：
  对端"响应后即关闭连接"时，连续请求必须全部成功；并断言连接策略已禁用复用。

日志排查后续修复（P2–P7）

- **P2 未分类网络错误现在可重试**：`dart:io` 把"连接在接收中被关闭"等场景归入
  `unknown`，此前不可重试，大响应中途失败即终止；现纳入可重试类别
  （是否真正重试仍受"仅幂等方法"约束，`POST` 依旧不会自动重试）。
- **P3 仓库浏览不再绕过缓存**：目录列表与文件读取原先一律 `refresh: true`，
  使底座缓存永不命中、每次切目录/切标签都重新下载；现默认走缓存，
  仅下拉刷新 / 写操作后强制回源。
- **P4 切标签不再重复拉取**：分页数据源新增"同目标 6 秒内的成功快照"，
  标签页被 `TabBarView` 销毁重建时秒开、不再重复请求；
  用户下拉刷新与写后重载不受影响（始终回源）。
- **P5 正常缺省不再报错**：404（无 README / CNAME / Pages）降级为 WARN；
  `readme()` 改为直接请求 `/readme`，去掉"先探测 `README.md`"的额外一次 404。
- **P6 窗口日志节流**：幽灵键盘 inset 高频抖动不再逐条落盘（同形态最多 1 秒 1 条）。
- **P7 重负载端点分页调小**：发布 / Actions 每页 30 → 10，降低单次响应体积
  （此前单次可达数百 KB ~ 2 MB）与弱网中断概率。

## v4.1.0（2026-10-03）

本版聚焦「仓库浏览」的补齐与控件/布局的 Material 3 规范化。

仓库浏览

- 新增**分支切换**：AppBar 下方常驻分支栏（Material 底部弹层 + 搜索），
  切换后「代码 / 提交 / 发布 / Actions」同步；
- 新增**新建文件**：代码标签提供 `FloatingActionButton` 入口（路径 + 内容）；
- 新增**目录内筛选**：按名称过滤当前目录条目；
- 新增**图片预览**：png / jpg / jpeg / gif / webp / bmp / ico 在应用内预览（可缩放），
  不再显示为二进制乱码；
- 新增**分页「加载更多」**：首页仓库列表（我的 / 星标）与仓库页的
  发布 / 分支 / 提交 / Actions 统一分页；
- `GhApi.workflowRuns` 新增 `branch` / `page` 参数。

控件与布局（Material 3）

- 「新建」类主操作统一为 `FloatingActionButton.extended`
  （新建仓库 / 新建议题 / 新建发布 / 新建分支 / 新建文件）；
- 次要操作收进 `PopupMenuButton`：仓库（复刻 / 复制克隆地址 / 浏览器打开）、
  文件（复制路径 / 浏览器打开 / 删除）、分支（重命名 / 删除）；
- 空 / 错 / 载三态与「加载更多」底部按钮统一；列表项统一 `ListTile` + `OgLReveal`；
- 危险操作（删除文件 / 删除分支 / 删除仓库）统一二次确认。

已知限制（客观）

- 分支切换作用于上述标签；议题 / PR 列表仍为仓库级（相关接口不按分支过滤）；
- 代码标签的目录内容由 Contents API 一次性返回，「加载更多」在代码标签仅表现为一次拉取；
- 文件内查找、blame、图片以外的二进制预览仍未实现。

验证

- 由 CI 验证：质量门（`analyze --fatal-infos --fatal-warnings` + 全量测试）
  与全平台构建矩阵（Android ×5 / Windows ×2 / Linux ×2 / macOS ×2 / iOS ×2）。

## v4.0.0（2026-10-03）

可靠性重构版：自底向上逐层修复，并将多个自研模块替换为成熟库。

验证状态

- CI 质量门通过：`flutter analyze --fatal-infos --fatal-warnings` + 全量单元/渲染测试；
- 全平台构建矩阵通过：13 个目标全部成功（Android ×5：arm64-v8a / armeabi-v7a / x86_64 / universal APK / AAB；
  Windows ×2；Linux ×2；macOS ×2；iOS ×2）。

依赖变更

- 新增 `permission_handler ^13.0.2`（运行时权限）、`background_downloader ^9.6.3`（下载）、`archive ^3.6.1`（日志解压）；
- 新增 `dependency_overrides: connectivity_plus: 6.1.4`：`background_downloader` 依赖 `connectivity_plus '>=6.1.3 <8.0.0'`，
  其 7.x 的 macOS / iOS Swift 使用了构建环境 SDK 尚未提供的 `NWPath.isUltraConstrained`，导致 iOS / macOS 构建失败；
  固定到 6.1.4（仍满足上游约束）后恢复；
- 未引入 `highlight` / `flutter_highlight` / `flutter_code_editor`：其 SDK 约束为 Dart < 3，与当前 Dart 3.13 不兼容。

权限

- 权限申请由纯 Dart 网关改为 `permission_handler`：Android / iOS / macOS 会真正调起系统权限弹窗；
  此前实现只执行"写入探针 + 打开设置"，且使用 iOS 专用的 `app-settings:` URI（在 Android 上无效）；
- Android 11+ 的「所有文件访问」使用 `manageExternalStorage`；Android 13+ 运行时请求 `POST_NOTIFICATIONS`；
- 构建期新增 `tool/inject_android_gradle.py`：幂等提升宿主 `compileSdk`（平台目录由 CI 现场生成）；
- 构建期新增 `tool/inject_windows_cmake.py`：为 `permission_handler_windows` 注入 MSVC 兼容宏
  `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS`。

通知

- 统一通知入口：`KernelDiagnostics` 的 error 与引导层信任告警经 sink 转发到 `OgLNoticeCenter`，
  各层（含无 `BuildContext` 的底座 / 中枢）的告警均可触达界面；
- 通知中心新增历史记录列表。

认证

- `GhAuthService` 改为 `ChangeNotifier` 并引入 `GhAuthState`（unknown / signedOut / signingIn / signedIn / expired / guest）；
- HTTP 401 作为唯一出口触发失效标记；外壳订阅认证状态，令牌失效后自动回到登录门；切号 / 登出会通知订阅方。

草稿

- `DraftStore` 改为 `ChangeNotifier`，并通过 `GhApi.draftsChanged` 暴露；
  草稿箱与「我的」页订阅后实时刷新（此前为一次性查询）。

编辑器

- 编辑区改为「高亮图层 + 透明输入层」叠加，编辑过程中可见语法高亮（复用项目既有词法器；未引入 `highlight` 系库的原因见上）；
- 撤销 / 重做改用 Flutter 内建 `UndoHistoryController`（替换自研防抖快照栈）。

下载

- 下载实现由自研分块下载器改为 `background_downloader`（断点续传 / 队列 / 暂停 / 继续 / 取消）；
- 保持 `IxDownloadManager` / `IxDownloadTask` / `IxDownloadCategory` / `IxDownloadStatus` 对外契约不变，相关页面未改动；
- 落盘位置随库能力调整为「应用文档目录 / ogl / download / <分类>」（该库仅支持其 `BaseDirectory` 枚举，不支持任意绝对路径）。

Actions

- 新增运行日志：带令牌下载日志 zip 并经 `archive` 解压，按 job 展示与搜索
  （`ix_action_logs.dart` + `action_log_page.dart`）；
- 新增产物（artifacts）列表与下载地址端点。

动效

- 列表入场动效统一走 `OgLReveal` 与动效档位；本次覆盖搜索等页面。

其他

- 关于页依赖许可清单补充 `permission_handler` / `background_downloader` / `archive`；
- Android 发布护栏新增 `POST_NOTIFICATIONS` 断言；
- Windows 上的构建期 Python 脚本改为 ASCII 输出，并设置 `PYTHONIOENCODING=utf-8`
  （此前在 Windows 默认码页下打印非 ASCII 会抛 `UnicodeEncodeError` 并使该构建目标失败）。

已知限制

- `background_downloader 9.6.3` 的 `flutter.plugin.platforms` 仅声明 android / ios；桌面端（Windows / Linux / macOS）
  不注册该插件，桌面端下载功能不可用；
- 编辑器高亮为图层叠加实现，长文件下的滚动同步与自动换行场景尚未逐一验证；
- 动效为逐页补齐，尚未覆盖全部页面。

## v3.2.0（2026-10-03）

动效（与设置里的「动效档位」联动）

- 新增档位作用域与动效工具箱：动画时长与叠加效果按档位 0–3 变化；
- 入场动画覆盖：首页仓库、下载管理、通知中心、草稿箱、仓库页（Issues / Pull Requests / Releases / 分支 / 提交 / Actions）；
- 加载 / 空 / 错误三态之间加入淡入淡出；
- 档位 0 完全关闭动画；档位 1 仅淡入、档位 2 淡入 + 位移、档位 3 再叠缩放（开销随档位增加）；
- 新增分档与回退测试（时长递增、降到 0 回退为零、按档位叠加效果）。

其他

- 规划文档：新增 `docs/ANIMATION_PLAN.md`（3.2 任务与性能对应）；
- 交互细项（分段选择位移、对话框曲线、共享元素等）移交 3.3。

## v3.1.0（2026-10-03）

下载

- 内建下载器：多线程（32 线程）分块下载，支持暂停 / 继续 / 取消 / 重试 / 移除；
- 小于 16 MB 的文件一次铺满并发；服务器不支持 Range 时自动退回单流；
- 下载管理页展示进度与速率；首页右上角加入口；
- Release 附件经内置代理加速，落盘到 `ogl/download/<分类>/`。

文件与日志

- 统一应用根目录 `ogl`：日志落到 `ogl/logging`，下载按分类存放；
- 平台路径适配：Android 优先外部可见目录，不可写时退到应用外部目录；桌面用文档目录。

草稿

- 编辑器自动保存草稿；再次进入同一文件自动恢复并提醒；提交成功后清除；
- 「我的」页新增草稿箱入口。

可靠性与权限

- 启动接入失败写入重放；
- CNAME 更新改为加锁写入；
- 权限网关：Android 存储用真实写入探针主动获取，失败弹窗并跳转系统设置；
- 引导改为分步（欢迎 / 权限 / 隐私 / 完成）。

其他

- 首页右上角新增通知中心（可按告警 / 错误筛选、单条复制）。

## v3.0.0（2026-10-03）

界面

- 设置页改为可折叠分组，默认收起，并补充更多设置项与子项。
- 新增动效档位设置：最小 / 当前 / 标准 / 增强。
- 「关于」整理为设置页内的独立页面，展示项目名称、主要开发者、版本、仓库地址、未来扩展与启动诊断。
- 首页移除无响应的刷新按钮，保留下拉刷新。

功能

- 新增「捐赠一颗心」：二次确认后，用当前登录账号为本仓库加星；已 star 时不会重复操作。
- 新增「开源许可」栏目：本项目许可与第三方依赖清单。
- 新增「日志」栏目：日志文件位置与复制入口。
- 新增 15 种界面语言，翻译按页面分片保存。

可靠性

- 写入与删除带基线校验；冲突时先提示，再决定是否覆盖。

其他

- 开源许可切换为 AGPL-3.0。
- 新增星标与提交历史图表（见仓库首页）。
- 清理部分过时文案。

## v2.2.0（2026-10-02）

- 合并原定 v2.1.0 的内容（v2.1.0 未发布）。
- 修复静态分析错误后重新构建，发布产物 19 个。

## v2.1.0（未发布）

- 内容并入 v2.2.0。

## v2.0.0（2026-10-02）

- 修复手动发布时安装包版本号回落为 0.1.0 的问题：发布参数改为必填，并在构建阶段校验产物版本号。
- 构建版本号注入覆盖各平台产物。

## v1.4（2026-10-02）

- 新增缓存读取加速：目录与文件在短时间内命中缓存，下拉刷新可取最新。
- 写入与删除带基线校验，冲突时给出提示。
- 新增独立代码编辑器：撤销 / 重做、查找 / 替换、换行与字号、未保存提醒。
- 新增发布详情：附件下载、编辑与删除。
- 新增 Actions 运行详情（作业与步骤）与重新运行 / 取消。
- 新增手动触发工作流。
- 新增 Gist 列表、详情、新建、编辑与删除。
- Issues 支持评论。
- 文件图标按类型配色；代码高亮提供多种预设。

## v1.1.0（2026-10-01）

- 展示层重写，统一为 Material 3 组件。

## v1.0.0（2026-10-01）

- 首个版本，提供 Android / Windows / Linux / macOS / iOS 构建。