# OGL 路线图（ROADMAP）

> 本文件是**唯一进度真源**：每次交付后更新勾选状态与 CI 运行号。
> 验证原则：本机无 Flutter SDK，一切代码质量以 **CI 实跑**为准（静态分析 + 单测）。

## 里程碑总览

| 阶段 | 名称 | 交付物 | 状态 |
| --- | --- | --- | --- |
| A | 代码整理与文档完善 | barrel / 规范 / 文档索引 / 变更记录 | ✅ |
| B | **L1 底座级** `base/` | `net/` + `disk/`（含缓存一致性 D1–D7）+ `base_bridge` | ✅ |
| C | **L2 中枢级** `domain/` | `gh/` + `ix/` + `sys/` + `domain_bridge` | ✅ |
| D | **L3 展示级** `surface/` | `theme/` + `ui/` + `mod/` + `surface_bridge` | ⏳ 下一步 |
| E | **UI 三项打磨** | E1 动效 / E2 性能 / E3 代码之美 | ⏳ |

## 已完成

- [x] **M0 架构冻结 v3.1** —— 双底座 → 双中枢 → 消费层；总线段 Kernel；每层一座桥
- [x] 命名规范冻结（`docs/NAMING.md`）
- [x] 依赖清单（`pubspec.yaml`，按分层分组）
- [x] **L0 内核级**（13 源文件 + 23 项测试）
  - 契约 / DI / 桥注册 / 模块总线 / 生命周期 / 诊断
  - 启动层：`boot_loader` / `boot_manifest` / `boot_fs` / `integrity_verifier` / `trust_policy` / `trust_warnings`
- [x] CI 接入（Flutter 3.47.5，`analyze --fatal-infos --fatal-warnings` + `test`）
- [x] CI run `36752266286` **全绿**（23/23 测试通过）

## 阶段细则

### A 代码整理与文档完善
- [ ] 文档索引 `docs/README.md`
- [ ] 变更记录 `CHANGELOG.md`、贡献指南 `CONTRIBUTING.md`
- [ ] 代码风格自查（import 次序 / 文档头 / 无死代码）

### B L1 底座级
- [x] `base/net`：请求/响应类型、重试退避（**幂等守卫**）、镜像通道、传输抽象、Dio 实现、观测
- [x] `base/disk`：KV / 保险库 / 文件原语 / **缓存一致性引擎（D1–D7）**
- [x] `base_bridge` 与 L1 模块装配（`base.net` / `base.disk` / `base.layer`）
- [x] **持久性防线 D8–D10**：提交日志（写前落盘 / 可恢复 / 可重放）、草稿持久化、冲突三方信息与处置建议
- [x] 键校验（作用域分隔符 / 路径穿越）、内容完整性（长度 + SHA-256）、有界淘汰（TTL / prune / purge）
- [x] `base/disk/platform_io.dart`：真实平台持久化（**原子写：临时文件 + fsync + rename**；启动清扫残骸；`IoDiskKv` 摘要文件名防路径越界）
- [x] **能力冲突交由用户选择**原则落档（搜索策略 / 批量提交方式 / 下载通道 / 大文件通路 / 目录树获取）
- [x] **DNS 支持**：策略层（系统解析 / 自定义，内置阿里·腾讯·114·Cloudflare·Google 五家）、
      RFC 1035 报文编解码、DoH（注入式 HTTP）、明文 UDP、TTL 缓存、并发竞速、失败回退系统（留痕）、
      接入真实传输（`connectionFactory` 接管，代理与 SNI 不受影响）
- [x] **内核环境自检扩展点**（`KernelEnvironmentProbe` + 注册表 + `kernel.runProbes()`），内核保持零依赖

### C L2 中枢级
- [x] `domain/gh`：领域模型（含 `truncated` / `>1 MB` 识别）、认证（令牌只进保险箱）、
      请求客户端（限流避让 / 并发闸门 / 分页安全上限 / 错误映射）、端点全量封装
      （仓库·分支·内容·树·**批量原子提交**·提交历史·compare·Releases·搜索·代码搜索·
      Pages·CNAME·组织·星标写·Issues·PR·Gist·Actions·标签·README）
- [x] **`CacheRemote` 适配**：D1–D10 接到真实 GitHub API（读含 Blobs 补齐、写带基线 sha）
- [x] `domain/ix`：会话（上下文 + 偏好 + 持久化）、批量任务（**强制确认 + 通道选择 + 可取消 + 逐条结果**）、
      冲突编排（三方预览 + 处置排序 + 危险确认）、通知中心（去重合并 + 安全告警不可关）
- [x] `domain/sys`：本地深层信息（设备/应用/环境/内存/网络策略，采集器可注入）、
      **Mod 能力守门**（清单 / 授权 / 撤销 / 审计 / 按授权裁剪）
- [x] `domain_bridge` 与 L2 模块装配（`domain.gh` / `domain.ix` / `domain.sys` / `domain.layer`）
- [x] L2 测试（`gh_test` / `gh_client_test` / `ix_test` / `sys_test`，+50 项）

### D L3 展示级
- [ ] `surface/theme`：设计令牌、双内置风格（VSCode 极简 / 圆角毛玻璃）、主题包
- [ ] `surface/ui`：页面、组件、响应式布局（多端）
- [ ] `surface/mod`：Mod 运行时 + **强制告警弹窗**
- [ ] `surface_bridge` 与 L3 模块装配

### E UI 三项打磨（各一轮，均以 CI 验证）
- [ ] E1 动效：朴素而深入人心的动画（淡入/位移/曲线，克制不喧哗）
- [ ] E2 性能：帧率、内存、懒加载、重绘边界
- [ ] E3 代码之美：结构、命名、注释、可读性

## 变更记录

| 日期 | 变更 | CI |
| --- | --- | --- |
| — | L0 内核级落地 | `36752266286` ✅ |
| — | L0 缺陷修复（force 二次确认 / write 不外抛 / 诊断接线 / 完整性校验 / 读写同锁 / 幂等重试 / 有界淘汰） | `36799111105` ✅ |
| — | 持久性防线 D8–D10（提交日志 / 草稿 / 冲突三方与处置建议） | `36801743094` ✅ |
| — | L1 真实平台持久化（原子写 / 启动清扫 / 摘要键 KV） | `36809423885` ✅ |
| — | DNS 策略层（内置五家 / DoH / RFC 1035 / 竞速 / 回退）+ 内核环境自检扩展点 | `36807894594` ✅ |
| — | L2 中枢级（gh + ix + sys + domain_bridge，248 项测试） | `36811401922` ✅ |
