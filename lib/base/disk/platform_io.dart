/// L1 底座级 · 硬盘逻辑：**平台实现的条件入口**（唯一需要分平台的接缝）。
///
/// ## 为什么要有这一层
/// `dart:io`（File / Directory / IOSink）在浏览器里**不存在**——直接 import
/// 会让 web 构建在编译期就失败。跨平台适配的标准做法是**条件导入**：
///
/// ```dart
/// import 'platform_io_impl.dart'
///     if (dart.library.js_interop) 'platform_web_impl.dart';
/// ```
///
/// 判据用 `dart.library.js_interop`——这是当前 Dart 对「web 平台」的可靠判据
/// （`dart:js_interop` 只在 web 目标下可用）。
///
/// ## 两边导出**同一套公开 API**
/// - 非 web → [platform_io_impl.dart]：真实文件系统（原子写 / 启动清扫 / abs 归一化）。
/// - web    → [platform_web_impl.dart]：**localStorage 支撑的 KV + 内存文件表**
///   （浏览器无文件系统；文件类存储仅会话内有效，KV 走 localStorage）。
///
/// 调用方（`base_bootstrap.dart`、单测等）只需 `import 'platform_io.dart';`，
/// 不必关心当前目标平台。
library;

export 'platform_io_impl.dart'
    if (dart.library.js_interop) 'platform_web_impl.dart';
