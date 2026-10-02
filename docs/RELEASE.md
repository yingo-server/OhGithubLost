# OGL 发布手册（RELEASE）

> 讲清楚四件事：**怎么发版**、标签与版本怎么定、**证书为什么固定**、坏了怎么查。

## 一键发布（推荐）

1. GitHub → **Actions** → `build` → **Run workflow**；
2. 必填参数：

   | 参数 | 说明 | 示例 |
   | --- | --- | --- |
   | `channel` | 发布通道：`stable` / `beta` / `alpha` | `stable` |
   | `version_number` | 版本号（正整数，写入 Android `versionCode`） | `1` |
   | `version_name` | 版本名（写入 Android `versionName`） | `0.1.0` |
   | `release_notes` | Release 说明（可留空 → 自动模板） | `修复若干问题` |

3. 全平台构建成功后，**`release` 任务自动**：
   - 计算标签：`stable` → `v{版本名}`；`beta`/`alpha` → `v{版本名}-{通道}`（版本名已含通道则不重复）；
   - 创建 GitHub Release（beta / alpha 自动勾选 **Pre-release**）；
   - 上传资产：APK / AAB 加 `OGL-v{版本名}-` 前缀直传；其余平台打包为 zip；
     另附 GitHub 自动生成的源码 zip / tar.gz。

## 标签与版本约定

| 通道 | 标签示例 | GitHub 状态 | 语义 |
| --- | --- | --- | --- |
| stable | `v1.2.0` | Latest | 正式版 |
| beta | `v1.2.0-beta` | Pre-release | 公测 |
| alpha | `v1.2.0-alpha` | Pre-release | 内测 |

> 版本号与 `pubspec.yaml` 的 `version` 同步维护；构建时通过
> `--build-name/--build-number` 灌入安卓产物（versionName / versionCode）。

## 固定签名证书（可覆盖安装）

- 位置：`.github/signing/ogl-debug.keystore.b64`（JKS，别名 `androiddebugkey`，口令 `android`）；
- 构建前解码到 `$HOME/.android/debug.keystore` → 所有产物同一签名 → **新包可直接覆盖安装**；
- 首个 Release（v0.1.0）之前的构建使用随机 debug 证书，安装过的设备需**先卸载一次**；
- **红线：证书永久保留**（丢失 = 存量设备永远无法覆盖升级）。
  指纹与安全说明见 [`.github/signing/README.md`](../.github/signing/README.md)。

## 手动触发（API）

```bash
curl -X POST \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/yingo-server/OhGithubLost/actions/workflows/build.yml/dispatches \
  -d '{"ref":"main","inputs":{"channel":"beta","version_number":"2","version_name":"0.2.0-beta","release_notes":""}}'
```

## 产物矩阵（13 个目标）

Android（arm64-v8a / armeabi-v7a / x86_64 / universal APK / AAB）、
Windows（x64 / arm64*）、Linux（x64 / arm64*）、macOS（arm64 / x64）、iOS（device / simulator）。

带 * 的是 best-effort 目标：失败不阻塞发布（日志可见）。

## 故障排查

- **构建失败**：看 run 里哪条腿红；`best_effort` 腿失败不会拦发布；
- **发布任务没跑**：确认是 `workflow_dispatch` 触发、且 `build` 结果 = success；
- **SDK 组件下载损坏**（`ZipException: Archive is not a ZIP archive`）：
  重跑该 run；工作流已提前预装 CMake 降低概率；
- **APK 装不上**：旧包是否为随机证书时代的产物（先卸载）。

## 日志文件在哪（支持流程第一步）

- 目标路径：`/storage/emulated/0/logging/ogl-YYYY-MM-DD.log`（即 `sdcard/logging`）。
- 写不进去时**逐级回退**：应用外部目录（`Android/data/<pkg>/files/logging`，无需权限）
  → 应用文档目录 → 应用支持目录；实际路径与失败原因在**设置 → 关于 → 日志文件**里可见。
- 想让它写到 `sdcard/logging`（Android 11+）：在系统设置里给本应用授予"所有文件访问"，
  重启应用即可；Android ≤ 10 直接授权存储权限即可。
- 报错时请附：日志文件（或"复制全部日志"的内容）+ 版本号（关于页启动报告里）。
