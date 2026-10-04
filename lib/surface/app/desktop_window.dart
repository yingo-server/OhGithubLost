/// L3 展示级 · 桌面窗口（**自绘标题栏** + 原生标题）。
///
/// ## 为什么不用系统默认装饰
/// Windows / Linux 的窗口管理器给的外观（标题栏高度、按钮形状、字体）
/// 与 App 自己的设计语言**完全不是一套**，一眼就能看出"移动端套壳"。
/// 桌面端改为：**隐藏系统标题栏**，自绘一条与 App 同语言的标题栏。
///
/// ## 但原生标题仍然要写对
/// 任务栏、Alt-Tab、任务管理器读的是**原生标题**（不是 Flutter 画的那条）。
/// 因此这里同时 `setTitle('OhGithubLost')`，构建期还会由
/// `tool/inject_desktop_shell.py` 把原生壳的标题也改成同一个值（双保险）。
///
/// ## 允许回退
/// 设置里可以切回**系统默认窗口装饰**（部分 Linux 桌面环境 / 平铺窗口管理器
/// 下，自绘栏反而别扭）。切换即时生效，不需要重启。
///
/// ## 平台
/// 仅桌面（Windows / Linux / macOS）生效；Android / iOS / Web 上
/// 所有函数都是空操作，[OgLWindowFrame] 原样返回子组件。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 当前是否为桌面平台（Windows / Linux / macOS）。
bool get ogLIsDesktopPlatform =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

/// 标题栏高度（自绘）。
const double kOgLTitleBarHeight = 38;

/// 应用窗口装饰模式。
enum OgLWindowDecoration {
  /// 自绘标题栏（默认，外观与 App 一致）。
  custom,

  /// 交还系统默认窗口装饰（用户可在设置里切回）。
  system,
}

/// 首次初始化窗口：标题、装饰模式、最小尺寸。
Future<void> ogLInitDesktopWindow({OgLWindowDecoration decoration = OgLWindowDecoration.custom}) async {
  if (!ogLIsDesktopPlatform) {
    return;
  }
  try {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('OhGithubLost');
    await ogLApplyWindowDecoration(decoration);
  } catch (error) {
    // 桌面环境千差万别（平铺 WM / 精简会话可能不支持）→ 绝不外抛。
    debugPrint('OGL 桌面窗口：初始化失败（已降级为系统装饰）：$error');
  }
}

/// 应用（或回退）窗口装饰。切换即时生效。
Future<void> ogLApplyWindowDecoration(OgLWindowDecoration decoration) async {
  if (!ogLIsDesktopPlatform) {
    return;
  }
  try {
    if (decoration == OgLWindowDecoration.custom) {
      // Windows：保留系统阴影 / 圆角 / 贴边（Aero Snap），只是**不画标题栏**；
      // Linux：整体去掉 GTK 的 CSD，由我们完全自绘。
      if (Platform.isWindows || Platform.isMacOS) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.hidden,
          windowButtonVisibility: false,
        );
      } else {
        await windowManager.setAsFrameless();
      }
    } else {
      // 回退：恢复系统默认标题栏与按钮。
      await windowManager.setAsFrameless(false);
      if (Platform.isWindows || Platform.isMacOS) {
        await windowManager.setTitleBarStyle(
          TitleBarStyle.normal,
          windowButtonVisibility: true,
        );
      }
    }
    await windowManager.setTitle('OhGithubLost');
  } catch (error) {
    debugPrint('OGL 桌面窗口：切换装饰失败：$error');
  }
}

/// 自绘标题栏：拖拽区 + 应用名 + 最小化 / 最大化 / 关闭。
///
/// 用 Material 的 `InkWell` 提供反馈（不引入自定时长，动效门禁安全）。
class OgLTitleBar extends StatefulWidget implements PreferredSizeWidget {
  /// 创建标题栏。
  const OgLTitleBar({super.key, this.title = 'OhGithubLost'});

  /// 标题文案（原生标题由窗口管理器另设）。
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kOgLTitleBarHeight);

  @override
  State<OgLTitleBar> createState() => _OgLTitleBarState();
}

class _OgLTitleBarState extends State<OgLTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    if (ogLIsDesktopPlatform) {
      windowManager.addListener(this);
      _sync();
    }
  }

  @override
  void dispose() {
    if (ogLIsDesktopPlatform) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _sync() async {
    try {
      final bool value = await windowManager.isMaximized();
      if (mounted && value != _maximized) {
        setState(() => _maximized = value);
      }
    } catch (_) {
      // 取不到就保持原状。
    }
  }

  @override
  void onWindowMaximize() => _sync();

  @override
  void onWindowUnmaximize() => _sync();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SizedBox(
        height: kOgLTitleBarHeight,
        child: Row(
          children: <Widget>[
            // 拖拽区：按住标题栏任意空白处拖动窗口；双击切换最大化。
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => windowManager.startDragging(),
                onDoubleTap: () => _toggleMaximize(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.title,
                      key: const ValueKey<String>('ogl_title_bar_title'),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _button(
              context,
              icon: Icons.remove,
              onTap: () => windowManager.minimize(),
            ),
            _button(
              context,
              icon: _maximized ? Icons.filter_none : Icons.crop_square,
              onTap: _toggleMaximize,
            ),
            _button(
              context,
              icon: Icons.close,
              onTap: () => windowManager.close(),
              danger: true,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
      await _sync();
    } catch (_) {
      // 忽略。
    }
  }

  Widget _button(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: kOgLTitleBarHeight,
        child: Icon(
          icon,
          size: 16,
          color: danger ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 桌面窗口外框：把**自绘标题栏**套在整棵界面之上。
///
/// - 非桌面平台 / 选择系统装饰时 → **原样返回**子组件（零开销、零影响）；
/// - 桌面 + 自绘 → `Column(标题栏, Expanded(内容))`。
class OgLWindowFrame extends StatefulWidget {
  /// 创建外框。
  const OgLWindowFrame({
    required this.child,
    this.decoration = OgLWindowDecoration.custom,
    super.key,
  });

  /// 内容。
  final Widget child;

  /// 装饰模式。
  final OgLWindowDecoration decoration;

  @override
  State<OgLWindowFrame> createState() => _OgLWindowFrameState();
}

class _OgLWindowFrameState extends State<OgLWindowFrame> {
  @override
  void initState() {
    super.initState();
    // 首次进入即把窗口设置落实（避免"先闪一下系统标题栏"）。
    ogLInitDesktopWindow(decoration: widget.decoration);
  }

  @override
  void didUpdateWidget(OgLWindowFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.decoration != widget.decoration) {
      ogLApplyWindowDecoration(widget.decoration);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ogLIsDesktopPlatform || widget.decoration != OgLWindowDecoration.custom) {
      return widget.child;
    }
    return Column(
      children: <Widget>[
        const OgLTitleBar(),
        Expanded(child: widget.child),
      ],
    );
  }
}