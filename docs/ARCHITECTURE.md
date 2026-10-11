# OGL 架构

> 一页讲清四件事：**分成哪几层**、**谁能依赖谁**、**文件怎么命名**、**CI 怎么守**。
>
> 相关文档：[`docs/README.md`](README.md)（文档索引）· [`docs/NETWORK.md`](NETWORK.md)（网络出路）
> · [`docs/I18N.md`](I18N.md)（多语言手册）
>
> 维护纪律（与其它文档相同）：本文件点到的符号必须**真实存在**，与代码一致；
> 改名或改变行为时一并更新，否则这份文档会从资产变成误导源。

## 一、五层与依赖方向

```
        surface  (L3)   页面 / 控件 / i18n / 主题 / 用户交互
            │
        domain   (L2)   GitHub API、下载管理、文件操作、业务逻辑
            │
        base     (L1)   网络传输、磁盘存储、缓存引擎、DNS
            │
        kernel   (L0)   契约（抽象接口）+ DI + 模块总线 + 信任链 + 日志接口
            ↑
        platform        平台判定（`defaultTargetPlatform` 约定的出处）+ 窗口能力
```

**依赖只能向下**：`surface → domain → base → kernel`。
`platform` 只依赖 `kernel`，可被 `base` / `domain` / `surface` 依赖。
反向依赖（下层 import 上层）与跨层直接 import 别层的**实现**都是违规 —— 跨层要用
**桥 / 门面**（见 §四）。

## 二、层职责

| 层 | 目录 | 职责 | 代表符号 |
| --- | --- | --- | --- |
| kernel (L0) | [`lib/kernel/`](../lib/kernel) | 契约（`contract/` 下的抽象接口）+ DI + 模块总线 + 信任链（引导清单签名与完整性）+ 日志接口 | `KernelDi` · `KernelModuleBus` · `OgLModule` · `BootLoader` · `BootIntegrityVerifier` · `KernelLogSink` |
| platform | [`lib/platform/`](../lib/platform) | 平台识别与窗口能力（标题栏 / 最大化 / 权限网关 / 存储裁决的选型点） | `ogLDetectPlatform()` · `window_capability.dart` · `window_*.dart` |
| base (L1) | [`lib/base/`](../lib/base) | 网络传输（重试 / 主机冷却 / DoH 回落）、磁盘存储、缓存引擎（D1–D7 一致性）、DNS | `NetTransport` · `ResilientTransport` · `DnsService` · `RepositoryCache` · `OgLStorage` |
| domain (L2) | [`lib/domain/`](../lib/domain) | GitHub API 客户端、下载与预签名、仓库文件写回、设备信息等业务逻辑 | `GhApi` · `DomainBridge` · `IxPresign` · `SysInfoService` |
| surface (L3) | [`lib/surface/`](../lib/surface) | 页面、控件、i18n、主题、用户交互与其共用构件 | `SurfaceBridge` · 页面 `pages/*_page.dart` · 共用构件 `app/`（`AsyncController` / `AsyncView` · `OgLNotifier` · `PagedController`） |

## 三、依赖方向是怎么被守住的

```bash
python3 tool/layer_audit.py --fatal     # 有违规即退出 1（CI 门禁）
```

**两个合法的例外**（`layer_audit.py` 的 `ALLOW`）：

1. **装配根**：`domain/domain_bridge.dart`、`surface/surface_bridge.dart` —— 每层的装配
   入口，职责就是把下层接到本层，允许 import 下层桥；
2. **类型门面**：`surface/types.dart` —— 交互层唯一允许 re-export 逻辑层 DTO / 异常的地方，
   页面只 import 它，从而拿不到 domain 的服务类。

**已知待收敛**（`layer_audit.py` 的 `KNOWN`，属独立批次，不掩盖）：逻辑层目前直接依赖
硬件层的两个具体类型 —— `GhApi` → `RepositoryCache`、`GhClient` → `NetBridge`；
正解是在 `kernel/contract/` 定义抽象、由硬件层实现、逻辑层只依赖抽象。

平台判定的现状：`defaultTargetPlatform` 的**约定出处**在 `lib/platform/platform.dart`
（本文件即该约定的说明），但项目里还有几处按平台分流（`base/disk/app_dirs.dart`、
`surface/app/permissions.dart` / `system_notifier.dart`、`domain/sys/sys_info.dart`）；
把它们也收敛到 platform 层是待办。**新代码不要直接判平台**，走 platform 层门面。

## 四、命名

| 类别 | 命名 | 例 |
| --- | --- | --- |
| 页面 | `*_page.dart` | `pages/repo_page.dart` · `pages/settings_page.dart` |
| 桥（本层装配入口） | `*bridge.dart` | `base/base_bridge.dart` · `domain/domain_bridge.dart` · `surface/surface_bridge.dart`（硬件层内还有 `disk/disk_bridge.dart` · `net/net_bridge.dart`） |
| 平台实现 | `*_io.dart`（原生）· `*_web.dart`（浏览器） | `base/disk/app_dirs_fs_io.dart` · `base/net/net_dns_platform_io.dart`（web 分支已随 Web 支持一并移除，现无 `*_web.dart`；重新引入时按此命名） |
| 服务 / 门面 | `*service.dart` · `*manager.dart` · `*api.dart` | `domain/gh/repo_file_service.dart` · `domain/gh/gh_api.dart`（`DownloadManagerPage` 是**页面**，不属此类） |
| 共用构件（展示层） | 按"一件事一个文件"放在 `surface/app/` | `async.dart`（载 / 空 / 错 / 软错）· `notifier.dart`（提示语气）· `paged_controller.dart`（分页 + 快照） |

## 五、自检（提交前跑一遍）

```bash
python3 tool/layer_audit.py --fatal                          # 分层：违规 0
python3 tool/i18n_scan.py --check                            # i18n：未本地化 0 + 分片键一致
python3 tool/motion_audit.py --fatal                         # 动效：必须走档位质量表
python3 tool/perf_audit.py --fatal                           # 反模式：0
dart analyze lib/kernel lib/base lib/domain lib/platform     # 四个不依赖 Flutter SDK 的层：0 问题
```

展示层（`lib/surface/`）需要真实 Flutter SDK 才能 `dart analyze`，在无 SDK 的环境里以
`dart format --output=none lib`（纯语法解析）兜底；四个非 UI 层的静态分析必须为 **0 问题**。
