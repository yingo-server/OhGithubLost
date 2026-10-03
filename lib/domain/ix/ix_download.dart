/// L2 中枢级 · 内建下载器（多线程分块 / 断点续传 / 进度广播）。
///
/// ## 为什么放在中枢层
/// 它既要用底座的应用目录（[OgLAppDirs]），又要被展示层当作业务能力使用；
/// 放在 L2 让**页面只 import 中枢类型**，不破坏分层。
///
/// ## 下载策略
/// - 分块下载：`Range` 请求 + 多分块并发；
/// - 分块大小 512 KB，保证文件尾部仍有足量分块可并发（≥ 32 个分块）；
/// - 文件小于 16 MB：按 32 等分一次性铺满并发；
/// - 服务器不支持 `Range`（返回 200）：自动退回单流下载；
/// - 暂停 / 继续：记录已完成分块，继续时只补缺失分块；
/// - 进度：已收字节 / 总字节 / 即时速率，节流广播给 UI。
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../base/disk/app_dirs.dart';

/// 下载分类（决定落到哪个子目录）。
enum IxDownloadCategory {
  /// Release 附件。
  release,

  /// 仓库文件。
  repo,

  /// Gist 文件。
  gist,

  /// 其它。
  other;

  /// 子目录名。
  String get folder => switch (this) {
        IxDownloadCategory.release => 'release',
        IxDownloadCategory.repo => 'repo',
        IxDownloadCategory.gist => 'gist',
        IxDownloadCategory.other => 'other',
      };

  /// 展示名。
  String get label => switch (this) {
        IxDownloadCategory.release => 'Release',
        IxDownloadCategory.repo => '仓库文件',
        IxDownloadCategory.gist => 'Gist',
        IxDownloadCategory.other => '其它',
      };
}

/// 下载状态。
enum IxDownloadStatus {
  /// 排队中。
  queued,

  /// 下载中。
  running,

  /// 已暂停。
  paused,

  /// 已完成。
  completed,

  /// 失败。
  failed,

  /// 已取消。
  canceled;

  /// 展示名。
  String get label => switch (this) {
        IxDownloadStatus.queued => '排队中',
        IxDownloadStatus.running => '下载中',
        IxDownloadStatus.paused => '已暂停',
        IxDownloadStatus.completed => '已完成',
        IxDownloadStatus.failed => '失败',
        IxDownloadStatus.canceled => '已取消',
      };
}

/// 一个下载任务的可读快照（不可变）。
@immutable
class IxDownloadTask {
  /// 创建快照。
  const IxDownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.category,
    required this.savePath,
    required this.status,
    required this.received,
    required this.total,
    required this.bytesPerSecond,
    required this.createdAt,
    this.error,
    this.threadsActive = 0,
  });

  /// 任务 id。
  final String id;

  /// 源地址。
  final String url;

  /// 文件名。
  final String fileName;

  /// 分类。
  final IxDownloadCategory category;

  /// 保存路径（绝对路径）。
  final String savePath;

  /// 状态。
  final IxDownloadStatus status;

  /// 已收字节。
  final int received;

  /// 总字节（0 表示未知）。
  final int total;

  /// 即时速率（字节 / 秒）。
  final double bytesPerSecond;

  /// 创建时间。
  final DateTime createdAt;

  /// 失败原因。
  final String? error;

  /// 当前活跃分块数。
  final int threadsActive;

  /// 进度（0–1；总长未知时为 0）。
  double get progress => total <= 0 ? 0 : (received / total).clamp(0, 1).toDouble();

  /// 百分比（0–100）。
  int get percent => (progress * 100).round();

  /// 是否仍在进行。
  bool get busy =>
      status == IxDownloadStatus.running || status == IxDownloadStatus.queued;

  /// 是否已完成。
  bool get done => status == IxDownloadStatus.completed;
}

/// 下载管理器（展示层唯一入口）。
class IxDownloadManager extends ChangeNotifier {
  /// 创建管理器。
  IxDownloadManager({Dio? dio, int threads = 32, int chunkSize = 512 * 1024})
      : _dio = dio ?? _defaultDio(),
        _threads = threads < 1 ? 1 : threads,
        _chunkSize = chunkSize < 64 * 1024 ? 64 * 1024 : chunkSize;

  static Dio _defaultDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 10),
        headers: const <String, String>{'User-Agent': 'OhGithubLost'},
      ));

  final Dio _dio;
  final int _threads;
  final int _chunkSize;

  final Map<String, _DownloadJob> _jobs = <String, _DownloadJob>{};
  final Map<String, IxDownloadTask> _snapshots = <String, IxDownloadTask>{};
  int _seq = 0;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

  /// 任务列表（新的在前）。
  List<IxDownloadTask> get tasks {
    final List<IxDownloadTask> list = _snapshots.values.toList();
    list.sort((IxDownloadTask a, IxDownloadTask b) =>
        b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 是否有任务。
  bool get isEmpty => _snapshots.isEmpty;

  /// 进行中的任务数。
  int get runningCount => _jobs.values
      .where((_DownloadJob job) => job.snapshot().status == IxDownloadStatus.running)
      .length;

  /// 加入一个下载任务（自动落盘到 `<ogl>/download/<分类>/`）。
  Future<IxDownloadTask> enqueue({
    required String url,
    required String fileName,
    IxDownloadCategory category = IxDownloadCategory.other,
    Map<String, String> headers = const <String, String>{},
  }) async {
    final String id = 'dl-${DateTime.now().microsecondsSinceEpoch}-${_seq++}';
    final String root = await OgLAppDirs.downloads();
    final String dir = '$root/${category.folder}';
    final String safe = _sanitize(fileName.isEmpty ? 'download_$id' : fileName);
    final String path = await _uniquePath(dir, safe);
    final _DownloadJob job = _DownloadJob(
      id: id,
      url: url,
      fileName: safe,
      category: category,
      savePath: path,
      headers: headers,
      dio: _dio,
      threads: _threads,
      chunkSize: _chunkSize,
      onChanged: _onJobChanged,
    );
    _jobs[id] = job;
    _snapshots[id] = job.snapshot();
    notifyListeners();
    unawaited(job.start());
    return job.snapshot();
  }

  /// 暂停。
  Future<void> pause(String id) async => _jobs[id]?.pause();

  /// 继续。
  Future<void> resume(String id) async {
    final _DownloadJob? job = _jobs[id];
    if (job == null) {
      return;
    }
    await job.start();
  }

  /// 取消（删除未完成的临时文件）。
  Future<void> cancel(String id) async => _jobs[id]?.cancel();

  /// 重试（从头开始）。
  Future<void> retry(String id) async {
    final _DownloadJob? job = _jobs[id];
    if (job == null) {
      return;
    }
    job.reset();
    await job.start();
  }

  /// 从列表移除（进行中的先取消）。
  Future<void> remove(String id) async {
    final _DownloadJob? job = _jobs.remove(id);
    _snapshots.remove(id);
    if (job != null) {
      await job.cancel();
    }
    notifyListeners();
  }

  /// 清空已完成 / 已取消的条目（不动磁盘文件）。
  void clearFinished() {
    for (final MapEntry<String, _DownloadJob> entry in _jobs.entries.toList()) {
      final IxDownloadStatus status = entry.value.snapshot().status;
      if (status == IxDownloadStatus.completed ||
          status == IxDownloadStatus.canceled ||
          status == IxDownloadStatus.failed) {
        if (status != IxDownloadStatus.completed) {
          _jobs.remove(entry.key);
        }
        _snapshots.remove(entry.key);
      }
    }
    notifyListeners();
  }

  void _onJobChanged() {
    for (final _DownloadJob job in _jobs.values) {
      _snapshots[job.snapshot().id] = job.snapshot();
    }
    final DateTime now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < 200) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }

  static String _sanitize(String name) {
    final String cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_').trim();
    return cleaned.isEmpty ? 'download' : cleaned;
  }

  static Future<String> _uniquePath(String dir, String fileName) async {
    final Directory d = Directory(dir);
    await d.create(recursive: true);
    String candidate = '$dir/$fileName';
    if (!await File(candidate).exists()) {
      return candidate;
    }
    final int dot = fileName.lastIndexOf('.');
    final String base = dot > 0 ? fileName.substring(0, dot) : fileName;
    final String ext = dot > 0 ? fileName.substring(dot) : '';
    int i = 1;
    while (await File('$dir/$base ($i)$ext').exists()) {
      i++;
    }
    candidate = '$dir/$base ($i)$ext';
    return candidate;
  }
}

/// 分块下载内部实现。
class _DownloadJob {
  _DownloadJob({
    required this.id,
    required this.url,
    required this.fileName,
    required this.category,
    required this.savePath,
    required this.headers,
    required Dio dio,
    required int threads,
    required int chunkSize,
    required VoidCallback onChanged,
  })  : _dio = dio,
        _threads = threads,
        _chunkSize = chunkSize,
        _onChanged = onChanged,
        createdAt = DateTime.now();

  final String id;
  final String url;
  final String fileName;
  final IxDownloadCategory category;
  final String savePath;
  final Map<String, String> headers;
  final DateTime createdAt;
  final Dio _dio;
  final int _threads;
  final int _chunkSize;
  final VoidCallback _onChanged;

  IxDownloadStatus _status = IxDownloadStatus.queued;
  int _received = 0;
  int _total = 0;
  String? _error;
  double _speed = 0;
  int _active = 0;

  int _chunkCount = 0;
  int _nextChunk = 0;
  final Set<int> _doneChunks = <int>{};
  RandomAccessFile? _raf;
  bool _paused = false;
  bool _canceled = false;
  bool _started = false;
  final List<CancelToken> _tokens = <CancelToken>[];

  DateTime _sampleAt = DateTime.now();
  int _sampleBytes = 0;

  IxDownloadTask snapshot() => IxDownloadTask(
        id: id,
        url: url,
        fileName: fileName,
        category: category,
        savePath: savePath,
        status: _status,
        received: _received,
        total: _total,
        bytesPerSecond: _speed,
        createdAt: createdAt,
        error: _error,
        threadsActive: _active,
      );

  void reset() {
    _status = IxDownloadStatus.queued;
    _received = 0;
    _total = 0;
    _error = null;
    _speed = 0;
    _chunkCount = 0;
    _nextChunk = 0;
    _doneChunks.clear();
    _paused = false;
    _canceled = false;
    _started = false;
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _paused = false;
    _canceled = false;
    _status = IxDownloadStatus.running;
    _error = null;
    _onChanged();
    try {
      await _run();
    } catch (error) {
      if (_canceled) {
        _status = IxDownloadStatus.canceled;
      } else if (_paused) {
        _status = IxDownloadStatus.paused;
      } else {
        _status = IxDownloadStatus.failed;
        _error = '$error';
      }
    } finally {
      _active = 0;
      await _closeRaf();
      _started = false;
      if (_status == IxDownloadStatus.running) {
        _status = IxDownloadStatus.completed;
      }
      _onChanged();
    }
  }

  void pause() {
    if (_status != IxDownloadStatus.running) {
      return;
    }
    _paused = true;
    _cancelTokens();
    _status = IxDownloadStatus.paused;
    _onChanged();
  }

  Future<void> cancel() async {
    _canceled = true;
    _cancelTokens();
    await _closeRaf();
    final File part = File('$savePath.part');
    if (await part.exists()) {
      try {
        await part.delete();
      } catch (_) {
        // 删除失败不阻断（下次同路径会重下）。
      }
    }
    _status = IxDownloadStatus.canceled;
    _onChanged();
  }

  void _cancelTokens() {
    for (final CancelToken token in _tokens) {
      if (!token.isCancelled) {
        token.cancel('paused');
      }
    }
    _tokens.clear();
  }

  Future<void> _closeRaf() async {
    final RandomAccessFile? raf = _raf;
    _raf = null;
    if (raf != null) {
      try {
        await raf.close();
      } catch (_) {
        // 忽略关闭错误。
      }
    }
  }

  Future<void> _run() async {
    final _Probe probe = await _probe();
    _total = probe.total;
    final File part = File('$savePath.part');
    if (_total > 0 && probe.rangeOk) {
      try {
        await _downloadChunked(part);
      } on _RangeUnsupported {
        // 服务器忽略 Range：停止分块，退回单流下载。
        _cancelTokens();
        await _closeRaf();
        if (await part.exists()) {
          try {
            await part.delete();
          } catch (_) {
            // 删除失败则以覆盖方式重写。
          }
        }
        _received = 0;
        _total = 0;
        _doneChunks.clear();
        _nextChunk = 0;
        _active = 0;
        await _downloadSingle(part);
      }
    } else {
      await _downloadSingle(part);
    }
    if (_canceled || _paused) {
      return;
    }
    await _closeRaf();
    if (await part.exists()) {
      await part.rename(savePath);
    }
    _received = _total > 0 ? _total : _received;
    _status = IxDownloadStatus.completed;
    _onChanged();
  }

  Future<_Probe> _probe() async {
    try {
      final Response<dynamic> head = await _dio.head<dynamic>(
        url,
        options: Options(
          headers: headers,
          followRedirects: true,
          validateStatus: (int? status) => status != null && status < 500,
        ),
      );
      final int? len = int.tryParse('${head.headers.value('content-length') ?? ''}');
      final String? acceptRanges = head.headers.value('accept-ranges');
      final bool rangeOk = acceptRanges == null ||
          acceptRanges.toLowerCase() != 'none';
      if (len != null && len > 0) {
        return _Probe(total: len, rangeOk: rangeOk);
      }
    } catch (_) {
      // HEAD 不被支持：继续用分块请求探测。
    }
    return const _Probe(total: 0, rangeOk: false);
  }

  Future<void> _downloadChunked(File part) async {
    final RandomAccessFile raf = await part.open(mode: FileMode.write);
    await raf.truncate(_total);
    _raf = raf;

    _chunkCount = _total <= 16 * 1024 * 1024
        ? _threads
        : (_total / _chunkSize).ceil();
    if (_chunkCount < 1) {
      _chunkCount = 1;
    }
    // 每次进入分块阶段都从头扫描，已完成分块由 `_doneChunks` 跳过：
    // 这样"暂停时在途、被取消"的分块会在继续时被重新取回，不会漏块。
    _nextChunk = 0;
    // 已完成分块按当前分块方案重算（分块方案在一次任务内稳定）。
    _received = 0;
    for (final int index in _doneChunks) {
      _received += _chunkLength(index);
    }
    _sampleBytes = _received;
    _sampleAt = DateTime.now();
    _onChanged();

    final List<Future<void>> workers = <Future<void>>[];
    for (int i = 0; i < _threads && i < _chunkCount; i++) {
      workers.add(_worker());
    }
    await Future.wait(workers);
  }

  int _chunkLength(int index) {
    if (_total <= 16 * 1024 * 1024) {
      final int per = (_total / _threads).ceil();
      final int start = index * per;
      if (start >= _total) {
        return 0;
      }
      final int end = math.min(start + per, _total) - 1;
      return end - start + 1;
    }
    final int start = index * _chunkSize;
    if (start >= _total) {
      return 0;
    }
    final int end = math.min(start + _chunkSize, _total) - 1;
    return end - start + 1;
  }

  Future<void> _worker() async {
    while (!_canceled && !_paused) {
      final int index = _nextChunk++;
      if (index >= _chunkCount) {
        return;
      }
      if (_doneChunks.contains(index)) {
        continue;
      }
      final int length = _chunkLength(index);
      if (length <= 0) {
        continue;
      }
      final int start = _chunkStart(index);
      final int end = start + length - 1;
      _active++;
      final CancelToken token = CancelToken();
      _tokens.add(token);
      try {
        final Response<List<int>> response = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: <String, String>{
              ...headers,
              'Range': 'bytes=$start-$end',
            },
            followRedirects: true,
            validateStatus: (int? status) => status != null && status < 400,
            receiveTimeout: const Duration(minutes: 10),
          ),
          cancelToken: token,
        );
        final List<int>? data = response.data;
        if (response.statusCode == 206 && data != null && data.length == length) {
          await _writeAt(start, data);
          _doneChunks.add(index);
          _received += length;
          _updateSpeed();
          _onChanged();
        } else if (response.statusCode == 200) {
          // 服务器忽略 Range：退回单流。
          throw const _RangeUnsupported();
        } else {
          throw StateError('分块 $index 失败：HTTP ${response.statusCode}');
        }
      } on _RangeUnsupported {
        rethrow;
      } on DioException catch (error) {
        if (_canceled || _paused) {
          return;
        }
        throw StateError('分块 $index 出错：${error.message ?? error.type.name}');
      } finally {
        _active = math.max(0, _active - 1);
        _tokens.remove(token);
      }
    }
  }

  int _chunkStart(int index) {
    if (_total <= 16 * 1024 * 1024) {
      final int per = (_total / _threads).ceil();
      return index * per;
    }
    return index * _chunkSize;
  }

  Future<void> _writeAt(int offset, List<int> bytes) async {
    RandomAccessFile raf = _raf ?? await File('$savePath.part').open(mode: FileMode.write);
    _raf = raf;
    await raf.setPosition(offset);
    await raf.writeFrom(bytes);
  }

  void _updateSpeed() {
    final DateTime now = DateTime.now();
    final int elapsed = now.difference(_sampleAt).inMilliseconds;
    if (elapsed >= 1000) {
      _speed = (_received - _sampleBytes) * 1000 / elapsed;
      _sampleAt = now;
      _sampleBytes = _received;
    }
  }

  Future<void> _downloadSingle(File part) async {
    final CancelToken token = CancelToken();
    _tokens.add(token);
    try {
      await _dio.download(
        url,
        part.path,
        options: Options(headers: headers, followRedirects: true),
        cancelToken: token,
        onReceiveProgress: (int received, int total) {
          _received = received;
          if (total > 0) {
            _total = total;
          }
          _updateSpeed();
          _onChanged();
        },
      );
    } on DioException catch (error) {
      if (_canceled || _paused) {
        return;
      }
      throw StateError('下载失败：${error.message ?? error.type.name}');
    } finally {
      _tokens.remove(token);
    }
  }
}

/// 探测结果。
@immutable
class _Probe {
  const _Probe({required this.total, required this.rangeOk});

  final int total;
  final bool rangeOk;
}

/// 服务器不支持分块（Range 被忽略）。
class _RangeUnsupported implements Exception {
  const _RangeUnsupported();

  @override
  String toString() => '服务器不支持 Range 分块下载';
}