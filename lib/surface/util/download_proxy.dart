/// L3 展示级 · 下载加速的**路由判定**（唯一定策处）。
///
/// ## 总开关与协议
/// 加速通道会把流量导向**应用之外的服务器**（内置通道是开发者自建，自定义
/// 通道是第三方），属于信任边界外的行为，因此必须由用户显式开启并同意协议
/// （`util/accel.dart`，含版本号）。本文件只做**纯判定**，不碰 IO，便于单测。
///
/// ## 两条族：能不能加速，取决于「怎么拿到内容」
/// | 族       | 资源                              | 加速条件 |
/// |----------|-----------------------------------|---------|
/// | 签名族   | Release 附件 / Action 日志 / 产物 | 大小未知或超过阈值 |
/// | raw 族   | 仓库文件 / README 仓库内图片      | **仅内置通道 + 公开仓库** |
///
/// raw 族走 `raw.githubusercontent.com`，该端点**没有签名机制**：私有内容必须
/// 直接带 `Authorization` 头。交给代理就等于把令牌送出去 —— 所以**私有仓库的
/// raw 内容永远不加速**，只能走 API 带认证（与「加速开关」无关，是硬约束）。
///
/// 反过来，**不加速时仓库文件也必须走 API**
/// （`/repos/{o}/{r}/contents/{path}` + `Accept: application/vnd.github.raw`）：
/// raw 直链对私有仓库根本取不到内容，而该 API 端点带上令牌就可用，且实测
/// 支持 Range（多连接分片不受影响）。
///
/// ## 为什么还要阈值
/// 小文件加速没有收益（延迟主导，多一跳反而更慢），却要多经一次第三方。
/// 阈值同时让「哪些内容会离开设备」的范围**可控可解释**。
library;

/// 大文件阈值：**小于等于 500KB 不加速**。
const int kOgLAccelMinBytes = 500 * 1024;

/// 资源族（决定能否加速）。
enum OgLAccelFamily {
  /// **签名族**：Release 附件、Action 运行日志、Action 构建产物。
  ///
  /// 三者都是「302 → 短期签名 URL」结构，且**公开与私有仓库都能取到签名**。
  /// 因此这一类始终按「先本地解出签名地址，再把签名地址交给加速通道」处理：
  /// 令牌不出设备，代理拿到的是一个**短期、无令牌**的地址。
  signed,

  /// **raw 族**（README 仓库内图片、仓库文件）：只有**公开仓库**能加速。
  ///
  /// 私有仓库**并非没有加速需求，而是没有加速手段**：raw 端点没有签名机制
  /// （实测：匿名 404；`?token=` 查询参数形式已被废弃、同样 404），
  /// 要让它返回内容就必须带上 `Authorization` 头，而带头的 URL 一旦交给代理
  /// 就等于把令牌送出去。所以私有仓库的 raw **一律不加速**，与开关无关。
  ///
  /// 这不是保守，是硬约束 —— 宁可私有仓库慢一点，也不能把用户的令牌交出去。
  raw,
}

/// 判定某个资源走不走加速，并给出候选地址（按优先级）。
///
/// 返回列表的语义与下载器一致：**首项是首选，其余用于静默降级，末尾永远带一个
/// 直连兜底**。这样即便加速通道整体不可用，下载依然能完成。
///
/// ## 判定规则
/// - [prefixes] 为空（未启用、或未同意当前版本协议）→ 只返回直连；
/// - **签名族**（Release 附件 / Action 日志 / 产物）：`bytes` 未知或超过
///   [kOgLAccelMinBytes] 即加速。未知时按「值得加速」处理 —— 这类资源本就是
///   大 blob，且大小要先下才知道；
/// - **raw 族**（仓库文件 / README 仓库内图片）：默认只有**内置通道 + 公开仓库**
///   才加速。私有仓库需要用户先**知情接受**「令牌会交给第三方代理」
///   （[privateAccelAccepted]），才会走加速；否则一律不加速。
///   理由：raw 端点没有签名机制，私有内容的 raw 必须带 `Authorization`，
///   交给代理就等于把令牌送出去 —— 所以默认不送，接受后才送。
/// - `bytes` 已知且 ≤ 阈值 → 不加速（小文件加速没有收益，却要多经一次第三方）。
List<String> ogLAccelCandidates({
  required String url,
  required List<String> prefixes,
  required OgLAccelFamily family,
  int? bytes,
  bool builtinChannel = true,
  bool repoPrivate = false,
  /// [privateAccelAccepted]：私有仓库 + raw 族时，用户是否已**知情接受**
  /// 「令牌会交给第三方代理」。默认 `false` → 不加速（令牌不出设备）。
  /// 该开关由用户在警告弹窗里显式确认，并可在加速设置页改回
  /// （改回 = 不再询问**且**不再加速，而不是"别问了但照旧送"）。
  bool privateAccelAccepted = false,
}) {
  if (url.isEmpty) {
    return const <String>[];
  }
  // ★ 非 http(s) 一律原样返回：加速前缀拼到 `file://` 之类地址上只会产出
  //   垃圾，且这里不做检查就等于把「协议白名单」的责任推给调用方。
  //   入队口另有 `ogLAssertDownloadUrl` 兜底，但**两层都要有**。
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return <String>[url];
  }
  final bool bigEnough = bytes == null || bytes > kOgLAccelMinBytes;
  // 私有 + raw：只有在用户知情接受后才放行（否则令牌绝不出设备）。
  final bool privateOk = !repoPrivate || privateAccelAccepted;
  final bool familyOk =
      family == OgLAccelFamily.signed || (builtinChannel && privateOk);
  if (prefixes.isEmpty || !familyOk || !bigEnough) {
    return <String>[url];
  }
  final List<String> out = <String>[];
  for (final String base in prefixes) {
    // 空前缀、或已经是加速地址（避免二次加前缀）。
    if (base.isEmpty || url.startsWith(base)) {
      continue;
    }
    final String candidate = '$base$url';
    if (!out.contains(candidate)) {
      out.add(candidate);
    }
  }
  if (!out.contains(url)) {
    out.add(url); // 直连：永远的最后底线。
  }
  return out;
}