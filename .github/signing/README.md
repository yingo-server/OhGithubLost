# OGL 密钥与签名说明（v2 · 2026-10-02）

## 总览：本目录**不再存放任何私钥**

所有私钥均存放于 GitHub Actions Secrets
（仓库 → Settings → Secrets and variables → Actions），仓库里只保留这份说明：

| Secret 名 | 内容 | 用途 |
| --- | --- | --- |
| `OGL_BOOT_KEY` | Ed25519 私钥（32 字节 seed 的 base64） | 给引导清单（Boot Manifest）签名 |
| `OGL_ANDROID_KEYSTORE` | Android 固定签名证书（JKS 的 base64 文本） | 给 Android 产物签名（可覆盖安装） |

CI 在构建时把密钥**临时还原**到 runner（随 runner 销毁，不落任何仓库）；
本地如需演练，见 §3「本地还原」。

---

## 1. Android 固定签名证书（可覆盖安装）

**为什么需要**：Flutter 模板默认用构建机随机生成的 debug keystore 签 release 包 ——
每台 runner 的证书都不同，导致新版 APK 无法覆盖安装旧版（系统报"应用签名不一致"）。
固定证书后：**所有构建产物同一签名，可直接覆盖安装。**

### 当前证书（v2 · 2026-10-02 起）

| 项 | 值 |
| --- | --- |
| 别名 | `androiddebugkey` |
| 算法 | RSA 2048 / SHA256withRSA |
| 有效期 | 2026-10-02 → 2056-09-23（10957 天） |
| storepass / keypass | `android` / `android`（"个人分发"低信任场景） |
| SHA256 | `3F:CA:DB:03:95:4D:74:A9:2B:73:6C:E6:69:69:C5:1F:B1:D9:05:2F:1C:CB:C6:FB:84:FD:00:08:0E:33:AB:0B` |

### ⚠️ 证书轮换的一次性影响

- v1（2026-10-01 → 2026-10-02）已被 **v2 全量替换**；
- 旧证书签名的存量安装包（v0.1.0 / v0.2.0-beta / v1.0.0）**无法被 v2 签名的新包覆盖安装** ——
  安装 v1.1.0+ 前需**先卸载旧版一次**，之后即可正常覆盖升级；
- v1 证书已归档在仓库之外，不再参与任何构建。

---

## 2. Ed25519 引导签名密钥（Boot Manifest）

| 项 | 值 |
| --- | --- |
| 私钥 | 仅存于 Secret `OGL_BOOT_KEY`（32 字节 seed 的 base64），**不落仓库** |
| 公钥（内嵌应用） | `lib/kernel/boot/release_trust_root.dart` · `Qaojo9YuV4nQoNbyfDiwoYofhUg/sPrKhOkDyW5DQ8s=`（v2） |
| 用途 | 给引导清单（Boot Manifest）签名；应用启动时用内嵌公钥验签，签错 = 拒绝启动 |
| 生成与签名 | `tool/boot_manifest.py`（CI 的 `manifest` 任务；本地可手工跑演练） |

### 密钥轮换记录

- **v1**（2026-10-01 → 2026-10-02）：已退役；旧私钥仅作档案馆藏（仓库之外），不再使用；
- **v2**（2026-10-02 起）：当前有效。本次完成"全量轮换"：
  CI 改为从 Secret 还原，仓库内所有私钥文件被移除。

### 防脱节护栏

`test/kernel/boot_release_chain_test.dart` 用**固定签名样本**
（`test/kernel/fixtures/release_key_signed_manifest.json`，由发布私钥签出）
验证「内嵌公钥可验发布签名」。**轮换密钥时必须同步更新该样本**，否则 CI 变红。

> **轮换红线（仍然有效）**：公钥内嵌在历史版本与已发布安装包里。
> 轮换 = 新版本使用新公钥 + 新签名；历史版本各自自洽（清单编译期内嵌），
> 无需也无法"追溯升级"。外部签名物（Mod / 主题清单）需用新钥重签。
> 私钥丢失 = 无法再发布"能通过启动校验"的新版本（只能再走一次轮换流程）。

---

## 3. 本地还原（演练 / 排障）

```bash
# ① 引导签名私钥（本机需先有同名环境变量，或手动粘贴）
printf '%s' "$OGL_BOOT_KEY" > /tmp/ogl-boot-ed25519.key
python3 tool/boot_manifest.py --key /tmp/ogl-boot-ed25519.key --build-id local-test

# ② Android 证书
printf '%s' "$OGL_ANDROID_KEYSTORE" | base64 -d > ~/.android/debug.keystore
keytool -list -keystore ~/.android/debug.keystore -storepass android
```

密钥的**带外备份**（不进仓库、不进 git 历史）：由维护者单独保管。

---

## 4. 与历史说明的关系

旧版 README 描述"私钥随仓库保管"的做法已**废止**（公开仓库不适合存放任何私钥）。
本文件为现行唯一口径。
