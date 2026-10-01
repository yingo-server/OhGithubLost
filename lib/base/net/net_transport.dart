/// L1 底座级 · 网络连接：传输抽象与韧性编排。
///
/// 分层：
/// ```
/// NetBridge（门面）
///   └─ ResilientTransport（重试 + 镜像回落 + 观测）  ← 本文件
///        └─ NetTransport（纯发送，无策略）
///             └─ DioNetTransport（真实 HTTP） / 测试桩
/// ```
/// 这样"策略"与"能力"分离：换 HTTP 客户端不影响重试与观测，
/// 换策略也不影响传输实现。
///
/// ## 两条安全铁律
/// 1. **只重试幂等方法**：`POST` / `PATCH` 的失败**绝不自动重试**——
///    一次超时重试就可能重复创建 Release、重复提交。需要重试时由调用方
///    通过 [retryableMethods] 显式放行，并自行保证幂等键。
/// 2. **失败必须显式**：重试耗尽后不再把 5xx / 429「当作正常响应」返回，
///    而是抛 [NetException]（携带状态码与响应体片段）。
///    语义性响应（4xx 如 404 / 409 / 422）仍照常返回，由上层判断。
library;

import 'net_mirror.dart';
import 'net_retry.dart';
import 'net_types.dart';

/// 默认可重试的方法：具备幂等语义，重复执行不会产生额外副作用。
const Set<NetMethod> defaultRetryableMethods = <NetMethod>{
  NetMethod.get,
  NetMethod.head,
  NetMethod.put,
  NetMethod.delete,
};

/// 纯发送能力：一次请求一次响应，不做重试、不做镜像。
abstract class NetTransport {
  /// 发送请求；传输层失败必须抛 [NetException]。
  Future<NetResponse> send(NetRequest request);
}

/// 韧性传输：在纯发送之外叠加**重试、镜像回落与观测**。
class ResilientTransport implements NetTransport {
  /// 创建韧性传输。
  ///
  /// [sleep] 可注入（测试传零延迟版本），避免单测真的等待退避时间。
  /// [retryableMethods] 缺省为幂等方法；**不要**为了"多试几次"把 POST 放进来。
  ResilientTransport({
    required NetTransport inner,
    RetryPolicy? policy,
    MirrorSelector? mirrors,
    NetObserver? observer,
    Future<void> Function(Duration duration)? sleep,
    Set<NetMethod> retryableMethods = defaultRetryableMethods,
  })  : _inner = inner,
        _policy = policy ?? const RetryPolicy(),
        _mirrors = mirrors ?? MirrorSelector(),
        _observer = observer ?? NetObserver(),
        _sleep = sleep ?? Future<void>.delayed,
        _retryableMethods = Set<NetMethod>.of(retryableMethods);

  final NetTransport _inner;
  final RetryPolicy _policy;
  final MirrorSelector _mirrors;
  final NetObserver _observer;
  final Future<void> Function(Duration duration) _sleep;
  final Set<NetMethod> _retryableMethods;

  /// 观测器（读取统计用）。
  NetObserver get observer => _observer;

  /// 重试策略（只读）。
  RetryPolicy get policy => _policy;

  /// 镜像选择器（只读）。
  MirrorSelector get mirrors => _mirrors;

  /// 允许自动重试的方法（只读）。
  Set<NetMethod> get retryableMethods =>
      Set<NetMethod>.unmodifiable(_retryableMethods);

  @override
  Future<NetResponse> send(NetRequest request) async {
    var current = request;
    final triedMirrors = <String>{};

    for (var attempt = 1; attempt <= _policy.maxAttempts; attempt++) {
      // 幂等守卫：非幂等方法既不重试、也不换镜像。
      final mayRetry = _retryableMethods.contains(current.method);
      _observer.onRequest(current);

      NetResponse response;
      try {
        response = await _inner.send(current);
      } on NetException catch (error) {
        _observer.onFailure(current, error);

        if (mayRetry) {
          final mirror = _mirrors.mirrorFor(current.url, skip: triedMirrors);
          if (mirror != null) {
            triedMirrors.add(mirror.id);
            current = current.copyWith(url: mirror.url);
            _observer.onMirror(current, mirror.id);
            continue;
          }
        }

        final delay = mayRetry
            ? _policy.delayFor(
                attempt,
                kind: error.kind,
                retryAfter: error.retryAfter,
              )
            : null;
        if (delay == null) {
          rethrow;
        }
        _observer.onRetry(current, attempt, error.kind.name);
        await _sleep(delay);
        continue;
      }

      _observer.onResponse(response);

      // 非"可重试状态码"：属于语义性响应（含 4xx），交还调用方判断。
      if (!_policy.retryableStatuses.contains(response.statusCode)) {
        return response;
      }

      final delay = mayRetry
          ? _policy.delayFor(attempt, statusCode: response.statusCode)
          : null;
      if (delay == null) {
        // 铁律 2：重试已耗尽（或方法不幂等）——必须显式失败，
        // 绝不把 5xx / 429 当成"正常响应"交给上层。
        throw NetException(
          _kindForStatus(response.statusCode),
          'HTTP ${response.statusCode}：重试已耗尽',
          statusCode: response.statusCode,
          body: _snippet(response.body),
        );
      }
      _observer.onRetry(current, attempt, 'HTTP ${response.statusCode}');
      await _sleep(delay);
    }

    // 只有当 maxAttempts < 1（策略配置错误）才可能走到这里。
    throw const NetException(
      NetErrorKind.unknown,
      '重试策略未产出任何结果（请检查 maxAttempts 配置）',
    );
  }

  static NetErrorKind _kindForStatus(int statusCode) {
    if (statusCode == 408) {
      return NetErrorKind.timeout;
    }
    if (statusCode == 429) {
      return NetErrorKind.rateLimited;
    }
    return NetErrorKind.server;
  }

  static String _snippet(String body) =>
      body.length <= 200 ? body : '${body.substring(0, 200)}…';
}

/// 脚本化传输（测试 / 演练用）。
///
/// 按入队顺序返回预设结果：给了 [NetException] 就抛出，给了 [NetResponse] 就返回。
class ScriptedTransport implements NetTransport {
  /// 创建脚本化传输。
  ScriptedTransport(this._script);

  final List<Object> _script;
  final List<NetRequest> _received = <NetRequest>[];

  /// 实际收到的请求（按顺序，断言镜像改写 / 重试用）。
  List<NetRequest> get received => List<NetRequest>.unmodifiable(_received);

  @override
  Future<NetResponse> send(NetRequest request) async {
    _received.add(request);
    if (_script.isEmpty) {
      throw StateError('ScriptedTransport 脚本已耗尽');
    }
    final next = _script.removeAt(0);
    if (next is NetException) {
      throw next;
    }
    if (next is NetResponse) {
      return next;
    }
    throw StateError('无法识别的脚本项: ${next.runtimeType}');
  }
}