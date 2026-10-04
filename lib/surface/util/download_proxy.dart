/// L3 展示级 · Release 下载加速（唯一实现处）。
///
/// ## 为什么要有开关与协议
/// 加速通道会把附件流量导向**应用之外的服务器**（内置通道是开发者自建，
/// 自定义通道是第三方）。这属于信任边界外的行为，因此必须：
/// 1. 由用户显式开启总开关；
/// 2. 已同意对应协议（`util/accel.dart` 里定义，含版本号）。
///
/// 它只作用于 **Release 附件**；仓库文件 / Gist 等其它下载不经过它。
///
/// ## 通道选择
/// 通道模型（内置 + 自定义多通道 / 单开关）在 `util/accel.dart`，
/// 生效前缀由 `OgLSettings.activeAccelPrefix` 计算后传入本函数——
/// 本文件保持**纯函数**，便于单测。
library;

/// 解析 Release 附件的实际下载地址。
///
/// [accelBase] 为 `null` / 空表示**走直连**（加速关闭或未同意协议）；
/// 已是加速地址、或非 http(s) 地址时原样返回（避免二次加前缀）。
/// 解析 Release 附件的**候选下载地址（按优先级）**。
///
/// [accelBases] 是加速前缀链（空 = 直接走直连）。返回列表：
/// 首项 = 首选地址，其后是**静默降级**用的备选（同一原始 URL 换前缀），
/// **最后一定带一个直连兜底**。
List<String> ogLReleaseDownloadUrls(String url, List<String> accelBases) {
  if (url.isEmpty) {
    return const <String>[];
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return <String>[url];
  }
  final List<String> out = <String>[];
  for (final String base in accelBases) {
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

String ogLReleaseDownloadUrl(String url, {String? accelBase}) {
  if (accelBase == null || accelBase.isEmpty || url.isEmpty) {
    return url;
  }
  if (url.startsWith(accelBase)) {
    return url;
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return url;
  }
  return '$accelBase$url';
}