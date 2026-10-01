# OGL 持久性防线（DURABILITY）

> 定位：[CONSISTENCY.md](CONSISTENCY.md) 的续篇。
> 一致性（D1–D7）解决"**别覆盖错**"，持久性（D8–D10）解决"**别丢**"。
> 两者合起来，才配得上"数据无价"。**强制验收标准。**

---

## D8 · 提交日志（Write Journal）

### 问题
没有日志时，"提交"是**一次易失的网络调用**：
用户点了提交 → 网络断 / App 被系统杀 → **这次提交彻底消失，无人知道**。

### 规则
```
① 写前落盘：真正要发出去的写，先落一条 pending 记录（内容 + 基线 + 提交信息）
② 结果收尾：
     成功            → 移除记录
     可重试失败       → 保留 pending（等网络恢复 / 用户点重试）
     语义性冲突       → 标记 abandoned（需用户重新决策）
③ 崩溃恢复：重启后 pending 记录仍在 → 「有 N 项未完成，是否重试」
```

### 关键性质
- **只有"真正要发的写"才入队**：D1/D2/D7 拦下的意图不产生待办，
  否则用户会看到一堆莫名其妙、永远清不掉的"待同步"。
- **重放不降标准**：重放 = 把记录还原成 `WriteIntent` 再走一次完整
  `RepositoryCache.write()`。D1/D2/D7 一条不少。
  「上次因为基线过期失败」的记录，重放时**仍会被拦下**并再次询问用户。
- **重放不产生重影**：重放时不重复入队（`recordJournal: false`），
  由重放方对**原记录**收尾。

### 落点
`lib/base/disk/disk_journal.dart`（`WriteJournal` / `JournalRecord`）、
`RepositoryCache.attachJournal` / `replayPending`。

---

## D9 · 草稿持久化（Draft Store）

### 问题
用户改了文件、还没点提交，此时崩溃 / 被杀 / 切走再也没回来 ——
**用户敲的字就没了。**

### 规则
1. **先落盘，再展示**：编辑器每次变更都 `save()`（调用方做防抖）；
2. **提交成功即清草稿**：由 `RepositoryCache` 在写成功后调用 `discard`，
   保证草稿不会"阴魂不散"地盖住刚提交的新内容；
3. **草稿带基线**：记录起草时基于哪个远端版本，冲突判定才有依据。

### 落点
`lib/base/disk/disk_draft.dart`（`DraftStore` / `DraftRecord`）、
`RepositoryCache.attachDrafts`。

---

## D10 · 冲突可解释（Three-Way + 处置建议）

### 问题
只说"冲突了"没有用。用户需要知道：
**我基于什么改的？别人改成了什么？我现在要写成什么？能怎么做？**

### 规则
冲突结果必须携带三方内容与**允许的处置方式**：

| 字段 | 含义 |
| --- | --- |
| `threeWay.base` | 用户编辑所基于的版本内容（**拿不到就如实为 `null`**） |
| `threeWay.remote` | 远端最新内容 |
| `threeWay.local` | 用户要写入的内容 |
| `threeWay.diverged` | 是否真分歧（两边各改各的） |
| `outcome.actions` | 允许的处置方式（顺序即推荐顺序） |

**硬性约束**：`staleSha` 的处置建议**必须**包含
`viewDiff` 与 `pullRemote`，**不得只给 `forceOverwrite`**。
"只给覆盖按钮"是把用户往数据事故上推。

### 落点
`lib/base/disk/disk_types.dart`（`ConflictThreeWay` / `ConflictAction` /
`resolveConflictActions`），`WriteOutcome.threeWay` / `WriteOutcome.actions`。

---

## 与强制覆盖的关系（重要）

即便用户选择了「强制覆盖」：

1. 必须经过 `confirmed: true`（D7）；
2. 后端仍以「**用户点确认那一刻读到的远端版本**」为期望值——
   若对话框挂着时又有人提交，服务端会**再拦一次**，用户必须重新决策。

即：**本设计不提供"无条件覆盖"**。要放开这个口子，属于产品策略变更，
必须先在本文档与 [CONSISTENCY.md](CONSISTENCY.md) 中登记理由。

---

## 验收清单

- [ ] 提交失败（网络 / 崩溃）后，队列里能查到该记录（内容 / 基线 / 次数 / 原因）；
- [ ] 重放会完整重走 D1–D7，且不会重复入队；
- [ ] 编辑中的内容在崩溃后可从草稿恢复；
- [ ] 提交成功后草稿被清空；
- [ ] 冲突结果同时给出 base / remote / local 与处置建议；
- [ ] `staleSha` 的处置建议含 `viewDiff`，不止 `forceOverwrite`；
- [ ] 全程有审计（`OGL-JOURNAL-*` / `OGL-CONS-*` / `OGL-DRAFT-*`）。