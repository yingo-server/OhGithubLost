/// L1 底座级 · 日志目录候选链的**web 实现**（浏览器）。
///
/// 由 `log_dirs.dart` 直接导入。浏览器里**没有文件写入**，
/// 因此候选清单恒为**空**：`OgLLogFile.init` 会如实进入"未落盘"状态
/// （`isEnabled == false`、`lastError` 记录原因），而不是假装写成功。
///
/// 本文件**不** import `dart:io` / `path_provider`（浏览器里都不存在）。
library;

/// 浏览器无文件落盘：没有任何候选目录。
Future<List<String>> platformLogCandidates() async => <String>[];
