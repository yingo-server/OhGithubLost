/// L1 底座级 · 网络连接：基于 Dio 的真实传输实现。
///
/// 职责**只有一个**：把 Dio 的异常与响应翻译成 OGL 的
/// [NetException] / [NetResponse]。
/// 重试、镜像、观测一律不在这里做——那是 [ResilientTransport] 的活。
library;

import 'package:dio/dio.dart';

import 'net_transport.dart';
import 'net_types.dart';

/// Dio 传输实现（Android / Windows / Linux 共用）。
class DioNetTransport implements NetTransport {
  /// 创建传输。
  DioNetTransport({
    Dio? dio,
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
            );

  final Dio _dio;

  /// 连接超时。
  final Duration connectTimeout;

  /// 接收超时。
  final Duration receiveTimeout;

  /// 底层 Dio 实例（高级用法 / 注入拦截器）。
  Dio get dio => _dio;

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
