/// L1 底座级 · 硬盘逻辑：**平台实现的入口**（本分支 = 纯 Web）。
///
/// ## 这一层是什么
/// 硬盘逻辑全部收敛在 [platform_web_impl.dart]；本文件只做一步**直接导出**——
/// 调用方（`base_bootstrap.dart`、单测等）只需 `import 'platform_io.dart';`。
///
/// 注：本分支为**纯 Web 构建**（浏览器），原先对原生（非 web）的条件导出已移除；
/// 实现文件后缀 `_impl` 仅表示「实现」，不重命名。
///
/// [platform_web_impl.dart]：**localStorage 支撑的 KV + 内存文件表**
/// （浏览器无文件系统；文件类存储仅会话内有效，KV 走 localStorage）。
library;

export 'platform_web_impl.dart';
