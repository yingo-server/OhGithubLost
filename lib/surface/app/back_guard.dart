/// L3 展示级 · **返回键统一处理**（安卓返回键 / 系统手势返回）。
///
/// ## 为什么需要它
/// 之前没有任何统一策略：在不同页面按返回，行为不一致——有时直接退出应用，
/// 有时卡在某个 tab 里出不去，抽屉打开时也不会先关抽屉。用户要求：
/// **全局统一处理（含二级页 / 弹窗 / 抽屉）**。
///
/// ## 策略（优先级从上到下）
/// 1. 有可弹出的路由（二级页 / 弹窗）→ 交给 `Navigator` 弹栈；
/// 2. 抽屉/侧边面板打开 → 先关它；
/// 3. 不在首页 tab → 回到首页 tab（**不退出**）；
/// 4. 已在首页 → 第一次提示「再按一次退出」，窗口内再按一次才退出。
///
/// 逻辑（状态机）与 UI 分离，方便单测：见 [OgLBackGuard]。
library;

/// 返回键应当执行的动作。
enum OgLBackAction {
  /// 交给导航器弹栈（二级页 / 弹窗）。
  popRoute,

  /// 先关掉抽屉 / 侧边面板。
  closeDrawer,

  /// 回到首页 tab（不退出应用）。
  goHome,

  /// 第一次按下：提示「再按一次退出」。
  armExit,

  /// 窗口内第二次按下：退出应用。
  exit,
}

/// 返回键状态机（纯逻辑，可单测）。
///
/// 只负责「按一次返回键应该做什么」，不碰 Flutter API：
/// 这样"双击退出"这类时序行为可以在单测里稳定复现。
class OgLBackGuard {
  /// 创建状态机。
  ///
  /// [exitWindow] 为「再按一次退出」的有效窗口。
  OgLBackGuard({this.exitWindow = const Duration(seconds: 2)});

  /// 双击退出的时间窗口。
  final Duration exitWindow;

  DateTime? _armedAt;

  /// 是否已处于「再按一次」的待退出状态（UI 可用它显示提示）。
  bool get armed => _armedAt != null;

  /// 判定本次返回键的动作。
  ///
  /// - [atHome]：当前是否已在首页 tab；
  /// - [drawerOpen]：是否有抽屉/面板开着；
  /// - [now]：当前时间（测试注入，避免依赖真实时钟）。
  OgLBackAction decide({
    required bool atHome,
    required DateTime now,
    bool drawerOpen = false,
  }) {
    if (drawerOpen) {
      _armedAt = null;
      return OgLBackAction.closeDrawer;
    }
    if (!atHome) {
      _armedAt = null;
      return OgLBackAction.goHome;
    }
    final DateTime? armedAt = _armedAt;
    if (armedAt != null && now.difference(armedAt) <= exitWindow) {
      _armedAt = null;
      return OgLBackAction.exit;
    }
    _armedAt = now;
    return OgLBackAction.armExit;
  }

  /// 手动清除待退出状态（例如提示已消失、或用户切了 tab）。
  void reset() => _armedAt = null;
}

/// 提示文案键（`shell` 分片）：再按一次退出。
const String kOgLBackExitHintKey = 'backExitHint';
