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
  IxDownloadManager({FileDownloader? downloader, KernelDiagnostics? diagnostics})
      : _downloader = downloader ?? FileDownloader(),
        _diagnostics = diagnostics {
    _subscription = _downloader.updates.listen(_onUpdate);
  }

  final FileDownloader _downloader;
  KernelDiagnostics? _diagnostics;
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
    await _downloader.enqueue(task);
    return _snapshots[id]!;
  }

  /// 暂停。
  Future<void> pause(String id) async {
    final DownloadTask? task = _tasks[id];
    if (task != null) {
      await _downloader.pause(task);
      _applyStatus(id, IxDownloadStatus.paused);
    }
  }

  /// 继续。
  Future<void> resume(String id) async {
    final DownloadTask? task = _tasks[id];
    if (task != null) {
      await _downloader.resume(task);
      _applyStatus(id, IxDownloadStatus.running);
    }
  }

  /// 取消（不会保留未完成文件）。
  Future<void> cancel(String id) async {
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
    await _downloader.enqueue(task);
  }

  /// 从列表移除（进行中的先取消）。
  Future<void> remove(String id) async {
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