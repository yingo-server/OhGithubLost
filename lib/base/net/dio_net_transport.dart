/// L1 底座级 · 网络连接：基于 Dio 的真实传输实现。
///
/// 职责**只有一个**：把 Dio 的异常与响应翻译成 OGL 的
/// [NetException] / [NetResponse]。
/// 重试、镜像、观测一律不在这里做——那是 [ResilientTransport] 的活。
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'net_dns.dart';
import 'net_self_test.dart';
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
          return Socket.startConnect(proxyHost, proxyPort)
              .timeout(connectTimeout);
        }
        final port = uri.hasPort && uri.port != 0
            ? uri.port
            : (uri.scheme == 'https' ? 443 : 80);
        if (dns.policy.mode != NetDnsMode.custom) {
          // ★ 线上实证修复（v2）：App 进程内曾出现「DNS 解析超时 +
          //   Connection closed before full header」——特征指向**半死的
          //   IPv6 通道**（AAAA 解析/连接半通）。策略：优先 IPv4-only
          //   解析（3 秒上限）并直连；失败才回退平台默认路径（含 IPv6，
          //   绝不比现状更差）。
          final v4 = await _resolveIpv4(uri.host);
          for (final address in v4) {
            try {
              return await Socket.startConnect(address, port)
                  .timeout(connectTimeout);
            } on Object {
              // 该地址直连失败 → 试下一个（全部失败后回退平台默认路径）。
            }
          }
          return Socket.startConnect(uri.host, port);
        }

        final resolved = await dns.resolve(uri.host);
        // IPv4 优先排序（半死 IPv6 通道场景下先走可达地址）。
        // 说明：DnsService.resolve 返回 IP 字符串列表（含 ':' 即 IPv6）。
        final v4List = resolved.where((ip) => !ip.contains(':')).toList();
        final v6List = resolved.where((ip) => ip.contains(':')).toList();
        final addresses = <String>[...v4List, ...v6List];
        Object? lastError;
        for (final address in addresses) {
          try {
            return await Socket.startConnect(address, port)
                .timeout(connectTimeout);
          } catch (error) {
            lastError = error;
          }
        }
        // ★ 降级：自定义解析全军覆没 → 交给系统解析再试一次（绝不静默）。
        try {
          return await Socket.startConnect(uri.host, port)
              .timeout(connectTimeout);
        } catch (error) {
          lastError = error;
        }
        throw NetException(
          NetErrorKind.connection,
          'DNS 解析后无法连接 ${uri.host}'
          '（自定义 ${addresses.length} 地址 + 系统解析均失败）：$lastError',
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
      final translated = _translate(error);
      if (translated.kind == NetErrorKind.connection) {
        // ★ 连接失败 = 最模糊的错误；自动跑「解析 → 逐地址 TCP」自检，
        //   把 errno 级真相附进异常消息（日志 / 界面直接可见）。
        String report;
        try {
          report = await NetSelfTest.cachedOrRun(error.requestOptions.uri.host);
        } on Object catch (selfTestError) {
          report = '自检异常: $selfTestError';
        }
        throw NetException(
          translated.kind,
          '${translated.message}｜自检: $report',
          statusCode: translated.statusCode,
          cause: translated.cause,
          retryAfter: translated.retryAfter,
        );
      }
      throw translated;
    }
  }

  /// IPv4-only 系统解析（3 秒上限；任何失败返回空列表——**绝不抛异常**）。
  static Future<List<InternetAddress>> _resolveIpv4(String host) async {
    try {
      return await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      ).timeout(const Duration(seconds: 3));
    } on Object {
      return const <InternetAddress>[];
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
          '连接失败：${error.error ?? error.message ?? '无底层信息'}',
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
          '${error.message ?? '未知网络错误'}（${error.error ?? '无底层信息'}）',
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
