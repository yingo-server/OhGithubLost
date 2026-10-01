/// L3 展示级 · 权限策略：跨平台权限模型（Android / iOS / Windows / Linux / macOS）。
///
/// ## 为什么"权限"要在展示层建模，而不是散在各页里
/// 同一件事（比如"选一个文件"）在五个平台上的**用户可见含义完全不同**：
/// - Android 13+：`READ_MEDIA_*` 按媒体类型分权，图片和文档是两回事；
/// - Android 5.1（本项目最低支持）：只有安装期 `READ_EXTERNAL_STORAGE`；
/// - iOS：必须先在 `Info.plist` 声明用途字符串，否则**调用即崩**；
/// - Windows：大多没有运行期弹窗，文件访问靠系统文件选择器即可；
/// - macOS：沙箱 + `NSOpenPanel`，还需用户授权"文件夹访问"；
/// - Linux：基本没有运行期权限概念（全靠文件系统权限位）。
///
/// 所以这里定义的是**策略矩阵**：每个（平台 × 权限）组合都要回答三个问题：
/// 1. **怎么问**（[OgLAskKind]）——有没有弹窗。
/// 2. **不给会怎样**（[OgLDenyBehavior]）——降级还是阻塞。
/// 3. **用户会失去什么**（[OgLPermissionRule.consequence]）——必须写清楚。
///
/// ## 两条不可违背的约定
/// 1. **主功能不依赖任何权限**：浏览公开仓库、查看代码永远可用。
///    没有任何一条规则是 `block` 且涉及核心流程的。
/// 2. **不假装知道**：未知平台 / 未知权限一律判为 [OgLAskKind.notRequired]，
///    而不是猜一个"大概需要授权"。宁可少要，不可多要。
library;

import '../layout/adaptive.dart';

/// 权限项（**业务语义**，不是系统 API 名）。
enum OgLPermission {
  /// 系统通知（后台任务完成 / 冲突提醒）。
  notifications,

  /// 相册读取（选图上传）。
  photos,

  /// 相机（扫码 / 拍照上传）。
  camera,

  /// 麦克风（语音输入 / 录屏讲解）。
  microphone,

  /// 共享存储（导出文件到公共目录）。
  storage,

  /// 任意路径文件访问（导入 / 导出到用户自选目录）。
  fileSystem,

  /// 网络诊断（读取当前 Wi-Fi / DNS 状态）。
  networkDiagnostics,

  /// 后台刷新（应用不可见时继续同步）。
  backgroundRefresh,

  /// 拉起外部应用（浏览器 / 编辑器 / 终端）。
  externalLaunch,

  /// 生物识别（解锁保险库中的令牌）。
  biometric,
}

/// 询问方式。
enum OgLAskKind {
  /// 运行期弹窗（用户可选择拒绝）。
  runtimeDialog,

  /// 只能引导用户去系统设置里手动开（已被"拒绝且不再询问"）。
  systemSettingsOnly,

  /// 安装期声明（Android 5.1 时代的旧模型：装的时候就要，装完不可撤销）。
  installTime,

  /// 系统自带选择器即可（**不需要任何权限**，也不该弹窗）。
  systemPicker,

  /// 不需要。
  notRequired,
}

/// 拒绝之后的后果。
enum OgLDenyBehavior {
  /// 功能降级：相关入口隐藏或禁用，**其余功能完全不受影响**。
  degrade,

  /// 阻塞：该功能无法使用，但必须给出明确的"去哪里开"的指引。
  block,
}

/// 一条权限规则。
class OgLPermissionRule {
  /// 创建规则。
  const OgLPermissionRule({
    required this.permission,
    required this.askKind,
    required this.denyBehavior,
    required this.consequence,
    this.settingsHint,
  });

  /// 权限项。
  final OgLPermission permission;

  /// 询问方式。
  final OgLAskKind askKind;

  /// 拒绝后果。
  final OgLDenyBehavior denyBehavior;

  /// **失去它会失去什么**（必须写清楚，不允许"点了没反应"）。
  final String consequence;

  /// 去哪开（系统设置指引文案）。
  final String? settingsHint;

  /// 是否需要向用户发起询问。
  bool get needsPrompt =>
      askKind == OgLAskKind.runtimeDialog ||
      askKind == OgLAskKind.systemSettingsOnly;
}

/// 权限状态。
enum OgLPermissionStatus {
  /// 已授权。
  granted,

  /// 被拒绝（还可以再问）。
  denied,

  /// 被拒绝且不再询问（只能去系统设置）。
  permanentlyDenied,

  /// 受系统策略限制（家长控制 / 企业设备）。
  restricted,

  /// 部分授权（iOS 的"仅选定照片"）。
  limited,

  /// 不需要（该平台上没有这个概念）。
  notRequired;

  /// 当前是否可用。
  bool get isUsable =>
      this == OgLPermissionStatus.granted ||
      this == OgLPermissionStatus.limited ||
      this == OgLPermissionStatus.notRequired;
}

/// 某平台上的权限矩阵。
class OgLPermissionPolicy {
  /// 创建策略。
  const OgLPermissionPolicy({required this.platform, required this.rules});

  /// 按平台构建策略矩阵。
  factory OgLPermissionPolicy.forPlatform(OgLPlatformKind platform) =>
      OgLPermissionPolicy(
        platform: platform,
        rules: _matrixFor(platform),
      );

  /// 平台。
  final OgLPlatformKind platform;

  /// 规则表。
  final List<OgLPermissionRule> rules;

  /// 取某权限的规则；表中没有则视为"不需要"（不假装知道）。
  OgLPermissionRule ruleFor(OgLPermission permission) {
    for (final rule in rules) {
      if (rule.permission == permission) {
        return rule;
      }
    }
    return OgLPermissionRule(
      permission: permission,
      askKind: OgLAskKind.notRequired,
      denyBehavior: OgLDenyBehavior.degrade,
      consequence: '该平台上不存在此权限',
    );
  }

  /// 需要询问的权限列表（**只问真正需要的**，避免一上来弹五个框）。
  List<OgLPermission> get promptable => <OgLPermission>[
        for (final rule in rules)
          if (rule.needsPrompt) rule.permission,
      ];

  static List<OgLPermissionRule> _matrixFor(OgLPlatformKind platform) {
    switch (platform) {
      case OgLPlatformKind.android:
        return const <OgLPermissionRule>[
          OgLPermissionRule(
            permission: OgLPermission.notifications,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '后台同步完成、冲突提醒将不会通知你（功能本身仍会执行）',
            settingsHint: '系统设置 → 应用 → OhGithubLost → 通知',
          ),
          OgLPermissionRule(
            permission: OgLPermission.photos,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '无法从相册选择图片上传（仍可从文件选择器挑选）',
            settingsHint: '系统设置 → 应用 → OhGithubLost → 照片和视频',
          ),
          OgLPermissionRule(
            permission: OgLPermission.storage,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '导出文件将只能保存到应用私有目录，无法直接放进下载目录',
            settingsHint: '系统设置 → 应用 → OhGithubLost → 权限 → 文件和媒体',
          ),
          OgLPermissionRule(
            permission: OgLPermission.camera,
            askKind: OgLAskKind.systemPicker,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '扫码登录与拍照上传不可用',
          ),
          OgLPermissionRule(
            permission: OgLPermission.microphone,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '语音输入不可用',
            settingsHint: '系统设置 → 应用 → OhGithubLost → 权限 → 麦克风',
          ),
          OgLPermissionRule(
            permission: OgLPermission.networkDiagnostics,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence:
                '无法读取当前 Wi-Fi 的 DNS，设置页的"网络诊断"只显示基础连通性',
            settingsHint: '系统设置 → 应用 → OhGithubLost → 位置信息（读取 Wi-Fi 名称需要它）',
          ),
          OgLPermissionRule(
            permission: OgLPermission.backgroundRefresh,
            askKind: OgLAskKind.systemSettingsOnly,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '切到后台后同步会暂停，回到前台继续',
          ),
          OgLPermissionRule(
            permission: OgLPermission.biometric,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '保险库将退化为仅用设备锁屏保护，无法单次指纹解锁',
          ),
        ];

      case OgLPlatformKind.iOS:
        return const <OgLPermissionRule>[
          OgLPermissionRule(
            permission: OgLPermission.notifications,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '后台同步完成、冲突提醒将不会通知你',
            settingsHint: '设置 → 通知 → OhGithubLost',
          ),
          OgLPermissionRule(
            permission: OgLPermission.photos,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '无法从相册选择图片上传；可选"仅选定的照片"以最小授权',
            settingsHint: '设置 → 隐私与安全性 → 照片',
          ),
          OgLPermissionRule(
            permission: OgLPermission.camera,
            askKind: OgLAskKind.systemPicker,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '扫码登录与拍照上传不可用',
          ),
          OgLPermissionRule(
            permission: OgLPermission.biometric,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '保险库无法使用 Face ID / Touch ID 解锁',
            settingsHint: '设置 → 面容 ID 与密码',
          ),
          OgLPermissionRule(
            permission: OgLPermission.fileSystem,
            askKind: OgLAskKind.systemPicker,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '只能访问"文件"应用里你显式选择的位置',
          ),
          OgLPermissionRule(
            permission: OgLPermission.backgroundRefresh,
            askKind: OgLAskKind.systemSettingsOnly,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '后台拉取会显著受限（iOS 由系统决定何时唤醒）',
            settingsHint: '设置 → 通用 → 后台 App 刷新',
          ),
        ];

      case OgLPlatformKind.windows:
        return const <OgLPermissionRule>[
          OgLPermissionRule(
            permission: OgLPermission.notifications,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '同步完成与冲突提醒不会出现在操作中心',
            settingsHint: '系统 → 通知 → OhGithubLost',
          ),
          OgLPermissionRule(
            permission: OgLPermission.fileSystem,
            askKind: OgLAskKind.systemPicker,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '文件读写只能通过系统文件选择器（应用自身不持有任意路径访问）',
          ),
          OgLPermissionRule(
            permission: OgLPermission.externalLaunch,
            askKind: OgLAskKind.notRequired,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '无法用默认浏览器 / 编辑器打开外链与文件',
          ),
          OgLPermissionRule(
            permission: OgLPermission.backgroundRefresh,
            askKind: OgLAskKind.systemSettingsOnly,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '关闭窗口后同步停止（可开启"最小化到托盘"缓解）',
          ),
        ];

      case OgLPlatformKind.linux:
        return const <OgLPermissionRule>[
          OgLPermissionRule(
            permission: OgLPermission.notifications,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '依赖桌面环境的通知服务（D-Bus），不可用时静默降级为应用内提示',
          ),
          OgLPermissionRule(
            permission: OgLPermission.fileSystem,
            askKind: OgLAskKind.notRequired,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '受文件系统权限位限制（Flatpak / Snap 沙箱内会额外受限）',
          ),
          OgLPermissionRule(
            permission: OgLPermission.externalLaunch,
            askKind: OgLAskKind.notRequired,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '无法调用 xdg-open 打开外链',
          ),
        ];

      case OgLPlatformKind.macOS:
        return const <OgLPermissionRule>[
          OgLPermissionRule(
            permission: OgLPermission.notifications,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '同步完成与冲突提醒不会出现在通知中心',
            settingsHint: '系统设置 → 通知 → OhGithubLost',
          ),
          OgLPermissionRule(
            permission: OgLPermission.fileSystem,
            askKind: OgLAskKind.systemSettingsOnly,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '沙箱外目录（桌面 / 文稿 / 下载）需要你手动授权文件夹访问',
            settingsHint: '系统设置 → 隐私与安全性 → 文件与文件夹',
          ),
          OgLPermissionRule(
            permission: OgLPermission.biometric,
            askKind: OgLAskKind.runtimeDialog,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '保险库无法使用 Touch ID 解锁',
          ),
          OgLPermissionRule(
            permission: OgLPermission.backgroundRefresh,
            askKind: OgLAskKind.notRequired,
            denyBehavior: OgLDenyBehavior.degrade,
            consequence: '合上窗口后同步停止（菜单栏常驻可缓解）',
          ),
        ];

      case OgLPlatformKind.web:
      case OgLPlatformKind.other:
        // 不假装知道：未知平台一律"不需要"，绝不凭空索要权限。
        return const <OgLPermissionRule>[];
    }
  }
}

/// 权限状态快照（由平台层采集后交给 UI）。
class OgLPermissionSnapshot {
  /// 创建快照。
  const OgLPermissionSnapshot({
    required this.policy,
    required this.statuses,
  });

  /// 全空快照（启动早期 / 测试）。
  factory OgLPermissionSnapshot.empty(OgLPlatformKind platform) =>
      OgLPermissionSnapshot(
        policy: OgLPermissionPolicy.forPlatform(platform),
        statuses: const <OgLPermission, OgLPermissionStatus>{},
      );

  /// 策略。
  final OgLPermissionPolicy policy;

  /// 已知状态（未采集到的按"未知"处理，而不是按"已授权"）。
  final Map<OgLPermission, OgLPermissionStatus> statuses;

  /// 取状态；**未知时返回 [OgLPermissionStatus.denied]**。
  ///
  /// 这里刻意不用 `granted` 兜底：把"不知道"当成"已授权"，
  /// 会让界面在真正调用系统 API 时才炸——那是用户可见的崩溃。
  OgLPermissionStatus statusOf(OgLPermission permission) =>
      statuses[permission] ?? OgLPermissionStatus.denied;

  /// 该权限当前是否可用。
  bool isUsable(OgLPermission permission) => statusOf(permission).isUsable;

  /// 是否应该发起询问。
  bool shouldPrompt(OgLPermission permission) {
    final rule = policy.ruleFor(permission);
    if (!rule.needsPrompt) {
      return false;
    }
    final status = statusOf(permission);
    return status == OgLPermissionStatus.denied ||
        status == OgLPermissionStatus.permanentlyDenied;
  }

  /// 是否只能去系统设置开（已"不再询问"）。
  bool needsSettingsTrip(OgLPermission permission) =>
      statusOf(permission) == OgLPermissionStatus.permanentlyDenied ||
      policy.ruleFor(permission).askKind == OgLAskKind.systemSettingsOnly;

  /// 拒绝说明（给 UI 直接展示，避免每个页面自己编文案）。
  String consequenceText(OgLPermission permission) =>
      policy.ruleFor(permission).consequence;

  /// 复制一份新的状态。
  OgLPermissionSnapshot withStatus(
    OgLPermission permission,
    OgLPermissionStatus status,
  ) =>
      OgLPermissionSnapshot(
        policy: policy,
        statuses: <OgLPermission, OgLPermissionStatus>{
          ...statuses,
          permission: status,
        },
      );
}

/// 平台权限网关（由平台实现层提供；L3 只依赖这个接口，便于离线测试）。
abstract class OgLPermissionGateway {
  /// 读取当前状态。
  Future<OgLPermissionStatus> statusOf(OgLPermission permission);

  /// 发起询问；返回用户决定后的状态。
  Future<OgLPermissionStatus> request(OgLPermission permission);

  /// 打开系统设置页（"去设置里开"）。
  Future<bool> openSettings(OgLPermission permission);

  /// 采集全部状态。
  Future<Map<OgLPermission, OgLPermissionStatus>> snapshot(
    OgLPermissionPolicy policy,
  );
}