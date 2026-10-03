/// L3 展示级 · Release 下载加速（唯一实现处）。
///
/// ## 为什么要开关
/// 加速通道会把附件流量导向**第三方主机** —— 属于第三方信任边界，因此必须由
/// 用户在设置里显式同意后才启用（默认关闭）。它只作用于 **Release 附件**；
/// 仓库文件 / Gist 等其它下载不经过它。
///
/// ## 为什么不把地址写进界面
/// 通道地址是实现细节，**不允许出现在界面文案或设置项描述里**：它既无助于
/// 用户决策，也会把第三方依赖固化成"产品文案"。故前缀在这里是私有常量。
library;

/// 加速通道前缀（仅本实现内可见）。
const String _kReleaseAccelPrefix = 'http://server.344977.xyz:5000/';

/// 解析 Release 附件的实际下载地址。
///
/// [enabled] 为假（设置里关闭）时原样返回直连地址；已是加速地址、或非 http(s)
/// 地址时也原样返回（避免二次加前缀）。
String ogLReleaseDownloadUrl(String url, {required bool enabled}) {
  if (!enabled || url.isEmpty) {
    return url;
  }
  if (url.startsWith(_kReleaseAccelPrefix)) {
    return url;
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return url;
  }
  return '$_kReleaseAccelPrefix$url';
}