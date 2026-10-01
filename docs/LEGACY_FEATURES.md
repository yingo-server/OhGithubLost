# 原项目功能矩阵与缺口清单（LEGACY_FEATURES）

> 目的：把老 App（GitHub King v3.9）的**全部业务功能**逐条落位到 OGL 的架构模块，
> 并明确"原项目没做到 / 做得薄弱"的部分，供决策是否补齐。
>
> **证据来源**（非猜测）：
> - `assets/KAold.zip` → `index.html`（541,582 字符，内联 JS 494,584 字符，5 段 script）
>   + `style.css`（154 KB）
> - 应用**自带的使用手册**（"全能使用手册 / 网站部署功能指南 / 令牌获取指南"）
> - 代码实证：58 个 `api.github.com` 端点、269 个 `function`、159 个箭头函数、
>   25 个 `localStorage` 键、内置类 `ConsistencyManager` / `UpdatedFilesManager` / `SimpleDB`

---

## 一、功能矩阵

图例：✅ 原项目已实现｜⚠️ 原项目实现薄弱｜❌ 原项目未实现｜🎯 OGL 落位模块

### A. 账号与认证

| 功能 | 原项目 | OGL 模块 |
| --- | --- | --- |
| 多账号（Token）管理、一键切换 | ✅ `github_accounts` / `active_github_account_id` | `domain.gh.auth` + `ix.session` |
| Token 获取引导（勾 `repo` scope） | ✅ 内置图文指南 | `surface.ui` 引导页 |
| 令牌安全存储 | ⚠️ 明文存 `localStorage` | `base.disk.vault`（Keystore/DPAPI） |
| 令牌失效处理 | ⚠️ 无重授权流程 | `domain.gh.auth` |
| OAuth Device Flow | ❌ | 待定（需外部 OAuth App） |

### B. 仓库列表与导航

| 功能 | 原项目 | OGL 模块 |
| --- | --- | --- |
| 我的仓库 / 星标仓库切换 | ✅ `user/repos`、`user/starred?per_page&page` | `domain.gh.repos` |
| 置顶（Pin） | ✅ `pinned_repos` | `ix.session` 偏好 |
| 列表缓存 + 时效 | ✅ `cached_repos` / `repos_cache_time` | `base.disk.cache`（D1–D7） |
| 视图模式：详细列表 / 网格 | ✅ `view_mode` | `surface.ui` + `ix.session` |
| 排序：名称 / 大小 / 时间 + 文件夹置顶 | ✅ `sort_by` / `directory_sort_priority` | `ix.session` |
| 面包屑导航、下拉刷新 | ✅ | `surface.ui` |
| 全局搜索：关键词 / `@用户` / `#文件名`（跨仓库深遍历）/ 链接直达 | ✅ | `domain.gh.search` + `ix` |
| 仓库内递归搜索 | ✅ | `domain.gh.search` |
| 搜索历史 | ✅ `search_history` | `ix.session` |

### C. 仓库级操作

| 功能 | 原项目 | OGL 模块 |
| --- | --- | --- |
| 新建仓库 | ✅ | `domain.gh.repos` |
| 仓库设置（改名 / 描述 / 公开私有） | ✅ | `domain.gh.repos` |
| 复刻 Fork | ✅ `repos/{full_name}/forks` | `domain.gh.repos` |
| 查看作者名下所有公开仓库 | ✅ `users/{username}/repos` | `domain.gh.repos` |
| 分支：创建（基于指定分支）/ 重命名 / 删除 | ✅ `branches/{name}/rename`、`git/refs/heads/{branch}` | `domain.gh.repos` |
| Releases：创建 / 传附件 / 预发布 / 删除 | ✅ `releases`、`releases/{id}` | `domain.gh.releases` |
| 整仓打包 ZIP + 加速下载 | ✅ | `domain.gh.repos` + `base.net.mirror` |
| 仓库详情（Star/Fork/Watch 统计、语言构成、README 预览） | ✅ `readme`、`marked.js` | `domain.gh.repos` |
| **移动文件跨目录** | ❌（只有重命名） | 建议补 |
| **提交历史 / 回滚 / diff 对比** | ❌（"历史"仅 3 处、"回滚/对比" 0 处） | 建议补 |

### D. 文件与目录

| 功能 | 原项目 | OGL 模块 |
| --- | --- | --- |
| 目录树浏览 | ✅ `git/trees/{branch}?recursive=1` | `domain.gh.contents` |
| 新建文件 / 文件夹、重命名、删除 | ✅ `contents/{path}` | `domain.gh.contents` |
| 在线编辑（base64 编解码） | ✅ | `domain.gh.contents` |
| **批量上传：一次提交多文件** | ✅ **已用 Git Data API**（`git/blobs` → `git/trees` → `git/commits` → `git/refs/heads`） | `domain.gh.contents` |
| 单文件下载 / 文件夹打包 ZIP | ✅ | `domain.gh.contents` |
| **在线解压 ZIP 并云端上传（含覆盖检测）** | ✅（`jszip`） | `domain.gh.contents` |
| 媒体预览：图片 / 视频 / 音频 | ✅ | `surface.ui` |
| 音频频谱彩蛋 | ✅ | `surface.ui`（E1–E3 打磨） |
| 编辑器：双指缩放字号 / 全屏 / 查找高亮 / 撤销 | ✅ | `surface.ui` |
| Markdown 渲染预览 | ✅（`marked.js`） | `surface.ui` |
| 不可编辑扩展名白名单 | ✅ `NON_EDITABLE_EXTS`（zip/rar/7z/pdf/doc/xls/exe/apk/ttf/db…） | `domain.ix` 规则表 |
| **递归树 `truncated` 处理** | ⚠️ 未见处理 | 必须补（否则大仓库静默少文件） |

### E. 批量操作

| 功能 | 原项目 | OGL 模块 |
| --- | --- | --- |
| 多选模式（全选 / 反选） | ✅ | `surface.ui` |
| 批量删除 | ✅ | `domain.gh.contents` |
| 批量下载（打包成一个 ZIP） | ✅ | `domain.gh.contents` |
| **批量前询问用户（通道选择）** | ❌ | **本轮的硬性要求，见第四节** |

### F. 网络与加速

| 功能 | 原项目 | OGL 模块 |
| --- | --- | --- |
| 代理源管理（增删 / 清空 / 启用） | ✅ `proxies`、`active_proxy_index`、`proxy_global_enable` | `base.net.mirror` + `ix.session` |
| 自动并发测速 → 切最低延迟 | ✅ `proxy_auto_select`、`last_proxy_check_time` | 建议补（见第五节） |
| 内置加速域名 | ✅ 实证：`ghproxy.net`、`gh.927223.xyz`、`ghfast.top`、`tvv.tw` | `base.net.mirror`（默认**关闭**） |
| 代理源远端订阅 | ✅ `raw.githubusercontent.com/rjdsq/github-king/main/代理/代理.txt` | 待定 |
| API 额度仪表盘（Core/Search + 重置时间） | ✅ `rate_limit` | `domain.gh.client` + `ix.notify` |
| 限流主动避让（剩余为 0 时不发请求） | ⚠️ 仅展示，未避让 | 必须补 |

### G. 建站 / GitHub Pages

| 功能 | 原项目 | OGL 模块 |
| --- | --- | --- |
| 发布主站（仅 `用户名.github.io`） | ✅ | `domain.gh.pages` |
| 发布项目站 | ✅ `pages` 接口 | `domain.gh.pages` |
| 自定义域名（写 `CNAME` + Cloudflare 引导） | ✅ | `domain.gh.pages` |
| 取消发布（主站改名为备份名下线，文件不丢） | ✅ | `domain.gh.pages` |
| 网站管理面板 | ✅ `sync_domain_cache` | `ix` + `surface.ui` |

### H. 一致性机制（原项目自研，可对照）

| 机制 | 原项目做法 | OGL 对应 |
| --- | --- | --- |
| 已更新文件 SHA 记录 | ✅ `UpdatedFilesManager`：`smart_sha_{repo}_{branch}_{path}` | D2 SHA 乐观锁 |
| 短时一致性缓冲 | ✅ `ConsistencyManager`：60s 窗口、同文件防重、路径标准化（忽略末尾 `/`） | D4 串行化 + 作用域规范化 |
| 本地列表乐观补丁 | ✅ add / delete / rename 三类补丁 | D5 写后失效 + 回读 |
| 大容量本地库 | ✅ `SimpleDB`（IndexedDB，5 GB，`lastAccessed` LRU） | `base.disk` + `prune/purge` |
| **冲突时阻止并询问用户** | ❌ 仅本地补丁，无服务端乐观锁、无 409/422 重试 | **D1–D7 已实现** |
| **提交/编辑的崩溃恢复** | ❌ | **D8 / D9 已实现** |
| **本地内容完整性校验** | ❌ | **已实现（长度 + SHA-256）** |

### I. 个性化

| 功能 | 原项目 | OGL 模块 |
| --- | --- | --- |
| 日夜模式 | ✅ `app_theme` | `surface.theme` |
| 云端插件 / 特效（下雨·樱花·极光·波纹·频谱） | ✅ `cloud_effects_data`、`cloud_effects_prefs` | `surface.mod` |
| 层级控制（顶层 / 背景特效） | ✅ | `surface.mod` |
| 长按菜单项自定义 | ✅ `context_menu_visibility` | `ix.session` |
| 编辑器最大化 | ✅ `editor-maximized` | `surface.ui` |
| 版本检查 | ✅ `CURRENT_VERSION = "3.9"`、`last_app_version` | `domain.gh.update` |

### J. 数据层

| 功能 | 原项目 | OGL |
| --- | --- | --- |
| 直接进入指定仓库 | ✅ `direct_entry_repos` | `ix.session` |
| 大容量本地库 | ✅ IndexedDB 5 GB | `base.disk` + `platform_io`（待补） |
| 搜索分页 | ✅ `state.publicSearchPerPage` | `domain.gh.search` |

---

## 二、原项目**完全没做**的 GitHub 能力（关键词零命中）

这些是"GitHub 客户端"的常见能力，老 App 一个都没有。**是否补齐请你定夺：**

| # | 能力 | 涉及 API | 我的建议 |
| --- | --- | --- | --- |
| 1 | **Issues**（列表 / 详情 / 评论 / 新建 / 关闭） | `/issues`、`/issues/{n}/comments` | 建议补（仓库管理刚需） |
| 2 | **Pull Requests**（列表 / 详情 / 文件变更 / 评论） | `/pulls`、`/pulls/{n}/files` | 建议补 |
| 3 | **提交历史 / 文件历史 / diff / 回滚** | `/commits`、`/compare/{a}...{b}` | **强烈建议补**（与"数据无价"直接相关） |
| 4 | **代码搜索**（服务端） | `/search/code` | 建议补（老项目只有本地遍历，慢） |
| 5 | **Star / Unstar / Watch 写操作** | `PUT/DELETE /user/starred/{repo}` | 建议补（老项目只能读星标） |
| 6 | **Gist** | `/gists` | 可选 |
| 7 | **Actions / Workflows**（查看运行状态） | `/actions/runs` | 可选 |
| 8 | **标签 / 里程碑 / 协作者 / 分支保护** | `/labels`、`/milestones`… | 可选 |
| 9 | **组织 / 团队仓库** | `/orgs/{org}/repos` | 建议补（多账号场景常有） |
| 10 | **大文件（>1MB）走 Blobs API** | `/git/blobs` | **建议补**（Contents API 对 >1MB 会返回 `content: ""`，静默失败） |
| 11 | **文件移动** | 需 delete + create 或 Git Data API | 建议补 |

---

## 三、原项目**做得薄弱**、OGL 必须修正的点

| # | 问题 | 后果 | OGL 处置 |
| --- | --- | --- | --- |
| 1 | 令牌明文存 `localStorage` | 令牌泄露 | 走 `DiskVault`（Keystore/DPAPI/libsecret） |
| 2 | 无服务端乐观锁，只有本地补丁 | **错位覆盖** | D1–D7（已实现） |
| 3 | 上传失败即丢，无队列 | 提交丢失 | D8（已实现） |
| 4 | 编辑中崩溃即丢 | 内容丢失 | D9（已实现） |
| 5 | 本地内容无完整性校验 | 坏内容被当真 | 长度 + SHA-256（已实现） |
| 6 | 未见 `trees?recursive=1` 的 `truncated` 处理 | 大仓库**静默缺文件** | 必须补 |
| 7 | 限流只展示不避让 | 触发封禁 | 必须补（剩余 0 不发请求） |
| 8 | 第三方加速域名硬编码且默认启用 | 流量被导向第三方 | 已改为 `MirrorChannel` **默认关闭** + 用户显式授权 |
| 9 | 无请求并发上限 | 批量操作易触发 Secondary Rate Limit | 建议补 |
| 10 | 列表排序/视图等状态全在 `localStorage` | 无法跨设备、易损坏 | 走 `DiskKv` + schema 版本 |

---

## 四、批量操作：**必须询问用户**（本轮新增硬性要求）

> 用户指令原文：*"在批量的时候可以询问用户这一点，因为有的用户他使用 GET 访问，他可能会有访问问题，比如说 DNS 污染等等。"*

**规则（写死进代码契约）：**

1. **批量操作（批量删除 / 批量下载 / 批量上传 / 整仓 ZIP / 在线解压）在发出第一个请求之前，
   必须弹出确认对话框**，列出：影响条目数、目标仓库/分支、预计请求数与体积。
2. 对话框**同时提供通道选择**：`直连` / `指定镜像` / `自动（并发测速选最低延迟）`。
   —— 这是针对 DNS 污染 / 网络受限地区的必要逃生通道。
3. 用户选择的通道**必须可记忆**（下次默认沿用），但**每次都仍要显示当前通道**，
   不得静默切换。
4. 批量过程中**必须可中断**，中断后已经完成的部分**不得回滚成半成品状态**：
   走 Git Data API 的多文件提交是**原子**的（要么全成要么全不成）；
   逐文件 PUT 的批量则必须记录进度到 D8 提交日志。
5. 批量结果必须给出**逐条结果清单**（成功 / 跳过 / 冲突 / 失败原因），不得只报"完成"。

**归属**：`domain.ix.ix_task`（编排）+ `base.net.mirror`（通道）+ `surface.ui`（对话框）。

---

## 五、建议补齐的网络能力（源于原项目的薄弱点）

| 能力 | 说明 |
| --- | --- |
| **通道并发测速** | 老项目有；OGL 的 `MirrorChannel` 目前只做顺序回退。建议补"并发测速 + 记忆最优" |
| **通道健康记忆** | 记录每个通道的成功/失败率与延迟，供下次优选 |
| **通道来源审计** | 订阅远端代理列表时，必须**显式告诉用户"这会把你的流量导向第三方"**并签名/白名单校验 |
| **限流避让** | 解析 `X-RateLimit-Remaining/Reset`；剩余为 0 时排队而非发请求 |
| **Secondary Rate Limit** | 403 + `retry-after` 单独识别（区别于权限 403） |

---

## 六、API 覆盖清单（L2 `domain/gh` 要交付的接口面）

> 目标：**把老项目的 58 个端点全覆盖，并补齐第二、三节的新端点**。

```
认证       GET  /user                                  当前用户
           GET  /rate_limit                            额度与重置
仓库       GET  /user/repos?per_page&sort=updated       我的仓库
           GET  /user/starred?per_page&page             星标仓库
           PUT/DELETE /user/starred/{owner}/{repo}      星标写（新增）
           GET  /users/{username}/repos                 他人仓库
           GET/PATCH /repos/{owner}/{repo}              详情 / 设置
           POST /user/repos                             新建仓库
           POST /repos/{owner}/{repo}/forks             复刻
           GET  /orgs/{org}/repos                       组织仓库（新增）
分支       GET  /repos/{o}/{r}/branches                 分支列表
           POST /repos/{o}/{r}/branches/{b}/rename      重命名
           POST/DELETE /repos/{o}/{r}/git/refs          创建 / 删除引用
内容       GET  /repos/{o}/{r}/contents/{path}?ref=     读取（含 sha）
           PUT  /repos/{o}/{r}/contents/{path}          写入（带 sha → 乐观锁）
           DELETE /repos/{o}/{r}/contents/{path}        删除
           GET  /repos/{o}/{r}/git/trees/{sha}?recursive=1   目录树（★ truncated）
           GET  /repos/{o}/{r}/git/blobs/{sha}          大文件（新增）
批量提交   POST /repos/{o}/{r}/git/blobs                单文件 blob
           POST /repos/{o}/{r}/git/trees                整树（含 base_tree）
           POST /repos/{o}/{r}/git/commits              一次提交
           PATCH /repos/{o}/{r}/git/refs/heads/{b}      移动引用（原子提交）
Releases   GET/POST /repos/{o}/{r}/releases
           GET/PATCH/DELETE /repos/{o}/{r}/releases/{id}
           POST /uploads.github.com/.../assets          上传附件
搜索       GET  /search/repositories?q=&page=&per_page=
           GET  /search/code?q=                         代码搜索（新增）
Pages      GET/POST/DELETE /repos/{o}/{r}/pages         查询 / 启用 / 关闭
           GET/PUT/DELETE /repos/{o}/{r}/contents/CNAME 自定义域名
历史       GET  /repos/{o}/{r}/commits                   提交历史（新增）
           GET  /repos/{o}/{r}/compare/{base}...{head}  差异（新增）
Issues     GET/POST /repos/{o}/{r}/issues                （新增·待决）
PR         GET  /repos/{o}/{r}/pulls                     （新增·待决）
README     GET  /repos/{o}/{r}/readme                    渲染
```

---

## 七、决策记录

### 7.1 已决策（用户 2026-Q4 拍板）

| # | 事项 | 决策 |
| --- | --- | --- |
| 1 | Issues | **补** |
| 2 | Pull Requests | **补** |
| 3 | 提交历史 / diff / 回滚 | **补** |
| 4 | 代码搜索 | **补** |
| 5 | Star / Unstar / Watch 写操作 | **补** |
| 6 | Gist | **补** |
| 7 | Actions / Workflows | **补** |
| 8 | 标签 / 里程碑 | **补** |
| 9 | 组织 / 团队仓库 | **补** |
| 7' | >1MB 大文件（Blobs API） | **必须补** |
| 8' | 文件移动 | **补** |
| 9' | OAuth Device Flow | 暂不做（需外部 OAuth App，后续可加） |
| 10 | 代理源远端订阅 | 做，但必须显式授权 + 来源提示 |
| 11 | 通道并发测速与记忆 | 补 |
| 12 | 强推是否允许"无条件覆盖" | 安全默认：**不允许** |

### 7.2 **能力冲突 → 交由用户选择**（总体原则）

当同一目标存在"更快但范围小"与"更全但更慢"的两条路径时，
**不允许程序替用户选**，必须暴露为可切换策略，并显示当前用的是哪条。

**原则**：
1. 两条路径都要实现，不得只做一条；
2. 策略可记忆，但**每次操作界面必须显示当前策略**；
3. 策略切换不得静默发生在后台（除非用户在设置里显式选了"自动"）。

### 7.3 首个冲突案例：**搜索策略**（用户明确要求）

用户原话：*"我认为本地搜索搜索快，但是你也可以加上交由用户选择。"*

| 策略 | 实现 | 优点 | 缺点 |
| --- | --- | --- | --- |
| **本地优先**（默认） | 在已缓存的仓库树里递归匹配（老项目做法） | **快**、不消耗配额、离线可用 | 只覆盖**已缓存**的仓库；新仓库要先把树拉下来 |
| **服务端** | `GET /search/code?q=` | 覆盖 GitHub 全站已索引代码 | 慢、**消耗 Search 配额**（10 次/分钟）、需认证 |
| **自动** | 本地命中 ≥ N 条则用本地，否则回退服务端 | 兼顾 | 结果来源不稳定，需明确标注 |

**实现要求**：`domain.gh.search` 必须提供 `SearchStrategy { local, remote, auto }`，
结果对象携带 `source` 字段（`local` / `remote`），UI 必须显示结果来自哪一侧。

### 7.4 其他已知冲突点（同样交由用户选择）

| 冲突 | 选项 |
| --- | --- |
| 批量提交方式 | `Git Data API`（一次原子提交，快） / `逐文件 PUT`（可逐条回滚，慢） |
| 下载通道 | `直连` / `指定镜像` / `自动测速`（见第四节） |
| 大文件上传 | `Contents API`（<1MB） / `Blobs API`（≥1MB，需多次请求）——**程序按体积自动选，但要在进度里说明** |
| 缓存策略 | `内存优先`（最快，重启失效） / `磁盘优先`（重启可恢复） |
| 目录树获取 | `recursive=1`（一次拿全，可能 `truncated`） / 逐层懒加载（多次请求，永不截断） |

*未决策项在实现前保持"不做"，决策后回填本文并进 `ROADMAP`。*