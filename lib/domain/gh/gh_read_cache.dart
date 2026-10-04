/// L2 中枢级 · 只读端点缓存（JSON）。
///
/// ## 与底座 `RepositoryCache` 的分工
/// 后者面向**文件内容 / 目录**，会与远端 `contents` 做一致性回源（D1–D7）；
/// 本缓存只服务**只读的列表 / 详情端点**（releases / branches / commits /
/// issues / pulls / Actions / 仓库详情 …），以「原始响应文本 + 抓取时间」落盘，
/// 按端点设定 TTL。
///
/// ## 设计要点（R4：缓存时长）
/// - **只缓存成功的 GET**（2xx）；写请求一律让整体失效；
/// - **账号隔离**：键里带 accountId，切换账号时 [clear]（用户明确要求）；
/// - **换纪元清理**：`clear()` 只递增纪元计数，旧条目自然失联（无需删除 API）；
/// - **任何异常都不阻断读取**：读失败 → 当作未命中（并留痕，不静默）。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../kernel/contract/disk_store.dart';

import '../../kernel/diagnostics.dart';

/// 只读端点缓存。
class GhReadCache {
  /// 创建缓存。
  GhReadCache({
    required this.store,
    required Future<String?> Function() accountId,
    KernelDiagnostics? diagnostics,
  })  : _accountId = accountId,
        _diagnostics = diagnostics;

  /// 底层 KV。
  final DiskKv store;

  final Future<String?> Function() _accountId;
  final KernelDiagnostics? _diagnostics;

  static const String _epochKey = 'ogl.rc.epoch';
  static const String _prefix = 'ogl.rc.v1';

  int? _epochMemo;

  Future<int> _epoch({bool refresh = false}) async {
    if (!refresh && _epochMemo != null) {
      return _epochMemo!;
    }
    try {
      final String? raw = await store.read(_epochKey);
      final int value = int.tryParse(raw ?? '') ?? 0;
      _epochMemo = value;
      return value;
    } catch (error) {
      _diagnostics?.warn(
        'CACHE',
        '读取只读缓存纪元失败：$error',
        code: 'OGL-RC-001',
      );
      _epochMemo = 0;
      return 0;
    }
  }

  Future<String> _key(
    String path,
    Map<String, String> query,
    String account,
  ) async {
    final int epoch = await _epoch();
    final String raw = '$account\n$path\n${_canonicalQuery(query)}';
    final String digest =
        sha256.convert(utf8.encode(raw)).toString().substring(0, 32);
    return '$_prefix.$epoch.$digest';
  }

  static String _canonicalQuery(Map<String, String> query) {
    final List<String> keys = query.keys.toList()..sort();
    return keys.map((String k) => '$k=${query[k]}').join('&');
  }

  /// 读：命中且未过期返回原始文本；否则返回 `null`（当作未命中）。
  Future<String?> get(
    String path,
    Map<String, String> query,
    Duration maxAge, {
    bool bypass = false,
  }) async {
    if (bypass) {
      return null;
    }
    try {
      final String account = await _accountOrGuest();
      final String key = await _key(path, query, account);
      final String? raw = await store.read(key);
      if (raw == null) {
        return null;
      }
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final Object? at = decoded['at'];
      final Object? body = decoded['body'];
      if (at is! int || body is! String) {
        return null;
      }
      if (DateTime.now().millisecondsSinceEpoch - at > maxAge.inMilliseconds) {
        return null;
      }
      return body;
    } catch (error) {
      _diagnostics?.warn(
        'CACHE',
        '读取只读缓存失败：$error',
        code: 'OGL-RC-002',
      );
      return null;
    }
  }

  /// 写：保存原始响应文本。
  Future<void> put(
    String path,
    Map<String, String> query,
    String body,
  ) async {
    try {
      final String account = await _accountOrGuest();
      final String key = await _key(path, query, account);
      await store.write(
        key,
        jsonEncode(<String, Object?>{
          'at': DateTime.now().millisecondsSinceEpoch,
          'body': body,
        }),
      );
    } catch (error) {
      _diagnostics?.warn(
        'CACHE',
        '写入只读缓存失败：$error',
        code: 'OGL-RC-003',
      );
    }
  }

  Future<String> _accountOrGuest() async {
    try {
      final String? id = await _accountId();
      if (id != null && id.isNotEmpty) {
        return id;
      }
    } catch (error) {
      _diagnostics?.warn(
        'CACHE',
        '读取账号标识失败：$error',
        code: 'OGL-RC-004',
      );
    }
    return 'guest';
  }

  /// 清空（切换账号 / 用户手动清缓存）：递增纪元，旧条目自然失联。
  Future<void> clear() async {
    try {
      final int next = (await _epoch(refresh: true)) + 1;
      await store.write(_epochKey, '$next');
      _epochMemo = next;
    } catch (error) {
      _diagnostics?.warn(
        'CACHE',
        '清空只读缓存失败：$error',
        code: 'OGL-RC-005',
      );
    }
  }
}
