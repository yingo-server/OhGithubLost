/// L1 底座级 · 网络连接：基于 Dio 的真实传输实现。
///
/// 职责**只有一个**：把 Dio 的异常与响应翻译成 OGL 的
/// [NetException] / [NetResponse]。
/// 重试、镜像、观测一律不在这里做——那是 [ResilientTransport] 的活。
library;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'net_dns.dart';
import 'net_transport.dart';
import 'net_types.dart';

/// Dio 传输实现（Android / Windows / Linux 共用）。
class DioNetTransport implements NetTransport {
  /// 创建传输。
  ///
  /// [dns] 非空时启用**自定义 DNS**：连接前先按策略解析域名，
  /// 再直连解析出的 IP（TLS 的 SNI 仍用原主机名，证书校验不受影响）。
  /// 这是绕开 DNS 污染的关键——换的是"谁告诉我 IP"，不是"我连谁"。
  DioNetTransport({
    Dio? dio,
    DnsService? dns,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 60),
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: connectTimeout,
                receiveTimeout: receiveTimeout,
                followRedirects: true,
                maxRedirects: 5,
                // 交给上层分类，不在这里抛状态码异常。
                validateStatus: (int? _) => true,
              ),
            ) {
    if (dns != null) {
      _installCustomDns(dns);
    }
  }

  final Dio _dio;

  /// 连接超时。
  final Duration connectTimeout;

  /// 接收超时。
  final Duration receiveTimeout;

  /// 底层 Dio 实例（高级用法 / 注入拦截器）。
  Dio get dio => _dio;

  /// 安装自定义 DNS：接管 `connectionFactory`，把域名换成我们解析出的 IP。
  ///
  /// 三条分支，缺一不可：
  /// - **代理存在**：必须连代理（沿用平台行为），否则代理会失效；
  /// - **system 模式**：与平台默认一致（`startConnect(host)`），保证开关切换可逆；
  /// - **custom 模式**：用我们解析出的 IP 直连（TLS 的 SNI 仍是原主机名，
  ///   证书校验不受影响）——这一步才是真正绕开 DNS 污染的地方。
  ///
  /// 非 IO 平台（Web）没有 `HttpClient`，直接跳过：Web 端由浏览器负责解析。
  void _installCustomDns(DnsService dns) {
    final adapter = _dio.httpClientAdapter;
    if (adapter is! IOHttpClientAdapter) {
      return;
    }
    adapter.createHttpClient = () {
      final client = HttpClient();
      client.connectionFactory = (
        Uri uri,
        String? proxyHost,
        int? proxyPort,
      ) async {
        const connectTimeout = Duration(seconds: 15);
        if (proxyHost != null && proxyPort != null) {
          return Socket.startConnect(
            proxyHost,
            proxyPort,
            timeout: connectTimeout,
          );
        }
        final port = uri.hasPort && uri.port != 0
            ? uri.port
            : (uri.scheme == 'https' ? 443 : 80);
        if (dns.policy.mode != NetDnsMode.custom) {
          return Socket.startConnect(uri.host, port, timeout: connectTimeout);
        }

        final addresses = await dns.resolve(uri.host);
        Object? lastError;
        for (final address in addresses) {
          try {
            return await Socket.startConnect(
              address,
              port,
              timeout: connectTimeout,
            );
          } catch (error) {
            lastError = error;
          }
        }
        throw NetException(
          NetErrorKind.connection,
          'DNS 解析后无法连接 ${uri.host}（尝试 ${addresses.length} 个地址）：$lastError',
        );
      };
      return client;
    };
  }

  @override
  Future<NetResponse> send(NetRequest request) async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _dio.request<dynamic>(
        request.url,
        data: request.body,
        options: Options(
          method: request.method.verb,
          headers: request.headers.isEmpty ? null : request.headers,
          responseType: ResponseType.plain,
          sendTimeout: request.timeout,
          receiveTimeout: receiveTimeout,
          validateStatus: (int? _) => true,
        ),
      );
      stopwatch.stop();
      return NetResponse(
        statusCode: response.statusCode ?? 0,
        body: response.data?.toString() ?? '',
        duration: stopwatch.elapsed,
        headers: _flattenHeaders(response.headers),
      );
    } on DioException catch (error) {
      stopwatch.stop();
      throw _translate(error);
    }
  }

  static Map<String, String> _flattenHeaders(Headers headers) {
    final result = <String, String>{};
    headers.map.forEach((key, value) {
      result[key.toLowerCase()] = value.join(', ');
    });
    return result;
  }

  static NetException _translate(DioException error) {
    final status = error.response?.statusCode;
    final retryAfter = _parseRetryAfter(error.response?.headers.value('retry-after'));
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return NetException(
          NetErrorKind.timeout,
          '请求超时',
          statusCode: status,
          cause: error,
        );
      case DioExceptionType.badCertificate:
        return NetException(
          NetErrorKind.tls,
          '证书校验失败',
          statusCode: status,
          cause: error,
        );
      case DioExceptionType.cancel:
        return NetException(
          NetErrorKind.cancelled,
          '请求已取消',
          statusCode: status,
          cause: error,
        );
      case DioExceptionType.connectionError:
        return NetException(
          NetErrorKind.connection,
          '连接失败',
          statusCode: status,
          cause: error,
        );
      case DioExceptionType.badResponse:
        if (status == 403 || status == 429) {
          return NetException(
            NetErrorKind.rateLimited,
            '请求被限流',
            statusCode: status,
            cause: error,
            retryAfter: retryAfter,
          );
        }
        return NetException(
          status != null && status >= 500
              ? NetErrorKind.server
              : NetErrorKind.client,
          '服务端返回 $status',
          statusCode: status,
          cause: error,
          retryAfter: retryAfter,
        );
      case DioExceptionType.unknown:
        return NetException(
          NetErrorKind.unknown,
          error.message ?? '未知网络错误',
          statusCode: status,
          cause: error,
        );
    }
  }

  /// 解析 `Retry-After`（秒数或 HTTP 日期；无法解析时返回 `null`）。
  static Duration? _parseRetryAfter(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final seconds = int.tryParse(raw.trim());
    if (seconds != null) {
      return Duration(seconds: seconds);
    }
    try {
      final target = DateTime.parse(raw);
      final delta = target.difference(DateTime.now());
      return delta.isNegative ? null : delta;
    } catch (_) {
      return null;
    }
  }
}

/// DoH 解析所需的 HTTP 能力实现。
///
/// **刻意不使用自定义 DNS**：如果 DoH 端点自己也要靠自定义解析才能连上，
/// 就成了先有鸡还是先有蛋。DoH 端点域名一律交给系统解析——
/// 这正是 DoH 存在的意义（它走 443，而系统解析通常至少能拿到可连的 IP）。
class DioDnsHttpClient implements DnsHttpClient {
  /// 创建客户端。
  DioDnsHttpClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
              ),
            );

  final Dio _dio;

  @override
  Future<String> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final response = await _dio.get<String>(
      url,
      options: Options(
        headers: headers,
        responseType: ResponseType.plain,
        validateStatus: (int? status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    return response.data ?? '';
  }
}
