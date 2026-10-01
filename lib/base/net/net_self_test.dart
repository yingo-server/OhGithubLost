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

  /// 单类型解析（**绝不抛**：失败以文本返回，便于日志直读）。
  static Future<({List<InternetAddress> addrs, String text})> _lookupSafe(
    String host,
    InternetAddressType type,
    Duration timeout,
  ) async {
    try {
      final addrs =
          await InternetAddress.lookup(host, type: type).timeout(timeout);
      return (
        addrs: addrs,
        text: addrs.isEmpty ? '空' : addrs.map((a) => a.address).join(','),
      );
    } on Object catch (error) {
      return (addrs: const <InternetAddress>[], text: '失败($error)');
    }
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
    final v4 = await _lookupSafe(host, InternetAddressType.IPv4, timeout);
    final v6 = await _lookupSafe(host, InternetAddressType.IPv6, timeout);
    lines.add('DNS-A(IPv4): ${v4.text}');
    lines.add('DNS-AAAA(IPv6): ${v6.text}');
    final addresses = <InternetAddress>[...v4.addrs, ...v6.addrs];
    if (addresses.isEmpty) {
      return lines.join(' | ');
    }
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
    // ── 追加：两条"原生栈"探针（定位故障层：TLS？HttpClient？）──
    final ipv4s =
        v4.addrs.where((a) => a.type == InternetAddressType.IPv4).toList();
    if (ipv4s.isNotEmpty) {
      final addr = ipv4s.first;
      final swT = Stopwatch()..start();
      try {
        final raw = await Socket.connect(addr, port, timeout: timeout);
        final tls = await SecureSocket.secure(raw, host: host).timeout(timeout);
        tls.write(
          'GET /zen HTTP/1.1\r\nHost: $host\r\n'
          'User-Agent: ogl-selftest\r\n'
          'accept: application/vnd.github+json\r\n'
          'x-github-api-version: 2022-11-28\r\n'
          'Connection: close\r\n\r\n',
        );
        final first = await tls.first.timeout(timeout);
        swT.stop();
        final line1 = String.fromCharCodes(first).split('\r\n').first;
        lines.add('TLS(原生): $line1 · ${swT.elapsedMilliseconds}ms');
        await tls.close();
      } on Object catch (error) {
        swT.stop();
        lines.add('TLS(原生): 失败 ${swT.elapsedMilliseconds}ms → $error');
      }
      final swH = Stopwatch()..start();
      try {
        final hc = HttpClient()..connectionTimeout = timeout;
        final req =
            await hc.getUrl(Uri.parse('https://$host/zen')).timeout(timeout);
        final resp = await req.close().timeout(timeout);
        swH.stop();
        lines.add(
          'HTTP(dart原生): ${resp.statusCode} · ${swH.elapsedMilliseconds}ms',
        );
        hc.close(force: true);
      } on Object catch (error) {
        swH.stop();
        lines.add('HTTP(dart原生): 失败 ${swH.elapsedMilliseconds}ms → $error');
      }
    }
    return lines.join(' | ');
  }
}