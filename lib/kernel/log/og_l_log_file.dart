/// L0 内核级 ·**日志落盘**（把"看不见的失败"变成磁盘上的事实）。
///
/// ## 为什么必须有它
/// 此前的日志只在内存里环形保留 200 条：进程一退、一崩、一被杀，
/// 现场**全部消失**；而且只记"出错"，不记"做成了什么"——
/// 于是排查时手里什么都没有，只能猜。
///
/// 现在：
/// - **每条日志立刻写文件**（写入后排队 flush，崩溃也不丢已写入的行）；
/// - 目录按候选链**逐个尝试**（`sdcard/logging` → 应用外部目录 → 应用文档/支持目录），
///   全部失败时**自己把原因记下来**，由界面展示（绝不静默）；
/// - 文件按天切分、超限滚动（`ogl-YYYY-MM-DD.log` / `.1.log`）；
/// - 与 Flutter / path_provider **零耦合**：候选目录由组合根注入，
///   因此本文件是纯 Dart + `dart:io`，可以在测试里指向临时目录。
library;

import 'dart:async';
import 'dart:io';

/// 日志落盘器（单例；组合根在 `runApp` 之前 `init`）。
abstract final class OgLLogFile {
  /// 单文件大小上限（超出即滚动到 `.1.log`）。
  static const int maxBytes = 2 * 1024 * 1024;

  static IOSink? _sink;
  static String? _filePath;
  static String? _dirPath;
  static String? _lastError;
  static final List<String> _tried = <String>[];
  static String _dayStamp = '';
  static Future<void> _flushTail = Future<void>.value();

  /// 是否已成功落盘。
  static bool get isEnabled => _sink != null;

  /// 当前日志文件的绝对路径（未落盘时为 `null`）。
  static String? get filePath => _filePath;

  /// 当前日志目录（未落盘时为 `null`）。
  static String? get dirPath => _dirPath;

  /// 最后一次失败原因（未落盘时给界面看）。
  static String? get lastError => _lastError;

  /// 试过的候选目录（按顺序），供界面如实展示"为什么没写到 sdcard"。
  static List<String> get triedDirectories => List<String>.unmodifiable(_tried);

  /// 初始化：按候选顺序找**第一个可写**的目录。
  ///
  /// [candidates] 由 `base` 层解析（`sdcard/logging` → 外部目录 → 文档 → 支持目录）。
  static Future<void> init({
    required List<String> candidates,
    String prefix = 'ogl',
    String appVersion = '',
    String buildMode = '',
    String platform = '',
  }) async {
    _tried.clear();
    _lastError = null;
    final String stamp = _stamp(DateTime.now());
    for (final String raw in candidates) {
      _tried.add(raw);
      try {
        final String dir = raw.replaceAll(r'\', '/');
        Directory(dir).createSync(recursive: true);
        final String path = '$dir/$prefix-$stamp.log';
        await _open(path, rotateIfNeeded: true);
        _dirPath = dir;
        _filePath = path;
        line(
          '日志',
          '日志落盘已启用：$path（平台=$platform 版本=$appVersion 构建=$buildMode）',
        );
        return;
      } catch (error) {
        _lastError = '$raw → $error';
      }
    }
    _sink = null;
    _dirPath = null;
    _filePath = null;
    _lastError ??= '没有可写的候选目录';
  }

  /// 写一行（自动加时间戳与级别；`level` 取 `INFO/WARN/ERR`）。
  static void line(String area, String message, {String level = 'INFO'}) {
    raw('${_iso(DateTime.now())} [$level] [$area] $message');
  }

  /// 写一行原始文本（**已带时间戳的完整行**）。
  static void raw(String text) {
    final IOSink? sink = _sink;
    if (sink == null) {
      return;
    }
    ensureCurrentDay();
    try {
      sink.writeln(text);
      // 排队 flush：不阻塞调用方，但保证"写过的行"尽快落盘。
      _flushTail = _flushTail.then((_) async {
        try {
          await _sink?.flush();
        } catch (_) {
          // flush 失败不能反过来炸应用；错误在下次 init 时重新暴露。
        }
      });
    } catch (error) {
      _lastError = '$error';
    }
  }

  /// 等所有已排队的写入落盘（退出前 / 崩溃上报时用）。
  static Future<void> flush() async {
    try {
      await _sink?.flush();
    } catch (_) {
      // 同上：不抛出。
    }
    await _flushTail;
  }

  static Future<void> close() async {
    await flush();
    try {
      await _sink?.close();
    } catch (_) {
      // 关闭失败不影响退出。
    }
    _sink = null;
    _filePath = null;
  }

  /// 测试用：绑定一个任意 sink（不做目录探测）。
  static void bindForTest(String path) {
    _dayStamp = _stamp(DateTime.now());
    _sink = File(path).openWrite(mode: FileMode.write);
    _filePath = path;
    _dirPath = File(path).parent.path;
  }

  static Future<void> _open(String path, {bool rotateIfNeeded = false}) async {
    final File file = File(path);
    if (rotateIfNeeded && file.existsSync() && file.lengthSync() > maxBytes) {
      final File rotated = File('$path.1.log');
      try {
        if (rotated.existsSync()) {
          rotated.deleteSync();
        }
        file.renameSync(rotated.path);
      } catch (_) {
        // 滚动失败就继续往原文件写：宁可文件大，不可丢日志。
      }
    }
    // 探针：先同步写一个空追加，权限不足会**在这里**就抛出，
    // 而不是等到第一次 flush 才悄悄失败。
    file.writeAsStringSync('', mode: FileMode.append, flush: true);
    _sink = file.openWrite(mode: FileMode.append);
    _dayStamp = _stamp(DateTime.now());
  }

  /// 跨天时自动切到新文件（每次写入前检查，代价可忽略）。
  static void ensureCurrentDay() {
    final IOSink? sink = _sink;
    final String? dir = _dirPath;
    if (sink == null || dir == null || _filePath == null) {
      return;
    }
    final String today = _stamp(DateTime.now());
    if (today == _dayStamp) {
      return;
    }
    final String prefix = File(_filePath!).uri.pathSegments.last.split('-').first;
    final String next = '$dir/$prefix-$today.log';
    try {
      sink.flush();
      sink.close();
    } catch (_) {
      // 忽略：下面重新打开。
    }
    _open(next).then((_) {
      _filePath = next;
    }).catchError((Object error) {
      _lastError = '$error';
    });
  }

  static String _iso(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} '
        '${two(at.hour)}:${two(at.minute)}:${two(at.second)}.${three(at.millisecond)}';
  }

  static String _stamp(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}';
  }
}