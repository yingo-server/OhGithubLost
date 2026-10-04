/// L1 底座级 · 应用目录规划（**唯一**知道"ogl 放哪"的地方）。
///
/// ## 约定的目录结构
/// ```text
/// <root>/                     应用根（默认 ogl）
///   logging/                  日志落盘
///   download/                 下载根
///     release/                Release 附件
///     repo/                   仓库文件
///     gist/                   Gist 文件
///     other/                  其它
/// ```
///
/// ## 平台适配
/// - Android：优先外部可见目录 `/storage/emulated/0/ogl`（需可写）；
///   不可写时退到应用外部目录 `/storage/emulated/0/Android/data/<pkg>/files/ogl`
///   （无需权限、文件管理器可见）；再退到应用文档目录。
/// - 桌面（Windows / Linux / macOS）：文档目录下的 `ogl`。
/// - 探测方式为**真实写入探针**：能建目录并写删探针文件才算可用，不靠猜。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';

/// 应用目录规划。
abstract final class OgLAppDirs {
  /// 根目录名。
  static const String folderName = 'ogl';

  /// 解析应用根目录（结果按进程缓存：一次探测，后续复用）。
  static Future<String> root() async {
    final String? cached = _rootCache;
    if (cached != null) {
      return cached;
    }
    final String resolved = await _resolveRoot();
    _rootCache = resolved;
    return resolved;
  }

  static String? _rootCache;

  /// 日志目录。
  static Future<String> logging() async => '${await root()}/logging';

  /// 下载根目录。
  static Future<String> downloads() async => '${await root()}/download';

  /// 下载分类子目录名。
  static String categoryFolder(String category) {
    switch (category) {
      case 'release':
        return 'release';
      case 'repo':
        return 'repo';
      case 'gist':
        return 'gist';
      default:
        return 'other';
    }
  }

  static Future<String> _resolveRoot() async {
    if (kIsWeb) {
      return folderName;
    }
    if (Platform.isAndroid) {
      // ① 外部可见目录（Android 11+ 通常写不动 → 探针会失败）。
      final String visible = '/storage/emulated/0/$folderName';
      if (await _writable(visible)) {
        return visible;
      }
      // ② 应用外部目录：无需权限、文件管理器可见。
      try {
        final Directory? ext = await getExternalStorageDirectory();
        if (ext != null) {
          final String candidate = '${ext.path.replaceAll(r'\', '/')}/$folderName';
          if (await _writable(candidate)) {
            return candidate;
          }
        }
      } catch (_) {
        // 某些定制 ROM 会抛：忽略，继续退。
      }
    }
    // ③ 文档目录（桌面为 ~/Documents，用户可见；其余平台兜底）。
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final String candidate = '${docs.path.replaceAll(r'\', '/')}/$folderName';
      if (await _writable(candidate)) {
        return candidate;
      }
    } catch (_) {
      // 忽略。
    }
    // ④ 支持目录：一定可写，保底。
    final Directory support = await getApplicationSupportDirectory();
    final String candidate = '${support.path.replaceAll(r'\', '/')}/$folderName';
    if (await _writable(candidate)) {
      return candidate;
    }
    return support.path.replaceAll(r'\', '/');
  }

  /// 真实写入探针：能建目录、能写入并删除探针文件，才算可写。
  static Future<bool> _writable(String dir) async {
    try {
      final Directory d = Directory(dir);
      await d.create(recursive: true);
      final File probe = File('$dir/.ogl_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}