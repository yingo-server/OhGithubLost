# OhGithubLost（OGL）— 架构设计 v3.2

> v3.1：新增「启动层（BootLoader）」与信任策略（BL 锁 / 主题不设限 / Mod 总线警告）。
> **v3.2（本版）：与实际实现全面对齐** —— 目录树、模块名、行数、进度全部按仓库现状校准；
> 旧版中残留的设计稿名称（`net_engine` / `blob_cache` / `github_api` 等）**在仓库中不存在，已全部废弃**。
> 配套文档：[CONSISTENCY.md](CONSISTENCY.md) · [BOOT.md](BOOT.md) · [SURFACE.md](SURFACE.md) · [STANDARDS.md](STANDARDS.md)

---

## 0. 完整骨架（现状）

```
┌────────────────────────────────────────────────────────────────────┐
│ 总线段 KERNEL（底座的底座，零业务依赖）                              │
│ BootLoader 五阶段校验 · 模块总线 · DI · 生命周期 · 桥注册 · 诊断 ·    │
│ 环境自检扩展点                                                      │
└────────────────────────────────────────────────────────────────────┘
        ▲ 全层注册于此（OgLModule）
┌────────────────────────────────────────────────────────────────────┐
│ 底座层 BASE（L1）                                                   │
│ 网络连接 net ‖平行‖ 硬盘逻辑 disk（缓存一致性 D1–D10）              │
│   └─ base.layer（base_bridge）：层内接线 + 对外唯一出口             │
├────────────────────────────────────────────────────────────────────┤
│ 中枢层 DOMAIN（L2）                                                 │
│ GitHub 领域 gh ＋ 交互逻辑 ix ＋ 系统能力 sys                       │
│   └─ domain.layer（domain_bridge）：层内接线 + 对外唯一出口         │
├────────────────────────────────────────────────────────────────────┤
│ 消费层 SURFACE（L3）                                                │
│ 主题体系 · 自适应布局 · 主壳 · 设置 · 权限策略 · 异步状态           │
│   └─ surface.layer（surface_bridge）：层内接线 + 对外唯一出口       │
└────────────────────────────────────────────────────────────────────┘
```

## 1. 总线段（Kernel）—— 底座的底座

> 定位：**只做"引导、引入与治理"**，不做业务、不碰网络与磁盘。零第三方依赖（仅 `cryptography` 用于签名校验）。

| 能力 | 实施文件 | 职责 |
|---|---|---|
| 启动层 boot | `kernel/boot/`（6 文件） | 五阶段引导：清单 → 自检 → 签名 → 模块校验 → 扩展装载 → 就绪。详见 [BOOT.md](BOOT.md) |
| 模块引入 module_bus | `kernel/module_bus.dart` | 模块注册、拓扑排序、依赖校验、**环检测** |
| 依赖容器 di | `kernel/di.dart` | 类型化注册/解析；**封存后禁止注册** |
| 生命周期 lifecycle | `kernel/lifecycle.dart` | 拓扑序启动、逆序停止、**失败逆序回滚** |
| 桥注册与发现 bridge_registry | `kernel/bridge_registry.dart` | 每层一座桥；跨层只能解析到桥 |
| 启动诊断 diagnostics | `kernel/diagnostics.dart` | 有界环形日志、阶段耗时、模块健康 |
| 环境自检 environment | `kernel/environment.dart` | `KernelEnvironmentProbe` 注册表；**单项失败/超时不得阻断其余** |

**设计红线**：
- 除 Kernel 自身外，任何模块不得自行 `new` 其他层的实现；
- Kernel 不提供"事件总线"语义（跨层通信走桥接口），避免隐性耦合。

## 2. 桥（Bridge）—— 每层一座，层内接线 + 层间唯一通道

| 桥（模块 id） | 实施文件 | 层内职责 | 层间职责 |
|---|---|---|---|
| base.layer | `base/base_bridge.dart` | 装配 `base.net` / `base.disk` | 对中枢暴露底座统一接口 |
| domain.layer | `domain/domain_bridge.dart` | 装配 `domain.gh` / `domain.ix` / `domain.sys`；**唯一允许 `cache.bindRemote(api)` 的地方** | 对下依赖 base 桥，对上暴露中枢接口 |
| surface.layer | `surface/surface_bridge.dart` | 装配 theme / settings / perm / layout / app | 只依赖 domain 桥 |

**桥的四条铁律**：
1. **唯一出入口**：跨层引用只允许 import 对方 **bridge**，禁止 import 内部实现；
2. **契约稳定**：桥的接口是稳定面，层内实现可自由重构；
3. **装配者不做事**：桥只负责接线、转发、契约适配，不承载业务逻辑；
4. **测试缝**：桥是单元测试与 Mock 的唯一切入点。

## 3. 分层与模块职责（现状模块名）

### L1 底座 BASE
- **`base.net`（网络连接）**：`net_types`（请求/响应/异常分类/观测）· `net_retry`（退避，纯函数）· `net_mirror`（镜像通道，默认关闭）· `net_transport`（韧性编排：重试+镜像+观测，**幂等铁律**）· `dio_net_transport`（Dio 翻译层）· `net_dns`（DNS 策略：系统/自定义 + 五家内置 + DoH + RFC 1035 UDP，**回退必留痕**）· `net_bridge`
- **`base.disk`（硬盘逻辑）**：`disk_types` · `disk_store`（KV/保险库/文件原语）· `disk_cache`（**一致性引擎 D1–D10**）· `disk_journal`（提交日志，D8）· `disk_draft`（草稿，D9）· `platform_io`（真实持久化：**原子写 tmp→flush→rename**、启动清扫、摘要键 KV）· `disk_bridge`
- 详见 [CONSISTENCY.md](CONSISTENCY.md) / [DURABILITY.md](DURABILITY.md)

### L2 中枢 DOMAIN
- **`domain.gh`（GitHub 领域）**：`gh_models`（容错解析：`truncated` / `>1 MB` 识别）· `gh_auth`（多账号 + 令牌**只进保险库**）· `gh_client`（限流避让 / 并发闸 / 分页安全上限 / 错误映射）· `gh_api`（端点封装 + `CacheRemote` 适配）
- **`domain.ix`（交互逻辑）**：`ix_session`（会话与偏好，持久化且损坏自清）· `ix_task`（批量任务：**无确认不得开工** + 通道选择 + 可取消 + 逐条汇报）· `ix_conflict`（冲突→用户决策，**危险项绝不排首位**）· `ix_notify`（通知中心，安全告警不可关闭）
- **`domain.sys`（系统能力）**：`sys_info`（本地深层信息，**采集器可注入**、拿不到就说拿不到）· `sys_access`（Mod 能力守门：**未授权字段根本不出现**、越权必审计）

### L3 消费 SURFACE
- **主题体系**：`design_tokens`（令牌 = 界面唯一尺寸来源）· `theme_pack`（三主题：极客 VS Code / WinUI 3 / Material 3；唯一 `ThemeData` 编译处）· `icon_pack`（45 语义 × 3 套包，`switch` 编译期强制齐全）
- **布局与交互**：`adaptive`（断点 600/840/1200、DPI、发丝线 1 物理像素、安全区/键盘）· `shell`（导航四形态 + 单栏/列表详情/三栏 + 键盘操控）· `async_state`（四态 + 并发抑制 + 刷新失败不丢数据）
- **设置与权限**：`settings_model`（用户偏好 + 开发者/测试选项，总闸护栏）· `permission_policy`（五平台权限策略矩阵 + 设置路径 + 状态快照）
- **Mod 运行时**：**尚未实现**（设计中，红线：装载必须产生强制告警弹窗）

## 4. 目录分布（= 仓库现状，51 文件 / 17,681 行）

```
lib/
├─ main.dart                          # 应用入口（组装 L0–L3 → 内核启动 → KernelReport）
├─ kernel/                            # 总线段（14 文件 / 2,801 行）
│  ├─ kernel.dart · module_bus.dart · di.dart · lifecycle.dart
│  ├─ bridge_registry.dart · diagnostics.dart · environment.dart
│  ├─ contract/module.dart
│  └─ boot/  boot_loader · boot_manifest · boot_fs · integrity_verifier
│            · trust_policy · trust_warnings
├─ base/                              # 底座层（15 文件 / 4,600 行）
│  ├─ base_bridge.dart
│  ├─ net/   net_types · net_retry · net_mirror · net_transport
│  │         · dio_net_transport · net_dns · net_bridge
│  └─ disk/  disk_types · disk_store · disk_cache · disk_journal
│            · disk_draft · platform_io · disk_bridge
├─ domain/                            # 中枢层（11 文件 / 5,476 行）
│  ├─ domain_bridge.dart
│  ├─ gh/    gh_models · gh_auth · gh_client · gh_api
│  ├─ ix/    ix_session · ix_task · ix_conflict · ix_notify
│  └─ sys/   sys_info · sys_access
└─ surface/                           # 消费层（10 文件 / 4,714 行）
   ├─ surface_bridge.dart
   ├─ app/      async_state · shell · og_l_app
   ├─ layout/   adaptive
   ├─ perm/     permission_policy
   ├─ settings/ settings_model
   └─ theme/    design_tokens · icon_pack · theme_pack
```

> 平台工程脚手架（android/ios/linux/macos/windows）**不提交进仓库**，
> 由 CI 在构建时用 `flutter create` 生成 —— 既满足"零外部资源"，又避免脚手架与 SDK 版本漂移。

## 5. 依赖规则（可由 lint / 脚本强制检查）

| 允许 | 禁止 |
|---|---|
| 任意模块 → kernel（注册自身） | 模块 → 其他层内部实现 |
| domain → base_bridge | base → domain / surface（反向依赖） |
| surface → domain_bridge | net ↔ disk 直接互调（必须经 base_bridge） |
| 任意模块 → 纯类型 / 模型 / 常量（值对象豁免） | UI 直接发请求 / 直接读写令牌 |

## 6. 关键数据流（现状名称）

```
启动：BootLoader → 清单 → 自检 → 签名/指纹 → 模块校验 → 扩展装载 → 就绪上报
读  ：UI → ix(会话) → domain_bridge → gh_api(策略) → base_bridge → net/disk(缓存) → 回填
写  ：UI → ix_task(队列) → gh_api(含基线 sha) → net → disk_cache 写后失效 + 回读 → 状态更新
重放：disk_journal(写前落盘) → 恢复 → 逐条重放（不降标准） → 提交成功清草稿(disk_draft)
解析：net_dns(自定义 DoH / UDP) → 失败回退系统解析并留痕
```

## 7. 进度与里程碑（2026-10-01 校准）

- **M0 架构冻结 ✓**（v3.1 文档）
- **M1 内核 + 底座 ✓**（2,801 + 4,600 行；缓存一致性 D1–D10 全部有测试）
- **M2 中枢 ✓**（5,476 行；+50 项领域测试）
- **M3 展示层（进行中）**
  - ✓ 已落地：令牌 / 自适应 / 图标语义 / 三主题 / 权限策略矩阵 / 设置模型 / 异步四态 / 主壳 / 应用入口 / 渲染快照流水线（12 张 PNG 进 CI 产物）
  - ☐ 待做：权限网关平台实现 · Mod 运行时 + 强制告警弹窗 · 真实数据页（仓库列表起步） · 动效打磨 · 缓存参数接到 L1
- **M4 Mod / 主题包生态 ☐**
- **构建矩阵**（`.github/workflows/build.yml`，13 目标）：
  Android ×5 ✓ · macOS arm64 ✓ · Windows / Linux / iOS 修复验证中（详见 CI 运行记录）

---
*v3.2 · 变更依据：全库通读核对（每文件行数、模块名、测试数与 CI 状态，逐项以代码为准）*
