/// L1 硬件层 · **多连接分片（HTTP Range）下载**（实现启动层契约 [DownloadEngine]）。
///
/// ## 为什么需要它
/// `background_downloader` 是单连接下载：大文件（Release 附件动辄几十 MB）只能
/// 吃一条 TCP 的带宽，用户实测"再快的网也跑不满"。本文件用 `Range` 请求把文件
/// 切成若干片、**并发拉取**，最后顺序合并成目标文件。
///
/// ## 为什么每片写独立临时文件（而不是共用一个 `RandomAccessFile`）
/// 项目早期正是"多 worker 共用一个文件句柄并发定位写入"，导致偶发**错位写坏**。
/// 这里改为每片各写 `<目标>.partN`，全部成功后再顺序合并：
/// - 没有共享可写状态 → 不存在错位竞争；
/// - 任一分片失败/取消 → 删掉所有分片，**不留半成品**（不会把坏文件当成功）。
///
/// ## 与库的分工
/// 本文件是**增补引擎**：不支持 Range（或探测失败）时抛 [DownloadUnsupported]，
/// 由中枢层回退到库任务，绝不硬撑。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../kernel/contract/download_engine.dart';

/// 一个字节区间（**闭区间**：`start..end` 含两端）。
@immutable
class OgLByteRange {
  /// 创建区间。
  const OgLByteRange(this.start, this.end);

  /// 起始偏移（含）。
  final int start;

  /// 结束偏移（含）。
  final int end;

  /// 区间长度。
  int get length => end - start + 1;

  @override
  String toString() => '$start-$end';
}

/// 分片规划（**纯函数**，可单测）。
abstract final class OgLChunkPlan {
  /// 把 [total] 字节切成至多 [connections] 片。
  ///
  /// 规则：
  /// - 每片不小于 [minChunkBytes]（小文件不为它开一堆连接）；
  /// - 分片数 = `min(connections, ceil(total / minChunkBytes))`；
  /// - 余数补给**最后一片**，保证并集正好覆盖 `0..total-1`（不重不漏）。
  static List<OgLByteRange> of({
    required int total,
    required int connections,
    int minChunkBytes = 1 << 20,
  }) {
    if (total <= 0) {
      return const <OgLByteRange>[];
    }
    final int maxConnections = connections < 1 ? 1 : connections;
    final int minChunk = minChunkBytes < 1 ? 1 : minChunkBytes;
    final int byMin = (total + minChunk - 1) ~/ minChunk;
    final int count =
        maxConnections < byMin ? maxConnections : (byMin < 1 ? 1 : byMin);
    final int base = total ~/ count;
    final List<OgLByteRange> out = <OgLByteRange>[];
    int start = 0;
    for (int i = 0; i < count; i++) {
      final int end = i == count - 1 ? total - 1 : start + base - 1;
      out.add(OgLByteRange(start, end));
      start = end + 1;
    }
    return out;
  }
}

/// 取消令牌（实现契约；暂停 / 取消都走它）。
class OgLRangeCancelToken implements DownloadCancelToken {
  bool _canceled = false;

  @override
  bool get isCancelled => _canceled;

  @override
  void cancel() => _canceled = true;
}

/// 多连接分片下载器。
class OgLRangeDownloader implements DownloadEngine {
  /// 创建。
  ///
  /// [client] 可注入（复用既有连接池）；不传则自建并在 [close] 时关闭。
  OgLRangeDownloader({HttpClient? client, this.userAgent = 'OhGithubLost'})
      : _owned = client == null,
        _client = client ?? HttpClient() {
    _client.userAgent = userAgent;
  }

  final HttpClient _client;
  final bool _owned;

  /// User-Agent。
  final String userAgent;

  /// 每片最小字节（比它小的文件不值得分片）。
  static const int minChunkBytes = 1 << 20;

  @override
  Future<DownloadProbe> probe(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    const Duration timeout = Duration(seconds: 15);
    try {
      final HttpClientRequest head = await _client.headUrl(url);
      _applyHeaders(head, headers);
      head.persistentConnection = false;
      final HttpClientResponse response = await head.close().timeout(timeout);
      final int? length =
          response.contentLength >= 0 ? response.contentLength : null;
      final String acceptRanges =
          response.headers.value(HttpHeaders.acceptRangesHeader) ?? '';
      final String? fileName = _fileNameOf(response);
      final int status = response.statusCode;
      await response.drain<void>();
      if (status == 200 && acceptRanges.contains('bytes')) {
        return DownloadProbe(
          supportsRange: true,
          total: length,
          fileName: fileName,
          statusCode: status,
        );
      }
      // 有些服务端只在带 Range 的 GET 上才表态，复核一次。
      return await _probeByRange(url, headers: headers, timeout: timeout);
    } catch (error) {
      // HEAD 被禁（405 等）时同样用 Range 复核；仍失败则视为不支持。
      try {
        return await _probeByRange(url, headers: headers, timeout: timeout);
      } catch (inner) {
        return const DownloadProbe(supportsRange: false);
      }
    }
  }

  Future<DownloadProbe> _probeByRange(
    Uri url, {
    Map<String, String>? headers,
    required Duration timeout,
  }) async {
    final HttpClientRequest request = await _client.getUrl(url);
    _applyHeaders(request, headers);
    request.persistentConnection = false;
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
    final HttpClientResponse response = await request.close().timeout(timeout);
    final int status = response.statusCode;
    final String? contentRange =
        response.headers.value(HttpHeaders.contentRangeHeader);
    final String? fileName = _fileNameOf(response);
    await response.drain<void>();
    if (status != HttpStatus.partialContent) {
      return DownloadProbe(supportsRange: false, statusCode: status);
    }
    return DownloadProbe(
      supportsRange: true,
      total: _totalFromContentRange(contentRange),
      fileName: fileName,
      statusCode: status,
    );
  }

  @override
  Future<int> fetch(
    DownloadRequest request, {
    void Function(int received, int total)? onProgress,
    DownloadCancelToken? cancel,
  }) async {
    if (request.total <= 0) {
      throw const DownloadUnsupported('总长度未知，无法分片');
    }
    final List<OgLByteRange> plan = OgLChunkPlan.of(
      total: request.total,
      connections: request.connections,
      minChunkBytes: minChunkBytes,
    );
    if (plan.length < 2) {
      throw const DownloadUnsupported('分片数不足（文件太小或并发不足）');
    }
    final File target = File(request.targetPath);
    final List<File> parts = <File>[
      for (int i = 0; i < plan.length; i++)
        File('${request.targetPath}.part$i'),
    ];
    int received = 0;

    bool merged = false;
    try {
      await Future.wait<void>(<Future<void>>[
        for (int i = 0; i < plan.length; i++)
          _fetchPart(
            url: request.url,
            part: parts[i],
            range: plan[i],
            headers: request.headers,
            cancel: cancel,
            onBytes: (int delta) {
              received += delta;
              onProgress?.call(received, request.total);
            },
          ),
      ]);
      // 合并：顺序拼接，写盘一次成型。
      //
      // ★ 合并阶段失败必须把半成品删掉：契约要求「失败不留半成品」（见
      //   kernel/contract/download_engine.dart），而此前 finally 只删分片，
      //   长度不符或 addStream 抛错时会把一个残缺的 target 留在磁盘上 ——
      //   中控回退到库任务时用的还是同一个路径。
      final IOSink sink = target.openWrite();
      try {
        for (final File part in parts) {
          await sink.addStream(part.openRead());
        }
      } finally {
        await sink.close();
      }
      final int written = await target.length();
      if (written != request.total) {
        throw DownloadHttpException('合并后长度不符：$written != ${request.total}');
      }
      merged = true;
      return written;
    } finally {
      if (!merged) {
        // 合并没成功：target 是半成品，一并清掉（失败不留半成品）。
        try {
          if (await target.exists()) {
            await target.delete();
          }
        } catch (_) {
          // 清理失败不改变结论：本次下载已经失败，上层会如实报错。
        }
      }
      for (final File part in parts) {
        if (await part.exists()) {
          try {
            await part.delete();
          } catch (_) {
            // 清理失败不影响主流程（下次同名任务会重建）。
          }
        }
      }
    }
  }

  Future<void> _fetchPart({
    required Uri url,
    required File part,
    required OgLByteRange range,
    required Map<String, String> headers,
    DownloadCancelToken? cancel,
    required void Function(int delta) onBytes,
  }) async {
    if (cancel?.isCancelled ?? false) {
      throw const DownloadCanceled();
    }
    final HttpClientRequest request = await _client.getUrl(url);
    _applyHeaders(request, headers);
    request.persistentConnection = false;
    request.headers
        .set(HttpHeaders.rangeHeader, 'bytes=${range.start}-${range.end}');
    final HttpClientResponse response = await request.close();
    if (response.statusCode != HttpStatus.partialContent) {
      throw DownloadHttpException(
        '分片 $range 返回 ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    final IOSink sink = part.openWrite();
    int got = 0;
    try {
      await for (final List<int> chunk in response) {
        if (cancel?.isCancelled ?? false) {
          throw const DownloadCanceled();
        }
        sink.add(chunk);
        got += chunk.length;
        onBytes(chunk.length);
      }
    } finally {
      await sink.close();
    }
    if (got != range.length) {
      // 长度不符：这一片不可信（由调用方删除全部分片）。
      throw DownloadHttpException('分片 $range 长度不符：$got != ${range.length}');
    }
  }

  void _applyHeaders(HttpClientRequest request, Map<String, String>? headers) {
    if (headers == null) {
      return;
    }
    for (final MapEntry<String, String> entry in headers.entries) {
      request.headers.set(entry.key, entry.value);
    }
  }

  @override
  void close() {
    if (_owned) {
      _client.close(force: true);
    }
  }

  @override
  DownloadCancelToken newCancelToken() => OgLRangeCancelToken();

  static int? _totalFromContentRange(String? value) {
    if (value == null) {
      return null;
    }
    final int slash = value.lastIndexOf('/');
    if (slash < 0) {
      return null;
    }
    return int.tryParse(value.substring(slash + 1).trim());
  }

  static String? _fileNameOf(HttpClientResponse response) {
    final String? disposition =
        response.headers.value('content-disposition');
    if (disposition == null) {
      return null;
    }
    final RegExpMatch? match =
        RegExp('filename="?([^";]+)"?').firstMatch(disposition);
    return match?.group(1);
  }
}