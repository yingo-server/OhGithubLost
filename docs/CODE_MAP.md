# OGL 代码地图（CODE_MAP）

> 用途：**上手导航 + 改动前必读**。
> 每行给出：文件 · 行数 · 职责 · **该文件不可违背的不变量**。
> 不变量写错 = 数据事故（见 [CONSISTENCY.md](CONSISTENCY.md) / [DURABILITY.md](DURABILITY.md)）。

统计口径：`lib/` 40 文件 / 12,679 行；`test/` 11 文件 / 4,647 行；合计 **17,326 行**。

---

## 依赖规则（先看这个）

```
kernel（L0，零依赖）
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

## L1 · 底座级（15 文件 / 4,485 行）

### 网络连接（`lib/base/net/`）

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `net_types.dart` | 308 | 请求/响应/异常分类/观测类型 | 传输实现的异常**必须翻译成 `NetException`**；`NetObserver` 只记账不决策 |
| `net_retry.dart` | 92 | 退避策略（纯函数） | **不发请求、不持状态**；`Retry-After` 优先但受 `maxDelay` 约束 |
| `net_mirror.dart` | 153 | 镜像通道选择 | 通道**默认关闭**；`apply()` 不匹配返回 `null`（不抛） |
| `net_transport.dart` | 193 | 韧性传输（重试+镜像+观测） | **非幂等方法绝不重试**；**重试耗尽必须显式抛错**（不得把 5xx 当正常响应） |
| `dio_net_transport.dart` | 263 | Dio 翻译层 | 只做异常翻译，**不做策略**；覆盖 `DioExceptionType` 全部分支 |
| `net_dns.dart` | 797 | DNS 策略（系统/自定义 + DoH + UDP） | **事务 ID 不匹配必须拒绝**；回退系统解析 **必留痕**；`system` 模式行为必须与不加 DNS 一致 |
| `net_bridge.dart` | 148 | 网络门面 + 模块 | 策略必须**可见**（`dnsSummary`）；注册 DNS 自检项 |

### 硬盘逻辑（`lib/base/disk/`）

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `disk_store.dart` | 188 | KV / 保险库 / 文件 / 路径原语 | 接口与内存实现**语义一致**；`InMemoryFileStore.normalize` 是路径归一化的唯一真源 |
| `disk_types.dart` | 500 | 缓存键/条目/写意图/结果/三方/处置建议 | 作用域四元组**不可缺维**；路径**拒绝 `..`**；`staleSha` 的处置建议**必含 `viewDiff`** |
| `disk_cache.dart` | 745 | 一致性引擎 D1–D10 | **write 永不外抛**；**读写都进逐键锁**；缺基线不写；**无 rebase 不自动覆盖**；写后必回读；**force 也需二次确认**；内容**len+SHA-256 校验** |
| `disk_journal.dart` | 314 | 提交日志（D8） | **写前落盘**；重放**不降标准、不重复入队**；语义冲突标 abandoned 不自动重放 |
| `disk_draft.dart` | 200 | 草稿（D9） | 先落盘后展示；**提交成功必须清草稿** |
| `disk_bridge.dart` | 159 | 硬盘门面 + 模块 | 三处接线（诊断/日志/草稿）**一个都不能省** |
| `platform_io.dart` | 353 | 真实持久化 | **原子写**（tmp→flush→rename）；启动清扫 `.tmp`；KV 文件名用摘要；路径不得逃出根目录 |

### 层桥

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `base_bridge.dart` | 72 | L1 唯一出口 + 装配 | 桥只在 `base.layer` 注册一次；`baseLayerModules()` 顺序 = sys 无关（net/disk 无依赖） |

---

## L2 · 中枢级（11 文件 / 5,393 行）

| 文件 | 行 | 职责 | 不变量 |
| --- | ---: | --- | --- |
| `gh/gh_models.dart` | 948 | 领域模型 + 容错解析 | **缺字段不得崩**；`raw` 必须保留；`truncated` 必须暴露；`>1 MB` 必须识别 |
| `gh/gh_auth.dart` | 298 | 多账号 + 令牌 | 令牌**只在保险库**；`toString` **只出脱敏**；删除顺序 = 先密文后元数据 |
| `gh/gh_client.dart` | 502 | 请求构造/限流/并发/分页/错误映射 | **额度耗尽不发请求**；分页**必须有安全上限**；409/422 仅在显式要求时转冲突 |
| `gh/gh_api.dart` | 973 | 端点封装 + `CacheRemote` | `read` **拿不到内容返回 `null`**（绝不返回空串）；批量提交**先校验期望 sha**；`write` 必带基线 |
| `ix/ix_session.dart` | 342 | 会话上下文 + 偏好 | 状态**持久化且损坏自清**；目录置顶优先于排序方向 |
| `ix/ix_task.dart` | 425 | 批量任务编排 | **无确认不得开工**；**通道切换先于第一个请求**；单项失败不中断；**逐条汇报** |
| `ix/ix_conflict.dart` | 271 | 冲突 → 用户决策 | 选项顺序即推荐顺序；**危险项绝不排首位**；危险动作 `allowed` 必须 `confirmed` |
| `ix/ix_notify.dart` | 228 | 通知中心 | 同类**合并计数**；**安全告警不可关闭且不被淘汰** |
| `sys/sys_info.dart` | 572 | 本地深层信息 | **拿不到就说拿不到**（`source` 标注）；单项失败不拖垮整体 |
| `sys/sys_access.dart` | 466 | Mod 能力守门 | 公开能力**自动可用不留记录**；**未授权字段根本不出现**；越权必审计 |
| `domain_bridge.dart` | 368 | L2 唯一出口 + 四个模块 | **`cache.bindRemote(api)` 必须且只能在这里接** |

---

## 测试（11 文件 / 4,647 行 / 248 项）

| 文件 | 行 | 覆盖重点 |
| --- | ---: | --- |
| `test/kernel/kernel_test.dart` | 704 | 规范化 JSON、Ed25519 防篡改、目录指纹、五阶段引导、信任策略、DI、桥、总线拓扑/环、生命周期回滚、端到端 |
| `test/kernel/environment_test.dart` | 151 | 自检注册/封存/超时/单项失败隔离 |
| `test/base/cache_consistency_test.dart` | 614 | **D1–D7 逐条** + 作用域隔离 + 完整性 + 有界淘汰 + 键安全 |
| `test/base/durability_test.dart` | 353 | **D8–D10**：提交日志（含重放不降标准）、草稿、三方信息与处置建议 |
| `test/base/net_test.dart` | 375 | 退避分支、镜像改写、韧性编排、**幂等铁律**、观测 |
| `test/base/net_dns_test.dart` | 429 | 五家内置、RFC 1035 编解码（字节级）、事务 ID 防伪造、DoH 解析、TTL、竞速、回退留痕 |
| `test/base/platform_io_test.dart` | 218 | **原子写**、启动清扫、路径安全、KV 摘要键、坏数据不污染 |
| `test/domain/gh_test.dart` | 395 | 容错解析、`truncated`、`>1MB`、Link 解析、令牌安全与存取顺序 |
| `test/domain/gh_client_test.dart` | 513 | 认证头、**限流避让**、错误映射、分页、批量提交顺序、**CacheRemote 适配** |
| `test/domain/sys_test.dart` | 352 | meminfo 解析、采集失败降级、能力清单覆盖、授权/撤销/持久化、**按授权裁剪** |
| `test/domain/ix_test.dart` | 543 | 会话持久化、**批量必追问**、通道顺序、取消、冲突文案与选项顺序、通知去重 |

> 全部测试**离线可跑**：外部依赖一律通过注入点（`ScriptedTransport` / 探针函数 / 内存存储）替换。

---

## 改动前自检清单

1. 我改的文件，**上表对应行的不变量**是否还成立？
2. 是否新增了跨层 `import`（除接口类型外）？
3. 是否触碰缓存/仓库读写？→ 逐条对照 [CONSISTENCY.md](CONSISTENCY.md)。
4. 是否触碰提交/编辑状态？→ 对照 [DURABILITY.md](DURABILITY.md)。
5. 是否触碰模块装载/扩展？→ 对照 [BOOT.md](BOOT.md)。
6. 新能力是否回填 [FEATURES.md](FEATURES.md) 与 [ROADMAP.md](ROADMAP.md)？