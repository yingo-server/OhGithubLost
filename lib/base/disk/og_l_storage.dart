/// L1 底座级 · **落盘去处**（公共目录 / SAF 文件夹 / 应用内部）。
///
/// ## 为什么需要这一层
/// Android 11+ 上，普通应用**拿不到「所有文件访问」时无法**往
/// `/storage/emulated/0/` 写文件——这是系统限制，不是本项目的 bug。
/// 系统给出的合规出口只有 **SAF**：让用户自己选一个文件夹，系统发一个
/// **可长期持有**的授权 URI。
///
/// 于是"文件放哪"不再是一条路径，而是**三档**（按优先级）：
///
/// | 档 | 条件 | 实际写入位置 | 用户可见 | 自检 |
/// |---|---|---|---|---|
/// | ① `publicDir` | 有「所有文件访问」 | `/storage/emulated/0/ogl` | ✅ | **过** |
/// | ② `safDir` | 无权限但用户授权了文件夹 | 应用私有目录 → **导出粘贴**到该文件夹 | ✅ | **过** |
/// | ③ `internal` | 两者都没有 | 应用私有目录 | ❌ | **不过**（不阻断） |
///
/// ## 为什么不必重写下载引擎
/// ② 档下下载**照旧**写应用私有目录（现有分片 / 断点 / 后台通知全部不动），
/// 完成后再用 `SafStream.pasteLocalFile` 把成品**粘贴**进用户选的文件夹。
/// 这样"用户可见"这件事与下载实现解耦。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

import 'app_dirs.dart';

/// 落盘模式（三档，按优先级）。
enum OgLStorageMode {
  /// ① 公共目录：拿到「所有文件访问」，直接写系统可见的 `ogl`。
  publicDir,

  /// ② SAF 文件夹：用户授权了某个文件夹，成品**导出粘贴**过去。
  safDir,

  /// ③ 应用内部目录：功能完整，但用户**看不到**（不算通过，但可用）。
  internal,
}

/// 当前落盘方案。
@immutable
class OgLStoragePlan {
  /// 创建。
  const OgLStoragePlan({
    required this.mode,
    required this.root,
    this.safTreeUri,
  });

  /// 当前档位。
  final OgLStorageMode mode;

  /// **实际写入位置**（下载 / 日志落盘的地方）。
  final String root;

  /// ② 档下的导出目标（SAF 目录 URI）。
  final String? safTreeUri;

  /// 用户是否拿得到文件（①② 为真，③ 为假）。
  /// 是否**用户可见**（用户能靠文件管理器 / 电脑找到）。
  ///
  /// 判定**统一走 [OgLAppDirs.isUserVisible]**（按实际路径分级），不在这里
  /// 另写一套「档位 != internal」。两套定义会在「桌面文档目录不可写、最终落到
  /// 应用支持目录」时给出**相反结论**：按档位说不可见，按路径分级又判成桌面可见。
  /// 今天没露馅只是因为界面还没接后者 —— 一旦接上就会对用户撒谎。
  ///
  /// ② 档（SAF）是例外：那里的 `root` 是应用内回退路径，真正可见的是用户
  /// 授权的那个文件夹，所以只要用户授权过就算可见。
  bool get userVisible =>
      mode == OgLStorageMode.safDir || OgLAppDirs.isUserVisible(root);

  /// 诊断用短串。
  String get label => switch (mode) {
        OgLStorageMode.publicDir => 'public',
        OgLStorageMode.safDir => 'saf',
        OgLStorageMode.internal => 'internal',
      };

  @override
  String toString() => 'OgLStoragePlan($label, root=$root)';
}

/// SAF（Storage Access Framework）操作封装。
///
/// **只在 Android 上被调用**；其余平台这些方法不会被走到。
/// 刻意不直接引用插件的数据类型（`SafDocumentFile` / `SafNewFile`），
/// 只用已确认存在的方法签名 + `dynamic` 读字段——把编译面压到最小。
abstract final class OgLSaf {
  /// 选一个文件夹并获得**可持久化**的读写授权；取消 / 失败返回 `null`。
  static Future<String?> pickDirectory() async {
    if (kIsWeb || !Platform.isAndroid) {
      return null;
    }
    try {
      final Object? picked = await SafUtil().pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      if (picked == null) {
        return null;
      }
      final Object? uri = (picked as dynamic).uri;
      final String? text = uri?.toString();
      return (text == null || text.isEmpty) ? null : text;
    } catch (error) {
      debugPrint('OGL 存储：选择 SAF 文件夹失败：$error');
      return null;
    }
  }

  /// 把本地文件**粘贴**进 SAF 目录；成功返回 `true`。
  static Future<bool> pasteLocalFile({
    required String srcPath,
    required String treeUri,
    required String fileName,
    String mime = 'application/octet-stream',
  }) async {
    if (kIsWeb || !Platform.isAndroid) {
      return false;
    }
    try {
      await SafStream().pasteLocalFile(
        srcPath,
        treeUri,
        fileName,
        mime,
        overwrite: true,
      );
      return true;
    } catch (error) {
      debugPrint('OGL 存储：导出到 SAF 失败：$error');
      return false;
    }
  }
}

/// 落盘方案的**唯一裁决处**。
abstract final class OgLStorage {
  /// 已授权的 SAF 目录 URI（进程缓存）。
  static String? _safUri;

  /// 是否已从磁盘读过 SAF 配置。
  static bool _safLoaded = false;

  /// SAF 配置文件名（存在**应用支持目录**：一定可写，不需要任何权限）。
  static const String _safFileName = 'ogl_saf_tree.txt';

  /// 已知的 SAF 目录 URI（未授权 = `null`）。
  static String? get safTreeUri => _safUri;

  static Future<File> _safFile() async {
    final Directory support = await getApplicationSupportDirectory();
    return File('${support.path.replaceAll(r'\', '/')}/$_safFileName');
  }

  /// 从磁盘加载 SAF 授权（只读一次）。
  static Future<void> ensureLoaded() async {
    if (_safLoaded) {
      return;
    }
    _safLoaded = true;
    try {
      final File file = await _safFile();
      if (await file.exists()) {
        final String text = (await file.readAsString()).trim();
        _safUri = text.isEmpty ? null : text;
      }
    } catch (_) {
      _safUri = null;
    }
  }

  /// 记录 / 清除 SAF 授权（`null` = 清除）。
  static Future<void> setSafTreeUri(String? uri) async {
    _safLoaded = true;
    _safUri = (uri == null || uri.isEmpty) ? null : uri;
    try {
      final File file = await _safFile();
      if (_safUri == null) {
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        await file.writeAsString(_safUri!, flush: true);
      }
    } catch (error) {
      debugPrint('OGL 存储：写入 SAF 配置失败：$error');
    }
  }

  /// **裁决当前落盘方案**（每次都会重新探测公共目录可写性）。
  ///
  /// 顺序即优先级：① 公共目录 → ② SAF → ③ 内部。
  static Future<OgLStoragePlan> plan() async {
    await ensureLoaded();
    if (await OgLAppDirs.publicWritable()) {
      final String? root = await OgLAppDirs.publicRoot();
      if (root != null) {
        return OgLStoragePlan(mode: OgLStorageMode.publicDir, root: root);
      }
    }
    final String fallback = await OgLAppDirs.root();
    if (_safUri != null) {
      return OgLStoragePlan(
        mode: OgLStorageMode.safDir,
        root: fallback,
        safTreeUri: _safUri,
      );
    }
    return OgLStoragePlan(mode: OgLStorageMode.internal, root: fallback);
  }

  /// 把刚落盘的成品**导出**到 SAF 文件夹（② 档专用）。
  ///
  /// 未授权 / 非 Android / 失败 → 返回 `false`（**绝不抛**，也不阻断下载）。
  static Future<bool> exportToSaf({
    required String localPath,
    required String fileName,
  }) async {
    final String? uri = _safUri;
    if (uri == null) {
      return false;
    }
    if (!File(localPath).existsSync()) {
      return false;
    }
    return OgLSaf.pasteLocalFile(
      srcPath: localPath,
      treeUri: uri,
      fileName: fileName,
    );
  }
}