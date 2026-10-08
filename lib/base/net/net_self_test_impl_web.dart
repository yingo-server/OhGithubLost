/// L1 底座级 · 网络自检的**平台实现**（Web）。
///
/// ## 为什么 Web 上只有"有限自检"
/// 原生自检的价值在于把链路分层定位：DNS 解析 → 逐地址 TCP → 裸 TLS →
/// `HttpClient`。但 Web 上四层里有三层根本不存在：
/// - 页面拿不到 DNS 解析结果（浏览器内部完成）；
/// - 不能发起裸 TCP 连接；
/// - 不能自己做 TLS 握手。
///
/// 所以 Web 版只做**唯一能做的事**：发一次 HTTP 请求，看浏览器能否到达。
/// 报告里**明确标注**"web 端不包含 DNS / TCP / TLS 探测"，
/// 以免读者把它当成原生那份完整报告。
///
/// 注：浏览器受同源策略约束，跨域且未开放 CORS 的主机会报失败 ——
/// 那是"浏览器不允许"，不是"网络不通"，报告里如实写清。
library;

import 'package:http/http.dart' as http;

/// 平台自检实现（Web）。
abstract final class NetSelfTestImpl {
  /// 运行有限自检，返回单行报告。
  static Future<String> run(
    String host, {
    int port = 443,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final lines = <String>[
      '$host:$port',
      // 如实标注能力边界：本报告**不含** DNS / UDP / TCP 探测。
      '有限自检（web 端不包含 DNS / TCP / TLS 探测）',
    ];
    final sw = Stopwatch()..start();
    final http.Client client = http.Client();
    try {
      final scheme = port == 80 ? 'http' : 'https';
      final http.Response response = await client
          .get(Uri.parse('$scheme://$host/'), headers: <String, String>{
        'accept': '*/*',
      }).timeout(timeout);
      sw.stop();
      lines.add(
        'HTTP(浏览器): ${response.statusCode} · ${sw.elapsedMilliseconds}ms',
      );
    } on Object catch (error) {
      sw.stop();
      // 失败原因里同时包含"网络不可达"与"被 CORS 拦下"两种情况——
      // 浏览器不向页面区分它们，所以**不编造**结论，只如实转述。
      lines.add('HTTP(浏览器): 失败 ${sw.elapsedMilliseconds}ms → $error');
    } finally {
      client.close();
    }
    return lines.join(' | ');
  }
}
