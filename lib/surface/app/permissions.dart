/// L3 展示级 · 权限网关（跨平台分派 + 真实探测）。
///
/// ## 为什么不是 `permission_handler`
/// `pubspec.yaml` 已明确记录：`permission_handler_android` 要求宿主
/// `compileSdk ≥ 37`，与当前 Flutter 构建链冲突，会在 CI 直接构建失败。
/// 因此本项目**不引入第三方权限插件**，改用纯 Dart 的权限网关。
///
/// ## "主动获取"能做到什么
/// - **存储**：用**真实写入探针**主动尝试（建目录 → 写探针 → 删探针）。
///   成功即视为已具备（应用会自动选一个可写目录，无需系统权限）；
///   失败则引导到系统设置。
/// - **通知**：纯 Dart 无法直接申请系统通知权限，网关会**打开系统设置**
///   让用户开启；拿不到就如实说明。
/// 网关绝不假装已授权：状态来自真实探测或用户的明确动作。
///
/// ## 不同平台
/// | 平台            | 存储                 | 通知                 |
/// |-----------------|----------------------|----------------------|
/// | Android         | 探针可用即具备       | 需手动（13+）        |
/// | iOS             | 不需要（沙箱）       | 需手动               |
/// | Windows/Linux   | 不需要               | 不需要               |
/// | macOS           | 不需要               | 需手动               |
/// | Web             | 不支持               | 不支持               |
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 权限种类（与业务相关的最小集合）。
enum OgLPermission {
  /// 存储 / 文件访问（影响日志落盘位置、下载文件可见性）。
  storage,

  /// 通知（影响限流提醒等主动提示）。
  notifications,
}

/// 权限状态。
enum OgLPermissionStatus {
  /// 已具备（或系统已默认授予）。
  granted,

  /// 需要用户到系统设置手动开启。
  needsUserAction,

  /// 该平台不需要此类权限。
  notRequired,

  /// 该平台不支持此类权限。
  unsupported,
}

/// 单条权限的说明与状态。
@immutable
class OgLPermissionInfo {
  /// 创建条目。
  const OgLPermissionInfo({
    required this.permission,
    required this.title,
    required this.rationale,
    required this.status,
  });

  /// 权限种类。
  final OgLPermission permission;

  /// 标题。
  final String title;

  /// 为什么需要它。
  final String rationale;

  /// 当前状态。
  final OgLPermissionStatus status;

  /// 是否还需要用户处理。
  bool get actionable => status == OgLPermissionStatus.needsUserAction;

  /// 是否已就绪（无需再处理）。
  bool get ready =>
      status == OgLPermissionStatus.granted ||
      status == OgLPermissionStatus.notRequired;

  /// 复制并覆盖状态。
  OgLPermissionInfo withStatus(OgLPermissionStatus next) => OgLPermissionInfo(
        permission: permission,
        title: title,
        rationale: rationale,
        status: next,
      );
}

/// 权限网关接口（各平台实现）。
abstract class OgLPermissionGateway {
  /// 平台展示名（引导页会明显展示，用户要知道自己在为哪个平台授权）。
  String get platformLabel;

  /// 本平台托管的权限清单及其当前状态。
  Future<List<OgLPermissionInfo>> describe();

  /// 主动获取一次（尽力而为）。返回获取后的状态。
  Future<OgLPermissionStatus> request(OgLPermission permission);

  /// 是否具备"跳到本应用系统设置页"的能力。
  bool get canOpenSettings;
}

/// 按运行平台创建网关（**唯一入口**）。
///
/// [storageProbe] 由装配层注入：返回"应用目录当前是否可写"。
/// 不传时按"可用"处理（例如桌面端）。
OgLPermissionGateway ogLPermissionGateway({
  Future<bool> Function()? storageProbe,
}) {
  if (kIsWeb) {
    return const _WebPermissionGateway();
  }
  if (Platform.isAndroid) {
    return _AndroidPermissionGateway(storageProbe: storageProbe);
  }
  if (Platform.isIOS) {
    return const _IosPermissionGateway();
  }
  if (Platform.isMacOS) {
    return const _MacPermissionGateway();
  }
  return const _DesktopPermissionGateway();
}

/// 尝试跳转到本应用的系统设置页。
Future<bool> _openAppSettings() async {
  const List<String> candidates = <String>['app-settings:'];
  for (final String candidate in candidates) {
    try {
      if (await launchUrl(
        Uri.parse(candidate),
        mode: LaunchMode.externalApplication,
      )) {
        return true;
      }
    } catch (error) {
      // 该 URI 不被系统识别：记录后继续尝试下一个；全部失败返回 false，
      // 由 UI 如实告知用户"需手动前往系统设置"，绝不假装成功。
      debugPrint('OGL 权限网关：打开系统设置失败（$candidate）：$error');
    }
  }
  return false;
}

/// Android：存储（探针可用即具备）+ 通知（13+ 需手动）。
class _AndroidPermissionGateway implements OgLPermissionGateway {
  /// 创建网关。
  const _AndroidPermissionGateway({this.storageProbe});

  /// 存储探针（由装配层注入）。
  final Future<bool> Function()? storageProbe;

  @override
  String get platformLabel => 'Android';

  @override
  bool get canOpenSettings => true;

  Future<bool> _storageOk() async {
    final probe = storageProbe;
    if (probe == null) {
      return true;
    }
    try {
      return await probe();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<OgLPermissionInfo>> describe() async {
    final bool storageOk = await _storageOk();
    return <OgLPermissionInfo>[
      OgLPermissionInfo(
        permission: OgLPermission.storage,
        title: '存储 / 文件访问',
        rationale: storageOk
            ? '已找到一个可写目录，日志与下载文件会写在那里，无需额外授权。'
            : '未找到可写目录。请在系统设置中允许本应用访问存储，'
                '或授予"所有文件访问"以便写入根目录下的 ogl 文件夹。',
        status: storageOk
            ? OgLPermissionStatus.granted
            : OgLPermissionStatus.needsUserAction,
      ),
      const OgLPermissionInfo(
        permission: OgLPermission.notifications,
        title: '通知',
        rationale: 'Android 13+ 需要你手动允许通知，否则限流提醒等提示不会出现。',
        status: OgLPermissionStatus.needsUserAction,
      ),
    ];
  }

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async {
    if (permission == OgLPermission.storage) {
      // 先尝试"就地获取"：探针成功即说明无需系统权限。
      if (await _storageOk()) {
        return OgLPermissionStatus.granted;
      }
      final bool opened = await _openAppSettings();
      return opened
          ? OgLPermissionStatus.needsUserAction
          : OgLPermissionStatus.unsupported;
    }
    final bool opened = await _openAppSettings();
    return opened
        ? OgLPermissionStatus.needsUserAction
        : OgLPermissionStatus.unsupported;
  }
}

/// iOS：沙箱内存储无需权限；通知需手动。
class _IosPermissionGateway implements OgLPermissionGateway {
  /// 创建网关。
  const _IosPermissionGateway();

  @override
  String get platformLabel => 'iOS';

  @override
  bool get canOpenSettings => true;

  @override
  Future<List<OgLPermissionInfo>> describe() async =>
      const <OgLPermissionInfo>[
        OgLPermissionInfo(
          permission: OgLPermission.storage,
          title: '存储 / 文件访问',
          rationale: 'iOS 应用运行在沙箱内，无需额外存储权限。',
          status: OgLPermissionStatus.notRequired,
        ),
        OgLPermissionInfo(
          permission: OgLPermission.notifications,
          title: '通知',
          rationale: '需要你手动允许通知，才能收到限流等主动提示。',
          status: OgLPermissionStatus.needsUserAction,
        ),
      ];

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async {
    if (permission == OgLPermission.storage) {
      return OgLPermissionStatus.notRequired;
    }
    final bool opened = await _openAppSettings();
    return opened
        ? OgLPermissionStatus.needsUserAction
        : OgLPermissionStatus.unsupported;
  }
}

/// macOS：存储沙箱无需权限；通知需手动。
class _MacPermissionGateway implements OgLPermissionGateway {
  /// 创建网关。
  const _MacPermissionGateway();

  @override
  String get platformLabel => 'macOS';

  @override
  bool get canOpenSettings => true;

  @override
  Future<List<OgLPermissionInfo>> describe() async =>
      const <OgLPermissionInfo>[
        OgLPermissionInfo(
          permission: OgLPermission.storage,
          title: '存储 / 文件访问',
          rationale: 'macOS 应用沙箱内无需额外存储权限。',
          status: OgLPermissionStatus.notRequired,
        ),
        OgLPermissionInfo(
          permission: OgLPermission.notifications,
          title: '通知',
          rationale: '需要在系统设置中允许通知。',
          status: OgLPermissionStatus.needsUserAction,
        ),
      ];

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async {
    if (permission == OgLPermission.storage) {
      return OgLPermissionStatus.notRequired;
    }
    final bool opened = await _openAppSettings();
    return opened
        ? OgLPermissionStatus.needsUserAction
        : OgLPermissionStatus.unsupported;
  }
}

/// Windows / Linux：桌面平台，所需权限均不需要。
class _DesktopPermissionGateway implements OgLPermissionGateway {
  /// 创建网关。
  const _DesktopPermissionGateway();

  @override
  String get platformLabel {
    if (Platform.isWindows) {
      return 'Windows';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    // 其它桌面/未知平台：用系统名兜底，避免谎报平台。
    return Platform.operatingSystem;
  }

  @override
  bool get canOpenSettings => false;

  @override
  Future<List<OgLPermissionInfo>> describe() async =>
      const <OgLPermissionInfo>[
        OgLPermissionInfo(
          permission: OgLPermission.storage,
          title: '存储 / 文件访问',
          rationale: '桌面平台直接使用应用数据目录，无需授权。',
          status: OgLPermissionStatus.notRequired,
        ),
        OgLPermissionInfo(
          permission: OgLPermission.notifications,
          title: '通知',
          rationale: '桌面平台无系统级权限门槛。',
          status: OgLPermissionStatus.notRequired,
        ),
      ];

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async =>
      OgLPermissionStatus.notRequired;
}

/// Web：不支持系统权限。
class _WebPermissionGateway implements OgLPermissionGateway {
  /// 创建网关。
  const _WebPermissionGateway();

  @override
  String get platformLabel => 'Web';

  @override
  bool get canOpenSettings => false;

  @override
  Future<List<OgLPermissionInfo>> describe() async =>
      const <OgLPermissionInfo>[
        OgLPermissionInfo(
          permission: OgLPermission.storage,
          title: '存储 / 文件访问',
          rationale: '浏览器环境由浏览器自身管理存储配额，应用无法也无需申请。',
          status: OgLPermissionStatus.unsupported,
        ),
        OgLPermissionInfo(
          permission: OgLPermission.notifications,
          title: '通知',
          rationale: 'Web 端不提供本应用所需的通知能力。',
          status: OgLPermissionStatus.unsupported,
        ),
      ];

  @override
  Future<OgLPermissionStatus> request(OgLPermission permission) async =>
      OgLPermissionStatus.unsupported;
}