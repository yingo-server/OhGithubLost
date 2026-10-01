# OhGithubLost（OGL）

[![CI](https://github.com/yingo-server/OhGithubLost/actions/workflows/ci.yml/badge.svg)](https://github.com/yingo-server/OhGithubLost/actions/workflows/ci.yml)
[![Build](https://github.com/yingo-server/OhGithubLost/actions/workflows/build.yml/badge.svg)](https://github.com/yingo-server/OhGithubLost/actions/workflows/build.yml)

> **GitHub 第三方客户端** · Flutter 全平台（Android / Windows / Linux / macOS / iOS）
> Linux 内核式四层架构（L0 内核 → L1 底座 → L2 中枢 → L3 展示） · 零外部资源 · 双主题（Primer 官方 / OGL 自研）

## 这是什么

OGL 是一个完整的 **GitHub 第三方客户端**：

- **仓库全功能**：文件浏览 / 编辑提交（基线 sha 防错位覆盖）/ 删除文件、议题（新建 / 评论 / 关闭）、
  Pull Request（列表 / 文件变更）、发布（新建 / 删除）、分支（增 / 删 / 改）、提交历史与 compare 对比、
  Pages / CNAME / 危险区；
- **发现与组织**：仓库与代码搜索、星标仓库、多账户切换、Gist 列表；
- **工程底盘**：缓存一致性防线（D1–D10）、启动层信任策略（Ed25519 + 指纹）、
  应用级日志环（原始异常 + 堆栈）、一键发布的 CI（13 个全架构构建目标）。

## 下载与安装

- **稳定版**：在 [Releases](https://github.com/yingo-server/OhGithubLost/releases) 页面下载
  `OGL-v*-arm64-v8a-release.apk`（绝大多数安卓手机适用）；
- 全部平台产物见 `build` 工作流最近一次运行（13 个"平台 × 架构"目标）；
- **签名**：自 v0.1.0 起使用固定证书 → 可直接覆盖安装；更早的随机证书安装包需先卸载一次。

## 架构（L0–L3 · 每层一座桥）

```
L3 展示 SURFACE   UI · OGL Kit · 主题（primer / ogl.spatial） · Mod
L2 中枢 DOMAIN    GitHub 语义与治理 · 会话/任务/冲突 · 设备信息与能力守门
L1 底座 BASE      网络（DNS 策略 / 重试 / 镜像） ‖ 硬盘（KV / 保险库 / 一致性介质）
L0 内核 KERNEL    启动层 BootLoader · 模块总线 · 依赖容器 · 生命周期 · 诊断
```

- **依赖单向**：`surface → domain → base → kernel`；跨层只允许 import 对方 `*_bridge`；
- **启动层**：Ed25519 清单签名 + 逐层模块指纹；第三方主题不设限，第三方 Mod 放行但必须告警（UI 弹窗）。

## 文档

完整索引见 [docs/README.md](docs/README.md)（架构 / 一致性 / 持久化 / 启动 / 界面法则 / **发布手册**）。

## 开发

```bash
flutter pub get
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

> 发布新版本：Actions → `build` → Run workflow（选通道 stable/beta/alpha + 版本号/版本名/说明），
> 详见 [docs/RELEASE.md](docs/RELEASE.md)。

## 许可证

[MIT](LICENSE)