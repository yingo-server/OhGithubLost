# 贡献指南（CONTRIBUTING）

## 一、不可违背的三条红线

1. **缓存一致性是致命级**：任何涉及仓库读写的改动，必须逐条对照
   [`docs/CONSISTENCY.md`](docs/CONSISTENCY.md) 的七道防线（D1–D7）。
2. **Mod 告警必须触达用户**：禁止"只写日志不弹窗"（见 [`docs/BOOT.md`](docs/BOOT.md)）。
3. **跨层只准走桥**：`kernel → base → domain → surface` 单向依赖；
   同层内部走层内桥，禁止跨层直接 `new` 上层/下层实现。

## 二、代码规范

- 格式化：`dart format --line-length 80`。
- 静态分析：`flutter analyze --fatal-infos --fatal-warnings`（CI 红线，零容忍）。
- 文档：所有公开 API 必须有 `///` 文档注释；文件首行写"本文件做什么、不做什么"。
- 命名：遵循 [`docs/NAMING.md`](docs/NAMING.md) 的层前缀与告警码段。

## 三、提交前自检清单

- [ ] `flutter analyze` 零告警（含 info 级）。
- [ ] `flutter test` 全绿，新增行为有对应测试。
- [ ] 触碰缓存/仓库读写的改动，已对照 CONSISTENCY 七道防线自审。
- [ ] 触碰模块装载/扩展的改动，已对照 BOOT 信任策略自审。
- [ ] 更新 `docs/ROADMAP.md` 勾选状态与 `CHANGELOG.md`。

## 四、提交信息

采用 [Conventional Commits](https://www.conventionalcommits.org/zh-hans/)：

```
<type>(<scope>): <subject>

type: feat | fix | docs | refactor | perf | test | build | chore
scope: kernel | base | domain | surface | ci | docs
```

示例：`feat(base): 落地缓存一致性引擎（D1–D7）与冲突重试`

## 五、评审纪律

- 一次提交只做一件事，便于回滚。
- 涉及架构变更的，先改 `docs/`，评审通过后再动代码。
