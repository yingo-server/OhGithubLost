/// L1 底座级 · 硬盘逻辑：真实平台持久化（Android / Windows / Linux）。
///
/// ## 为什么单独成文件
/// 上层（缓存引擎 / 提交日志 / 草稿 / 偏好）只认识
/// [DiskKv] / [DiskFileStore] / [DiskVault] / [DiskPaths] 接口；
/// 本文件是**唯一**知道"东西到底落在哪、怎么落"的地方。
/// 换平台、换存储后端，都只改这里。
///
/// ## 两条硬规则
/// 1. **原子写**：先写 `*.tmp` 并 `flush`（fsync），再 `rename` 覆盖目标。
///    掉电 / 被系统杀**不会**产生半截文件——这是 D5 完整性校验之外的第二道保险。
/// 2. **启动清扫**：残留的 `*.tmp` 一律删除。它们是中断的残骸，不是数据；
///    留着只会污染目录列举结果。
///
/// ## 安全边界
/// 所有相对路径在落盘前必须通过 [IoDiskFileStore.abs]：
/// 拒绝空路径、拒绝绝对路径、拒绝 `..`——**绝不写出根目录之外**。
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import 'disk_bridge.dart';
import 'disk_cache.dart';
import 'disk_draft.dart';
import 'disk_journal.dart';
import 'disk_store.dart';

/// 基于 `dart:io` 的文件存储（**原子写**）。
class IoDiskFileStore implements DiskFileStore {
  /// 创建文件存储。
  IoDiskFileStore({required String root}) : _root = _normalizeRoot(root);

  final String _root;

  /// 根目录（绝对路径，POSIX 分隔符）。
  String get root => _root;

  static String _normalizeRoot(String root) {
    var value = root.replaceAll(r'\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 把仓库相对路径解析为绝对路径，并执行安全校验。
  ///
  /// `relative` 为空表示根目录本身（仅 [list] 允许）。
  String abs(String relative) {
    final path = InMemoryFileStore.normalize(relative);
    if (path.split('/').contains('..')) {
      throw ArgumentError.value(relative, 'path', '路径不得包含 ..（防目录穿越）');
    }
    return path.isEmpty ? _root : '$_root/$path';
  }

  String _absFile(String relative) {
    if (InMemoryFileStore.normalize(relative).isEmpty) {
      throw ArgumentError.value(relative, 'path', '文件路径不能为空');
    }
    return abs(relative);
  }

  @override
  Future<String?> readText(String path) async {
    final file = File(_absFile(path));
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  @override
  Future<void> writeText(String path, String content) async {
    final target = File(_absFile(path));
    await target.parent.create(recursive: true);

    // 原子写：临时文件 → flush（fsync）→ rename 替换。
    // 临时文件名必须**唯一**：固定 `<目标>.tmp` 在"同一目标被并发写"时
    // 会互相踩（A 写完 tmp、B 覆盖 tmp、A rename 时文件已被 B 移走 → ENOENT）。
    final temp = File(_tempNameOf(target));
    await temp.writeAsString(content, flush: true);
    await temp.rename(target.path);
  }

  static int _tempSeq = 0;

  /// 生成唯一临时文件名（保持 `.tmp` 后缀，便于启动清扫识别）。
  static String _tempNameOf(File target) =>
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}-${_tempSeq++}.tmp';

  @override
  Future<void> delete(String path) async {
    final file = File(_absFile(path));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists(String path) => File(_absFile(path)).exists();

  @override
  Future<List<String>> list(String directory) async {
    final dir = Directory(abs(directory));
    if (!await dir.exists()) {
      return const <String>[];
    }
    final names = <String>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.isEmpty
          ? entity.path
          : entity.uri.pathSegments.last;
      if (name.endsWith('.tmp')) {
        continue; // 残骸不算条目。
      }
      names.add(name);
    }
    names.sort();
    return names;
  }

  /// 清扫上次中断留下的临时文件。
  ///
  /// 返回 `(removed, failed)`：失败项**不静默吞掉**，交由调用方诊断。
  Future<({int removed, List<String> failed})> sweepTemp() async {
    final rootDir = Directory(_root);
    if (!await rootDir.exists()) {
      return (removed: 0, failed: const <String>[]);
    }
    var removed = 0;
    final failed = <String>[];
    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is! File ||
          !entity.path.replaceAll(r'\', '/').endsWith('.tmp')) {
        continue;
      }
      try {
        await entity.delete();
        removed++;
      } catch (error) {
        failed.add('${entity.path}: $error');
      }
    }
    return (removed: removed, failed: failed);
  }
}

/// 基于文件的键值存储。
///
/// **文件名 = `sha256(键)`，文件内容 = `{"k": 原键, "v": 值}`。**
///
/// 为什么不直接把键当文件名：键里含 `/`、`|`，且可能因深层路径超过文件系统
/// 的长度上限。用摘要做文件名 + 在文件里存原键，既安全又可反查
/// （[keys] 靠读原键还原）。
class IoDiskKv implements DiskKv {
  /// 创建键值存储。
  IoDiskKv({required String root})
      : _store = IoDiskFileStore(root: '$root/kv');

  final IoDiskFileStore _store;

  /// 底层文件存储（诊断用）。
  IoDiskFileStore get store => _store;

  static String _nameOf(String key) => '${sha256.convert(utf8.encode(key))}.json';

  @override
  Future<String?> read(String key) async {
    final raw = await _store.readText(_nameOf(key));
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (decoded['k'] != key) {
        // 摘要碰撞或脏数据：当作不存在，绝不返回别人的值。
        return null;
      }
      return decoded['v'] as String;
    } catch (_) {
      // 结构损坏：清掉，避免每次读取都报错。
      await _store.delete(_nameOf(key));
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) => _store.writeText(
        _nameOf(key),
        jsonEncode(<String, Object?>{'k': key, 'v': value}),
      );

  @override
  Future<void> remove(String key) => _store.delete(_nameOf(key));

  @override
  Future<bool> has(String key) => _store.exists(_nameOf(key));

  @override
  Future<List<String>> keys() async {
    final result = <String>[];
    for (final name in await _store.list('')) {
      final raw = await _store.readText(name);
      if (raw == null) {
        continue;
      }
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final key = decoded['k'] as String?;
        if (key != null) {
          result.add(key);
        }
      } catch (_) {
        // 脏文件：留给 read/remove 自清。
        continue;
      }
    }
    result.sort();
    return result;
  }
}

/// 安全保险库：走平台密钥库
/// （Android Keystore / Windows DPAPI / Linux libsecret）。
class SecureDiskVault implements DiskVault {
  /// 创建保险库。
  SecureDiskVault({FlutterSecureStorage? storage})
      : _storage = storage ?? FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const String _prefix = 'ogl.vault.';

  @override
  Future<String?> readSecret(String key) =>
      _storage.read(key: '$_prefix$key');

  @override
  Future<void> writeSecret(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> deleteSecret(String key) =>
      _storage.delete(key: '$_prefix$key');
}

/// 平台目录规划（应用私有目录下）。
class PlatformDiskPaths implements DiskPaths {
  /// 创建路径规划。
  const PlatformDiskPaths({required this.root});

  /// 根目录。
  final String root;

  @override
  Future<String> cacheRoot() async => '$root/cache';

  @override
  Future<String> configRoot() async => '$root/config';

  @override
  Future<String> logRoot() async => '$root/logs';
}

/// 平台存储装配：**一次**解析根目录，构建全部真实实现。
///
/// 用法（必须在 `WidgetsFlutterBinding.ensureInitialized()` 之后）：
/// ```dart
/// final storage = await PlatformStorage.open();
/// final kernel = OgLKernel(...);
/// await kernel.boot(<OgLModule>[...baseLayerModules(disk: storage.toDiskModule())]);
/// ```
class PlatformStorage {
  /// 创建装配结果。
  const PlatformStorage({
    required this.root,
    required this.paths,
    required this.files,
    required this.kv,
    required this.vault,
  });

  /// 根目录。
  final String root;

  /// 路径规划。
  final DiskPaths paths;

  /// 用户文件存储。
  final DiskFileStore files;

  /// 键值存储（缓存索引 / 提交日志 / 草稿共用，靠前缀隔离）。
  final DiskKv kv;

  /// 安全保险库。
  final DiskVault vault;

  /// 打开平台存储。
  ///
  /// [folder] 为应用私有根目录下的子目录名。
  /// [rootOverride] 用于测试或让用户指定自定义数据目录。
  static Future<PlatformStorage> open({
    String folder = 'ohgithublost',
    String? rootOverride,
  }) async {
    final root = rootOverride ?? await _resolveDefaultRoot(folder);
    final normalized = IoDiskFileStore._normalizeRoot(root);

    await Directory(normalized).create(recursive: true);
    final files = IoDiskFileStore(root: '$normalized/files');

    // 启动清扫：上次中断留下的残骸一律清掉。
    await files.sweepTemp();
    await IoDiskFileStore(root: '$normalized/cache').sweepTemp();
    await IoDiskFileStore(root: '$normalized/kv').sweepTemp();

    return PlatformStorage(
      root: normalized,
      paths: PlatformDiskPaths(root: normalized),
      files: files,
      kv: IoDiskKv(root: normalized),
      vault: SecureDiskVault(),
    );
  }

  static Future<String> _resolveDefaultRoot(String folder) async {
    final base = await getApplicationSupportDirectory();
    return '${base.path.replaceAll(r'\', '/')}/$folder';
  }

  /// 组装成 L1 硬盘模块（缓存 / 日志 / 草稿全部落到真实磁盘）。
  ///
  /// 这里**不提供"关掉日志/草稿"的开关**：一旦关掉，`DiskModule` 会用内存实现
  /// 兜底，反而造出"以为关了、其实在内存里漂"的假象。
  /// 真要换实现，请直接给 `DiskModule` 注入自己的 `store`。
  DiskModule toDiskModule() {
    final indexKv = kv;
    return DiskModule(
      kv: kv,
      vault: vault,
      files: files,
      paths: paths,
      cache: RepositoryCache(
        index: indexKv,
        blobs: IoDiskFileStore(root: '$root/cache'),
      ),
      journal: WriteJournal(store: indexKv),
      drafts: DraftStore(store: indexKv),
    );
  }

  @override
  String toString() => 'PlatformStorage(root=$root)';
}