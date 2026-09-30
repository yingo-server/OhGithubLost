/// L1 底座级 · 网络连接：门面与模块装配。
///
/// [NetBridge] 是**本层对外唯一出口**：上层只认识它，不认识 Dio、
/// 不认识重试策略、更不认识镜像通道实现。
library;

import '../../kernel/contract/module.dart';
import 'dio_net_transport.dart';
import 'net_mirror.dart';
import 'net_retry.dart';
import 'net_transport.dart';
import 'net_types.dart';

/// 网络连接门面。
class NetBridge {
  /// 创建门面。
  NetBridge({required this.transport, required this.observer});

  /// 韧性传输（重试 + 镜像 + 观测）。
  final NetTransport transport;

  /// 观测器。
  final NetObserver observer;

  /// 发送请求。
  Future<NetResponse> send(NetRequest request) => transport.send(request);

  /// 便捷 GET（返回响应体文本；非 2xx 由调用方自行处理）。
  Future<NetResponse> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
    String? label,
  }) =>
      send(NetRequest(
        method: NetMethod.get,
        url: url,
        headers: headers,
        label: label,
      ));

  /// 当前网络统计。
  NetStats get stats => observer.snapshot();

  @override
  String toString() => 'NetBridge(${observer.snapshot()})';
}

/// 网络连接模块（`base.net`）。
///
/// 依赖：无（底座最底层）。
/// 提供：`net.transport`。
class NetModule extends OgLModule {
  /// 创建模块。
  NetModule({
    NetTransport? transport,
    NetObserver? observer,
    RetryPolicy policy = const RetryPolicy(),
    MirrorSelector? mirrors,
    NetTransport Function()? transportFactory,
  })  : _observer = observer ?? NetObserver(),
        _explicit = transport {
    _policy = policy;
    _mirrors = mirrors ?? MirrorSelector();
    _factory = transportFactory;
  }

  final NetObserver _observer;
  final NetTransport? _explicit;
  late final RetryPolicy _policy;
  late final MirrorSelector _mirrors;
  late final NetTransport Function()? _factory;

  /// 门面实例（[onRegister] 后可用）。
  late final NetBridge bridge;

  @override
  ModuleDescriptor get descriptor => const ModuleDescriptor(
        id: 'base.net',
        layer: ModuleLayer.base,
        version: '0.1.0',
        provides: <String>['net.transport'],
        description: '底座·网络连接（传输 / 重试 / 镜像加速 / 观测）',
      );

  @override
  Future<void> onRegister(KernelContext context) async {
    final inner = _explicit ?? _factory?.call() ?? DioNetTransport();
    final transport = inner is ResilientTransport
        ? inner
        : ResilientTransport(
            inner: inner,
            policy: _policy,
            mirrors: _mirrors,
            observer: _observer,
          );
    bridge = NetBridge(transport: transport, observer: _observer);
    context.di.register<NetBridge>(bridge);
    context.diagnostics.info(
      'NET',
      '网络连接就绪',
      code: 'OGL-NET-001',
      data: <String, Object?>{'policy': _policy.toString(), 'mirrors': _mirrors.channels.length},
    );
  }
}
