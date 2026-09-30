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
library;

import 'net_mirror.dart';
import 'net_retry.dart';
import 'net_types.dart';

/// 纯发送能力：一次请求一次响应，不做重试、不做镜像。
abstract class NetTransport {
  /// 发送请求；失败必须抛 [NetException]。
  Future<NetResponse> send(NetRequest request);
}

/// 韧性传输：在纯发送之外叠加**重试、镜像回落与观测**。
class ResilientTransport implements NetTransport {
  /// 创建韧性传输。
  ///
  /// [sleep] 可注入（测试用零延迟版本），避免单测真的等待退避时间。
  ResilientTransport({
    required NetTransport inner,
    RetryPolicy? policy,
    MirrorSelector? mirrors,
    NetObserver? observer,
    Future<void> Function(Duration duration)? sleep,
  })  : _inner = inner,
        _policy = policy ?? const RetryPolicy(),
        _mirrors = mirrors ?? MirrorSelector(),
        _observer = observer ?? NetObserver(),
        _sleep = sleep ?? Future<void>.delayed;

  final NetTransport _inner;
  final RetryPolicy _policy;
  final MirrorSelector _mirrors;
  final NetObserver _observer;
  final Future<void> Function(Duration duration) _sleep;

  /// 观测器（读取统计用）。
  NetObserver get observer => _observer;

  /// 重试策略（只读）。
  RetryPolicy get policy => _policy;

  /// 镜像选择器（只读）。
  MirrorSelector get mirrors => _mirrors;

  @override
  Future<NetResponse> send(NetRequest request) async {
    var current = request;
    final triedMirrors = <String>{};
    NetResponse? lastResponse;
    NetException? lastError;

    for (var attempt = 1; attempt <= _policy.maxAttempts; attempt++) {
      _observer.onRequest(current);
      try {
        final response = await _inner.send(current);
        _observer.onResponse(response);
        lastResponse = response;
        lastError = null;

        if (!_policy.retryableStatuses.contains(response.statusCode)) {
          return response;
        }
        final delay = _policy.delayFor(attempt, statusCode: response.statusCode);
        if (delay == null) {
          return response;
        }
        _observer.onRetry(current, attempt, 'HTTP ${response.statusCode}');
        await _sleep(delay);
      } on NetException catch (error) {
        lastError = error;
        _observer.onFailure(current, error);

        // 镜像回落：换一条通道再试（被跳过的通道不再重复尝试）。
        final mirror = _mirrors.mirrorFor(current.url, skip: triedMirrors);
        if (mirror != null) {
          triedMirrors.add(mirror.id);
          current = current.copyWith(url: mirror.url);
          _observer.onMirror(current, mirror.id);
          continue;
        }

        final delay = _policy.delayFor(
          attempt,
          kind: error.kind,
          retryAfter: error.retryAfter,
        );
        if (delay == null) {
          throw error;
        }
        _observer.onRetry(current, attempt, error.kind.name);
        await _sleep(delay);
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    return lastResponse!;
  }
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
