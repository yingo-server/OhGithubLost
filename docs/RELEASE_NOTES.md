# Release 说明规范

> 目标：每个版本一个**结构一致、中英对照、可追责**的说明；用户只看这一页就能知道
> 「这版改了什么 / 会不会影响我 / 有什么已知问题 / 下哪份产物」。

## 1. 模板

```markdown
## OhGithubLost <版本> · 正式版 / Stable        （或：预发布 / Pre-release）

**主题 · Theme** — 一句话中文
*One-line English.*

### 新增 · Added        （留空则省略本节）
- **中文小标题 · English title**
  中文说明：做什么 + 为什么（必要时给数字）。
  English description: what and why (numbers where they help).

### 变更 · Changed
### 修复 · Fixed
### 已知限制 · Known limitations
### 安装注意 · Installation note      （仅签名/升级方式有变化时出现）
> **中文必须卸载重装的场景**，附一句英文。
### 产物 · Artifacts
Android（arm64-v8a / armeabi-v7a / x86_64 / universal APK / AAB）、Windows、Linux、macOS、iOS —— 共 **N** 个文件。
```

## 2. 硬性约定

| 约定 | 说明 |
|---|---|
| **中英对照** | 每条先中文、紧接英文（同一 bullet 内），不要中英两段分离。 |
| 标题格式 | `## OhGithubLost <版本> · 正式版 / Stable` 或 `· 预发布 / Pre-release`；**带通道**。 |
| 小节顺序 | 主题 → 新增 → 变更 → 修复 → 已知限制 →（安装注意）→ 产物。 |
| 术语 | GitHub / Release(s) / Actions / Pull request / PR / Token / Pages / Commit / Gist / README / DNS / DoH **不译**。 |
| 不写空话 | 禁止「优化体验」「若干修复」这类无信息量表述；写清**具体行为差异**。 |
| 已知限制必须写 | 真实存在的不支持项、平台差异、性能代价、未经充分验证的场景。 |
| 跨版本脉络 | 修复了历史问题的，注明**根因**与「自哪个版本起引入/修复」（如「4.4.0 的根因，4.8.0 修复」）。 |
| 预发布 | 预发布版本标题标注，并在「已知限制」里写明「仅供体验验证，请以正式版为准」。 |
| 产物数量 | 与本次 Release 实际资产数一致（含 `boot-manifest.zip`）。 |
| 链接与图片 | 不在正文塞长链接；需要引用文档用仓库内相对路径（如 `docs/I18N.md`）。 |

## 3. 写作检查清单

- [ ] 标题含**版本号 + 通道**；
- [ ] 每条都有英文对应句（不是整段翻译，而是逐条对应）；
- [ ] 新增/变更/修复里每条都能回答「用户会看到什么不同」；
- [ ] 「已知限制」不是空话，且与代码/CI 现状一致；
- [ ] 产物数量与实际资产一致；
- [ ] 破坏性变更（签名更换、需要卸载、参数必填）写在**安装注意**并加引用块。

## 4. 落地方式

线上 Release 正文由本机脚本维护（不随仓库发布）：

```bash
# 从文件覆盖某个 Release 的正文（只改 body，不动 tag / 标记 / 产物）
python3 ogl_release_notes.py set <tag> notes.md
# 目录内 <tag>.md 批量覆盖（先 --dry-run 看差异）
python3 ogl_release_notes.py set-all release_notes --dry-run
```

- 覆盖前自动把旧正文备份到 `release_notes_backup/<tag>.md`；
- 网络抖动会重试（`IncompleteRead`）；
- 版本发布时把 `release_notes` 目录里的同名文件作为 `release_notes` 输入传给构建工作流，
  这样「仓库里的规范」与「线上 Release」保持一致。
