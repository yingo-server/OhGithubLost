/// L1 底座级 · 网络连接：基于 `package:http` 的**浏览器传输实现**。
///
/// ## 为什么 Web 不能用 `IoNetTransport`
/// 浏览器里没有 `dart:io`（`HttpClient` / `Socket` / TLS 全都不存在），
/// 因此 Web 侧改用 `package:http` 自带的 [BrowserClient]：它底下是浏览器的
/// `fetch`/XHR，能自动带上 Cookie、自动跟随重定向、自动走系统解析。
///
/// ## 契约必须一致
/// **所有**底层异常都要翻译成 [NetException]（全项目同一约定）：
/// 上层（重试 / 镜像 / 提示）只认识它，不允许让 `ClientException` 直接漏上去。
///
/// ## 哪些原生策略在 Web 上不适用（如实说明，不假装支持）
/// - `persistentConnection = false` —— 无意义：连接复用完全由浏览器管理，
///   页面既看不到连接，也无法要求"每请求新开一条"；
/// - `maxConnectionsPerHost` / `idleTimeout` —— 无意义：没有连接池 API；
/// - 自定义 DNS（`connectionFactory` 直连 IP）—— 做不到：见
///   `net_dns_platform_web.dart`，浏览器不给裸 socket；
/// - 区分 TLS 证书错误的专门分类 —— 做不到：浏览器不把证书细节交给页面，
///   这类失败一律归入"连接失败"（[NetErrorKind.connection]）；
/// - `maxRedirects` 精确控制 —— 只能由浏览器默认策略处理（通常 20 跳）。
///
/// 另外：`User-Agent` / `Cookie` / `Referer` 等属于浏览器的**禁止头**，
/// 页面设置它们会被静默忽略（浏览器不允许脚本伪造这些身份信息）。
library;

import 'dart:async';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

import 'net_dns.dart';
import 'net_transport.dart';
import 'net_types.dart';

/// 装配用工厂：Web 侧返回 [WebNetTransport]。
///
/// 由 `net_bridge.dart` 直接装配选用——装配代码不必自己判断平台。
NetTransport createPlatformNetTransport(
  DnsService? dns, {
  Duration connectTimeout = const Duration(seconds: 15),
}) =>
    WebNetTransport(dns: dns, connectTimeout: connectTimeout);

/// 基于浏览器 `fetch` 的传输实现（Flutter Web）。
class WebNetTransport implements NetTransport {
  /// 创建传输。
  ///
  /// [dns] 仅用于在连接类失败时清缓存（与原生侧一致的"下次重试重新解析"），
  /// Web 上不做自定义解析（见文件头说明）。
  /// [client] 仅供测试注入。
  WebNetTransport({
    DnsService? dns,
    http.Client? client,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 60),
  })  : _dns = dns,
        _client = client ?? BrowserClient();

  final DnsService? _dns;
  final http.Client _client;

  /// 连接（首字节）超时。浏览器不区分"连接"与"接收"，这里是整段的上限。
  final Duration connectTimeout;

  /// 接收超时。
  final Duration receiveTimeout;

  /// 底层客户端（诊断用）。
  http.Client get client => _client;

  @override
  Future<NetResponse> send(NetRequest request) async {
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final Uri uri = Uri.parse(request.url);
      final http.Request req = http.Request(request.method.verb, uri);
      // ── 请求头：原样透传（浏览器禁止的头会被静默忽略，见文件头说明）──
      req.headers.addAll(request.headers);
      final Object? body = request.body;
      if (body != null) {
        final bool hasContentType = request.headers.keys
            .any((String key) => key.toLowerCase() == 'content-type');
        if (body is List<int>) {
          req.bodyBytes = body;
        } else {
          req.body = '$body';
        }
        if (!hasContentType) {
          req.headers['content-type'] = 'application/json; charset=utf-8';
        }
      }

      // 说明：这里**没有** `persistentConnection` / `maxConnectionsPerHost`
      // 之类的连接策略——浏览器不暴露连接池，这些策略在 Web 上不适用。
      final http.StreamedResponse streamed =
          await _client.send(req).timeout(connectTimeout);
      final String text = await streamed.stream
          .bytesToString()
          .timeout(receiveTimeout);
      stopwatch.stop();
      return NetResponse(
        statusCode: streamed.statusCode,
        body: text,
        duration: stopwatch.elapsed,
        headers: _lowerCaseHeaders(streamed.headers),
      );
    } on TimeoutException catch (error) {
      stopwatch.stop();
      _clearDnsCache();
      throw NetException(
        NetErrorKind.timeout,
        '请求超时（$error）',
        cause: error,
      );
    } on http.ClientException catch (error) {
      stopwatch.stop();
      // 浏览器把 DNS 失败 / 断网 / CORS 拦截 / TLS 错误**统一**报成一次
      // 网络错误，页面分不出具体是哪一种——所以不臆测，如实归为连接类
      // （可重试），并把浏览器给的原文附上。
      _clearDnsCache();
      throw NetException(
        NetErrorKind.connection,
        '浏览器网络请求失败：${error.message}'
        '（Web 端不区分 DNS / TLS / CORS，可能需要对方允许跨域访问）',
        cause: error,
      );
    } on Object catch (error) {
      stopwatch.stop();
      throw NetException(
        NetErrorKind.unknown,
        '未知网络错误（$error）',
        cause: error,
      );
    }
  }

  /// 连接类失败的统一善后：清 DNS 缓存，让下一次重试重新解析
  /// （与原生侧一致的语义；Web 上缓存本就是域内缓存，非系统解析结果）。
  void _clearDnsCache() {
    _dns?.cache.clear();
  }

  /// 响应头键统一小写（与 [NetResponse] 的约定一致）。
  static Map<String, String> _lowerCaseHeaders(Map<String, String> headers) {
    final Map<String, String> result = <String, String>{};
    headers.forEach((String name, String value) {
      result[name.toLowerCase()] = value;
    });
    return result;
  }
}
