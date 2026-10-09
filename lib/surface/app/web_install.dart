/// L3 展示级 · **Web 专属**：添加到桌面（PWA 安装）与 Web 启动偏好。
///
/// ## 三条路径（不是"实现取舍"，是平台差异）
/// 1. **Chromium 家族**（Android Chrome / 桌面 Chrome、Edge…）：浏览器在"应用
///    可安装"时**至多派发一次** `beforeinstallprompt`。本模块第一时间挂上监听
///    把它抓住（错过就没有第二次），用户点"添加"时才调用它的 `prompt()`。
/// 2. **iOS Safari**：**平台压根没有** `beforeinstallprompt`（Safari 至今未实现
///    该 API）。所以只能给"共享 → 添加到主屏幕"的**手动引导文案**，而不是
///    假装能一键安装。
/// 3. **已安装（standalone）**：无论哪条路径都不再提示。
///
/// ## 单一构建目标（本分支 = 纯 Web）
/// 本分支只构建浏览器产物；实现收敛到 `web_install_web.dart`，所有函数按
/// 浏览器真实能力返回结果 —— 不支持的情形（如 iOS Safari 没有安装事件）
/// **如实**报"不支持"，不假装。
///
/// ## 本模块负责什么
/// - 安装提示的**平台判定**与**浏览器动作**（[ogLWebInstall*]）；
/// - 装配层要用的两个持久化开关（[OgLWebStartup]）：`webInstallPromptEnabled`
///   与"加速服务弹窗已读"。
/// - **不负责 UI**：对话框由 `main.dart` 在启动后按这里给出的判定呈现。
library;

import 'package:flutter/foundation.dart';

import 'web_install_web.dart' as impl;

/// Web 安装提示的形态。
enum OgLWebInstallPlatform {
  /// Chromium 家族：支持 `beforeinstallprompt`，可以**一键**安装。
  chromium,

  /// iOS Safari：**平台不支持** `beforeinstallprompt`，只能给手动引导。
  ios,

  /// 其它浏览器：既没有原生安装事件，也不适用 iOS 的引导路径。
  other,

  /// 非浏览器运行环境：本模块整体不生效。
  unsupported,
}

/// 当前运行环境的安装提示形态。
OgLWebInstallPlatform ogLWebInstallPlatform() {
  if (!kIsWeb) {
    return OgLWebInstallPlatform.unsupported;
  }
  // iOS 判定优先：Chrome iOS 的 UA 里也有 "crios"，但它同样没有
  // `beforeinstallprompt`，必须走 iOS 的引导路径（否则会提示了却装不上）。
  if (defaultTargetPlatform == TargetPlatform.iOS) {
    return OgLWebInstallPlatform.ios;
  }
  if (impl.ogLWebInstallChromium()) {
    return OgLWebInstallPlatform.chromium;
  }
  return OgLWebInstallPlatform.other;
}

/// 是否已作为"已安装应用"运行（standalone 显示模式 / iOS 主屏幕）。
///
/// 已安装 = **不再提示**（任何路径都不提示）。
bool ogLWebInstallStandalone() => kIsWeb && impl.ogLWebInstallStandalone();

/// 是否已经抓到可用的 `beforeinstallprompt` 事件（Chromium 才可能为 `true`）。
bool ogLWebInstallCanPrompt() => kIsWeb && impl.ogLWebInstallCanPrompt();

/// 监听 `beforeinstallprompt`。**必须尽早调用**：该事件只派发一次。
///
/// [onAvailable] 在事件到达时回调（此时 [ogLWebInstallCanPrompt] 才为 `true`）。
/// 非浏览器环境里是空操作，不会注册任何东西。
void ogLWebInstallWatch(void Function() onAvailable) {
  if (!kIsWeb) {
    return;
  }
  impl.ogLWebInstallWatch(onAvailable);
}

/// 触发浏览器自带的安装提示。
///
/// 返回 `accepted` / `dismissed`（用户的选择）、`unavailable`（没有可用事件）
/// 或 `error`（调用失败）——**如实返回**，调用方不要把它们当成"成功"。
Future<String> ogLWebInstallPrompt() async {
  if (!kIsWeb) {
    return 'unavailable';
  }
  return impl.ogLWebInstallPrompt();
}

/// Web 启动偏好的持久化接口（由装配层用底座的 KV 实现；测试可注入内存实现）。
abstract class OgLWebPrefsStore {
  /// 读一个键（不存在返回 `null`）。
  Future<String?> read(String key);

  /// 写一个键。
  Future<void> write(String key, String value);
}

/// 内存实现：默认兜底（测试 / 无法落盘的场景），行为与"关掉应用就忘"一致。
class OgLMemoryWebPrefs implements OgLWebPrefsStore {
  /// 创建。
  OgLMemoryWebPrefs();

  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

/// Web 启动偏好：安装提示开关 + "加速服务弹窗已读"标记。
///
/// ## 为什么不用 `OgLSettings`
/// 这两项**只在浏览器里有意义**，塞进通用的 `OgLSettings` 会为其它环境
/// 留下两个永远不生效的字段。这里用独立的存储键，互不干扰。
///
/// ## 非浏览器环境也会被创建
/// 但没有任何代码读取它：设置页只在 [kIsWeb] 时展示对应开关
/// （项目纪律"只留真选项"，不摆一个不生效的假开关）。
class OgLWebStartup extends ChangeNotifier {
  /// 创建。
  OgLWebStartup(this._store);

  /// 「打开时询问添加到桌面」的存储键。
  static const String installPromptKey = 'ogl.web.installPromptEnabled';

  /// 「需要配置加速服务」弹窗的"已读"存储键。
  static const String accelNoticeKey = 'ogl.web.accelNoticeShown';

  /// 「检测到鼠标」交互说明弹窗的"已读"存储键。
  static const String mouseNoticeKey = 'ogl.web.mouseNoticeShown';

  final OgLWebPrefsStore _store;

  bool _installPromptEnabled = true;
  bool _accelNoticeShown = false;
  bool _mouseNoticeShown = false;
  bool _loaded = false;

  /// 是否在每次打开时询问"添加到桌面"（默认**开**）。
  bool get installPromptEnabled => _installPromptEnabled;

  /// "需要配置加速服务"弹窗是否已展示过（只弹一次）。
  bool get accelNoticeShown => _accelNoticeShown;

  /// 「检测到鼠标」说明是否已展示过（只弹一次）。
  bool get mouseNoticeShown => _mouseNoticeShown;

  /// 是否已读过一次持久化值。
  bool get loaded => _loaded;

  /// 读取持久化值。**绝不抛**：读失败就保留默认值（默认 = 开）。
  Future<void> load() async {
    try {
      final String? install = await _store.read(installPromptKey);
      if (install != null) {
        // 只有**明确写入过** `false` 才算关闭；坏值一律维持"开"（保守默认）。
        _installPromptEnabled = install != 'false';
      }
      _accelNoticeShown = await _store.read(accelNoticeKey) == 'true';
      _mouseNoticeShown = await _store.read(mouseNoticeKey) == 'true';
    } catch (error) {
      debugPrint('OGL Web 启动偏好：读取失败，使用默认值（$error）');
    }
    _loaded = true;
    notifyListeners();
  }

  /// 设置"打开时询问添加到桌面"。UI 立即生效；写盘失败不影响本次会话。
  Future<void> setInstallPromptEnabled(bool enabled) async {
    if (_installPromptEnabled == enabled) {
      return;
    }
    _installPromptEnabled = enabled;
    notifyListeners();
    try {
      await _store.write(installPromptKey, enabled ? 'true' : 'false');
    } catch (error) {
      debugPrint('OGL Web 启动偏好：写入失败（$error）');
    }
  }

  /// 标记"加速服务弹窗"已展示（保证只弹一次）。
  Future<void> markAccelNoticeShown() async {
    if (_accelNoticeShown) {
      return;
    }
    _accelNoticeShown = true;
    notifyListeners();
    try {
      await _store.write(accelNoticeKey, 'true');
    } catch (error) {
      debugPrint('OGL Web 启动偏好：写入失败（$error）');
    }
  }

  /// 标记「检测到鼠标」弹窗已展示（保证只弹一次）。
  Future<void> markMouseNoticeShown() async {
    if (_mouseNoticeShown) {
      return;
    }
    _mouseNoticeShown = true;
    notifyListeners();
    try {
      await _store.write(mouseNoticeKey, 'true');
    } catch (error) {
      debugPrint('OGL Web 启动偏好：写入失败（$error）');
    }
  }
}
