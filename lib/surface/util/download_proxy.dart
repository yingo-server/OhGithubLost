/// L3 展示级 · Release 下载代理（唯一实现处）。
///
/// 内置代理仅用于 **Release 附件**：
/// - 其它类型的文件是否会经过该代理尚未验证，因此不套用；
/// - 已是代理地址、或非 http(s) 地址时原样返回，避免二次加前缀。
library;

/// 内置代理前缀。
const String kOgLReleaseProxyPrefix = 'http://server.344977.xyz:5000/';

/// 给 Release 附件地址套上代理前缀。
String ogLProxiedReleaseUrl(String url) {
  if (url.isEmpty) {
    return url;
  }
  if (url.startsWith(kOgLReleaseProxyPrefix)) {
    return url;
  }
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    return url;
  }
  return '$kOgLReleaseProxyPrefix$url';
}