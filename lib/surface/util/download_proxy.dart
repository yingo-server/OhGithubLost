/// L3 展示级 · 下载加速的**路由判定**（唯一定策处）。
///
/// ## 总开关与协议
/// 加速通道会把流量导向**应用之外的服务器**（内置通道是开发者自建，自定义
/// 通道是第三方），属于信任边界外的行为，因此必须由用户显式开启并同意协议
/// （`util/accel.dart`，含版本号）。本文件只做**纯判定**，不碰 IO，便于单测。
///
/// ## 两条族：能不能加速，取决于「能不能拿到签名地址」
/// | 族       | 资源                          | 能否加速 |
/// |----------|-------------------------------|---------|
/// | 签名族   | Release 附件 / Action 日志 / 产物 | ✅ 能（先本地解 302） |
/// | raw 族   | README 仓库内图片 / 仓库文件     | ❌ 不能 |
///
/// raw 族走 `raw.githubusercontent.com`，该端点**没有签名机制**：私有内容必须
/// 直接带 `Authorization` 头。交给代理就等于把令牌送出去，因此**一律不加速**
/// —— 这一格与「加速是否开启、选哪个通道」无关。
///
/// ## 为什么还要阈值
/// 小文件加速没有收益（延迟主导，多一跳反而更慢），却要多经一次第三方。
/// 阈值同时让「哪些内容会离开设备」的范围**可控可解释**。
library;

/// 大文件阈值：**小于等于 500KB 不加速**。
const int kOgLAccelMinBytes = 500 * 1024;

/// 资源族（决定能否加速）。
enum OgLAccelFamily {
  /// 签名族：Release 附件、Action 运行日志、Action 构建产物。
  /// 三者都是「302 → 短期签名 URL」结构，代理可用。
  signed,

  /// raw 族：README 仓库内图片、仓库文件下载。**一律不加速**。
  raw,
}

/// 判定某个资源走不走加速，并给出候选地址（按优先级）。
///
/// 返回列表的语义与下载器一致：**首项是首选，其余用于静默降级，末尾永远带一个
/// 直连兜底**。这样即便加速通道整体不可用，下载依然能完成。
///
/// - [prefixes] 为空（未启用、或未同意当前版本协议）→ 只返回直连；
/// - [family] 为 [OgLAccelFamily.raw] → 只返回直连；
/// - [bytes] 已知且 ≤ [kOgLAccelMinBytes] → 只返回直连；
/// - [bytes] 为 `null`（拿不到大小，如 Action 日志 zip）→ **加速**：
///   这类资源本就是大 blob，保守起见按「值得加速」处理。
List<String> ogLAccelCandidates({
  required String url,
  required List<String> prefixes,
  required OgLAccelFamily family,
  int? bytes,
}) {
  if (url.isEmpty) {
    return const <String>[];
  }
  final bool accelWanted = prefixes.isNotEmpty &&
      family == OgLAccelFamily.signed &&
      (bytes == null || bytes > kOgLAccelMinBytes);
  if (!accelWanted) {
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