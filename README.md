# OhGithubLost（OGL）

Flutter 编写的 GitHub 仓库管理客户端。仓库地址与项目同名。

## 平台与测试状态

| 平台 | 构建产物 | 测试情况 | 说明 |
| --- | --- | --- | --- |
| Android | APK（arm64-v8a / armeabi-v7a / x86_64 / universal）、AAB | 经过测试 | 当前发布的可用目标 |
| Windows | x64、arm64 | 有限测试 | 基本流程可用，细节仍在核对 |
| Linux | x64、arm64 | 未测试 | 未在设备上验证 |
| macOS | x64、arm64 | 未测试 | 未在设备上验证 |
| iOS | device-arm64、simulator | 未测试 | 未在设备上验证 |

说明：

- macOS 与 iOS 设备当前**不能直接使用**。产物为未签名构建，需要自备证书与描述文件，或者使用开发者环境重新构建。
- 上表的"构建产物"由 CI 生成；"测试情况"指手工使用记录。

## 星标与提交历史

星标数量（蓝色折线）：

![星标数量折线图](https://raw.githubusercontent.com/yingo-server/OhGithubLost/stats/stats/star-history.png)

提交数量（绿色折线）：

![提交数量折线图](https://raw.githubusercontent.com/yingo-server/OhGithubLost/stats/stats/commit-history.png)

- 两张图由 GitHub Actions 每 10 分钟更新一次。
- 数据点写入 `stats/history.json`，折线图写入 `stats/star-history.png` 与 `stats/commit-history.png`，三份文件位于 `stats` 分支。
- 数据来源：仓库接口的 stargazers_count，以及提交接口分页计数。
- 折线按各自的极值缩放，量级差异下两条线仍可辨认。

## 功能

仓库浏览：

- 目录优先排序，可切换为按名称排序
- 按文件类型区分图标与颜色
- 长按（手机）或右键（桌面）菜单：下载、详情、删除
- 路径面包屑；切换目录时先清空旧数据

代码查看与编辑：

- 语法高亮：关键词、类型、字符串、注释、数字
- 配色预设：跟随主题、高对比、柔和、自定义（逐项选色）
- 独立编辑页：撤销、重做、查找、替换、字号调整、换行开关、未保存提醒、预览

议题、拉取请求与评论：

- 列表与详情、Markdown 渲染
- 评论发布，带长度护栏
- 关闭与重开

Releases：

- 列表与说明渲染
- 附件列表：文件名、大小、下载次数、下载入口
- 编辑标签、标题、说明、草稿、预发布
- 删除；复制说明

Actions：

- 运行列表与状态筛选
- 运行详情：作业与步骤、状态、结论、耗时
- 重新运行、取消运行
- 手动触发工作流：选择工作流、填写 ref 与 inputs

Gist：

- 列表、详情、新建、编辑、删除
- 内容被服务端截断时回退到 raw 地址

缓存与写入：

- 读取走底座缓存，目录列表 1 分钟、文件内容 30 秒，下拉刷新可绕过
- 写入与删除按基线 SHA 加锁；基线过期时给出提示，避免覆盖他人改动
- 缓存键包含账号、仓库、分支、路径四个维度

多语言：

- 15 种语言，JSON 按页面分片，位于 `assets/i18n/<语言>/<页面>.json`
- 缺失键按“当前语言、英文、键名”顺序回落
- 中文语境保留 GitHub 术语英文，例如 Issues、Releases、Actions、Pull Requests

权限引导：

- 按平台给出权限说明与跳转入口（Android、iOS、macOS、Windows、Linux、Web 分派）

设置：

- 分组可折叠，默认收起；进入设置页先看到分组标题
- 外观：明暗模式、主题色、界面密度、文字缩放、动效档位（最小、当前、标准、增强）
- 语言：15 种界面语言切换
- 代码与文件：语法高亮、主题预设、自动换行、代码字号、目录优先
- 网络：自定义 DNS、DNS 服务器、DoH 优先
- 账户：当前账号与退出登录
- 维护：权限与引导、重置设置
- 关于：独立页面（不放进折叠菜单），展示项目名称、主要开发者、版本、仓库地址与启动诊断
- 开源许可：本项目 AGPL-3.0 与第三方依赖清单（可收起，默认收起）
- 日志：日志文件路径与复制入口（可收起，默认收起）
- 捐赠一颗心：二次确认后，用当前登录账号给本仓库加星；已 star 时不重复操作

## 语言列表

| 代码 | 语言 |
| --- | --- |
| zh | 简体中文 |
| zh_TW | 繁體中文 |
| en | English |
| ja | 日本語 |
| ko | 한국어 |
| fr | Français |
| de | Deutsch |
| es | Español |
| pt | Português |
| ru | Русский |
| ar | العربية |
| hi | हिन्दी |
| th | ไทย |
| vi | Tiếng Việt |
| id | Bahasa Indonesia |

## 构建与发布

- `.github/workflows/ci.yml`：静态分析与单元测试，`push` 与 `pull_request` 触发。
- `.github/workflows/build.yml`：五平台构建；手动触发时填写通道、版本号、版本名、发布说明，构建通过后创建 Release。
- `.github/workflows/stats.yml`：每 10 分钟更新星标与提交折线图，写入 `stats` 分支。
- `.github/workflows/release-verify.yml`：对已发布版本做产物核对。

发布参数：

- `version_name` 与 `version_number` 为必填项，未提供默认值。
- 构建阶段对版本号与产物写入版本做比对，不一致时终止。

## 数据与隐私

- 令牌写入本机密钥库（Android Keystore、Windows DPAPI、Linux libsecret）。
- 仓库请求发往 `api.github.com`，不经过第三方服务。
- 令牌以脱敏形式进入日志。

## 目录结构

```
lib/
  kernel/     引导、模块总线、诊断、日志
  base/       网络传输、硬盘逻辑、缓存一致性
  domain/     GitHub 接口封装、认证、会话、任务
  surface/    页面、控件、主题、设置、多语言
assets/i18n/  语言包（按语言与页面分片）
test/         单元测试与渲染快照
tool/         构建脚本与图表脚本
```

## 许可

本仓库使用 GNU Affero General Public License v3.0（AGPL-3.0）。条款见 `LICENSE`。
