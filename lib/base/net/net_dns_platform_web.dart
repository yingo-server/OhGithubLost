/// L1 底座级 · DNS 策略的**平台原语**（Web 侧实现）。
///
/// ## 为什么 Web 上只能"系统解析"
/// 浏览器**不向页面暴露裸 socket**（`fetch` / XHR 之外没有 UDP、没有 TCP），
/// 因此：
/// - **明文 DNS（UDP 53）做不了**：`dart:io` 的 `RawDatagramSocket` 在 Web 上
///   根本不存在，浏览器也没有替代 API；
/// - **DoH 也不能用来"接管解析"**：即便发得出 HTTPS 请求，浏览器在真正建立
///   连接时仍用它自己的解析器，页面拿到的 IP 无法回灌给 socket；
/// - 于是 Web 上的 DNS **只有一条路**：把域名原样交给浏览器，由它自己解析
///   （即 `NetDnsMode.system`）。
///
/// 这不是"降级实现"，而是能力事实。`DnsPlatform.supportsCustomDns = false`
/// 会让 `DnsService` 明确拒绝自定义路径（并在诊断里留痕），
/// 而不是假装切换成功、实际静默走系统解析。
///
/// ★ 安全红线：**绝不**为了"看起来能用"而在 Web 上改写请求去跟随重定向或
///   直接把解析结果编造出来——那会让上层以为自定义 DNS 生效了。
library;

/// 平台 DNS 原语（Web）。
class DnsPlatform {
  const DnsPlatform._();

  /// Web 上不支持自定义 DNS / DoH（见文件头注释）。
  static const bool supportsCustomDns = false;

  /// 系统解析：浏览器内部完成，页面拿不到 IP 列表。
  ///
  /// 返回 `[host]` 原样（而不是空列表）——语义是"解析结果是域名本身，
  /// 实际连接由浏览器的网络栈完成"。返回空会被上层判为解析失败。
  static Future<List<String>> lookup(String host) async => <String>[host];

  /// 是否为 IP 字面量（IPv4 / IPv6，含压缩写法）。
  ///
  /// 纯正则实现：Web 上没有 `InternetAddress`。判断标准与原生侧一致——
  /// `host:port` 这类输入必须被判为"不是 IP"。
  static bool isIpLiteral(String host) {
    if (_ipv4.hasMatch(host)) {
      return true;
    }
    if (!host.contains(':')) {
      return false;
    }
    if (!_ipv6Chars.hasMatch(host)) {
      return false;
    }
    final List<String> groups = host.split(':');
    if (groups.length > 8) {
      return false;
    }
    return groups.any((String group) => group.isNotEmpty);
  }

  /// 明文 UDP 交换：Web 上**不可用**（浏览器没有裸 socket）。
  ///
  /// 抛 [UnsupportedError] 而非静默返回 `null`：调用方若真走到这里，
  /// 应当看到"能力不存在"，而不是"超时"这种误导性的诊断。
  static Future<List<int>?> udpExchange(
    String serverIp,
    List<int> query, {
    required Duration timeout,
  }) async {
    throw UnsupportedError(
      'Web 平台不支持明文 UDP DNS（浏览器不提供裸 socket）',
    );
  }

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
  static final RegExp _ipv6Chars = RegExp(r'^[0-9a-fA-F:.]+$');
}
