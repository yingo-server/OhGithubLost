# 变更记录（CHANGELOG）

本文件遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循[语义化版本](https://semver.org/lang/zh-CN/)。

## [未发布]

### 新增
- `docs/ROADMAP.md`：唯一进度真源（阶段勾选 + CI 运行号）。
- `CHANGELOG.md`、`CONTRIBUTING.md`：变更记录与贡献约定。

### 变更
- 待补充。

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
