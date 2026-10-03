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