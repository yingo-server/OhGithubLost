import 'dart:io';

/// 网络自检：解析 → 逐地址 TCP 连接，输出可读报告。
///
/// 用途：登录/列表出现「连接失败」（`NetException.kind == connection`）时，
/// 自动运行一次并把报告附进异常消息——把 errno 级真相写进日志与界面，
/// 不再让"连接失败"三个字背走全部信息。
///
/// 为什么需要它：设备网络可能对 `curl` 完全通畅，而 App 进程请求失败；
/// 自检在**同一进程、同一时刻**复现整条链路（DNS → TCP 逐地址），
/// 结果可直接区分：DNS 污染 / IPv6 黑洞 / 系统级应用联网拦截 / TLS 问题。
class NetSelfTest {
  const NetSelfTest._();

  static String? _cachedReport;
  static DateTime? _cachedAt;
  static String? _cachedHost;

  /// 带缓存的运行：`ttl` 内、**同一主机**重复调用直接返回上次报告
  /// （重试链路只自测一次，避免拖慢失败路径）。
  static Future<String> cachedOrRun(
    String host, {
    Duration ttl = const Duration(seconds: 30),
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final lastAt = _cachedAt;
    final last = _cachedReport;
    if (last != null &&
        lastAt != null &&
        _cachedHost == host &&
        DateTime.now().difference(lastAt) < ttl) {
      return last;
    }
    final report = await run(host, timeout: timeout);
    _cachedReport = report;
    _cachedAt = DateTime.now();
    _cachedHost = host;
    return report;
  }

  /// 运行自检。
  ///
  /// 返回单行报告，例如：
  /// `api.github.com:443 | DNS 2 个: 20.205.243.168(IPv4), 2606:... (IPv6) | TCP[20.205.243.168]: OK 350ms | TCP[2606:...]: 失败 12ms → SocketException: ...`
  static Future<String> run(
    String host, {
    int port = 443,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final lines = <String>['$host:$port'];
    List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(host).timeout(timeout);
    } on Object catch (error) {
      lines.add('DNS 解析失败: $error');
      return lines.join(' | ');
    }
    if (addresses.isEmpty) {
      lines.add('DNS 无结果');
      return lines.join(' | ');
    }
    final addrText = addresses
        .map((a) => '${a.address}(${a.type.name})')
        .join(', ');
    lines.add('DNS ${addresses.length} 个: $addrText');
    for (final address in addresses) {
      final sw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(address, port, timeout: timeout);
        sw.stop();
        lines.add('TCP[${address.address}]: OK ${sw.elapsedMilliseconds}ms');
        socket.destroy();
      } on Object catch (error) {
        sw.stop();
        lines.add(
          'TCP[${address.address}]: 失败 ${sw.elapsedMilliseconds}ms → $error',
        );
      }
    }
    return lines.join(' | ');
  }
}