# OGL 文档索引

> 阅读顺序即依赖顺序：先看架构，再看"生存规则"，最后看落地细节。

| 文档 | 回答的问题 | 强制性 |
| --- | --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 系统怎么分层、每层放什么、依赖往哪个方向流？ | 架构基线 |
| [CONSISTENCY.md](CONSISTENCY.md) | 缓存为什么是致命区？七道防线怎么落地？ | **强制验收** |
| [DURABILITY.md](DURABILITY.md) | 提交/编辑会不会丢？冲突怎么解释给用户？ | **强制验收** |
| [BOOT.md](BOOT.md) | 谁能被装载？签名/指纹/信任策略？扩展怎么告警？ | **强制验收** |
| [NAMING.md](NAMING.md) | 层级、模块、类前缀、告警码怎么取名？ | 强制 |
| [LEGACY_FEATURES.md](LEGACY_FEATURES.md) | 老 App 有哪些功能？覆盖到哪了？还缺什么？ | 功能真源 |
| [STANDARDS.md](STANDARDS.md) | 什么叫商业级？自审发现了什么？ | 标准 + 记录 |
| [ROADMAP.md](ROADMAP.md) | 现在做到哪一步了？下一步是什么？ | 进度真源 |

## 配套文件（仓库根目录）

| 文件 | 用途 |
| --- | --- |
| [README.md](../README.md) | 项目介绍、特性、构建方式 |
| [CONTRIBUTING.md](../CONTRIBUTING.md) | 贡献约定与提交前自检 |
| [CHANGELOG.md](../CHANGELOG.md) | 版本变更记录 |
| [pubspec.yaml](../pubspec.yaml) | 依赖清单（按架构分层分组） |
| [analysis_options.yaml](../analysis_options.yaml) | 静态分析基线（警告即失败） |
