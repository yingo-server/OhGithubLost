/// L2 中枢级 · 内建下载器（**改用成熟库 `background_downloader`**）。
///
/// ## 为什么换库
/// 早期是自研分块下载器：多 worker 共用一个 `RandomAccessFile` 并发定位写入，
/// 必然偶发错位；Range 兼容、暂停/继续、进度重算等边界全靠手工维护，bug 多。
/// 现在交给 `background_downloader`（多平台后台下载：断点续传 / 队列 / 通知）。
///
/// ## 对外契约保持不变
/// [IxDownloadManager] / [IxDownloadTask] / [IxDownloadCategory] /
/// [IxDownloadStatus] 的名字与语义不变，页面（下载管理、Release、仓库文件）
/// **零改动**。
///
/// ## 落盘位置
/// 库只支持 `BaseDirectory`（applicationDocuments / temporary / …），
/// 故统一落到「应用文档目录 / ogl / download / <分类>」。
library;

import 'dart:async';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:flutter/foundation.dart';

import '../../kernel/contract/download_engine.dart';
import '../../kernel/contract/storage_export.dart';
import '../../kernel/diagnostics.dart';

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

  /// 进度（0–1；总长未知时为 0）。
  double get progress =>
      total <= 0 ? 0 : (received / total).clamp(0, 1).toDouble();

  /// 百分比（0–100）。
  int get percent => (progress * 100).round();

  /// 是否仍在进行。
  bool get busy =>
      status == IxDownloadStatus.running || status == IxDownloadStatus.queued;

  /// 是否已完成。
  bool get done => status == IxDownloadStatus.completed;

  /// 复制并覆盖部分字段。
  IxDownloadTask copyWith({
    IxDownloadStatus? status,
    int? received,
    int? total,
    double? bytesPerSecond,
    String? error,
    String? savePath,
  }) =>
      IxDownloadTask(
        id: id,
        url: url,
        fileName: fileName,
        category: category,
        savePath: savePath ?? this.savePath,
        status: status ?? this.status,
        received: received ?? this.received,
        total: total ?? this.total,
        bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
        createdAt: createdAt,
        error: error ?? this.error,
      );
}

/// 下载管理器（展示层唯一入口；内部委托 `background_downloader`）。
class IxDownloadManager extends ChangeNotifier {
  /// 创建管理器。
  ///
  /// [diagnostics] 用于把"取不到文件大小"等**降级**情况按事件码上报
  /// （不允许静默）。
  IxDownloadManager({
    FileDownloader? downloader,
    KernelDiagnostics? diagnostics,
    DownloadEngine? engine,
    StorageExporter? storageExporter,
  })  : _downloader = downloader ?? FileDownloader(),
        _diagnostics = diagnostics,
        _engine = engine,
        _exporter = storageExporter {
    _subscription = _downloader.updates.listen(_onUpdate);
  }
  final FileDownloader _downloader;
  final KernelDiagnostics? _diagnostics;

  /// 成品导出能力（**契约层类型**，由装配根注入；为 `null` 时不导出）。
  final StorageExporter? _exporter;

  /// 多连接分片引擎（**契约层类型**，由装配根注入；为 `null` 时只用库）。
  final DownloadEngine? _engine;

  /// 走分片引擎的任务 → 取消令牌（暂停 / 取消 / 重试都靠它）。
  final Map<String, DownloadCancelToken> _rangeTokens =
      <String, DownloadCancelToken>{};

  /// 走分片引擎的任务 → 并发数（重试用同一份参数）。
  final Map<String, int> _rangeConnections = <String, int>{};

  /// 每个任务的**候选地址（按优先级）**：首个是首选，其余用于**静默降级**。
  final Map<String, List<String>> _urlCandidates = <String, List<String>>{};

  /// 已请求「暂停」的分片任务（取消令牌后据此标记 paused 而非 canceled）。
  final Set<String> _pausedIds = <String>{};

  /// 是否由分片引擎接管（页面据此显示"多线程"标记）。
  bool isRanged(String id) => _rangeTokens.containsKey(id);
  StreamSubscription<TaskUpdate>? _subscription;

  final Map<String, IxDownloadTask> _snapshots = <String, IxDownloadTask>{};
  final Map<String, DownloadTask> _tasks = <String, DownloadTask>{};

  /// 上次进度采样（用于估算速率；库本身只给进度、不给速度）。
  final Map<String, ({DateTime at, int received})> _lastSample =
      <String, ({DateTime at, int received})>{};

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
  int get runningCount => _snapshots.values
      .where((IxDownloadTask t) =>
          t.status == IxDownloadStatus.running ||
          t.status == IxDownloadStatus.queued)
      .length;

  /// 加入一个下载任务。
  Future<IxDownloadTask> enqueue({
    required String url,
    required String fileName,
    IxDownloadCategory category = IxDownloadCategory.other,
    Map<String, String> headers = const <String, String>{},
    int connections = 1,
    List<String> fallbackUrls = const <String>[],
  }) async {
    final DownloadTask task = DownloadTask(
      url: url,
      filename: fileName.isEmpty ? null : fileName,
      directory: 'ogl/download/${category.folder}',
      baseDirectory: BaseDirectory.applicationDocuments,
      headers: headers,
      updates: Updates.statusAndProgress,
      allowPause: true,
      retries: 2,
    );
    final String id = task.taskId;
    String savePath = '';
    try {
      savePath = await task.filePath();
    } catch (_) {
      savePath = fileName;
    }
    _tasks[id] = task;
    _snapshots[id] = IxDownloadTask(
      id: id,
      url: url,
      fileName: fileName,
      category: category,
      savePath: savePath,
      status: IxDownloadStatus.queued,
      received: 0,
      total: 0,
      bytesPerSecond: 0,
      createdAt: DateTime.now(),
    );
    notifyListeners();

    // 5.0：并发 > 1 且装配层给了分片引擎 → 走**多连接分片**；
    // 不支持 Range 时自动回退到库任务（同一 taskId，页面无感）。
    // 候选地址（按优先级去重）：分片路径会逐个探测，**静默降级**到可用者。
    _urlCandidates[id] = <String>[
      url,
      for (final String alt in fallbackUrls)
        if (alt.isNotEmpty && alt != url) alt,
    ];
    if (connections > 1 && _engine != null && savePath.isNotEmpty) {
      _rangeConnections[id] = connections;
      unawaited(_runRanged(id: id, task: task, connections: connections));
      return _snapshots[id]!;
    }
    await _downloader.enqueue(task);
    return _snapshots[id]!;
  }

  /// 用分片引擎跑一个任务；不支持 / 失败则回退库任务。
  Future<void> _runRanged({
    required String id,
    required DownloadTask task,
    required int connections,
  }) async {
    final IxDownloadTask? snap = _snapshots[id];
    if (snap == null) {
      return;
    }
    final DownloadEngine engine = _engine!;
    final List<String> candidates = _urlCandidates[id] ?? <String>[task.url];
    final DownloadCancelToken token = engine.newCancelToken();
    _rangeTokens[id] = token;

    // 按优先级逐个探测：命中第一个"可并发分片"的地址就停（**静默降级**）。
    Uri? uri;
    DownloadProbe probe = const DownloadProbe(supportsRange: false);
    String? reachable;
    for (final String candidate in candidates) {
      final Uri parsed = Uri.parse(candidate);
      DownloadProbe current;
      try {
        current = await engine.probe(
          parsed,
          headers: task.headers.isEmpty ? null : task.headers,
        );
      } catch (error) {
        // 该通道不可用 → 静默试下一个（不打扰用户）。
        continue;
      }
      reachable ??= candidate;
      if (current.supportsRange && current.total != null && current.total! > 0) {
        uri = parsed;
        probe = current;
        break;
      }
    }

    if (uri == null) {
      // 没有一个地址可并发分片：回退库任务（优先用最后一个可达地址）。
      _rangeTokens.remove(id);
      _diagnostics?.info(
        'DL',
        '无可分片通道，回退单连接下载：${candidates.first}',
        code: 'OGL-DL-201',
        data: probe.toJson(),
      );
      final String target = reachable ?? candidates.first;
      await _downloader.enqueue(
        target == task.url ? task : _withUrl(task, target),
      );
      return;
    }

    _snapshots[id] = snap.copyWith(
      status: IxDownloadStatus.running,
      total: probe.total!,
    );
    notifyListeners();

    try {
      await engine.fetch(
        DownloadRequest(
          url: uri,
          targetPath: snap.savePath,
          total: probe.total!,
          headers: task.headers,
          connections: connections,
        ),
        cancel: token,
        onProgress: (int received, int total) =>
            _applyRangeProgress(id, received, total),
      );
      _applyRangeProgress(id, probe.total!, probe.total!);
      _applyStatus(id, IxDownloadStatus.completed);
    } on DownloadCanceled {
      _applyStatus(
        id,
        _pausedIds.contains(id)
            ? IxDownloadStatus.paused
            : IxDownloadStatus.canceled,
      );
    } catch (error) {
      // 分片失败**不静默**：记事件码并置失败（可重试）。
      _diagnostics?.error(
        'DL',
        '多连接下载失败：$uri（$error）',
        code: 'OGL-DL-202',
        data: <String, Object?>{'connections': connections},
      );
      final IxDownloadTask? current = _snapshots[id];
      if (current != null) {
        _snapshots[id] = current.copyWith(
          status: IxDownloadStatus.failed,
          error: '$error',
        );
        notifyListeners();
      }
    } finally {
      _rangeTokens.remove(id);
      _pausedIds.remove(id);
    }
  }

  /// 换一个源地址重建任务（**静默降级**时用；其余参数保持不变）。
  DownloadTask _withUrl(DownloadTask task, String url) => DownloadTask(
        url: url,
        filename: task.filename,
        directory: task.directory,
        baseDirectory: task.baseDirectory,
        headers: task.headers,
        updates: Updates.statusAndProgress,
        allowPause: true,
        retries: 2,
      );

  /// 分片进度 → 快照（含速率估算；节流通知与库路径一致）。
  void _applyRangeProgress(String id, int received, int total) {
    final IxDownloadTask? snap = _snapshots[id];
    if (snap == null) {
      return;
    }
    final DateTime now = DateTime.now();
    final ({DateTime at, int received})? last = _lastSample[id];
    double speed = snap.bytesPerSecond;
    if (last != null) {
      final int ms = now.difference(last.at).inMilliseconds;
      if (ms >= 400) {
        speed = (received - last.received) * 1000 / ms;
        _lastSample[id] = (at: now, received: received);
      }
    } else {
      _lastSample[id] = (at: now, received: received);
    }
    _snapshots[id] = snap.copyWith(
      status: IxDownloadStatus.running,
      received: received,
      total: total,
      bytesPerSecond: speed,
    );
    _notifyThrottled();
  }

  /// 暂停。
  Future<void> pause(String id) async {
    final DownloadCancelToken? token = _rangeTokens[id];
    if (token != null) {
      // 分片任务：取消当前分片连接即"暂停"（重试会重新分片拉取）。
      _pausedIds.add(id);
      token.cancel();
      _applyStatus(id, IxDownloadStatus.paused);
      return;
    }
    final DownloadTask? task = _tasks[id];
    if (task != null) {
      await _downloader.pause(task);
      _applyStatus(id, IxDownloadStatus.paused);
    }
  }

  /// 继续。
  ///
  /// 分片任务没有"库队列"可恢复：重新起一次分片拉取（分片临时文件已在失败时清理，
  /// 因此是**从头发起**；换来的是不出现"假装在续传"的错位文件）。
  Future<void> resume(String id) async {
    final int? connections = _rangeConnections[id];
    final DownloadTask? task = _tasks[id];
    if (connections != null && task != null && _engine != null) {
      _pausedIds.remove(id);
      _applyStatus(id, IxDownloadStatus.running);
      await _runRanged(id: id, task: task, connections: connections);
      return;
    }
    if (task != null) {
      await _downloader.resume(task);
      _applyStatus(id, IxDownloadStatus.running);
    }
  }

  /// 取消（不会保留未完成文件）。
  ///
  /// 分片任务：取消令牌 → 各分片退出 → 引擎负责删掉全部临时分片。
  Future<void> cancel(String id) async {
    final DownloadCancelToken? token = _rangeTokens[id];
    if (token != null) {
      _pausedIds.remove(id);
      token.cancel();
      _applyStatus(id, IxDownloadStatus.canceled);
      return;
    }
    await _downloader.cancelTaskWithId(id);
    _applyStatus(id, IxDownloadStatus.canceled);
  }

  /// 重试（重新入队）。
  Future<void> retry(String id) async {
    final DownloadTask? task = _tasks[id];
    if (task == null) {
      return;
    }
    final IxDownloadTask? snap = _snapshots[id];
    if (snap != null) {
      _snapshots[id] = snap.copyWith(
        status: IxDownloadStatus.queued,
        received: 0,
        total: 0,
        bytesPerSecond: 0,
      );
      notifyListeners();
    }
    final int? connections = _rangeConnections[id];
    if (connections != null && _engine != null) {
      _pausedIds.remove(id);
      await _runRanged(id: id, task: task, connections: connections);
      return;
    }
    await _downloader.enqueue(task);
  }

  /// 从列表移除（进行中的先取消）。
  Future<void> remove(String id) async {
    _rangeTokens[id]?.cancel();
    _rangeTokens.remove(id);
    _rangeConnections.remove(id);
    _pausedIds.remove(id);
    await _downloader.cancelTaskWithId(id);
    _tasks.remove(id);
    _snapshots.remove(id);
    _lastSample.remove(id);
    notifyListeners();
  }

  /// 清空已完成 / 已取消 / 失败的条目（不动磁盘文件）。
  void clearFinished() {
    _snapshots.removeWhere((String id, IxDownloadTask t) {
      final bool finished = t.status == IxDownloadStatus.completed ||
          t.status == IxDownloadStatus.canceled ||
          t.status == IxDownloadStatus.failed;
      if (finished && t.status != IxDownloadStatus.completed) {
        _tasks.remove(id);
      }
      return finished;
    });
    notifyListeners();
  }

  void _applyStatus(String id, IxDownloadStatus status) {
    final IxDownloadTask? snap = _snapshots[id];
    if (snap != null) {
      _snapshots[id] = snap.copyWith(status: status);
      notifyListeners();
      if (status == IxDownloadStatus.completed) {
        unawaited(_maybeExportToSaf(id));
      }
    }
  }

  /// 已导出到 SAF 的任务（去重：进度/状态事件会反复到达）。
  final Set<String> _exportedToSaf = <String>{};

  /// 下载完成后，把成品**导出**到用户授权的 SAF 文件夹（存储②档）。
  ///
  /// - 只在 ② 档（`safDir`）生效；① 档直接写公共目录、③ 档无处可导；
  /// - **绝不抛出**：导出失败不影响"下载已完成"这个事实，只在日志留痕。
  Future<void> _maybeExportToSaf(String id) async {
    final StorageExporter? exporter = _exporter;
    if (exporter == null) {
      return;
    }
    if (!_exportedToSaf.add(id)) {
      return;
    }
    final IxDownloadTask? snap = _snapshots[id];
    if (snap == null) {
      return;
    }
    try {
      final bool ok = await exporter.export(
        localPath: snap.savePath,
        fileName: snap.fileName,
      );
      if (!ok) {
        _exportedToSaf.remove(id);
        return;
      }
      _diagnostics?.info(
        'DL',
        '已导出到所选文件夹：${snap.fileName}',
        code: 'OGL-DL-301',
      );
    } catch (_) {
      _exportedToSaf.remove(id);
    }
  }

  /// 把库的更新映射成对外快照（进度节流）。
  void _onUpdate(TaskUpdate update) {
    if (update is TaskStatusUpdate) {
      final String id = update.task.taskId;
      final IxDownloadTask? snap = _snapshots[id];
      if (snap == null) {
        return;
      }
      final IxDownloadStatus status = _mapStatus(update.status);
      _snapshots[id] = snap.copyWith(
        status: status,
        error: update.exception?.description,
      );
      notifyListeners();
      if (status == IxDownloadStatus.completed) {
        // 库对小文件可能一次进度事件都不发 → 界面会一直显示 "0 B"（截图实证）。
        // 完成时以磁盘上的真实文件大小回填。
        unawaited(_fillCompletedSize(id));
        // 存储②档：成品自动**导出**到用户选的文件夹（去重、失败不阻断）。
        unawaited(_maybeExportToSaf(id));
      }
      return;
    }
    if (update is TaskProgressUpdate) {
      final String id = update.task.taskId;
      final IxDownloadTask? snap = _snapshots[id];
      if (snap == null) {
        return;
      }
      final int total =
          update.expectedFileSize > 0 ? update.expectedFileSize : snap.total;
      final int received = total > 0 ? (update.progress * total).round() : 0;
      // 库只给进度，不给速度：用两次采样的差分估算。
      final DateTime now = DateTime.now();
      final ({DateTime at, int received})? last = _lastSample[id];
      double speed = snap.bytesPerSecond;
      if (last != null) {
        final int ms = now.difference(last.at).inMilliseconds;
        final int delta = received - last.received;
        if (ms > 0 && delta >= 0) {
          speed = delta * 1000 / ms;
        }
      }
      _lastSample[id] = (at: now, received: received);
      _snapshots[id] = snap.copyWith(
        received: received,
        total: total,
        bytesPerSecond: speed,
        status: IxDownloadStatus.running,
      );
      _notifyThrottled();
    }
  }

  void _notifyThrottled() {
    final DateTime now = DateTime.now();
    if (now.difference(_lastNotify).inMilliseconds < 200) {
      return;
    }
    _lastNotify = now;
    notifyListeners();
  }

  /// 完成后回填真实文件大小。
  ///
  /// 库对小文件可能一次进度事件都不发 → 界面会一直显示 "0 B"（截图实证）。
  Future<void> _fillCompletedSize(String id) async {
    try {
      final DownloadTask? task = _tasks[id];
      final IxDownloadTask? snap = _snapshots[id];
      if (task == null || snap == null) {
        return;
      }
      final String path = await task.filePath();
      final File file = File(path);
      if (!await file.exists()) {
        return;
      }
      final int size = await file.length();
      _snapshots[id] = snap.copyWith(received: size, total: size);
      notifyListeners();
    } catch (error) {
      // 不允许静默：按事件码上报到通知中心。
      _diagnostics?.warn(
        'DOWNLOAD',
        '下载完成后无法读取文件大小',
        code: 'OGL-DL-101',
        data: <String, Object?>{'taskId': id, 'error': '$error'},
      );
    }
  }

  static IxDownloadStatus _mapStatus(TaskStatus status) {
    switch (status) {
      case TaskStatus.enqueued:
        return IxDownloadStatus.queued;
      case TaskStatus.running:
        return IxDownloadStatus.running;
      case TaskStatus.complete:
        return IxDownloadStatus.completed;
      case TaskStatus.paused:
        return IxDownloadStatus.paused;
      case TaskStatus.canceled:
        return IxDownloadStatus.canceled;
      case TaskStatus.failed:
      case TaskStatus.notFound:
        return IxDownloadStatus.failed;
      default:
        return IxDownloadStatus.failed;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}