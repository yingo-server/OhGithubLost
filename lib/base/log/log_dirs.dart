/// L1 底座级 · **日志目录候选链**（"日志到底写到哪儿"的唯一答案处）。
///
/// 日志统一写入应用根目录下的 `logging/`（默认 `<sdcard>/ogl/logging`，
/// 平台不可写时自动退到应用可见目录，见 `disk/app_dirs.dart`）。
///
/// 顺序即优先级：越靠前越"用户看得见"。
///
/// ## Web 适配
/// 浏览器里**没有文件写入**：候选清单恒为**空**（`log_dirs_platform_web.dart`），
/// 于是 `OgLLogFile.init` 找不到可写目录 → `isEnabled == false`、`lastError` 如实记录。
/// 平台侧的 `dart:io` / `path_provider` 全部收敛到条件导入的实现文件。
library;

import 'log_dirs_platform_io.dart'
    if (dart.library.js_interop) 'log_dirs_platform_web.dart';

/// 解析日志目录候选清单（去重、规整为正斜杠路径）。
///
/// 返回的**第一个**可写目录会被 `OgLLogFile` 采用。
/// Web 端返回**空清单**（浏览器无文件落盘）。
Future<List<String>> ogLLogDirectoryCandidates() async {
  final List<String> out = <String>[];
  void add(String? path) {
    if (path == null || path.isEmpty) {
      return;
    }
    final String normalized = path.replaceAll(r'\', '/');
    if (!out.contains(normalized)) {
      out.add(normalized);
    }
  }

  for (final String candidate in await platformLogCandidates()) {
    add(candidate);
  }

  return out;
}
