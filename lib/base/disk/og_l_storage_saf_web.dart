/// L1 底座级 · 落盘去处的**web 实现**（浏览器）。
///
/// 由 `og_l_storage.dart` 条件导入。浏览器里：
/// - **没有 SAF**（那是 Android 的 Storage Access Framework）：选择 / 粘贴恒失败；
/// - **没有配置文件落盘**：SAF 授权配置不持久化（Web 恒为内部档，见 `plan()`）；
/// - 因此本文件**不** import `dart:io` / `path_provider` / `saf_*`。
library;

/// SAF 与 SAF 配置的平台侧实现（web）：全部为空实现 / 失败返回。
abstract final class OgLSafBridge {
  /// 浏览器无 SAF：恒返回 `null`（未授权）。
  static Future<String?> pickDirectory() async => null;

  /// 浏览器无 SAF：恒 `false`（绝不假装导出成功）。
  static Future<bool> pasteLocalFile({
    required String srcPath,
    required String treeUri,
    required String fileName,
    String mime = 'application/octet-stream',
  }) async =>
      false;

  /// 浏览器无 SAF 配置落盘：恒 `null`。
  static Future<String?> loadConfig() async => null;

  /// 浏览器不持久化 SAF 授权：空操作。
  static Future<void> saveConfig(String? uri) async {}

  /// 浏览器没有真实文件：恒 `false`。
  static Future<bool> localFileExists(String path) async => false;
}
