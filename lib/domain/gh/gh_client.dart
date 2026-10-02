/// L2 中枢级 · API 逻辑：GitHub 请求客户端。
///
/// ## 它负责的五件事（其余一概不管）
/// 1. **认证头**：从保险库取当前账号令牌，注入 `Authorization`；
/// 2. **限流避让**：解析 `x-ratelimit-*`，**剩余为 0 时不发请求**，直接告知何时恢复；
/// 3. **并发上限**：批量操作排队，避免触发 Secondary Rate Limit；
/// 4. **分页**：解析 `Link` 头，提供安全上限的流式遍历；
/// 5. **错误映射**：把 HTTP 语义翻译成**类型化异常**（401/403/404/409/422/限流）。
///
/// ## 不做的事
/// 不做缓存、不做业务模型、不做重试（重试在底座 [ResilientTransport] 里）。
library;

import 'dart:async';
import 'dart:convert';

import '../../base/disk/disk_types.dart';
import '../../base/net/net_bridge.dart';
import '../../base/net/net_types.dart';
import '../../kernel/diagnostics.dart';
import '../../kernel/log/og_l_log_file.dart';
import 'gh_auth.dart';
import 'gh_models.dart';

/// 限流额度快照。
class GhRateLimit {
  /// 创建额度。
  const GhRateLimit({
    required this.limit,
    required this.remaining,
    required this.resetAt,
    this.resource = 'core',
  });

  /// 上限。
  final int limit;

  /// 剩余。
  final int remaining;

  /// 恢复时间。
  final DateTime resetAt;

  /// 资源类别（`core` / `search` / `graphql`）。
  final String resource;

  /// 是否已耗尽。
  bool get isExhausted => remaining <= 0;

  /// 距恢复还有多久。
  Duration get untilReset {
    final delta = resetAt.difference(DateTime.now());
    return delta.isNegative ? Duration.zero : delta;
  }

  /// 从响应头解析（缺头时返回 `null`）。
  static GhRateLimit? fromHeaders(Map<String, String> headers) {
    final limit = int.tryParse(headers['x-ratelimit-limit'] ?? '');
    final remaining = int.tryParse(headers['x-ratelimit-remaining'] ?? '');
    final resetEpoch = int.tryParse(headers['x-ratelimit-reset'] ?? '');
    if (limit == null || remaining == null || resetEpoch == null) {
      return null;
    }
    return GhRateLimit(
      limit: limit,
      remaining: remaining,
      resetAt: DateTime.fromMillisecondsSinceEpoch(
        resetEpoch * 1000,
        isUtc: true,
      ),
      resource: headers['x-ratelimit-resource'] ?? 'core',
    );
  }

  /// 序列化。
  Map<String, Object?> toJson() => <String, Object?>{
        'limit': limit,
        'remaining': remaining,
        'resetAt': resetAt.toIso8601String(),
        'resource': resource,
      };

  @override
  String toString() => 'GhRateLimit($remaining/$limit, reset in ${untilReset.inMinutes}min)';
}

/// 未认证 / 令牌失效。
class GhAuthException implements Exception {
  /// 创建异常。
  const GhAuthException(this.message, {this.statusCode});

  /// 说明。
  final String message;

  /// 状态码。
  final int? statusCode;

  @override
  String toString() => 'GhAuthException(${statusCode ?? '-'}): $message';
}

/// 限流（含 Secondary Rate Limit）。
class GhRateLimitException implements Exception {
  /// 创建异常。
  const GhRateLimitException({
    required this.message,
    this.resetAt,
    this.retryAfter,
    this.secondary = false,
  });

  /// 说明。
  final String message;

  /// 主限流恢复时间。
  final DateTime? resetAt;

  /// 次要限流的退避建议。
  final Duration? retryAfter;

  /// 是否为次要限流（短时高频触发）。
  final bool secondary;

  @override
  String toString() =>
      'GhRateLimitException(${secondary ? 'secondary' : 'primary'}): $message';
}

/// 资源不存在 / 无权限。
class GhNotFoundException implements Exception {
  /// 创建异常。
  const GhNotFoundException(this.path);

  /// 请求路径。
  final String path;

  @override
  String toString() => 'GhNotFoundException($path)';
}

/// 一次请求。
class GhRequest {
  /// 创建请求。
  const GhRequest({
    required this.path,
    this.method = NetMethod.get,
    this.query = const <String, String>{},
    this.body,
    this.label,
    this.conflictsAsRemoteConflict = false,
  });

  /// 路径（`/repos/...`）或完整 URL。
  final String path;

  /// 方法。
  final NetMethod method;

  /// 查询参数。
  final Map<String, String> query;

  /// 请求体（会被 JSON 编码）。
  final Object? body;

  /// 诊断标签。
  final String? label;

  /// 409/422 是否翻译成 [RemoteConflictException]（内容读写场景需要）。
  final bool conflictsAsRemoteConflict;

  /// 拼出完整 URL。
  String toUrl(String base) {
    final buffer = StringBuffer(path.startsWith('http') ? path : '$base$path');
    if (query.isEmpty) {
      return buffer.toString();
    }
    final parts = query.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .toList();
    return '$buffer${buffer.toString().contains('?') ? '&' : '?'}${parts.join('&')}';
  }
}

/// 一次响应。
class GhResponse {
  /// 创建响应。
  const GhResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    this.rateLimit,
  });

  /// 状态码。
  final int statusCode;

  /// 原始文本。
  final String body;

  /// 响应头。
  final Map<String, String> headers;

  /// 限流快照。
  final GhRateLimit? rateLimit;

  /// 是否成功。
  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// 分页信息。
  GhPage get page => GhPage.parse(headers['link']);

  /// 解析为对象 Map（失败返回 `null`）。
  Map<String, dynamic>? get jsonObject {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  /// 解析为对象列表（失败返回空列表）。
  List<Map<String, dynamic>> get jsonList {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        return const <Map<String, dynamic>>[];
      }
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map(Map<String, dynamic>.from)
          .toList();
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  /// 解析列表或单个对象（GitHub 部分端点两种都可能返回）。
  List<Map<String, dynamic>> get jsonAsList {
    final asList = jsonList;
    if (asList.isNotEmpty) {
      return asList;
    }
    final asObject = jsonObject;
    return asObject == null
        ? const <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[asObject];
  }

  @override
  String toString() => 'GhResponse($statusCode, ${body.length}B)';
}

/// 并发闸门（信号量）。
class _Semaphore {
  _Semaphore(this.permits);

  final int permits;
  int _used = 0;
  final List<Completer<void>> _waiters = <Completer<void>>[];

  Future<void> acquire() async {
    if (_used < permits) {
      _used++;
      return;
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
    _used++;
  }

  void release() {
    _used--;
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    }
  }

  /// 当前在用数量（诊断）。
  int get inUse => _used;
}

/// GitHub 客户端。
class GhClient {
  /// 创建客户端。
  GhClient({
    required NetBridge net,
    required GhAuthService auth,
    this.baseUrl = 'https://api.github.com',
    int maxConcurrent = 4,
    KernelDiagnostics? diagnostics,
  })  : _net = net,
        _auth = auth,
        _semaphore = _Semaphore(maxConcurrent),
        _diagnostics = diagnostics;

  /// 默认 API 根。
  final String baseUrl;

  final NetBridge _net;
  final GhAuthService _auth;
  final _Semaphore _semaphore;
  KernelDiagnostics? _diagnostics;

  GhRateLimit? _lastRateLimit;

  /// 最近一次已知额度（供仪表盘展示）。
  GhRateLimit? get lastRateLimit => _lastRateLimit;

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  /// 发送请求。
  ///
  /// 抛：[GhAuthException] / [GhRateLimitException] / [GhNotFoundException] /
  /// [RemoteConflictException]（按需）。
  Future<GhResponse> send(GhRequest request) async {
    // 限流避让：**已知耗尽就不发请求**，省下一次注定 403 的往返。
    final known = _lastRateLimit;
    if (known != null && known.isExhausted && known.untilReset > Duration.zero) {
      throw GhRateLimitException(
        message: '额度已耗尽，将在 ${known.untilReset.inMinutes} 分钟后恢复',
        resetAt: known.resetAt,
      );
    }

    await _semaphore.acquire();
    try {
      final token = await _auth.activeToken();
      final headers = <String, String>{
        'accept': 'application/vnd.github+json',
        'x-github-api-version': '2022-11-28',
        if (token != null) 'authorization': 'Bearer ${token.value}',
      };
      OgLLogFile.line(
        '网络',
        '→ ${request.method.verb} ${request.path}'
            '${request.query.isEmpty ? '' : '?${request.query.entries.map((e) => '${e.key}=${e.value}').join('&')}'}',
      );
      final netResponse = await _net.send(NetRequest(
        method: request.method,
        url: request.toUrl(baseUrl),
        headers: headers,
        body: request.body == null ? null : jsonEncode(request.body),
        timeout: const Duration(seconds: 30),
        label: request.label ?? '${request.method.verb} ${request.path}',
      ));

      final rateLimit = GhRateLimit.fromHeaders(netResponse.headers);
      if (rateLimit != null) {
        _lastRateLimit = rateLimit;
      }
      final response = GhResponse(
        statusCode: netResponse.statusCode,
        body: netResponse.body,
        headers: netResponse.headers,
        rateLimit: rateLimit,
      );
      _diagnostics?.debug(
        'GH',
        '${request.method.verb} ${request.path} → ${response.statusCode}',
        data: <String, Object?>{
          if (rateLimit != null) 'remaining': rateLimit.remaining,
        },
      );

      OgLLogFile.line(
        '网络',
        '← ${response.statusCode} ${request.method.verb} ${request.path}'
            '（${netResponse.bodyLength} 字符 / ${netResponse.duration.inMilliseconds}ms'
            '${rateLimit == null ? '' : ' / 余量 ${rateLimit.remaining}'}'
            '${netResponse.fromMirrorId == null ? '' : ' / 镜像 ${netResponse.fromMirrorId}'}）',
      );
      try {
        _throwIfFailed(response, request);
        return response;
      } catch (error) {
        // 失败要**看得见**：状态码 + 映射后的异常类型 + 服务端原话。
        OgLLogFile.line(
          '网络',
          '✗ ${request.method.verb} ${request.path} → ${response.statusCode}：$error',
          level: 'ERR',
        );
        rethrow;
      }
    } finally {
      _semaphore.release();
    }
  }

  /// 便捷：GET 对象。
  Future<Map<String, dynamic>?> getObject(
    String path, {
    Map<String, String> query = const <String, String>{},
    String? label,
  }) async {
    final response = await send(GhRequest(path: path, query: query, label: label));
    return response.jsonObject;
  }

  /// 便捷：GET 列表（含单对象兼容）。
  Future<List<Map<String, dynamic>>> getList(
    String path, {
    Map<String, String> query = const <String, String>{},
    String? label,
  }) async {
    final response = await send(GhRequest(path: path, query: query, label: label));
    return response.jsonAsList;
  }

  /// 分页遍历。
  ///
  /// [maxPages] 是**安全上限**：GitHub 某些端点会返回极大的 `last`，
  /// 无上限遍历会烧光额度。默认 10 页足够仓库管理场景。
  Stream<List<Map<String, dynamic>>> paginate(
    String path, {
    Map<String, String> query = const <String, String>{},
    int perPage = 100,
    int maxPages = 10,
  }) async* {
    var page = 1;
    while (page <= maxPages) {
      final response = await send(GhRequest(
        path: path,
        query: <String, String>{
          ...query,
          'per_page': '$perPage',
          'page': '$page',
        },
        label: 'GET $path (page $page)',
      ));
      final items = response.jsonAsList;
      if (items.isEmpty) {
        return;
      }
      yield items;
      final next = response.page.next;
      if (next == null) {
        return;
      }
      page++;
    }
    _diagnostics?.warn(
      'GH',
      '分页达到安全上限 $maxPages，已停止（避免烧光额度）',
      code: 'OGL-GH-101',
      data: <String, Object?>{'path': path},
    );
  }

  void _throwIfFailed(GhResponse response, GhRequest request) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      return;
    }
    switch (status) {
      case 401:
        throw const GhAuthException(
          '令牌无效或已过期，请重新授权',
          statusCode: 401,
        );
      case 403:
      case 429:
        final retryAfter = _retryAfterOf(response);
        final remaining = response.rateLimit?.remaining;
        if (remaining != null && remaining <= 0) {
          throw GhRateLimitException(
            message: '额度耗尽',
            resetAt: response.rateLimit?.resetAt,
          );
        }
        // 403 且额度充足 = 多半是 Secondary Rate Limit。
        if (retryAfter != null) {
          throw GhRateLimitException(
            message: '触发次要限流，建议退避后重试',
            retryAfter: retryAfter,
            secondary: true,
          );
        }
        throw GhAuthException(
          '权限不足（缺少 repo 等作用域）',
          statusCode: 403,
        );
      case 404:
        throw GhNotFoundException(request.path);
      case 409:
      case 422:
        if (request.conflictsAsRemoteConflict) {
          throw RemoteConflictException(
            statusCode: status,
            currentSha: _currentShaOf(response),
            message: '远端版本已变化',
          );
        }
        throw GhAuthException(
          '请求被拒绝（HTTP $status）：${_snippet(response.body)}',
          statusCode: status,
        );
      default:
        throw GhAuthException(
          '请求失败（HTTP $status）：${_snippet(response.body)}',
          statusCode: status,
        );
    }
  }

  static Duration? _retryAfterOf(GhResponse response) {
    final raw = response.headers['retry-after'];
    final seconds = int.tryParse(raw ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static String? _currentShaOf(GhResponse response) {
    final object = response.jsonObject;
    final sha = object?['sha'];
    return sha is String ? sha : null;
  }

  static String _snippet(String body) =>
      body.length <= 160 ? body : '${body.substring(0, 160)}…';
}
