/// L1 底座级 · 硬盘逻辑：**Web 实现**（浏览器目标，本分支唯一实现）。
///
/// 由 `platform_io.dart` 直接导出；公开 API（`PlatformStorage` /
/// `PlatformDiskPaths` / `IoDiskFileStore` / `IoDiskKv` / `SecureDiskVault`）
/// 保持既有名字不变，`DiskKv` / `DiskVault` / `DiskFileStore` 三大契约
/// （见 `kernel/contract/disk_store.dart`）按下面如实写明的差异实现。
///
/// ## 浏览器下的真实语义（**不假装**）
/// - **没有文件系统**：`IoDiskFileStore` 是**进程存活期内有效**的内存文件表。
///   刷新页面即清空；`sweepTemp()` 无残骸可扫，恒返回 0。
///   —— 注释即约定：这里**不假装**能把文件持久化。
/// - **KV 走 `localStorage`**：`IoDiskKv` 把值写进浏览器 `localStorage`
///   （键按应用根前缀隔离），因此键值在刷新后仍在。若 `localStorage`
///   不可用（隐私模式 / 禁用存储），自动降级为进程内存，绝不抛。
/// - **安全保险库无系统密钥库**：浏览器没有 Keystore / DPAPI / libsecret。
///   为避免把长期令牌**明文**留在 `localStorage`，Web 端保险库**仅内存持有**
///   （刷新后需重新登录）。这是一处**如实的能力缺失**，不是静默降级。
library;

import 'dart:js_interop';

import 'disk_bridge.dart';
import 'disk_cache.dart';
import 'disk_draft.dart';
import 'disk_journal.dart';
import 'disk_store.dart';

// ── localStorage 互操作（dart:js_interop）──────────────────────────────

@JS('localStorage')
external _WebStorage get _localStorage;

/// 浏览器 `Storage` 的最小接口（只声明用到的成员）。
extension type _WebStorage._(JSObject _) implements JSObject {
  external int get length;
  external String? key(int index);
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// 基于内存文件表 + `localStorage` KV 的存储（浏览器）。
///
/// ## 两条硬规则（与 io 实现对齐的**契约**）
/// 1. **路径安全**：所有相对路径落表前经 [abs]：归一化前导 `/`（绝对路径因此
///    落在根内，不会逃逸）、**拒绝** `..`。空串是合法入参（`list('')` = 列根）。
/// 2. **删/写幂等**：不存在时删除静默、覆盖写入替换——上层无需区分实现。
class IoDiskFileStore implements DiskFileStore {
  /// 创建文件存储（`root` 仅作虚拟前缀 / 诊断展示，浏览器下不落真实目录）。
  IoDiskFileStore({required String root}) : _root = _normalizeRoot(root);

  final String _root;

  /// 根目录（浏览器下的**虚拟**前缀，如 `web/files`）。
  String get root => _root;

  /// 内存文件表：键 = 归一化后的**根内相对路径**，值 = 文本内容。
  /// 进程存活期内有效；页面刷新即清空（浏览器无持久文件系统）。
  final Map<String, String> _files = <String, String>{};

  static String _normalizeRoot(String root) {
    var value = root.replaceAll(r'\', '/');
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 触发长路径处理的门槛（Win32 的 MAX_PATH 是 260）。
  ///
  /// Web 无 Win32，保留常量只为与 io 实现**公开 API 对齐**。
  static const int kWinPathSoftLimit = 240;

  /// Windows 长路径前缀。Web 不存在 Win32，原样返回。
  static String winLong(String posixAbs) => posixAbs;

  /// 把仓库相对路径解析为绝对路径，并执行安全校验（与 io 实现同一条规则）。
  ///
  /// `relative` 为空表示根目录本身（仅 [list] 允许）。
  String abs(String relative) {
    final path = InMemoryFileStore.normalize(relative);
    if (path.split('/').contains('..')) {
      throw ArgumentError.value(relative, 'path', '路径不得包含 ..（防目录穿越）');
    }
    return path.isEmpty ? _root : '$_root/$path';
  }

  /// 取内存表的归一化键（空路径是非法文件路径）。
  String _key(String relative) {
    final path = InMemoryFileStore.normalize(relative);
    if (path.isEmpty) {
      throw ArgumentError.value(relative, 'path', '文件路径不能为空');
    }
    return path;
  }

  @override
  Future<String?> readText(String path) async => _files[_key(path)];

  @override
  Future<void> writeText(String path, String content) async {
    _files[_key(path)] = content;
  }

  @override
  Future<void> delete(String path) async {
    _files.remove(_key(path));
  }

  @override
  Future<bool> exists(String path) async => _files.containsKey(_key(path));

  @override
  Future<List<String>> list(String directory) async {
    final prefix = InMemoryFileStore.normalize(directory);
    final scope = prefix.isEmpty ? '' : '$prefix/';
    final names = <String>{};
    for (final key in _files.keys) {
      if (!key.startsWith(scope)) {
        continue;
      }
      final rest = key.substring(scope.length);
      if (rest.isEmpty) {
        continue;
      }
      names.add(rest.contains('/') ? rest.substring(0, rest.indexOf('/')) : rest);
    }
    return names.toList()..sort();
  }

  /// 清扫中断残留的临时文件。浏览器下**没有文件系统**，也就没有残骸——恒 0。
  Future<({int removed, List<String> failed})> sweepTemp() async =>
      (removed: 0, failed: const <String>[]);
}

/// 基于 `localStorage` 的键值存储（浏览器）。
///
/// 键按应用根前缀隔离（`ogl.kv.<root>.<key>`），因此刷新后仍在；
/// `localStorage` 不可用时自动降级为进程内存（绝不抛）。
class IoDiskKv implements DiskKv {
  /// 创建键值存储。
  IoDiskKv({required String root})
      : _prefix = 'ogl.kv.${IoDiskFileStore._normalizeRoot(root)}.',
        _store = IoDiskFileStore(root: '$root/kv');

  final String _prefix;
  final IoDiskFileStore _store;

  /// 底层文件存储（诊断用；浏览器下为内存文件表，不参与 KV 读写）。
  IoDiskFileStore get store => _store;

  /// 降级镜像：`localStorage` 写入失败时的兜底，同时作为读取的第二来源。
  static final Map<String, String> _mirror = <String, String>{};

  @override
  Future<String?> read(String key) async {
    final String name = '$_prefix$key';
    try {
      return _localStorage.getItem(name) ?? _mirror[name];
    } catch (_) {
      return _mirror[name];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    final String name = '$_prefix$key';
    _mirror[name] = value;
    try {
      _localStorage.setItem(name, value);
    } catch (_) {
      // 存储不可用：保留在内存镜像里，不抛。
    }
  }

  @override
  Future<void> remove(String key) async {
    final String name = '$_prefix$key';
    _mirror.remove(name);
    try {
      _localStorage.removeItem(name);
    } catch (_) {
      // 同上。
    }
  }

  @override
  Future<bool> has(String key) async {
    final String name = '$_prefix$key';
    try {
      if (_localStorage.getItem(name) != null) {
        return true;
      }
    } catch (_) {
      // 落到镜像判断。
    }
    return _mirror.containsKey(name);
  }

  @override
  Future<List<String>> keys() async {
    final names = <String>{};
    try {
      final int n = _localStorage.length;
      for (var i = 0; i < n; i++) {
        final String? name = _localStorage.key(i);
        if (name != null && name.startsWith(_prefix)) {
          names.add(name.substring(_prefix.length));
        }
      }
    } catch (_) {
      // 存储不可用：只从镜像取。
    }
    for (final String name in _mirror.keys) {
      if (name.startsWith(_prefix)) {
        names.add(name.substring(_prefix.length));
      }
    }
    final result = names.toList()..sort();
    return result;
  }
}

/// 安全保险库：**Web 端仅内存持有**。
///
/// 浏览器没有 Keystore / DPAPI / libsecret；为不把长期令牌**明文**写进
/// `localStorage`，这里只保存在进程内存中——刷新页面即失效（用户需重新登录）。
/// 这是**如实的能力缺失**，不是静默降级：调用方拿到的仍是 [DiskVault] 契约。
class SecureDiskVault implements DiskVault {
  /// 创建保险库（Web 端无系统密钥库，构造不接收存储后端）。
  SecureDiskVault();

  static final Map<String, String> _secrets = <String, String>{};

  static const String _prefix = 'ogl.vault.';

  @override
  Future<String?> readSecret(String key) async => _secrets['$_prefix$key'];

  @override
  Future<void> writeSecret(String key, String value) async {
    _secrets['$_prefix$key'] = value;
  }

  @override
  Future<void> deleteSecret(String key) async {
    _secrets.remove('$_prefix$key');
  }
}

/// 平台目录规划（浏览器下的虚拟前缀）。
class PlatformDiskPaths implements DiskPaths {
  /// 创建路径规划。
  const PlatformDiskPaths({required this.root});

  /// 根目录（虚拟前缀，如 `web`）。
  final String root;

  @override
  Future<String> cacheRoot() async => '$root/cache';

  @override
  Future<String> configRoot() async => '$root/config';

  @override
  Future<String> logRoot() async => '$root/logs';
}

/// 平台存储装配（Web）：解析虚拟根目录，构建内存文件表 + `localStorage` KV。
///
/// `folder` 仅为与 io 实现保持**同一签名**（浏览器无多档目录，恒用虚拟根 `web`）。
class PlatformStorage {
  /// 创建装配结果。
  const PlatformStorage({
    required this.root,
    required this.paths,
    required this.files,
    required this.kv,
    required this.vault,
  });

  /// 根目录（虚拟前缀）。
  final String root;

  /// 路径规划。
  final DiskPaths paths;

  /// 用户文件存储（内存文件表）。
  final DiskFileStore files;

  /// 键值存储（`localStorage`）。
  final DiskKv kv;

  /// 安全保险库（内存）。
  final DiskVault vault;

  /// 打开平台存储。
  ///
  /// [folder] 在 Web 端**不参与**目录解析（浏览器只有一档虚拟根），
  /// 仅为与 io 实现签名一致而保留；[rootOverride] 可覆盖虚拟根（测试 / 预览）。
  static Future<PlatformStorage> open({
    String folder = 'ohgithublost',
    String? rootOverride,
  }) async {
    final root = IoDiskFileStore._normalizeRoot(rootOverride ?? 'web');

    final files = IoDiskFileStore(root: '$root/files');
    // 启动清扫：浏览器无残骸，调用只为对齐 io 的启动流程（恒 0）。
    await files.sweepTemp();

    return PlatformStorage(
      root: root,
      paths: PlatformDiskPaths(root: root),
      files: files,
      kv: IoDiskKv(root: root),
      vault: SecureDiskVault(),
    );
  }

  /// 组装成 L1 硬盘模块（KV 走 `localStorage`，文件类落在内存表，日志见 `log_dirs` 的 web 分支）。
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
  String toString() => 'PlatformStorage(root=$root, web=true)';
}
