# OGL 文档索引

> 阅读顺序即依赖顺序：先看架构，再看"生存规则"，最后看落地细节。

| 文档 | 回答的问题 | 强制性 |
| --- | --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 系统怎么分层、每层放什么、依赖往哪个方向流？ | 架构基线 |
| [CONSISTENCY.md](CONSISTENCY.md) | 缓存为什么是致命区？七道防线怎么落地？ | **强制验收** |
| [DURABILITY.md](DURABILITY.md) | 提交/编辑会不会丢？冲突怎么解释给用户？ | **强制验收** |
| [BOOT.md](BOOT.md) | 谁能被装载？签名/指纹/信任策略？扩展怎么告警？ | **强制验收** |
| [NAMING.md](NAMING.md) | 层级、模块、类前缀、告警码怎么取名？ | 强制 |
| [SURFACE.md](SURFACE.md) | 界面法则：布局断点 / DPI / 主题 / 图标 / 权限 / 设置护栏 | 强制 |
| [UI_SYSTEM_V3.md](UI_SYSTEM_V3.md) | 双主题（Primer 官方 / OGL 自研）与 OGL Kit 组件规范 | 设计真源 |
| [UI_PAGES_PLAN.md](UI_PAGES_PLAN.md) | **逐个页面重写的施工图**（结构 / 层级 / 行规格 / 状态 / 检查） | **先规划后写** |
| [RELEASE.md](RELEASE.md) | 怎么发版？通道/标签/证书/产物/排查？ | 发布手册 |
| [PHASE2_PLAN.md](PHASE2_PLAN.md) | 第二阶段修复与重构：清单/分层/层检/推送策略 | **执行契约** |
| [FEATURES.md](FEATURES.md) | **现在到底有哪些能力？哪些还没做？** | 功能真源 |
| [CODE_MAP.md](CODE_MAP.md) | **每个文件干什么？哪些不变量不能破？** | 改动前必读 |
| [LEGACY_FEATURES.md](LEGACY_FEATURES.md) | 老 App 有哪些功能？覆盖到哪了？还缺什么？ | 功能对照 |
| [STANDARDS.md](STANDARDS.md) | 什么叫商业级？自审发现了什么？ | 标准 + 记录 |
| [ROADMAP.md](ROADMAP.md) | 现在做到哪一步了？下一步是什么？ | 进度真源 |

## 配套文件（仓库根目录）

| 文件 | 用途 |
| --- | --- |
| [DESIGN.md](../DESIGN.md) | **视觉身份规范**（design-md 格式：令牌 + 理念 + 组件索引） |
| [README.md](../README.md) | 项目介绍、特性、构建方式 |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | 贡献约定与提交前自检 |
| [CHANGELOG.md](../CHANGELOG.md) | 版本变更记录 |
| [pubspec.yaml](../pubspec.yaml) | 依赖清单（按架构分层分组） |
| [analysis_options.yaml](../analysis_options.yaml) | 静态分析基线（警告即失败） |
