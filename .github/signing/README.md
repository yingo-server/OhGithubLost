# OGL 固定 Android 签名证书

## 这是什么

本目录内置 OGL 的**固定 Android 签名证书**（JKS，别名 `androiddebugkey`）。
`ogl-debug.keystore.b64` 是证书本体的 base64 编码（文本格式，便于入库与传输）。

## 为什么需要它

Flutter 模板默认用「构建机随机生成的 debug keystore」给 release 包签名：

- 每台 runner / 每次全新缓存，证书都不同；
- 表现：新版 APK 覆盖安装旧版时报**"应用签名不一致"**，必须先卸载再装。

固定证书后：**所有构建产物同一签名，可直接覆盖安装。**

## 使用方式

CI 在构建 Android 产物前会执行（见 `.github/workflows/build.yml`）：

```bash
mkdir -p "$HOME/.android"
base64 -d .github/signing/ogl-debug.keystore.b64 > "$HOME/.android/debug.keystore"
```

## 证书信息

| 项 | 值 |
| --- | --- |
| 别名 | `androiddebugkey` |
| 算法 | RSA 2048 / SHA256withRSA |
| 有效期 | 2026-10-01 → 2056-09-23 |
| storepass / keypass | `android` / `android` |
| SHA1 | `95:AA:1A:00:06:22:47:EC:10:B8:71:09:B6:58:40:65:6B:EA:23:C6` |
| SHA256 | `7F:55:58:68:0C:61:2F:32:46:88:82:D5:CB:5C:7B:9E:14:58:6E:5C:19:03:46:03:6B:6F:58:25:08:BA:73:4D` |

## 安全说明

- 该证书用于**个人分发**场景（与 debug 签名同级信任），不含任何商店发布密钥；
- 如需上架，请单独生成正式发布密钥（且不要入库）；
- **一旦证书丢失，所有存量安装包将永远无法再收到可覆盖安装的升级** ——
  故该文件必须长期保留在仓库中（即使更换 CI 平台）。

---

## Ed25519 发布密钥（引导清单签名）

| 项 | 值 |
| --- | --- |
| 私钥 | `ogl-boot-ed25519.key`（32 字节 seed 的 base64） |
| 公钥（内嵌应用） | `lib/kernel/boot/release_trust_root.dart` · `3sPk7i1MNSkRE1VCzgpli7e/zWJxrnPWazVS7cfGcjc=` |
| 用途 | 给引导清单（Boot Manifest）签名；应用启动时用内嵌公钥验签，签错 = 拒绝启动 |
| 生成与签名 | `tool/boot_manifest.py`（CI 的 `manifest` 任务；本地可手工跑演练） |

> **轮换红线**：公钥内嵌在历史版本里。换密钥 = 旧版本无法验证新清单 →
> 必须：① 先生成新密钥对；② 公钥升级随新版本发布；③ 过渡期保留旧公钥/双签。
> 私钥丢失 = 无法再发布"能通过启动校验"的新版本（只能再走一次轮换流程）。
