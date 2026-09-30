# OGL 启动层（BootLoader）与信任策略（BOOT）

> 定位：内核的第一个子系统，**先于一切模块运行**。负责"谁能被装载"的裁决——借 BL 锁的模型：官方模块必须过校验，第三方扩展按信任分级区别对待。

---

## 1. 启动序列（5 阶段）

```
Stage 0 内核自检 ▸ kernel 自身指纹校验（防注入/篡改）
Stage 1 引导清单校验 ▸ boot_manifest.json 签名/指纹验证
Stage 2 层级模块校验（BL 锁） ▸ base → domain → surface 官方模块逐一指纹比对
 ├─ 通过 → 装载
 └─ 失败 → 拒绝装载该模块 +安全模式 +总线告警（不允许"降级放行"）
Stage 3 扩展装载（差异化策略）
 ├─ 主题包 → 不设信任限制（仅 schema 白名单校验）→ 直接装载
 └─ Mod 包 → 放行，但标记"第三方未签名" →总线警告 +审计 +用户可见
Stage 4 就绪上报 ▸ 依赖图 /启动耗时 /告警清单 →交互层 → UI（安全中心）
```

## 2. 引导清单（Boot Manifest）

随发布产物分发，CI 构建时自动生成（禁止手工维护）：

```json
{
 "schema": 1,
 "appVersion": "0.1.0",
 "buildId": "2026.09.30-abcdef",
 "generatedAt": "2026-09-30T17:00:00Z",
 "modules": [
 { "id": "base.net", "layer": "base", "path": "lib/base/net/", "sha256": "…", "version": "0.1.0" },
 { "id": "base.disk", "layer": "base", "path": "lib/base/disk/", "sha256": "…", "version": "0.1.0" },
 { "id": "domain.api", "layer": "domain", "path": "lib/domain/api/", "sha256": "…", "version": "0.1.0" },
 { "id": "domain.interaction", "layer": "domain", "path": "lib/domain/interaction/", "sha256": "…", "version": "0.1.0" },
 { "id": "surface.ui", "layer": "surface", "path": "lib/surface/ui/", "sha256": "…", "version": "0.1.0" }
 ],
 "extra": {}
}
```

- **清单签名**：清单整体用发布私钥签名（Ed25519），公钥内嵌应用；签名不符 → 拒绝启动（Stage 1）。
- **模块指纹**：每模块目录 sha256（规范化排序）；不符 → 拒绝该模块（Stage 2）。
- **清单冗余**：`extra` 字段保留未知内容；schema 版本化，向前兼容。

## 3. 信任分级（Trust Tiers）

| 对象 | 锁状态 | 校验方式 | 处置 |
|---|---|---|---|
| 官方核心模块（kernel/base/domain/surface 内置） | 🔒 **locked** | 清单签名 +目录指纹 | 不符 → **拒绝装载 +安全模式** |
| 未来官方扩展（官方 Mod/主题） | ✅ verified | 指纹比对 | 不符 → 警告 +禁用 |
| **第三方主题** | 🟢 **open（不设限制）** | 仅 schema 白名单解析校验 | 直接可用（声明式数据，无代码执行，安全边界由 schema 保证） |
| **第三方 Mod** | ⚠️ **warn（放行+告警）** | schema 校验 +信任标记 | 装载，但**必须向总线发出警告**，并写入审计与用户可见清单 |

> 策略变更（如把主题改为 locked）属于破坏性变更：必须走 ADR +迁移说明。

## 4. 总线警告机制（Bus Warning）

Mod 装载不是"静默放行"，而是**显式告警**：

```
kernel.warn(TrustWarning(
 code: 'OGL-BOOT-101',
 subject: 'mod:hidden-tools@1.2.0',
 severity: Severity.warn,          // info / warn / danger
 message: '已加载未经签名的第三方 Mod，请确认来源可信',
 at: now,
))
```

- **传播路径**：BootLoader → 内核告警汇总 → 交互层 session → UI；
- **UI 弹窗通知（强制）**：告警**不得只落日志**。交互层必须把未确认告警以**对话框形式弹窗通知用户**（内容：Mod 名称/来源/风险说明；操作：「信任并继续」「禁用该 Mod」）；用户可选「不再提示此 Mod」，但**审计记录不豁免**；重复告警可降级为横幅 +「安全中心」角标；
- **持久化**：审计日志（可导出）+ 扩展清单（可一键禁用/卸载）；
- **可升级**：同一 Mod 若被标记 danger（如声明高危能力），启动时需用户显式确认；
- **审计字段**：`ts · subject · code · severity · action(taken) · by(user/boot)`。

## 5. 失败处置与安全模式（Fail-safe）

| 情形 | 行为 |
|---|---|
| 官方模块指纹不符 | 拒绝装载 →进入**安全模式**（仅内核 +最小核心）→提示修复/重装 →审计上报 |
| 引导清单签名不符 | 拒绝启动（最高级别），提示应用可能被篡改 |
| 扩展（Mod/主题）加载失败 | 跳过该扩展，不影响启动；记录原因 |
| 连续多次启动失败 | 自动进入安全模式并禁用全部第三方扩展，引导用户排查 |

## 6. 威胁模型（如实声明边界）

- ✅ 防御：打包后被注入/替换模块文件；伪造扩展冒充官方模块；静默加载未授权 Mod。
- ⚠️ 不防：拥有调试能力的用户重打包（与所有本地应用同级别限制）；
- 平台手段：Android（APK 签名 +资产指纹自检）、Windows（Authenticode +清单指纹）、Linux（发布包签名 +清单指纹）。

## 7. 测试要求（CI 门禁）

1. 篡改任一官方模块文件 →启动必须拒绝并进安全模式；
2. 篡改引导清单/签名 →启动必须拒绝；
3. 装载第三方 Mod →必须产生总线警告 +审计记录；
4. 装载第三方主题 →无信任拦截（仅 schema 校验），不得误报警告；
5. schema 不合法主题 →仅拒绝该主题，不影响启动；
6. 安全模式：核心功能可用、扩展全部禁用；
7. **UI 弹窗**：装载 Mod 后必须实际弹出告警对话框，「禁用该 Mod」可生效（禁止"只写日志不弹窗"）。

## 8. 与架构落点

| 要素 | 归属 |
|---|---|
| 启动序列/裁决 | `kernel/boot/boot_loader.dart` |
| 信任分级策略 | `kernel/boot/trust_policy.dart` |
| 指纹/签名校验 | `kernel/boot/integrity_verifier.dart`（Ed25519 + sha256） |
| 总线警告 | `kernel/boot/trust_warnings.dart` + `kernel/diagnostics` |
| 清单生成 | CI 脚本（构建时产出，随包发布） |
| UI 呈现 | `surface/ui`（安全中心，经交互层） |

---
*本文件与 CONSISTENCY.md 同为强制验收标准：涉及模块装载与扩展的任何改动，都必须逐条对照本文。*