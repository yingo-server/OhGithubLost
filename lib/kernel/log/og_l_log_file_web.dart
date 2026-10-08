/// L0 内核级 · **日志落盘后端**（web 实现：不落盘，改走控制台）。
///
/// 由 `og_l_log_file.dart` 条件导入。浏览器里**没有文件系统**，
/// 因此本后端：
/// - `isEnabled` 恒 `false`、`filePath` / `dirPath` 恒 `null`
///   —— 主门面据此把原因记入 `lastError`，**不静默假装写成功**；
/// - [openDir] 对任何候选目录都返回失败（浏览器没有可写目录）；
/// - [fallback] 把行输出到**浏览器控制台**（保留"控制台输出路径"）。
///
/// 本文件**不** import `dart:io` / `flutter`：只用 `dart:js_interop` 直连
/// `console`，因此内核层仍然与 Flutter 零耦合。
library;

import 'dart:js_interop';

@JS('console')
external _Console get _console;

extension type _Console._(JSObject _) implements JSObject {
  external void log(String message);
}

/// 日志文件后端（web）：不落盘，只保留控制台输出。
class OgLLogBackend {
  /// 创建后端（[maxBytes] 仅为与 io 后端保持同一构造签名）。
  OgLLogBackend({this.maxBytes = 2 * 1024 * 1024});

  /// 单文件大小上限（浏览器下不落盘，此值不生效）。
  final int maxBytes;

  /// 出错回调（web 后端不会触发；仅为与 io 后端保持同一契约）。
  void Function(String error)? onError;

  /// 浏览器未落盘。
  bool get isEnabled => false;

  /// 无落盘文件。
  String? get filePath => null;

  /// 无落盘目录。
  String? get dirPath => null;

  /// 浏览器没有可写文件系统：任何候选都失败（返回原因，不抛）。
  Future<String?> openDir(
    String dir, {
    required String prefix,
    required String stamp,
  }) async =>
      '浏览器不支持文件落盘';

  /// 未落盘时的写入口径：落到控制台（内存/控制台输出路径得以保留）。
  void write(String text) {
    _logToConsole(text);
  }

  /// 未落盘时的兜底输出：落到浏览器控制台。
  void fallback(String text) {
    _logToConsole(text);
  }

  /// 无队列可刷。
  Future<void> flush() async {}

  /// 无句柄可关。
  Future<void> close() async {}

  /// 测试用：web 端无文件可绑，空操作（不抛）。
  void bindForTest(String path) {}

  /// web 端无跨天切换。
  void ensureCurrentDay() {}

  void _logToConsole(String text) {
    try {
      _console.log(text);
    } catch (_) {
      // 控制台不可用也不影响业务。
    }
  }
}
