# OhGithubLost（OGL）

GitHub 仓库管理客户端，手机、平板与桌面可用。仓库地址与项目同名。

## 平台与测试状态

| 平台 | 构建产物 | 测试情况 | 说明 |
| --- | --- | --- | --- |
| Android | APK（arm64-v8a / armeabi-v7a / x86_64 / universal）、AAB | 经过测试 | 当前主要目标 |
| Windows | x64、arm64 | 有限测试 | 基本流程可用，细节仍在核对 |
| Linux | x64、arm64 | 未测试 | 未在设备上验证 |
| macOS | x64、arm64 | 未测试 | 未在设备上验证 |
| iOS | device-arm64、simulator | 未测试 | 未在设备上验证 |

说明：

- macOS 与 iOS 设备当前不能直接安装使用。产物为未签名构建，需要自备证书与描述文件，或者使用开发者环境重新构建。
- 上表的「构建产物」由 CI 生成；「测试情况」指手工使用记录。

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
- [更新日志](CHANGELOG.md)

## 星标与提交历史

星标数量（蓝色折线）：

![星标数量折线图](https://raw.githubusercontent.com/yingo-server/OhGithubLost/stats/stats/star-history.png)

提交数量（绿色折线）：

![提交数量折线图](https://raw.githubusercontent.com/yingo-server/OhGithubLost/stats/stats/commit-history.png)

- 两张图由 GitHub Actions 每 10 分钟更新一次。
- 数据点写入 `stats/history.json`，折线图写入 `stats/star-history.png` 与 `stats/commit-history.png`，三份文件位于 `stats` 分支。
- 数据来源：仓库接口的 stargazers_count，以及提交接口分页计数。
- 折线按各自的极值缩放，量级差异下两条线仍可辨认。

## 许可

本仓库使用 GNU Affero General Public License v3.0（AGPL-3.0）。条款见 `LICENSE`。