# 网络连接总览

> 目的：回答两个问题 —— **本项目一共往哪些地方发请求**，以及**每一类 GitHub
> 资源到底用哪条路取**。写这份文档的起因是排查"私有仓库图片/预览打不开"，
> 过程中发现同一个缺陷在两个控件里各有一份。
>
> 维护纪律：本文件点到的每个符号都必须真实存在。改名时请一并更新这里，
> 否则这份文档会从资产变成误导源。

## 一、出口清单（全项目往哪些主机发请求）

| 目的地 | 何时 | 是否带令牌 | 代码位置 |
|---|---|---|---|
| `api.github.com` | 所有仓库元数据、文件内容 | ✅ Bearer | `lib/domain/gh/gh_client.dart` |
| `raw.githubusercontent.com` | raw 族加速时、仓库内图片直链 | 私有时必须带 | `SurfaceBridge.planRepoFileDownload` · `lib/surface/surface_bridge.dart` |
| `github.com` | 令牌校验、OAuth Device Flow | OAuth client_id | `lib/domain/gh/gh_client.dart` |
| `objects.githubusercontent.com` | **Release 附件 / Action 产物 / 日志下载** | ❌ 只用签名 | `OgLIxPaths.releaseMediaDownload` · `lib/domain/ix/ix_paths.dart` |
| DoH 解析器 | DNS 被污染时的加密解析 | ❌ | `DnsService.resolve` · `lib/base/net/net_dns.dart` |
| 用户自建加速通道 | 用户在设置里打开加速后 | ⚠️ 见下节 | `activeAccelPrefixes` · `lib/surface/settings.dart` |
| 更新/站点 | Release 列表、changed 站点 | ❌ | 走 `ghClient()` 匿名入口 |

**传输层**：`NetTransport`（抽象）→ `ResilientTransport`（重试 + 镜像降级 +
主机冷却 + DoH 回落），`lib/base/net/net_transport.dart`。
分片下载用同一传输 NMR/ spurious 由 `OgLRangeDownloader` 实现
（`lib/base/net/range_download.dart`）。

## 二、资源取法（这是本文档的重点）

### 2.1 签名族 —— 公开与私有**都能**加速

Release 附件 / Action 运行日志 / Action 构建产物，三者结构相同：
先拿 API 地址（`IxDownloadSource.api`）→ 本地解 302 拿到带签名的直连地址，
目的在于**令牌不出设备**——代理拿到的是一个短期、无令牌的 URL，
私有仓库同样能解出签名，所以这一类**不受仓库公私限制**。

签名解出：`IxPresign.resolve(url)` → `IxPresignResult`，
`lib/domain/ix/ix_presign.dart`（类型经 `lib/surface/types.dart` 转出）。

### 2.2 raw 族 —— 只有公开仓库能加速

仓库文件 / README 仓库内图片。路由判定：`ogLAccelCandidates`
（`lib/surface/util/download_proxy.dart`），两类返回值：

| | 加速关 / 私有 | 加速开 + 公开且 ≥ 500 KB |
|---|---|---|
| 仓库文件预览 | Contents API + Bearer | raw + 加速通道 |
| README 图 | Contents API + Bearer | raw + 代理前缀（`imageProxyPrefix`） |

**私有仓库的 raw 一律不加速**，理由实测如下：

- 匿名访问 raw → **404**
- `?token=<PAT>` 形式 → **404**（早已废弃）
- 带 `Authorization` 头 → 200，这是唯一可行的方式
- 实测内置通道会**把 Authorization 头原样转发**给 GitHub
  （带令牌 200 / 不带 404）→ 交给代理即送令牌

所以约束是硬的：宁可私有仓库慢一点，也不能把用户的令牌交出去。

### 2.3 README 图片与 1 MB 上限

GitHub 的 Contents API 对 > 1 MB 的文件不返回内容（返回 200 且 body 为空），
因此仓库内图片**无论公私都只能走 raw**。公开仓库可把 raw 交给加速通道
（代理前缀经 `ReadmeView.imageProxyPrefix` 传入）；
私有仓库则必须带 `Authorization` 头，不交给代理。

## 三、连接怎么被发出去

```
UI ─→ DomainBridge ─→ GhClient (429 重试 / 403 冷却) ─→ ghNetTransport() ─→ ResilientTransport
                                                                              ├─ DoH 解析
                                                                              └─ 镜像降级
```

DNS 层另有缓存与探针（见 `net_dns.dart` 的 `DnsCache`、`DnsProbe`）。

## 四、复现命令（排查时用）

```bash
TOKEN=<PAT>

# 1) raw 是否支持断点续传（公开应 206）
curl -s -o /dev/null -w '%{http_code}\n' -H "Range: bytes=0-99" \
     https://raw.githubusercontent.com/<o>/<r>/HEAD/README.md

# 2) 私有仓库的 raw：匿名应 404，带令牌才 200
curl -s -o /dev/null -w '%{http_code}\n' \
     https://raw.githubusercontent.com/<o>/<r>/HEAD/<path>
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" \
     https://raw.githubusercontent.com/<o>/<r>/HEAD/<path>

# 3) 签名族：应 302 且 Location 含 X-Amz-Signature
curl -sI -H "Authorization: Bearer $TOKEN" -H "Accept: application/octet-stream" \
     "https://api.github.com/repos/<o>/<r>/releases/assets/<asset-id>"
```
