# 更新日志

本项目各版本的变更记录，新版本在前。

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