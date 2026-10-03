/// L2 中枢级 · Actions 运行日志（**带令牌下载 zip + 解压**）。
///
/// GitHub 的日志接口 `GET /repos/{o}/{r}/actions/runs/{id}/logs`
/// 返回 **302 → zip**（逐个 job 一个 `.txt`），必须带令牌请求。
/// 本服务负责：带令牌拉取二进制 → 用 `archive` 解压 → 返回
/// `job 名 → 文本` 映射，供运行详情页展示与检索。
///
/// ## 传输实现（2026-10-03）
/// 由 Dio 改为 `dart:io HttpClient`：这里只需要"取一段字节"，没必要为它引入一个
/// HTTP 框架；同时**禁用连接复用**，与底座传输保持同一策略，避开
/// `Connection closed before full header` 一类故障。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Actions 日志服务。
class IxActionLogs {
  /// 创建服务。
  ///
  /// [tokenProvider] 返回当前令牌明文（未登录返回 `null`）。
  /// [clientFactory] 仅供测试注入（默认每次请求新建一个客户端并即用即关）。
  IxActionLogs({
    required this.tokenProvider,
    HttpClient Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? _defaultClient;

  /// 令牌提供者。
  final Future<String?> Function() tokenProvider;

  final HttpClient Function() _clientFactory;

  static const Duration _connectTimeout = Duration(seconds: 20);
  static const Duration _receiveTimeout = Duration(minutes: 5);

  static HttpClient _defaultClient() {
    final HttpClient client = HttpClient();
    // 不用连接复用（与底座传输保持同一策略）。
    client.persistentConnection = false;
    client.idleTimeout = const Duration(seconds: 3);
    client.connectionTimeout = _connectTimeout;
    client.userAgent = 'OhGithubLost';
    return client;
  }

  /// 拉取一次运行的日志；失败返回空映射（调用方如实提示）。
  Future<Map<String, String>> fetch(String fullName, int runId) async {
    final String? token = await tokenProvider();
    final HttpClient client = _clientFactory();
    final Uri uri = Uri.parse(
      'https://api.github.com/repos/$fullName/actions/runs/$runId/logs',
    );
    try {
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(_connectTimeout);
      request.followRedirects = true;
      request.maxRedirects = 5;
      request.headers.set('accept', 'application/vnd.github+json');
      if (token != null) {
        request.headers.set('authorization', 'Bearer $token');
      }
      final HttpClientResponse response =
          await request.close().timeout(_receiveTimeout);
      if (response.statusCode < 200 || response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final List<int> data = await _collect(response).timeout(_receiveTimeout);
      if (data.isEmpty) {
        return const <String, String>{};
      }
      return _decodeZip(data);
    } finally {
      // 即用即关：不复用、不泄漏。
      client.close(force: true);
    }
  }

  /// 读取全部响应字节。
  static Future<List<int>> _collect(HttpClientResponse response) async {
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  }

  /// 解压日志 zip → `job 名 → 文本`。
  static Map<String, String> _decodeZip(List<int> bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final Map<String, String> out = <String, String>{};
    for (final ArchiveFile file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.txt')) {
        continue;
      }
      out[_labelOf(file.name)] = utf8.decode(
        file.content,
        allowMalformed: true,
      );
    }
    return out;
  }

  /// zip 内条目形如 `job 名/1_步骤.txt` → 取 `job 名` 作为分组标题。
  static String _labelOf(String path) {
    final int slash = path.indexOf('/');
    if (slash <= 0) {
      return path.replaceAll('.txt', '');
    }
    return path.substring(0, slash);
  }
}