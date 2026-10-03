/// L2 中枢级 · Actions 运行日志（**带令牌下载 zip + 解压**）。
///
/// GitHub 的日志接口 `GET /repos/{o}/{r}/actions/runs/{id}/logs`
/// 返回 **302 → zip**（逐个 job 一个 `.txt`），必须带令牌请求。
/// 本服务负责：带令牌拉取二进制 → 用 `archive` 解压 → 返回
/// `job 名 → 文本` 映射，供运行详情页展示与检索。
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';

/// Actions 日志服务。
class IxActionLogs {
  /// 创建服务。
  ///
  /// [tokenProvider] 返回当前令牌明文（未登录返回 `null`）。
  IxActionLogs({
    required this.tokenProvider,
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(minutes: 5),
                headers: const <String, String>{'User-Agent': 'OhGithubLost'},
              ),
            );

  /// 令牌提供者。
  final Future<String?> Function() tokenProvider;

  final Dio _dio;

  /// 拉取一次运行的日志；失败返回空映射（调用方如实提示）。
  Future<Map<String, String>> fetch(String fullName, int runId) async {
    final String? token = await tokenProvider();
    final Response<List<int>> response = await _dio.get<List<int>>(
      'https://api.github.com/repos/$fullName/actions/runs/$runId/logs',
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: true,
        headers: <String, String>{
          'accept': 'application/vnd.github+json',
          if (token != null) 'authorization': 'Bearer $token',
        },
        validateStatus: (int? status) =>
            status != null && status >= 200 && status < 400,
      ),
    );
    final List<int>? data = response.data;
    if (data == null || data.isEmpty) {
      return const <String, String>{};
    }
    return _decodeZip(data);
  }

  /// 解压日志 zip → `job 名 → 文本`。
  static Map<String, String> _decodeZip(List<int> bytes) {
    final Archive archive = ZipDecoder().decodeBytes(bytes);
    final Map<String, String> out = <String, String>{};
    for (final ArchiveFile file in archive.files) {
      if (!file.isFile || !file.name.toLowerCase().endsWith('.txt')) {
        continue;
      }
      out[_labelOf(file.name)] = utf8.decode(file.content, allowMalformed: true);
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