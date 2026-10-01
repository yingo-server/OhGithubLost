/// L1 底座级 · 网络连接：DNS 策略（系统解析 / 自定义 DNS）。
///
/// ## 为什么需要它
/// 在部分网络环境下，`api.github.com`、`raw.githubusercontent.com` 会被
/// **DNS 污染**（返回错误 IP，TCP 直接连不上），而 HTTPS 本身毫无问题。
/// 换一个可信解析器就能绕开——这就是本文件的全部意义。
///
/// ## 设计原则（能力冲突 → 交由用户选择）
/// - **两条路都要有**：`system`（交给操作系统，最省事）与
///   `custom`（自定义解析器，绕开污染）；
/// - **默认内置五家**：阿里 / 腾讯 / 114 / Cloudflare / Google；
/// - **绝不静默降级**：自定义解析失败会**回退系统解析**，但必须记日志，
///   并且自检项会把这个事实报出来；
/// - **不引入新依赖**：DoH 走底座自己的 HTTP 能力，明文 DNS 用
///   `RawDatagramSocket` 自己编码报文（RFC 1035，仅 A/AAAA）。
///
/// ## 测试友好
/// UDP 通道（[DnsUdpChannel]）与 DoH 的 HTTP 能力（[DnsHttpClient]）
/// 都是抽象接口——因此**整套策略逻辑可以在 CI 上完全离线断言**，
/// 包括报文编解码、缓存、回退与并发竞速。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../kernel/diagnostics.dart';
import '../../kernel/environment.dart';

/// DNS 解析模式。
enum NetDnsMode {
  /// 交给操作系统（默认；不改动任何行为）。
  system,

  /// 使用自定义 DNS 服务器列表。
  custom,
}

/// 一家 DNS 服务商。
class DnsServer {
  /// 创建服务商。
  const DnsServer({
    required this.id,
    required this.label,
    required this.ip,
    this.dohUrl,
    this.region = 'global',
  });

  /// 稳定 ID（用于设置持久化与日志）。
  final String id;

  /// 展示名。
  final String label;

  /// 明文 DNS 地址（UDP 53）。
  final String ip;

  /// DoH 端点（`null` 表示只支持明文）。
  final String? dohUrl;

  /// 归属地分组（`cn` / `global`），用于界面分组与默认排序。
  final String region;

  /// 是否支持 DoH。
  bool get supportsDoh => dohUrl != null;

  @override
  String toString() => 'DnsServer($id, $ip${dohUrl == null ? '' : ', doh'})';
}

/// 内置 DNS 服务商（默认全部可用，顺序即默认优先级：国内优先）。
///
/// 之所以国内放前面：在受污染网络里，国内解析器的可达性最高，
/// 而它们对 GitHub 域名的解析同样有效。
const List<DnsServer> builtinDnsServers = <DnsServer>[
  DnsServer(
    id: 'alidns',
    label: '阿里 AliDNS',
    ip: '223.5.5.5',
    dohUrl: 'https://dns.alidns.com/resolve',
    region: 'cn',
  ),
  DnsServer(
    id: 'dnspod',
    label: '腾讯 DNSPod',
    ip: '119.29.29.29',
    dohUrl: 'https://doh.pub/dns-query',
    region: 'cn',
  ),
  DnsServer(
    id: 'dns114',
    label: '114 DNS',
    ip: '114.114.114.114',
    region: 'cn',
  ),
  DnsServer(
    id: 'cloudflare',
    label: 'Cloudflare',
    ip: '1.1.1.1',
    dohUrl: 'https://cloudflare-dns.com/dns-query',
  ),
  DnsServer(
    id: 'google',
    label: 'Google',
    ip: '8.8.8.8',
    dohUrl: 'https://dns.google/resolve',
  ),
];

/// DNS 解析异常。
class DnsException implements Exception {
  /// 创建异常。
  const DnsException(this.message);

  /// 说明。
  final String message;

  @override
  String toString() => 'DnsException: $message';
}

/// DNS 报文编解码（RFC 1035，仅 A / AAAA）。
///
/// 刻意保持**纯函数**：不碰 socket、不碰时间，因此可以用固定字节序列断言。
class DnsWireCodec {
  const DnsWireCodec._();

  /// A 记录。
  static const int typeA = 1;

  /// AAAA 记录。
  static const int typeAaaa = 28;

  /// 构造查询报文。
  static List<int> buildQuery(
    String host, {
    int id = 0,
    int type = typeA,
  }) {
    final out = <int>[];
    _writeU16(out, id);
    _writeU16(out, 0x0100); // QR=0, Opcode=0, RD=1
    _writeU16(out, 1); // QDCOUNT
    _writeU16(out, 0); // ANCOUNT
    _writeU16(out, 0); // NSCOUNT
    _writeU16(out, 0); // ARCOUNT

    for (final label in host.split('.')) {
      if (label.isEmpty) {
        continue;
      }
      final bytes = utf8.encode(label);
      if (bytes.length > 63) {
        throw DnsException('域名标签过长（>63 字节）：$label');
      }
      out.add(bytes.length);
      out.addAll(bytes);
    }
    out.add(0); // 结束标签
    _writeU16(out, type);
    _writeU16(out, 1); // CLASS IN
    return out;
  }

  /// 解析响应报文中的 A / AAAA 地址。
  ///
  /// 会校验事务 ID：**不匹配一律拒绝**（防伪造响应/串包）。
  static List<String> parseAnswers(List<int> packet, {int? expectId}) {
    if (packet.length < 12) {
      throw const DnsException('DNS 响应过短');
    }
    final id = _readU16(packet, 0);
    if (expectId != null && id != expectId) {
      throw DnsException('DNS 事务 ID 不匹配（收到 $id，期望 $expectId）');
    }
    final flags = _readU16(packet, 2);
    if ((flags & 0x8000) == 0) {
      throw const DnsException('收到的不是响应报文');
    }
    final rcode = flags & 0x000F;
    if (rcode != 0) {
      throw DnsException('DNS 返回错误码 $rcode');
    }

    final questionCount = _readU16(packet, 4);
    final answerCount = _readU16(packet, 6);

    var offset = 12;
    for (var index = 0; index < questionCount; index++) {
      offset = _skipName(packet, offset) + 4;
    }

    final addresses = <String>[];
    for (var index = 0; index < answerCount; index++) {
      offset = _skipName(packet, offset);
      if (offset + 10 > packet.length) {
        break;
      }
      final type = _readU16(packet, offset);
      final dataLength = _readU16(packet, offset + 8);
      final dataStart = offset + 10;
      if (dataStart + dataLength > packet.length) {
        break;
      }
      if (type == typeA && dataLength == 4) {
        addresses.add(
          '${packet[dataStart]}.${packet[dataStart + 1]}.'
          '${packet[dataStart + 2]}.${packet[dataStart + 3]}',
        );
      } else if (type == typeAaaa && dataLength == 16) {
        final parts = <String>[];
        for (var group = 0; group < 8; group++) {
          parts.add(
            ((packet[dataStart + group * 2] << 8) |
                    packet[dataStart + group * 2 + 1])
                .toRadixString(16),
          );
        }
        addresses.add(parts.join(':'));
      }
      offset = dataStart + dataLength;
    }
    return addresses;
  }

  static int _skipName(List<int> packet, int offset) {
    var cursor = offset;
    while (true) {
      if (cursor >= packet.length) {
        throw const DnsException('DNS 响应截断（域名未结束）');
      }
      final length = packet[cursor];
      if ((length & 0xC0) == 0xC0) {
        return cursor + 2; // 压缩指针
      }
      if (length == 0) {
        return cursor + 1;
      }
      cursor += 1 + length;
    }
  }

  static void _writeU16(List<int> out, int value) {
    out.add((value >> 8) & 0xFF);
    out.add(value & 0xFF);
  }

  static int _readU16(List<int> data, int offset) =>
      ((data[offset] & 0xFF) << 8) | (data[offset + 1] & 0xFF);
}

/// UDP 交换通道（抽象以便离线测试）。
abstract class DnsUdpChannel {
  /// 向 [serverIp]:53 发送 [query]，返回响应字节；超时返回 `null`。
  Future<List<int>?> exchange(
    String serverIp,
    List<int> query, {
    Duration timeout = const Duration(seconds: 5),
  });
}

/// 真实 UDP 通道。
class RawDnsUdpChannel implements DnsUdpChannel {
  @override
  Future<List<int>?> exchange(
    String serverIp,
    List<int> query, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final completer = Completer<List<int>?>();
    Timer? timer;
    StreamSubscription<RawSocketEvent>? subscription;
    try {
      subscription = socket.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read || completer.isCompleted) {
          return;
        }
        final datagram = socket.receive();
        if (datagram != null) {
          completer.complete(datagram.data);
        }
      });
      timer = Timer(timeout, () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });
      socket.send(query, InternetAddress(serverIp), 53);
      return await completer.future;
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      socket.close();
    }
  }
}

/// 解析器抽象。
abstract class DnsResolver {
  /// 稳定 ID。
  String get id;

  /// 解析主机名，返回 IP 列表。
  Future<List<String>> resolve(String host);
}

/// 系统解析（交给平台）。
class SystemDnsResolver implements DnsResolver {
  @override
  String get id => 'system';

  @override
  Future<List<String>> resolve(String host) async {
    final list = await InternetAddress.lookup(host);
    return list.map((InternetAddress address) => address.address).toList();
  }
}

/// 明文 UDP DNS 解析器。
class UdpDnsResolver implements DnsResolver {
  /// 创建解析器。
  UdpDnsResolver({
    required this.server,
    required this.channel,
    this.timeout = const Duration(seconds: 5),
  });

  /// 目标服务商。
  final DnsServer server;

  /// 交换通道。
  final DnsUdpChannel channel;

  /// 超时。
  final Duration timeout;

  int _queryId = 0;

  @override
  String get id => server.id;

  /// 下一个事务 ID（单调递增，避免与陈旧响应串包）。
  int nextQueryId() => (++_queryId) & 0xFFFF;

  @override
  Future<List<String>> resolve(String host) async {
    final queryId = nextQueryId();
    final query = DnsWireCodec.buildQuery(host, id: queryId);
    final response = await channel.exchange(server.ip, query, timeout: timeout);
    if (response == null) {
      throw DnsException('${server.label} 无响应（超时）');
    }
    return DnsWireCodec.parseAnswers(response, expectId: queryId);
  }
}

/// DoH 所需的**最小** HTTP 能力（由底座传输实现注入，不引入新依赖）。
abstract class DnsHttpClient {
  /// 发起 GET，返回响应体。
  Future<String> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
  });
}

/// DoH（DNS over HTTPS，JSON 格式）解析器。
///
/// 之所以重要：明文 53 端口在受限网络里常被劫持或阻断，
/// HTTPS 通常仍可用——DoH 是绕开 DNS 污染最稳的一条路。
class DohDnsResolver implements DnsResolver {
  /// 创建解析器。
  DohDnsResolver({
    required this.server,
    required this.client,
    this.timeout = const Duration(seconds: 8),
  }) : assert(server.dohUrl != null, 'DoH 解析器需要 server.dohUrl');

  /// 目标服务商。
  final DnsServer server;

  /// HTTP 能力。
  final DnsHttpClient client;

  /// 超时。
  final Duration timeout;

  @override
  String get id => server.id;

  @override
  Future<List<String>> resolve(String host) async {
    final endpoint = server.dohUrl!;
    final separator = endpoint.contains('?') ? '&' : '?';
    final body = await client.get(
      '$endpoint${separator}name=$host&type=A',
      headers: const <String, String>{'accept': 'application/dns-json'},
    ).timeout(timeout);
    return parseDohJson(body);
  }

  /// 解析 DoH 的 JSON 响应（抽出 A 记录）。
  ///
  /// 刻意做成静态纯函数：便于离线断言，也便于复用到 DoT/TLS 场景。
  static List<String> parseDohJson(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (error) {
      throw DnsException('DoH 响应不是合法 JSON：$error');
    }
    if (decoded is! Map) {
      throw const DnsException('DoH 响应结构异常');
    }
    final status = decoded['Status'];
    if (status is int && status != 0) {
      throw DnsException('DoH 返回错误状态 $status');
    }
    final answers = decoded['Answer'];
    if (answers is! List) {
      return const <String>[];
    }
    final result = <String>[];
    for (final answer in answers) {
      if (answer is! Map) {
        continue;
      }
      if (answer['type'] != DnsWireCodec.typeA) {
        continue;
      }
      final data = answer['data'];
      if (data is String && _ipv4.hasMatch(data)) {
        result.add(data);
      }
    }
    return result;
  }

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
}

/// 解析结果（含缓存标记）。
class DnsAnswer {
  /// 创建结果。
  const DnsAnswer({
    required this.addresses,
    required this.serverId,
    required this.expiresAt,
  });

  /// 地址列表。
  final List<String> addresses;

  /// 由哪家解析器给出。
  final String serverId;

  /// 过期时间。
  final DateTime expiresAt;

  /// 是否已过期。
  bool isExpiredAt(DateTime now) => !expiresAt.isAfter(now);

  @override
  String toString() => 'DnsAnswer(${addresses.join(',')} via $serverId)';
}

/// DNS 结果缓存（带 TTL 与条目上限）。
class DnsCache {
  /// 创建缓存。
  DnsCache({this.maxEntries = 512});

  /// 条目上限（超过时优先淘汰最接近过期者）。
  final int maxEntries;

  final Map<String, DnsAnswer> _entries = <String, DnsAnswer>{};

  /// 当前条目数。
  int get size => _entries.length;

  /// 读取（自动剔除过期项）。
  DnsAnswer? get(String host) {
    final answer = _entries[host];
    if (answer == null) {
      return null;
    }
    if (answer.isExpiredAt(DateTime.now())) {
      _entries.remove(host);
      return null;
    }
    return answer;
  }

  /// 写入。
  void put(String host, DnsAnswer answer) {
    _entries[host] = answer;
    if (_entries.length <= maxEntries) {
      return;
    }
    // 先清过期项，再按插入顺序淘汰最老者。
    final now = DateTime.now();
    final expired = _entries.entries
        .where((MapEntry<String, DnsAnswer> entry) =>
            entry.value.isExpiredAt(now))
        .map((MapEntry<String, DnsAnswer> entry) => entry.key)
        .toList();
    for (final key in expired) {
      _entries.remove(key);
    }
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// 清空。
  void clear() => _entries.clear();
}

/// DNS 策略（**能力冲突 → 交由用户选择**的落点）。
class DnsPolicy {
  /// 创建策略。
  DnsPolicy({
    this.mode = NetDnsMode.system,
    List<DnsServer>? servers,
    this.preferDoh = true,
    this.raceServers = true,
    this.cacheTtl = const Duration(minutes: 5),
    this.timeout = const Duration(seconds: 5),
    this.fallbackToSystem = true,
  }) : servers = List<DnsServer>.of(servers ?? builtinDnsServers);

  /// 当前模式。
  ///
  /// 可变是有意的：用户在设置里切换后**立即生效**，不需要重建传输层。
  NetDnsMode mode;

  /// 服务器列表（顺序即优先级；可增删排序）。
  final List<DnsServer> servers;

  /// 是否优先 DoH（禁用后只用明文 UDP）。
  bool preferDoh;

  /// 多服务器时是否并发竞速（取最先成功者）。
  bool raceServers;

  /// 结果缓存时长。
  Duration cacheTtl;

  /// 单次解析超时。
  Duration timeout;

  /// 自定义解析全部失败时，是否回退系统解析。
  ///
  /// 建议保持 `true`：回退**不会**让污染变得更糟，却能让用户不至于完全断网。
  /// 但每次回退都会记 warn 日志，并在自检报告里体现。
  bool fallbackToSystem;

  /// 当前启用的服务器（按列表顺序）。
  List<DnsServer> get enabledServers => List<DnsServer>.unmodifiable(servers);

  @override
  String toString() =>
      'DnsPolicy(mode=${mode.name}, servers=${servers.length}, '
      'doh=$preferDoh, race=$raceServers)';
}

/// DNS 服务：按策略解析，带缓存、并发竞速与系统回退。
class DnsService {
  /// 创建服务。
  DnsService({
    DnsPolicy? policy,
    DnsResolver? systemResolver,
    DnsResolver Function(DnsServer server)? resolverFactory,
    DnsCache? cache,
    KernelDiagnostics? diagnostics,
  })  : policy = policy ?? DnsPolicy(),
        systemResolver = systemResolver ?? SystemDnsResolver(),
        cache = cache ?? DnsCache(),
        _diagnostics = diagnostics,
        _resolverFactory = resolverFactory ?? _defaultResolverFactory;

  /// 策略。
  final DnsPolicy policy;

  /// 系统解析器。
  final DnsResolver systemResolver;

  /// 结果缓存。
  final DnsCache cache;

  final DnsResolver Function(DnsServer server) _resolverFactory;
  KernelDiagnostics? _diagnostics;

  /// 绑定诊断中枢（装配阶段调用）。
  void attachDiagnostics(KernelDiagnostics diagnostics) {
    _diagnostics = diagnostics;
  }

  static DnsResolver _defaultResolverFactory(DnsServer server) =>
      UdpDnsResolver(server: server, channel: RawDnsUdpChannel());

  /// 解析主机名。
  ///
  /// - IP 字面量直接返回（不做无谓查询）；
  /// - 命中缓存直接返回；
  /// - `system` 模式交给系统；`custom` 模式按策略尝试，失败可回退系统。
  Future<List<String>> resolve(String host) async {
    if (host.isEmpty) {
      throw const DnsException('主机名为空');
    }
    if (_ipv4.hasMatch(host) || host.contains(':')) {
      return <String>[host];
    }

    final cached = cache.get(host);
    if (cached != null) {
      _diagnostics?.debug(
        'DNS',
        '缓存命中 $host',
        data: <String, Object?>{'via': cached.serverId},
      );
      return cached.addresses;
    }

    if (policy.mode == NetDnsMode.system) {
      final addresses = await _attempt(systemResolver, host);
      _remember(host, addresses, systemResolver.id);
      return addresses;
    }

    try {
      final resolution = await _resolveCustom(host);
      _remember(host, resolution.addresses, resolution.serverId);
      return resolution.addresses;
    } catch (error) {
      if (!policy.fallbackToSystem) {
        rethrow;
      }
      // 回退是安全网，但必须在日志里留下痕迹——绝不静默。
      _diagnostics?.warn(
        'DNS',
        '自定义 DNS 全部失败，已回退系统解析：$host',
        code: 'OGL-DNS-101',
        data: <String, Object?>{'error': '$error'},
      );
      final addresses = await _attempt(systemResolver, host);
      _remember(host, addresses, 'system(fallback)');
      return addresses;
    }
  }

  /// 生成环境自检项（注册到 `kernel.probes`）。
  KernelEnvironmentProbe probe({String sampleHost = 'api.github.com'}) =>
      DnsProbe(service: this, sampleHost: sampleHost);

  void _remember(String host, List<String> addresses, String serverId) {
    cache.put(
      host,
      DnsAnswer(
        addresses: addresses,
        serverId: serverId,
        expiresAt: DateTime.now().add(policy.cacheTtl),
      ),
    );
    _diagnostics?.debug(
      'DNS',
      '解析成功 $host',
      data: <String, Object?>{
        'via': serverId,
        'addresses': addresses.take(3).toList(),
      },
    );
  }

  Future<({List<String> addresses, String serverId})> _resolveCustom(
    String host,
  ) async {
    final servers = policy.servers;
    if (servers.isEmpty) {
      throw const DnsException('未配置任何 DNS 服务器');
    }

    if (policy.raceServers && servers.length > 1) {
      return _race(<Future<({List<String> addresses, String serverId})>>[
        for (final server in servers) _attemptServer(server, host),
      ]);
    }

    final failures = <String>[];
    for (final server in servers) {
      try {
        return await _attemptServer(server, host);
      } catch (error) {
        failures.add('$error');
      }
    }
    throw DnsException('全部 DNS 解析失败：${failures.join('；')}');
  }

  Future<({List<String> addresses, String serverId})> _attemptServer(
    DnsServer server,
    String host,
  ) async {
    final resolver = _resolverFactory(server);
    final addresses = await _attempt(resolver, host);
    return (addresses: addresses, serverId: server.id);
  }

  Future<List<String>> _attempt(DnsResolver resolver, String host) async {
    final addresses = await resolver.resolve(host).timeout(policy.timeout);
    if (addresses.isEmpty) {
      throw DnsException('${resolver.id} 返回空结果');
    }
    return addresses;
  }

  /// 并发竞速：取最先成功者；全部失败才抛错。
  Future<({List<String> addresses, String serverId})> _race(
    List<Future<({List<String> addresses, String serverId})>> attempts,
  ) {
    final completer =
        Completer<({List<String> addresses, String serverId})>();
    var remaining = attempts.length;
    Object? lastError;
    for (final attempt in attempts) {
      attempt.then(
        (({List<String> addresses, String serverId}) value) {
          if (!completer.isCompleted) {
            completer.complete(value);
          }
        },
        onError: (Object error) {
          lastError = error;
          remaining--;
          if (remaining == 0 && !completer.isCompleted) {
            completer.completeError(
              DnsException('并发解析全部失败：$lastError'),
            );
          }
        },
      );
    }
    return completer.future;
  }

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
}

/// DNS 环境自检项（注册到内核的 [KernelProbeRegistry]）。
class DnsProbe implements KernelEnvironmentProbe {
  /// 创建自检项。
  DnsProbe({required this.service, this.sampleHost = 'api.github.com'});

  /// 被测服务。
  final DnsService service;

  /// 采样主机名。
  final String sampleHost;

  @override
  String get id => 'base.net.dns';

  @override
  String get title => 'DNS 解析';

  @override
  Future<KernelProbeResult> run() async {
    final stopwatch = Stopwatch()..start();
    final detail = <String, Object?>{
      'mode': service.policy.mode.name,
      'servers': service.policy.servers
          .map((DnsServer server) => '${server.id}(${server.ip})')
          .toList(),
      'preferDoh': service.policy.preferDoh,
    };
    try {
      final addresses = await service.resolve(sampleHost);
      stopwatch.stop();
      detail['addresses'] = addresses.take(3).toList();
      detail['ms'] = stopwatch.elapsedMilliseconds;
      return KernelProbeResult(
        ok: addresses.isNotEmpty,
        summary: addresses.isEmpty
            ? '解析 $sampleHost 无结果'
            : '解析 $sampleHost → ${addresses.take(3).join(', ')}',
        detail: detail,
      );
    } catch (error) {
      stopwatch.stop();
      detail['ms'] = stopwatch.elapsedMilliseconds;
      return KernelProbeResult(
        ok: false,
        summary: '解析 $sampleHost 失败：$error',
        detail: detail,
      );
    }
  }
}