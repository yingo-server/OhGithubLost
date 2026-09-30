# OhGithubLost（OGL）

[![CI](https://github.com/yingo-server/OhGithubLost/actions/workflows/ci.yml/badge.svg)](https://github.com/yingo-server/OhGithubLost/actions/workflows/ci.yml)

> 全能 GitHub 仓库管理器 · Flutter 全平台重构版
> 移动优先 · 全平台（Android 5.1+ / Windows / Linux）· 商业级工程质量

## 这是什么

OGL 是一个"像管理本地文件一样管理 GitHub 仓库"的跨平台应用：
浏览与编辑文件、批量上传下载、发版管理、**一键建站（GitHub Pages）与自定义域名**、
主题包与 Mod 扩展体系——并对"代码仓库最怕的事"（版本不一致、错位覆盖）做工程级防护。

## 架构（三层四段）

```
消费层 SURFACE   UI · Mod · 主题包（全部挂载在交互逻辑之上）
中枢层 DOMAIN    API 逻辑（GitHub 语义 + 冲突治理） · 交互逻辑（状态/命令/任务/扩展点）
底座层 BASE      网络连接 net ‖平行‖ 硬盘逻辑 disk（含缓存一致性介质）
内核级 KERNEL    启动层 BootLoader · 模块总线 · 依赖容器 · 生命周期 · 桥发现 · 诊断
```

- **每层一座桥**：跨层只允许 import 对方 `*_bridge`，禁止直连实现；
- **依赖单向**：`surface → domain → base → kernel`，由 lint 与评审强制；
- **启动层（BL 锁）**：Ed25519 清单签名 + 逐层模块目录指纹校验；
  第三方主题**不设限制**，第三方 Mod **放行但必须总线告警 + UI 弹窗通知**。

## 文档（先设计后编码）

| 文档 | 内容 |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 分层架构 / 目录分布 / 依赖规则 / 数据流 |
| [docs/CONSISTENCY.md](docs/CONSISTENCY.md) | 缓存与一致性协议（七道防线，防错位覆盖） |
| [docs/BOOT.md](docs/BOOT.md) | 启动层与信任策略（BL 锁 / 主题开放 / Mod 告警） |
| [docs/STANDARDS.md](docs/STANDARDS.md) | 商业级交付标准 + 设计自审报告 + PR 清单 |
| [docs/NAMING.md](docs/NAMING.md) | 层级 / 模块 / 类前缀 / 告警码 命名规范 |

## 当前进度

- ✅ **M0 架构冻结**：三份强制协议（架构 / 一致性 / 启动层）与规范落地
- ✅ **L0 内核级**：启动层（签名 + 指纹 + 信任策略 + 告警）、模块总线、依赖容器、
  生命周期（含失败回滚）、桥注册、诊断中枢 —— 23 项单元测试
- ⏳ M1：底座（`base/net` 传输引擎与镜像通道 · `base/disk` 缓存一致性与平台 IO）
- ⏳ M2：中枢（GitHub API 冲突治理 + 交互控制器/任务队列）
- ⏳ M3：UI 最小闭环；⏳ M4：Mod / 主题包生态

## 开发

```bash
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

> 引导清单（`assets/boot/manifest.json`）由 CI 构建时生成并签名；
> 本地调试可用 `BootLoader(developmentBypass: true)`，该旁路必然产生
> `OGL-BOOT-107` 告警，发布构建严禁开启。

## 许可证

[MIT](LICENSE)