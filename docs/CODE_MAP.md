# OGL 代码地图（CODE_MAP）

> 用途：**上手导航 + 改动前必读**。
> 每行给出：文件 · 行数 · 职责 · **该文件不可违背的不变量**。
> 不变量写错 = 数据事故（见 [CONSISTENCY.md](CONSISTENCY.md) / [DURABILITY.md](DURABILITY.md)）。
>
> 统计口径（2026-10-01 实测）：`lib/` **51 文件 / 17,681 行**；`test/` **15 文件 / 6,089 行**；测试 **322 项全过**（CI 全绿）。

---

## 依赖规则（先看这个）

```
kernel（L0，零业务依赖）
   ↑
base（L1，只依赖 kernel 的契约与 DI）
   ↑
domain（L2，只经 BaseBridge 拿实例；类型可引用 base 的接口）
   ↑
surface（L3，只经 DomainBridge）
```

- **跨层只准走桥**：`BaseBridge.of(bridges)` / `DomainBridge.of(bridges)`。
- 层间不允许 `import` 对方内部实现文件（只允许接口类型）。
- 同层内部走层内桥（`base_bridge` / `domain_bridge` / `surface_bridge`）。

---

## L0 · 内核级（14 文件 / 2,801 行）

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `kernel/contract/module.dart` | 167 | 层级枚举、模块描述符、状态机、`KernelContext` | 描述符 **运行时不可变**；`id` 必须是 `<layer>.` 前缀；`KernelContext.probes` 可空，模块必须容错 |
| `kernel/di.dart` | 142 | 类型化依赖容器 | **封存后禁止任何注册**；重复注册需显式 `replace` |
| `kernel/bridge_registry.dart` | 66 | 桥注册与发现 | **每层只允许一座桥**；解析带类型断言 |
| `kernel/module_bus.dart` | 172 | 模块注册 / 拓扑排序 / 校验 | ID 唯一；**能力唯一**；依赖必须存在；**环必须被检出** |
| `kernel/lifecycle.dart` | 187 | 注册 / 启动 / 停止 / 回滚 | 启动按拓扑序、停止逆序；**失败必须逆序回滚**；`onStop` 必须幂等 |
| `kernel/diagnostics.dart` | 246 | 日志 / 阶段耗时 / 模块状态 | 环形缓冲有上限；sink 抛异常**必须记录**不得吞 |
| `kernel/environment.dart` | 179 | 环境自检扩展点 | **单项失败/超时不得阻断其余**；封存后禁止注册 |
| `kernel/kernel.dart` | 284 | 内核门面（引导→装配→启动→报告） | `boot()` 只能调一次；`runProbes()` **不改变生命周期** |
| `kernel/boot/boot_manifest.dart` | 290 | 引导清单模型 + canonical JSON | 序列化必须 **canonical**（键序稳定），否则签名不可复现 |
| `kernel/boot/integrity_verifier.dart` | 205 | 签名校验 + 目录指纹 | **签名不过一律拒绝**；指纹用 SHA-256 |
| `kernel/boot/trust_policy.dart` | 135 | 扩展信任策略 | 官方核心 **locked + 强制签名**；主题不设限；Mod 放行但 **必须告警** |
| `kernel/boot/trust_warnings.dart` | 175 | 信任告警收集与序列化 | 告警 **不得被静默丢弃**；可 JSON 导出给 UI |
| `kernel/boot/boot_fs.dart` | 134 | 启动层文件系统抽象 | 只读接口；内存实现必须与真实实现**语义一致** |
| `kernel/boot/boot_loader.dart` | 419 | 五阶段引导编排 | 任一阶段失败 **必须终止并给原因**；安全模式排除而非全拒 |

---

## L1 · 底座级（15 文件 / 4,600 行）

### 网络连接（`lib/base/net/`，7 文件 / 1,998 行）

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `net_types.dart` | 308 | 请求/响应/异常分类/观测类型 | 传输实现的异常**必须翻译成 `NetException`**；`NetObserver` 只记账不决策 |
| `net_retry.dart` | 92 | 退避策略（纯函数） | **不发请求、不持状态**；`Retry-After` 优先但受 `maxDelay` 约束 |
| `net_mirror.dart` | 162 | 镜像通道选择 | 通道**默认关闭**；`apply()` 不匹配返回 `null`（不抛） |
| `net_transport.dart` | 222 | 韧性传输（重试+镜像+观测） | **非幂等方法绝不重试**；**重试耗尽必须显式抛错**（不得把 5xx 当正常响应） |
| `dio_net_transport.dart` | 263 | Dio 翻译层 | 只做异常翻译，**不做策略**；覆盖 `DioExceptionType` 全部分支 |
| `net_dns.dart` | 803 | DNS 策略（系统/自定义 + DoH + UDP） | **事务 ID 不匹配必须拒绝**；回退系统解析 **必留痕**；`system` 模式行为必须与不加 DNS 一致 |
| `net_bridge.dart` | 148 | 网络门面 + 模块 | 策略必须**可见**（`dnsSummary`）；注册 DNS 自检项 |

### 硬盘逻辑（`lib/base/disk/`，7 文件 / 2,530 行）

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `disk_store.dart` | 188 | KV / 保险库 / 文件 / 路径原语 | 接口与内存实现**语义一致**；`InMemoryFileStore.normalize` 是路径归一化的唯一真源 |
| `disk_types.dart` | 500 | 缓存键/条目/写意图/结果/三方/处置建议 | 作用域四元组**不可缺维**；路径**拒绝 `..`**；`staleSha` 的处置建议**必含 `viewDiff`** |
| `disk_cache.dart` | 796 | 一致性引擎 D1–D10 | **write 永不外抛**；**读写都进逐键锁**；缺基线不写；**无 rebase 不自动覆盖**；写后必回读；**force 也需二次确认**；内容 **len+SHA-256 校验** |
| `disk_journal.dart` | 325 | 提交日志（D8） | **写前落盘**；重放**不降标准、不重复入队**；语义冲突标 abandoned 不自动重放；`failByKey` 只动最新一条 |
| `disk_draft.dart` | 200 | 草稿（D9） | 先落盘后展示；**提交成功必须清草稿** |
| `platform_io.dart` | 362 | 真实持久化 | **原子写**（tmp→flush→rename）；启动清扫 `.tmp`；KV 文件名用摘要；路径不得逃出根目录 |
| `disk_bridge.dart` | 159 | 硬盘门面 + 模块 | 三处接线（诊断/日志/草稿）**一个都不能省** |

### 层桥

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `base/base_bridge.dart` | 72 | L1 唯一出口 + 装配 | 桥只在 `base.layer` 注册一次；`baseLayerModules()` 顺序 = sys 无关（net/disk 无依赖） |

---

## L2 · 中枢级（11 文件 / 5,476 行）

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `gh/gh_models.dart` | 948 | 领域模型 + 容错解析 | **缺字段不得崩**；`raw` 必须保留；`truncated` 必须暴露；`>1 MB` 必须识别 |
| `gh/gh_auth.dart` | 298 | 多账号 + 令牌 | 令牌**只在保险库**；`toString` **只出脱敏**；删除顺序 = 先密文后元数据 |
| `gh/gh_client.dart` | 502 | 请求构造/限流/并发/分页/错误映射 | **额度耗尽不发请求**；分页**必须有安全上限**；409/422 仅在显式要求时转冲突 |
| `gh/gh_api.dart` | 976 | 端点封装 + `CacheRemote` | `read` **拿不到内容返回 `null`**（绝不返回空串）；批量提交**先校验期望 sha**；`write` 必带基线 |
| `ix/ix_session.dart` | 342 | 会话上下文 + 偏好 | 状态**持久化且损坏自清**；目录置顶优先于排序方向 |
| `ix/ix_task.dart` | 444 | 批量任务编排 | **无确认不得开工**；**通道切换先于第一个请求**；单项失败不中断；**逐条汇报** |
| `ix/ix_conflict.dart` | 271 | 冲突 → 用户决策 | 选项顺序即推荐顺序；**危险项绝不排首位**；危险动作 `allowed` 必须 `confirmed` |
| `ix/ix_notify.dart` | 228 | 通知中心 | 同类**合并计数**；**安全告警不可关闭且不被淘汰** |
| `sys/sys_info.dart` | 572 | 本地深层信息 | **拿不到就说拿不到**（`source` 标注）；单项失败不拖垮整体 |
| `sys/sys_access.dart` | 495 | Mod 能力守门 | 公开能力**自动可用不留记录**；**未授权字段根本不出现**；越权必审计；读-改-写**串行原子** |
| `domain_bridge.dart` | 400 | L2 唯一出口 + 四个模块 | **`cache.bindRemote(api)` 必须且只能在这里接** |

---

## L3 · 消费级（10 文件 / 4,714 行；另有入口 `main.dart` 90 行）

### 主题体系（`lib/surface/theme/`）

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `design_tokens.dart` | 344 | 设计令牌（密度/间距/圆角/描边/时长/字阶）+ 可访问性护栏 | **界面唯一允许读取尺寸的来源**；触摸目标 ≥44；文字缩放夹紧 0.85–2.0；减少动效归零 |
| `theme_pack.dart` | 644 | 三主题包（极客 VS Code / WinUI 3 / Material 3）+ `buildOgLTheme` | **唯一 `ThemeData` 编译处**；组件样式一律走 `ThemeExtension`；不硬编码 `Colors.`；`withAlpha` 而非新 API（跨版本稳定） |
| `icon_pack.dart` | 411 | 45 语义 × 3 套包（Material 线性 / 极简线性 / Material 实心） | `switch` 编译期强制齐全；**只实例化 `IconData`、不继承**（`final class` 约束） |

### 布局 / 应用 / 设置 / 权限

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `layout/adaptive.dart` | 480 | 自适应引擎（横竖屏 / 大小屏 / 平板 / 桌面 / DPI） | 断点 600/840/1200；**分栏数量严格服从布局结论**；发丝线 = 1 物理像素 |
| `app/async_state.dart` | 243 | 统一异步状态模型（idle/loading/ready/empty/failed）+ 控制器 | **并发抑制**；刷新失败**不丢数据**；失败**必带原因** |
| `app/shell.dart` | 468 | 主壳：导航四形态 + 单栏/列表详情/三栏 + 键盘操控 | 导航形态自动切换；**非列表页永远单栏**；键盘绑定可测试（`OgLKeyIntent`） |
| `app/og_l_app.dart` | 673 | `MaterialApp` 组装 + 外壳 + 启动失败页 | 启动被拒**不静默降级**（走专用失败页）；三页（概览/设置/诊断）零硬编码 |
| `settings/settings_model.dart` | 711 | 用户偏好 + 开发者/测试选项 | **容错反序列化**（坏数据回落默认并上报）；开发者选项受**总闸**约束 |
| `perm/permission_policy.dart` | 458 | 五平台权限策略矩阵（Android/iOS/Windows/Linux/macOS） | 每项权限**必有后果说明与设置路径**；策略是**纯数据**、不做平台调用 |
| `surface_bridge.dart` | 282 | L3 唯一出口 + 模块装配 | 只在 `surface.layer` 注册一次；`surfaceLayerModules()` 是装配入口 |

### 入口

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `main.dart` | 90 | 组装 L0–L3 → 内核 `boot()` → 交付 `KernelReport` | **不静默降级**：引导被拒展示原因；引导清单由代码生成（零外部资源） |

---

## 测试（15 文件 / 6,089 行 / 322 项）

| 文件 | 行 | 覆盖重点 |
| --- | ---: | --- |
| `test/kernel/kernel_test.dart` | 704 | 规范化 JSON、Ed25519 防篡改、目录指纹、五阶段引导、信任策略、DI、桥、总线拓扑/环、生命周期回滚、端到端 |
| `test/kernel/environment_test.dart` | 151 | 自检注册/封存/超时/单项失败隔离 |
| `test/base/cache_consistency_test.dart` | 614 | **D1–D7 逐条** + 作用域隔离 + 完整性 + 有界淘汰 + 键安全 |
| `test/base/chaos_test.dart` | 366 | **破坏性测试**：崩溃/磁盘满/撕裂写/并发风暴/模糊；"要么成功，要么可解释地失败" |
| `test/base/durability_test.dart` | 353 | **D8–D10**：提交日志（含重放不降标准）、草稿、三方信息与处置建议 |
| `test/base/net_test.dart` | 419 | 退避分支、镜像改写、韧性编排、**幂等铁律**、观测、多通道回落不吃重试预算 |
| `test/base/net_dns_test.dart` | 443 | 五家内置、RFC 1035 编解码（字节级）、事务 ID 防伪造、DoH 解析、TTL、竞速、回退留痕 |
| `test/base/platform_io_test.dart` | 218 | **原子写**、启动清扫、路径安全、KV 摘要键、坏数据不污染 |
| `test/domain/gh_test.dart` | 395 | 容错解析、`truncated`、`>1MB`、Link 解析、令牌安全与存取顺序 |
| `test/domain/gh_client_test.dart` | 515 | 认证头、**限流避让**、错误映射、分页、批量提交顺序、**CacheRemote 适配** |
| `test/domain/sys_test.dart` | 393 | meminfo 解析、采集失败降级、能力清单覆盖、授权/撤销/持久化、**按授权裁剪**、并发串行化 |
| `test/domain/ix_test.dart` | 570 | 会话持久化、**批量必追问**、通道顺序与落地、取消、冲突文案与选项顺序、通知去重 |
| `test/surface/surface_foundation_test.dart` | 319 | 令牌/断点/发丝线/图标齐全性/主题包令牌完整性 |
| `test/surface/surface_settings_test.dart` | 449 | 设置容错、开发者总闸、权限矩阵完整性、后果说明与设置路径 |
| `test/surface/ui_screenshot_test.dart` | 180 | **渲染快照**：3 主题 × 4 形态 = 12 张真实 PNG（CI 产物 `ui-shots`） |

> 全部测试**离线可跑**：外部依赖一律通过注入点（`ScriptedTransport` / 探针函数 / 内存存储）替换。
> 渲染快照的图像编码**必须**放在 `tester.runAsync()` 内（FakeAsync 下光栅线程永不返回 —— 踩过坑，勿回退）。

---

## 改动前自检清单

1. 我改的文件，**上表对应行的不变量**是否还成立？
2. 是否新增了跨层 `import`（除接口类型外）？
3. 是否触碰缓存/仓库读写？→ 逐条对照 [CONSISTENCY.md](CONSISTENCY.md)。
4. 是否触碰提交/编辑状态？→ 对照 [DURABILITY.md](DURABILITY.md)。
5. 是否触碰模块装载/扩展？→ 对照 [BOOT.md](BOOT.md)。
6. 是否触碰界面（尺寸/颜色/布局/图标）？→ 对照 [SURFACE.md](SURFACE.md)。
7. 新能力是否回填 [FEATURES.md](FEATURES.md) 与 [ROADMAP.md](ROADMAP.md)？