# OhGithubLost（OGL）— 架构设计 v3.1

> 第三稿：新增「总线（Kernel）」+「每层桥（Bridge）」；缓存一致性升级为独立协议
> v3.1：新增「启动层（BootLoader）」与信任策略（BL 锁 / 主题不设限 / Mod 总线警告）
> 配套文档：[CONSISTENCY.md](CONSISTENCY.md)（一致性协议）· [BOOT.md](BOOT.md)（启动层）· [STANDARDS.md](STANDARDS.md)（规范与自审）

---

## 0. 完整骨架

```
┌──────────────────────────────────────────────────────────────┐
│ 总线段 KERNEL（底座的底座）                                   │
│ BootLoader 校验序列 · 模块引入 · 依赖注入 · 生命周期 · 桥发现   │
└──────────────────────────────────────────────────────────────┘
        ▲ 全层注册于此
┌──────────────────────────────────────────────────────────────┐
│ 底座层 BASE                                                  │
│ 网络连接 net  ‖平行‖ 硬盘逻辑 disk                            │
│   └─ base_bridge（底座桥：层内接线 + 对外唯一出口）            │
├──────────────────────────────────────────────────────────────┤
│ 中枢层 DOMAIN                                                │
│ API逻辑 api  +  交互逻辑 interaction                          │
│   └─ domain_bridge（中枢桥）                                  │
├──────────────────────────────────────────────────────────────┤
│ 消费层 SURFACE                                               │
│ UI + Mod + 主题包 + 其他模块                                  │
│   └─ surface_bridge（消费桥）                                 │
└──────────────────────────────────────────────────────────────┘
```

## 1. 总线段（Kernel）——底座的底座

> 定位：**只做"引导、引入与治理"**，不做业务、不碰网络与磁盘。

| 能力 | 职责 |
|---|---|
| 启动层 boot | **BootLoader 校验序列**：引导清单校验 → 逐层模块指纹校验（BL 锁）→ 扩展装载策略（主题不设限 / Mod 总线警告）→ 就绪上报。详见 [BOOT.md](BOOT.md) |
| 模块引入 module_bus | 模块清单注册、导入顺序编排、依赖声明（requires / provides） |
| 依赖容器 di | 类型化服务注册与解析（`register<T>()` / `resolve<T>()`），禁用全局单例乱用 |
| 生命周期 lifecycle | 按依赖拓扑排序初始化；初始化失败回滚；退出时逆序释放 |
| 桥注册与发现 bridge_registry | 三层桥统一注册；**跨层只能解析到桥，拿不到对方内部实现** |
| 启动诊断 diagnostics | 依赖图导出、启动耗时、模块健康状态（商业级可观测性） |

**设计红线**：
- 除 Kernel 自身外，任何模块不得自行 `new` 其他层的实现；
- Kernel 不提供"事件总线"语义（跨层通信走桥接口 + 交互层状态广播），避免隐性耦合。

## 2. 桥（Bridge）——每层一座，层内接线 + 层间唯一通道

每一层都有一个**桥模块**，它是该层唯一"知道全部实现"的地方：

| 桥 | 层内职责（对接本层所有模块） | 层间职责（与其他层桥对接） |
|---|---|---|
| base_bridge | 装配 net 与 disk（两者互相不知道彼此，由桥接线） | 对中枢暴露底座统一接口 |
| domain_bridge | 装配 api 与 interaction（同层协作也走桥注入） | 对下依赖 base_bridge，对上暴露中枢接口 |
| surface_bridge | 装配 ui / mods / themes，注册扩展点 | 只依赖 domain_bridge |

**桥的四条铁律**：
1. **唯一出入口**：跨层引用只允许 import 对方 **bridge**，禁止 import 内部实现；
2. **契约稳定**：桥的接口是稳定面，层内实现可自由重构；
3. **装配者不做事**：桥只负责接线、转发、契约适配，不承载业务逻辑；
4. **测试缝**：桥是单元测试与 Mock 的唯一切入点。

## 3. 分层与模块职责

### 底座层 BASE
- **网络连接 net**：传输引擎（池化 / 超时 / 取消 / 并发闸 / 退避重试 / 流式传输）、镜像通道（代理节点、测速、优选，**仅白名单下载域**）、传输观测（限流头 / 统计）、传输错误分类
- **硬盘逻辑 disk**（重点：缓存）：目录规划、KV 存储、安全保险库、**缓存介质（含一致性元数据）**、文件操作（哈希 / ZIP）、平台 IO 桥
- 详见 [CONSISTENCY.md](CONSISTENCY.md)

### 中枢层 DOMAIN
- **API 逻辑 api**：GitHub 领域语义、模型、**冲突治理 conflict_guard**、分页、缓存策略 cache_policy
- **交互逻辑 interaction**：会话、控制器群、命令层、任务系统、扩展点注册表、状态广播

### 消费层 SURFACE
- **UI**：设计系统（VSCode 极简 / 毛玻璃 × 明暗）、组件库、自适应断点布局
- **Mod**：声明式 JSON（无代码执行），经扩展点注册；**装载时总线警告**
- **主题包**：JSON 白名单 + extra 冗余，向前向后兼容；**信任不设限制**

## 4. 目录分布

```
lib/
├─ kernel/                        # 总线段（底座的底座）
│  ├─ module_bus.dart             # 模块引入 / 依赖解析
│  ├─ di.dart                     # 类型化依赖容器
│  ├─ lifecycle.dart              # 初始化 / 释放编排
│  ├─ bridge_registry.dart        # 桥注册与发现
│  ├─ diagnostics.dart            # 依赖图 / 启动诊断
│  └─ boot/                       # 启动层
│     ├─ boot_loader.dart         # 启动序列编排
│     ├─ trust_policy.dart        # 信任分级（locked / warn / open）
│     ├─ integrity_verifier.dart  # 签名 / 指纹校验
│     └─ trust_warnings.dart      # 总线警告
├─ base/                          # 底座层
│  ├─ net/                        # 网络连接
│  │  ├─ net_engine.dart
│  │  ├─ mirror_channel.dart
│  │  ├─ net_metrics.dart
│  │  └─ net_types.dart
│  ├─ disk/                       # 硬盘逻辑
│  │  ├─ paths.dart
│  │  ├─ kv_store.dart
│  │  ├─ secret_vault.dart
│  │  ├─ blob_cache.dart          # 缓存介质（一致性元数据）
│  │  ├─ file_ops.dart
│  │  └─ platform_io.dart
│  └─ base_bridge.dart            # 底座桥
├─ domain/                        # 中枢层
│  ├─ api/                        # API 逻辑
│  │  ├─ github_api.dart
│  │  ├─ gh_models.dart
│  │  ├─ conflict_guard.dart
│  │  ├─ paging.dart
│  │  └─ cache_policy.dart
│  ├─ interaction/                # 交互逻辑
│  │  ├─ session.dart
│  │  ├─ controllers/
│  │  ├─ commands/
│  │  ├─ tasks/
│  │  ├─ extension_registry.dart
│  │  └─ bus.dart
│  └─ domain_bridge.dart          # 中枢桥
└─ surface/                       # 消费层
   ├─ ui/                         # design / kit / pages
   ├─ mods/                       # Mod 系统
   ├─ themes/                     # 主题包
   └─ surface_bridge.dart         # 消费桥
```

## 5. 依赖规则（可用 lint / 脚本强制检查）

| 允许 | 禁止 |
|---|---|
| 任意模块 → kernel（注册自身） | 模块 → 其他层内部实现 |
| domain.api → base_bridge | base → domain / surface（反向依赖） |
| domain.interaction → domain_bridge（含 api 注入）+ base_bridge | net ↔ disk 直接互调（必须经 base_bridge） |
| surface.* → domain_bridge | UI 直接发请求 / 直接读写令牌 |
| 任意模块 → 纯类型 / 模型 / 常量（值对象豁免） | 跨层自行 `new` 对方实现 |

## 6. 关键数据流

```
启动：BootLoader → 清单校验 → 逐层模块校验（BL 锁）→ 扩展装载（主题不设限 / Mod 总线警告）→ 就绪上报
读  ：UI → 交互(命令) → domain_bridge → api(策略) → base_bridge → net/disk(缓存) → 回填
写  ：UI → 交互(任务队列) → api(conflict_guard) → net → 写后失效 + 回读 → 状态更新 → UI 刷新
挂载：Mod / 主题包 → disk → 交互(校验 + 注册) → 即时生效
更新：交互(更新控制器) → net(多镜像) → schema 校验 → 提示
```

## 7. 里程碑（节奏由你定）

- M0 架构冻结（本次评审）
- M1 总线 + 启动层（BootLoader 校验与信任策略）+ 底座（net/disk，含一致性协议与测试）
- M2 中枢（api 冲突治理 + interaction 控制器 / 任务）
- M3 UI 最小闭环
- M4 Mod / 主题包生态

---
*v3.1 · 变更依据：用户评审（总线 / 每层桥 / 缓存一致性致命级 / 启动层 BL 锁与信任策略）+ 商业级自审*