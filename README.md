# OhGithubLost（OGL）

GitHub 仓库管理客户端，手机、平板与桌面可用。仓库地址与项目同名。

## 平台与测试状态

| 平台 | 构建产物 | 测试情况 | 说明 |
| --- | --- | --- | --- |
| Android | APK（arm64-v8a / armeabi-v7a / x86_64 / universal）、AAB | 经过测试 | **当前主要目标**；应用名为 **OGL** |
| Windows | x64、arm64 | 有限测试 | 基本流程可用，细节仍在核对 |
| Linux | x64、arm64 | 未测试 | 未在设备上验证 |
| ~~macOS~~ | — | — | **自 5.6.0 起弃用**，最后支持版本 **v5.3.0** |
| ~~iOS~~ | — | — | **自 5.6.0 起弃用**，最后支持版本 **v5.3.0** |

说明：

- **自 5.6.0 起不再构建 / 发布 macOS 与 iOS**；需要这两个平台请使用
  **[v5.3.0](https://github.com/yingo-server/OhGithubLost/releases/tag/v5.3.0)**
  （其产物为未签名构建，需自备证书与描述文件，或自行重建）。
- **自 5.6.0 起，Release 只提供压缩包**：每个平台产物同时给出 **`.zip` 与 `.7z`**，
  且都用**极限压缩**（`zip -9` / `7z -mx=9`），不再直传裸 APK / AAB / 平台目录。
- **32 位**：桌面端（Windows / Linux）上游 Flutter **不提供 32 位目标**，因此只有
  Android 有 32 位产物（`armeabi-v7a`）。
- 上表的「构建产物」由 CI 生成；「测试情况」指手工使用记录。

## 平台最低要求（请先读，能省下大量时间）

| 平台 | 最低要求 | 说明 |
| --- | --- | --- |
| Android | Android 6.0（API 23）+ | 32 位（`armeabi-v7a`）仅此平台提供 |
| Windows | **Windows 10 1809 或更高** | Flutter 桌面自身的要求；**7 / 8.1 无法运行** |
| Linux | **glibc ≥ 2.28** | 对应 Ubuntu 18.10 / Debian 10 / RHEL 8 那一代；产物在更老的 glibc 上会报 `GLIBC_2.xx not found` |

### ⚠️ 不要做无用尝试

以下组合**明确不支持**，试了也不会成功（不是配置问题，是上游限制）：

- **Linux · musl 系（Alpine 等）**：Flutter 的 Linux 引擎依赖 glibc，musl 下不保证可运行；
- **Linux · glibc < 2.28**：产物按 2.28 基线构建，老系统缺符号；
- **Windows 7 / 8.1**：Flutter 桌面要求 Windows 10 1809+；
- **桌面 32 位（x86）**：Flutter 桌面只提供 x64 / arm64，**没有 ia32 引擎**。

### 可选要求

- **Windows 长路径支持**（建议开启）：路径接近 260 字符时，
  Windows 会拒绝创建文件。程序已做三层兜底（`\\?\` 前缀 → 超长部分收纳为
  `TooLongRoad_<8位编号>.zip` → 根目录索引可还原），但**开启系统长路径支持后
  体验最好**（组策略 / `LongPathsEnabled`）。

## 快速开始

1. 在 Releases 页面下载对应平台的安装包。
2. 打开应用，用 GitHub 个人访问令牌登录，或以游客身份浏览公开内容。

详细步骤与各项功能用法，见 **[使用说明](docs/USAGE.md)**。

## 主要功能

- 仓库浏览与文件操作：目录优先排序、按类型显示图标、下载 / 详情 / 删除、在线编辑与提交。
- 代码编辑器：撤销 / 重做、查找 / 替换、换行与字号、未保存提醒、冲突提示。
- Issues 与 Pull Requests：列表、详情、评论、关闭 / 重开、变更文件与补丁查看。
- Releases：列表、详情、附件下载、新建 / 编辑 / 删除。
- Actions：运行列表与详情（作业与步骤）、重新运行 / 取消、手动触发工作流。
- Gist：列表、详情、新建、编辑、删除。
- 搜索：仓库搜索与代码搜索，代码结果可直达文件。
- 多账号、15 种界面语言、主题与动效档位、DNS 与 DoH、日志与开源许可。

## 文档

- [使用说明](docs/USAGE.md)
- [多语言维护手册](docs/I18N.md)
- [Release 说明规范](docs/RELEASE_NOTES.md)
- [更新日志](CHANGELOG.md)

## 星标与提交历史 · Stars & commits

**星标数量 · Stars（蓝线 / blue）**

![星标数量曲线：纵轴为「个」、从 0 起；横轴为 UTC 时间](https://raw.githubusercontent.com/yingo-server/OhGithubLost/stats/stats/star-history.png)

**提交数量 · Commits（绿线 / green）**

![提交数量曲线：纵轴为「个」、从 0 起；横轴为 UTC 时间](https://raw.githubusercontent.com/yingo-server/OhGithubLost/stats/stats/commit-history.png)

### 怎么读这两张图 · How to read

- **纵轴 / Y axis**：从 **0** 起（不截断），单位是**个（count）**；上限取"整齐"刻度
  （1 / 2 / 2.5 / 5 × 10ⁿ），并画出 5 条刻度线与数值。
  *Starts at 0, unit = count, "nice" upper bound with 5 labelled gridlines.*
- **横轴 / X axis**：**真实 UTC 时间**（`MM-DD HH:MM`），不是"第几个采样点"——
  采样间隔不均时不会被拉伸或压缩。*A true time axis in UTC, so uneven sampling
  intervals are shown honestly.*
- **两图不可直接比高度**：星标与提交各自独立纵轴，请**看纵轴数值**而不是线条高低。
  *The two charts have independent Y axes — compare values, not visual heights.*
- 图上标题行给出「最新值 / 数据点数 / 数据来源」，最新点用方块标出。
  *The header row shows last value, point count and source; the latest point is boxed.*

### 更新与产物 · Updates & files

- 由 GitHub Actions 每 10 分钟更新一次（`.github/workflows/stats.yml`）。
- 数据点：`stats/history.json`（`{ "t": ISO-8601 UTC, "stars": 整数, "commits": 整数 }`）；
  图表：`stats/star-history.png`、`stats/commit-history.png`；三份文件都位于 `stats` 分支。
- 数据来源：仓库接口的 `stargazers_count`，以及提交接口 `Link` 头 `rel="last"` 的页码（总数）。
- 历史最多保留 **2000** 点；绘图时按像素密度**等距降采样**（保留首尾），避免折线糊成一片。
- 生成器 `tool/stats_chart.py` **零第三方依赖**（zlib 手写 PNG + 内置 5×7 点阵字体），
  并提供 `--selftest` 在 CI 中核对刻度 / 时间轴 / 降采样数学。
- 折线按各自的极值缩放，量级差异下两条线仍可辨认。

## 许可

本仓库使用 GNU Affero General Public License v3.0（AGPL-3.0）。条款见 `LICENSE`。