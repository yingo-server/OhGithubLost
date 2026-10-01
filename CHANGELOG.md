# 变更记录（CHANGELOG）

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增
- `docs/ROADMAP.md`：唯一进度真源（阶段勾选 + CI 运行号）。
- `CHANGELOG.md`、`CONTRIBUTING.md`：变更记录与贡献约定。

### 变更
- 无（本轮仅新增文档与清理）。

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
