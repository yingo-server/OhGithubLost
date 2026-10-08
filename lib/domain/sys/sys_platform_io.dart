/// L2 中枢级 · 本地信息的**平台原语**（非 Web）。
///
/// 把 `dart:io` 的 `Platform` / `File` 收在这一个文件里，`sys_info.dart` 本体
/// 不再 `import 'dart:io'`（浏览器里没有它），Web 构建才能通过。
///
/// 只在非 Web 构建里参与编译；Web 对应文件是 `sys_platform_web.dart`。
library;

import 'dart:io';

/// 平台原语（非 Web）。
class SysPlatform {
  const SysPlatform._();

  /// 平台名（`android` / `windows` / `linux` / `ios` / `macos`）。
  static String get operatingSystem => Platform.operatingSystem;

  /// 系统版本串。
  static String get operatingSystemVersion => Platform.operatingSystemVersion;

  /// 区域设置（如 `zh_CN`）。
  static String get localeName => Platform.localeName;

  /// CPU 逻辑核数。
  static int? get numberOfProcessors => Platform.numberOfProcessors;

  /// 是否 Android。
  static bool get isAndroid => Platform.isAndroid;

  /// 读取文本文件（诊断用）。
  static Future<String> readFile(String path) => File(path).readAsString();

  /// 读取 `/proc/meminfo` 原文；**非 Linux/Android 或读不到时返回 `null`**
  /// （如实表示"本平台拿不到"，而不是编一个数字）。
  static Future<String?> readMemInfoText() async {
    if (!Platform.isLinux && !Platform.isAndroid) {
      return null;
    }
    try {
      return await File('/proc/meminfo').readAsString();
    } catch (_) {
      return null;
    }
  }
}
