# OGL 功能树（FEATURES）

> 状态：**L0 / L1 / L2 已完成；L3 UI v3（两主题 + OGL Kit + 客户端页面群）已落地**。
> CI：分析 + 测试全绿（`c2dbd711`）；构建：13/13 平台目标全绿（`efa7ed66`）。
> 本文只列**代码里真实存在**的能力，每一项都可追到源文件与测试。
> 未实现的部分集中在文末，**不粉饰**。

图例：✅ 已实现并有测试 ｜ ⚙️ 已实现但缺真机验收 ｜ ⏳ 未开始

---

## 一、L0 内核级（`lib/kernel/`，14 文件 / 2,801 行）

```
内核
├─ 模块契约                                    ✅ lib/kernel/contract/module.dart
│  ├─ 四层级 Kernel / base / domain / surface（稳定键）
│  ├─ 模块描述符：ID 规范 <layer>.<name>、版本、requires、provides
│  ├─ 模块状态机：registered → registering → started → ready → stopped / failed
│  └─ KernelContext：DI / 诊断 / 桥 / 信任告警 / 自检注册表
│
├─ 依赖容器（DI）                               ✅ lib/kernel/di.dart
│  ├─ 实例注册 + 惰性工厂（只创建一次）+ 标签（同类型多实例）
│  ├─ 重复注册拒绝（需显式 replace）
│  └─ 【封存】启动后 seal()，杜绝运行期偷偷注册
│
├─ 桥注册表                                     ✅ lib/kernel/bridge_registry.dart
│  ├─ 每层一座桥（重复注册拒绝）
│  ├─ 解析时类型断言（不匹配报错而不是静默 cast）
│  └─ 【封存】杜绝运行期加桥
│
├─ 模块总线                                     ✅ lib/kernel/module_bus.dart
│  ├─ 注册 / ID 去重 / 能力唯一性校验
│  ├─ 依赖拓扑排序（依赖先启动）
│  ├─ 环检测 / 依赖缺失检测 / 描述符合法性校验
│  └─ 依赖图文本导出（进启动报告）
│
├─ 生命周期编排                                 ✅ lib/kernel/lifecycle.dart
│  ├─ 拓扑顺序启动 / 逆序停止 / 幂等
│  └─ 【失败回滚】启动失败时已启动模块逆序回滚
│
├─ 诊断中枢                                     ✅ lib/kernel/diagnostics.dart
│  ├─ 五级日志（trace/debug 受 verbose 控制）
│  ├─ 环形缓冲（容量上限）+ 结构化事件码 + JSON 序列化
│  ├─ 多 sink 分发（sink 抛异常记录在案，不静默吞）
│  └─ 阶段耗时 / 模块状态 / 错误计数
│
├─ 环境自检扩展点                               ✅ lib/kernel/environment.dart
│  ├─ 内核不认识 DNS/代理/存储——只提供槽位
│  ├─ 注册 / 封存 / 单项超时 / 【单项失败不阻断其余】
│  └─ OgLKernel.runProbes() 结果写诊断（OGL-PROBE-001/101）
│
└─ 启动层（BootLoader）                         ✅ lib/kernel/boot/
   ├─ 五阶段：Stage0 自检 → Stage1 清单签名 → Stage2 模块指纹
   │           → Stage3 扩展信任策略 → Stage4 就绪上报
   ├─ 引导清单：canonical JSON + Ed25519 签名校验
   ├─ 目录指纹：文件集合 + 内容摘要汇总（SHA-256）
   ├─ 信任策略：官方核心 locked + 强制签名 / 第三方主题不设限 / Mod 放行但强制告警
   ├─ 信任告警收集（含 UI 弹窗强制条款，见 BOOT.md）
   └─ 安全模式：官方模块校验失败 → 排除该模块而非整体拒绝启动
```

---

## 二、L1 底座级（`lib/base/`，15 文件 / 4,485 行）

### 2.1 网络连接（`base/net/`）

```
网络连接
├─ 类型系统                                     ✅ net_types.dart
│  ├─ NetMethod / NetErrorKind / NetException（统一错误翻译目标）
│  ├─ NetRequest（不可变 + copyWith）/ NetResponse（含 etag）
│  └─ NetObserver / NetStats（请求/失败/重试/镜像/字节/延迟）
│
├─ 重试策略                                     ✅ net_retry.dart
│  ├─ 指数退避 + ±ratio 抖动（随机源可注入 → 可确定性断言）
│  ├─ Retry-After 优先，但受本地上限约束
│  └─ 纯函数：不发请求、不持状态
│
├─ 幂等守卫                                     ✅ net_transport.dart
│  ├─ 默认只重试 GET / HEAD / PUT / DELETE
│  └─ POST / PATCH 【绝不自动重试】（防重复创建 Release）
│
├─ 镜像通道                                     ✅ net_mirror.dart
│  ├─ MirrorChannel（正则改写 URL）+ MirrorSelector（顺序挑选）
│  ├─ 【默认全部关闭】——加速域名属第三方信任边界
│  ├─ 批量启停 setAllEnabled / 限定 restrictTo（供批量任务切通道）
│  └─ 内置 ghproxy 通道（默认关闭）
│
├─ 韧性传输                                     ✅ net_transport.dart
│  ├─ 重试 + 镜像回落 + 观测三件事，与 HTTP 客户端解耦
│  ├─ 非幂等请求不重试也不切镜像
│  └─ 【失败显式】：重试耗尽抛 NetException（带状态码 + 响应体片段）
│
├─ 真实传输                                     ⚙️ dio_net_transport.dart
│  ├─ Dio 异常 → NetException 翻译（超时/TLS/取消/连接/限流/未知）
│  ├─ 非穷尽 switch 覆盖 DioExceptionType 全部分支
│  └─ 注入 DnsService 时接管 connectionFactory
│
├─ DNS 策略                                     ⚙️ net_dns.dart
│  ├─ 模式：system（默认，行为与不加 DNS 一致）/ custom
│  ├─ 内置五家：阿里 223.5.5.5 · 腾讯 119.29.29.29 · 114.114.114.114
│  │            · Cloudflare 1.1.1.1 · Google 8.8.8.8
│  ├─ DoH（注入式 HTTP，不引新依赖）+ 明文 UDP（RFC 1035 自实现）
│  ├─ 报文编解码纯函数 + 【事务 ID 校验】（防伪造响应）
│  ├─ TTL 缓存 + 条目上限 + 并发竞速 + 顺序回退
│  ├─ 全部失败 → 回退系统解析，但【必记 warn OGL-DNS-101】（绝不静默）
│  └─ 连接层：代理优先 / system 模式=平台默认 / custom 才换 IP（SNI 不变）
│
└─ 门面与模块                                   ✅ net_bridge.dart
   ├─ NetBridge：send / get / stats / dnsSummary（策略必须可见）
   └─ NetModule：装配 + 注册 DNS 自检项到内核
```

### 2.2 硬盘逻辑（`base/disk/`）

```
硬盘逻辑
├─ 存储原语                                     ✅ disk_store.dart
│  ├─ DiskKv / DiskVault / DiskFileStore / DiskPaths（接口 + 内存实现）
│  └─ 内存实现让上层逻辑可在 CI 完全离线断言
│
├─ 缓存一致性 D1–D7                             ✅ disk_cache.dart
│  ├─ 作用域四元组 schemaVersion|accountId|repo|branch|path
│  ├─ D1 写前必读   ：缺 baseSha 直接拒绝（requiresRead）
│  ├─ D2 SHA 乐观锁 ：基线≠远端 → staleSha（并回传远端最新）
│  ├─ D3 冲突重试   ：仅在有 rebase 时按上限重试；无 rebase 绝不自动覆盖
│  ├─ D4 串行化     ：逐键互斥，【读写都进锁】
│  ├─ D5 失效+回读  ：写后强制回读校验（带少量重试抵御瞬时陈旧）
│  ├─ D6 失败可感知 ：返回结果 + 审计日志双通道，【永不外抛】
│  ├─ D7 二次确认   ：dangerous 【或 force】未确认 → needsConfirmation
│  ├─ 完整性：索引存 len + SHA-256，读取校验，损坏即丢弃（OGL-CONS-208）
│  ├─ 有界：TTL + 条目上限 + prune() / purge()
│  └─ 键安全：作用域禁含分隔符；路径拒绝绝对/穿越/反斜杠
│
├─ 持久性 D8–D10                                ✅ disk_journal.dart / disk_draft.dart / disk_types.dart
│  ├─ D8 提交日志：写前落盘 → 成功移除 / 可重试失败保留 / 语义冲突放弃
│  │             重放【完整重走 D1–D7】，且不重复入队
│  ├─ D9 草稿    ：编辑先落盘；提交成功自动清草稿
│  └─ D10 冲突可解释：ConflictThreeWay(base/remote/local/diverged)
│                    + ConflictAction 处置建议（staleSha 必含 viewDiff）
│
├─ 门面与模块                                   ✅ disk_bridge.dart
│  ├─ DiskBridge：kv / vault / files / paths / cache / journal / drafts
│  └─ DiskModule：三处接线（诊断 / 提交日志 / 草稿）一个都不能省
│
└─ 真实持久化                                   ⚙️ platform_io.dart
   ├─ 原子写：tmp → flush(fsync) → rename（掉电不留半截文件）
   ├─ 启动清扫：残留 *.tmp 一律删除
   ├─ IoDiskKv：文件名 = sha256(键)，内容存原键（防路径越界 + 可反查）
   ├─ 安全保险库：Keystore / DPAPI / libsecret
   └─ PlatformStorage.open()：一次解析根目录并装配整层
```

### 2.3 底座层桥

```
底座桥                                          ✅ base_bridge.dart
├─ BaseBridge：net + disk 合成 L1 唯一出口
├─ BaseLayerModule（base.layer）：requires base.net / base.disk
└─ baseLayerModules()：一行接入
```

---

## 三、L2 中枢级（`lib/domain/`，11 文件 / 5,393 行）

### 3.1 API 逻辑（`domain/gh/`）

```
GitHub API
├─ 领域模型                                     ✅ gh_models.dart
│  ├─ GhUser / GhRepo / GhBranch / GhTreeEntry / GhTree / GhContent
│  │   / GhRelease / GhAsset / GhCommit / GhPage
│  ├─ 容错解析：缺字段默认 / 类型漂移（"7"与 7）/ 未知枚举 → unknown
│  ├─ raw 保留：GitHub 加字段无需改模型（Mod 可直接取）
│  ├─ GhTree.truncated 【一等公民】（大仓库会被服务端静默截断）
│  ├─ GhContent.isTooLarge（Contents API 对 >1 MB 省略内容）
│  └─ GhPage：Link 头解析（容忍 `rel="next"` 与 `rel = "next"`）
│
├─ 认证                                         ✅ gh_auth.dart
│  ├─ 多账号：元数据在 KV、令牌在保险库【分开存】
│  ├─ GhToken：toString 只出脱敏形态（ghp_****1234）
│  ├─ 切换前校验令牌存在（防"登录了却处处 401"）
│  └─ 删除顺序：先删密文再删元数据（防"看不见但还在"的令牌）
│
├─ 请求客户端                                   ✅ gh_client.dart
│  ├─ 认证头注入 / API 版本头
│  ├─ 限流避让：【已知额度耗尽不再发请求】
│  ├─ 并发闸门（Semaphore，默认 4）
│  ├─ 分页：Link 驱动 + 安全上限（默认 10 页，防烧光额度）
│  └─ 错误映射：401 / 403(主限流·次限流·权限) / 404 / 409·422 / 其他
│
└─ 端点封装                                     ✅ gh_api.dart
   ├─ 仓库：我的/星标/他人/组织/详情/新建/改设置/删除/复刻/加星
   ├─ 分支：列表/创建（指定起点）/重命名/删除
   ├─ 内容：树（recursive）/读/列目录/大文件 Blobs/写（带基线 sha）/删除
   ├─ 批量提交：blob → tree(base_tree) → commit → ref【原子】
   ├─ 历史：commits / compare
   ├─ Releases：列表/创建/删除
   ├─ 搜索：仓库 / 代码（服务端）
   ├─ Pages：查询/启用/停用 / CNAME 读写
   ├─ Issues / PR / PR 文件 / Gist / Actions / 标签 / README
   └─ ★ CacheRemote 实现：read（含 >1MB 走 Blobs）/ write（带 sha）
```

### 3.2 交互逻辑（`domain/ix/`）

```
交互
├─ 会话                                         ✅ ix_session.dart
│  ├─ 上下文：仓库 / 分支 / 路径 / 面包屑
│  ├─ 偏好：视图（列表·网格）/ 排序（名称·大小·时间）/ 方向 / 文件夹置顶
│  ├─ 搜索历史（去重 + 上限 20）
│  ├─ 全部持久化，启动 restore()，损坏自清
│  └─ sortEntries()：目录置顶优先于排序方向
│
├─ 批量任务                                     ✅ ix_task.dart
│  ├─ 【类型级强制】run() 无 IxBatchDecision → 抛 IxConfirmationRequired
│  ├─ IxBatchPlan：条数/仓库/分支/预计请求数/体积/是否破坏性/样本
│  ├─ IxChannel：direct / auto / mirror（【通道在第一个请求前生效】）
│  ├─ 可取消；单项失败不中断整批；【逐条结果】成功/跳过/失败+原因
│  └─ 运行中不允许再开一批
│
├─ 冲突编排                                     ✅ ix_conflict.dart
│  ├─ WriteOutcome → IxConflictPrompt（标题 + 人话 + 三方预览 + 选项）
│  ├─ 选项顺序即推荐顺序；staleSha 必为 viewDiff → pullRemote → forceOverwrite
│  ├─ 危险项标 destructive 且【绝不排首位】
│  └─ IxConflictResolution.allowed：危险动作必须 confirmed
│
└─ 通知中心                                     ✅ ix_notify.dart
   ├─ 同 ID 合并计数（不堆叠）+ 被抑制计数可见
   ├─ 三级：info / warning / danger
   ├─ 【安全告警不可关闭】，超限时优先淘汰可关闭项
   ├─ 从内核诊断导入（只收 warn/error + 支持水位）
   └─ dismiss / clearDismissible / wasDismissed
```

### 3.3 本地深层信息（`domain/sys/`）

```
本地信息
├─ 深层信息                                     ✅ sys_info.dart
│  ├─ 设备：平台/系统版本/区域/CPU 核数（dart:io）+ 机型/厂商（插件，可注入）
│  ├─ 应用：名称/包名/版本/构建号（插件）+ 安装 ID（敏感）
│  ├─ 运行环境：区域/时区/UTC 偏移（纯 dart:io）
│  ├─ 内存：/proc/meminfo 解析（纯函数可离线断言）
│  ├─ 网络策略：DNS 模式与摘要 / 启用通道 / 请求·失败·重试统计
│  ├─ 【拿不到就说拿不到】：每项带 source，失败返回 null 不编值
│  └─ 单项采集失败不拖垮整体（留痕 OGL-SYS-101/102/103）
│
└─ 能力守门（供 Mod）                           ✅ sys_access.dart
   ├─ 能力清单：deviceBasic / deviceHardware / appBasic / appInstallId
   │            / runtime / memory / network / fileSystem
   ├─ 公开能力（deviceBasic·appBasic·runtime）自动可用，不留记录
   ├─ 授权 / 撤销 / 按 Mod 全撤 / 持久化（重启仍有效）
   ├─ require() 越权 → SysAccessDenied + 审计（OGL-SYSACC-101）
   ├─ sliceFor()：【未授权字段根本不出现】（不是返回 null）
   └─ describeRequest()：给用户看的授权说明，标出敏感项
```

### 3.4 中枢桥

```
中枢桥                                          ✅ domain_bridge.dart
├─ DomainBridge：auth / api / client / session / tasks / notifications
│                / sysInfo / sysAccess
├─ GhModule（domain.gh）：
│   └─ ★ base.disk.cache.bindRemote(api) —— D1–D10 落到真实 GitHub
├─ SysModule（domain.sys）：装配信息与守门 + 注册环境自检项
├─ IxModule（domain.ix）：会话/任务/通知；onStart 恢复会话
└─ DomainLayerModule（domain.layer）：注册 'domain' 桥
```

---

## 四、工程设施

```
工程
├─ CI                                           ✅ .github/workflows/ci.yml
│  ├─ flutter analyze --fatal-infos --fatal-warnings（警告即失败）
│  └─ flutter test
├─ 构建与发布                                   ✅ .github/workflows/build.yml
│  ├─ 13 个"平台 × 架构"目标（best-effort 分级，失败不拦主线）
│  └─ 一键发布 → 自动 GitHub Release（见 docs/RELEASE.md）
├─ 增量推送                                     ✅ _setup/push_batch.py
│  ├─ 比对远端 tree 的 blob sha，只传变更
│  ├─ base_tree 增量提交 + 删除项（sha: null）
│  └─ 网络抖动重试（HTTP 4xx/5xx 不重试）
├─ 测试                                         ✅ 16 文件 / 6,293 行 / 330+ 项（含渲染快照）
└─ 文档                                         ✅ 15 份（见 docs/README.md）
```

---

## 五、尚未实现（诚实清单）

| # | 项目 | 状态 |
| --- | --- | --- |
| 1 | **Mod 运行时 + 强制告警弹窗**（红线；主题 / UI / Kit / 页面群已落地） | ⏳ |
| 2 | **Phase E**：UI 三项打磨（动效 / 性能 / 代码之美） | ⏳ 未开始 |
| 3 | **真机探针装配**：`AndroidProbe` / `AppProbe` 接 `device_info_plus` / `package_info_plus` | ⏳ 未接线 |
| 4 | **通道并发测速与记忆**（老项目有，我们目前只做顺序回退） | ⏳ |
| 5 | **代理源远端订阅**（需显式授权 + 来源提示） | ⏳ |
| 6 | **OAuth Device Flow**（需外部 OAuth App） | ⏳ 按决策暂不做 |
| 7 | **内核功能全量接线**（通知中心 / Mod 门 / 诊断 → UI） | ⏳ |
| 8 | **权限网关五平台实现**（接口已定） | ⏳ |
| 9 | **`PlatformStorage` / `SecureDiskVault` 的真机验收**（CI 无法覆盖） | ⚙️ 待真机 |
| 10 | **快照矩阵扩展**（新页面 × 两主题） | ⏳ |

*本文与 `docs/ROADMAP.md` 同步维护：功能落地后勾掉，新增能力必须回填。*