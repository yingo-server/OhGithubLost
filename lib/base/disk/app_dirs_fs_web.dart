/// L1 底座级 · 应用目录规划的**web 实现**（浏览器）。
///
/// 由 `app_dirs.dart` 条件导入。浏览器里：
/// - **没有多档目录**：只有一档 `internal` 语义的**虚拟根** `web`；
/// - **没有可写探针**：`writable` 恒 `false`（浏览器沙箱里没有"用户可见目录"这回事）；
/// - **不得调用 path_provider**：因此本文件**不** import `path_provider`。
library;

/// 平台文件系统侧（web）：只有虚拟根，没有真实路径探测。
abstract final class AppDirsFs {
  /// 浏览器没有「用户可见的公共目录」——恒 `null`。
  static Future<String?> publicRoot(String folder) async => null;

  /// 浏览器沙箱里没有可写的"用户可见目录"——恒 `false`。
  static Future<bool> writable(String dir) async => false;

  /// 应用根目录：一档虚拟前缀 `web`（对齐 `OgLStorageMode.internal` 语义）。
  static Future<String> resolveRoot(String folder) async => 'web';
}
