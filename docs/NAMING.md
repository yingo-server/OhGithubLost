# OGL 命名规范（NAMING）

> 一页定稿：层级 / 模块 / 类前缀 / 告警码 / 其他约定

## 1. 层级命名（L0–L3）

| 级 | 中文名 | 英文代号 | 目录 | 桥 | 日志标签 |
|---|---|---|---|---|---|
| **L0** | 内核级（总线段） | `kernel` | `lib/kernel` | —（提供桥注册） | `[KERNEL]` `[BOOT]` |
| **L1** | 底座级 | `base` | `lib/base` | `base_bridge`（底座桥） | `[NET]` `[DISK]` |
| **L2** | 中枢级 | `domain` | `lib/domain` | `domain_bridge`（中枢桥） | `[API]` `[IX]` |
| **L3** | 消费级 | `surface` | `lib/surface` | `surface_bridge`（消费桥） | `[UI]` `[MOD]` `[THEME]` |

## 2. 模块命名

| 级 | 模块 |
|---|---|
| L0 kernel | `boot` 启动层 · `module_bus` 模块总线 · `di` 依赖容器 · `lifecycle` 生命周期 · `bridge_registry` 桥注册 · `diagnostics` 诊断 |
| L1 base | `net` 网络连接 · `disk` 硬盘逻辑 |
| L2 domain | `api` API 逻辑 · `interaction` 交互逻辑 |
| L3 surface | `ui` 界面 · `mods` Mod · `themes` 主题包 |

## 3. 类名前缀（与层级一一对应）

| 层级/模块 | 前缀 | 示例 |
|---|---|---|
| kernel | `Kernel*` | KernelModuleBus、KernelDi、KernelLifecycle、KernelBridgeRegistry、KernelDiagnostics |
| kernel/boot | `Boot*` | BootLoader、BootTrustPolicy、BootIntegrityVerifier、BootTrustWarning |
| base/net | `Net*` | NetEngine、NetMirrorChannel、NetMetrics、NetError |
| base/disk | `Disk*` | DiskPaths、DiskKvStore、DiskSecretVault、DiskBlobCache、DiskFileOps、DiskPlatformIO |
| base（桥） | `Base*` | BaseBridge（+对外接口协议） |
| domain/api | `Gh*` | GhApi、GhRepo、GhFileEntry、GhConflictGuard、GhCachePolicy、GhPager |
| domain/interaction | `Ix*` | IxSession、IxThemeController、IxTasks、IxExtensionRegistry、IxBus |
| domain（桥） | `Domain*` | DomainBridge |
| surface/ui（设计系统） | `Og*` | OgTokens、OgThemeBuilder、OgGlassCard、OgButton、OgAsyncView |
| surface/ui（页面） | `*Page` | AuthPage、ShellPage、ReposPage、RepoPage、FilesPage、SitesPage、SearchPage、SettingsPage |
| surface/mods | `Mod*` | ModManifest、ModLoader、ModAction |
| surface/themes | `ThemePack*` | ThemePack、ThemePackLoader |
| surface（桥） | `Surface*` | SurfaceBridge |

## 4. 告警码段（TrustWarning / 审计 code）

| 段 | 领域 | 示例 |
|---|---|---|
| `OGL-BOOT-1xx` | 启动层 / 信任 | OGL-BOOT-101 未签名 Mod 已加载 |
| `OGL-CONS-2xx` | 一致性 / 冲突 | OGL-CONS-201 写入冲突自动重试 · OGL-CONS-202 冲突重试耗尽 |
| `OGL-NET-3xx` | 网络连接 | OGL-NET-301 镜像切换 |
| `OGL-DISK-4xx` | 硬盘逻辑 | OGL-DISK-401 缓存 schema 失配已丢弃 |
| `OGL-API-5xx` | API 逻辑 | OGL-API-501 令牌失效 |
| `OGL-IX-6xx` | 交互逻辑 | OGL-IX-601 任务取消 |
| `OGL-UI-7xx` | 界面 | OGL-UI-701 主题包非法已忽略 |

## 5. 其他约定

- **文件**：snake_case（`boot_loader.dart`）
- **提交前缀**：`kernel:` `boot:` `net:` `disk:` `api:` `ix:` `ui:` `mod:` `theme:` `docs:` `ci:`
- **事件/消息**：`ogl.<domain>.<action>`（如 `ogl.boot.trust_warning`）
- **JSON 协议字段**：lowerCamelCase，全协议保留 `extra` 冗余字段
- **常量**：`k` 前缀（如 `kDefaultTimeout`）
- **私有成员**：`_` 前缀；跨层只暴露桥接口，其余 `internal` 效果由 lint 强制